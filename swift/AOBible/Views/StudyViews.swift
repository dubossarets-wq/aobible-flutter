import SwiftUI

/// Номера Стронга в тексте («G26», «H1254») → ссылки внутри приложения
enum StrongLinks {
    private static let pattern = try! NSRegularExpression(pattern: "[HG]\\d+")

    static func attributed(_ s: String) -> AttributedString {
        var attr = AttributedString(s)
        let ns = s as NSString
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: s) else { continue }
            let lo = s.distance(from: s.startIndex, to: r.lowerBound)
            let hi = s.distance(from: s.startIndex, to: r.upperBound)
            let a = attr.index(attr.startIndex, offsetByCharacters: lo)
            let b = attr.index(attr.startIndex, offsetByCharacters: hi)
            attr[a..<b].link = URL(string: "aobstrong:" + ns.substring(with: m.range))
        }
        return attr
    }

    static func key(from url: URL) -> String? {
        guard url.scheme == "aobstrong" else { return nil }
        return String(url.absoluteString.dropFirst("aobstrong:".count))
    }
}

/// Статья словаря: поля модуля (оригинал, транслитерация, значение, происхождение…)
struct EntryView: View {
    let entry: [String: Any]
    let onLink: (String) -> Void

    private func str(_ k: String) -> String? {
        guard let s = entry[k] as? String, !s.isEmpty else { return nil }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let l = str("lemma") ?? str("word") {
                Text(l).font(.title2.weight(.semibold))
            }
            let tr = [str("xlit"), str("pron").map { "[\($0)]" }].compactMap { $0 }.joined(separator: " · ")
            if !tr.isEmpty {
                Text(tr).foregroundStyle(.secondary)
            }
            if let d = str("derivation") {
                Text(StrongLinks.attributed(d))
            }
            if let d = str("definition") {
                Text(StrongLinks.attributed(d))
            }
            if let t = str("text") {
                Text(StrongLinks.attributed(t))
            }
            if let k = str("kjv") {
                Text("KJV: \(k)").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let k = StrongLinks.key(from: url) {
                onLink(k)
                return .handled
            }
            return .systemAction
        })
    }
}

/// Статьи по одному или нескольким ключам из всех установленных словарей
struct StrongList: View {
    @EnvironmentObject private var store: ModuleStore
    let keys: [String]
    let onLink: (String) -> Void

    var body: some View {
        let dicts = store.dictionaries
        List {
            if dicts.isEmpty {
                Section {
                    Text("Установите словарь Стронга: «Ещё» → «Библиотека модулей» → «Словари».")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(keys, id: \.self) { key in
                ForEach(dicts) { m in
                    if let e = store.dictEntry(module: m, key: key) {
                        Section {
                            EntryView(entry: e, onLink: onLink)
                        } header: {
                            Text("\(key) · \(m.name)")
                        }
                    }
                }
            }
        }
    }
}

/// Окно словарной статьи (по нажатию на номер Стронга); номера внутри статей ведут к другим статьям
struct StrongSheet: View {
    let keys: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            StrongList(keys: keys) { path.append($0) }
                .navigationTitle(keys.joined(separator: " "))
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { k in
                    StrongList(keys: [k]) { path.append($0) }
                        .navigationTitle(k)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Толкования к стиху из установленных комментариев
struct CommentarySheet: View {
    @EnvironmentObject private var store: ModuleStore
    let book: String
    let chapter: Int
    let verse: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = store.commentary(book: book, chapter: chapter, verse: verse)
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Нет толкований", systemImage: "text.book.closed")
                    } description: {
                        Text("К этому стиху толкований нет. Установить комментарии можно в «Ещё» → «Библиотека модулей» → «Толкования».")
                    }
                }
                ForEach(items) { it in
                    Section {
                        if !it.title.isEmpty {
                            Text(it.title).font(.headline)
                        }
                        Text(it.text)
                    } header: {
                        Text(it.module.name)
                    }
                }
            }
            .navigationTitle("Толкования")
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

/// Параллельные места стиха; нажатие открывает место в чтении
struct XrefsSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let module: InstalledModule
    let book: String
    let chapter: Int
    let verse: Int
    let onOpen: (String, Int, Int) -> Void

    private func label(_ r: OsisRef) -> String {
        let short = module.books.first { $0.id == r.book }?.short ?? Books.info(r.book)?.short ?? r.book
        var s = "\(short) \(r.chapter):\(r.verse)"
        if let ev = r.endVerse {
            if let ec = r.endChapter, ec != r.chapter {
                s += "–\(ec):\(ev)"
            } else if ev != r.verse {
                s += "–\(ev)"
            }
        }
        return s
    }

    var body: some View {
        let refs = store.xrefs(module: module.id, book: book, chapter: chapter, verse: verse)
        NavigationStack {
            List {
                if refs.isEmpty {
                    ContentUnavailableView {
                        Label("Нет параллельных мест", systemImage: "arrow.triangle.branch")
                    } description: {
                        Text("К этому стиху параллельных мест нет.")
                    }
                }
                ForEach(refs.indices, id: \.self) { i in
                    let r = refs[i]
                    Button {
                        dismiss()
                        onOpen(r.book, r.chapter, r.verse)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label(r)).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                            Text(store.refText(module: module.id, r)).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Параллельные места")
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

/// Иллюстрации к стиху: листаются, у каждой — автор, год, лицензия и ссылка на страницу файла
struct IllustrationsSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let book: String
    let chapter: Int
    let verse: Int

    var body: some View {
        let items = store.illustrations(book: book, chapter: chapter, verse: verse)
        NavigationStack {
            TabView {
                ForEach(items) { it in
                    VStack(spacing: 10) {
                        AsyncImage(url: URL(string: it.img)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxHeight: .infinity)
                        Text(it.title).font(.headline).multilineTextAlignment(.center)
                        Text([it.author, it.year].filter { !$0.isEmpty }.joined(separator: ", ") + (it.license.isEmpty ? "" : " · \(it.license)"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let u = URL(string: it.src), it.src.hasPrefix("http") {
                            Button("Страница файла на Commons") { openURL(u) }
                                .font(.footnote)
                        }
                    }
                    .padding()
                }
            }
            .tabViewStyle(.page)
            .navigationTitle("Иллюстрации")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// Поиск по словарям: номер Стронга (G26) или слово (по началу)
struct DictionaryView: View {
    @EnvironmentObject private var store: ModuleStore
    @State private var query = ""
    @State private var hits: [DictHit] = []

    var body: some View {
        List {
            if store.dictionaries.isEmpty {
                Section {
                    Text("Словарей пока нет. Установите их: «Ещё» → «Библиотека модулей» → «Словари».")
                        .foregroundStyle(.secondary)
                }
            } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    Text("Введите слово или номер Стронга, например G26 или H430.")
                        .foregroundStyle(.secondary)
                }
            } else if hits.isEmpty {
                Section {
                    Text("Ничего не найдено.").foregroundStyle(.secondary)
                }
            }
            ForEach(hits) { h in
                NavigationLink {
                    EntryPage(hit: h)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.word)
                        Text("\(h.key) · \(h.module.name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Словарь")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Слово или номер Стронга")
        .onChange(of: query) { _, _ in search() }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "ё", with: "е")
        guard !q.isEmpty else {
            hits = []
            return
        }
        var out: [DictHit] = []
        if let strong = SearchEngine.strongNumber(q) {
            for m in store.dictionaries {
                if let e = store.dictEntry(module: m, key: strong) {
                    out.append(DictHit(module: m, key: strong, word: (e["lemma"] as? String) ?? (e["word"] as? String) ?? strong))
                }
            }
        } else {
            for m in store.dictionaries where m.dictionaryKind != "strongs" {
                out.append(contentsOf: store.dictPrefix(module: m, prefix: q, limit: 30))
            }
        }
        hits = out
    }
}

struct EntryPage: View {
    @EnvironmentObject private var store: ModuleStore
    let hit: DictHit
    @State private var extra: [String] = []

    var body: some View {
        List {
            if let e = store.dictEntry(module: hit.module, key: hit.key) {
                Section {
                    EntryView(entry: e) { extra.append($0) }
                }
            }
            ForEach(extra, id: \.self) { k in
                ForEach(store.dictionaries) { m in
                    if let e = store.dictEntry(module: m, key: k) {
                        Section {
                            EntryView(entry: e) { extra.append($0) }
                        } header: {
                            Text("\(k) · \(m.name)")
                        }
                    }
                }
            }
        }
        .navigationTitle(hit.word)
        .navigationBarTitleDisplayMode(.inline)
    }
}
