import SwiftUI

/// Чтение: одна или несколько панелей (до шести) — рядом или друг над другом, у каждой свой перевод, место и история
struct ReaderView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var audio: AudioEngine
    @AppStorage("panesStacked") private var stacked = true
    @Environment(\.readerPalette) private var pal
    @State private var showModules = false

    var body: some View {
        NavigationStack {
            Group {
                if panes.panes.isEmpty || store.bibles.isEmpty {
                    ContentUnavailableView {
                        Label("Нет переводов", systemImage: "book")
                    } description: {
                        Text("Скачайте перевод Библии, чтобы начать читать.")
                    } actions: {
                        Button("Выбрать перевод") { showModules = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if stacked || panes.panes.count == 1 {
                    VStack(spacing: 0) {
                        ForEach(panes.panes) { p in
                            PaneView(paneID: p.id)
                            if p.id != panes.panes.last?.id { Divider() }
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(panes.panes) { p in
                            PaneView(paneID: p.id)
                            if p.id != panes.panes.last?.id { Divider() }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(pal.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                if let s = store.starterStatus {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(s).font(.footnote)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                }
            }
            .alert("Аудио", isPresented: Binding(get: { audio.message != nil }, set: { if !$0 { audio.message = nil } })) {
                Button("OK") {}
            } message: {
                Text(audio.message ?? "")
            }
            .sheet(isPresented: $showModules) {
                NavigationStack {
                    ModulesList(selected: panes.primaryBinding())
                        .navigationTitle("Переводы")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Готово") { showModules = false }
                            }
                        }
                }
            }
            .onAppear {
                panes.ensureStarted(store)
                if let m = store.module(panes.primaryModule) { SearchIndex.warm(path: m.path) }
            }
            .onChange(of: store.installed) { _, _ in panes.ensureStarted(store) }
        }
    }
}

/// Одна панель: шапка (перевод, место, история, соседние главы, меню панели) и текст главы
struct PaneView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var audio: AudioEngine
    @AppStorage("panesStacked") private var stacked = true
    let paneID: UUID
    @State private var showGoto = UserDefaults.standard.bool(forKey: "debugGoto")
    @State private var showModules = false

    private var pane: PaneState? {
        panes.panes.first { $0.id == paneID }
    }

    var body: some View {
        if let p = pane, let m = store.module(p.moduleId) {
            VStack(spacing: 0) {
                header(p, m)
                ChapterText(module: m, pane: p)
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Button { panes.step(paneID, -1, module: m) } label: { Image(systemName: "chevron.left").font(.title3) }
                                .accessibilityLabel("Предыдущая глава")
                            Spacer()
                            Button {
                                Task { await audio.listen(store: store, moduleId: p.moduleId, from: Place(book: p.book, chapter: p.chapter, verse: max(1, p.verse))) }
                            } label: { Image(systemName: "headphones").font(.title3) }
                                .accessibilityLabel("Слушать")
                            Spacer()
                            Button { panes.step(paneID, 1, module: m) } label: { Image(systemName: "chevron.right").font(.title3) }
                                .accessibilityLabel("Следующая глава")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                    }
            }
            .sheet(isPresented: $showGoto) {
                GotoSheet(module: m, recents: panes.recentBooks(), current: p.book) { b, c, v in
                    panes.go(paneID, b, c, v)
                }
            }
            .sheet(isPresented: $showModules) {
                NavigationStack {
                    ModulesList(selected: Binding(
                        get: { p.moduleId },
                        set: { panes.setModule(paneID, $0, store) }
                    ))
                    .navigationTitle("Перевод")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showModules = false }
                        }
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func bookName(_ p: PaneState, _ m: InstalledModule) -> String {
        m.books.first { $0.id == p.book }?.short.replacingOccurrences(of: ".", with: "") ?? Books.info(p.book)?.short ?? p.book
    }

    private func header(_ p: PaneState, _ m: InstalledModule) -> some View {
        HStack(spacing: 8) {
            Button { showModules = true } label: {
                Text(m.shortName).font(.subheadline.weight(.semibold)).fixedSize()
            }
            .buttonStyle(.glass)
            Button { showGoto = true } label: {
                HStack(spacing: 4) {
                    LiveTitle(live: panes.live, id: paneID, name: bookName(p, m), chapter: p.chapter, fallback: max(p.verse, 1))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
            }
            .buttonStyle(.glass)
            Spacer(minLength: 4)
            if panes.canBack(paneID) {
                Button { panes.back(paneID) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Назад")
            }
            if panes.canForward(paneID) {
                Button { panes.forward(paneID) } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Вперёд")
            }
            if panes.panes.count > 1 {
                Button(role: .destructive) { panes.closePane(paneID) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Закрыть панель")
            }
            Button { panes.addPane(after: paneID, moduleId: p.moduleId) } label: { Image(systemName: "rectangle.split.2x1") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(panes.panes.count >= maxPanes)
                .accessibilityLabel("Добавить панель")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

/// «Ин 3:16» в шапке: стих — верхний видимый, меняется при прокрутке
struct LiveTitle: View {
    @ObservedObject var live: LivePlace
    let id: UUID
    let name: String
    let chapter: Int
    let fallback: Int

    var body: some View {
        Text("\(name) \(chapter):\(live.verse[id] ?? fallback)").font(.subheadline.weight(.semibold)).fixedSize()
    }
}

struct ChapterCache {
    let key: String
    let verses: [Verse]
    let heads: [Int: String]
    let xcounts: [Int: Int]
    let icounts: [Int: Int]
    let attr: [Int: AttributedString]
}

/// Ссылочный ящик: запись в него при построении экрана не вызывает перерисовку
final class CacheBox {
    var value: ChapterCache?
}

struct StrongRequest: Identifiable {
    let id = UUID()
    let key: String
}

/// Долгое нажатие выделило стих: следующее нажатие на слово этого стиха — это отпускание пальца, а не выбор слова
struct LPGuard {
    let verse: Int
    let at: Date
}

enum StudyPanel: Identifiable {
    case commentary(Int)
    case xrefs(Int)
    case compare(Int)
    case interlinear(Int)
    case illustrations(Int)
    case collect(Int)

    var id: String {
        switch self {
        case .commentary(let v): return "c\(v)"
        case .xrefs(let v): return "x\(v)"
        case .compare(let v): return "v\(v)"
        case .interlinear(let v): return "i\(v)"
        case .illustrations(let v): return "p\(v)"
        case .collect(let v): return "k\(v)"
        }
    }
}

/// Текст главы: нажатие выбирает стих, двойное — делает любимым; внизу — панель действий
struct ChapterText: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var sermons: SermonStore
    @EnvironmentObject private var audio: AudioEngine
    let module: InstalledModule
    let pane: PaneState

    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("lineHeight") private var lineHeight = 1.45
    @AppStorage("showVerseNumbers") private var showNumbers = true
    @AppStorage("showStrongs") private var showStrongs = false
    @AppStorage("showXrefs") private var showXrefs = true
    @AppStorage("showIllustrations") private var showIllus = true
    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("fontWeight") private var fontWeight = 400.0
    @AppStorage("verseSpacing") private var verseSpacing = 0.55
    @AppStorage("verseNumPos") private var verseNumPos = "sup"
    @AppStorage("showHeadings") private var showHeadings = true
    @AppStorage("continuousVerses") private var continuous = false
    @AppStorage("textMargin") private var textMargin = 14.0
    @Environment(\.readerPalette) private var pal
    @AppStorage("theme") private var theme = "system"
    @State private var cacheBox = CacheBox()
    @State private var selected: Set<Int> = []
    @State private var collectItems: [MarkItem] = []
    @State private var pulseVerse = 0
    @State private var pulseAmt = 0.0
    @State private var wordTask: Task<Void, Never>?
    @State private var noWordUntil = Date.distantPast
    @State private var lpGuard: LPGuard?
    @State private var partVerse: Int?
    @State private var partFrom: Int?
    @State private var partTo: Int?
    @State private var noteVerse: Int?
    @State private var noteText = ""
    @State private var strong: StrongRequest?
    @State private var imageReq: ImageRequest?
    @State private var word: WordRequest?
    @State private var panel: StudyPanel?
    @State private var readTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var pinchBase: Double?

    private var book: String { pane.book }
    private var chapter: Int { pane.chapter }
    private var focus: Int { pane.verse }

    private var bookName: String {
        module.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
    }

    var body: some View {
        let d = chapterData()
        let verses = d.verses
        let heads = d.heads
        let xcounts = d.xcounts
        let icounts = d.icounts
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * verseSpacing) {
                    if continuous {
                        // сплошной текст: стихи идут подряд, разрыв — только у заголовков разделов
                        ForEach(blocks(verses, heads)) { blk in
                            VStack(alignment: .leading, spacing: 6) {
                                if let h = blk.heading, showHeadings { headingText(h) }
                                Text(continuousText(blk, xcounts, icounts))
                                    .tint(pal.text)
                                    .font(readerFont)
                                    .foregroundStyle(pal.text)
                                    .lineSpacing(fontSize * (lineHeight - 1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(blk.id)
                        }
                    } else {
                        ForEach(verses) { v in
                            VStack(alignment: .leading, spacing: 6) {
                                if showHeadings, let h = heads[v.num] { headingText(h) }
                                Text(d.attr[v.num] ?? AttributedString())
                                    // слова — ссылки: цвет не меняем (тот же, что у текста)
                                    .tint(pal.text)
                                    .font(readerFont)
                                    .foregroundStyle(pal.text)
                                    .lineSpacing(fontSize * (lineHeight - 1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(background(v.num), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .background(Color(hex: 0xd9475e).opacity(pulseVerse == v.num ? pulseAmt : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        HStack(spacing: 4) {
                                            if marks.isBookmarked(book, chapter, v.num) {
                                                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    // выделение уже есть — нажатие добавляет и снимает стихи; без него стих выделяется
                                    // долгим нажатием (нажатие на слово открывает словарь)
                                    .simultaneousGesture(TapGesture().onEnded { if !selected.isEmpty { toggle(v.num) } })
                                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                                        guard selected.isEmpty else { return }
                                        wordTask?.cancel()
                                        noWordUntil = Date().addingTimeInterval(0.6)
                                        let was = marks.isFavorite(MarksStore.key(book, chapter, v.num))
                                        marks.toggleFavorite(book, chapter, v.num, text: Markup.plain(v.text))
                                        show(was ? "Убрано из любимых стихов" : "♥ Добавлено в любимые стихи")
                                        pulseVerse = v.num
                                        pulseAmt = 0.3
                                        withAnimation(.easeOut(duration: 0.8)) { pulseAmt = 0 }
                                    })
                                    // долгое нажатие в любом месте стиха (и на слове): выделяет; отпускание пальца
                                    // не должно считаться нажатием на слово (иначе оно сразу снимало выделение)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.25, maximumDistance: 12).onEnded { _ in
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            partVerse = nil
                                            selected.insert(v.num)
                                            lpGuard = LPGuard(verse: v.num, at: Date())
                                        }
                                    )
                                if !continuous, partVerse == v.num {
                                    partBar(v).frame(maxWidth: .infinity)
                                } else if !continuous, v.num == selected.max() {
                                    selectionBar(verses).frame(maxWidth: .infinity)
                                }
                            }
                            .id(v.num)
                        }
                    }
                    if verses.isEmpty {
                        Text("В этом переводе нет такой главы.")
                            .foregroundStyle(pal.muted)
                    }
                    // конец главы на экране и прошло достаточно времени — глава прочитана (записывается в историю
                    // и засчитывается в планы)
                    Color.clear.frame(height: 1)
                        .onAppear { startReading(count: verses.count) }
                        .onDisappear { readTask?.cancel() }
                }
                .scrollTargetLayout()
                .padding(.horizontal, textMargin)
                .padding(.vertical, 12)
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { ids in
                if let top = ids.min() { panes.setLive(pane.id, top) }
            }
            .background { ReaderBackdrop(pal: pal) }
            .onAppear {
                scroll(proxy, verses, heads)
                // проверка на симуляторе: -debugWord YES открывает окно слова «Бог»
                if UserDefaults.standard.bool(forKey: "debugWord"), word == nil {
                    word = WordRequest(text: "Бог", strongs: ["H430"], morph: [], book: book, chapter: chapter, verse: 1)
                }
                // -debugSelect YES: выделен первый стих (панель действий)
                if UserDefaults.standard.bool(forKey: "debugSelect") { selected = [1] }
            }
            .onChange(of: focus) { _, _ in scroll(proxy, verses, heads) }
        }
        .id("\(module.id)|\(book)|\(chapter)")
        .simultaneousGesture(
            DragGesture(minimumDistance: 50).onEnded { g in
                if abs(g.translation.width) > abs(g.translation.height) * 2 {
                    panes.step(pane.id, g.translation.width < 0 ? 1 : -1, module: module)
                }
            }
        )
        // два пальца: размер букв
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    if pinchBase == nil { pinchBase = fontSize }
                    fontSize = min(40, max(13, (pinchBase ?? fontSize) * g.magnification))
                }
                .onEnded { _ in pinchBase = nil }
        )
        .safeAreaInset(edge: .bottom) {
            // сплошной текст: панель внизу; иначе она стоит между стихами, под последним выделенным
            if !selected.isEmpty && continuous {
                selectionBar(verses)
            }
        }
        .sheet(isPresented: Binding(get: { noteVerse != nil }, set: { if !$0 { noteVerse = nil } })) {
            noteEditor
        }
        .onChange(of: chapter) { _, _ in selected = [] }
        .overlay(alignment: .top) {
            if let t = toast {
                Text(t)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: toast)
        .environment(\.openURL, OpenURLAction { url in
            // палец ещё не отпущен после долгого нажатия (или только что отпущен) — это не нажатие на слово
            if let g = lpGuard, let v = verseOf(url), v == g.verse {
                lpGuard = nil
                if Date().timeIntervalSince(g.at) < 15 { return .handled }
            }
            // выбор части стиха: нажатия по словам этого стиха ставят начало и конец
            if let pv = partVerse, url.scheme == "aobword", verseOf(url) == pv {
                if let wi = partWordIndex(url) {
                    if partFrom == nil || partTo != nil { partFrom = wi; partTo = nil } else { partTo = wi }
                }
                return .handled
            }
            // идёт выделение стихов: нажатие на слово, номер Стронга и метки только выделяет стих, словарь не открывается
            if !selected.isEmpty, let v = verseOf(url) {
                toggle(v)
                return .handled
            }
            if let k = StrongLinks.key(from: url) {
                strong = StrongRequest(key: k)
                return .handled
            }
            if url.scheme == "aobxref", let v = Int(url.absoluteString.dropFirst("aobxref:".count)) {
                panel = .xrefs(v)
                return .handled
            }
            if url.scheme == "aobword" {
                if Date() < noWordUntil { return .handled }
                wordTask?.cancel()
                wordTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !Task.isCancelled { openWord(url) }
                }
                return .handled
            }
            if url.scheme == "aobillus", let v = Int(url.absoluteString.dropFirst("aobillus:".count)) {
                panel = .illustrations(v)
                return .handled
            }
            if url.scheme == "aobverse", let v = Int(url.absoluteString.dropFirst("aobverse:".count)) {
                toggle(v)
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $strong) { r in
            StrongSheet(keys: [r.key])
        }
        .sheet(item: $word) { r in
            WordSheet(req: r)
        }
        .sheet(item: $imageReq) { r in
            VerseImageSheet(text: r.text, ref: r.ref)
        }
        .sheet(item: $panel) { p in
            switch p {
            case .commentary(let v):
                CommentarySheet(book: book, chapter: chapter, verse: v)
            case .xrefs(let v):
                XrefsSheet(module: module, book: book, chapter: chapter, verse: v) { b, c, vv in
                    panes.openSecond(from: pane.id, b, c, vv)
                }
            case .compare(let v):
                CompareSheet(book: book, chapter: chapter, verse: v)
            case .interlinear(let v):
                InterlinearSheet(book: book, chapter: chapter, verse: v)
            case .illustrations(let v):
                IllustrationsSheet(book: book, chapter: chapter, verse: v)
            case .collect:
                CollectSheet(items: collectItems) { show("Добавлено в подборку «\($0)»") }
            }
        }
    }

    /// Глава, её заголовки, числа параллельных мест и иллюстраций и готовый текст стихов — собираются один раз и
    /// пересобираются только при смене главы, перевода или оформления (выделение стиха их не трогает)
    private func chapterData() -> ChapterCache {
        let favs = favNums
        let key = "\(favs.sorted())|\(partKey)|\(module.id)|\(book)|\(chapter)|\(fontSize)|\(fontFamily)|\(fontWeight)|\(showNumbers)|\(showStrongs)|\(verseNumPos)|\(showXrefs)|\(showIllus)|\(theme)|\(store.installed.count)"
        if let c = cacheBox.value, c.key == key { return c }
        let verses = store.verses(module: module.id, book: book, chapter: chapter)
        let heads = store.headings(module: module.id, book: book, chapter: chapter)
        let xcounts = showXrefs ? store.xrefCounts(module: module.id, book: book, chapter: chapter) : [:]
        let icounts = showIllus ? store.illustrationCounts(book: book, chapter: chapter) : [:]
        var attr: [Int: AttributedString] = [:]
        for v in verses {
            attr[v.num] = attributed(v, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true)
        }
        let c = ChapterCache(key: key, verses: verses, heads: heads, xcounts: xcounts, icounts: icounts, attr: attr)
        cacheBox.value = c
        return c
    }

    /// Номер стиха, к которому относится ссылка в тексте
    private func verseOf(_ url: URL) -> Int? {
        let s = url.absoluteString
        switch url.scheme {
        case "aobword": return s.dropFirst("aobword:".count).split(separator: ",").first.flatMap { Int($0) }
        case "aobstrong": return s.split(separator: "@").last.flatMap { Int($0) }
        case "aobxref": return Int(s.dropFirst("aobxref:".count))
        case "aobillus": return Int(s.dropFirst("aobillus:".count))
        case "aobverse": return Int(s.dropFirst("aobverse:".count))
        default: return nil
        }
    }

    private func startReading(count: Int) {
        readTask?.cancel()
        guard count > 0 else { return }
        let b = book
        let c = chapter
        readTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(PlanLogic.minSeconds(count) * 1_000_000_000))
            if Task.isCancelled { return }
            let r = plans.chapterRead(book: b, chapter: c)
            if let f = r.finished.first {
                show("План «\(f)»: на сегодня всё ✓")
            } else if let p = r.credited.first {
                show("Засчитано в план «\(p)»")
            }
        }
    }

    private func show(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == s { toast = nil }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, _ verses: [Verse], _ heads: [Int: String]) {
        guard focus > 0 else { return }
        var target = focus
        if continuous, let blk = blocks(verses, heads).first(where: { $0.verses.contains { $0.num == focus } }) {
            target = blk.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        }
    }

    private func toggle(_ n: Int) {
        if selected.contains(n) { selected.remove(n) } else { selected.insert(n) }
    }

    private var partKey: String {
        let fp = marks.data.favorites.filter { $0.book == book && $0.chapter == chapter }.compactMap { f in f.part.map { "\(f.verse):\($0.from)-\($0.to)" } }
        return "\(partVerse ?? 0):\(partFrom ?? -1):\(partTo ?? -1)|\(fp.sorted())"
    }

    private func partRange(_ n: Int) -> ClosedRange<Int>? {
        guard partVerse == n, let a = partFrom else { return nil }
        let b = partTo ?? a
        return min(a, b)...max(a, b)
    }

    private func favPartRange(_ n: Int) -> ClosedRange<Int>? {
        guard let p = marks.data.favorites.first(where: { $0.book == book && $0.chapter == chapter && $0.verse == n })?.part else { return nil }
        return min(p.from, p.to)...max(p.from, p.to)
    }

    /// Любимые стихи этой главы (сердечко ставится в текст между номером и словами)
    private var favNums: Set<Int> {
        Set(marks.data.favorites.filter { $0.book == book && $0.chapter == chapter }.map { $0.verse })
    }

    private func background(_ n: Int) -> Color {
        if selected.contains(n) { return pal.accent.opacity(continuous ? 0.16 : 0.09) }
        // звучащий стих подсвечен
        if audio.active, audio.moduleId == module.id, let c = audio.current, c.book == book, c.chapter == chapter, c.verse == n {
            return pal.accent.opacity(0.16)
        }
        if let c = hlColor(marks.highlight(MarksStore.key(book, chapter, n))) {
            return c.color.opacity(0.4)
        }
        if marks.isFavorite(MarksStore.key(book, chapter, n)) { return Color(hex: 0xd9475e).opacity(0.09) }
        if n == focus { return pal.hl }
        return Color.clear
    }

    private static let wordRe = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:[-’'][\\p{L}\\p{M}]+)*")

    private var readerFont: Font {
        ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight)
    }

    private func piece(_ text: String, italic: Bool) -> AttributedString {
        var s = AttributedString(text)
        if italic { s.font = readerFont.italic() }
        return s
    }

    private func headingText(_ h: String) -> some View {
        Text(h)
            .font(ReadingFonts.font(fontFamily, size: fontSize * 0.92, weight: max(fontWeight, 600)))
            .foregroundStyle(pal.text)
            .padding(.top, 8)
    }

    private struct VerseBlock: Identifiable {
        let id: Int
        let heading: String?
        let verses: [Verse]
    }

    /// Стихи сплошным текстом: новый блок начинается с заголовка раздела
    private func blocks(_ verses: [Verse], _ heads: [Int: String]) -> [VerseBlock] {
        var out: [VerseBlock] = []
        var cur: [Verse] = []
        var head: String? = nil
        for v in verses {
            if let h = heads[v.num], !cur.isEmpty {
                out.append(VerseBlock(id: cur[0].num, heading: head, verses: cur))
                cur = []
                head = h
            } else if let h = heads[v.num] {
                head = h
            }
            cur.append(v)
        }
        if !cur.isEmpty { out.append(VerseBlock(id: cur[0].num, heading: head, verses: cur)) }
        return out
    }

    private func continuousText(_ blk: VerseBlock, _ xcounts: [Int: Int], _ icounts: [Int: Int]) -> AttributedString {
        var out = AttributedString()
        for v in blk.verses {
            var part = attributed(v, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true)
            if let bgc = continuousBackground(v.num) { part.backgroundColor = bgc }
            out += part
            out += AttributedString(" ")
        }
        return out
    }

    private func continuousBackground(_ n: Int) -> Color? {
        let c = background(n)
        return c == Color.clear ? nil : c
    }

    private func attributed(_ v: Verse, xrefs: Int, illus: Int, number: Bool, numberLink: Bool) -> AttributedString {
        var out = AttributedString()
        if showNumbers && number {
            var n = AttributedString("\(v.num) ")
            n.font = .system(size: fontSize * 0.62, weight: .semibold)
            if verseNumPos == "sup" { n.baselineOffset = fontSize * 0.32 }
            n.foregroundColor = pal.verseNum
            if numberLink { n.link = URL(string: "aobverse:\(v.num)") }
            out += n
        }
        if favNums.contains(v.num) {
            var h = AttributedString("♥ ")
            h.font = .system(size: fontSize * 0.62)
            h.foregroundColor = Color(hex: 0xd9475e)
            out += h
        }
        var wi = 0
        let sel = partRange(v.num)
        let fav = favPartRange(v.num)
        func mark(_ s: inout AttributedString, _ i: Int) {
            if let r = sel, r.contains(i) { s.backgroundColor = pal.accent.opacity(0.24) }
            else if let r = fav, r.contains(i) { s.backgroundColor = Color(hex: 0xd9475e).opacity(0.2) }
        }
        for (ti, t) in Markup.parse(v.text).enumerated() {
            if !t.strongs.isEmpty {
                // слово с номером Стронга — целиком одна ссылка на окно слова
                var s = piece(t.text, italic: t.italic)
                s.link = URL(string: "aobword:\(v.num),\(ti),-1")
                mark(&s, wi)
                wi += 1
                out += s
                if showStrongs {
                    // номера Стронга — ссылки: нажатие открывает словарную статью
                    for key in t.strongs {
                        var n = AttributedString(" " + key)
                        n.font = .system(size: fontSize * 0.55)
                        n.baselineOffset = fontSize * 0.3
                        n.foregroundColor = pal.accent
                        n.link = URL(string: "aobstrong:\(key)@\(v.num)")
                        out += n
                    }
                }
            } else {
                // обычный текст: каждое слово — ссылка, знаки между словами — просто текст
                let ns = t.text as NSString
                var pos = 0
                var k = 0
                for m in Self.wordRe.matches(in: t.text, range: NSRange(location: 0, length: ns.length)) {
                    if m.range.location > pos {
                        out += piece(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)), italic: t.italic)
                    }
                    var w = piece(ns.substring(with: m.range), italic: t.italic)
                    w.link = URL(string: "aobword:\(v.num),\(ti),\(k)")
                    mark(&w, wi)
                    wi += 1
                    out += w
                    k += 1
                    pos = m.range.location + m.range.length
                }
                if pos < ns.length {
                    out += piece(ns.substring(from: pos), italic: t.italic)
                }
            }
        }
        if xrefs > 0 {
            // число параллельных мест после стиха: нажатие открывает их список
            var n = AttributedString(" ⇅\(xrefs)")
            n.font = .system(size: fontSize * 0.62, weight: .medium)
            n.foregroundColor = pal.accent
            n.link = URL(string: "aobxref:\(v.num)")
            out += n
        }
        if illus > 0 {
            // иллюстрации к стиху: нажатие открывает их
            var n = AttributedString(" 🖼\(illus)")
            n.font = .system(size: fontSize * 0.62, weight: .medium)
            n.link = URL(string: "aobillus:\(v.num)")
            out += n
        }
        return out
    }

    /// Номер слова в стихе: слово с номером Стронга — одно слово, в обычном тексте — каждое слово отдельно
    private func partWordIndex(_ url: URL) -> Int? {
        let p = url.absoluteString.dropFirst("aobword:".count).split(separator: ",").map { Int($0) ?? -1 }
        guard p.count == 3, let raw = store.verseRaw(module: module.id, book: book, chapter: chapter, verse: p[0]) else { return nil }
        let toks = Markup.parse(raw)
        guard p[1] >= 0, p[1] < toks.count else { return nil }
        var n = 0
        for i in 0..<p[1] {
            n += toks[i].strongs.isEmpty ? Self.wordRe.numberOfMatches(in: toks[i].text, range: NSRange(location: 0, length: (toks[i].text as NSString).length)) : 1
        }
        return toks[p[1]].strongs.isEmpty ? n + max(p[2], 0) : n
    }

    private func verseWords(_ num: Int) -> [String] {
        guard let raw = store.verseRaw(module: module.id, book: book, chapter: chapter, verse: num) else { return [] }
        var out: [String] = []
        for t in Markup.parse(raw) {
            if !t.strongs.isEmpty { out.append(t.text); continue }
            let ns = t.text as NSString
            for m in Self.wordRe.matches(in: t.text, range: NSRange(location: 0, length: ns.length)) { out.append(ns.substring(with: m.range)) }
        }
        return out
    }

    private func partText(_ num: Int) -> String {
        guard let r = partRange(num) else { return "" }
        let w = verseWords(num)
        guard r.lowerBound < w.count else { return "" }
        return w[r.lowerBound...min(r.upperBound, w.count - 1)].joined(separator: " ")
    }

    private func endPart() {
        partVerse = nil
        partFrom = nil
        partTo = nil
    }

    /// Выбор части стиха прямо в тексте: нажмите первое и последнее слово — они закрашиваются; действия — под стихом
    private func partBar(_ v: Verse) -> some View {
        let text = partText(v.num)
        let short = Books.info(book)?.short ?? bookName
        let quote = "\"\(text)\" - \(short) \(chapter):\(v.num)"
        return VStack(spacing: 8) {
            if partFrom == nil {
                Text(partTo == nil ? "Нажмите первое и последнее слово части" : "")
                    .font(.footnote).foregroundStyle(pal.muted)
            }
            HStack(spacing: 4) {
                if !text.isEmpty, let r = partRange(v.num) {
                    barButton("heart", "В любимые") {
                        marks.setFavoritePart(book, chapter, v.num, text: text, part: Part(from: r.lowerBound, to: r.upperBound))
                        show("♥ Часть стиха — в любимых")
                        endPart()
                    }
                    Menu {
                        ForEach(sermons.sermons.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(10)) { s in
                            Button(s.title.isEmpty ? "Без названия" : s.title) { partToSermon(s.id, v.num, text) }
                        }
                        Button("Новая проповедь") { partToSermon(sermons.create("Новая проповедь").id, v.num, text) }
                    } label: { barLabel("scroll", "В проповедь") }
                    barButton("doc.on.doc", "Копировать") {
                        UIPasteboard.general.string = quote
                        show("Часть стиха скопирована")
                        endPart()
                    }
                }
                barButton("xmark", "Отмена") { endPart() }
            }
            .padding(.horizontal, 8)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.bottom, 8)
    }

    private func partToSermon(_ id: String, _ num: Int, _ text: String) {
        sermons.addVerses(to: id, items: [VerseItem(book: book, chapter: chapter, verse: num, text: text, moduleId: module.id, part: true)], moduleId: module.id)
        show("Добавлено в проповедь")
        endPart()
    }

    private func barLabel(_ icon: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.body)
            Text(title).font(.caption2).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 7)
        .frame(minHeight: 52)
    }

    private func barButton(_ icon: String, _ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(icon, title) }
            .buttonStyle(.plain)
    }

    /// Нажатие на слово: находим слово и его разметку (номера Стронга, морфология) и открываем окно слова
    private func openWord(_ url: URL) {
        let p = url.absoluteString.dropFirst("aobword:".count).split(separator: ",").map { Int($0) ?? -1 }
        guard p.count == 3, let raw = store.verseRaw(module: module.id, book: book, chapter: chapter, verse: p[0]) else { return }
        let toks = Markup.parse(raw)
        guard p[1] >= 0, p[1] < toks.count else { return }
        let t = toks[p[1]]
        var text = t.text
        if p[2] >= 0 {
            let ns = t.text as NSString
            let ms = Self.wordRe.matches(in: t.text, range: NSRange(location: 0, length: ns.length))
            guard p[2] < ms.count else { return }
            text = ns.substring(with: ms[p[2]].range)
        }
        word = WordRequest(text: text, strongs: t.strongs, morph: t.morph, book: book, chapter: chapter, verse: p[0])
    }

    // MARK: - Панель действий

    private func keys() -> [String] {
        selected.sorted().map { MarksStore.key(book, chapter, $0) }
    }

    private func rangeText() -> String {
        let nums = selected.sorted()
        guard let first = nums.first, let last = nums.last else { return "" }
        if nums.count == 1 { return "\(first)" }
        if last - first + 1 == nums.count { return "\(first)-\(last)" }
        return nums.map(String.init).joined(separator: ", ")
    }

    private func addToSermon(_ id: String, _ verses: [Verse]) {
        let items = verses.filter { selected.contains($0.num) }.map {
            VerseItem(book: book, chapter: chapter, verse: $0.num, text: Markup.plain($0.text), moduleId: module.id)
        }
        sermons.addVerses(to: id, items: items, moduleId: module.id)
        selected = []
        show("Добавлено в проповедь")
    }

    private func quote(_ verses: [Verse]) -> String {
        let text = verses.filter { selected.contains($0.num) }.map { Markup.plain($0.text) }.joined(separator: " ")
        let short = Books.info(book)?.short ?? bookName
        return "\"\(text)\" - \(short) \(chapter):\(rangeText())"
    }

    private func toggleFavorites(_ verses: [Verse], _ favorite: Bool) {
        for v in verses where selected.contains(v.num) && marks.isFavorite(MarksStore.key(book, chapter, v.num)) == favorite {
            marks.toggleFavorite(book, chapter, v.num, text: Markup.plain(v.text))
        }
        show(favorite ? "Убрано из любимых стихов" : "♥ Добавлено в любимые стихи")
        selected = []
    }

    private func selectionBar(_ verses: [Verse]) -> some View {
        let first = selected.sorted().first ?? 1
        let bookmarked = marks.isBookmarked(book, chapter, first)
        let favorite = !selected.isEmpty && selected.allSatisfy { marks.isFavorite(MarksStore.key(book, chapter, $0)) }
        return HStack(spacing: 4) {
            barButton("headphones", "Слушать") {
                Task { await audio.listen(store: store, moduleId: module.id, from: Place(book: book, chapter: chapter, verse: first)) }
                selected = []
            }
            Menu {
                ForEach(sermons.sermons.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(10)) { s in
                    Button(s.title.isEmpty ? "Без названия" : s.title) { addToSermon(s.id, verses) }
                }
                Button("Новая проповедь") {
                    let s = sermons.create("Новая проповедь")
                    addToSermon(s.id, verses)
                }
            } label: { barLabel("scroll", "В проповедь") }
            if selected.count == 1 {
                barButton("selection.pin.in.out", "Часть стиха") {
                    partVerse = first
                    partFrom = nil
                    partTo = nil
                    selected = []
                }
            }
            barButton("text.alignleft", "Подстрочник") { panel = .interlinear(first) }
            Menu {
                Menu {
                    ForEach(hlColors) { c in
                        Button {
                            marks.setHighlight(keys: keys(), color: c.id)
                            selected = []
                        } label: {
                            Label(marks.colorName(c), systemImage: "circle.fill")
                        }
                        .tint(c.color)
                    }
                    Button("Убрать выделение цветом", role: .destructive) {
                        marks.setHighlight(keys: keys(), color: nil)
                        selected = []
                    }
                } label: { Label("Выделить цветом", systemImage: "highlighter") }
                Button {
                    toggleFavorites(verses, favorite)
                } label: { Label(favorite ? "Убрать из любимых" : "В любимые", systemImage: favorite ? "heart.slash" : "heart") }
                Button {
                    if let v = verses.first(where: { $0.num == first }) {
                        marks.toggleBookmark(book, chapter, v.num, text: String(Markup.plain(v.text).prefix(160)))
                        show(bookmarked ? "Закладка удалена" : "Закладка: \(Books.info(book)?.short ?? bookName) \(chapter):\(first)")
                    }
                    selected = []
                } label: { Label(bookmarked ? "Убрать закладку" : "Закладка", systemImage: bookmarked ? "bookmark.slash" : "bookmark") }
                Button {
                    noteText = marks.note(MarksStore.key(book, chapter, first)) ?? ""
                    noteVerse = first
                } label: { Label("Заметка", systemImage: "note.text") }
                Button {
                    UIPasteboard.general.string = quote(verses)
                    show(selected.count > 1 ? "Скопировано стихов: \(selected.count)" : "Стих скопирован")
                    selected = []
                } label: { Label("Копировать", systemImage: "doc.on.doc") }
                ShareLink(item: quote(verses)) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                Divider()
                Button {
                    collectItems = verses.filter { selected.contains($0.num) }.map {
                        MarkItem(book: book, chapter: chapter, verse: $0.num, text: Markup.plain($0.text))
                    }
                    panel = .collect(first)
                    selected = []
                } label: { Label("В подборку…", systemImage: "folder.badge.plus") }
                Button { panel = .commentary(first) } label: { Label("Толкования", systemImage: "text.book.closed") }
                if selected.count == 1 {
                    Button { panel = .xrefs(first) } label: { Label("Параллельные места", systemImage: "arrow.triangle.branch") }
                }
                Button { panel = .compare(first) } label: { Label("Сравнить переводы", systemImage: "rectangle.on.rectangle") }
                Button {
                    let t = verses.filter { selected.contains($0.num) }.map { Markup.plain($0.text) }.joined(separator: " ")
                    imageReq = ImageRequest(text: t, ref: "\(bookName) \(chapter):\(rangeText())")
                    selected = []
                } label: { Label("Картинка со стихом", systemImage: "photo") }
                Menu {
                    ForEach(store.bibles) { m in
                        Button(m.name + " — " + m.title) {
                            panes.addPane(after: pane.id, moduleId: m.id)
                            selected = []
                        }
                    }
                } label: { Label("Перевод рядом", systemImage: "rectangle.split.2x1") }
                    .disabled(panes.panes.count >= maxPanes)
                Divider()
                Button { selected = [] } label: { Label("Снять выделение", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 52)
            }
            .accessibilityLabel("Ещё")
        }
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 8)
    }

    private var noteEditor: some View {
        NavigationStack {
            TextEditor(text: $noteText)
                .padding(12)
                .navigationTitle("Заметка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { noteVerse = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            if let v = noteVerse { marks.setNote(MarksStore.key(book, chapter, v), noteText) }
                            noteVerse = nil
                            selected = []
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

/// Сравнение: один и тот же стих во всех установленных переводах
struct CompareSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let book: String
    let chapter: Int
    let verse: Int

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.bibles) { m in
                    if let t = store.verseText(module: m.id, book: book, chapter: chapter, verse: verse) {
                        Section {
                            Text(t).font(.system(size: 18, design: .serif))
                        } header: {
                            Text("\(m.name) — \(m.title)")
                        }
                    }
                }
            }
            .navigationTitle("Сравнить переводы")
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

// MARK: - Навигатор

private struct BookCategory {
    let title: String
    let color: Color
    let ids: [String]
}

private let bookCategories: [BookCategory] = [
    BookCategory(title: "Пятикнижие", color: Color(red: 0.69, green: 0.48, blue: 0.18), ids: ["Gen", "Exod", "Lev", "Num", "Deut"]),
    BookCategory(title: "Исторические книги", color: Color(red: 0.42, green: 0.56, blue: 0.31), ids: ["Josh", "Judg", "Ruth", "1Sam", "2Sam", "1Kgs", "2Kgs", "1Chr", "2Chr", "Ezra", "Neh", "Esth"]),
    BookCategory(title: "Поэтические книги", color: Color(red: 0.25, green: 0.5, blue: 0.65), ids: ["Job", "Ps", "Prov", "Eccl", "Song"]),
    BookCategory(title: "Большие пророки", color: Color(red: 0.55, green: 0.29, blue: 0.49), ids: ["Isa", "Jer", "Lam", "Ezek", "Dan"]),
    BookCategory(title: "Малые пророки", color: Color(red: 0.69, green: 0.41, blue: 0.56), ids: ["Hos", "Joel", "Amos", "Obad", "Jonah", "Mic", "Nah", "Hab", "Zeph", "Hag", "Zech", "Mal"]),
    BookCategory(title: "Неканонические книги", color: Color(red: 0.54, green: 0.51, blue: 0.45), ids: ["PrMan", "1Esd", "Tob", "Jdt", "Wis", "Sir", "EpJer", "Bar", "1Macc", "2Macc", "3Macc", "2Esd"]),
    BookCategory(title: "Евангелия", color: Color(red: 0.75, green: 0.33, blue: 0.23), ids: ["Matt", "Mark", "Luke", "John"]),
    BookCategory(title: "Деяния и соборные послания", color: Color(red: 0.18, green: 0.56, blue: 0.51), ids: ["Acts", "Jas", "1Pet", "2Pet", "1John", "2John", "3John", "Jude"]),
    BookCategory(title: "Послания апостола Павла", color: Color(red: 0.29, green: 0.41, blue: 0.68), ids: ["Rom", "1Cor", "2Cor", "Gal", "Eph", "Phil", "Col", "1Thess", "2Thess", "1Tim", "2Tim", "Titus", "Phlm", "Heb"]),
    BookCategory(title: "Откровение", color: Color(red: 0.48, green: 0.33, blue: 0.66), ids: ["Rev"]),
]

private struct ChapterPick: Hashable {
    let book: ModuleBook
    let chapter: Int
}

/// Перейти: ссылка в поле, недавние книги, книги по разделам (цвет — раздел) → главы → стихи
struct GotoSheet: View {
    @EnvironmentObject private var store: ModuleStore
    let module: InstalledModule
    let recents: [String]
    let current: String
    let onPick: (String, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var linkError = false
    @State private var path = NavigationPath()

    private func book(_ id: String) -> ModuleBook? {
        module.books.first { $0.id == id }
    }

    private func submitLink() {
        guard let r = RefParser.parse(link), let b = book(r.book), r.chapter >= 1, r.chapter <= max(1, b.chapters) else {
            linkError = true
            return
        }
        onPick(r.book, r.chapter, r.verse)
        dismiss()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        TextField("Книга или ссылка: Ин 3:16", text: $link)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(submitLink)
                            .onChange(of: link) { _, _ in linkError = false }
                        Button(action: submitLink) {
                            Image(systemName: "arrow.right.circle.fill").font(.title2)
                        }
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.fill.tertiary, in: Capsule())
                    if linkError {
                        Text("Не нашёл такое место в этом переводе.").font(.footnote).foregroundStyle(.red)
                    }

                    let rec = recents.compactMap { book($0) }
                    if !rec.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                                ForEach(rec) { b in
                                    Button { path.append(b) } label: {
                                        Text(b.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(b.id == current ? Color.white : Color.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(b.id == current ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ForEach(sections(), id: \.title) { sec in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(LocalizedStringKey(sec.title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(sec.books) { b in
                                    Button { path.append(b) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(b.short.replacingOccurrences(of: ".", with: "")).font(.headline)
                                                .foregroundStyle(b.id == current ? Color.white : Color.primary)
                                            Text(b.name).font(.caption).foregroundStyle(b.id == current ? Color.white.opacity(0.85) : Color.secondary).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .background(b.id == current ? Color.accentColor : sec.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Перейти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .navigationDestination(for: ModuleBook.self) { b in
                ChapterGrid(book: b) { c in path.append(ChapterPick(book: b, chapter: c)) }
            }
            .navigationDestination(for: ChapterPick.self) { p in
                VerseGrid(module: module, pick: p) { v in
                    onPick(p.book.id, p.chapter, v)
                    dismiss()
                }
            }
        }
    }

    private struct Section2 {
        let title: String
        let color: Color
        let books: [ModuleBook]
    }

    private func sections() -> [Section2] {
        var out: [Section2] = []
        var used = Set<String>()
        for c in bookCategories {
            let list = c.ids.compactMap { book($0) }
            list.forEach { used.insert($0.id) }
            if !list.isEmpty { out.append(Section2(title: c.title, color: c.color, books: list)) }
        }
        let rest = module.books.filter { !used.contains($0.id) }
        if !rest.isEmpty { out.append(Section2(title: "Другие книги", color: .gray, books: rest)) }
        return out
    }
}

struct ChapterGrid: View {
    let book: ModuleBook
    let onPick: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                ForEach(1...max(1, book.chapters), id: \.self) { n in
                    Button { onPick(n) } label: {
                        Text("\(n)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
            .padding(16)
        }
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Номера стихов главы; «Читать главу» — с начала
private struct VerseGrid: View {
    @EnvironmentObject private var store: ModuleStore
    let module: InstalledModule
    let pick: ChapterPick
    let onPick: (Int) -> Void

    var body: some View {
        let counts = store.verseCounts(module: module.id, book: pick.book.id)
        let n = counts[pick.chapter] ?? 0
        ScrollView {
            VStack(spacing: 14) {
                Button { onPick(0) } label: {
                    Label("Читать главу \(pick.chapter)", systemImage: "book")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                if n > 0 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                        ForEach(1...n, id: \.self) { v in
                            Button { onPick(v) } label: {
                                Text("\(v)")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("\(pick.book.name) \(pick.chapter)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
