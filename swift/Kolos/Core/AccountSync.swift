import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Аккаунт Колоса: вход через Google и синхронизация «Моих данных» (закладки, заметки, любимые, выделения, подборки,
/// проповеди, планы, настройки) с сервером aobible.app/sync — одно и то же на iPhone, Android и в веб-версии.
///
/// Как сходится (так же, как во Flutter-версии): у каждого ключа «Моих данных» запоминаем отпечаток значения на момент
/// последней синхронизации. Изменилось с тех пор — поменяли на этом телефоне, уходит на сервер. Пришло новое с сервера,
/// а здесь не трогали — берём серверное. Поменяли и там, и здесь — объединяем: записи списков (закладки, проповеди,
/// планы) и словарей (заметки, выделения, настройки) складываются, совпадающие — с этого телефона.
/// Модули, место чтения и язык не переносятся.
@MainActor
final class AccountSync: ObservableObject {
    static let shared = AccountSync()
    static let base = "https://aobible.app/sync"
    /// Клиент OAuth Google для iPhone (…apps.googleusercontent.com). Пусто — вход ещё не настроен
    static let iosClientId = ""

    private static let stateKey = "syncState"
    /// Не переносятся между устройствами: место чтения, язык, запрос поиска
    private static let localOnly: Set<String> = ["panes", "lang", "searchQuery", "syncState"]

    struct State: Codable {
        var token: String?
        var email: String?
        var name: String?
        var rev = 0
        var prints: [String: String] = [:]
        var lastSync: Double?
        var error: String?
    }

    @Published private(set) var state: State
    @Published private(set) var busy = false

    private weak var marks: MarksStore?
    private weak var plans: PlansStore?
    private weak var sermons: SermonStore?
    private var running: Task<Bool, Never>?
    private var lastAuto = Date.distantPast

    var signedIn: Bool { state.token != nil }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.stateKey), let s = try? JSONDecoder().decode(State.self, from: d) {
            state = s
        } else {
            state = State()
        }
    }

    private func save(_ s: State) {
        state = s
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.stateKey) }
    }

    /// Запуск приложения: хранилища, в которые приходят данные, и первая синхронизация
    func attach(marks: MarksStore, plans: PlansStore, sermons: SermonStore) {
        self.marks = marks
        self.plans = plans
        self.sermons = sermons
    }

    /// Вернулись в приложение — свести данные (не чаще раза в минуту); ушли — отправить сделанное
    func onPhase(active: Bool) {
        guard signedIn else { return }
        if active {
            guard Date().timeIntervalSince(lastAuto) > 60 else { return }
            lastAuto = Date()
        }
        Task { await sync() }
    }

    // MARK: - Отпечаток и объединение

    /// FNV-1a: одинаков на всех запусках
    static func fp(_ s: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for c in s.utf16 {
            h ^= UInt32(c)
            h = h &* 0x01000193
        }
        return "\(s.utf16.count):\(String(h, radix: 16))"
    }

    /// Одна и та же запись списка на разных устройствах: по id / key, по месту (книга, глава, стих), иначе целиком
    static func identity(_ x: Any) -> String {
        if let m = x as? [String: Any] {
            for k in ["id", "key", "uid"] {
                if let v = m[k], !(v is NSNull) { return "\(k):\(v)" }
            }
            if let b = m["book"] {
                return "ref:\(b).\(m["chapter"] ?? "").\(m["verse"] ?? "").\(m["from"] ?? "").\(m["to"] ?? "")"
            }
            if let r = m["ref"] as? [String: Any] {
                return "ref:\(r["book"] ?? "").\(r["chapter"] ?? "").\(r["verse"] ?? "")"
            }
        }
        if let d = try? JSONSerialization.data(withJSONObject: x, options: [.sortedKeys, .fragmentsAllowed]), let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "\(x)"
    }

    static func merge(_ l: Any, _ r: Any) -> Any {
        if let lm = l as? [String: Any], let rm = r as? [String: Any] {
            var out = rm
            for (k, v) in lm { out[k] = out[k].map { merge(v, $0) } ?? v }
            return out
        }
        if let la = l as? [Any], let ra = r as? [Any] {
            var seen = Set<String>()
            var out: [Any] = []
            for x in la + ra where seen.insert(identity(x)).inserted { out.append(x) }
            return out
        }
        return l
    }

    /// Значение, изменённое и здесь, и на другом устройстве: записи складываются, совпадающие — с этого телефона
    static func mergeValues(_ local: String, _ remote: String) -> String {
        guard let l = try? JSONSerialization.jsonObject(with: Data(local.utf8), options: [.fragmentsAllowed]),
              let r = try? JSONSerialization.jsonObject(with: Data(remote.utf8), options: [.fragmentsAllowed]) else { return local }
        let m = merge(l, r)
        guard let d = try? JSONSerialization.data(withJSONObject: m, options: [.fragmentsAllowed]), let s = String(data: d, encoding: .utf8) else { return local }
        return s
    }

    // MARK: - Сервер

    enum SyncError: Error {
        case auth
        case server(String)
    }

    private func call(_ method: String, _ path: String, token: String?, body: Any? = nil) async throws -> [String: Any] {
        guard let url = URL(string: Self.base + path) else { throw SyncError.server("url") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if code == 401 && path != "/login" { throw SyncError.auth }
        guard code == 200 else { throw SyncError.server((j["error"] as? String) ?? "\(code)") }
        return j
    }

    private static func errorCode(_ e: Error) -> String {
        if case SyncError.server(let s) = e { return s }
        if e is URLError { return "offline" }
        return "\(e.localizedDescription)"
    }

    // MARK: - Синхронизация

    /// Свести данные телефона и аккаунта. true — данные на телефоне поменялись (хранилища уже обновлены)
    @discardableResult
    func sync() async -> Bool {
        guard signedIn else { return false }
        if let r = running { return await r.value }
        let t = Task { await self.run() }
        running = t
        let v = await t.value
        running = nil
        return v
    }

    private func syncable(_ k: String) -> Bool { !Self.localOnly.contains(k) }

    private func collect() -> [String: String]? {
        guard let marks, let plans, let sermons else { return nil }
        return UserData.collect(marks: marks, plans: plans, sermons: sermons).filter { syncable($0.key) }
    }

    private func applyAll(_ local: [String: String]) {
        guard let marks, let plans, let sermons else { return }
        // полный набор: свои ключи, не переносимые между устройствами (панели, язык), остаются как были
        var full = UserData.collect(marks: marks, plans: plans, sermons: sermons)
        for k in full.keys where syncable(k) && local[k] == nil { full.removeValue(forKey: k) }
        for (k, v) in local { full[k] = v }
        UserData.apply(full, marks: marks, plans: plans, sermons: sermons)
    }

    private func run() async -> Bool {
        guard var local = collect() else { return false }
        busy = true
        var st = state
        var changed = false
        /// ключи, взятые с сервера как есть (после записи в хранилища их отпечаток — как их выгружает этот телефон)
        var taken = Set<String>()

        /// Запись с сервера (nil — удалена там)
        func applyRemote(_ key: String, _ remote: String?) {
            guard syncable(key) else { return }
            let mine = local[key]
            let last = st.prints[key]
            let localChanged = mine == nil ? last != nil : Self.fp(mine!) != last
            if !localChanged {
                // здесь не трогали — берём с сервера
                if let remote {
                    st.prints[key] = Self.fp(remote)
                    if mine != remote {
                        local[key] = remote
                        taken.insert(key)
                        changed = true
                    }
                } else {
                    st.prints.removeValue(forKey: key)
                    if mine != nil {
                        local.removeValue(forKey: key)
                        changed = true
                    }
                }
                return
            }
            guard let remote else {
                // там удалили, здесь изменили — изменённое важнее: уйдёт на сервер снова
                st.prints.removeValue(forKey: key)
                return
            }
            guard let mine else {
                // здесь удалили, там изменили — ничего не теряем: берём изменённое
                st.prints[key] = Self.fp(remote)
                local[key] = remote
                taken.insert(key)
                changed = true
                return
            }
            let merged = Self.mergeValues(mine, remote)
            // отпечаток — серверного значения: объединённое от него отличается и уйдёт на сервер
            st.prints[key] = Self.fp(remote)
            if merged != mine {
                local[key] = merged
                changed = true
            }
        }

        /// Записать пришедшее в хранилища; у взятых как есть отпечаток — как их теперь выгружает телефон
        func store() {
            guard changed else { return }
            applyAll(local)
            if let now = collect() {
                for k in taken { if let v = now[k] { st.prints[k] = Self.fp(v) } }
                local = now
            }
            taken.removeAll()
        }

        do {
            // 1. Забрать новое с сервера
            var since = st.rev
            while true {
                let r = try await call("GET", "/pull?since=\(since)", token: st.token)
                for it in (r["items"] as? [[String: Any]]) ?? [] {
                    guard let k = it["key"] as? String else { continue }
                    applyRemote(k, (it["deleted"] as? Bool) == true ? nil : it["value"] as? String)
                }
                since = (r["rev"] as? NSNumber)?.intValue ?? since
                if (r["more"] as? Bool) != true { break }
            }
            st.rev = since
            store()

            // 2. Отправить изменённое здесь (что сервер не принял, потому что у него новее, — объединить и снова)
            for _ in 0..<3 {
                let now = Date().timeIntervalSince1970 * 1000
                var items: [[String: Any]] = []
                for (k, v) in local where st.prints[k] != Self.fp(v) { items.append(["key": k, "value": v, "updated": now]) }
                for k in st.prints.keys where local[k] == nil && syncable(k) { items.append(["key": k, "deleted": true, "updated": now]) }
                if items.isEmpty { break }
                var again = false
                var i = 0
                while i < items.count {
                    let part = Array(items[i..<min(i + 200, items.count)])
                    i += 200
                    let r = try await call("POST", "/push", token: st.token, body: ["items": part])
                    let applied = Set(((r["applied"] as? [Any]) ?? []).compactMap { $0 as? String })
                    for it in part {
                        guard let k = it["key"] as? String, applied.contains(k) else { continue }
                        if (it["deleted"] as? Bool) == true {
                            st.prints.removeValue(forKey: k)
                        } else if let v = it["value"] as? String {
                            st.prints[k] = Self.fp(v)
                        }
                    }
                    for it in (r["newer"] as? [[String: Any]]) ?? [] {
                        guard let k = it["key"] as? String else { continue }
                        applyRemote(k, (it["deleted"] as? Bool) == true ? nil : it["value"] as? String)
                        again = true
                    }
                }
                store()
                if !again { break }
            }
            st.lastSync = Date().timeIntervalSince1970 * 1000
            st.error = nil
        } catch SyncError.auth {
            // вход больше не действует (вышли на другом устройстве, аккаунт удалён) — данные телефона остаются
            st.token = nil
            st.error = "auth"
        } catch {
            st.error = Self.errorCode(error)
        }
        save(st)
        busy = false
        return changed
    }

    // MARK: - Вход и выход

    /// Вход через Google. nil — вошли (и данные уже сведены), иначе код ошибки
    func signIn() async -> String? {
        guard !Self.iosClientId.isEmpty else { return "not-configured" }
        guard let marks, let plans, let sermons else { return "not-ready" }
        do {
            let idToken = try await GoogleAuth().idToken(clientId: Self.iosClientId)
            let r = try await call("POST", "/login", token: nil, body: ["idToken": idToken, "device": "iPhone"])
            // первое объединение с аккаунтом: прежде — копия данных телефона (её можно вернуть в «Моих данных»)
            UserData.snapshot("перед первой синхронизацией с аккаунтом", marks: marks, plans: plans, sermons: sermons)
            let user = r["user"] as? [String: Any]
            save(State(token: r["token"] as? String, email: user?["email"] as? String, name: user?["name"] as? String))
            await sync()
            return state.error
        } catch GoogleAuth.Failure.canceled {
            return "canceled"
        } catch GoogleAuth.Failure.google {
            return "google"
        } catch {
            return Self.errorCode(error)
        }
    }

    /// Выйти на этом телефоне: данные остаются и здесь, и в аккаунте
    func signOut() async {
        if let t = state.token { _ = try? await call("POST", "/logout", token: t) }
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
        state = State()
    }

    /// Удалить аккаунт и все его данные на сервере (на телефоне данные остаются). nil — удалено
    func deleteAccount() async -> String? {
        guard let t = state.token else { return nil }
        do {
            _ = try await call("DELETE", "/account", token: t)
        } catch SyncError.auth {
            // уже удалён
        } catch {
            return Self.errorCode(error)
        }
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
        state = State()
        return nil
    }
}

/// Вход через Google без их библиотеки: страница входа в системном окне (ASWebAuthenticationSession), код → ID-токен
/// (OAuth с PKCE, клиент «iOS» без секрета). Работает и в приложении, поставленном не из App Store
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: Error {
        case canceled
        case google
    }

    private var session: ASWebAuthenticationSession?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func idToken(clientId: String) async throws -> String {
        // «123-abc.apps.googleusercontent.com» → схема возврата «com.googleusercontent.apps.123-abc»
        let scheme = clientId.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(scheme):/oauth2redirect"
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Self.b64url(Data(bytes))
        let challenge = Self.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = c.url else { throw Failure.google }
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: Failure.canceled)
                } else {
                    cont.resume(throwing: Failure.google)
                }
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw Failure.google
        }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        let form: [String: String] = [
            "code": code, "client_id": clientId, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier,
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let token = j["id_token"] as? String else {
            throw Failure.google
        }
        return token
    }
}
