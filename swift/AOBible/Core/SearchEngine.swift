import Foundation
import SwiftUI

struct SearchHit: Identifiable {
    let id: Int
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
}

enum SearchEngine {
    /// Регулярное выражение запроса: все слова фразы по порядку, часть слова тоже подходит («свет» найдёт
    /// «светильник»); «ё» = «е»; знак ударения в тексте не мешает
    static func regex(for query: String, wholeWord: Bool) -> NSRegularExpression? {
        let q = query
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
        let pattern = wholeWord ? "(?<!\\p{L})" + body + "(?!\\p{L})" : body
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// «G26», «h1254» → номер Стронга
    static func strongNumber(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2, let first = q.first, first == "G" || first == "H",
              q.dropFirst().allSatisfy({ $0.isNumber }) else { return nil }
        return q
    }

    /// Поиск по всем стихам перевода (в порядке Библии). books — только эти книги
    static func run(path: String, query: String, wholeWord: Bool, books: Set<String>?) -> [SearchHit] {
        guard let db = try? SQLiteDB(path: path, readOnly: true) else { return [] }
        let rows = db.query("SELECT id, book, chapter, verse, text FROM verses ORDER BY id") {
            (id: $0.int(0), book: $0.text(1), chapter: $0.int(2), verse: $0.int(3), text: $0.text(4))
        }
        var out: [SearchHit] = []
        if let strong = strongNumber(query) {
            // слово с номером Стронга: {текст|G26} или {текст|G1 G26|морфология}
            guard let re = try? NSRegularExpression(pattern: "\\|(?:[^|}]* )?" + strong + "(?=[ |}])") else { return [] }
            for r in rows {
                if let b = books, !b.contains(r.book) { continue }
                if re.firstMatch(in: r.text, range: NSRange(location: 0, length: (r.text as NSString).length)) != nil {
                    out.append(SearchHit(id: r.id, book: r.book, chapter: r.chapter, verse: r.verse, text: Markup.plain(r.text)))
                }
            }
            return out
        }
        guard let re = regex(for: query, wholeWord: wholeWord) else { return [] }
        for r in rows {
            if Task.isCancelled { return out }
            if let b = books, !b.contains(r.book) { continue }
            let plain = Markup.plain(r.text)
            if re.firstMatch(in: plain, range: NSRange(location: 0, length: (plain as NSString).length)) != nil {
                out.append(SearchHit(id: r.id, book: r.book, chapter: r.chapter, verse: r.verse, text: plain))
            }
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
