import SwiftUI

struct WordRequest: Identifiable {
    let id = UUID()
    let text: String
    let strongs: [String]
    let morph: [String]
    let book: String
    var chapter = 0
    var verse = 0
}

/// Выбор словаря у слова (как всплывающая карточка Flutter-версии): места («Название · Карта»), затем статьи
/// по номерам Стронга, затем остальные словари. Выбор — статья: Стронг на всю высоту, остальное на полэкрана
struct WordSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let req: WordRequest
    @State private var chosen: String?
    @State private var detent: PresentationDetent = .height(160)
    @State private var res: LookupResult?
    @State private var places: [BiblePlace] = []

    private struct Row: Identifiable {
        let id: String
        let module: InstalledModule
        let found: Found
        var isStrong: Bool { found.key.range(of: "^[GH][0-9]", options: .regularExpression) != nil }
    }

    var body: some View {
        let all = (res?.results ?? []).flatMap { r in r.found.map { Row(id: r.module.id + "|" + $0.key, module: r.module, found: $0) } }
        let rows = all.filter { $0.isStrong } + all.filter { !$0.isStrong }
        let approx = res?.mapping.mode == "approx"
        let count = rows.count + places.count + (approx ? 1 : 0)
        let height = CGFloat(min(max(count, 1), 7)) * 56 + 90
        NavigationStack {
            List {
                if res == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ищу в словарях…").foregroundStyle(.secondary)
                    }
                }
                if approx {
                    Text("≈ приблизительно: перевод без номеров Стронга")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(places) { p in
                    NavigationLink {
                        PlaceDetail(place: p).onAppear { detent = .medium }
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                            Text(p.name).fontWeight(.semibold)
                            Text("·").foregroundStyle(.secondary)
                            Text("Карта")
                        }
                    }
                }
                ForEach(rows) { r in
                    NavigationLink {
                        EntryDetail(module: r.module, found: r.found).onAppear { detent = r.isStrong ? .large : .medium }
                    } label: {
                        HStack(spacing: 10) {
                            if r.isStrong {
                                Text(r.found.key)
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                                    .foregroundStyle(.tint)
                            } else {
                                Text(r.found.label.isEmpty ? r.found.key : r.found.label).fontWeight(.semibold)
                            }
                            Text(r.module.name).foregroundStyle(.primary).lineLimit(1)
                        }
                    }
                }
                if let res, rows.isEmpty && places.isEmpty {
                    Text("Статей для «\(req.text)» нет").foregroundStyle(.secondary)
                    if res.dictionaryCount == 0 {
                        Text("Словари в библиотеке: «Ещё» → «Библиотека модулей»").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(req.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(height), .medium, .large], selection: $detent)
        .task {
            // окно уже показано; поиск по словарям — после первого кадра и только один раз
            await Task.yield()
            guard res == nil else { return }
            let r = Lexicon.lookupWord(store: store, text: req.text, strongs: req.strongs, morph: req.morph, book: req.book)
            places = store.placesFor(word: req.text, book: req.book, chapter: req.chapter, verse: req.verse)
            res = r
            let all = r.results.reduce(0) { $0 + $1.found.count }
            let n = all + places.count + (r.mapping.mode == "approx" ? 1 : 0)
            detent = .height(CGFloat(min(max(n, 1), 7)) * 56 + 90)
        }
    }
}

/// Статья: оригинал, транслитерация, значение, происхождение со ссылками, «Как переведено», толковые словари,
/// «Все места» (стихи с этим номером)
struct EntryDetail: View {
    @EnvironmentObject private var store: ModuleStore
    let module: InstalledModule
    let found: Found
    @State private var linked: String?
    @State private var refHit: DictHit?

    private var renderings: [(String, Int)] {
        guard let list = found.entry["renderings"] as? [[Any]] else { return [] }
        return list.compactMap { p in
            guard p.count >= 2, let w = p[0] as? String, let n = p[1] as? NSNumber else { return nil }
            return (w, n.intValue)
        }
    }

    /// «См. Законник»: статья этого слова в том же словаре
    private func openRef(_ word: String) {
        let keys = [Lexicon.dictKey(word), word.lowercased()]
        if let f = store.dictGetMany(module: module, keys: keys).first {
            refHit = DictHit(module: module, key: f.0, word: (f.1["word"] as? String) ?? (f.1["lemma"] as? String) ?? f.0)
        }
    }

    var body: some View {
        List {
            Section {
                EntryView(entry: found.entry, onLink: { linked = $0 }, refs: module.dictionaryKind != "strongs", onRef: { openRef($0) })
            }
            if module.dictionaryKind != "strongs" {
                ForEach(store.otherEntries(key: found.key, excluding: module.id)) { o in
                    Section {
                        EntryView(entry: o.entry, onLink: { _ in }, refs: true, onRef: { openRef($0) })
                    } header: {
                        Text(o.module.name)
                    }
                }
            }
            if !renderings.isEmpty {
                Section("Как переведено") {
                    Text(renderings.map { "\($0.0) ×\($0.1)" }.joined(separator: ", "))
                }
            }
            if module.dictionaryKind == "strongs" {
                ForEach(Lexicon.lexiconIds, id: \.self) { id in
                    if let m = store.module(id), let e = store.dictEntry(module: m, key: found.key), let t = e["text"] as? String, !t.isEmpty {
                        Section {
                            Text(t)
                        } header: {
                            Text(m.name)
                        }
                    }
                }
                Section {
                    NavigationLink {
                        ConcordancePage(key: found.key)
                    } label: {
                        Label("Все места", systemImage: "text.magnifyingglass")
                    }
                }
            }
        }
        .navigationTitle(found.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $refHit) { EntryPage(hit: $0) }
        .navigationDestination(item: $linked) { k in
            StrongList(keys: [k]) { linked = $0 }
                .navigationTitle(k)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Все места, где в тексте перевода встречается номер Стронга
struct ConcordancePage: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.openVerse) private var openVerse
    let key: String
    @State private var hits: [SearchHit] = []
    @State private var loaded = false
    @State private var shown = 60

    private var module: InstalledModule? {
        // перевод с разметкой Стронга: открытый в первой панели, иначе первый, где она есть
        if let m = store.module(panes.primaryModule), m.hasStrongs { return m }
        return store.bibles.first { $0.hasStrongs }
    }

    var body: some View {
        List {
            if module == nil {
                Section {
                    Text("Нужен перевод с номерами Стронга (например, RST+). Скачайте его в библиотеке модулей.")
                        .foregroundStyle(.secondary)
                }
            } else if !loaded {
                Section {
                    HStack {
                        ProgressView()
                        Text("Поиск…").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach(hits.prefix(shown)) { h in
                        Button {
                            openVerse(h.book, h.chapter, h.verse)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Books.info(h.book)?.short ?? h.book) \(h.chapter):\(h.verse)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(h.text).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if hits.count > shown {
                        Button("Показать ещё (\(hits.count - shown))") { shown += 60 }
                    }
                } header: {
                    Text("Найдено: \(hits.count)")
                }
            }
        }
        .navigationTitle("\(key) · все места")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let m = module else { return }
            let path = m.path
            let k = key
            let result = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                guard let idx = SearchIndex.index(path: path) else { return [] }
                return SearchEngine.run(index: idx, query: k, wholeWord: false, books: nil)
            }.value
            hits = result
            loaded = true
        }
    }
}

extension InstalledModule {
    var hasStrongs: Bool { strongs }
}
