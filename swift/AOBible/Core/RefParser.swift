import Foundation

struct ParsedRef {
    let book: String
    let chapter: Int
    let verse: Int
}

/// «Ин 3:16», «1 Кор 13:4-7», «Пс 22» → ссылка; названия книг — целиком, по началу и по согласным («фс», «флп»…)
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
        func put(_ key: String, _ id: String) {
            if key.count >= 2, dict[key] == nil {
                dict[key] = id
                order.append(key)
            }
        }
        var forms: [(id: String, n: String?, starts: [String], skel: [String])] = []
        for b in Books.all {
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
                bases.append(strip(String(base.dropFirst(3))))
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
        return ParsedRef(book: book, chapter: c, verse: Int(group(3) ?? "") ?? 1)
    }
}
