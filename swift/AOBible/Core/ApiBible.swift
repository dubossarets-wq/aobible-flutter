import Foundation

// Переводы API.Bible: не скачиваются, а читаются по сети через наш посредник (aobible.app/bapi, ключ — на сервере).
// «Добавить» создаёт модуль без текста (список книг); главы приходят по одной, когда их открывают, и хранятся в базе
// перевода недолго — по условиям API.Bible не больше 480 стихов подряд и не дольше 14 дней. Порт lib/core/apibible.dart.

enum OnlineError: Error {
    case limit // исчерпан месячный лимит API.Bible
    case net // нет связи

    var message: String {
        switch self {
        case .limit: return String(localized: "Переводы по сети сейчас недоступны: исчерпан месячный лимит запросов. Выберите скачанный перевод или загляните позже.")
        case .net: return String(localized: "Нет связи: этот перевод читается по сети. Подключитесь к интернету или выберите скачанный перевод.")
        }
    }
}

enum ApiBible {
    static let bases = ["https://aobible.app/bapi", "https://aobible-apibible.apibible.workers.dev"]
    static let keepVerses = 480
    static let keepDays = 14

    private static let osisToUsfm: [String: String] = Dictionary(usfmToOsis.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
    private static let order: [String: Int] = {
        // порядок книг — как в списке USFM из Flutter-версии (словарь не упорядочен, поэтому берём порядок Bible)
        var o: [String: Int] = [:]
        for (i, b) in Books.all.enumerated() { o[b.id] = i }
        return o
    }()

    /// Модуль без текста: только список книг (modules/api/ID.json: {"books": {"Gen": 50, …}})
    static func module(entry: [String: Any], books: [String: Any]) -> [String: Any] {
        let counts = (books["books"] as? [String: Any]) ?? [:]
        var list: [[String: Any]] = []
        for (id, n) in counts {
            let info = Books.info(id)
            let chapters = max(1, (n as? Int) ?? 1)
            list.append(["id": id, "name": info?.name ?? id, "short": info?.short ?? id, "chapters": Array(repeating: [String](), count: chapters)])
        }
        list.sort { (order[$0["id"] as? String ?? ""] ?? 999) < (order[$1["id"] as? String ?? ""] ?? 999) }
        return [
            "format": "aob-module",
            "type": "bible",
            "id": entry["id"] as? String ?? "",
            "name": entry["name"] as? String ?? "",
            "title": entry["title"] as? String ?? "",
            "description": entry["description"] as? String ?? "",
            "language": entry["language"] as? String ?? "en",
            "license": entry["license"] as? String ?? "",
            "source": entry["source"] as? String ?? "",
            "versification": "synodal",
            "online": entry["online"] as Any,
            "books": list,
        ]
    }

    // MARK: - Разбор главы (JSON API.Bible) → стихи с разметкой приложения

    private static let headStyles = try! NSRegularExpression(pattern: "^(s\\d?|ms\\d?|mr|sr|d|sp|qa|r)$")
    private static let addedStyles: Set<String> = ["add", "it"] // слова, добавленные переводчиками (курсив) → ‹…›
    private static let spaces = try! NSRegularExpression(pattern: "\\s+")
    private static let angle = try! NSRegularExpression(pattern: "›\\s*‹")

    static func parseChapter(_ content: [Any]) -> (verses: [String], heads: [Int: String], title: String) {
        var v: [String] = []
        var h: [Int: String] = [:]
        var head: [String] = []
        var title = "" // надписание псалма (стиль d до первого стиха)

        func text(_ n: [String: Any]) -> String {
            if n["type"] as? String == "text" { return n["text"] as? String ?? "" }
            return (n["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map { text($0) }.joined()
        }
        func walk(_ n: [String: Any], _ added: Bool) {
            if n["type"] as? String == "text" {
                let id = (n["attrs"] as? [String: Any])?["verseId"] as? String
                let num = id.flatMap { Int($0.split(separator: ".").last ?? "") } ?? 0
                if num < 1 { return }
                while v.count < num { v.append("") }
                let s = (n["text"] as? String ?? "").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
                v[num - 1] += added ? "‹\(s)›" : s
                return
            }
            let name = n["name"] as? String
            let attrs = n["attrs"] as? [String: Any]
            if name == "verse" {
                let raw = "\(attrs?["number"] ?? "")"
                let num = Int(raw.split(separator: "-").first ?? "") ?? 0
                if num > 0, !head.isEmpty {
                    h[num] = head.joined(separator: " ")
                    head = []
                }
                return
            }
            if name == "note" { return }
            let style = attrs?["style"] as? String ?? ""
            if name == "para", headStyles.firstMatch(in: style, range: NSRange(location: 0, length: (style as NSString).length)) != nil {
                let s = text(n).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty, style == "d", v.isEmpty {
                    title = s
                } else if !s.isEmpty {
                    head.append(s)
                }
                return
            }
            for x in (n["items"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                walk(x, added || (name == "char" && addedStyles.contains(style)))
            }
        }
        for n in content.compactMap({ $0 as? [String: Any] }) { walk(n, false) }
        for i in v.indices {
            var s = v[i]
            s = spaces.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            s = angle.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            v[i] = s.trimmingCharacters(in: .whitespaces)
        }
        return (v, h, title)
    }

    // MARK: - Сеть

    /// Глава API (западная нумерация) → её JSON-данные
    static func fetch(api: String, code: String, chapter: Int) async throws -> [String: Any] {
        let q = "content-type=json&include-notes=false&include-titles=true&include-chapter-numbers=false&include-verse-numbers=true&include-verse-spans=false"
        for base in bases {
            guard let url = URL(string: "\(base)/bibles/\(api)/chapters/\(code).\(chapter)?\(q)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 429 || status == 403 { throw OnlineError.limit }
                if status != 200 { throw OnlineError.net }
                guard let j = (try JSONSerialization.jsonObject(with: data)) as? [String: Any], let d = j["data"] as? [String: Any] else { throw OnlineError.net }
                return d
            } catch let e as OnlineError {
                throw e // сервер ответил — второй адрес не поможет
            } catch {
                continue // нет связи с этим адресом — следующий
            }
        }
        throw OnlineError.net
    }

    static func usfm(_ book: String) -> String? { osisToUsfm[book] }
}

extension ModuleStore {
    /// Есть ли глава в базе перевода
    func hasChapter(_ moduleId: String, _ book: String, _ chapter: Int) -> Bool {
        guard let d = db(moduleId) else { return false }
        return !d.query("SELECT 1 FROM verses WHERE book = ? AND chapter = ? LIMIT 1", [book, chapter]) { $0.int(0) }.isEmpty
    }

    /// Авторские права перевода (приходят вместе с главой)
    func onlineCopyright(_ moduleId: String) -> String {
        guard let d = db(moduleId) else { return "" }
        return d.query("SELECT value FROM meta WHERE key = 'copyright'") { $0.text(0) }.first ?? ""
    }

    /// Загрузить главу перевода API.Bible (если её ещё нет) и записать в базу перевода
    func loadOnlineChapter(_ moduleId: String, _ book: String, _ chapter: Int) async throws {
        guard let m = module(moduleId), m.online, !hasChapter(moduleId, book, chapter) else { return }
        guard let raw = try? SQLiteDB(path: m.path, readOnly: true).query("SELECT value FROM meta WHERE key = 'json'", [], { $0.text(0) }).first,
              let j = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
              let api = (j["online"] as? [String: Any])?["api"] as? String,
              let code = ApiBible.usfm(book) else { throw OnlineError.net }
        // глава в синодальной нумерации — из одной или двух глав API (в нём западная нумерация)
        var v: [String] = []
        var h: [Int: String] = [:]
        var copyright = ""
        for kc in Versification.westernChapters(for: book, chapter) {
            let data = try await ApiBible.fetch(api: api, code: code, chapter: kc)
            let parsed = ApiBible.parseChapter(data["content"] as? [Any] ?? [])
            Versification.place(book, kc: kc, verses: parsed.verses, heads: parsed.heads, target: chapter, into: &v, headings: &h, title: parsed.title)
            if copyright.isEmpty { copyright = data["copyright"] as? String ?? "" }
        }
        try store(path: m.path, book: book, chapter: chapter, verses: v, heads: h, copyright: copyright)
        forgetCached(moduleId)
    }

    /// Запись главы; старые главы уходят, пока в базе больше keepVerses стихов или они старше keepDays дней
    private func store(path: String, book: String, chapter: Int, verses: [String], heads: [Int: String], copyright: String) throws {
        let db = try SQLiteDB(path: path, readOnly: false)
        try db.exec("CREATE TABLE IF NOT EXISTS online(book TEXT, chapter INTEGER, at INTEGER, n INTEGER, PRIMARY KEY(book, chapter))")
        try db.exec("BEGIN")
        var id = db.query("SELECT MAX(id) FROM verses", [], { $0.int(0) }).first ?? 0
        var rows: [[Any]] = []
        for (i, text) in verses.enumerated() where !text.isEmpty {
            id += 1
            rows.append([id, book, chapter, i + 1, text])
        }
        if !rows.isEmpty { try db.insert("INSERT INTO verses VALUES (?, ?, ?, ?, ?)", rows) }
        let hrows: [[Any]] = heads.map { [book, chapter, $0.key, $0.value] }
        if !hrows.isEmpty { try db.insert("INSERT INTO headings VALUES (?, ?, ?, ?)", hrows) }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        try db.insert("INSERT OR REPLACE INTO online VALUES (?, ?, ?, ?)", [[book, chapter, now, verses.count]])
        if !copyright.isEmpty { try db.insert("INSERT OR REPLACE INTO meta VALUES ('copyright', ?)", [[copyright]]) }
        var total = 0
        let all = db.query("SELECT book, chapter, at, n FROM online ORDER BY at DESC", [], { (b: $0.text(0), c: $0.int(1), at: $0.int(2), n: $0.int(3)) })
        for r in all {
            total += r.n
            let old = now - r.at > ApiBible.keepDays * 86_400_000
            let fresh = r.b == book && r.c == chapter
            if !fresh && (total > ApiBible.keepVerses || old) {
                try db.exec("DELETE FROM verses WHERE book = '\(r.b)' AND chapter = \(r.c)")
                try db.exec("DELETE FROM headings WHERE book = '\(r.b)' AND chapter = \(r.c)")
                try db.exec("DELETE FROM online WHERE book = '\(r.b)' AND chapter = \(r.c)")
            }
        }
        try db.exec("COMMIT")
    }
}
