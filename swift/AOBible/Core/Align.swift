import Foundation

// Сопоставление слов синодального стиха (RST+) со словами оригинала (ВЗ — OSHB, НЗ — Робинсон — Пирпонт) по номерам
// Стронга — порт alignVerse / ruInterlinear из interlinear.dart. Нужно окну слова: «В этом стихе» — точная форма
// слова оригинала, которое стоит за нажатым русским словом.

/// Слово или промежуток разобранного стиха
struct ILTok {
    let isWord: Bool
    let text: String
    var strongs: [String] = []
    var morph: [String] = []
    var orig: String? = nil
    var italic = false
}

/// Русское слово стиха с его оригиналом
struct RuWord {
    let text: String
    let orig: String
    let origMorph: String?
    let num: String?
}

/// Слово оригинала: накапливает русские слова, которыми оно передано
final class OWord {
    let text: String
    let num: String?
    let morph: String?
    var gloss: [String] = []
    init(text: String, num: String?, morph: String?) {
        self.text = text
        self.num = num
        self.morph = morph
    }
}

enum Align {
    private static let wordRe = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:[-’'][\\p{L}\\p{M}]+)*")
    private static let strongRe = try! NSRegularExpression(pattern: "^([HG])0*(\\d+)([a-z]?)$", options: [.caseInsensitive])
    private static let cantillation = try! NSRegularExpression(pattern: "[\\u0591-\\u05BD\\u05AF\\u05C0]")

    /// Разбор стиха: {слово|номера|морфология|оригинал}, ‹добавленное›; слово без номеров — обычные слова
    static func tokenize(_ text: String) -> [ILTok] {
        var out: [ILTok] = []
        var italic = false
        func plain(_ s: String) {
            let ns = s as NSString
            var last = 0
            for m in wordRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > last {
                    out.append(ILTok(isWord: false, text: ns.substring(with: NSRange(location: last, length: m.range.location - last)), italic: italic))
                }
                out.append(ILTok(isWord: true, text: ns.substring(with: m.range), italic: italic))
                last = m.range.location + m.range.length
            }
            if last < ns.length { out.append(ILTok(isWord: false, text: ns.substring(from: last), italic: italic)) }
        }
        let c = Array(text)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == "‹" {
                italic = true
                i += 1
            } else if ch == "›" {
                italic = false
                i += 1
            } else if ch == "{" {
                guard let end = c[i...].firstIndex(of: "}") else {
                    plain(String(c[i...]))
                    break
                }
                let p = String(c[(i + 1)..<end]).components(separatedBy: "|")
                let strongs = p.count > 1 ? p[1].split(whereSeparator: { $0.isWhitespace }).map(String.init) : []
                let morph = p.count > 2 ? p[2].split(whereSeparator: { $0.isWhitespace }).map(String.init) : []
                let o = p.count > 3 ? p[3] : ""
                if !strongs.isEmpty {
                    out.append(ILTok(isWord: true, text: p[0], strongs: strongs, morph: morph, orig: o.isEmpty ? nil : o, italic: italic))
                } else {
                    plain(p[0])
                }
                i = end + 1
            } else {
                var j = i
                while j < c.count, !"‹›{".contains(c[j]) { j += 1 }
                plain(String(c[i..<j]))
                i = j
            }
        }
        return out
    }

    /// «H0430» → «H430», «h1254a» → «H1254» (без буквы-суффикса)
    static func strongNum(_ s: String) -> String {
        let ns = s as NSString
        guard let m = strongRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return s }
        return ns.substring(with: m.range(at: 1)).uppercased() + ns.substring(with: m.range(at: 2))
    }

    static func originalFor(_ book: String) -> String? {
        switch Books.info(book)?.t {
        case "OT": return "oshb"
        case "NT": return "byz-rp2018"
        default: return nil
        }
    }

    // в греческом тексте у всех форм глагола один номер, а в RST+ у отдельных форм свои
    private static let same: [[String]] = [
        ["G1510", "G2258", "G2071", "G2070", "G2075", "G2076", "G2468", "G5600", "G1488", "G1526", "G2277"],
        ["G3004", "G2036", "G2046", "G4483"],
        ["G3708", "G1492", "G3700"],
        ["G2068", "G5315"],
        ["G5143", "G1408"],
    ]
    private static let aliases: [String: [String]] = {
        var m: [String: [String]] = [:]
        for g in same { for n in g { m[n] = g } }
        return m
    }()

    /// Русский перевод с разметкой, по которому строится сопоставление (RST+, иначе первый русский с номерами)
    @MainActor
    static func taggedRu(_ store: ModuleStore) -> InstalledModule? {
        store.bibles.first { $0.id == "rst-plus" } ?? store.bibles.first { $0.strongs && $0.language == "ru" && !$0.interlinear }
    }

    /// Слова синодального стиха, под каждым — слово оригинала (если нашлось)
    @MainActor
    static func ruWords(store: ModuleStore, book: String, chapter: Int, verse: Int) -> [RuWord]? {
        guard let id = originalFor(book), store.module(id) != nil else { return nil }
        let orig = store.verseRaw(module: id, book: book, chapter: chapter, verse: verse)
        let ru = taggedRu(store).flatMap { store.verseRaw(module: $0.id, book: book, chapter: chapter, verse: verse) }
        var queues: [String: [OWord]] = [:]
        for t in tokenize(orig ?? "") where t.isWord {
            let k = t.strongs.first.map(strongNum)
            let clean = cantillation.stringByReplacingMatches(in: t.text, range: NSRange(location: 0, length: (t.text as NSString).length), withTemplate: "")
            let w = OWord(text: clean, num: k, morph: t.morph.first)
            if let k { queues[k, default: []].append(w) }
        }
        guard let ru else { return [] }
        var last: [String: OWord] = [:]
        func take(_ k: String) -> OWord? {
            for n in aliases[k] ?? [k] {
                if var q = queues[n], !q.isEmpty {
                    let w = q.removeFirst()
                    queues[n] = q
                    last[k] = w
                    return w
                }
            }
            return nil
        }
        var out: [RuWord] = []
        var prevKey: String?
        var prevOrig: OWord?
        var gap = false
        for t in tokenize(ru) {
            if !t.isWord {
                if !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { gap = true }
                continue
            }
            let k = t.strongs.first.map(strongNum)
            var o: OWord?
            if let k, k == prevKey, !gap {
                prevOrig?.gloss.append(t.text)
            } else if let k {
                let fresh = take(k)
                fresh?.gloss.append(t.text)
                o = fresh ?? last[k]
                prevOrig = fresh
            }
            for extra in t.strongs.dropFirst() { _ = take(strongNum(extra)) }
            out.append(RuWord(text: t.text, orig: o?.text ?? "", origMorph: o?.morph, num: o != nil ? k : nil))
            prevKey = k
            gap = false
        }
        return out
    }
}
