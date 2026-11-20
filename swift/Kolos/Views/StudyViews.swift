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

    private static let seeRe = try! NSRegularExpression(pattern: "(?:См\\.|см\\.|Ср\\.|ср\\.)\\s*([А-Яа-яЁё][А-Яа-яЁё\\s,\\-]*)")
    private static let wordRe = try! NSRegularExpression(pattern: "[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*")

    /// Текст статьи со ссылками: номера Стронга и слова после «См.» / «Ср.» (нажатие — статья этого слова)
    static func attributed(_ s: String, refs: Bool) -> AttributedString {
        var attr = attributed(s)
        guard refs else { return attr }
        let ns = s as NSString
        for m in seeRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let group = m.range(at: 1)
            for w in wordRe.matches(in: s, range: group) {
                let word = ns.substring(with: w.range)
                guard word.count > 2, let r = Range(w.range, in: s), let enc = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
                let lo = s.distance(from: s.startIndex, to: r.lowerBound)
                let hi = s.distance(from: s.startIndex, to: r.upperBound)
                let a = attr.index(attr.startIndex, offsetByCharacters: lo)
                let b = attr.index(attr.startIndex, offsetByCharacters: hi)
                attr[a..<b].link = URL(string: "aobref:" + enc)
            }
        }
        return attr
    }

    static func refWord(from url: URL) -> String? {
        guard url.scheme == "aobref" else { return nil }
        return String(url.absoluteString.dropFirst("aobref:".count)).removingPercentEncoding
    }

    static func key(from url: URL) -> String? {
        guard url.scheme == "aobstrong" else { return nil }
        let rest = String(url.absoluteString.dropFirst("aobstrong:".count))
        return String(rest.split(separator: "@").first ?? "")
    }
}

/// Статья словаря: поля модуля (оригинал, транслитерация, значение, происхождение…)
struct EntryView: View {
    let entry: [String: Any]
    let onLink: (String) -> Void
    /// Словарь «по словам»: «См. Законник» — ссылка на статью (onRef получает слово)
    var refs = false
    var onRef: ((String) -> Void)? = nil

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
                Text(StrongLinks.attributed(t, refs: refs))
            }
            if let k = str("kjv") {
                Text("KJV: \(k)").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let w = StrongLinks.refWord(from: url) {
                onRef?(w)
                return .handled
            }
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
    /// только этот комментарий (нажали на метку после стиха); nil — все
    var moduleId: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = store.commentary(book: book, chapter: chapter, verse: verse).filter { moduleId == nil || $0.module.id == moduleId }
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
            .navigationTitle(moduleId != nil ? (items.first?.module.name ?? "") : String(localized: "Толкования"))
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
                                .bidi(store.refText(module: module.id, r))
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        ZoomableImage(url: URL(string: it.img))
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

/// Картинка с увеличением: щипок (до 6×), двойное касание — 2,5× и обратно, при увеличении — сдвиг пальцем
struct ZoomableImage: View {
    let url: URL?
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    private func reset() {
        scale = 1
        base = 1
        offset = .zero
        dragBase = .zero
    }

    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, min(6, base * $0.magnification)) }
                        .onEnded { _ in
                            base = scale
                            if scale <= 1 { reset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { offset = CGSize(width: dragBase.width + $0.translation.width, height: dragBase.height + $0.translation.height) }
                        .onEnded { _ in dragBase = offset },
                    including: scale > 1 ? .all : .none
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = 2.5
                            base = 2.5
                        }
                    }
                }
        } placeholder: {
            ProgressView()
        }
        .clipped()
    }
}

/// Поиск по всем словарям: слово (по началу) или номер Стронга. Русское слово ищется и в словарях Стронга —
/// через обратный индекс «словоформа → номера» (симфония RST+). Ниже скачанных — статьи из словарей библиотеки,
/// которые ещё не скачаны (приходят с сайта по частям). Строка поиска — внизу, над клавиатурой, стеклом
struct DictionaryView: View {
    @EnvironmentObject private var store: ModuleStore
    @State private var query = ""
    @State private var mine: [DictArticle] = []
    @State private var others: [DictArticle] = []
    @State private var searched = ""
    @State private var loadingOthers = false
    @FocusState private var focused: Bool

    private var q: String {
        query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    var body: some View {
        List {
            if q.isEmpty {
                Section {
                    Text("Введите слово или номер Стронга, например «благодать», G5485 или H430. Поиск идёт по всем словарям — и по скачанным, и по остальным из библиотеки.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !mine.isEmpty {
                    Section("Мои словари") {
                        ForEach(mine) { row($0) }
                    }
                } else if searched == q && !loadingOthers && others.isEmpty {
                    Section {
                        Text("Ничего не найдено.").foregroundStyle(.secondary)
                    }
                }
                if loadingOthers && others.isEmpty {
                    Section("Другие словари") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Ищу в словарях библиотеки…").foregroundStyle(.secondary)
                        }
                    }
                } else if !others.isEmpty {
                    Section {
                        ForEach(others) { row($0) }
                    } header: {
                        Text("Другие словари")
                    } footer: {
                        Text("Эти словари ещё не скачаны — статьи приходят по сети. Скачать словарь можно на странице статьи.")
                    }
                }
            }
        }
        .navigationTitle("Словарь")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { searchBar }
        .task(id: q) { await run(q) }
        .onAppear { if query.isEmpty { focused = true } }
    }

    /// Строка поиска над клавиатурой (без клавиатуры — над нижним меню)
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Слово или номер Стронга", text: $query)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func row(_ a: DictArticle) -> some View {
        NavigationLink {
            DictEntryPage(start: a)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.word).font(.body.weight(.medium))
                Text(a.dictName).font(.caption).foregroundStyle(.secondary)
                let sn = a.snippet(store)
                if !sn.isEmpty {
                    Text(sn).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private func run(_ q: String) async {
        guard !q.isEmpty else {
            mine = []
            others = []
            searched = ""
            loadingOthers = false
            return
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        if Task.isCancelled { return }
        // сначала скачанные (сразу), потом — словари сайта
        let local = DictSearch.localStrongKeys(store, q)
        mine = DictSearch.installed(store, q, strongs: local)
        searched = q
        others = []
        loadingOthers = true
        let keys = local.isEmpty ? await DictSearch.strongKeys(store, q) : local
        if Task.isCancelled { return }
        if keys != local { mine = DictSearch.installed(store, q, strongs: keys) }
        let more = await DictSearch.remote(store, q, strongs: keys)
        if Task.isCancelled { return }
        others = more
        loadingOthers = false
    }
}

/// Страница статьи: название словаря и переключение между словарями, где есть то же слово (или тот же номер
/// Стронга), — и скачанными, и с сайта
struct DictEntryPage: View {
    @EnvironmentObject private var store: ModuleStore
    let start: DictArticle
    @State private var tabs: [DictArticle] = []
    @State private var sel = ""
    @State private var extra: [String] = []
    @State private var refArticle: DictArticle?
    @State private var installing = false

    private var current: DictArticle { tabs.first { $0.id == sel } ?? start }

    var body: some View {
        let a = current
        List {
            if tabs.count > 1 {
                Section {
                    PillTabs(labels: tabs.map(\.dictName), index: tabs.firstIndex { $0.id == sel } ?? 0) { i in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sel = tabs[i].id
                            extra = []
                        }
                    }
                    // лента до краёв экрана, отступ — у содержимого (иначе плашки обрезаются в 16 пт от края)
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                if let e = a.entry(store) {
                    if let rich = e["rich"] as? [[String: Any]] {
                        DvoretskyArticle(blocks: rich)
                    } else {
                        EntryView(entry: e, onLink: { extra.append($0) }, refs: a.kind != "strongs", onRef: { openRef($0) })
                    }
                } else {
                    Text("Статья не найдена.").foregroundStyle(.secondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.dictName).font(.headline).foregroundStyle(.primary)
                    if !a.dictTitle.isEmpty && a.dictTitle != a.dictName {
                        Text(a.dictTitle).font(.footnote)
                    }
                }
                .textCase(nil)
            } footer: {
                if !a.installed { Text("Словарь не скачан — статья пришла по сети.") }
            }
            if !a.installed {
                Section {
                    Button { install(a) } label: {
                        if installing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Скачивается…")
                            }
                        } else {
                            Label("Скачать словарь «\(a.dictName)»", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(installing)
                }
            }
            if a.kind == "strongs" {
                Section {
                    NavigationLink {
                        ConcordancePage(key: a.key)
                    } label: {
                        Label("Все места", systemImage: "text.magnifyingglass")
                    }
                }
            }
            ForEach(extra, id: \.self) { k in
                ForEach(store.articleDictionaries) { m in
                    if let e = store.strongOrWordEntry(module: m, key: k) {
                        Section {
                            EntryView(entry: e) { extra.append($0) }
                        } header: {
                            Text("\(k) · \(m.name)")
                        }
                    }
                }
            }
        }
        .navigationTitle(a.word)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $refArticle) { DictEntryPage(start: $0) }
        .task { await load() }
        .onChange(of: store.installed.count) { _, _ in Task { await load() } }
    }

    private func load() async {
        // скачанные словари — сразу, словари сайта — следом
        var list = DictSearch.siblingsInstalled(store, start)
        if !list.contains(where: { $0.dictId == start.dictId }) { list.append(start) }
        let keep = current.dictId
        tabs = list
        if sel.isEmpty { sel = list.first { $0.dictId == start.dictId }?.id ?? start.id }
        let more = await DictSearch.siblingsRemote(store, start)
        var seen = Set(list.map(\.dictId))
        tabs = list + more.filter { seen.insert($0.dictId).inserted }
        // словарь только что скачали — выбранной остаётся статья того же словаря
        if !tabs.contains(where: { $0.id == sel }), let t = tabs.first(where: { $0.dictId == keep }) { sel = t.id }
    }

    /// «См. Законник»: статья этого слова в том же словаре
    private func openRef(_ word: String) {
        let a = current
        let keys = [Lexicon.dictKey(word), word.lowercased()]
        if let m = a.module {
            if let f = store.dictGetMany(module: m, keys: keys).first {
                refArticle = store.article(m, key: f.0, word: (f.1["word"] as? String) ?? f.0)
            }
            return
        }
        Task {
            let r = RemoteDicts.shared
            guard let d = await r.list().first(where: { $0.id == a.dictId }) else { return }
            for k in keys {
                if let e = await r.get(d, key: k) {
                    refArticle = r.article(d, key: k, entry: e)
                    return
                }
            }
        }
    }

    private func install(_ a: DictArticle) {
        installing = true
        Task {
            if store.catalog.isEmpty { await store.loadCatalog() }
            if let e = store.catalog.first(where: { $0.id == a.dictId }) { await store.install(e) }
            installing = false
        }
    }
}

struct EntryPage: View {
    @EnvironmentObject private var store: ModuleStore
    let hit: DictHit
    @State private var extra: [String] = []
    @State private var refHit: DictHit?

    var body: some View {
        List {
            if let e = store.dictEntry(module: hit.module, key: hit.key) {
                Section {
                    EntryView(entry: e, onLink: { extra.append($0) }, refs: hit.module.dictionaryKind != "strongs", onRef: { openRef($0) })
                }
            }
            if hit.module.dictionaryKind != "strongs" {
                ForEach(store.otherEntries(key: hit.key, excluding: hit.module.id)) { o in
                    Section {
                        EntryView(entry: o.entry, onLink: { _ in }, refs: true, onRef: { openRef($0) })
                    } header: {
                        Text(o.module.name)
                    }
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
        .navigationDestination(item: $refHit) { EntryPage(hit: $0) }
    }

    /// «См. Законник»: статья этого слова в том же словаре
    private func openRef(_ word: String) {
        let keys = [Lexicon.dictKey(word), word.lowercased()]
        if let f = store.dictGetMany(module: hit.module, keys: keys).first {
            refHit = DictHit(module: hit.module, key: f.0, word: (f.1["word"] as? String) ?? (f.1["lemma"] as? String) ?? f.0)
        }
    }
}
