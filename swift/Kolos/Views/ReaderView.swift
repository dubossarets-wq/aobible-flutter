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
    /// Панель подстрочника этого окна развёрнута (у каждого окна своя)
    private var ilBar: Bool { panes.ilBar(paneID) }
    private var ilCompact: Bool { panes.panes.count > 1 }
    /// Кнопка «свернуть» панели подстрочника и кнопка фильтра в шапке — одна и та же кнопка, перетекает при скрытии
    @AppStorage("panesStacked") private var stacked = true
    let paneID: UUID
    /// Состояние шапок читают только ChromeWatch-обёртки: смена его не перестраивает текст окна
    let chrome: ChromeState
    @State private var showGoto = UserDefaults.standard.bool(forKey: "debugGoto")
    @State private var showModules = false
    /// Перевод, выбранный в окне: применяется, когда окно закрылось
    @State private var pendingModule: String?

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
                        ChromeWatch(chrome: chrome, id: paneID) { hiddenNow, shift in
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
                        .offset(y: hiddenNow && !panes.isLowerPane(paneID) ? shift : 0)
                        .animation(.easeInOut(duration: 0.2), value: hiddenNow)
                        }
                        }
                    }
            }
            .sheet(item: Binding(get: { planDay }, set: { planDay = $0 })) { r in
                PlanDayView(uid: r.uid, day: r.day)
            }
            .sheet(isPresented: $showGoto) {
                GotoSheet(module: m, recents: panes.recentBooks(), current: p.book) { b, c, v in
                    panes.go(paneID, b, c, v)
                }
            }
            .sheet(isPresented: $showModules, onDismiss: {
                // окно уже закрыто — только теперь перестраиваем панель, окно не «висит» на время перерисовки текста
                if let id = pendingModule {
                    pendingModule = nil
                    if id != p.moduleId { panes.setModule(paneID, id, store) }
                }
            }) {
                NavigationStack {
                    TranslationPicker(current: p.moduleId, active: Set(panes.panes.map(\.moduleId))) { id in
                        pendingModule = id
                        showModules = false
                    }
                    .navigationTitle("Перевод")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showModules = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    private func chromeOverlay(_ p: PaneState, _ m: InstalledModule) -> some View {
        ChromeWatch(chrome: chrome, id: paneID) { hiddenNow, _ in chromeBody(p, m, hiddenNow) }
    }

    @ViewBuilder private func chromeBody(_ p: PaneState, _ m: InstalledModule, _ hiddenNow: Bool) -> some View {
        // нижняя панель при параллельном чтении: шапка на месте (не прячется), без отступа под строку состояния
        let lower = panes.isLowerPane(paneID)
        // несколько окон: шапки всех окон стоят на месте, при прокрутке уходит только нижнее меню
        let hidden = hiddenNow && !lower && panes.panes.count == 1
        // полоса прочтения лежит под шапкой; когда шапка ушла — поднимается к самому верху экрана.
        // От полосы до верхнего края всегда размытый фон
        let barShown = m.interlinear && ilBar
        // высота фона шапки меняется вместе с панелью подстрочника (плавно, SlidingChrome её анимирует)
        let barH = InterlinearBar.height(ilCompact)
        SlidingChrome(p: hidden ? 1 : 0, headerH: headerH + (barShown ? barH : 0), safeTop: lower ? 0 : Self.safeTop) {
            ZStack(alignment: .topLeading) {
                // панель подстрочника лежит ПОД строкой шапки: при скрытии уезжает вверх за кнопки перевода и книги
                // и растворяется под ними
                if m.interlinear {
                    InterlinearBar(compact: ilCompact)
                        .padding(.top, barShown ? headerH : max(0, headerH - barH))
                        .opacity(barShown ? 1 : 0)
                        .allowsHitTesting(barShown)
                }
                VStack(spacing: 0) {
                    header(p, m)
                    planPill(p)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerH = $0 }
            }
            .frame(height: headerH + (barShown ? barH : 0), alignment: .top)
            // одна кнопка на оба положения: в панели — «свернуть», в шапке — «фильтр»; иконка превращается
            // место считается явно (а не matchedGeometryEffect: тот при запуске не успевал пересчитаться, и кнопка
            // вставала поверх кнопки «две панели»). В шапке — сразу слева от неё, в панели — у правого края
            .overlay(alignment: .topLeading) {
                if m.interlinear {
                    GeometryReader { g in
                        let barTop = barShown ? headerH : max(0, headerH - barH)
                        let compact = ilCompact
                        ilToggle.position(ilBar
                            ? (compact ? CGPoint(x: g.size.width - 27, y: barTop + 15) : CGPoint(x: g.size.width - 40, y: barTop + 20))
                            : (compact ? CGPoint(x: g.size.width - 63, y: 19) : CGPoint(x: g.size.width - 88, y: 26)))
                    }
                }
            }
            .animation(InterlinearBar.motion, value: ilBar)
            .allowsHitTesting(!hidden)
        } line: {
            // несколько окон: полоска прочтения только у верхнего окна — у остальных место под текст
            if panes.panes.first?.id == paneID {
                ReadProgress(live: panes.live, id: paneID)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hidden)
    }

    /// Кнопка панели подстрочника: стоит на месте ilSlot (в панели или в шапке), при переключении переезжает,
    /// а иконка векторно превращается: стрелка «свернуть» ⇄ «фильтр»
    private var ilToggle: some View {
        Button { withAnimation(InterlinearBar.motion) { panes.setIlBar(paneID, !ilBar) } } label: {
            Image(systemName: ilBar ? "chevron.up" : "slider.horizontal.3")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .chromeCircle(ilCompact ? 30 : 40)
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

    /// Несколько панелей: одна тонкая строка — перевод, место и все кнопки окна значками (без меню «⋯»).
    /// Не помещается (узкие окна столбцами) — строка листается вбок, кнопки не прячутся
    private func compactHeader(_ p: PaneState, _ m: InstalledModule) -> some View {
        ViewThatFits(in: .horizontal) {
            compactRow(p, m)
            ScrollView(.horizontal, showsIndicators: false) { compactRow(p, m) }
        }
        .padding(.vertical, 4)
    }

    private func compactRow(_ p: PaneState, _ m: InstalledModule) -> some View {
        HStack(spacing: 6) {
            placePill(p, m, compact: true)
            Spacer(minLength: 2)
            if panes.canBack(paneID) {
                Button { panes.back(paneID) } label: { Image(systemName: "arrow.uturn.backward").chromeCircle(30) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")
            }
            if panes.canForward(paneID) {
                Button { panes.forward(paneID) } label: { Image(systemName: "arrow.uturn.forward").chromeCircle(30) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Вперёд")
            }
            Button {
                Task { await audio.listen(store: store, moduleId: p.moduleId, from: Place(book: p.book, chapter: p.chapter, verse: max(1, p.verse))) }
            } label: { Image(systemName: "headphones").chromeCircle(30) }
                .buttonStyle(.plain)
                .accessibilityLabel("Слушать")
            if panes.panes.count < maxPanes {
                Button { panes.addPane(after: paneID, moduleId: p.moduleId) } label: { Image(systemName: "rectangle.split.2x1").chromeCircle(30) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить панель")
            }
            if m.interlinear && !ilBar {
                // место кнопки фильтра подстрочника (она в ilToggle) — сразу перед «Закрыть»
                Color.clear.frame(width: 30, height: 30)
            }
            Button { panes.closePane(paneID) } label: { Image(systemName: "xmark").chromeCircle(30) }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть панель")
        }
        .padding(.horizontal, 12)
    }

    /// Перевод и место — одна плашка из двух половин с тонкой чертой между ними: нажатие на перевод открывает
    /// переводы, на место — книги и главы
    private func placePill(_ p: PaneState, _ m: InstalledModule, compact: Bool) -> some View {
        let pad: CGFloat = compact ? 12 : 16
        return HStack(spacing: 0) {
            Button { showModules = true } label: {
                Text(m.shortName)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .fixedSize()
                    .padding(.leading, pad)
                    .padding(.trailing, pad - 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Перевод: \(m.shortName)")
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 1, height: compact ? 14 : 18)
                .allowsHitTesting(false)
            Button { showGoto = true } label: {
                HStack(spacing: compact ? 4 : 5) {
                    LiveTitle(live: panes.live, id: paneID, name: bookName(p, m), chapter: p.chapter, fallback: max(p.verse, 1))
                    Image(systemName: "chevron.down").font((compact ? Font.caption2 : Font.caption).weight(.bold))
                }
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .padding(.leading, pad - 4)
                .padding(.trailing, pad)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
        .frame(height: compact ? 30 : 40)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func fullHeader(_ p: PaneState, _ m: InstalledModule) -> some View {
        HStack(spacing: 8) {
            placePill(p, m, compact: false)
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

    // значение меняется на каждом кадре прокрутки: подсказку оповещаем, только когда оно правда изменилось
    // (иначе при нескольких панелях каждая из них перерисовывалась на каждом кадре)
    func setBottom(_ v: CGFloat) {
        guard v != bottom else { return }
        bottom = v
        bottomShown = v
        crossed(v, &bottomReady)
        #if DEBUG
        if v > 5 { SyncTrace.write("P,bottom,\(v)") }
        #endif
    }

    func setTop(_ v: CGFloat) {
        guard v != top else { return }
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

/// Следит за тем, спрятаны ли шапка и нижнее меню, и перерисовывает только своё содержимое (шапку, кнопку «Слушать»),
/// а не всё окно с текстом
struct ChromeWatch<Content: View>: View {
    @ObservedObject var chrome: ChromeState
    let id: UUID
    @ViewBuilder let content: (Bool, CGFloat) -> Content

    var body: some View {
        content(chrome.hidden[id] == true, chrome.bottomShift)
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
            // сплошной цвет на 5% серее фона страницы (в тёмной теме — на 5% светлее), без размытия
            ZStack {
                Rectangle().fill(pal.bg)
                Rectangle().fill(pal.text.opacity(0.05))
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
        Text("\(name) \(live.chapter[id] ?? chapter):\(live.verse[id] ?? fallback)").font(.headline).fixedSize()
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

/// Ссылочный ящик: запись в него при построении экрана не вызывает перерисовку. Готовый текст по главам
/// (в сплошном тексте книги на экране бывает несколько глав; держим немного последних)
final class CacheBox {
    var chapters: [Int: ChapterCache] = [:]
}

/// Строка сплошного текста книги: заголовок главы, стих (или блок сплошного текста) и просвет после главы
struct BookRow: Identifiable {
    enum Kind { case title, verse, end }
    let id: Int
    let chapter: Int
    let verse: Int
    let kind: Kind
}

/// Раскладка книги: номера строк всех глав (сами главы строятся, когда до них доходит прокрутка)
final class BookBox {
    var key = ""
    var chapters: [Int] = []
    var counts: [Int: Int] = [:]
    var rows: [BookRow] = []
}

/// Что было нажато в главе, которая ещё не текущая: сначала она становится текущей, потом выполняется нажатие
enum PendingTap {
    case tap(URL?, Int)
    case double(Int)
    case long(Int)
}

/// Служебное состояние прокрутки — без перерисовки при записи
final class NavBox {
    /// Глава сменилась от прокрутки (а не переходом): к стиху прокручивать не нужно
    var silent = false
    var pending: PendingTap?
    /// Шапка: где была прокрутка в прошлый раз и сколько набралось в одну сторону
    var chromeLastY: CGFloat = 0
    var chromeAcc: CGFloat = 0
    /// Для какой главы идёт отсчёт «глава прочитана»
    var readingChapter = 0
}

/// Какие строки сейчас на экране — без перерисовки при записи
final class IdsBox {
    var ids: [Int] = []
}

/// Комментарии по стихам (для текста под стихом): собираются один раз на главу
final class CommBox {
    var maps: [String: [Int: [CommentaryItem]]] = [:]
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
    /// Сплошной текст книги: все главы книги одной лентой, глава за главой без переключения
    @State private var bookBox = BookBox()
    @State private var idsBox = IdsBox()
    @State private var nav = NavBox()
    /// текст уже поставлен на нужное место (до этого прокрутка скрыта, чтобы не мелькало начало книги)
    @State private var positioned = false

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
    /// Панель подстрочника (фильтр строк) развёрнута под шапкой. Свёрнута — места под неё в тексте нет: иначе при
    /// синхронной прокрутке стихи подстрочника вставали ниже, чем в остальных окнах
    private var ilBar: Bool { panes.ilBar(pane.id) }
    private var ilInset: CGFloat { module.interlinear && ilBar ? InterlinearBar.height(panes.panes.count > 1) : 0 }
    @Environment(\.readerPalette) private var pal
    @AppStorage("theme") private var theme = "system"
    @State private var cacheBox = CacheBox()
    @State private var selected: Set<Int> = []
    @AppStorage("hideOnScroll") private var hideOnScroll = true
    @AppStorage("readingStyle") private var readingStyle = "scroll"
    @State private var pull = PullState()
    @State private var touchScroll = PhaseBox()
    @State private var flashVerse = 0
    /// Переход из поиска: в подсвеченном стихе ещё и найденные слова
    @State private var flashWords = ""
    @State private var flashWhole = false
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
            // в сплошном тексте книги глав «по страницам» нет — свайп ничего не листает
            guard !bookOn, selected.isEmpty, partVerse == nil,
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
        let _ = bindGestures()
        let book1 = bookOn
        Group {
        if readingStyle == "pages" {
            pagedView(d)
        } else {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if book1 {
                        // сплошной текст книги: все главы подряд, глава за главой, без переключения. Строки строятся
                        // по мере прокрутки; вверху и внизу книги — переход к соседней книге
                        LazyVStack(alignment: .leading, spacing: fontSize * verseSpacing) {
                            bookEdge(-1).id(-1)
                            ForEach(bookRows()) { r in bookRow(r) }
                            bookEdge(1).id(-2)
                        }
                        .scrollTargetLayout()
                    } else {
                        // несколько панелей: все стихи главы строятся сразу — их положения точные и не «плывут»
                        // при прокрутке (на этом держится синхронная прокрутка, см. ScrollSync)
                        VStack(alignment: .leading, spacing: fontSize * verseSpacing) { rows(d) }
                            .scrollTargetLayout()
                    }
                }
                .environment(\.layoutDirection, Bidi.isRTLLang(module.language) ? .rightToLeft : .leftToRight)
                .background(ScrollFinder(sync: panes.scrollSync, paneID: pane.id, gestures: gestures))
                .padding(.horizontal, textMargin)
                .padding(.vertical, 12)
            }
            .contentMargins(.top, headerTop + ilInset, for: .scrollContent)
            // пока текст не поставлен на нужное место — прокрутка невидима (иначе на кадр мелькает начало книги)
            .opacity(book1 && !positioned ? 0 : 1)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { ids in
                idsBox.ids = ids
                if book1 {
                    // строки книги: глава × 1000 + стих; 0 — заголовок главы, 999 — просвет после главы
                    if let top = ids.filter({ $0 > 0 && $0 % 1000 != 0 && $0 % 1000 != 999 }).min() {
                        let c = top / 1000
                        panes.setLive(pane.id, top % 1000, chapter: c)
                        updateProgress(c, top % 1000, bookBox.counts[c] ?? 1)
                    }
                } else if let top = ids.filter({ $0 > 0 }).min() {
                    panes.setLive(pane.id, top)
                    updateProgress(chapter, top, verses.count)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                trackChrome(y)
            }
            // несколько панелей (там глава по-прежнему одна): потянули за конец главы вверх (или за начало вниз)
            // и отпустили — открывается соседняя глава
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.containerSize.height - $0.contentSize.height - $0.contentInsets.bottom }) { _, over in
                if !book1 { pull.setBottom(max(0, bottomOver(fallback: over))) }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { -($0.contentOffset.y + $0.contentInsets.top) }) { _, over in
                if !book1 { pull.setTop(max(0, over)) }
            }
            .onScrollPhaseChange { old, new in
                touchScroll.user = (new == .interacting || new == .decelerating)
                // книга: остановились — глава верхнего стиха становится текущей (заголовок, закладки, выделение)
                if book1 && new == .idle { settleChapter() }
                guard !book1, old == .interacting, new != .interacting else { return }
                if max(pull.bottom, bottomOver(fallback: 0)) >= PullState.threshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    panes.step(pane.id, 1, module: module)
                } else if pull.top >= PullState.threshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    panes.step(pane.id, -1, module: module, atEnd: true)
                }
            }
            .overlay(alignment: .bottom) { if !book1 { PullHint(state: pull, next: true, label: neighbour(1)).padding(.bottom, 10) } }
            // сверху — под шапкой (и панелью подстрочника), а не за ними
            .overlay(alignment: .top) {
                if !book1 {
                    PullHint(state: pull, next: false, label: neighbour(-1))
                        .padding(.top, headerTop + ilInset + 10)
                }
            }
            .background { ReaderBackdrop(pal: pal) }
            .onAppear {
                scroll(proxy, initial: true)
                // открыли книгу переходом (закладка, поиск, ссылка) — стих подсвечивается
                if let j = panes.lastJump, j.id == pane.id, Date().timeIntervalSince(j.at) < 3 { flash() }
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
            .onChange(of: "\(chapter)|\(focus)") { old, _ in
                // глава сменилась от прокрутки книги — текст уже там, где надо
                if nav.silent {
                    nav.silent = false
                    return
                }
                let sameChapter = old.split(separator: "|").first.flatMap { Int($0) } == chapter
                scroll(proxy, initial: false, animated: sameChapter || !book1)
                // перешли к стиху (закладка, ссылка, поиск) — он подсвечивается на пару секунд
                flash()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
        // книга — один экран на всю книгу (смена главы его не пересоздаёт); при нескольких панелях — экран на главу
        .id(book1 ? "\(module.id)|\(book)" : "\(module.id)|\(book)|\(chapter)")
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
            endPart()
            // нажали в главе, которая ещё не была текущей, — теперь она текущая, выполняем само нажатие
            if let p = nav.pending {
                nav.pending = nil
                run(p)
            }
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
            insets: UIEdgeInsets(top: 14 + headerTop + ilInset, left: textMargin + 6, bottom: 34, right: textMargin + 6),
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
            let part = NSMutableAttributedString(attributedString: attributedNS(v, chapter, xrefs: d.xcounts[v.num] ?? 0, illus: d.icounts[v.num] ?? 0, number: true, numberLink: true))
            let full = NSRange(location: 0, length: part.length)
            if let bgc = continuousBackground(chapter, v.num) { part.addAttribute(.backgroundColor, value: UIColor(bgc), range: full) }
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

    /// Номер строки: в книге — глава × 1000 + стих (0 — заголовок главы), в одной главе — номер стиха
    private func rowID(_ c: Int, _ n: Int) -> Int { bookOn ? c * 1000 + n : n }

    /// Одна глава (несколько панелей, перевод по сети): заголовок, стихи, конец главы
    @ViewBuilder private func rows(_ d: ChapterCache) -> some View {
        let verses = d.verses
        let views = panes.scrollSync.views(pane.id)
        if !verses.isEmpty { chapterTitle.id(0) }
        if continuous && !module.interlinear {
            // сплошной текст: стихи идут подряд, разрыв — только у заголовков разделов
            ForEach(blocks(verses, d.heads)) { blk in blockRow(chapter, blk, d, views: views) }
        } else {
            ForEach(verses) { v in verseRow(chapter, v, d, views: views) }
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
                if visible { startReading(chapter, count: verses.count) } else { readTask?.cancel() }
            }
    }

    /// Блок сплошного текста главы c
    private func blockRow(_ c: Int, _ blk: VerseBlock, _ d: ChapterCache, views: VerseViews?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let h = blk.heading, showHeadings { headingText(h) }
            VerseTextView(
                text: continuousNS(c, blk, d.xcounts, d.icounts),
                verse: blk.id,
                onTap: { url, vn in act(c, .tap(url, vn)) },
                onDouble: { vn in act(c, .double(vn)) },
                onLong: { vn in act(c, .long(vn)) },
                selecting: c == chapter && (!selected.isEmpty || partVerse != nil),
                views: views
            )
            .padding(-VerseTextView.bleed)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(rowID(c, blk.id))
    }

    /// Стих главы c. Выделение, часть стиха и панель действий — только у текущей главы; подсветка, любимые,
    /// закладки — у всех глав книги
    private func verseRow(_ c: Int, _ v: Verse, _ d: ChapterCache, views: VerseViews?) -> some View {
        let cur = c == chapter
        let selecting = cur && (!selected.isEmpty || partVerse != nil)
        return VStack(alignment: .leading, spacing: 6) {
            if showHeadings, let h = d.heads[v.num] { headingText(h) }
            Group {
                if module.interlinear {
                    // подстрочный перевод: слова столбиками «перевод / оригинал / Стронг»
                    InterlinearVerse(
                        verse: v, fontSize: fontSize, fontFamily: fontFamily, fontWeight: fontWeight, lineHeight: lineHeight,
                        showNumber: showNumbers, numberColor: pal.verseNum, textColor: pal.text, accent: pal.accent,
                        showGloss: ilGloss, showOrig: ilOrig, showStrong: ilStrong,
                        favorite: favNums(c).contains(v.num),
                        xrefs: d.xcounts[v.num] ?? 0, illus: d.icounts[v.num] ?? 0,
                        mark: { wi in
                            if cur, let r = partRange(v.num), r.contains(wi) { return pal.accent.opacity(0.24) }
                            if let r = favPartRange(c, v.num), r.contains(wi) { return Color(hex: 0xd9475e).opacity(0.2) }
                            return nil
                        },
                        onTap: { url, vn in act(c, .tap(url, vn)) },
                        onDouble: { _ in act(c, .double(v.num)) },
                        onLong: { vn in act(c, .long(vn)) },
                        selecting: selecting,
                        views: views
                    )
                } else {
                    VerseTextView(
                        text: d.attr[v.num] ?? NSAttributedString(),
                        verse: v.num,
                        onTap: { url, vn in act(c, .tap(url, vn)) },
                        onDouble: { _ in act(c, .double(v.num)) },
                        onLong: { vn in act(c, .long(vn)) },
                        selecting: selecting,
                        views: views
                    )
                    .padding(-VerseTextView.bleed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background(c, v.num), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeInOut(duration: 0.45), value: cur && flashVerse == v.num)
            .background(Color(hex: 0xd9475e).opacity(cur && pulseVerse == v.num ? pulseAmt : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if marks.isBookmarked(book, c, v.num) {
                    Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.orange)
                        .allowsHitTesting(false)
                }
            }
            if cur && partVerse == v.num {
                partBar(v).frame(maxWidth: .infinity)
            } else if cur && v.num == selected.max() {
                selectionBar(d.verses).frame(maxWidth: .infinity)
            }
        }
        .id(rowID(c, v.num))
    }

    // MARK: - Сплошной текст книги

    /// Вся книга одной лентой: при чтении прокруткой в одной панели (перевод по сети приходит по главам — у него глава)
    private var bookOn: Bool {
        readingStyle != "pages" && panes.panes.count == 1 && !module.online
    }

    /// Строки всей книги (номера стихов — одним запросом; текст глав строится, когда до них доходит прокрутка)
    private func bookRows() -> [BookRow] {
        let blocksMode = continuous && !module.interlinear
        let key = "\(module.id)|\(book)|\(blocksMode)|\(store.installed.count)"
        if bookBox.key == key { return bookBox.rows }
        let lay = store.bookLayout(module: module.id, book: book)
        var rows: [BookRow] = []
        let chs = lay.verses.keys.sorted()
        var counts: [Int: Int] = [:]
        for c in chs {
            let vs = (lay.verses[c] ?? []).filter { $0 >= 1 && $0 < 999 }
            guard !vs.isEmpty else { continue }
            counts[c] = vs.count
            rows.append(BookRow(id: c * 1000, chapter: c, verse: 0, kind: .title))
            if blocksMode {
                // блоки сплошного текста: новый блок — с заголовка раздела (как blocks())
                let hd = lay.headed[c] ?? []
                for (i, n) in vs.enumerated() where i == 0 || hd.contains(n) {
                    rows.append(BookRow(id: c * 1000 + n, chapter: c, verse: n, kind: .verse))
                }
            } else {
                for n in vs { rows.append(BookRow(id: c * 1000 + n, chapter: c, verse: n, kind: .verse)) }
            }
            rows.append(BookRow(id: c * 1000 + 999, chapter: c, verse: 999, kind: .end))
        }
        bookBox.key = key
        bookBox.rows = rows
        bookBox.chapters = counts.keys.sorted()
        bookBox.counts = counts
        return rows
    }

    @ViewBuilder private func bookRow(_ r: BookRow) -> some View {
        switch r.kind {
        case .title:
            chapterTitleFor(book, r.chapter)
                .padding(.top, r.chapter == bookBox.chapters.first ? 0 : fontSize * 0.6)
                .id(r.id)
        case .end:
            // конец главы на экране и прошло достаточно времени — глава прочитана (история, планы)
            Color.clear.frame(height: max(1, fontSize * 0.4))
                .onScrollVisibilityChange { visible in
                    if visible {
                        startReading(r.chapter, count: bookBox.counts[r.chapter] ?? 0)
                    } else if nav.readingChapter == r.chapter {
                        readTask?.cancel()
                    }
                }
                .id(r.id)
        case .verse:
            let d = chapterCache(r.chapter)
            if continuous && !module.interlinear {
                if let blk = blocks(d.verses, d.heads).first(where: { $0.id == r.verse }) {
                    blockRow(r.chapter, blk, d, views: nil)
                } else {
                    Color.clear.frame(height: 1).id(r.id)
                }
            } else if let v = d.verses.first(where: { $0.num == r.verse }) {
                verseRow(r.chapter, v, d, views: nil)
            } else {
                Color.clear.frame(height: 1).id(r.id)
            }
        }
    }

    /// Вверху книги — переход к предыдущей книге, внизу — к следующей
    @ViewBuilder private func bookEdge(_ dir: Int) -> some View {
        if let bi = module.books.firstIndex(where: { $0.id == book }), bi + dir >= 0, bi + dir < module.books.count {
            let b = module.books[bi + dir]
            Button {
                panes.go(pane.id, b.id, 1, 0)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: dir < 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pal.accent)
                        .frame(width: 34, height: 34)
                        .background(pal.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dir < 0 ? "Предыдущая книга" : "Следующая книга")
                            .font(.footnote)
                            .foregroundStyle(pal.muted)
                        Text(b.name)
                            .font(.headline)
                            .foregroundStyle(pal.text)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, dir > 0 ? fontSize : 0)
            .padding(.bottom, dir < 0 ? fontSize * 0.6 : 24)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// Текущая глава панели прямо сейчас (замыкания строк могут быть собраны до того, как она сменилась)
    private var paneChapter: Int {
        panes.panes.first { $0.id == pane.id }?.chapter ?? chapter
    }

    /// Остановились: глава верхнего стиха на экране становится текущей — без прокрутки (текст уже на месте)
    private func settleChapter() {
        guard selected.isEmpty, partVerse == nil else { return }
        guard let top = idsBox.ids.filter({ $0 > 0 && $0 % 1000 != 0 && $0 % 1000 != 999 }).min() else { return }
        let c = top / 1000
        guard c != paneChapter else { return }
        makeCurrent(c, top % 1000)
    }

    private func makeCurrent(_ c: Int, _ v: Int) {
        nav.silent = true
        panes.go(pane.id, book, c, v, record: false)
    }

    /// Нажатие в главе c: в текущей — сразу; в другой — она становится текущей, и нажатие выполняется уже в ней
    private func act(_ c: Int, _ p: PendingTap) {
        if c == paneChapter {
            run(p)
            return
        }
        nav.pending = p
        switch p {
        case .tap(_, let n), .double(let n), .long(let n): makeCurrent(c, n)
        }
    }

    private func run(_ p: PendingTap) {
        switch p {
        case .tap(let url, let v): tapped(url, v)
        case .double(let v): doubleTapped(chapterData().verses.first { $0.num == v })
        case .long(let v): longPressed(v)
        }
    }

    /// Глава, её заголовки, числа параллельных мест и иллюстраций и готовый текст стихов — собираются один раз и
    /// пересобираются только при смене перевода, оформления или отметок этой главы (выделение стиха их не трогает)
    private func chapterCache(_ c: Int) -> ChapterCache {
        let favs = favNums(c)
        let comm = expandedComm.filter { $0.hasPrefix("\(c)|") }.sorted()
        let key = "\(favs.sorted())|\(partKey(c))|\(module.id)|\(book)|\(c)|\(fontSize)|\(lineHeight)|\(fontFamily)|\(fontWeight)|\(showNumbers)|\(showStrongs)|\(verseNumPos)|\(showXrefs)|\(showIllus)|\(theme)|\(store.installed.count)|\(inlineRaw)|\(commentView)|\(commentaryFontSize)|\(comm)|\(onlineTick)|\(continuous)|\(c == chapter && !flashWords.isEmpty ? "\(flashVerse):\(flashWords):\(flashWhole)" : "")"
        if let x = cacheBox.chapters[c], x.key == key { return x }
        let verses = store.verses(module: module.id, book: book, chapter: c)
        let heads = store.headings(module: module.id, book: book, chapter: c)
        let xcounts = showXrefs ? store.xrefCounts(module: module.id, book: book, chapter: c) : [:]
        let icounts = showIllus ? store.illustrationCounts(book: book, chapter: c) : [:]
        var attr: [Int: NSAttributedString] = [:]
        for v in verses {
            attr[v.num] = attributedNS(v, c, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true)
        }
        let x = ChapterCache(key: key, verses: verses, heads: heads, xcounts: xcounts, icounts: icounts, attr: attr)
        // держим главы рядом с этой (на экране — одна-две), далёкие отпускаем
        if cacheBox.chapters.count > 10 {
            cacheBox.chapters = cacheBox.chapters.filter { abs($0.key - c) <= 3 || $0.key == chapter }
        }
        cacheBox.chapters[c] = x
        return x
    }

    /// Текущая глава
    private func chapterData() -> ChapterCache { chapterCache(chapter) }

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

    private func startReading(_ c: Int, count: Int) {
        readTask?.cancel()
        guard count > 0 else { return }
        let b = book
        nav.readingChapter = c
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

    /// Подсветить стих, к которому перешли (и найденные слова, если пришли из поиска), на две секунды
    private func flash() {
        let v = focus
        guard v > 0 && v < 9999 else { return }
        var words = ""
        var whole = false
        if let j = panes.lastJump, j.id == pane.id, Date().timeIntervalSince(j.at) < 3 {
            words = j.words ?? ""
            whole = j.whole
            panes.lastJump = nil
        }
        flashWhole = whole
        flashWords = words
        flashVerse = v
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if flashVerse == v {
                flashVerse = 0
                flashWords = ""
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

    /// К месту панели. initial — экран только появился (открыли книгу, сменили перевод): встаём сразу, без «подъезда»,
    /// и там, где читали (верхний видимый стих), если глава та же
    private func scroll(_ proxy: ScrollViewProxy, initial: Bool, animated: Bool = true) {
        var v = focus
        if initial, (panes.live.chapter[pane.id] ?? chapter) == chapter, let lv = panes.live.verse[pane.id], lv > 0 { v = lv }
        var t = Transaction()
        t.disablesAnimations = true
        if bookOn {
            let rows = bookBox.rows.filter { $0.chapter == chapter && $0.kind == .verse }
            // стих 0/1 — заголовок главы; 9999 — конец главы; иначе строка стиха (в сплошном тексте — его блок)
            var target = rows.isEmpty ? (bookBox.rows.first?.id ?? -1) : chapter * 1000
            if v >= 9999 {
                target = rows.last?.id ?? target
            } else if v > 1, let r = rows.last(where: { $0.verse <= v }) {
                target = r.id
            }
            if initial {
                withTransaction(t) { proxy.scrollTo(target, anchor: .top) }
                // второй раз — после раскладки: строки выше нужной ещё не были построены, их высота была примерной
                DispatchQueue.main.async {
                    withTransaction(t) { proxy.scrollTo(target, anchor: .top) }
                    positioned = true
                }
            } else if animated {
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            } else {
                // другая глава книги: сразу, без «проезда» через всю книгу
                withTransaction(t) { proxy.scrollTo(target, anchor: .top) }
                DispatchQueue.main.async { withTransaction(t) { proxy.scrollTo(target, anchor: .top) } }
            }
            return
        }
        guard v > 0 else { return }
        var target = v == 1 ? 0 : v
        let d = chapterData()
        if continuous, let blk = blocks(d.verses, d.heads).first(where: { $0.verses.contains { $0.num == v } }) {
            target = blk.id
        }
        if initial && v != focus {
            // открыли или закрыли панель — глава построилась заново: остаёмся на том же стихе
            DispatchQueue.main.async { withTransaction(t) { proxy.scrollTo(target, anchor: .top) } }
            return
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
    private func updateProgress(_ c: Int, _ verse: Int, _ count: Int) {
        let chapters = Double(max(1, module.books.first { $0.id == book }?.chapters ?? 1))
        let inChapter = Double(max(0, verse - 1)) / Double(max(1, count))
        let v = (Double(c - 1) + inChapter) / chapters
        // полоску оповещаем, только когда она заметно сдвинулась
        if abs((panes.live.progress[pane.id] ?? -1) - v) > 0.001 { panes.live.progress[pane.id] = v }
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
        // запоминается в ящике, а не в @State: запись на каждом кадре прокрутки иначе перестраивала бы весь текст
        let d = y - nav.chromeLastY
        nav.chromeLastY = y
        // переходы к стиху, возврат на сохранённое место, прокрутка, поставленная синхронизацией, — не повод прятать меню
        guard touchScroll.user else { return }
        // несколько окон: какое бы окно ни листали, уходит нижнее меню (оно следует за первым окном), шапки стоят
        let target = panes.panes.count > 1 ? (panes.panes.first?.id ?? pane.id) : pane.id
        func set(_ h: Bool) {
            if (panes.chrome.hidden[target] ?? false) != h { withAnimation(.easeInOut(duration: 0.2)) { panes.chrome.hidden[target] = h } }
        }
        guard hideOnScroll, selected.isEmpty, partVerse == nil, y > 80 else {
            nav.chromeAcc = 0
            set(false)
            return
        }
        if d == 0 || abs(d) > 1500 { return }
        nav.chromeAcc = (nav.chromeAcc > 0) == (d > 0) ? nav.chromeAcc + d : d
        if nav.chromeAcc > 14 {
            nav.chromeAcc = 0
            set(true)
        } else if nav.chromeAcc < -10 {
            nav.chromeAcc = 0
            set(false)
        }
    }

    private func toggle(_ n: Int) {
        if selected.contains(n) { selected.remove(n) } else { selected.insert(n) }
    }

    private func partKey(_ c: Int) -> String {
        let fp = marks.data.favorites.filter { $0.book == book && $0.chapter == c }.compactMap { f in f.part.map { "\(f.verse):\($0.from)-\($0.to)" } }
        let sel = c == chapter ? "\(partVerse ?? 0):\(partFrom ?? -1):\(partTo ?? -1)" : ""
        return "\(sel)|\(fp.sorted())"
    }

    private func partRange(_ n: Int) -> ClosedRange<Int>? {
        guard partVerse == n, let a = partFrom else { return nil }
        let b = partTo ?? a
        return min(a, b)...max(a, b)
    }

    private func favPartRange(_ c: Int, _ n: Int) -> ClosedRange<Int>? {
        guard let p = marks.data.favorites.first(where: { $0.book == book && $0.chapter == c && $0.verse == n })?.part else { return nil }
        return min(p.from, p.to)...max(p.from, p.to)
    }

    /// Любимые стихи главы (сердечко ставится в текст между номером и словами)
    private func favNums(_ c: Int) -> Set<Int> {
        Set(marks.data.favorites.filter { $0.book == book && $0.chapter == c }.map { $0.verse })
    }

    private func background(_ ch: Int, _ n: Int) -> Color {
        let cur = ch == chapter
        if cur && selected.contains(n) { return pal.accent.opacity(continuous ? 0.16 : 0.09) }
        // звучащий стих подсвечен
        if audio.active, audio.moduleId == module.id, let c = audio.current, c.book == book, c.chapter == ch, c.verse == n {
            return pal.accent.opacity(0.16)
        }
        if let c = hlColor(marks.highlight(MarksStore.key(book, ch, n))) {
            return c.color.opacity(0.4)
        }
        if marks.isFavorite(MarksStore.key(book, ch, n)) { return Color(hex: 0xd9475e).opacity(0.09) }
        if cur && n == flashVerse { return pal.hl }
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

    private func continuousNS(_ c: Int, _ blk: VerseBlock, _ xcounts: [Int: Int], _ icounts: [Int: Int]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for v in blk.verses {
            let part = NSMutableAttributedString(attributedString: attributedNS(v, c, xrefs: xcounts[v.num] ?? 0, illus: icounts[v.num] ?? 0, number: true, numberLink: true))
            if let bgc = continuousBackground(c, v.num) {
                part.addAttribute(.backgroundColor, value: UIColor(bgc), range: NSRange(location: 0, length: part.length))
            }
            out.append(part)
            out.append(NSAttributedString(string: " ", attributes: [.font: uiFont(fontSize), .aobVerse: v.num, .paragraphStyle: paragraph()]))
        }
        return out
    }

    private func continuousBackground(_ ch: Int, _ n: Int) -> Color? {
        let c = background(ch, n)
        return c == Color.clear ? nil : c
    }

    /// Текст стиха для UIKit: слова, номера Стронга, метки — с ссылками (aobURL) и номером стиха (aobVerse)
    private func attributedNS(_ v: Verse, _ ch: Int, xrefs: Int, illus: Int, number: Bool, numberLink: Bool) -> NSAttributedString {
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
        if favNums(ch).contains(v.num) {
            add("♥ ", [.font: UIFont.systemFont(ofSize: fontSize * 0.62), .foregroundColor: UIColor(Color(hex: 0xd9475e))])
        }
        var wi = 0
        let sel = ch == chapter ? partRange(v.num) : nil
        let fav = favPartRange(ch, v.num)
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
            // иллюстрации к стиху: значок «фото» и число, цвета акцента — как у параллельных мест; нажатие открывает их
            let url = URL(string: "aobillus:\(v.num)")!
            let small = UIFont.systemFont(ofSize: fontSize * 0.62, weight: .medium)
            add(" ", [.font: small, .aobURL: url])
            let cfg = UIImage.SymbolConfiguration(pointSize: fontSize * 0.6, weight: .semibold)
            if let img = UIImage(systemName: "photo", withConfiguration: cfg)?.withTintColor(UIColor(pal.accent), renderingMode: .alwaysOriginal) {
                let att = NSTextAttachment(image: img)
                att.bounds = CGRect(x: 0, y: (small.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
                let a = NSMutableAttributedString(attachment: att)
                a.addAttributes([.aobURL: url, .aobVerse: v.num], range: NSRange(location: 0, length: a.length))
                out.append(a)
            }
            add("\u{2009}\(illus)", [.font: small, .foregroundColor: UIColor(pal.accent), .aobURL: url])
        }
        let mainLength = out.length
        // пришли из поиска: найденные слова в этом стихе — плашками цвета акцента (на две секунды)
        if ch == chapter, v.num == flashVerse, !flashWords.isEmpty, let re = SearchEngine.regex(for: flashWords, wholeWord: flashWhole) {
            let plate = PlateStyle(UIColor(pal.accent.opacity(0.32)), radius: 5, inflate: 2)
            for m in re.matches(in: out.string, range: NSRange(location: 0, length: mainLength)) where m.range.length > 0 {
                out.addAttribute(.aobPlate, value: plate, range: m.range)
            }
        }
        out.addAttribute(.paragraphStyle, value: paragraph(), range: NSRange(location: 0, length: mainLength))
        if !continuous { appendComments(out, v, ch) }
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

    private func inlineComments(_ verse: Int, _ c: Int) -> [(module: InstalledModule, text: String)] {
        let mods = inlineModules()
        if mods.isEmpty { return [] }
        let key = "\(book)|\(c)|\(mods.map { $0.id })"
        if commBox.maps[key] == nil {
            if commBox.maps.count > 8 { commBox.maps = [:] }
            commBox.maps[key] = store.commentaryChapter(book: book, chapter: c, modules: mods)
        }
        var order: [String] = []
        var by: [String: (InstalledModule, [String])] = [:]
        for it in commBox.maps[key]?[verse] ?? [] {
            let t = (it.title.isEmpty ? "" : it.title + ". ") + it.text
            if by[it.module.id] == nil { order.append(it.module.id); by[it.module.id] = (it.module, []) }
            by[it.module.id]?.1.append(t)
        }
        return order.compactMap { id in by[id].map { (module: $0.0, text: $0.1.joined(separator: " ")) } }
    }

    /// Комментарии после стиха: текстом под стихом (свёрнут, нажатие раскрывает) или меткой «💬 Название»
    private func appendComments(_ out: NSMutableAttributedString, _ v: Verse, _ ch: Int) {
        let items = inlineComments(v.num, ch)
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
            let open = expandedComm.contains("\(ch)|\(key)")
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
            let ck = "\(chapter)|\(k)"
            if expandedComm.contains(ck) { expandedComm.remove(ck) } else { expandedComm.insert(ck) }
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
