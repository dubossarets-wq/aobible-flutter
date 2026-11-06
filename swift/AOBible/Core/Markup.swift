import Foundation

/// Фрагмент стиха: обычный текст, курсив (слова переводчиков) или слово с номером Стронга
struct Token {
    let text: String
    var italic: Bool = false
    var strongs: [String] = []
    var orig: String? = nil
}

/// Разметка стиха (формат aob-module):
///   {текст|H7225}              — слово с номером Стронга
///   {текст|H1254 H853|TH8804}  — несколько номеров и морфология
///   {текст|G976|N-NSF|βίβλος}  — в подстрочнике четвёртое поле: слово оригинала
///   ‹текст›                    — слова, добавленные переводчиками (курсив)
enum Markup {
    private static let pattern = try! NSRegularExpression(
        pattern: "\\{([^|}]*)\\|([^|}]*)(?:\\|([^|}]*))?(?:\\|([^}]*))?\\}|‹([^›]*)›"
    )

    static func parse(_ raw: String) -> [Token] {
        let ns = raw as NSString
        var out: [Token] = []
        var pos = 0
        for m in pattern.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                out.append(Token(text: ns.substring(with: NSRange(location: pos, length: m.range.location - pos))))
            }
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            if let italic = group(5) {
                out.append(Token(text: italic, italic: true))
            } else {
                let orig = group(4)
                let strongs = (group(2) ?? "").split(separator: " ").map { String($0) }
                out.append(Token(text: group(1) ?? "", strongs: strongs, orig: (orig ?? "").isEmpty ? nil : orig))
            }
            pos = m.range.location + m.range.length
        }
        if pos < ns.length {
            out.append(Token(text: ns.substring(from: pos)))
        }
        return out
    }

    /// Текст без разметки — для поиска, копирования и «Поделиться»
    static func plain(_ raw: String) -> String {
        parse(raw).map { $0.text }.joined()
    }
}
