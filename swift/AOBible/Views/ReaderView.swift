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
                GotoSheet(module: m, recents: panes.recentBooks()) { b, c, v in
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
                Text(m.name).font(.subheadline.weight(.semibold)).fixedSize()
            }
            .buttonStyle(.glass)
            Button { showGoto = true } label: {
                HStack(spacing: 4) {
                    Text("\(bookName(p, m)) \(p.chapter)").font(.subheadline.weight(.semibold)).fixedSize()
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
            Menu {
                if panes.panes.count < maxPanes {
                    Button { panes.addPane(after: paneID, moduleId: p.moduleId) } label: {
                        Label("Добавить панель", systemImage: "rectangle.split.2x1")
                    }
                }
                if panes.panes.count > 1 {
                    Button { stacked.toggle() } label: {
                        Label(stacked ? "Панели рядом" : "Панели друг над другом", systemImage: "rectangle.split.1x2")
                    }
                    Button(role: .destructive) { panes.closePane(paneID) } label: {
                        Label("Закрыть панель", systemImage: "xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

enum StudyPanel: Identifiable {
    case commentary(Int)
    case xrefs(Int)
    case compare(Int)
    case interlinear(Int)
    case illustrations(Int)

    var id: String {
        switch self {
        case .commentary(let v): return "c\(v)"
        case .xrefs(let v): return "x\(v)"
        case .compare(let v): return "v\(v)"
        case .interlinear(let v): return "i\(v)"
        case .illustrations(let v): return "p\(v)"
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
                                    .overlay(alignment: .topTrailing) {
                                        HStack(spacing: 4) {
                                            if marks.isFavorite(MarksStore.key(book, chapter, v.num)) {
                                                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
                                            }
                                            if marks.isBookmarked(book, chapter, v.num) {
                                                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { marks.toggleFavorite(book, chapter, v.num, text: Markup.plain(v.text)) }
                                    // выделение уже есть — нажатие добавляет и снимает стихи; без него стих выделяется
                                    // долгим нажатием (нажатие на слово открывает словарь)
                                    .onTapGesture { if !selected.isEmpty { toggle(v.num) } }
                                    .onLongPressGesture(minimumDuration: 0.3) {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        selected.insert(v.num)
                                    }
                                if !continuous, v.num == selected.max() {
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
                .padding(.horizontal, textMargin)
                .padding(.vertical, 12)
            }
            .background(pal.bg)
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
            if let k = StrongLinks.key(from: url) {
                strong = StrongRequest(key: k)
                return .handled
            }
            if url.scheme == "aobxref", let v = Int(url.absoluteString.dropFirst("aobxref:".count)) {
                panel = .xrefs(v)
                return .handled
            }
            if url.scheme == "aobword" {
                openWord(url)
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
            }
        }
    }

    /// Глава, её заголовки, числа параллельных мест и иллюстраций и готовый текст стихов — собираются один раз и
    /// пересобираются только при смене главы, перевода или оформления (выделение стиха их не трогает)
    private func chapterData() -> ChapterCache {
        let key = "\(module.id)|\(book)|\(chapter)|\(fontSize)|\(fontFamily)|\(fontWeight)|\(showNumbers)|\(showStrongs)|\(verseNumPos)|\(showXrefs)|\(showIllus)|\(theme)|\(store.installed.count)"
        if let c = cacheBox.value, c.key == key { return c }
        let verses = store.verses(module: module.id, book: book, chapter: chapter)
        let heads = store.headings(module: module.id, book: book, chapter: chapter)
        let xcounts = showXrefs ? store.xrefCounts(module: module.id, book: book, chapter: chapter) : [:]
        let icounts = showIllus ? store.illustrationCounts(book: book, chapter: chapter) : [:]
        var attr: [Int: AttributedString] = [:]
        for v in verses {
            attr[v.num] = attributed(v, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: false)
        }
        let c = ChapterCache(key: key, verses: verses, heads: heads, xcounts: xcounts, icounts: icounts, attr: attr)
        cacheBox.value = c
        return c
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

    private func background(_ n: Int) -> Color {
        if selected.contains(n) { return pal.accent.opacity(0.22) }
        // звучащий стих подсвечен
        if audio.active, audio.moduleId == module.id, let c = audio.current, c.book == book, c.chapter == chapter, c.verse == n {
            return pal.accent.opacity(0.16)
        }
        if let c = hlColor(marks.highlight(MarksStore.key(book, chapter, n))) {
            return c.color.opacity(0.4)
        }
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
        for (ti, t) in Markup.parse(v.text).enumerated() {
            if !t.strongs.isEmpty {
                // слово с номером Стронга — целиком одна ссылка на окно слова
                var s = piece(t.text, italic: t.italic)
                s.link = URL(string: "aobword:\(v.num),\(ti),-1")
                out += s
                if showStrongs {
                    // номера Стронга — ссылки: нажатие открывает словарную статью
                    for key in t.strongs {
                        var n = AttributedString(" " + key)
                        n.font = .system(size: fontSize * 0.55)
                        n.baselineOffset = fontSize * 0.3
                        n.foregroundColor = pal.accent
                        n.link = URL(string: "aobstrong:" + key)
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
        return nums.map(String.init).joined(separator: ",")
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
        return "\(text)\n— \(bookName) \(chapter):\(rangeText()) (\(module.name))"
    }

    private func selectionBar(_ verses: [Verse]) -> some View {
        let first = selected.sorted().first ?? 1
        let bookmarked = marks.isBookmarked(book, chapter, first)
        let favorite = marks.isFavorite(MarksStore.key(book, chapter, first))
        return HStack(spacing: 20) {
            Button {
                UIPasteboard.general.string = quote(verses)
                selected = []
            } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("Копировать")
            ShareLink(item: quote(verses)) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Поделиться")
            Menu {
                ForEach(hlColors) { c in
                    Button {
                        marks.setHighlight(keys: keys(), color: c.id)
                        selected = []
                    } label: {
                        Label(c.name, systemImage: "circle.fill")
                    }
                    .tint(c.color)
                }
                Button("Убрать подсветку", role: .destructive) {
                    marks.setHighlight(keys: keys(), color: nil)
                    selected = []
                }
            } label: { Image(systemName: "highlighter") }
                .accessibilityLabel("Подсветка")
            Button {
                for v in verses where selected.contains(v.num) && marks.isBookmarked(book, chapter, v.num) == bookmarked {
                    marks.toggleBookmark(book, chapter, v.num, text: Markup.plain(v.text))
                }
                selected = []
            } label: { Image(systemName: bookmarked ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel("Закладка")
            Button {
                noteText = marks.note(MarksStore.key(book, chapter, first)) ?? ""
                noteVerse = first
            } label: { Image(systemName: "note.text") }
                .accessibilityLabel("Заметка")
            Menu {
                Button { panel = .commentary(first) } label: { Label("Толкования", systemImage: "text.book.closed") }
                Button { panel = .xrefs(first) } label: { Label("Параллельные места", systemImage: "arrow.triangle.branch") }
                Button { panel = .compare(first) } label: { Label("Сравнить переводы", systemImage: "rectangle.on.rectangle") }
                Button { panel = .interlinear(first) } label: { Label("Подстрочник", systemImage: "text.alignleft") }
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
                Button {
                    for v in verses where selected.contains(v.num) && marks.isFavorite(MarksStore.key(book, chapter, v.num)) == favorite {
                        marks.toggleFavorite(book, chapter, v.num, text: Markup.plain(v.text))
                    }
                    selected = []
                } label: { Label(favorite ? "Убрать из любимых" : "В любимые", systemImage: favorite ? "heart.slash" : "heart") }
                Button {
                    Task { await audio.listen(store: store, moduleId: module.id, from: Place(book: book, chapter: chapter, verse: first)) }
                    selected = []
                } label: { Label("Слушать", systemImage: "headphones") }
                Menu {
                    ForEach(sermons.sermons.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(10)) { s in
                        Button(s.title.isEmpty ? "Без названия" : s.title) { addToSermon(s.id, verses) }
                    }
                    Button("Новая проповедь") {
                        let s = sermons.create("Новая проповедь")
                        addToSermon(s.id, verses)
                    }
                } label: { Label("В проповедь", systemImage: "scroll") }
                Button { selected = [] } label: { Label("Снять выделение", systemImage: "xmark") }
            } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Ещё")
        }
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
                                        Text(b.name).font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }

                    ForEach(sections(), id: \.title) { sec in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Circle().fill(sec.color).frame(width: 8, height: 8)
                                Text(LocalizedStringKey(sec.title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(sec.books) { b in
                                    Button { path.append(b) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(b.short.replacingOccurrences(of: ".", with: "")).font(.headline)
                                            Text(b.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .background(sec.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
