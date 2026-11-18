import Foundation

// Поиск словарных статей для слова, на которое нажал читатель (порт lexicon.dart / lexicon.js):
// 1. Если перевод размечен номерами Стронга — берём их (точная привязка).
// 2. Иначе сопоставляем русскую словоформу с номерами Стронга по обратному индексу симфонии (windex) — приблизительно.
// 3. Словари «по словам» ищутся по самой словоформе, затем по начальной форме (благодати → благодать), затем без
//    приставки (возлюбил → любить), и лишь потом — ближайшие слова с той же основой.

struct Found {
    let key: String
    let entry: [String: Any]
    let match: String // form | lemma | root | stem — по слову; exact | approx — по номеру
    var label: String { (entry["lemma"] as? String) ?? (entry["word"] as? String) ?? key }
}

struct ModResult: Identifiable {
    let module: InstalledModule
    let found: [Found]
    var id: String { module.id }
}

struct Mapping {
    let mode: String // exact | approx | none
    let strongs: [String]
    var morph: [String] = []
    var weights: [String: Double] = [:]
}

struct LookupResult {
    let word: String
    let mapping: Mapping
    let results: [ModResult]
    let dictionaryCount: Int
}

enum Lexicon {
    static let symphonyId = "rst-symphony"
    /// Толковые словари к Стронгу — не отдельной вкладкой, а разделом внутри статьи Стронга
    static let lexiconIds = ["dvoretsky-gr"]

    private static let endings = [
        "ениями", "ениях", "остями", "ствами", "иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими", "ешь", "ете",
        "ите", "ают", "яют", "ует", "ться", "тся", "ась", "ось", "ись", "ыся", "вши", "ший", "щий", "ние", "ния",
        "нию", "ием", "иях", "ой", "ей", "ий", "ый", "ая", "яя", "ое", "ее", "ую", "юю", "ом", "ем", "ах", "ях", "ов",
        "ев", "ам", "ям", "ть", "ти", "ет", "ит", "ут", "ют", "ат", "ят", "ил", "ел", "ла", "ли", "ло", "ся", "сь",
        "ы", "и", "а", "я", "о", "е", "у", "ю", "ь", "й",
    ]

    static func normalizeWord(_ w: String) -> String {
        w.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    static func stem(_ word: String) -> String {
        let w = normalizeWord(word)
        for e in endings where w.count - e.count >= 3 && w.hasSuffix(e) {
            return String(w.dropLast(e.count))
        }
        return w
    }

    /// Ключ для словаря: без ударений и титл, дореформенные буквы — в современные
    static func dictKey(_ word: String) -> String {
        var s = normalizeWord(word)
        s = s.replacingOccurrences(of: "[\u{0300}\u{0301}\u{0483}-\u{0489}]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "ѣ", with: "е")
        s = s.replacingOccurrences(of: "[іѵ]", with: "и", options: .regularExpression)
        s = s.replacingOccurrences(of: "ѳ", with: "ф")
        s = s.replacingOccurrences(of: "ъ$", with: "", options: .regularExpression)
        return s
    }

    private static let lemmaEndings = ["", "ь", "а", "я", "о", "е", "й", "ий", "ый", "ой", "ть", "ти", "ться", "ие", "ия"]
    private static let verbEndings = ["ить", "еть", "ать", "ять", "ть", "ти", "ться", "иться"]
    private static let vowels = Set("аеёиоуыэюяй")
    private static let verbalRe = try! NSRegularExpression(pattern: "(ил|ел|ал|ял|ла|ли|ло|ет|ит|ут|ют|ат|ят|ешь|ишь|ете|ите|ем|им|вши|ться|тся|лся|лась|лись)$")
    private static let prefixes = ["пред", "пере", "воз", "вос", "раз", "рас", "при", "про", "под", "пре", "вы", "из", "ис", "на", "за", "от", "об", "до", "со", "по", "у", "с", "о"]

    private static func isVerbal(_ w: String) -> Bool {
        verbalRe.firstMatch(in: w, range: NSRange(location: 0, length: (w as NSString).length)) != nil
    }

    private static func lemmaGuesses(_ st: String, verbal: Bool) -> [String] {
        var out: [String] = []
        for e in verbal ? verbEndings + lemmaEndings : lemmaEndings + verbEndings {
            out.append(st + e)
        }
        let chars = Array(st)
        if chars.count >= 3 {
            let last = chars[chars.count - 1]
            let prev = chars[chars.count - 2]
            // беглая гласная: «агнц» → агнец
            if !vowels.contains(last) && !vowels.contains(prev) {
                for v in ["е", "о"] {
                    for e in ["", "ь"] {
                        out.append(String(chars[0..<(chars.count - 1)]) + v + String(last) + e)
                    }
                }
            }
        }
        return out
    }

    static func strongKey(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: "^([HG])0*(\\d+)([a-z]?)$", options: [.caseInsensitive])
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return s }
        let letter = ns.substring(with: m.range(at: 1)).uppercased()
        let num = ns.substring(with: m.range(at: 2))
        let suffix = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3))
        return letter + num + suffix
    }

    @MainActor
    private static func findWord(_ store: ModuleStore, _ m: InstalledModule, _ text: String) -> [Found] {
        let key = dictKey(text)
        let exact = store.dictGetMany(module: m, keys: [key, text.lowercased()])
        if let f = exact.first { return [Found(key: f.0, entry: f.1, match: "form")] }

        func byLemma(_ w: String) -> [String] {
            let st = stem(w)
            var seen = Set<String>()
            let guesses = lemmaGuesses(st, verbal: isVerbal(w)).filter { $0 != w && seen.insert($0).inserted }
            return store.dictGetMany(module: m, keys: guesses).map { $0.0 }
        }

        func make(_ keys: [String], _ n: Int, _ match: String) -> [Found] {
            let take = Array(keys.prefix(n))
            let got = Dictionary(store.dictGetMany(module: m, keys: take), uniquingKeysWith: { a, _ in a })
            return take.compactMap { k in got[k].map { Found(key: k, entry: $0, match: match) } }
        }

        // начальная форма слова
        var hits = byLemma(key)
        if !hits.isEmpty { return make(hits, 3, "lemma") }
        // без приставки: «возлюбил» → «любить»
        for pre in prefixes where key.hasPrefix(pre) && key.count - pre.count >= 4 {
            let rest = String(key.dropFirst(pre.count))
            hits = store.dictGetMany(module: m, keys: [rest]).isEmpty ? byLemma(rest) : [rest]
            if !hits.isEmpty { return make(hits, 2, "root") }
        }
        // ближайшие слова с той же основой: сначала с той же основой целиком, потом по близости длины
        let st = stem(key)
        var near = store.dictKeys(module: m, prefix: st, limit: 50).filter { key.contains(" ") || !$0.contains(" ") }
        let order = Dictionary(uniqueKeysWithValues: near.enumerated().map { ($1, $0) })
        near.sort { a, b in
            let c = (stem(a) == st ? 0 : 1) - (stem(b) == st ? 0 : 1)
            if c != 0 { return c < 0 }
            let d = abs(a.count - key.count) - abs(b.count - key.count)
            return d != 0 ? d < 0 : (order[a] ?? 0) < (order[b] ?? 0)
        }
        return make(near, 4, "stem")
    }

    /// Статьи Стронга — только русские словари; толковые к Стронгу — отдельно
    private static func ruStrongs(_ m: InstalledModule) -> Bool {
        (m.dictionaryKind != "strongs" || m.language == "ru") && !lexiconIds.contains(m.id)
    }

    @MainActor
    static func lookupWord(store: ModuleStore, text: String, strongs: [String], morph: [String], book: String) -> LookupResult {
        let modules = store.dictionaries.filter(ruStrongs)
        let prefix = Books.info(book)?.t == "NT" ? "G" : "H"
        let lower = text.lowercased()
        let norm = normalizeWord(text)

        var mapping: Mapping
        if !strongs.isEmpty {
            mapping = Mapping(mode: "exact", strongs: strongs.map(strongKey), morph: morph)
        } else {
            var candidates: [String: Int] = [:]
            var order: [String] = []
            for m in modules {
                var idx = store.windex(module: m, word: lower)
                if idx.isEmpty { idx = store.windex(module: m, word: norm) }
                for (s, n) in idx where s.hasPrefix(prefix) {
                    let k = strongKey(s)
                    if candidates[k] == nil { order.append(k) }
                    candidates[k, default: 0] += n
                }
            }
            let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            let list = candidates.sorted { a, b in
                a.value != b.value ? a.value > b.value : (pos[a.key] ?? 0) < (pos[b.key] ?? 0)
            }.prefix(4)
            let total = max(1, list.reduce(0) { $0 + $1.value })
            if list.isEmpty {
                mapping = Mapping(mode: "none", strongs: [])
            } else {
                mapping = Mapping(mode: "approx", strongs: list.map { $0.key }, weights: Dictionary(uniqueKeysWithValues: list.map { ($0.key, Double($0.value) / Double(total)) }))
            }
        }

        var results: [ModResult] = []
        for m in modules {
            var found: [Found] = []
            if m.dictionaryKind == "strongs" {
                for s in mapping.strongs {
                    var e = store.dictEntry(module: m, key: s)
                    if e == nil, let r = s.range(of: "^([HG])(\\d+)$", options: .regularExpression) {
                        let letter = String(s[r].prefix(1))
                        let digits = String(s[r].dropFirst())
                        e = store.dictEntry(module: m, key: letter + String(repeating: "0", count: max(0, 4 - digits.count)) + digits)
                    }
                    if let e { found.append(Found(key: s, entry: e, match: mapping.mode)) }
                }
            } else {
                found.append(contentsOf: findWord(store, m, text))
            }
            if !found.isEmpty { results.append(ModResult(module: m, found: found)) }
        }
        return LookupResult(word: text, mapping: mapping, results: mergeSymphony(store, results), dictionaryCount: modules.count)
    }

    /// Симфония RST+ — не отдельной вкладкой: её «Как переведено» показывается в статье Стронга. Отдельно она остаётся
    /// только для номеров, которых нет в словаре Стронга
    @MainActor
    static func mergeSymphony(_ store: ModuleStore, _ results: [ModResult]) -> [ModResult] {
        var strongKeys = Set<String>()
        for r in results where r.module.dictionaryKind == "strongs" && r.module.id != symphonyId {
            for f in r.found { strongKeys.insert(f.key) }
        }
        var out: [ModResult] = []
        for r in results {
            if r.module.id != symphonyId {
                out.append(r)
            } else {
                let rest = r.found.filter { !strongKeys.contains($0.key) }
                if !rest.isEmpty { out.append(ModResult(module: r.module, found: rest)) }
            }
        }
        return out
    }
}

extension ModuleStore {
    /// Те ключи из списка, что есть в словаре (в порядке списка)
    func dictGetMany(module m: InstalledModule, keys: [String]) -> [(String, [String: Any])] {
        guard !keys.isEmpty, let d = db(m.id) else { return [] }
        let marks = Array(repeating: "?", count: keys.count).joined(separator: ",")
        let rows = d.query("SELECT key, json FROM dict WHERE key IN (\(marks))", keys) { ($0.text(0), $0.text(1)) }
        var found: [String: String] = [:]
        for (k, j) in rows { found[k] = j }
        var out: [(String, [String: Any])] = []
        for k in keys {
            if let s = found[k], let data = s.data(using: .utf8),
               let e = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                out.append((k, e))
            }
        }
        return out
    }

    /// Ключи, начинающиеся с основы слова (по возрастанию)
    func dictKeys(module m: InstalledModule, prefix: String, limit: Int) -> [String] {
        guard let d = db(m.id) else { return [] }
        return d.query("SELECT key FROM dict WHERE key >= ? AND key < ? ORDER BY key LIMIT ?", [prefix, prefix + "\u{FFFF}", limit]) { $0.text(0) }
    }

    /// «Словоформа → [[номер Стронга, частота], …]» из обратного индекса словаря (если он есть)
    func windex(module m: InstalledModule, word: String) -> [(String, Int)] {
        guard let d = db(m.id) else { return [] }
        let has = !d.query("SELECT 1 FROM sqlite_master WHERE name = 'windex'") { $0.int(0) }.isEmpty
        guard has else { return [] }
        let rows = d.query("SELECT json FROM windex WHERE word = ?", [word]) { $0.text(0) }
        guard let s = rows.first, let data = s.data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
        return list.compactMap { p in
            guard p.count >= 2, let k = p[0] as? String, let n = p[1] as? NSNumber else { return nil }
            return (k, n.intValue)
        }
    }
}
