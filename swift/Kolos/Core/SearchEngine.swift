import Foundation
import SwiftUI

struct SearchHit: Identifiable {
    let id: Int
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
    /// Перевод, в котором найдено (при поиске по нескольким)
    var moduleId = ""
    /// Один и тот же стих в разных переводах — разные результаты
    var uid: String { "\(moduleId)|\(id)" }
}

/// Текст перевода, подготовленный для поиска: один раз читается из файла и хранится в памяти (~10 МБ),
/// дальше любой запрос — проход по готовым байтам за считанные миллисекунды
final class SearchIndex: @unchecked Sendable {
    struct Row {
        let id: Int
        let book: String
        let chapter: Int
        let verse: Int
        let raw: String
        let plain: String
        let folded: [UInt8] // «_слова через пробел_» в нижнем регистре, ё = е, без ударений
    }

    let rows: [Row]

    private init(rows: [Row]) {
        self.rows = rows
    }

    private static let lock = NSLock()
    private static var cache: [String: SearchIndex] = [:]
    private static var building: Set<String> = []

    /// Подготовка заранее (в фоне): к первому запросу индекс уже готов
    static func warm(path: String) {
        lock.lock()
        let need = cache[path] == nil && !building.contains(path)
        if need { building.insert(path) }
        lock.unlock()
        guard need else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = index(path: path)
        }
    }

    static func index(path: String) -> SearchIndex? {
        lock.lock()
        if let hit = cache[path] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let db = try? SQLiteDB(path: path, readOnly: true) else { return nil }
        let rows = db.query("SELECT id, book, chapter, verse, text FROM verses ORDER BY id") { r -> Row in
            let raw = r.text(4)
            let plain = Markup.plain(raw)
            return Row(id: r.int(0), book: r.text(1), chapter: r.int(2), verse: r.int(3), raw: raw, plain: plain, folded: Array(fold(plain).utf8))
        }
        let idx = SearchIndex(rows: rows)
        lock.lock()
        cache[path] = idx
        building.remove(path)
        lock.unlock()
        return idx
    }

    static func forget(path: String) {
        lock.lock()
        cache.removeValue(forKey: path)
        lock.unlock()
    }

    /// Нижний регистр, «ё» = «е», без знаков ударения; всё, что не буква и не цифра, — один пробел; по краям пробелы
    static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.append(" ")
        var lastSpace = true
        for u in s.lowercased().unicodeScalars {
            if u.value == 0x0301 { continue }
            if u.value == 0x0451 { // ё
                out.append("е")
                lastSpace = false
                continue
            }
            if CharacterSet.letters.contains(u) || CharacterSet.decimalDigits.contains(u) || u.properties.generalCategory == .nonspacingMark {
                out.append(u)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        if !lastSpace { out.append(" ") }
        return String(out)
    }
}

enum SearchEngine {
    /// Слова запроса: каждое слово отдельно, а то, что в кавычках («свет миру»), — одной фразой подряд
    static func tokens(_ query: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuote = false
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            cur = ""
        }
        for ch in query {
            if ch == "\"" || ch == "«" || ch == "»" || ch == "“" || ch == "”" {
                flush()
                inQuote.toggle()
            } else if ch.isWhitespace && !inQuote {
                flush()
            } else {
                cur.append(ch)
            }
        }
        flush()
        return out
    }

    /// Регулярное выражение запроса (для подсветки найденного): любое из слов запроса, часть слова тоже
    /// подходит; «ё» = «е»; знак ударения в тексте не мешает
    static func regex(for query: String, wholeWord: Bool) -> NSRegularExpression? {
        let parts = tokens(query).compactMap { tokenPattern($0) }
        guard !parts.isEmpty else { return nil }
        let body = parts.count == 1 ? parts[0] : "(?:" + parts.joined(separator: "|") + ")"
        let pattern = wholeWord ? "(?<!\\p{L})" + body + "(?!\\p{L})" : body
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func tokenPattern(_ token: String) -> String? {
        let q = token
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{0301}", with: "")
        guard !q.isEmpty else { return nil }
        var body = ""
        var lastSpace = false
        for ch in q {
            if ch == " " {
                if !lastSpace { body += "[\\s\\p{P}]+" }
                lastSpace = true
                continue
            }
            lastSpace = false
            if "еёЕЁ".contains(ch) {
                body += "[её]\u{0301}?"
            } else {
                body += NSRegularExpression.escapedPattern(for: String(ch))
                if ch.isLetter { body += "\u{0301}?" }
            }
        }
        return body
    }

    /// «G26», «h1254» → номер Стронга
    static func strongNumber(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2, let first = q.first, first == "G" || first == "H",
              q.dropFirst().allSatisfy({ $0.isNumber }) else { return nil }
        return q
    }

    private static func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
        find(hay, needle, from: 0) != nil
    }

    /// Где слово встречается впервые, начиная с позиции from (конец найденного — index + needle.count)
    private static func find(_ hay: [UInt8], _ needle: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, from >= 0, hay.count - from >= needle.count else { return nil }
        return hay.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { n in
                guard let p = memmem(h.baseAddress! + from, h.count - from, n.baseAddress, n.count) else { return nil }
                return Int(bitPattern: p) - Int(bitPattern: h.baseAddress!)
            }
        }
    }

    /// Поиск по готовому индексу (в порядке Библии). books — только эти книги
    /// ordered: false — слова в любом порядке и с пропусками; true — слова в заданном порядке (между ними могут быть другие)
    static func run(index: SearchIndex, query: String, wholeWord: Bool, ordered: Bool = false, books: Set<String>?) -> [SearchHit] {
        var out: [SearchHit] = []
        if let strong = strongNumber(query) {
            // слово с номером Стронга: {текст|G26} или {текст|G1 G26|морфология}
            guard let re = try? NSRegularExpression(pattern: "\\|(?:[^|}]* )?" + strong + "(?=[ |}])") else { return [] }
            for r in index.rows {
                if let b = books, !b.contains(r.book) { continue }
                // быстрый отсев: номера в тексте нет — регулярное выражение не запускаем
                if !r.raw.contains(strong) { continue }
                if re.firstMatch(in: r.raw, range: NSRange(location: 0, length: (r.raw as NSString).length)) != nil {
                    out.append(SearchHit(id: r.id, book: r.book, chapter: r.chapter, verse: r.verse, text: r.plain))
                }
            }
            return out
        }
        // слова запроса: fold даёт «_слово_» с пробелами по краям — для обычного поиска края не нужны (часть слова
        // подходит), для «только целые слова» — нужны (слово не обрезано ни с одной стороны)
        let needles: [[UInt8]] = tokens(query).compactMap { t in
            var q = Array(SearchIndex.fold(t).utf8)
            guard q.count > 2 else { return nil }
            if !wholeWord {
                q.removeFirst()
                q.removeLast()
            }
            return q
        }
        guard !needles.isEmpty else { return [] }
        for r in index.rows {
            if let b = books, !b.contains(r.book) { continue }
            var ok = true
            if ordered {
                // каждое следующее слово — правее предыдущего (у целых слов пробел между словами общий — не отступаем)
                var pos = 0
                for n in needles {
                    guard let at = find(r.folded, n, from: pos) else { ok = false; break }
                    pos = at + n.count - (wholeWord ? 1 : 0)
                }
            } else {
                for n in needles where !contains(r.folded, n) { ok = false; break }
            }
            if ok {
                out.append(SearchHit(id: r.id, book: r.book, chapter: r.chapter, verse: r.verse, text: r.plain))
            }
        }
        return out
    }

    /// Текст результата с найденным на скруглённых плашках (для PlateLabel): слова подсвечены цельным фоном со скруглением
    static func highlightedNS(_ plain: String, query: String, wholeWord: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString(string: plain, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ])
        guard let re = regex(for: query, wholeWord: wholeWord) else { return out }
        let plate = PlateStyle(UIColor.systemYellow.withAlphaComponent(0.4), radius: 5, inflate: 2)
        for m in re.matches(in: plain, range: NSRange(location: 0, length: (plain as NSString).length)) {
            out.addAttribute(.aobPlate, value: plate, range: m.range)
        }
        return out
    }

    /// Текст результата с выделением найденного
    static func highlighted(_ plain: String, query: String, wholeWord: Bool) -> AttributedString {
        var attr = AttributedString(plain)
        attr.foregroundColor = Color.primary
        guard let re = regex(for: query, wholeWord: wholeWord) else { return attr }
        let ns = plain as NSString
        for m in re.matches(in: plain, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: plain) else { continue }
            let lo = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let hi = plain.distance(from: plain.startIndex, to: r.upperBound)
            let a = attr.index(attr.startIndex, offsetByCharacters: lo)
            let b = attr.index(attr.startIndex, offsetByCharacters: hi)
            attr[a..<b].backgroundColor = Color.yellow.opacity(0.4)
        }
        return attr
    }
}
