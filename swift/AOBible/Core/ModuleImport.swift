import Foundation

/// Импорт модулей из файла: кроме родного aob-module понимаются распространённые форматы — массив книг с главами,
/// плоский список стихов, словарь Стронга {"H1": …} и список слов. Всё приводится к aob-module (порт module_import.dart)
struct ImportError: Error {
    let message: String
}

enum ModuleImport {
    /// Порядок книг в западных (протестантских) изданиях — для форматов, где книга задана номером
    private static let western = [
        "Gen", "Exod", "Lev", "Num", "Deut", "Josh", "Judg", "Ruth", "1Sam", "2Sam", "1Kgs", "2Kgs", "1Chr", "2Chr",
        "Ezra", "Neh", "Esth", "Job", "Ps", "Prov", "Eccl", "Song", "Isa", "Jer", "Lam", "Ezek", "Dan", "Hos", "Joel",
        "Amos", "Obad", "Jonah", "Mic", "Nah", "Hab", "Zeph", "Hag", "Zech", "Mal", "Matt", "Mark", "Luke", "John",
        "Acts", "Rom", "1Cor", "2Cor", "Gal", "Eph", "Phil", "Col", "1Thess", "2Thess", "1Tim", "2Tim", "Titus", "Phlm",
        "Heb", "Jas", "1Pet", "2Pet", "1John", "2John", "3John", "Jude", "Rev",
    ]

    private static func strongKey(_ k: String) -> Bool {
        k.range(of: "^[HG]\\d+[a-z]?$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func slug(_ s: String) -> String {
        let v = s.lowercased().replacingOccurrences(of: "[^a-z0-9а-яё]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
        let cut = String(v.prefix(48))
        return cut.isEmpty ? "module" : cut
    }

    private static func resolveBook(_ b: Any?, index: Int?) -> String? {
        if let n = b as? Int { return n >= 1 && n <= western.count ? western[n - 1] : nil }
        if let s = b as? String {
            if let n = Int(s) { return n >= 1 && n <= western.count ? western[n - 1] : nil }
            return Books.info(s) != nil ? s : RefParser.findBook(s)
        }
        if let i = index, i < western.count { return western[i] }
        return nil
    }

    private static func verseText(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let m = v as? [String: Any] { return (m["text"] as? String) ?? (m["t"] as? String) ?? "" }
        return "\(v)"
    }

    /// Формат файла: books-array | flat-verses | strongs-map | word-list; nil — не из поддерживаемых
    static func detect(_ json: Any) -> String? {
        if let list = json as? [Any], let f = list.first as? [String: Any] {
            if f["chapters"] is [Any] { return "books-array" }
            if f["chapter"] != nil, f["verse"] != nil, f["text"] != nil { return "flat-verses" }
            if (f["word"] != nil || f["term"] != nil || f["topic"] != nil) && (f["definition"] != nil || f["text"] != nil || f["description"] != nil) { return "word-list" }
        }
        if let m = json as? [String: Any] {
            if let flat = m["verses"] as? [Any], let f = flat.first as? [String: Any], f["chapter"] != nil, f["verse"] != nil, f["text"] != nil { return "flat-verses" }
            let keys = Array(m.keys.prefix(50))
            if !keys.isEmpty, keys.allSatisfy({ strongKey($0) }) { return "strongs-map" }
        }
        return nil
    }

    /// Приведение к aob-module; ошибка — понятное сообщение
    static func normalize(_ json: Any, fileName: String) throws -> [String: Any] {
        guard let format = detect(json) else {
            throw ImportError(message: String(localized: "Это не модуль Колоса (нужен файл формата aob-module)."))
        }
        let base = fileName.replacingOccurrences(of: "(\\.(json|gz))+$", with: "", options: [.regularExpression, .caseInsensitive])
        let src = json as? [String: Any] ?? [:]
        func pick(_ l: [Any?]) -> String {
            for x in l { if let s = x as? String, !s.isEmpty { return s } }
            return ""
        }
        let name = pick([src["name"], src["abbreviation"], base, "Module"])
        var meta: [String: Any] = [
            "format": "aob-module", "formatVersion": 1,
            "id": slug(pick([src["id"], base, src["name"]])),
            "name": String(name.prefix(40)),
            "title": pick([src["title"], src["name"], base]),
            "description": pick([src["description"]]),
            "language": pick([src["language"], src["lang"], "ru"]),
            "author": pick([src["author"]]),
            "source": pick([src["source"], fileName]),
            "license": pick([src["license"], "—"]),
            "versification": pick([src["versification"], "synodal"]),
            "origin": "file",
        ]
        if format == "strongs-map" || format == "word-list" {
            meta["type"] = "dictionary"
            meta["dictionaryKind"] = format == "strongs-map" ? "strongs" : "words"
            meta["entries"] = try dictionary(json, format)
        } else {
            meta["type"] = "bible"
            let books = try bible(json, format)
            meta["books"] = books
            let hasStrongs = books.contains { b in
                (b["chapters"] as? [[String]] ?? []).contains { $0.contains { $0.contains("{") } }
            }
            meta["features"] = ["strongs": hasStrongs]
        }
        return meta
    }

    private static func bible(_ json: Any, _ format: String) throws -> [[String: Any]] {
        var books: [[String: Any]] = []
        func push(_ id: String, _ src: [String: Any]?, _ chapters: [[String]]) {
            let info = Books.info(id)
            books.append([
                "id": id,
                "name": (src?["name"] as? String) ?? info?.name ?? id,
                "short": (src?["short"] as? String) ?? info?.short ?? id,
                "t": ["OT", "NT", "AP"].contains(src?["t"] as? String ?? "") ? (src?["t"] as? String ?? "AP") : (info?.t ?? "AP"),
                "chapters": chapters,
                "headings": src?["headings"] as? [String: Any] ?? [:],
                "xrefs": src?["xrefs"] as? [String: Any] ?? [:],
            ])
        }
        if format == "books-array" {
            let list = json as? [Any] ?? []
            for (i, any) in list.enumerated() {
                guard let b = any as? [String: Any], let ch = b["chapters"] as? [Any] else { continue }
                let raw = b["id"] ?? b["osis"]
                var id = resolveBook(raw ?? b["name"] ?? b["abbrev"], index: raw != nil || b["name"] != nil ? nil : i)
                if id == nil, let r = raw as? String, r.range(of: "^[0-9A-Za-z]{2,12}$", options: .regularExpression) != nil, b["name"] != nil { id = r }
                if id == nil, raw == nil { id = resolveBook(nil, index: i) }
                guard let bookId = id else { continue }
                push(bookId, b, ch.map { c in ((c as? [Any]) ?? []).map { verseText($0) } })
            }
        } else if format == "flat-verses" {
            let list = (json as? [Any]) ?? ((json as? [String: Any])?["verses"] as? [Any]) ?? []
            var map: [String: [[String]]] = [:]
            for any in list {
                guard let v = any as? [String: Any],
                      let id = resolveBook(v["book"] ?? v["book_id"] ?? v["bookId"] ?? v["book_name"], index: nil),
                      let ch = (v["chapter"] as? Int) ?? Int("\(v["chapter"] ?? "")"), let vs = (v["verse"] as? Int) ?? Int("\(v["verse"] ?? "")"),
                      ch > 0, vs > 0 else { continue }
                var chs = map[id] ?? []
                while chs.count < ch { chs.append([]) }
                while chs[ch - 1].count < vs { chs[ch - 1].append("") }
                chs[ch - 1][vs - 1] = "\(v["text"] ?? "")"
                map[id] = chs
            }
            let order = Dictionary(uniqueKeysWithValues: Books.all.enumerated().map { ($1.id, $0) })
            for id in map.keys.sorted(by: { (order[$0] ?? 999) < (order[$1] ?? 999) }) { push(id, nil, map[id] ?? []) }
        }
        if books.isEmpty { throw ImportError(message: String(localized: "Не найдено ни одной распознанной книги.")) }
        var seen = Set<String>()
        for b in books where !seen.insert(b["id"] as? String ?? "").inserted {
            throw ImportError(message: String(localized: "Книга \(b["id"] as? String ?? "") встречается в модуле дважды."))
        }
        return books
    }

    private static func dictionary(_ json: Any, _ format: String) throws -> [String: Any] {
        var entries: [String: Any] = [:]
        if format == "strongs-map" {
            entries = json as? [String: Any] ?? [:]
        } else {
            for e in (json as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                let word = "\(e["word"] ?? e["term"] ?? e["topic"] ?? "")".trimmingCharacters(in: .whitespaces)
                if word.isEmpty { continue }
                entries[word.lowercased().replacingOccurrences(of: "ё", with: "е")] = [
                    "word": word, "text": "\(e["definition"] ?? e["text"] ?? e["description"] ?? "")", "refs": e["refs"] as? [Any] ?? [],
                ]
            }
        }
        if entries.isEmpty { throw ImportError(message: String(localized: "В словаре нет статей (поле «entries» пустое).")) }
        return entries
    }
}
