import Foundation

// Переводы Free Use Bible API (bible.helloao.org): скачиваются целиком (complete.json) прямо с их сайта и
// перекладываются в формат модуля приложения — дальше работают без сети, как любой скачанный перевод.
// Нумерация — синодальная, как у модулей каталога. Порт lib/core/helloao.dart и versification.dart.

/// Западная нумерация стихов (KJV) → синодальная. Таблицы — versification.json (собраны из Flutter-версии)
enum Versification {
    private struct Tables {
        let k2s: [String: [String: [[Int]]]]
        let western: [String: [Int]]
    }

    private static let tables: Tables = {
        guard let url = Bundle.main.url(forResource: "versification", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Tables(k2s: [:], western: [:])
        }
        let k = (j["k2s"] as? [String: [String: [[Int]]]]) ?? [:]
        let w = (j["western"] as? [String: [Int]]) ?? [:]
        return Tables(k2s: k, western: w)
    }()

    /// Стих KJV → (глава, стих) синодальной нумерации
    static func toSynodal(_ book: String, _ c: Int, _ v: Int) -> (Int, Int) {
        for r in tables.k2s[book]?[String(c)] ?? [] where r.count >= 4 && v >= r[0] && v <= r[1] {
            return (c + r[2], v + r[3])
        }
        return (c, v)
    }

    /// Какие главы KJV нужны, чтобы собрать синодальную главу c (обычно одна; на стыках псалмов — две)
    static func westernChapters(for book: String, _ c: Int) -> [Int] {
        guard let runs = tables.k2s[book] else { return [c] }
        var out = Set<Int>()
        for (kcs, list) in runs {
            guard let kc = Int(kcs) else { continue }
            if list.contains(where: { $0.count >= 4 && kc + $0[2] == c }) { out.insert(kc) }
        }
        let counts = tables.western[book] ?? []
        let n = counts.count >= c ? counts[c - 1] : 0
        if n >= 1 {
            for v in 1...n where toSynodal(book, c, v).0 == c {
                out.insert(c)
                break
            }
        }
        return out.sorted()
    }

    /// Глава KJV → стихи и заголовки синодальной главы target (что ушло в соседнюю главу — пропускается).
    /// title — надписание псалма: в синодальной нумерации это стих 1 (в западной — заголовок над стихом 1)
    static func place(_ book: String, kc: Int, verses: [String], heads: [Int: String], target: Int, into v: inout [String], headings h: inout [Int: String], title: String = "") {
        let first = toSynodal(book, kc, 1)
        if !title.isEmpty, book == "Ps", first.0 == target, first.1 == 2, v.isEmpty || v[0].isEmpty {
            if v.isEmpty { v.append("") }
            v[0] = title
        }
        for i in verses.indices {
            let text = verses[i]
            if text.isEmpty { continue }
            let (c, vn) = toSynodal(book, kc, i + 1)
            if c != target { continue }
            while v.count < vn { v.append("") }
            v[vn - 1] = v[vn - 1].isEmpty ? text : v[vn - 1] + " " + text
            if let hd = heads[i + 1], h[vn] == nil { h[vn] = hd }
        }
    }
}

enum Helloao {
    private static let spaces = try! NSRegularExpression(pattern: "\\s+")

    /// Содержимое стиха: строки и {text}; сноски и разрывы строк пропускаем
    private static func text(_ items: Any?) -> String {
        var parts: [String] = []
        for x in (items as? [Any]) ?? [] {
            if let s = x as? String {
                parts.append(s)
            } else if let m = x as? [String: Any], let s = m["text"] as? String {
                parts.append(s)
            }
        }
        var s = parts.joined(separator: " ").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        s = spaces.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// complete.json → модуль в формате aob-module (дальше — обычная установка в SQLite)
    static func module(from json: [String: Any], entry: [String: Any]) -> [String: Any] {
        var books: [[String: Any]] = []
        for b in (json["books"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
            guard let usfm = b["id"] as? String, let id = usfmToOsis[usfm] else { continue }
            // главы KJV: стихи, заголовки разделов, надписание псалма
            var kjv: [Int: (verses: [String], heads: [Int: String], title: String)] = [:]
            for ch in (b["chapters"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                guard let c = ch["chapter"] as? [String: Any], let n = c["number"] as? Int, n >= 1 else { continue }
                var verses: [String] = []
                var heads: [Int: String] = [:]
                var head: [String] = []
                var title = ""
                for it in (c["content"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                    let type = it["type"] as? String
                    if type == "hebrew_subtitle", verses.isEmpty {
                        title = text(it["content"])
                    } else if type == "heading" || type == "hebrew_subtitle" {
                        let s = text(it["content"])
                        if !s.isEmpty { head.append(s) }
                    } else if type == "verse", let v = it["number"] as? Int, v > 0 {
                        if !head.isEmpty {
                            heads[v] = head.joined(separator: " ")
                            head.removeAll()
                        }
                        while verses.count < v { verses.append("") }
                        let s = text(it["content"])
                        verses[v - 1] = verses[v - 1].isEmpty ? s : verses[v - 1] + " " + s
                    }
                }
                kjv[n] = (verses, heads, title)
            }
            if kjv.isEmpty { continue }
            // синодальные главы: каждая собирается из своих глав KJV
            var last = 0
            for (kc, k) in kjv {
                last = max(last, kc, Versification.toSynodal(id, kc, k.verses.isEmpty ? 1 : k.verses.count).0)
            }
            var chapters: [[String]] = []
            var headings: [String: String] = [:]
            for c in 1...max(1, last) {
                var v: [String] = []
                var h: [Int: String] = [:]
                for kc in Versification.westernChapters(for: id, c) {
                    if let k = kjv[kc] {
                        Versification.place(id, kc: kc, verses: k.verses, heads: k.heads, target: c, into: &v, headings: &h, title: k.title)
                    }
                }
                chapters.append(v)
                for (vn, t) in h { headings["\(c):\(vn)"] = t }
            }
            while let l = chapters.last, l.isEmpty { chapters.removeLast() }
            if chapters.isEmpty { continue }
            let info = Books.info(id)
            // родное название — из самой книги источника (commonName, иначе name)
            let native = ((b["commonName"] as? String) ?? (b["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            books.append(["id": id, "name": info?.rawName ?? id, "short": info?.rawShort ?? id, "nname": native, "chapters": chapters, "headings": headings])
        }
        let lang = entry["language"] as? String ?? "en"
        let words = BookLocale.chapterFormats(lang)
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
            "chapterWord": words?.0 ?? "",
            "psalmWord": words?.1 ?? "",
            "books": books,
        ]
    }
}
