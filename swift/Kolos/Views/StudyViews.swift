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
        // окно на пол-экрана — непрозрачное (в iOS 26 по умолчанию стекло, сквозь него виден текст)
        .presentationBackground(Color(.systemGroupedBackground))
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
                if !items.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        ShareLink(item: shareText(items)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Отправить")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // окно на пол-экрана — непрозрачное (в iOS 26 по умолчанию стекло, сквозь него виден текст)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// Для отправки: сначала место (на языке толкования), через пустую строку — толкование. Несколько толкователей —
    /// у каждого его имя
    private func shareText(_ items: [CommentaryItem]) -> String {
        let lang = items.first?.module.language ?? "ru"
        let name = store.nativeBookName(book, language: lang) ?? BookLocale.name(book, Books.info(book)?.rawName ?? book, lang: lang)
        var parts = ["\(name) \(chapter):\(verse)"]
        for it in items {
            var body = it.title.isEmpty ? it.text : it.title + "\n" + it.text
            if items.count > 1 { body = it.module.name + "\n" + body }
            parts.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.joined(separator: "\n\n")
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
        // окно на пол-экрана — непрозрачное (в iOS 26 по умолчанию стекло, сквозь него виден текст)
        .presentationBackground(Color(.systemGroupedBackground))
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
        // окно на пол-экрана — непрозрачное (в iOS 26 по умолчанию стекло, сквозь него виден текст)
        .presentationBackground(Color(.systemGroupedBackground))
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
    /// Язык словарей: «all» — все (общий с выбором на странице статьи)
    @AppStorage("dictLang") private var lang = "all"

    private var mineShown: [DictArticle] { lang == "all" ? mine : mine.filter { $0.language == lang } }
    private var othersShown: [DictArticle] { lang == "all" ? others : others.filter { $0.language == lang } }

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
                let langs = DictLang.list((mine + others).map(\.language) + [lang])
                if langs.count > 1 {
                    Section {
                        Picker("Язык словаря", selection: $lang) {
                            Text("Все языки").tag("all")
                            ForEach(langs, id: \.self) { l in Text(DictLang.name(l)).tag(l) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if !mineShown.isEmpty {
                    Section("Мои словари") {
                        ForEach(mineShown) { row($0) }
                    }
                } else if searched == q && !loadingOthers && othersShown.isEmpty {
                    Section {
                        Text("Ничего не найдено.").foregroundStyle(.secondary)
                    }
                }
                if loadingOthers && othersShown.isEmpty {
                    Section("Другие словари") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Ищу в словарях библиотеки…").foregroundStyle(.secondary)
                        }
                    }
                } else if !othersShown.isEmpty {
                    Section {
                        ForEach(othersShown) { row($0) }
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

/// Страница статьи — в том же виде, что окно слова из текста Библии: вкладки словарей, где есть то же слово
/// (или тот же номер Стронга), статья Стронга целиком (значение, происхождение, Дворецкий внутри, «В Синодальном
/// переводе», «Где встречается»), статья словаря «по словам» — заголовок, текст и ссылки на стихи. Вкладки —
/// и скачанные словари, и словари сайта (те — с кнопкой «Скачать словарь»)
struct DictEntryPage: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.readerPalette) private var pal
    @Environment(\.openVerse) private var openVerse
    let start: DictArticle
    @State private var tabs: [DictArticle] = []
    @State private var sel = ""
    @State private var next: DictArticle?
    @State private var allKey: String?
    @State private var installing = false
    @AppStorage("dictLang") private var lang = "all"

    private var current: DictArticle { tabs.first { $0.id == sel } ?? start }

    /// Словари выбранного языка (нет таких — все)
    private var shownTabs: [DictArticle] {
        let f = lang == "all" ? tabs : tabs.filter { $0.language == lang }
        return f.isEmpty ? tabs : f
    }

    var body: some View {
        let a = current
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pickerCard(a)
                if let e = a.entry(store) {
                    if a.kind == "strongs" {
                        StrongEntryView(num: a.key, entry: e, module: a.module ?? placeholder(a), mapping: nil, orig: nil,
                                        onOpenStrong: openStrong, onOpenRef: { b, c, v in openVerse(b, c, v) },
                                        onOpenAll: { allKey = a.key })
                            .id(a.id)
                    } else {
                        wordEntry(a, e)
                    }
                } else {
                    Text("Статья не найдена.").foregroundStyle(pal.muted)
                }
                if !a.installed { remoteNote(a) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(a.kind == "strongs" ? "Статья \(a.key)" : a.word)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $next) { DictEntryPage(start: $0) }
        .navigationDestination(item: $allKey) { ConcordancePage(key: $0) }
        .task { await load() }
        .onChange(of: store.installed.count) { _, _ in Task { await load() } }
        .onChange(of: lang) { _, _ in
            if !shownTabs.contains(where: { $0.id == sel }), let f = shownTabs.first { sel = f.id }
        }
    }

    /// Вверху — как в библиотеке модулей: «Словарь» (какой именно) и «Язык» (язык словаря); под ними — полное название
    @ViewBuilder private func pickerCard(_ a: DictArticle) -> some View {
        let langs = DictLang.list(tabs.map(\.language) + [lang])
        VStack(spacing: 0) {
            pickerRow("Словарь", value: tabLabel(a)) {
                Picker("Словарь", selection: $sel) {
                    ForEach(shownTabs) { t in Text(tabLabel(t)).tag(t.id) }
                }
            }
            if langs.count > 1 {
                Divider().padding(.leading, 16)
                pickerRow("Язык", value: lang == "all" ? "Все языки" : DictLang.name(lang)) {
                    Picker("Язык", selection: $lang) {
                        Text("Все языки").tag("all")
                        ForEach(langs, id: \.self) { l in Text(DictLang.name(l)).tag(l) }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        if !a.dictTitle.isEmpty && a.dictTitle != a.dictName {
            Text(a.dictTitle)
                .font(.footnote)
                .foregroundStyle(pal.muted)
                .padding(.horizontal, 16)
        }
    }

    /// Строка карточки: подпись слева занимает свою ширину, выбор — всю остальную и всегда в одну строку
    /// (у Picker в меню своя подпись делит строку поровну с соседями и переносится)
    private func pickerRow<P: View>(_ title: String, value: String, @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title)).foregroundStyle(pal.text).fixedSize()
            Spacer(minLength: 0)
            Menu {
                picker()
            } label: {
                HStack(spacing: 5) {
                    Text(value).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    /// Название в списке: несколько статей одного словаря (слово переводит разные номера) — с номером;
    /// словарь не скачан — «по сети»
    private func tabLabel(_ t: DictArticle) -> String {
        var s = t.dictName
        if tabs.filter({ $0.dictId == t.dictId }).count > 1 { s += " · \(t.key)" }
        if !t.installed { s += " · по сети" }
        return s
    }

    /// Словарь с сайта (не скачан): откуда статья и кнопка «Скачать»
    private func remoteNote(_ a: DictArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("«\(a.dictTitle.isEmpty ? a.dictName : a.dictTitle)» ещё не скачан — статья пришла по сети.")
                .font(.footnote)
                .foregroundStyle(pal.muted)
            Button { install(a) } label: {
                HStack(spacing: 8) {
                    if installing { ProgressView() } else { Image(systemName: "arrow.down.circle") }
                    Text(installing ? "Скачивается…" : "Скачать словарь «\(a.dictName)»")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .disabled(installing)
        }
        .padding(.top, 6)
    }

    /// Статья словаря «по словам» — как в окне слова
    @ViewBuilder private func wordEntry(_ a: DictArticle, _ e: [String: Any]) -> some View {
        let refs = (e["refs"] as? [String]) ?? []
        Text((e["word"] as? String) ?? a.word)
            .font(.system(size: 22.4, weight: .bold))
            .foregroundStyle(pal.text)
        if let o = e["original"] as? String, !o.isEmpty {
            Text(o).font(.system(size: 36.8)).foregroundStyle(pal.text)
        }
        let txt = (e["text"] as? String) ?? (e["definition"] as? String) ?? ""
        Text(EntryLinks.attributed(txt, accent: pal.accent))
            .lineSpacing(5)
            .foregroundStyle(pal.text)
            .environment(\.openURL, OpenURLAction { url in
                if let r = EntryLinks.verse(from: url) {
                    openVerse(r.0, r.1, r.2)
                } else if let w = StrongLinks.refWord(from: url) {
                    openRef(w)
                }
                return .handled
            })
        if !refs.isEmpty {
            FlowRow {
                ForEach(refs, id: \.self) { r in
                    if let p = OsisRef(r) {
                        RefChip(label: osisLabel(p), icon: "link") { openVerse(p.book, p.chapter, p.verse) }
                    }
                }
            }
        }
    }

    /// Словарь сайта ещё не скачан — для статьи Стронга нужно только его имя и вид
    private func placeholder(_ a: DictArticle) -> InstalledModule {
        InstalledModule(id: a.dictId, name: a.dictName, title: a.dictTitle, language: a.language, type: "dictionary",
                        path: "", books: [], online: false, dictionaryKind: a.kind)
    }

    private func load() async {
        // скачанные словари — сразу, словари сайта — следом
        // связи статьи (слова ↔ номера Стронга): сначала по словарям на телефоне, затем полностью
        var list = DictSearch.siblingsInstalled(store, DictSearch.relatedLocal(store, start))
        if !list.contains(where: { $0.id == start.id }) && !Lexicon.lexiconIds.contains(start.dictId) { list.insert(start, at: 0) }
        if list.isEmpty { list = [start] }
        let keep = current.dictId
        tabs = list
        if sel.isEmpty || !list.contains(where: { $0.id == sel }) {
            sel = list.first { $0.id == start.id }?.id ?? list[0].id
        }
        let rel = await DictSearch.related(store, start)
        let local = DictSearch.siblingsInstalled(store, rel)
        let more = await DictSearch.siblingsRemote(store, rel)
        var seen = Set<String>()
        tabs = (list + local + more).filter { seen.insert($0.id).inserted }
        // словарь только что скачали — выбранной остаётся статья того же словаря
        if !tabs.contains(where: { $0.id == sel }), let t = tabs.first(where: { $0.dictId == keep }) { sel = t.id }
        // открытая статья — на другом языке, чем выбран: показываем все языки, иначе её не было бы в списке
        if !shownTabs.contains(where: { $0.id == sel }) { lang = "all" }
    }

    /// Номер Стронга в тексте статьи («от H24») — его статья
    private func openStrong(_ num: String) {
        let k = Lexicon.strongKey(num)
        if let m = store.articleDictionaries.first(where: { $0.dictionaryKind == "strongs" && store.strongOrWordEntry(module: $0, key: k) != nil }),
           let e = store.strongOrWordEntry(module: m, key: k) {
            next = store.article(m, key: k, word: ModuleStore.strongWord(e, k))
            return
        }
        Task {
            let r = RemoteDicts.shared
            for d in await r.list() where d.kind == "strongs" && d.id != Lexicon.symphonyId {
                if let e = await r.get(d, key: k) {
                    next = r.article(d, key: k, entry: e)
                    return
                }
            }
        }
    }

    /// «См. Законник»: статья этого слова в том же словаре
    private func openRef(_ word: String) {
        let a = current
        let keys = [Lexicon.dictKey(word), word.lowercased()]
        if let m = a.module {
            if let f = store.dictGetMany(module: m, keys: keys).first {
                next = store.article(m, key: f.0, word: (f.1["word"] as? String) ?? f.0)
            }
            return
        }
        Task {
            let r = RemoteDicts.shared
            guard let d = await r.list().first(where: { $0.id == a.dictId }) else { return }
            for k in keys {
                if let e = await r.get(d, key: k) {
                    next = r.article(d, key: k, entry: e)
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

/// Языки словарей: названия по-русски, русский — первым
enum DictLang {
    private static let ru = Locale(identifier: "ru")

    static func name(_ code: String) -> String {
        let n = ru.localizedString(forLanguageCode: code) ?? code
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    static func list(_ codes: [String]) -> [String] {
        Set(codes.filter { $0 != "all" && !$0.isEmpty }).sorted { a, b in
            if (a == "ru") != (b == "ru") { return a == "ru" }
            return name(a) < name(b)
        }
    }
}
