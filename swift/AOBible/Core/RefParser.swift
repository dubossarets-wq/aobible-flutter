import Foundation

struct ParsedRef {
    let book: String
    let chapter: Int
    let verse: Int
    var endVerse: Int? = nil
}

/// «Ин 3:16», «1 Кор 13:4-7», «Пс 22», «John 3:16» → ссылка. Таблица сокращений — та же, что у Flutter-версии
/// (lib/core/books.dart): id, названия и сокращения (русские и английские), дополнительные сокращения
/// («мф», «ин», «флп»…), затем сгенерированные: начала названий и сокращения по согласным
enum RefParser {
    private static let vowels = Set("аеиоуыэюяйъь")
    private static let table: (dict: [String: String], order: [String]) = build()

    private static let nameRe = try! NSRegularExpression(pattern: "^([1-4])(?:-?[а-яё]{1,2})?\\s*(.*)$")
    private static let refRe = try! NSRegularExpression(
        pattern: "^((?:[1-4]\\s*)?[^\\d\\s:.,][^\\d:,]*?)\\.?\\s*(\\d+)(?:(?:\\s*[:.,]\\s*|\\s+)(\\d+)(?:\\s*[-–]\\s*(\\d+))?)?\\s*$"
    )

    private static func strip(_ s: String) -> String {
        s.filter { !$0.isWhitespace && $0 != "." && $0 != "-" }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "." }.replacingOccurrences(of: "ё", with: "е")
    }

    private static func build() -> (dict: [String: String], order: [String]) {
        var dict: [String: String] = [:]
        var order: [String] = []

        // 1–2: id, названия, сокращения и дополнительные — последний записавший побеждает, место в порядке остаётся первое
        func add(_ key: String, _ id: String) {
            let k = norm(key)
            if dict[k] == nil { order.append(k) }
            dict[k] = id
        }
        for b in Books.all {
            add(b.id, b.id)
            add(b.name, b.id)
            add(b.short, b.id)
            for n in BookNames.en[b.id] ?? [] { add(n, b.id) }
        }
        for (id, keys) in BookNames.extra {
            for k in keys { add(k, id) }
        }

        // 3: сгенерированные — первый записавший побеждает; неканонические книги после канонических
        func put(_ key: String, _ id: String) {
            if key.count >= 2, dict[key] == nil {
                dict[key] = id
                order.append(key)
            }
        }
        let ordered = Books.all.filter { $0.dc != true } + Books.all.filter { $0.dc == true }
        var forms: [(id: String, n: String?, starts: [String], skel: [String])] = []
        for b in ordered {
            let lower = b.name.lowercased()
            let ns = lower as NSString
            var n: String? = nil
            var base = lower
            if let m = nameRe.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) {
                n = ns.substring(with: m.range(at: 1))
                base = ns.substring(with: m.range(at: 2))
            }
            base = base.replacingOccurrences(of: "ё", with: "е")
            var bases = [strip(base)]
            if base.hasPrefix("от ") {
                let extra = strip(String(base.dropFirst(3)))
                if !bases.contains(extra) { bases.append(extra) }
            }
            var starts: [String] = []
            var skel: [String] = []
            for x in bases {
                let chars = Array(x)
                guard chars.count >= 2 else { continue }
                for k in 2...chars.count {
                    starts.append(String(chars[0..<k]))
                }
                // сокращение по согласным: первая буква + согласные дальше
                let cons = Array(String(chars[0]) + String(chars.dropFirst().filter { !vowels.contains($0) }))
                if cons.count >= 2 {
                    for k in 2...cons.count {
                        skel.append(String(cons[0..<k]))
                    }
                }
            }
            forms.append((b.id, n, starts, skel))
        }
        // сначала начала названий всех книг, потом сокращения по согласным
        for pass in [0, 1] {
            for f in forms {
                for key in (pass == 0 ? f.starts : f.skel) {
                    if let n = f.n {
                        put(n + key, f.id)
                        if n == "1" { put(key, f.id) }
                    } else {
                        put(key, f.id)
                    }
                }
            }
        }
        return (dict, order)
    }

    static func findBook(_ text: String) -> String? {
        let key = norm(text)
        if let hit = table.dict[key] { return hit }
        guard key.count >= 3 else { return nil }
        for k in table.order where k.hasPrefix(key) {
            return table.dict[k]
        }
        return nil
    }

    static func parse(_ input: String) -> ParsedRef? {
        let s = input.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString
        guard let m = refRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let bookText = group(1), let book = findBook(bookText), let c = Int(group(2) ?? "") else { return nil }
        return ParsedRef(book: book, chapter: c, verse: Int(group(3) ?? "") ?? 1, endVerse: Int(group(4) ?? ""))
    }
}
