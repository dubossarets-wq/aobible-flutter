import Foundation
import SwiftUI

enum Net {
    static let bases = ["https://aobible.app/", "https://dubossarets-wq.github.io/ao-bible/"]

    static func fetch(_ path: String) async throws -> Data {
        var lastError: Error = URLError(.badServerResponse)
        for base in bases {
            guard let url = URL(string: base + path) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return data }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func json(_ path: String) async -> [String: Any]? {
        guard let d = try? await fetch(path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}

struct PlanMeta: Identifiable {
    let json: [String: Any]
    var id: String { json["id"] as? String ?? "" }
    var name: String { json["name"] as? String ?? id }
    var file: String { json["file"] as? String ?? "" }
    var days: Int { json["days"] as? Int ?? 0 }
    var short: String? { json["short"] as? String }
    var description: String? { json["description"] as? String }
}

/// Планы чтения и учёт прочитанного: два файла в «Application Support». Если файлов ещё нет, но есть данные
/// Flutter-версии (тот же контейнер), они подхватываются
@MainActor
final class PlansStore: ObservableObject {
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var log = ReadLogData()
    private let plansURL: URL
    private let logURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        plansURL = base.appendingPathComponent("plans.json")
        logURL = base.appendingPathComponent("readlog.json")

        if let d = try? Data(contentsOf: plansURL), let p = try? JSONDecoder().decode([Plan].self, from: d) {
            plans = p
        } else if let s = UserDefaults.standard.string(forKey: "flutter.plans"),
                  let d = s.data(using: .utf8),
                  let p = try? JSONDecoder().decode([Plan].self, from: d) {
            plans = p
        }
        if let d = try? Data(contentsOf: logURL), let l = try? JSONDecoder().decode(ReadLogData.self, from: d) {
            log = l
        } else if let s = UserDefaults.standard.string(forKey: "flutter.readLog"),
                  let d = s.data(using: .utf8),
                  let l = try? JSONDecoder().decode(ReadLogData.self, from: d) {
            log = l
        }
        plans = PlanLogic.applyNewYear(plans)
        savePlans()
    }

    private func savePlans() {
        if let d = try? JSONEncoder().encode(plans) { try? d.write(to: plansURL, options: .atomic) }
        Reminders.schedule(plans)
    }

    private func saveLog() {
        if let d = try? JSONEncoder().encode(log) { try? d.write(to: logURL, options: .atomic) }
    }

    /// Файл «Мои данные»: планы и история чтения (строки JSON, как в localStorage веб-версии)
    func exportEntries() -> [String: String] {
        func js<T: Encodable>(_ v: T) -> String {
            String(data: (try? JSONEncoder().encode(v)) ?? Data("null".utf8), encoding: .utf8) ?? "null"
        }
        return ["plans": js(plans), "readLog": js(log)]
    }

    func importEntries(_ d: [String: String]) {
        if let s = d["plans"], let x = s.data(using: .utf8), let p = try? JSONDecoder().decode([Plan].self, from: x) {
            plans = PlanLogic.applyNewYear(p)
        } else {
            plans = []
        }
        if let s = d["readLog"], let x = s.data(using: .utf8), let l = try? JSONDecoder().decode(ReadLogData.self, from: x) {
            log = l
        } else {
            log = ReadLogData()
        }
        savePlans()
        saveLog()
    }

    func add(_ p: Plan) {
        plans.insert(p, at: 0)
        savePlans()
    }

    func remove(_ uid: String) {
        plans.removeAll { $0.uid == uid }
        savePlans()
    }

    /// Отметить отрывки дня прочитанными; true — день завершён
    @discardableResult
    func mark(uid: String, day: Int, keys: [String]) -> Bool {
        let r = PlanLogic.markUnits(plans, uid: uid, day: day, keys: keys)
        plans = r.plans
        savePlans()
        return r.finished
    }

    /// Глава дочитана: записать в историю чтения и засчитать в планы
    func chapterRead(book: String, chapter: Int) -> (credited: [String], finished: [String]) {
        let day = PlanLogic.localDate()
        let key = "\(book).\(chapter)"
        var list = log.days[day] ?? []
        if !list.contains(key) {
            list.append(key)
            log.days[day] = list
            saveLog()
        }
        let r = PlanLogic.creditChapter(plans, book: book, chapter: chapter)
        if !r.credited.isEmpty {
            plans = r.plans
            savePlans()
        }
        return (r.credited, r.finished)
    }
}

// MARK: - Стих дня

struct DayVerse {
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
    let module: InstalledModule
}

enum VerseOfDay {
    /// 366 известных стихов (ссылки в синодальной нумерации) — тот же список, что у Flutter-версии
    static let list: [String] = {
        guard let url = Bundle.main.url(forResource: "verses_of_day", withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }()

    static func dayOfYear(_ d: Date = Date()) -> Int {
        (Calendar.current.ordinality(of: .day, in: .year, for: d) ?? 1) - 1
    }

    /// Стих на дату: в один день у всех один стих; за год перебираются все без повторов
    static func key(_ d: Date = Date()) -> String? {
        let n = list.count
        guard n > 0 else { return nil }
        let y = Calendar.current.component(.year, from: d)
        return list[(dayOfYear(d) * 151 + (y % n) * 59) % n]
    }

    static func parse(_ k: String) -> (String, Int, Int)? {
        let p = k.split(separator: ".").map(String.init)
        guard p.count == 3, let c = Int(p[1]), let v = Int(p[2]) else { return nil }
        return (p[0], c, v)
    }

    /// Текст стиха на дату. Если в установленных переводах его нет (например, только Новый Завет) — следующий стих списка
    @MainActor
    static func load(store: ModuleStore, preferred: String) -> DayVerse? {
        var mods: [InstalledModule] = []
        if let m = store.module(preferred) { mods.append(m) }
        for m in store.bibles where !mods.contains(where: { $0.id == m.id }) { mods.append(m) }
        let own = mods.filter { $0.language == "ru" }
        mods = own.isEmpty ? mods : own
        guard let first = key(), let start = list.firstIndex(of: first) else { return nil }
        for k in 0..<40 {
            guard let (b, c, v) = parse(list[(start + k) % list.count]) else { continue }
            for m in mods {
                if let t = store.verseText(module: m.id, book: b, chapter: c, verse: v)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    return DayVerse(book: b, chapter: c, verse: v, text: t, module: m)
                }
            }
        }
        return nil
    }
}

extension ModuleStore {
    /// Главы книг по порядку: [(ссылка «Isa.1», число стихов)] — для своего плана
    func chapterList(module m: InstalledModule, books: [String]) -> [(ref: String, n: Int)] {
        guard let d = db(m.id) else { return [] }
        var out: [(ref: String, n: Int)] = []
        for b in books {
            let rows = d.query("SELECT chapter, COUNT(*) FROM verses WHERE book = ? GROUP BY chapter ORDER BY chapter", [b]) {
                (ref: "\(b).\($0.int(0))", n: $0.int(1))
            }
            out.append(contentsOf: rows)
        }
        return out
    }
}
