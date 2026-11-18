import SwiftUI

/// Письмо справа налево: иврит, арабский, персидский, урду, идиш и др. Язык модуля — по коду (в каталоге бывают
/// двухбуквенные и трёхбуквенные коды ISO 639), текст — по первому «сильному» знаку письма
enum Bidi {
    static let rtlLanguages: Set<String> = [
        "he", "heb", "hbo", "iw", "yi", "ydd", "ar", "arb", "arz", "apc", "ary", "acm", "afb", "ajp", "apd", "arq", "ars", "aeb", "acw",
        "fa", "pes", "prs", "glk", "ur", "urd", "ps", "pbt", "pst", "sd", "snd", "ug", "uig", "ckb", "ku-arab", "dv", "div", "syr",
        "syc", "aii", "arc", "nqo", "bal", "bgn", "lrc", "mzn", "pnb", "skr", "ks", "kas", "ota", "sam",
    ]

    static func isRTLLang(_ code: String?) -> Bool {
        guard let c = code?.lowercased() else { return false }
        if rtlLanguages.contains(c) { return true }
        let head = c.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? c
        return rtlLanguages.contains(head)
    }

    static func isHebrewLang(_ code: String?) -> Bool {
        guard let head = code?.lowercased().split(separator: "-").first else { return false }
        return ["he", "heb", "hbo", "iw"].contains(String(head))
    }

    /// Первая буква письма справа налево (еврейская, арабская, сирийская, тана…) раньше любой другой — текст читается справа налево
    static func isRTL(_ s: String) -> Bool {
        for u in s.unicodeScalars {
            let v = u.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v) { return true }
            if u.properties.isAlphabetic { return false }
        }
        return false
    }
}

extension View {
    /// Абзац читается справа налево, если сам текст — на иврите, арабском и т. п. (выравнивание по правому краю)
    func bidi(_ text: String) -> some View {
        environment(\.layoutDirection, Bidi.isRTL(text) ? .rightToLeft : .leftToRight)
    }
}
