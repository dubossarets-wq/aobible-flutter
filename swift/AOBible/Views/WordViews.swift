import SwiftUI

struct WordRequest: Identifiable {
    let id = UUID()
    let text: String
    let strongs: [String]
    let morph: [String]
    let book: String
}

/// Окно слова: словари, где оно есть (Стронг по разметке или по симфонии, словари «по словам»); выбор — статья
struct WordSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let req: WordRequest

    var body: some View {
        let res = Lexicon.lookupWord(store: store, text: req.text, strongs: req.strongs, morph: req.morph, book: req.book)
        NavigationStack {
            List {
                if res.dictionaryCount == 0 {
                    Section {
                        Text("Словарей пока нет. Установите их: «Ещё» → «Библиотека модулей» → «Словари».")
                            .foregroundStyle(.secondary)
                    }
                }
                if res.mapping.mode == "approx" {
                    Section {
                        Text("Номера Стронга подобраны приблизительно — по симфонии. Точные есть в переводах с разметкой Стронга.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(res.results) { r in
                    Section {
                        ForEach(r.found.indices, id: \.self) { i in
                            let f = r.found[i]
                            NavigationLink {
                                EntryDetail(module: r.module, found: f)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.label)
                                    Text(f.key).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(r.module.name)
                    }
                }
                if res.results.isEmpty && res.dictionaryCount > 0 {
                    Section {
                        Text("В словарях такого слова нет.").foregroundStyle(.secondary)
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
        .presentationDetents([.medium, .large])
    }
}

/// Статья: оригинал, транслитерация, значение, происхождение со ссылками, «Как переведено», толковые словари,
/// «Все места» (стихи с этим номером)
struct EntryDetail: View {
    @EnvironmentObject private var store: ModuleStore
    let module: InstalledModule
    let found: Found
    @State private var linked: String?

    private var renderings: [(String, Int)] {
        guard let list = found.entry["renderings"] as? [[Any]] else { return [] }
        return list.compactMap { p in
            guard p.count >= 2, let w = p[0] as? String, let n = p[1] as? NSNumber else { return nil }
            return (w, n.intValue)
        }
    }

    var body: some View {
        List {
            Section {
                EntryView(entry: found.entry) { linked = $0 }
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
