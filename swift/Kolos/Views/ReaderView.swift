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
                            PaneView(paneID: p.id, chrome: panes.chrome)
                            if p.id != panes.panes.last?.id { Divider() }
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(panes.panes) { p in
                            PaneView(paneID: p.id, chrome: panes.chrome)
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
                ScrollSync.debugSetup(store: store, panes: panes)
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
    @EnvironmentObject private var plans: PlansStore
    @Environment(\.readerPalette) private var pal
    @State private var planDay: PlanReturn?
    @State private var headerH: CGFloat = 52
    @AppStorage("ilBar") private var ilBar = true
    /// Кнопка «свернуть» панели подстрочника и кнопка фильтра в шапке — одна и та же кнопка, перетекает при скрытии
    @AppStorage("panesStacked") private var stacked = true
    let paneID: UUID
    @ObservedObject var chrome: ChromeState
    @State private var showGoto = UserDefaults.standard.bool(forKey: "debugGoto")
    @State private var showModules = false

    private var pane: PaneState? {
        panes.panes.first { $0.id == paneID }
    }

    var body: some View {
        if let p = pane, let m = store.module(p.moduleId) {
            VStack(spacing: 0) {
                ChapterText(module: m, pane: p)
                    // шапка лежит поверх текста и сама уходит вверх / возвращается; место под ней в тексте постоянное,
                    // поэтому прокрутку она не двигает. Под ней — мягкий градиент, текст у верхнего края как бы растворяется
                    .overlay(alignment: .top) { chromeOverlay(p, m) }
                    .safeAreaInset(edge: .bottom) {
                        if panes.panes.count == 1 {
                        HStack {
                            Spacer()
                            Button {
                                Task { await audio.listen(store: store, moduleId: p.moduleId, from: Place(book: p.book, chapter: p.chapter, verse: max(1, p.verse))) }
                            } label: { Image(systemName: "headphones").font(.title3) }
                                .accessibilityLabel("Слушать")
                            Spacer()
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .offset(y: chrome.hidden[paneID] == true && !panes.isLowerPane(paneID) ? chrome.bottomShift : 0)
                        }
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: chrome.hidden[paneID])
            .sheet(item: Binding(get: { planDay }, set: { planDay = $0 })) { r in
                PlanDayView(uid: r.uid, day: r.day)
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
                        // выбрали перевод — окно закрывается само
                        // сначала закрываем окно, потом перестраиваем панель: окно не «висит» на время перерисовки текста
                        set: { id in
                            showModules = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { panes.setModule(paneID, id, store) }
                        }
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

    /// «К плану · 2 из 4»: ушли из плана читать дальше — кнопка возвращает на страницу дня
    @ViewBuilder private func planPill(_ p: PaneState) -> some View {
        if panes.panes.first?.id == p.id, let r = plans.returnTo, let plan = plans.plans.first(where: { $0.uid == r.uid }), r.day < plan.readings.count {
            let units = PlanLogic.dayUnits(plan, r.day)
            let done = units.filter { PlanLogic.unitDone(plan, r.day, $0.key) }.count
            HStack(spacing: 4) {
                Button { planDay = r; plans.returnTo = nil } label: {
                    Label("К плану · \(done) из \(units.count)", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
                Button { plans.returnTo = nil } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).padding(.trailing, 12).padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 4)
        }
    }

    private func bookName(_ p: PaneState, _ m: InstalledModule) -> String {
        m.books.first { $0.id == p.book }?.short.replacingOccurrences(of: ".", with: "") ?? Books.info(p.book)?.short ?? p.book
    }

    /// Высота шапки: столько оставлено в начале текста (постоянно, чтобы шапка не двигала текст)
    static let headerHeight: CGFloat = 52
    /// Компактная шапка — когда панелей несколько: меньше кнопки, всё в одной строке, плавающих кнопок нет
    static let compactHeaderHeight: CGFloat = 38

    @ViewBuilder private func chromeOverlay(_ p: PaneState, _ m: InstalledModule) -> some View {
        // нижняя панель при параллельном чтении: шапка на месте (не прячется), без отступа под строку состояния
        let lower = panes.isLowerPane(paneID)
        let hidden = chrome.hidden[paneID] == true && !lower
        // полоса прочтения лежит под шапкой; когда шапка ушла — поднимается к самому верху экрана.
        // От полосы до верхнего края всегда размытый фон
        let barShown = m.interlinear && ilBar
        // высота фона шапки меняется вместе с панелью подстрочника (плавно, SlidingChrome её анимирует)
        SlidingChrome(p: hidden ? 1 : 0, headerH: headerH + (barShown ? InterlinearBar.height : 0), safeTop: lower ? 0 : Self.safeTop) {
            ZStack(alignment: .topLeading) {
                // панель подстрочника лежит ПОД строкой шапки: при скрытии уезжает вверх за кнопки перевода и книги
                // и растворяется под ними
                if m.interlinear {
                    InterlinearBar()
                        .padding(.top, barShown ? headerH : max(0, headerH - InterlinearBar.height))
                        .opacity(barShown ? 1 : 0)
                        .allowsHitTesting(barShown)
                }
                VStack(spacing: 0) {
                    header(p, m)
                    planPill(p)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerH = $0 }
            }
            .frame(height: headerH + (barShown ? InterlinearBar.height : 0), alignment: .top)
            // одна кнопка на оба положения: в панели — «свернуть», в шапке — «фильтр»; иконка превращается
            // место считается явно (а не matchedGeometryEffect: тот при запуске не успевал пересчитаться, и кнопка
            // вставала поверх кнопки «две панели»). В шапке — сразу слева от неё, в панели — у правого края
            .overlay(alignment: .topLeading) {
                if m.interlinear {
                    GeometryReader { g in
                        let barTop = barShown ? headerH : max(0, headerH - InterlinearBar.height)
                        let compact = panes.panes.count > 1
                        ilToggle.position(ilBar ? CGPoint(x: g.size.width - 40, y: barTop + 20) : (compact ? CGPoint(x: g.size.width - 99, y: 19) : CGPoint(x: g.size.width - 88, y: 26)))
                    }
                }
            }
            .animation(InterlinearBar.motion, value: ilBar)
            .allowsHitTesting(!hidden)
        } line: {
            ReadProgress(live: panes.live, id: paneID)
        }
        .animation(.easeInOut(duration: 0.2), value: hidden)
    }

    /// Кнопка панели подстрочника: стоит на месте ilSlot (в панели или в шапке), при переключении переезжает,
    /// а иконка векторно превращается: стрелка «свернуть» ⇄ «фильтр»
    private var ilToggle: some View {
        Button { withAnimation(InterlinearBar.motion) { ilBar.toggle() } } label: {
            Image(systemName: ilBar ? "chevron.up" : "slider.horizontal.3")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .chromeCircle(panes.panes.count > 1 && !ilBar ? 30 : 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ilBar ? "Свернуть" : "Подстрочник")
    }

    /// Высота системной строки состояния (до края экрана)
    static var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top) ?? 54
    }

    private func header(_ p: PaneState, _ m: InstalledModule) -> some View {
        Group {
            if panes.panes.count > 1 { compactHeader(p, m) } else { fullHeader(p, m) }
        }
    }

    /// Несколько панелей: одна тонкая строка — перевод, место, меню «⋯» (история, «Слушать», «Добавить панель») и закрытие
    private func compactHeader(_ p: PaneState, _ m: InstalledModule) -> some View {
        HStack(spacing: 6) {
            Button { showModules = true } label: {
                Text(m.shortName).font(.subheadline.weight(.semibold)).fixedSize().chromePill(compact: true)
            }
            .buttonStyle(.plain)
            Button { showGoto = true } label: {
                HStack(spacing: 4) {
                    LiveTitle(live: panes.live, id: paneID, name: bookName(p, m), chapter: p.chapter, fallback: max(p.verse, 1))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .chromePill(compact: true)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 2)
            if m.interlinear && !ilBar {
                // место кнопки фильтра подстрочника (она в ilToggle)
                Color.clear.frame(width: 30, height: 30)
            }
            Menu {
                if panes.canBack(paneID) {
                    Button { panes.back(paneID) } label: { Label("Назад", systemImage: "arrow.uturn.backward") }
                }
                if panes.canForward(paneID) {
                    Button { panes.forward(paneID) } label: { Label("Вперёд", systemImage: "arrow.uturn.forward") }
                }
                Button {
                    Task { await audio.listen(store: store, moduleId: p.moduleId, from: Place(book: p.book, chapter: p.chapter, verse: max(1, p.verse))) }
                } label: { Label("Слушать", systemImage: "headphones") }
                Button { panes.addPane(after: paneID, moduleId: p.moduleId) } label: { Label("Добавить панель", systemImage: "rectangle.split.2x1") }
                    .disabled(panes.panes.count >= maxPanes)
            } label: {
                Image(systemName: "ellipsis").chromeCircle(30)
            }
            .accessibilityLabel("Ещё")
            Button { panes.closePane(paneID) } label: { Image(systemName: "xmark").chromeCircle(30) }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть панель")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func fullHeader(_ p: PaneState, _ m: InstalledModule) -> some View {
        HStack(spacing: 8) {
            Button { showModules = true } label: {
                Text(m.shortName).font(.headline).fixedSize().chromePill()
            }
            .buttonStyle(.plain)
            Button { showGoto = true } label: {
                HStack(spacing: 5) {
                    LiveTitle(live: panes.live, id: paneID, name: bookName(p, m), chapter: p.chapter, fallback: max(p.verse, 1))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .font(.headline)
                .chromePill()
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            if panes.canBack(paneID) {
                Button { panes.back(paneID) } label: { Image(systemName: "arrow.uturn.backward").chromeCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")
            }
            if panes.canForward(paneID) {
                Button { panes.forward(paneID) } label: { Image(systemName: "arrow.uturn.forward").chromeCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Вперёд")
            }
            if panes.panes.count > 1 {
                Button { panes.closePane(paneID) } label: { Image(systemName: "xmark").chromeCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть панель")
            }
            if m.interlinear && !ilBar {
                // место кнопки фильтра; сама кнопка — в ilToggle (переезжает сюда из панели)
                Color.clear.frame(width: 40, height: 40)
            }
            Button { panes.addPane(after: paneID, moduleId: p.moduleId) } label: { Image(systemName: "rectangle.split.2x1").chromeCircle() }
                .buttonStyle(.plain)
                .disabled(panes.panes.count >= maxPanes)
                .opacity(panes.panes.count >= maxPanes ? 0.4 : 1)
                .accessibilityLabel("Добавить панель")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

/// Насколько потянули за край главы (в точках): по нему показывается подсказка, а при отпускании — переход к соседней главе
@MainActor
final class PullState: ObservableObject {
    /// Сколько тянуть, чтобы глава сменилась: чуть больше прежних 70 — быстрая прокрутка не листает главу случайно
    static let threshold: CGFloat = 92
    private(set) var bottom: CGFloat = 0
    private(set) var top: CGFloat = 0
    /// Для подсказки: меняется плавно вместе с пальцем (перерисовывается только сама подсказка)
    @Published private(set) var bottomShown: CGFloat = 0
    @Published private(set) var topShown: CGFloat = 0
    /// Уже «Отпустите» — вибрация один раз при переходе через порог (без звука)
    private var bottomReady = false
    private var topReady = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private func crossed(_ v: CGFloat, _ was: inout Bool) {
        let now = v >= Self.threshold
        if now && !was { haptic.impactOccurred() } else if !now && v > 20 && !was { haptic.prepare() }
        was = now
    }

    func setBottom(_ v: CGFloat) {
        bottom = v
        bottomShown = v
        crossed(v, &bottomReady)
        #if DEBUG
        if v > 5 { SyncTrace.write("P,bottom,\(v)") }
        #endif
    }

    func setTop(_ v: CGFloat) {
        top = v
        topShown = v
        crossed(v, &topReady)
    }
}

/// Подсказка у края (как «Новый чат» в ChatGPT): кольцо заполняется вслед за пальцем, под ним — что откроется.
/// Кольцо замкнулось — можно отпускать (вибрация — в PullState)
struct PullHint: View {
    @ObservedObject var state: PullState
    let next: Bool
    let label: (kind: String, name: String)?
    @Environment(\.readerPalette) private var pal

    var body: some View {
        let v = next ? state.bottomShown : state.topShown
        // появляется, когда текст отъехал настолько, что кольцо с подписью помещается в открывшийся промежуток
        // (раньше вылезало поверх заголовка главы); заполняется до порога смены главы
        let start: CGFloat = 48
        if v > start, let label {
            let ready = v >= PullState.threshold
            let progress = min(1, max(0, (v - start) / (PullState.threshold - start)))
            let k = min(1, (v - start) / 16)
            // стоит посередине открывшегося промежутка (кольцо с подписью — около 60 пт)
            let shift = max(0, (v - 60) / 2)
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(pal.muted.opacity(0.25), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(pal.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: next ? "arrow.up" : "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.accent)
                        .opacity(ready ? 1 : 0)
                        .scaleEffect(ready ? 1 : 0.5)
                }
                .frame(width: 34, height: 34)
                .scaleEffect(ready ? 1.08 : 1)
                Text(ready ? "Отпустите" : label.name)
                    .font(.subheadline.weight(ready ? .semibold : .regular))
                    .foregroundStyle(ready ? pal.text : pal.muted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .fixedSize()
            .opacity(k)
            .offset(y: next ? -shift : shift)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ready)
            .allowsHitTesting(false)
        }
    }
}

/// Шапка, полоска прочтения и размытый фон двигаются одним анимируемым значением p (0 — шапка на месте, 1 — ушла):
/// шапка уезжает за верхний край, полоска всё время висит под ней и останавливается у верха экрана, размытие — до полоски
struct SlidingChrome<Header: View, Line: View>: View, Animatable {
    @Environment(\.readerPalette) private var pal
    var p: CGFloat
    var headerH: CGFloat
    let safeTop: CGFloat
    let header: Header
    let line: Line

    init(p: CGFloat, headerH: CGFloat, safeTop: CGFloat, @ViewBuilder header: () -> Header, @ViewBuilder line: () -> Line) {
        self.p = p
        self.headerH = headerH
        self.safeTop = safeTop
        self.header = header()
        self.line = line()
    }

    /// Анимируются и уход шапки (p), и её высота (появилась или скрылась панель подстрочника)
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(p, headerH) }
        set {
            p = newValue.first
            headerH = newValue.second
        }
    }

    var body: some View {
        let travel = headerH + safeTop + 12
        let shift = p * travel
        let lineY = max(0, headerH - shift)
        ZStack(alignment: .top) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(pal.bg.opacity(0.55))
            }
                .frame(height: safeTop + lineY)
                .offset(y: -safeTop)
                .allowsHitTesting(false)
            header
                .offset(y: -shift)
            line
                .offset(y: lineY)
                .allowsHitTesting(false)
        }
    }
}

/// Какое окно слова / Стронга открыть. Отдельный объект: его смена перерисовывает только StudySheets, а не главу
enum StudySheet: Identifiable {
    case word(WordRequest)
    case dict(DictRequest)

    var id: String {
        switch self {
        case .word(let r): return "w" + r.id.uuidString
        case .dict(let r): return "d" + r.id.uuidString
        }
    }
}

@MainActor
final class StudyRequests: ObservableObject {
    @Published var sheet: StudySheet?
    var openedAt = Date.distantPast
    /// Окно на экране (в том числе пока уезжает вниз после закрытия)
    private var onScreen = false
    /// Нажали другое слово, пока прежнее окно ещё уезжало: SwiftUI в это время новое окно не показывает
    /// (запрос терялся — приходилось ждать и нажимать снова). Откроем сразу, как только прежнее закроется
    private var pending: StudySheet?

    func open(_ s: StudySheet) {
        if sheet == nil && onScreen {
            pending = s
            // страховка: если система не сообщила о закрытии — всё равно открыть, окна не должны «застрять»
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.pending?.id == s.id, self.sheet == nil else { return }
                self.pending = nil
                self.onScreen = false
                self.sheet = s
            }
        } else {
            sheet = s
        }
    }

    func appeared() { onScreen = true }

    func dismissed() {
        onScreen = false
        guard let p = pending else { return }
        pending = nil
        DispatchQueue.main.async { [weak self] in self?.sheet = p }
    }
}

/// Окна слова: список словарей у слова → статья (выбор строки закрывает список и открывает статью)
struct StudySheets: View {
    @ObservedObject var req: StudyRequests
    @EnvironmentObject private var store: ModuleStore
    var onOpenRef: (String, Int, Int) -> Void

    var body: some View {
        Color.clear
            .sheet(item: $req.sheet, onDismiss: { req.dismissed() }) { s in
                sheetContent(s).onAppear { req.appeared() }
            }
    }

    @ViewBuilder private func sheetContent(_ s: StudySheet) -> some View {
                switch s {
                case .word(let r):
                    WordSheet(req: r) { moduleId, key in
                        var d = DictRequest(text: r.text, strongs: r.strongs, morph: r.morph, book: r.book, chapter: r.chapter, verse: r.verse)
                        d.preselect = (moduleId, key)
                        d.wordIndex = r.wordIndex
                        d.origWord = r.origWord
                        req.sheet = .dict(d)
                    }
                case .dict(let r):
                    DictionarySheet(req: r) { b, c, v in
                        req.sheet = nil
                        onOpenRef(b, c, v)
                    }
                }
    }
}

/// Кнопки шапки и панели подстрочника — одной высоты: плашка и круг по 40 пт, стекло iOS 26
extension View {
    func chromePill(compact: Bool = false) -> some View {
        self
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 30 : 40)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
    }

    func chromeCircle(_ size: CGFloat = 40) -> some View {
        self
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
    }
}

/// Идёт ли сейчас прокрутка пальцем (без перерисовки при записи)
final class PhaseBox {
    var user = false
}

/// Тонкая полоска вверху панели: сколько прочитано книги
struct ReadProgress: View {
    @ObservedObject var live: LivePlace
    let id: UUID

    var body: some View {
        let v = min(1, max(0, live.progress[id] ?? 0))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.15))
                Rectangle().fill(Color.accentColor).frame(width: g.size.width * v)
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.3), value: v)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        Text("\(name) \(chapter):\(live.verse[id] ?? fallback)").font(.headline).fixedSize()
    }
}

struct ChapterCache {
    let key: String
    let verses: [Verse]
    let heads: [Int: String]
    let xcounts: [Int: Int]
    let icounts: [Int: Int]
    let attr: [Int: NSAttributedString]
}

/// Ссылочный ящик: запись в него при построении экрана не вызывает перерисовку
final class CacheBox {
    var value: ChapterCache?
}

/// Следующая глава под текущей (лента книги): готовый текст и откуда он
struct RibbonSide {
    let ref: (book: String, chapter: Int)
    let data: ChapterCache
}

final class PreviewBox {
    var key = ""
    var prev: RibbonSide?
    var next: RibbonSide?
}

/// Какие строки сейчас на экране (по ним лента решает, что текущая глава сменилась) — без перерисовки при записи
final class IdsBox {
    var ids: [Int] = []
}

/// Комментарии главы по стихам (для текста под стихом): собираются один раз на главу
final class CommBox {
    var key = ""
    var map: [Int: [CommentaryItem]] = [:]
}

struct StrongRequest: Identifiable {
    let id = UUID()
    let key: String
}

enum StudyPanel: Identifiable {
    case commentary(Int)
    case commentaryOf(Int, String)
    case xrefs(Int)
    case compare(Int)
    case interlinear(Int)
    case illustrations(Int)
    case collect(Int)
    case guide(Int)

    var id: String {
        switch self {
        case .commentary(let v): return "c\(v)"
        case .commentaryOf(let v, let m): return "co\(v)-\(m)"
        case .xrefs(let v): return "x\(v)"
        case .compare(let v): return "v\(v)"
        case .interlinear(let v): return "i\(v)"
        case .illustrations(let v): return "p\(v)"
        case .collect(let v): return "k\(v)"
        case .guide(let v): return "g\(v)"
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
    /// Комментарии в тексте (как во Flutter): пусто — все установленные, иначе список номеров модулей (JSON)
    @AppStorage("inlineCommentaries") private var inlineRaw = ""
    @AppStorage("commentView") private var commentView = "tag"
    @AppStorage("commentaryFontSize") private var commentaryFontSize = 19.0
    @State private var expandedComm: Set<String> = []
    /// перевод по сети (API.Bible): глава приходит, когда её открывают
    @State private var onlineTick = 0
    @State private var onlineErr: String?
    @State private var commBox = CommBox()
    @State private var previewCommBox = CommBox()
    /// Лента книги: под текущей главой показана следующая (статичный текст). Доскроллили до неё — она становится текущей
    @AppStorage("ribbonBook") private var ribbonBook = true
    @State private var previewBox = PreviewBox()
    @State private var idsBox = IdsBox()
    /// для какой главы лента уже поставила текст на место (до этого прокрутка скрыта, чтобы не мелькало начало предыдущей)
    @State private var positionedKey = ""
    /// человек уже листал пальцем в этой главе (без этого начальная раскладка не считается прокруткой)
    @State private var ribbonArmed = false

    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("fontWeight") private var fontWeight = 400.0
    @AppStorage("verseSpacing") private var verseSpacing = 0.55
    @AppStorage("verseNumPos") private var verseNumPos = "sup"
    @AppStorage("showHeadings") private var showHeadings = true
    @AppStorage("continuousVerses") private var continuous = false
    @AppStorage("textMargin") private var textMargin = 14.0
    @AppStorage("ilGloss") private var ilGloss = true
    @AppStorage("ilOrig") private var ilOrig = true
    @AppStorage("ilStrong") private var ilStrong = true
    @Environment(\.readerPalette) private var pal
    @AppStorage("theme") private var theme = "system"
    @State private var cacheBox = CacheBox()
    @State private var selected: Set<Int> = []
    @AppStorage("hideOnScroll") private var hideOnScroll = true
    @AppStorage("readingStyle") private var readingStyle = "scroll"
    @State private var pull = PullState()
    @State private var touchScroll = PhaseBox()
    @State private var flashVerse = 0
    @State private var chromeLastY: CGFloat = 0
    @State private var chromeAcc: CGFloat = 0
    @State private var collectItems: [MarkItem] = []
    @State private var pulseVerse = 0
    @State private var pulseAmt = 0.0
    @State private var req = StudyRequests()
    @State private var paneWidth: CGFloat = 400
    @State private var partVerse: Int?
    @State private var partFrom: Int?
    @State private var partTo: Int?
    @State private var noteVerse: Int?
    @State private var noteText = ""
    @State private var imageReq: ImageRequest?
    /// «В проповедь»: окно выбора проповеди
    @State private var sermonPick: SermonPick?
    @State private var panel: StudyPanel?
    @State private var readTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var pinchBase: Double?
    @State private var gestures = ReaderGestures()

    private var book: String { pane.book }

    /// Свежие действия для жестов UIKit (вызывается при каждой перестройке экрана)
    private func bindGestures() -> Bool {
        gestures.onSwipe = { dx, dy, x0, width in
            // свайп влево — следующая глава, вправо — предыдущая. Чтобы не срабатывал случайно: только явный
            // горизонтальный жест (не меньше 80 пт и в 2,5 раза больше, чем по вертикали), не от самого края экрана
            // (там системные жесты) и не во время выделения
            guard selected.isEmpty, partVerse == nil,
                  x0 > 24, x0 < width - 24,
                  abs(dx) >= 80, abs(dx) > abs(dy) * 2.5 else { return }
            panes.step(pane.id, dx < 0 ? 1 : -1, module: module)
        }
        gestures.onPinch = { state, scale in
            switch state {
            case .began:
                pinchBase = fontSize
            case .changed:
                fontSize = min(40, max(13, (pinchBase ?? fontSize) * Double(scale)))
            default:
                pinchBase = nil
            }
        }
        return true
    }
    private var chapter: Int { pane.chapter }
    private var focus: Int { pane.verse }

    private var bookName: String {
        module.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
    }

    var body: some View {
        let d = chapterData()
        let verses = d.verses
        let heads = d.heads
        let rib = ribbonOn ? ribbonData(d) : (prev: nil as RibbonSide?, next: nil as RibbonSide?)
        let _ = bindGestures()
        Group {
        if readingStyle == "pages" {
            pagedView(d)
        } else {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if ribbonOn {
                        // лента книги: предыдущая глава сверху, текущая, следующая снизу — одним текстом. Строится сразу
                        // целиком (не лениво): положения точные, и вход в главу ставится ровно на её начало
                        VStack(alignment: .leading, spacing: fontSize * verseSpacing) {
                            ribbonRows(rib.prev, sign: -1)
                            rows(d)
                            ribbonRows(rib.next, sign: 1)
                        }
                        .scrollTargetLayout()
                    } else if panes.panes.count > 1 {
                        // несколько панелей: все стихи главы строятся сразу — их положения точные и не «плывут»
                        // при прокрутке (на этом держится синхронная прокрутка, см. ScrollSync)
                        VStack(alignment: .leading, spacing: fontSize * verseSpacing) { rows(d) }
                            .scrollTargetLayout()
                    } else {
                        LazyVStack(alignment: .leading, spacing: fontSize * verseSpacing) { rows(d) }
                            .scrollTargetLayout()
                    }
                }
                .environment(\.layoutDirection, Bidi.isRTLLang(module.language) ? .rightToLeft : .leftToRight)
                .background(ScrollFinder(sync: panes.scrollSync, paneID: pane.id, gestures: gestures))
                .padding(.horizontal, textMargin)
                .padding(.vertical, 12)
            }
            .contentMargins(.top, headerTop + (module.interlinear ? InterlinearBar.height : 0), for: .scrollContent)
            // пока лента не поставила текст на место — прокрутка невидима (иначе на кадр мелькает начало предыдущей главы)
            .opacity(ribbonOn && rib.prev != nil && positionedKey != "\(module.id)|\(book)|\(chapter)" ? 0 : 1)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { ids in
                // стихи текущей главы — 1…, её заголовок — 0; предыдущая — со знаком минус от 100 000, следующая — от 100 000
                idsBox.ids = ids
                let cur = ids.filter { abs($0) < Self.ribbonBase }
                if let top = cur.filter({ $0 > 0 }).min() {
                    panes.setLive(pane.id, top)
                    updateProgress(top, verses.count)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                trackChrome(y)
            }
            // потянули за конец главы вверх (или за начало вниз) и отпустили — открывается соседняя глава, как в «ТикТоке»
            // насколько потянули за конец главы — по самой прокрутке UIKit (сводка SwiftUI внизу неточно учитывала
            // нижние кнопки и меню, и до порога было не дотянуть)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.containerSize.height - $0.contentSize.height - $0.contentInsets.bottom }) { _, over in
                if !ribbonOn { pull.setBottom(max(0, bottomOver(fallback: over))) }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { -($0.contentOffset.y + $0.contentInsets.top) }) { _, over in
                if !ribbonOn { pull.setTop(max(0, over)) }
            }
            .onScrollPhaseChange { old, new in
                touchScroll.user = (new == .interacting || new == .decelerating)
                if new == .interacting { ribbonArmed = true }
                #if DEBUG
                SyncTrace.write("P,phase,\(old),\(new),bottom=\(pull.bottom),top=\(pull.top)")
                #endif
                // лента: остановились — если текущая глава ушла с экрана, следующая (или предыдущая) становится текущей
                if new == .idle { evaluateRibbon() }
                guard !ribbonOn, old == .interacting, new != .interacting else { return }
                if max(pull.bottom, bottomOver(fallback: 0)) >= PullState.threshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    panes.step(pane.id, 1, module: module)
                } else if pull.top >= PullState.threshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    panes.step(pane.id, -1, module: module, atEnd: true)
                }
            }
            .overlay(alignment: .bottom) { if !ribbonOn { PullHint(state: pull, next: true, label: neighbour(1)).padding(.bottom, 10) } }
            // сверху — под шапкой (и панелью подстрочника), а не за ними
            .overlay(alignment: .top) {
                if !ribbonOn {
                    PullHint(state: pull, next: false, label: neighbour(-1))
                        .padding(.top, headerTop + (module.interlinear ? InterlinearBar.height : 0) + 10)
                }
            }
            .background { ReaderBackdrop(pal: pal) }
            .onAppear {
                scroll(proxy, verses, heads)
                // проверка на симуляторе: -debugWord YES открывает окно слова «Бог»
                if UserDefaults.standard.bool(forKey: "debugWord"), req.sheet == nil {
                    req.sheet = .word(WordRequest(text: "Бог", strongs: ["H430"], morph: [], book: book, chapter: chapter, verse: 1))
                }
                // -debugSelect YES: выделен первый стих (панель действий)
                // -debugPanel guide | interlinear: окно «Всё о стихе» или подстрочник к стиху -debugSelectVerse (для снимков магазина)
                if let p = UserDefaults.standard.string(forKey: "debugPanel"), panel == nil {
                    let v = max(1, UserDefaults.standard.integer(forKey: "debugSelectVerse"))
                    panel = p == "guide" ? .guide(v) : (p == "interlinear" ? .interlinear(v) : nil)
                }
                if UserDefaults.standard.bool(forKey: "debugSelect") {
                    let n = UserDefaults.standard.integer(forKey: "debugSelectVerse")
                    selected = [n > 0 ? n : 1]
                }
            }
            .onChange(of: focus) { _, v in
                scroll(proxy, verses, heads)
                // перешли к стиху (закладка, ссылка, поиск) — он мигает 2,4 секунды
                if v > 0 && v < 9999 {
                    flashVerse = v
                    Task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        if flashVerse == v { flashVerse = 0 }
                    }
                }
            }
            // открыли или закрыли вторую панель — глава построилась иначе: остаёмся на том же стихе
            .onChange(of: panes.panes.count > 1) { _, _ in
                if let v = panes.live.verse[pane.id] {
                    DispatchQueue.main.async { proxy.scrollTo(v, anchor: .top) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
        // свайп глав и щипок размера букв — жесты UIKit на самой прокрутке (ReaderGestures, см. bindGestures)
        .id("\(module.id)|\(book)|\(chapter)")
        }
        }
        // два пальца: размер букв (в режиме «Страницы»; при прокрутке — через ReaderGestures)
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    if pinchBase == nil { pinchBase = fontSize }
                    fontSize = min(40, max(13, (pinchBase ?? fontSize) * g.magnification))
                }
                .onEnded { _ in pinchBase = nil },
            including: readingStyle == "pages" ? .all : .subviews
        )
        .safeAreaInset(edge: .bottom) {
            // сплошной текст: панель внизу; иначе она стоит между стихами, под последним выделенным
            if !selected.isEmpty && (continuous || readingStyle == "pages") {
                selectionBar(verses)
            }
        }
        .sheet(isPresented: Binding(get: { noteVerse != nil }, set: { if !$0 { noteVerse = nil } })) {
            noteEditor
        }
        .onChange(of: chapter) { _, _ in
            selected = []
            ribbonArmed = false
        }
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
        .task(id: "\(module.id)|\(book)|\(chapter)|\(onlineTick)") { await loadOnline() }
        .background(StudySheets(req: req) { b, c, v in
            // место из словаря: из первой панели — во второй, из остальных — в самой панели
            if panes.index(pane.id) == 0 {
                panes.openSecond(from: pane.id, b, c, v)
            } else {
                panes.go(pane.id, b, c, v)
            }
        })
        .sheet(item: $imageReq) { r in
            VerseImageSheet(text: r.text, ref: r.ref)
        }
        .sheet(item: $sermonPick) { p in
            SermonPickerSheet(onPick: p.onPick)
        }
        .sheet(item: $panel) { p in
            switch p {
            case .commentary(let v):
                CommentarySheet(book: book, chapter: chapter, verse: v)
            case .commentaryOf(let v, let m):
                CommentarySheet(book: book, chapter: chapter, verse: v, moduleId: m)
            case .xrefs(let v):
                XrefsSheet(module: module, book: book, chapter: chapter, verse: v) { b, c, vv in
                    panes.openSecond(from: pane.id, b, c, vv)
                }
            case .compare(let v):
                CompareSheet(book: book, chapter: chapter, verses: selected.isEmpty ? [v] : selected.sorted())
            case .interlinear(let v):
                InterlinearSheet(book: book, chapter: chapter, verse: v)
            case .illustrations(let v):
                IllustrationsSheet(book: book, chapter: chapter, verse: v)
            case .collect:
                CollectSheet(items: collectItems) { show("Добавлено в подборку «\($0)»") }
            case .guide(let v):
                VerseGuideSheet(module: module, book: book, chapter: chapter, verse: v) { b, c, vv in
                    panes.openSecond(from: pane.id, b, c, vv)
                }
            }
        }
    }

    /// Режим «Страницы»: глава листается страницами, как в «Книгах»
    private func pagedView(_ d: ChapterCache) -> some View {
        PagedChapter(
            text: pagedNS(d),
            key: "\(module.id)|\(book)|\(chapter)|\(fontSize)|\(lineHeight)|\(fontFamily)|\(fontWeight)|\(showNumbers)|\(showStrongs)|\(verseNumPos)|\(continuous)|\(showHeadings)|\(textMargin)|\(verseSpacing)",
            focus: focus,
            insets: UIEdgeInsets(top: 14 + headerTop + (module.interlinear ? InterlinearBar.height : 0), left: textMargin + 6, bottom: 34, right: textMargin + 6),
            pageColor: UIColor(pal.bg),
            onTap: { url, vn in tapped(url, vn) },
            onDouble: { vn in doubleTapped(d.verses.first { $0.num == vn }) },
            onLong: { vn in longPressed(vn) },
            selecting: !selected.isEmpty || partVerse != nil,
            onPage: { verse, page, total in
                panes.setLive(pane.id, verse)
                panes.live.progress[pane.id] = (Double(chapter - 1) + Double(page - 1) / Double(max(1, total))) / Double(max(1, module.books.first { $0.id == book }?.chapters ?? 1))
            },
            onEdge: { dir in
                DispatchQueue.main.async { panes.step(pane.id, dir, module: module, atEnd: dir < 0) }
            }
        )
        .background { ReaderBackdrop(pal: pal) }
    }

    /// Вся глава одним текстом для разбивки на страницы: заголовки разделов и стихи (отдельными абзацами или сплошным текстом)
    private func pagedNS(_ d: ChapterCache) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base = uiFont(fontSize)
        let ink = UIColor(pal.text)
        func para(_ spacing: CGFloat, before: CGFloat = 0) -> NSParagraphStyle {
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = fontSize * (lineHeight - 1)
            ps.paragraphSpacing = spacing
            ps.paragraphSpacingBefore = before
            return ps
        }
        if let first = d.verses.first {
            if chapter == 1 {
                out.append(NSAttributedString(string: bookName + "\n", attributes: [
                    .font: uiFont(fontSize * 0.9, 600), .foregroundColor: UIColor(pal.muted), .aobVerse: first.num, .paragraphStyle: para(2),
                ]))
            }
            out.append(NSAttributedString(string: chapterTitleText + "\n", attributes: [
                .font: uiFont(fontSize * 2.1, 800), .foregroundColor: ink, .aobVerse: first.num, .paragraphStyle: para(fontSize * 0.5),
            ]))
        }
        for v in d.verses {
            if showHeadings, let h = d.heads[v.num] {
                out.append(NSAttributedString(string: h + "\n", attributes: [
                    .font: uiFont(fontSize * 0.92, max(fontWeight, 600)), .foregroundColor: ink, .aobVerse: v.num,
                    .paragraphStyle: para(6, before: out.length > 0 ? 10 : 0),
                ]))
            }
            let part = NSMutableAttributedString(attributedString: attributedNS(v, xrefs: d.xcounts[v.num] ?? 0, illus: d.icounts[v.num] ?? 0, number: true, numberLink: true))
            let full = NSRange(location: 0, length: part.length)
            if let bgc = continuousBackground(v.num) { part.addAttribute(.backgroundColor, value: UIColor(bgc), range: full) }
            part.addAttribute(.paragraphStyle, value: para(continuous ? 0 : fontSize * verseSpacing), range: full)
            out.append(part)
            out.append(NSAttributedString(string: continuous ? " " : "\n", attributes: [.font: base, .aobVerse: v.num, .paragraphStyle: para(continuous ? 0 : fontSize * verseSpacing)]))
        }
        return out
    }

    /// Строки главы: стихи (или сплошные блоки) и метка конца главы
    /// «Глава N» («Псалом N»); у первой главы над ним — название книги
    private var chapterTitleText: String {
        book == "Ps" ? String(localized: "Псалом \(chapter)") : String(localized: "Глава \(chapter)")
    }

    private var chapterTitle: some View { chapterTitleFor(book, chapter) }

    private func chapterTitleFor(_ b: String, _ c: Int) -> some View {
        let name = module.books.first { $0.id == b }?.name ?? Books.info(b)?.name ?? b
        return VStack(alignment: .leading, spacing: 2) {
            if c == 1 {
                Text(name)
                    .font(ReadingFonts.font(fontFamily, size: fontSize * 0.9, weight: 600))
                    .foregroundStyle(pal.muted)
            }
            Text(b == "Ps" ? String(localized: "Псалом \(c)") : String(localized: "Глава \(c)"))
                .font(ReadingFonts.font(fontFamily, size: fontSize * 2.1, weight: 800))
                .foregroundStyle(pal.text)
        }
        .padding(.horizontal, 6)
        .padding(.top, fontSize * 0.3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func rows(_ d: ChapterCache) -> some View {
        let verses = d.verses
        let heads = d.heads
        let views = panes.scrollSync.views(pane.id)
        if !verses.isEmpty { chapterTitle.padding(.top, ribbonOn && previewBox.prev != nil ? fontSize * 1.2 : 0).id(0) }
        if continuous && !module.interlinear {
            // сплошной текст: стихи идут подряд, разрыв — только у заголовков разделов
            ForEach(blocks(verses, heads)) { blk in
                VStack(alignment: .leading, spacing: 6) {
                    if let h = blk.heading, showHeadings { headingText(h) }
                    VerseTextView(
                        text: continuousNS(blk, d.xcounts, d.icounts),
                        verse: blk.id,
                        onTap: { url, vn in tapped(url, vn) },
                        onDouble: { vn in doubleTapped(verses.first { $0.num == vn }) },
                        onLong: { vn in longPressed(vn) },
                        selecting: !selected.isEmpty || partVerse != nil,
                        views: views
                    )
                    .padding(-VerseTextView.bleed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(blk.id)
            }
        } else {
            ForEach(verses) { v in
                VStack(alignment: .leading, spacing: 6) {
                    if showHeadings, let h = heads[v.num] { headingText(h) }
                    Group {
                        if module.interlinear {
                            // подстрочный перевод: слова столбиками «перевод / оригинал / Стронг»
                            InterlinearVerse(
                                verse: v, fontSize: fontSize, fontFamily: fontFamily, fontWeight: fontWeight, lineHeight: lineHeight,
                                showNumber: showNumbers, numberColor: pal.verseNum, textColor: pal.text, accent: pal.accent,
                                showGloss: ilGloss, showOrig: ilOrig, showStrong: ilStrong,
                                favorite: favNums.contains(v.num),
                                xrefs: d.xcounts[v.num] ?? 0, illus: d.icounts[v.num] ?? 0,
                                mark: { wi in
                                    if let r = partRange(v.num), r.contains(wi) { return pal.accent.opacity(0.24) }
                                    if let r = favPartRange(v.num), r.contains(wi) { return Color(hex: 0xd9475e).opacity(0.2) }
                                    return nil
                                },
                                onTap: { url, vn in tapped(url, vn) },
                                onDouble: { _ in doubleTapped(v) },
                                onLong: { vn in longPressed(vn) },
                                selecting: !selected.isEmpty || partVerse != nil,
                                views: views
                            )
                        } else {
                            VerseTextView(
                                text: d.attr[v.num] ?? NSAttributedString(),
                                verse: v.num,
                                onTap: { url, vn in tapped(url, vn) },
                                onDouble: { _ in doubleTapped(v) },
                                onLong: { vn in longPressed(vn) },
                                selecting: !selected.isEmpty || partVerse != nil,
                                views: views
                            )
                            .padding(-VerseTextView.bleed)
                        }
                    }
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
                        .allowsHitTesting(false)
                    }
                    if partVerse == v.num {
                        partBar(v).frame(maxWidth: .infinity)
                    } else if v.num == selected.max() {
                        selectionBar(verses).frame(maxWidth: .infinity)
                    }
                }
                .id(v.num)
            }
        }
        if verses.isEmpty {
            if module.online {
                if let e = onlineErr {
                    Text(e).foregroundStyle(pal.muted).multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 8) { ProgressView(); Text("Загрузка…").foregroundStyle(pal.muted) }
                }
            } else {
                Text("В этом переводе нет такой главы.")
                    .foregroundStyle(pal.muted)
            }
        } else if module.online {
            let c = store.onlineCopyright(module.id)
            if !c.isEmpty { Text(c).font(.system(size: 11.5)).foregroundStyle(pal.muted).padding(.top, 12) }
        }
        // конец главы на экране и прошло достаточно времени — глава прочитана (записывается в историю
        // и засчитывается в планы). Именно видимость при прокрутке: при нескольких панелях все строки строятся сразу
        Color.clear.frame(height: 1)
            .onScrollVisibilityChange { visible in
                if visible { startReading(count: verses.count) } else { readTask?.cancel() }
            }
    }

    // MARK: - Лента книги

    static let ribbonBase = 100_000

    /// Лента работает при чтении прокруткой в одной панели (не «Страницы», не сплошной текст и не подстрочник)
    private var ribbonOn: Bool {
        ribbonBook && readingStyle != "pages" && panes.panes.count == 1 && !continuous && !module.interlinear && !module.online
    }

    /// Следующая глава (через границу книги — первая глава следующей); nil — дальше некуда
    private func nextRef() -> (book: String, chapter: Int)? {
        guard let bi = module.books.firstIndex(where: { $0.id == book }) else { return nil }
        if chapter < module.books[bi].chapters { return (book, chapter + 1) }
        guard bi < module.books.count - 1 else { return nil }
        return (module.books[bi + 1].id, 1)
    }

    /// Предыдущая глава (через границу книги — последняя глава предыдущей); nil — выше некуда
    private func prevRef() -> (book: String, chapter: Int)? {
        guard let bi = module.books.firstIndex(where: { $0.id == book }) else { return nil }
        if chapter > 1 { return (book, chapter - 1) }
        guard bi > 0 else { return nil }
        return (module.books[bi - 1].id, max(1, module.books[bi - 1].chapters))
    }

    /// Текст соседней главы для ленты: готовый, как у текущей (без выделения и отметок — они появятся, когда она станет текущей)
    private func buildSide(_ r: (book: String, chapter: Int)?) -> RibbonSide? {
        guard let r else { return nil }
        let verses = store.verses(module: module.id, book: r.book, chapter: r.chapter)
        guard !verses.isEmpty else { return nil }
        let heads = store.headings(module: module.id, book: r.book, chapter: r.chapter)
        let xc = showXrefs ? store.xrefCounts(module: module.id, book: r.book, chapter: r.chapter) : [:]
        let ic = showIllus ? store.illustrationCounts(book: r.book, chapter: r.chapter) : [:]
        var attr: [Int: NSAttributedString] = [:]
        for v in verses {
            attr[v.num] = attributedNS(v, xrefs: xc[v.num] ?? 0, illus: ic[v.num] ?? 0, number: true, numberLink: false, preview: r)
        }
        return RibbonSide(ref: r, data: ChapterCache(key: "", verses: verses, heads: heads, xcounts: xc, icounts: ic, attr: attr))
    }

    /// Соседние главы (кеш на время, пока открыта эта глава и не менялось оформление)
    private func ribbonData(_ d: ChapterCache) -> (prev: RibbonSide?, next: RibbonSide?) {
        let key = d.key + "|ribbon"
        if previewBox.key != key {
            previewBox.prev = buildSide(prevRef())
            previewBox.next = buildSide(nextRef())
            previewBox.key = key
        }
        return (previewBox.prev, previewBox.next)
    }

    /// Соседняя глава стала текущей (доскроллили до неё или нажали на неё)
    private func promote(_ r: (book: String, chapter: Int), _ verse: Int) {
        ribbonArmed = false
        panes.go(pane.id, r.book, r.chapter, verse, record: false)
    }

    /// Остановились: если текущая глава целиком ушла с экрана, на экране соседняя — делаем её текущей
    /// (не на ходу: иначе обрывалась бы инерция прокрутки)
    private func evaluateRibbon() {
        guard ribbonOn, ribbonArmed else { return }
        let ids = idsBox.ids
        if ids.contains(where: { abs($0) < Self.ribbonBase }) { return }
        if let nx = previewBox.next, let nv = ids.filter({ $0 >= Self.ribbonBase }).min() {
            promote(nx.ref, nv == Self.ribbonBase ? 0 : nv - Self.ribbonBase)
        } else if let pv = previewBox.prev, let pid = ids.filter({ $0 <= -Self.ribbonBase }).max() {
            // сверху вниз по главе: первый видимый стих — тот, что ближе к началу (наибольший id)
            promote(pv.ref, pid == -Self.ribbonBase ? 0 : -pid - Self.ribbonBase)
        }
    }

    /// Соседняя глава в ленте: заголовок и стихи. sign: −1 — предыдущая (номера строк со знаком минус), 1 — следующая
    @ViewBuilder private func ribbonRows(_ side: RibbonSide?, sign: Int) -> some View {
        if let side {
            chapterTitleFor(side.ref.book, side.ref.chapter)
                .padding(.top, sign > 0 ? fontSize * 1.2 : 0)
                .id(sign * Self.ribbonBase)
            ForEach(side.data.verses) { v in
                VStack(alignment: .leading, spacing: 6) {
                    if showHeadings, let h = side.data.heads[v.num] { headingText(h) }
                    VerseTextView(
                        text: side.data.attr[v.num] ?? NSAttributedString(),
                        verse: v.num,
                        onTap: { _, _ in promote(side.ref, v.num) },
                        onDouble: { _ in promote(side.ref, v.num) },
                        onLong: { _ in promote(side.ref, v.num) },
                        selecting: false,
                        views: nil
                    )
                    .padding(-VerseTextView.bleed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .id(sign * (Self.ribbonBase + v.num))
            }
            if sign < 0 {
                // между предыдущей и текущей главой — просвет, как перед следующей
                Color.clear.frame(height: fontSize * 0.6)
            }
        }
    }

    /// Глава, её заголовки, числа параллельных мест и иллюстраций и готовый текст стихов — собираются один раз и
    /// пересобираются только при смене главы, перевода или оформления (выделение стиха их не трогает)
    private func chapterData() -> ChapterCache {
        let favs = favNums
        let key = "\(favs.sorted())|\(partKey)|\(module.id)|\(book)|\(chapter)|\(fontSize)|\(lineHeight)|\(fontFamily)|\(fontWeight)|\(showNumbers)|\(showStrongs)|\(verseNumPos)|\(showXrefs)|\(showIllus)|\(theme)|\(store.installed.count)|\(inlineRaw)|\(commentView)|\(commentaryFontSize)|\(expandedComm.sorted())|\(onlineTick)"
        if let c = cacheBox.value, c.key == key { return c }
        let verses = store.verses(module: module.id, book: book, chapter: chapter)
        let heads = store.headings(module: module.id, book: book, chapter: chapter)
        let xcounts = showXrefs ? store.xrefCounts(module: module.id, book: book, chapter: chapter) : [:]
        let icounts = showIllus ? store.illustrationCounts(book: book, chapter: chapter) : [:]
        var attr: [Int: NSAttributedString] = [:]
        for v in verses {
            attr[v.num] = attributedNS(v, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true)
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
        case "aobcomm": return s.dropFirst("aobcomm:".count).split(separator: ",").first.flatMap { Int($0) }
        case "aobcommx": return s.dropFirst("aobcommx:".count).split(separator: ",").first.flatMap { Int($0) }
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
        let key = "\(module.id)|\(book)|\(chapter)"
        let hasPrev = ribbonOn && previewBox.prev != nil
        if hasPrev {
            // над текущей главой лежит предыдущая — встаём на нужное место сразу, без «подъезда» и мелькания её начала
            let target = (focus <= 1 || !verses.contains { $0.num == focus }) ? 0 : focus
            if positionedKey != key {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(target, anchor: .top) }
                DispatchQueue.main.async { positionedKey = key }
            } else if focus > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                }
            }
            return
        }
        guard focus > 0 else { return }
        var target = focus == 1 ? 0 : focus
        if continuous, let blk = blocks(verses, heads).first(where: { $0.verses.contains { $0.num == focus } }) {
            target = blk.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        }
    }

    /// На сколько текст вытянут вверх за конец главы (0 — не вытянут): смещение прокрутки сверх наибольшего
    private func bottomOver(fallback: CGFloat) -> CGFloat {
        guard let sv = panes.scrollSync.scrollView(pane.id), sv.window != nil else { return fallback }
        let maxY = max(-sv.adjustedContentInset.top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
        return sv.contentOffset.y - maxY
    }

    /// Сколько прочитано книги: главы до этой плюс доля этой главы
    private func updateProgress(_ verse: Int, _ count: Int) {
        let chapters = Double(max(1, module.books.first { $0.id == book }?.chapters ?? 1))
        let inChapter = Double(max(0, verse - 1)) / Double(max(1, count))
        panes.live.progress[pane.id] = (Double(chapter - 1) + inChapter) / chapters
    }

    /// Соседняя глава (или книга, если эта глава крайняя) — что откроется, если потянуть за край
    private func neighbour(_ delta: Int) -> (kind: String, name: String)? {
        guard let bi = module.books.firstIndex(where: { $0.id == book }) else { return nil }
        let b = module.books[bi]
        let short = b.short.replacingOccurrences(of: ".", with: "")
        if delta > 0 {
            if chapter < b.chapters { return ("Следующая глава", "\(short) \(chapter + 1)") }
            if bi + 1 < module.books.count { return ("Следующая книга", module.books[bi + 1].name) }
        } else {
            if chapter > 1 { return ("Предыдущая глава", "\(short) \(chapter - 1)") }
            if bi > 0 { return ("Предыдущая книга", module.books[bi - 1].name) }
        }
        return nil
    }

    /// Прокрутка вниз прячет шапку, вверх — возвращает; у самого верха и при выделении — на месте
    /// Место под шапкой панели: при нескольких панелях шапка компактная
    private var headerTop: CGFloat {
        panes.panes.count > 1 ? PaneView.compactHeaderHeight : PaneView.headerHeight
    }

    private func trackChrome(_ y: CGFloat) {
        let d = y - chromeLastY
        chromeLastY = y
        // переходы к стиху, возврат на сохранённое место, прокрутка второй панели — не повод прятать шапку
        guard touchScroll.user, !panes.isLowerPane(pane.id) else { return }
        func set(_ h: Bool) {
            if (panes.chrome.hidden[pane.id] ?? false) != h { withAnimation(.easeInOut(duration: 0.2)) { panes.chrome.hidden[pane.id] = h } }
        }
        guard hideOnScroll, selected.isEmpty, partVerse == nil, y > 80 else {
            chromeAcc = 0
            set(false)
            return
        }
        if d == 0 || abs(d) > 1500 { return }
        chromeAcc = (chromeAcc > 0) == (d > 0) ? chromeAcc + d : d
        if chromeAcc > 14 {
            chromeAcc = 0
            set(true)
        } else if chromeAcc < -10 {
            chromeAcc = 0
            set(false)
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
        if n == flashVerse { return pal.hl }
        return Color.clear
    }

    private static let wordRe = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:[-’'][\\p{L}\\p{M}]+)*")

    private var readerFont: Font {
        ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight)
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

    private func uiFont(_ size: CGFloat, _ weight: Double? = nil) -> UIFont {
        ReadingFonts.uiFont(fontFamily, size: size, weight: weight ?? fontWeight)
    }

    private func paragraph() -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = fontSize * (lineHeight - 1)
        // иврит, арабский и др. — справа налево
        if Bidi.isRTLLang(module.language) {
            ps.baseWritingDirection = .rightToLeft
            ps.alignment = .natural
        }
        return ps
    }

    private func continuousNS(_ blk: VerseBlock, _ xcounts: [Int: Int], _ icounts: [Int: Int]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for v in blk.verses {
            let part = NSMutableAttributedString(attributedString: attributedNS(v, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true))
            if let bgc = continuousBackground(v.num) {
                part.addAttribute(.backgroundColor, value: UIColor(bgc), range: NSRange(location: 0, length: part.length))
            }
            out.append(part)
            out.append(NSAttributedString(string: " ", attributes: [.font: uiFont(fontSize), .aobVerse: v.num, .paragraphStyle: paragraph()]))
        }
        return out
    }

    private func continuousBackground(_ n: Int) -> Color? {
        let c = background(n)
        return c == Color.clear ? nil : c
    }

    /// Текст стиха для UIKit: слова, номера Стронга, метки — с ссылками (aobURL) и номером стиха (aobVerse)
    private func attributedNS(_ v: Verse, xrefs: Int, illus: Int, number: Bool, numberLink: Bool, preview: (book: String, chapter: Int)? = nil) -> NSAttributedString {
        typealias K = NSAttributedString.Key
        let out = NSMutableAttributedString()
        let base = uiFont(fontSize)
        let ink = UIColor(pal.text)
        func add(_ s: String, _ attrs: [K: Any] = [:]) {
            var a: [K: Any] = [.font: base, .foregroundColor: ink, .aobVerse: v.num]
            a.merge(attrs) { _, new in new }
            out.append(NSAttributedString(string: s, attributes: a))
        }
        if showNumbers && number {
            var a: [K: Any] = [.font: UIFont.systemFont(ofSize: fontSize * 0.62, weight: .semibold), .foregroundColor: UIColor(pal.verseNum)]
            if verseNumPos == "sup" { a[.baselineOffset] = fontSize * 0.32 }
            if numberLink { a[.aobURL] = URL(string: "aobverse:\(v.num)")! }
            add("\(v.num) ", a)
        }
        if preview == nil && favNums.contains(v.num) {
            add("♥ ", [.font: UIFont.systemFont(ofSize: fontSize * 0.62), .foregroundColor: UIColor(Color(hex: 0xd9475e))])
        }
        var wi = 0
        let sel = preview == nil ? partRange(v.num) : nil
        let fav = preview == nil ? favPartRange(v.num) : nil
        // выделенная часть стиха и любимая часть — не подсветка каждого слова, а одна цельная плашка от начала
        // первого слова до конца последнего (вместе с пробелами), её рисует PlateLayoutManager — как во Flutter
        var selSpan: (Int, Int)?
        var favSpan: (Int, Int)?
        func track(_ i: Int, _ a: Int, _ b: Int) {
            if let r = sel, r.contains(i) { selSpan = (selSpan?.0 ?? a, b) }
            if let r = fav, r.contains(i) { favSpan = (favSpan?.0 ?? a, b) }
        }
        for (ti, t) in Markup.parse(v.text).enumerated() {
            let slant: [K: Any] = t.italic ? [.obliqueness: 0.2] : [:]
            if !t.strongs.isEmpty {
                // слово с номером Стронга — целиком одна ссылка на окно слова
                var a = slant
                a[.aobURL] = URL(string: "aobword:\(v.num),\(ti),-1")!
                let at = out.length
                add(t.text, a)
                track(wi, at, out.length)
                wi += 1
                if showStrongs {
                    // номера Стронга — ссылки: нажатие открывает словарную статью
                    for key in t.strongs {
                        add(" " + key, [.font: UIFont.systemFont(ofSize: fontSize * 0.55), .baselineOffset: fontSize * 0.3, .foregroundColor: UIColor(pal.accent), .aobURL: URL(string: "aobstrong:\(key)@\(v.num)")!])
                    }
                }
            } else {
                // обычный текст: каждое слово — ссылка, знаки между словами — просто текст
                let ns = t.text as NSString
                var pos = 0
                var k = 0
                for m in Self.wordRe.matches(in: t.text, range: NSRange(location: 0, length: ns.length)) {
                    if m.range.location > pos {
                        add(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)), slant)
                    }
                    var a = slant
                    a[.aobURL] = URL(string: "aobword:\(v.num),\(ti),\(k)")!
                    let at = out.length
                    add(ns.substring(with: m.range), a)
                    track(wi, at, out.length)
                    wi += 1
                    k += 1
                    pos = m.range.location + m.range.length
                }
                if pos < ns.length { add(ns.substring(from: pos), slant) }
            }
        }
        if let f = favSpan, f.1 > f.0 {
            out.addAttribute(.aobPlate, value: PlateStyle(UIColor(Color(hex: 0xd9475e).opacity(0.2)), radius: 6, inflate: 2), range: NSRange(location: f.0, length: f.1 - f.0))
        }
        if let f = selSpan, f.1 > f.0 {
            out.addAttribute(.aobPlate, value: PlateStyle(UIColor(pal.accent.opacity(0.24)), radius: 6, inflate: 2), range: NSRange(location: f.0, length: f.1 - f.0))
        }
        if xrefs > 0 {
            // число параллельных мест после стиха: нажатие открывает их список
            add(" ⇅\(xrefs)", [.font: UIFont.systemFont(ofSize: fontSize * 0.62, weight: .medium), .foregroundColor: UIColor(pal.accent), .aobURL: URL(string: "aobxref:\(v.num)")!])
        }
        if illus > 0 {
            // иллюстрации к стиху: нажатие открывает их
            add(" 🖼\(illus)", [.font: UIFont.systemFont(ofSize: fontSize * 0.62, weight: .medium), .aobURL: URL(string: "aobillus:\(v.num)")!])
        }
        let mainLength = out.length
        out.addAttribute(.paragraphStyle, value: paragraph(), range: NSRange(location: 0, length: mainLength))
        if !continuous { appendComments(out, v, preview) }
        return out
    }

    /// Перевод по сети: главы ещё нет — загрузить и показать
    private func loadOnline() async {
        guard module.online, !store.hasChapter(module.id, book, chapter) else { return }
        onlineErr = nil
        do {
            try await store.loadOnlineChapter(module.id, book, chapter)
            onlineTick += 1
        } catch let e as OnlineError {
            onlineErr = e.message
        } catch {
            onlineErr = OnlineError.net.message
        }
    }

    /// Включённые для текста комментарии: не выбрано ничего — все установленные
    private func inlineModules() -> [InstalledModule] {
        let all = store.commentaries
        if inlineRaw.isEmpty { return all }
        let ids = (try? JSONDecoder().decode([String].self, from: Data(inlineRaw.utf8))) ?? []
        return all.filter { ids.contains($0.id) }
    }

    private func inlineComments(_ verse: Int, _ ctx: (book: String, chapter: Int)? = nil) -> [(module: InstalledModule, text: String)] {
        let mods = inlineModules()
        if mods.isEmpty { return [] }
        let b = ctx?.book ?? book
        let c = ctx?.chapter ?? chapter
        // у превью следующей главы свой ящик, чтобы не сбивать комментарии текущей
        let box = ctx == nil ? commBox : previewCommBox
        let key = "\(b)|\(c)|\(mods.map { $0.id })"
        if box.key != key {
            box.map = store.commentaryChapter(book: b, chapter: c, modules: mods)
            box.key = key
        }
        var order: [String] = []
        var by: [String: (InstalledModule, [String])] = [:]
        for it in box.map[verse] ?? [] {
            let t = (it.title.isEmpty ? "" : it.title + ". ") + it.text
            if by[it.module.id] == nil { order.append(it.module.id); by[it.module.id] = (it.module, []) }
            by[it.module.id]?.1.append(t)
        }
        return order.compactMap { id in by[id].map { (module: $0.0, text: $0.1.joined(separator: " ")) } }
    }

    /// Комментарии после стиха: текстом под стихом (свёрнут, нажатие раскрывает) или меткой «💬 Название»
    private func appendComments(_ out: NSMutableAttributedString, _ v: Verse, _ ctx: (book: String, chapter: Int)? = nil) {
        let items = inlineComments(v.num, ctx)
        if items.isEmpty { return }
        let accent = UIColor(pal.accent)
        if commentView == "tag" {
            // метки после стиха: серое название каждого комментария; нажатие открывает всплывающее окно с его текстом
            for it in items {
                out.append(NSAttributedString(string: "  ", attributes: [.font: uiFont(fontSize * 0.7), .aobVerse: v.num]))
                out.append(NSAttributedString(string: it.module.name, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize * 0.7, weight: .semibold),
                    .foregroundColor: UIColor(pal.muted),
                    .aobURL: URL(string: "aobcomm:\(v.num),\(it.module.id)")!, .aobVerse: v.num,
                ]))
            }
            return
        }
        let size = CGFloat(commentaryFontSize) * 0.86
        for it in items {
            let key = "\(v.num),\(it.module.id)"
            let open = expandedComm.contains(key)
            let limit = 170
            let shown = open || it.text.count <= limit ? it.text : String(it.text.prefix(limit)) + "…"
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = size * (lineHeight - 1)
            ps.firstLineHeadIndent = 12
            ps.headIndent = 12
            ps.paragraphSpacingBefore = 3
            if Bidi.isRTLLang(module.language) { ps.baseWritingDirection = .rightToLeft }
            let url = URL(string: "aobcommx:\(key)")!
            let part = NSMutableAttributedString()
            part.append(NSAttributedString(string: "\n" + it.module.name + "  ", attributes: [.font: UIFont.systemFont(ofSize: size * 0.8, weight: .bold), .foregroundColor: accent]))
            part.append(NSAttributedString(string: shown, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor(pal.text).withAlphaComponent(0.78)]))
            part.addAttributes([.aobURL: url, .aobVerse: v.num, .paragraphStyle: ps], range: NSRange(location: 0, length: part.length))
            out.append(part)
        }
    }

    // MARK: - Нажатия на текст

    /// Короткое нажатие: на слове, номере Стронга, метке — их действие; на любом другом месте стиха — выделение (если оно уже идёт)
    private func tapped(_ url: URL?, _ verse: Int) {
        if let url {
            openLink(url)
        } else if case .word? = req.sheet {
            // маленькое окно слова открыто, текст под ним живой: нажатие мимо слова закрывает окно
            req.sheet = nil
        } else if !selected.isEmpty {
            toggle(verse)
        }
    }

    /// Двойное касание — любимый стих (без выделения)
    private func doubleTapped(_ v: Verse?) {
        guard let v, selected.isEmpty else { return }
        if Date().timeIntervalSince(req.openedAt) < 0.5 {
            req.sheet = nil
        }
        let was = marks.isFavorite(MarksStore.key(book, chapter, v.num))
        marks.toggleFavorite(book, chapter, v.num, text: Markup.plain(v.text))
        show(was ? "Убрано из любимых стихов" : "♥ Добавлено в любимые стихи")
        pulseVerse = v.num
        pulseAmt = 0.3
        withAnimation(.easeOut(duration: 0.8)) { pulseAmt = 0 }
    }

    /// Долгое нажатие в любом месте стиха (и на слове) выделяет его
    private func longPressed(_ verse: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        partVerse = nil
        selected.insert(verse)
    }

    private func openLink(_ url: URL) {
        // выбор части стиха: нажатия по словам этого стиха ставят начало и конец
        if let pv = partVerse, url.scheme == "aobword", verseOf(url) == pv {
            if let wi = partWordIndex(url) {
                if partFrom == nil || partTo != nil { partFrom = wi; partTo = nil } else { partTo = wi }
            }
            return
        }
        // идёт выделение стихов: нажатие на слово, номер Стронга и метки только выделяет стих, словарь не открывается
        if !selected.isEmpty, let v = verseOf(url) {
            toggle(v)
            return
        }
        if let k = StrongLinks.key(from: url) {
            req.openedAt = Date()
            // номер Стронга в тексте — сразу статья словаря Стронга на всю высоту
            req.open(.dict(DictRequest(text: k, strongs: [k], morph: [], book: book, chapter: chapter, verse: verseOf(url) ?? focus, autoOpen: true)))
            return
        }
        if url.scheme == "aobxref", let v = Int(url.absoluteString.dropFirst("aobxref:".count)) {
            panel = .xrefs(v)
            return
        }
        if url.scheme == "aobword" {
            openWord(url)
            return
        }
        if url.scheme == "aobillus", let v = Int(url.absoluteString.dropFirst("aobillus:".count)) {
            panel = .illustrations(v)
            return
        }
        if url.scheme == "aobcomm" {
            let p = url.absoluteString.dropFirst("aobcomm:".count).split(separator: ",", maxSplits: 1).map(String.init)
            if let v = p.first.flatMap({ Int($0) }) { panel = p.count > 1 ? .commentaryOf(v, p[1]) : .commentary(v) }
            return
        }
        if url.scheme == "aobcommx" {
            // комментарий под стихом: нажатие раскрывает его целиком и сворачивает обратно
            let k = String(url.absoluteString.dropFirst("aobcommx:".count))
            if expandedComm.contains(k) { expandedComm.remove(k) } else { expandedComm.insert(k) }
            return
        }
        if url.scheme == "aobverse", let v = Int(url.absoluteString.dropFirst("aobverse:".count)) {
            toggle(v)
        }
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
                    barButton("scroll", "В проповедь") {
                        sermonPick = SermonPick { id in partToSermon(id, v.num, text) }
                    }
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
            Image(systemName: icon).font(.body).frame(height: 24)
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 52)
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
        req.openedAt = Date()
        // номер слова в стихе RST+ — по нему в статье видна форма слова оригинала
        let wi = (!t.strongs.isEmpty && module.id == Align.taggedRu(store)?.id) ? partWordIndex(url) : nil
        // подстрочник: слово оригинала известно сразу, его разбор — из греческого (еврейского) текста стиха
        var ow: OrigInfo?
        if module.interlinear, let o = t.orig, let n = t.strongs.first {
            let key = Align.strongNum(n)
            let occ = toks[..<p[1]].filter { $0.strongs.first.map(Align.strongNum) == key }.count
            ow = OrigInfo(orig: o, morph: t.morph.first ?? Align.origMorph(store: store, book: book, chapter: chapter, verse: p[0], num: n, occurrence: occ), num: key)
        }
        req.open(.word(WordRequest(text: text, strongs: t.strongs, morph: t.morph, book: book, chapter: chapter, verse: p[0], wordIndex: wi, origWord: ow)))
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
            barButton("scroll", "В проповедь") {
                sermonPick = SermonPick { id in addToSermon(id, verses) }
            }
            if selected.count == 1 && readingStyle != "pages" {
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
                if selected.count == 1 {
                    Button { panel = .guide(first) } label: { Label("Всё о стихе", systemImage: "list.bullet.rectangle") }
                }
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
            .tint(.primary)
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
    /// выделенные стихи (один или несколько) — сравнивается весь отрывок
    let verses: [Int]

    /// «16–18, 20»
    private var rangeLabel: String {
        var out: [String] = []
        var i = 0
        while i < verses.count {
            var j = i
            while j + 1 < verses.count, verses[j + 1] == verses[j] + 1 { j += 1 }
            out.append(j > i ? "\(verses[i])–\(verses[j])" : "\(verses[i])")
            i = j + 1
        }
        return "\(Books.info(book)?.short ?? book) \(chapter):" + out.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.bibles) { m in
                    let parts = verses.compactMap { v in store.verseText(module: m.id, book: book, chapter: chapter, verse: v).map { (v, $0) } }
                    if !parts.isEmpty {
                        Section {
                            ForEach(parts, id: \.0) { part in
                                Text(verses.count > 1 ? "\(part.0) \(part.1)" : part.1).font(.system(size: 18, design: .serif))
                                    .bidi(part.1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } header: {
                            Text("\(m.name) — \(m.title)")
                        }
                    }
                }
            }
            .navigationTitle("Сравнить переводы")
            .navigationSubtitle(rangeLabel)
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
