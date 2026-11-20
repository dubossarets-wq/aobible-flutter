import Foundation

/// Статья словаря для поиска и страницы слова: из скачанного словаря (module) или из ещё не скачанного —
/// тогда сама статья приходит с сайта частью словаря (entry)
struct DictArticle: Identifiable, Hashable {
    let dictId: String
    let dictName: String
    let dictTitle: String
    let language: String
    /// «strongs» (ключ — номер Стронга) или «words»
    let kind: String
    let key: String
    /// Заголовок: слово статьи или слово оригинала
    let word: String
    /// Статья (у не скачанных словарей — всегда; у скачанных берётся из модуля, когда нужна)
    let remoteEntry: [String: Any]?
    let module: InstalledModule?

    var id: String { dictId + "|" + key }
    var installed: Bool { module != nil }

    static func == (a: DictArticle, b: DictArticle) -> Bool { a.id == b.id && a.installed == b.installed }
    func hash(into h: inout Hasher) {
        h.combine(id)
        h.combine(installed)
    }

    @MainActor
    func entry(_ store: ModuleStore) -> [String: Any]? {
        if let e = remoteEntry { return e }
        guard let m = module else { return nil }
        return store.strongOrWordEntry(module: m, key: key)
    }

    /// Строка-подсказка под заголовком: начало толкования
    @MainActor
    func snippet(_ store: ModuleStore) -> String {
        guard let e = entry(store) else { return "" }
        for k in ["definition", "text", "derivation"] {
            if let s = e[k] as? String, !s.isEmpty {
                let flat = s.replacingOccurrences(of: "\n", with: " ")
                return String(flat.prefix(160))
            }
        }
        if let r = e["renderings"] as? [[Any]] {
            return r.prefix(6).compactMap { $0.first as? String }.joined(separator: ", ")
        }
        return ""
    }
}

extension ModuleStore {
    /// Статья по ключу; номера Стронга бывают с нулями впереди (G0026) — пробуем и так
    func strongOrWordEntry(module m: InstalledModule, key: String) -> [String: Any]? {
        if let e = dictEntry(module: m, key: key) { return e }
        if m.dictionaryKind == "strongs", let r = key.range(of: "^([HG])(\\d+)$", options: .regularExpression) {
            let letter = String(key[r].prefix(1))
            let digits = String(key[r].dropFirst())
            return dictEntry(module: m, key: letter + String(repeating: "0", count: max(0, 4 - digits.count)) + digits)
        }
        return nil
    }

    /// Словари для статей. Симфония RST+ — не статьи, а «как переведено»: её номера идут в поиск по слову.
    /// Дворецкий — часть статьи Стронга (показывается внутри неё, как в окне слова из Библии)
    var articleDictionaries: [InstalledModule] {
        dictionaries.filter { $0.id != Lexicon.symphonyId && !Lexicon.lexiconIds.contains($0.id) }
    }

    /// Номера Стронга для русского слова — из обратного индекса скачанных словарей (симфония RST+ и др.)
    func strongsForWord(_ word: String) -> [(String, Int)] {
        let lower = word.lowercased()
        let norm = Lexicon.normalizeWord(word)
        var count: [String: Int] = [:]
        var order: [String] = []
        for m in dictionaries {
            var idx = windex(module: m, word: lower)
            if idx.isEmpty, norm != lower { idx = windex(module: m, word: norm) }
            for (s, n) in idx {
                let k = Lexicon.strongKey(s)
                if count[k] == nil { order.append(k) }
                count[k, default: 0] += n
            }
        }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return count.sorted { a, b in a.value != b.value ? a.value > b.value : (pos[a.key] ?? 0) < (pos[b.key] ?? 0) }
    }

    func article(_ m: InstalledModule, key: String, word: String) -> DictArticle {
        DictArticle(dictId: m.id, dictName: m.name, dictTitle: m.title, language: m.language, kind: m.dictionaryKind,
                    key: key, word: word, remoteEntry: nil, module: m)
    }

    /// Заголовок статьи Стронга: слово оригинала и номер
    static func strongWord(_ e: [String: Any], _ key: String) -> String {
        if let l = e["lemma"] as? String, !l.isEmpty { return "\(l) · \(key)" }
        if let w = e["word"] as? String, !w.isEmpty { return "\(w) · \(key)" }
        return key
    }
}

/// Словари с сайта по частям (modules/dict-idx, собирает scripts/dict-index.mjs веб-версии): статьи из словарей,
/// которые ещё не скачаны. Каждая часть — маленький сжатый файл с ключами на одно начало
@MainActor
final class RemoteDicts {
    static let shared = RemoteDicts()

    struct Dict {
        let id: String
        let name: String
        let title: String
        let language: String
        let kind: String
        let shards: [String]
        let wshards: [String]
    }

    private let bases = ["https://aobible.app/", "https://dubossarets-wq.github.io/ao-bible/"]
    private var dicts: [Dict]?
    private var loadedAt = Date.distantPast
    private var parts: [String: [String: Any]] = [:]

    private func fetch(_ path: String) async -> Data? {
        for base in bases {
            guard let url = URL(string: base + path) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return data
            }
        }
        return nil
    }

    /// Список словарей сайта (раз в несколько часов заново; нет сети — пусто)
    func list() async -> [Dict] {
        if let d = dicts, Date().timeIntervalSince(loadedAt) < 6 * 3600 { return d }
        guard let data = await fetch("modules/dict-idx/index.json"),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = j["dicts"] as? [[String: Any]] else { return dicts ?? [] }
        let out = list.compactMap { x -> Dict? in
            guard let id = x["id"] as? String, let shards = x["shards"] as? [String] else { return nil }
            return Dict(id: id, name: x["name"] as? String ?? id, title: x["title"] as? String ?? "",
                        language: x["language"] as? String ?? "", kind: x["kind"] as? String ?? "words",
                        shards: shards, wshards: x["wshards"] as? [String] ?? [])
        }
        dicts = out
        loadedAt = Date()
        parts = [:]
        return out
    }

    private func part(_ d: Dict, _ i: Int, words: Bool) async -> [String: Any] {
        let name = "\(d.id)/\(words ? "w" : "")\(i)"
        if let p = parts[name] { return p }
        guard let data = await fetch("modules/dict-idx/\(name).json.gz"),
              let raw = try? Gzip.decode(data),
              let j = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return [:] }
        if parts.count > 80 { parts = [:] }
        parts[name] = j
        return j
    }

    /// Части, где может лежать ключ (точно) или ключи, начинающиеся с prefix
    private func indices(_ shards: [String], key: String? = nil, prefix: String? = nil) -> [Int] {
        var out: [Int] = []
        for (i, p) in shards.enumerated() {
            if let k = key, k.hasPrefix(p) { out.append(i) }
            if let q = prefix, q.hasPrefix(p) || p.hasPrefix(q) { out.append(i) }
        }
        return Array(out.prefix(6))
    }

    func get(_ d: Dict, key: String) async -> [String: Any]? {
        for i in indices(d.shards, key: key) {
            if let e = await part(d, i, words: false)[key] as? [String: Any] { return e }
        }
        return nil
    }

    /// Статьи, ключ которых начинается с q: сначала точное совпадение
    func prefix(_ d: Dict, _ q: String, limit: Int) async -> [(String, [String: Any])] {
        var found: [(String, [String: Any])] = []
        for i in indices(d.shards, prefix: q) {
            for (k, v) in await part(d, i, words: false) where k.hasPrefix(q) {
                if let e = v as? [String: Any] { found.append((k, e)) }
            }
        }
        found.sort { a, b in
            if (a.0 == q) != (b.0 == q) { return a.0 == q }
            return a.0 < b.0
        }
        return Array(found.prefix(limit))
    }

    /// Номера Стронга для русского слова — из обратного индекса словарей сайта (симфония RST+)
    func strongsForWord(_ word: String) async -> [(String, Int)] {
        let lower = word.lowercased()
        var count: [String: Int] = [:]
        for d in await list() where !d.wshards.isEmpty {
            for w in Set([lower, Lexicon.normalizeWord(word)]) {
                for i in indices(d.wshards, key: w) {
                    guard let pairs = await part(d, i, words: true)[w] as? [[Any]] else { continue }
                    for p in pairs where p.count >= 2 {
                        if let s = p[0] as? String, let n = p[1] as? NSNumber { count[Lexicon.strongKey(s), default: 0] += n.intValue }
                    }
                }
            }
        }
        return count.sorted { $0.value > $1.value }
    }

    func article(_ d: Dict, key: String, entry: [String: Any]) -> DictArticle {
        let word = d.kind == "strongs" ? ModuleStore.strongWord(entry, key) : (entry["word"] as? String ?? key)
        return DictArticle(dictId: d.id, dictName: d.name, dictTitle: d.title, language: d.language, kind: d.kind,
                           key: key, word: word, remoteEntry: entry, module: nil)
    }
}

/// Поиск по всем словарям: скачанные и с сайта
@MainActor
enum DictSearch {
    /// Номера Стронга, по которым ищем: введён номер — он сам; слово — самые частые переводы этого слова
    static func strongKeys(_ store: ModuleStore, _ q: String) async -> [String] {
        let local = localStrongKeys(store, q)
        if !local.isEmpty { return local }
        return top(await RemoteDicts.shared.strongsForWord(q))
    }

    /// То же только по скачанным словарям (без сети)
    static func localStrongKeys(_ store: ModuleStore, _ q: String) -> [String] {
        if let s = SearchEngine.strongNumber(q) { return [Lexicon.strongKey(s)] }
        return top(store.strongsForWord(q))
    }

    /// Только заметные: редкие совпадения (случайные переводы, служебные слова) не показываем
    private static func top(_ list: [(String, Int)]) -> [String] {
        guard let first = list.first?.1 else { return [] }
        return list.filter { $0.1 * 8 >= first }.prefix(3).map { $0.0 }
    }

    /// Скачанные словари: точные совпадения слова, затем статьи Стронга, затем остальные слова с тем же началом
    static func installed(_ store: ModuleStore, _ q: String, strongs: [String]) -> [DictArticle] {
        var exact: [DictArticle] = []
        var rest: [DictArticle] = []
        var strong: [DictArticle] = []
        let isNumber = SearchEngine.strongNumber(q) != nil
        for m in store.articleDictionaries {
            if m.dictionaryKind == "strongs" {
                for k in strongs {
                    if let e = store.strongOrWordEntry(module: m, key: k) {
                        strong.append(store.article(m, key: k, word: ModuleStore.strongWord(e, k)))
                    }
                }
            } else if !isNumber {
                for h in store.dictPrefix(module: m, prefix: q, limit: 30) {
                    let a = store.article(m, key: h.key, word: h.word)
                    if h.key == q { exact.append(a) } else { rest.append(a) }
                }
            }
        }
        return exact + strong + rest
    }

    /// Словари сайта, которых нет среди скачанных
    static func remote(_ store: ModuleStore, _ q: String, strongs: [String]) async -> [DictArticle] {
        let have = Set(store.allInstalled.map(\.id))
        let isNumber = SearchEngine.strongNumber(q) != nil
        var exact: [DictArticle] = []
        var rest: [DictArticle] = []
        var strong: [DictArticle] = []
        let r = RemoteDicts.shared
        // русские — первыми
        let list = await r.list().filter { !have.contains($0.id) && $0.id != Lexicon.symphonyId }
            .sorted { ($0.language == "ru" ? 0 : 1) < ($1.language == "ru" ? 0 : 1) }
        for d in list {
            if Task.isCancelled { return [] }
            if d.kind == "strongs" {
                for k in strongs {
                    if let e = await r.get(d, key: k) { strong.append(r.article(d, key: k, entry: e)) }
                }
            } else if !isNumber, q.count >= 2 {
                for (k, e) in await r.prefix(d, q, limit: 5) {
                    let a = r.article(d, key: k, entry: e)
                    if k == q { exact.append(a) } else { rest.append(a) }
                }
            }
        }
        return exact + strong + rest
    }

    /// Чем связаны статьи разных словарей: словами и номерами Стронга. Связь та же, что в поиске, — симфония RST+:
    /// у слова — номера, которыми оно чаще всего переводит оригинал; у номера — слова, которыми он чаще всего
    /// переведён в Синодальном
    struct Related {
        var words: [String]
        var strongs: [String]
    }

    /// Связи по скачанным словарям (без сети) — чтобы страница открылась сразу
    static func relatedLocal(_ store: ModuleStore, _ a: DictArticle) -> Related {
        if a.kind == "strongs" {
            return Related(words: top(localRenderings(store, a)), strongs: [a.key])
        }
        return Related(words: [a.key], strongs: localStrongKeys(store, a.word.isEmpty ? a.key : a.word))
    }

    /// Полные связи: нет симфонии на телефоне — берём её с сайта
    static func related(_ store: ModuleStore, _ a: DictArticle) async -> Related {
        if a.kind == "strongs" {
            var r = localRenderings(store, a)
            if r.isEmpty { r = await remoteRenderings(a.key) }
            return Related(words: top(r), strongs: [a.key])
        }
        return Related(words: [a.key], strongs: await strongKeys(store, a.word.isEmpty ? a.key : a.word))
    }

    private static func pairs(_ e: [String: Any]?) -> [(String, Int)] {
        ((e?["renderings"] as? [[Any]]) ?? []).compactMap { p in
            guard p.count >= 2, let w = p[0] as? String, let n = p[1] as? NSNumber else { return nil }
            return (w, n.intValue)
        }
    }

    /// Как номер переведён в Синодальном: из самой статьи, иначе из симфонии RST+
    private static func localRenderings(_ store: ModuleStore, _ a: DictArticle) -> [(String, Int)] {
        let own = pairs(a.entry(store))
        if !own.isEmpty { return own }
        guard let sym = store.module(Lexicon.symphonyId) else { return [] }
        return pairs(store.strongOrWordEntry(module: sym, key: a.key))
    }

    private static func remoteRenderings(_ key: String) async -> [(String, Int)] {
        let r = RemoteDicts.shared
        guard let sym = await r.list().first(where: { $0.id == Lexicon.symphonyId }) else { return [] }
        return pairs(await r.get(sym, key: key))
    }

    private static func wordKeys(_ w: String) -> [String] {
        Array(NSOrderedSet(array: [w, Lexicon.dictKey(w), w.lowercased()])) as? [String] ?? [w]
    }

    /// Статьи скачанных словарей по связям: в словарях Стронга — по номерам, в словарях «по словам» — по словам
    static func siblingsInstalled(_ store: ModuleStore, _ rel: Related) -> [DictArticle] {
        var out: [DictArticle] = []
        for m in store.articleDictionaries {
            if m.dictionaryKind == "strongs" {
                for k in rel.strongs {
                    if let e = store.strongOrWordEntry(module: m, key: k) {
                        out.append(store.article(m, key: k, word: ModuleStore.strongWord(e, k)))
                    }
                }
            } else {
                for w in rel.words {
                    if let f = store.dictGetMany(module: m, keys: wordKeys(w)).first {
                        out.append(store.article(m, key: f.0, word: (f.1["word"] as? String) ?? w))
                        break
                    }
                }
            }
        }
        return out
    }

    /// То же в словарях сайта, которых нет среди скачанных
    static func siblingsRemote(_ store: ModuleStore, _ rel: Related) async -> [DictArticle] {
        let have = Set(store.allInstalled.map(\.id))
        let r = RemoteDicts.shared
        var out: [DictArticle] = []
        let list = await r.list().filter { !have.contains($0.id) && $0.id != Lexicon.symphonyId && !Lexicon.lexiconIds.contains($0.id) }
            .sorted { ($0.language == "ru" ? 0 : 1) < ($1.language == "ru" ? 0 : 1) }
        for d in list {
            if Task.isCancelled { break }
            if d.kind == "strongs" {
                for k in rel.strongs {
                    if let e = await r.get(d, key: k) { out.append(r.article(d, key: k, entry: e)) }
                }
            } else {
                search: for w in rel.words {
                    for k in wordKeys(w) {
                        if let e = await r.get(d, key: k) {
                            out.append(r.article(d, key: k, entry: e))
                            break search
                        }
                    }
                }
            }
        }
        return out
    }
}
