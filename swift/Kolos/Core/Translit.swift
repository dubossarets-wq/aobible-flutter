import Foundation

/// Приблизительное чтение слов оригинала русскими буквами (для подстрочника): порт translit.dart / src/core/translit.js.
/// Греческий — по эразмову произношению; еврейский — по огласовкам (никуд)
enum Translit {
    /// Греческое или еврейское слово — русскими буквами; иное — пусто
    static func of(_ word: String) -> String {
        let scalars = word.unicodeScalars
        if scalars.contains(where: { (0x0590...0x05FF).contains($0.value) }) { return hebrewToRu(word) }
        if scalars.contains(where: { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }) { return greekToRu(word) }
        return ""
    }

    // MARK: - Греческий

    private static let gr: [Character: String] = [
        "α": "а", "β": "б", "γ": "г", "δ": "д", "ε": "е", "ζ": "дз", "η": "э", "θ": "т", "ι": "и", "κ": "к", "λ": "л", "μ": "м",
        "ν": "н", "ξ": "кс", "ο": "о", "π": "п", "ρ": "р", "σ": "с", "ς": "с", "τ": "т", "υ": "ю", "φ": "ф", "χ": "х", "ψ": "пс", "ω": "о",
    ]
    private static let grPairs: [(Character, Character, String)] = [
        ("α", "υ", "ау"), ("ε", "υ", "эу"), ("η", "υ", "эу"), ("ο", "υ", "у"), ("υ", "ι", "юи"),
        ("γ", "γ", "нг"), ("γ", "κ", "нк"), ("γ", "ξ", "нкс"), ("γ", "χ", "нх"),
    ]
    private static let rough = try! NSRegularExpression(pattern: "^[^\\u0300-\\u036F]*[\\u0300-\\u036F]*\\u0314")

    static func greekToRu(_ word: String) -> String {
        let d = word.decomposedStringWithCanonicalMapping
        // густое придыхание в начале слова или ῥ
        let hasRough = rough.firstMatch(in: d, range: NSRange(location: 0, length: (d as NSString).length)) != nil || word.hasPrefix("\u{1FE5}")
        var s = String.UnicodeScalarView()
        for u in d.unicodeScalars where !(0x0300...0x036F).contains(u.value) { s.append(u) }
        let chars = Array(String(s).lowercased())
        var out = ""
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count, let p = grPairs.first(where: { $0.0 == chars[i] && $0.1 == chars[i + 1] }) {
                out += p.2
                i += 2
                continue
            }
            let ch = chars[i]
            if let r = gr[ch] {
                out += r
            } else if let v = ch.unicodeScalars.first?.value, (0x61...0x7A).contains(v) || (0x430...0x44F).contains(v) {
                out.append(ch)
            }
            i += 1
        }
        return (hasRough && !out.hasPrefix("р") ? "х" : "") + out
    }

    // MARK: - Еврейский

    // согласные + огласовки. Дагеш в בכפ — взрывные (б, к, п), без него — в, х, ф
    private static let he: [UInt32: String] = [
        0x05D0: "", 0x05D1: "в", 0x05D2: "г", 0x05D3: "д", 0x05D4: "х", 0x05D5: "в", 0x05D6: "з", 0x05D7: "х", 0x05D8: "т", 0x05D9: "й",
        0x05DB: "х", 0x05DA: "х", 0x05DC: "л", 0x05DE: "м", 0x05DD: "м", 0x05E0: "н", 0x05DF: "н", 0x05E1: "с", 0x05E2: "",
        0x05E4: "ф", 0x05E3: "ф", 0x05E6: "ц", 0x05E5: "ц", 0x05E7: "к", 0x05E8: "р", 0x05E9: "ш", 0x05EA: "т",
    ]
    private static let hard: [UInt32: String] = [0x05D1: "б", 0x05DB: "к", 0x05DA: "к", 0x05E4: "п", 0x05E3: "п"]
    private static let vow: [UInt32: String] = [
        0x05B0: "е", 0x05B1: "е", 0x05B2: "а", 0x05B3: "о", 0x05B4: "и", 0x05B5: "е", 0x05B6: "е", 0x05B7: "а",
        0x05B8: "а", 0x05B9: "о", 0x05BA: "о", 0x05BB: "у", 0x05C7: "о",
    ]
    private static let dagesh: UInt32 = 0x05BC
    private static let holam: UInt32 = 0x05B9
    private static let sin: UInt32 = 0x05C2
    private static let shva: UInt32 = 0x05B0

    private static func isCantillation(_ v: UInt32) -> Bool {
        (0x0591...0x05AF).contains(v) || v == 0x05BD || v == 0x05C0 || v == 0x05C3 || v == 0x05BE
    }

    private static func isShvaBlock(_ v: UInt32) -> Bool {
        (0x05B1...0x05BB).contains(v) || v == 0x05C7
    }

    static func hebrewToRu(_ word: String) -> String {
        // кантилляция, метег, макаф — прочь
        let s = Array(word.unicodeScalars.filter { !isCantillation($0.value) })
        func isLetter(_ u: Unicode.Scalar) -> Bool { (0x05D0...0x05EA).contains(u.value) }
        let name: [UInt32] = [0x05D9, 0x05D4, 0x05D5, 0x05D4] // יהוה
        // Имя Божье (огласовано гласными «Адонай») — традиционное «Иегова», с приставкой (ла-, ва-, ми-…)
        let bare = s.filter(isLetter).map(\.value)
        if bare.count >= 4, Array(bare.suffix(4)) == name {
            var cut = -1
            for i in s.indices {
                if s[i].value == 0x05D9, s[i...].filter(isLetter).map(\.value) == name {
                    cut = s.distance(from: s.startIndex, to: i)
                    break
                }
            }
            var prefix = ""
            if cut > 0 {
                var v = String.UnicodeScalarView()
                v.append(contentsOf: s[..<cut])
                prefix = hebrewToRu(String(v))
            }
            return prefix + (cut > 0 ? "иегова" : "Иегова")
        }
        var letters: [(c: UInt32, marks: [UInt32])] = []
        for u in s {
            if he[u.value] != nil {
                letters.append((u.value, []))
            } else if !letters.isEmpty {
                letters[letters.count - 1].marks.append(u.value)
            }
        }
        var out = ""
        for (i, l) in letters.enumerated() {
            let c = l.c
            let marks = l.marks
            let hasDagesh = marks.contains(dagesh)
            let vowels = marks.compactMap { vow[$0] }
            let last = i == letters.count - 1
            if c == 0x05D5, vowels.isEmpty, hasDagesh {
                out += "у" // шурук
                continue
            }
            if c == 0x05D5, marks.contains(holam), i > 0 {
                out += "о" // холам-мале
                continue
            }
            var cons = hasDagesh ? (hard[c] ?? he[c] ?? "") : (he[c] ?? "")
            if c == 0x05E9, marks.contains(sin) { cons = "с" } // син
            if c == 0x05D4, last, !hasDagesh { cons = "" } // немая хе в конце
            if c == 0x05D9, vowels.isEmpty, i > 0, let tail = out.last, "иеэ".contains(tail) { cons = "" } // йуд как знак долготы
            let hasShva = marks.contains(shva)
            let v = vowels.first(where: { $0 != "е" || !hasShva || !last }) ?? ""
            let onlyShva = hasShva && !marks.contains(where: isShvaBlock)
            out += cons + (onlyShva ? (i == 0 ? "е" : "") : v)
        }
        return out
    }
}
