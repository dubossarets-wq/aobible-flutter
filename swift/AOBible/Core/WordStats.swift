import Foundation

/// Где и сколько раз встречается номер Стронга в переводе с разметкой (порт strongStats из study_data.dart)
struct WordStats {
    struct Ref: Identifiable {
        let book: String
        let chapter: Int
        let verse: Int
        let words: [String]
        var id: String { "\(book).\(chapter).\(verse)" }
    }
    let module: String
    let moduleId: String
    let total: Int
    let verses: Int
    /// книга, число употреблений — в порядке Библии
    let byBook: [(String, Int)]
    let renderings: [(String, Int)]
    let refs: [Ref]
}

extension Lexicon {
    /// Статьи по номеру из ссылки внутри статьи: русские словари Стронга (без толковых), ключ как есть
    @MainActor
    static func lookupStrong(store: ModuleStore, num: String) -> [ModResult] {
        let modules = store.dictionaries.filter { $0.dictionaryKind == "strongs" && $0.language == "ru" && !lexiconIds.contains($0.id) }
        var results: [ModResult] = []
        for m in modules {
            if let e = store.dictEntry(module: m, key: num) {
                results.append(ModResult(module: m, found: [Found(key: num, entry: e, match: "exact")]))
            }
        }
        return mergeSymphony(store, results)
    }

    /// Толковые словари к номеру (Дворецкий) — разделом в статье Стронга
    @MainActor
    static func lexiconEntries(store: ModuleStore, num: String) -> [(InstalledModule, String)] {
        lexiconIds.compactMap { id in
            guard let m = store.module(id), let e = store.dictEntry(module: m, key: num), let t = e["text"] as? String, !t.isEmpty else { return nil }
            return (m, t)
        }
    }
}

@MainActor
enum StrongStats {
    private static var cache: [String: WordStats] = [:]

    /// Считается один раз на номер, в фоне (просмотр всего текста перевода), результат запоминается
    static func load(store: ModuleStore, num: String) async -> WordStats? {
        if let c = cache[num] { return c }
        let mods = store.bibles.filter { $0.strongs }
        guard let mod = mods.first(where: { $0.id == "rst-plus" }) ?? mods.first(where: { $0.language == "ru" }) ?? mods.first else { return nil }
        let path = mod.path
        let esc = String(num.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        let s = await Task.detached(priority: .userInitiated) { StrongStats.scan(path, esc) }.value
        let st = WordStats(module: mod.name, moduleId: mod.id, total: s.total, verses: s.refs.count, byBook: s.byBook, renderings: s.renderings, refs: s.refs)
        cache[num] = st
        return st
    }

    nonisolated private static func scan(_ path: String, _ esc: String) -> (total: Int, byBook: [(String, Int)], renderings: [(String, Int)], refs: [WordStats.Ref]) {
        guard !esc.isEmpty, let re = try? NSRegularExpression(pattern: "\\{([^|}]*)\\|(?:[^|}]*\\s)?" + esc + "(?=[\\s|}])[^}]*\\}"),
              let db = try? SQLiteDB(path: path, readOnly: true) else { return (0, [], [], []) }
        var bookOrder: [String] = []
        var byBook: [String: Int] = [:]
        var renderOrder: [String] = []
        var renderings: [String: Int] = [:]
        var refs: [WordStats.Ref] = []
        var total = 0
        let rows = db.query("SELECT book, chapter, verse, text FROM verses WHERE text LIKE ? ORDER BY id", ["%\(esc)%"]) {
            ($0.text(0), $0.int(1), $0.int(2), $0.text(3))
        }
        for (book, chapter, verse, text) in rows {
            let ns = text as NSString
            var words: [String] = []
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let w = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
                words.append(w)
                if renderings[w] == nil { renderOrder.append(w) }
                renderings[w, default: 0] += 1
            }
            if words.isEmpty { continue }
            if byBook[book] == nil { bookOrder.append(book) }
            byBook[book, default: 0] += words.count
            total += words.count
            refs.append(WordStats.Ref(book: book, chapter: chapter, verse: verse, words: words))
        }
        // по убыванию числа; при равенстве — в порядке первого появления
        let pos = Dictionary(uniqueKeysWithValues: renderOrder.enumerated().map { ($1, $0) })
        let sorted = renderOrder.sorted { a, b in
            let x = renderings[a] ?? 0, y = renderings[b] ?? 0
            return x != y ? x > y : (pos[a] ?? 0) < (pos[b] ?? 0)
        }
        return (total, bookOrder.map { ($0, byBook[$0] ?? 0) }, sorted.map { ($0, renderings[$0] ?? 0) }, refs)
    }
}
