import SwiftUI

/// Что можно поставить в нижнее меню по обе стороны от «Библии» (по умолчанию — «Планы» и «Закладки»).
/// «Библия», «Ещё» и поиск в меню всегда. Убранные из меню «Планы» и «Закладки» появляются вверху «Ещё»
enum TabFunction: String, CaseIterable, Identifiable {
    case plans, saved, history, sermons, dictionary, maps, library, audio, appearance, settings, none

    var id: String { rawValue }

    static let leftKey = "tabLeft"
    static let rightKey = "tabRight"
    /// Поиск — пунктом меню (true) или отдельной круглой кнопкой справа (false)
    static let searchKey = "searchInTabBar"
    /// Порядок пунктов меню: «L» (слева), «B» (Библия), «R» (справа), «M» (Ещё), «S» (поиск), через запятую
    static let orderKey = "tabOrder"
    static let defaultOrder = "L,B,R,M,S"

    /// Порядок из строки: лишнее и повторы отбрасываются, недостающие пункты — в конец
    static func parseOrder(_ raw: String) -> [String] {
        let all = defaultOrder.split(separator: ",").map(String.init)
        var seen = Set<String>()
        var out: [String] = []
        for t in raw.split(separator: ",").map(String.init) where all.contains(t) && seen.insert(t).inserted { out.append(t) }
        for t in all where !seen.contains(t) { out.append(t) }
        return out
    }

    static func of(_ raw: String) -> TabFunction { TabFunction(rawValue: raw) ?? .none }

    var title: LocalizedStringKey {
        switch self {
        case .plans: "Планы"
        case .saved: "Закладки"
        case .history: "История"
        case .sermons: "Проповеди"
        case .dictionary: "Словарь"
        case .maps: "Карты"
        case .library: "Библиотека"
        case .audio: "Аудио"
        case .appearance: "Оформление"
        case .settings: "Настройки"
        case .none: "Нет"
        }
    }

    /// Название по-русски — оно же ключ перевода (см. TabTitles)
    var ruTitle: String {
        switch self {
        case .plans: "Планы"
        case .saved: "Закладки"
        case .history: "История"
        case .sermons: "Проповеди"
        case .dictionary: "Словарь"
        case .maps: "Карты"
        case .library: "Библиотека"
        case .audio: "Аудио"
        case .appearance: "Оформление"
        case .settings: "Настройки"
        case .none: "Нет"
        }
    }

    /// Короткое название для нижнего меню (там на пункт — около 70 пт): длинные заменены короче, чтобы подписи не
    /// наезжали на соседние пункты. Оно же ключ перевода
    var barTitle: String {
        switch self {
        case .appearance: "Вид"
        case .library: "Модули"
        default: ruTitle
        }
    }

    var symbol: String {
        switch self {
        case .plans: "calendar"
        case .saved: "heart"
        case .history: "clock.arrow.circlepath"
        case .sermons: "doc.text"
        case .dictionary: "character.book.closed"
        case .maps: "map"
        case .library: "books.vertical"
        case .audio: "waveform"
        case .appearance: "paintbrush"
        case .settings: "gearshape"
        case .none: "minus.circle"
        }
    }

    /// Экран вкладки (со своей навигацией)
    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .plans: PlansView()
        case .saved: BookmarksView()
        default: NavigationStack { page }
        }
    }

    /// Сам экран (внутри чужой навигации)
    @MainActor @ViewBuilder var page: some View {
        switch self {
        case .plans: PlansView(embedded: true)
        case .saved: BookmarksView(embedded: true)
        case .history: HistoryView()
        case .sermons: SermonsView()
        case .dictionary: DictionaryView()
        case .maps: MapsView()
        case .library: TabLibrary()
        case .audio: AudioSettingsView()
        case .appearance: AppearanceView()
        case .settings: SettingsView()
        case .none: EmptyView()
        }
    }
}

private struct TabLibrary: View {
    @EnvironmentObject private var panes: PanesStore

    var body: some View {
        ModulesList(selected: panes.primaryBinding())
            .navigationTitle("Библиотека модулей")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Названия пунктов нижнего меню одной ширины. Системное меню делит место по длине подписей («Проповеди» занимает больше,
/// чем «Ещё»), и средний пункт съезжает с середины. Короткие подписи дополняются с обеих сторон неразрывными пробелами до
/// ширины самой длинной — пункты получаются одинаковыми, средний стоит по центру
enum TabTitles {
    /// Подпись на языке интерфейса: по-русски — как есть, иначе — перевод из файла языка (русский текст — ключ)
    static func localized(_ ru: String, lang: String) -> String {
        guard lang != "ru" else { return ru }
        let folder = lang == "zh" ? "zh-Hans" : lang
        guard let p = Bundle.main.path(forResource: folder, ofType: "lproj"), let b = Bundle(path: p) else { return ru }
        return b.localizedString(forKey: ru, value: ru, table: nil)
    }

    /// separate — поиск отдельной круглой кнопкой (меню уже на её ширину)
    static func equalWidth(_ titles: [String: String], separateSearch: Bool) -> [String: String] {
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        let gap = max(1, width("\u{00A0}"))
        let widest = titles.values.map(width).max() ?? 0
        // место на один пункт: ширина меню (поля по 20 пт; круглая кнопка поиска — 56 + 8) на число пунктов
        let bar = UIScreen.main.bounds.width - 40 - (separateSearch ? 64 : 0)
        let item = bar / CGFloat(max(1, titles.count))
        // самая длинная подпись не помещается с зазором — вместо подписей остаются одни значки: так они ни на что не заезжают
        if widest > item - 10 { return titles.mapValues { _ in "" } }
        // неразрывный пробел (~2,6 пт), тонкий и волосяной: крупными шагами ширины подписей не выровнять — округление сдвигало
        // пункты, и «Библия» уезжала от середины. Мелкими шагами ширина сходится с точностью до долей пункта
        let units: [(String, CGFloat)] = ["\u{00A0}", "\u{2009}", "\u{200A}"].map { ($0, width($0)) }.filter { $0.1 >= 0.3 }.sorted { $0.1 > $1.1 }
        func padding(_ delta: CGFloat) -> String {
            var rest = delta / 2
            var out = ""
            for (ch, w) in units {
                let n = Int(floor(rest / w))
                if n > 0 {
                    out += String(repeating: ch, count: n)
                    rest -= CGFloat(n) * w
                }
            }
            return out
        }
        var out: [String: String] = [:]
        for (k, t) in titles {
            let sp = padding(widest - width(t))
            out[k] = sp + t + sp
        }
        return out
    }
}

/// Настройка нижнего меню: вверху — его копия. Нажатие на пункт — варианты замены (на поиск — отдельной кнопкой или в
/// меню); зажать пункт и перетащить — поменять порядок. Меняется только копия; настоящее меню — по «Применить»
struct TabBarSettings: View {
    /// Идёт перетаскивание пункта — экран настроек в это время не прокручивается
    @Binding var dragging: Bool

    @AppStorage(TabFunction.leftKey) private var left = TabFunction.plans.rawValue
    @AppStorage(TabFunction.rightKey) private var right = TabFunction.saved.rawValue
    @AppStorage(TabFunction.searchKey) private var searchInBar = false
    @AppStorage(TabFunction.orderKey) private var order = TabFunction.defaultOrder

    /// Черновик: что видно в копии меню. Порядок — пункты «L» (слева), «B» (Библия), «R» (справа), «M» (Ещё), «S» (поиск)
    @State private var dLeft = TabFunction.plans.rawValue
    @State private var dRight = TabFunction.saved.rawValue
    @State private var dSearch = false
    @State private var dOrder = TabFunction.parseOrder(TabFunction.defaultOrder)
    @State private var loaded = false
    /// У какого пункта открыт список вариантов («L», «R», «S»)
    @State private var openPop: String?
    /// Перетаскивание: пункт, смещение пальца, где пункт стоял в начале, когда закончили (тап после него не считается)
    @State private var dragID: String?
    /// Где центр перетаскиваемого пункта (в координатах ряда) и за какое место его взяли
    @State private var dragCenter: CGFloat = 0
    @State private var grab: CGFloat = 0
    @State private var lastDrag = Date.distantPast

    private var visible: [String] { dOrder.filter { dSearch || $0 != "S" } }

    private var changed: Bool {
        dLeft != left || dRight != right || dSearch != searchInBar || dOrder != TabFunction.parseOrder(order)
    }

    private var isDefault: Bool {
        dLeft == TabFunction.plans.rawValue && dRight == TabFunction.saved.rawValue && !dSearch
            && dOrder == TabFunction.parseOrder(TabFunction.defaultOrder)
    }

    var body: some View {
        Section {
            VStack(spacing: 14) {
                preview
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) {
                            dLeft = TabFunction.plans.rawValue
                            dRight = TabFunction.saved.rawValue
                            dSearch = false
                            dOrder = TabFunction.parseOrder(TabFunction.defaultOrder)
                        }
                    } label: {
                        Text("По умолчанию").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(isDefault)
                    Button {
                        left = dLeft
                        right = dRight
                        searchInBar = dSearch
                        order = dOrder.joined(separator: ",")
                    } label: {
                        Text("Применить").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!changed)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 6)
            // копия меню лежит на сером фоне, как настоящее меню над текстом
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        } header: {
            Text("Нижнее меню")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Нажмите на пункт, чтобы заменить его. «Библия» и «Ещё» в меню всегда; убранные «Планы» и «Закладки» остаются в «Ещё». Меню изменится после «Применить».")
                Text("Зажмите пункт и перетащите, чтобы поменять порядок.")
            }
        }
        .onChange(of: dragID) { _, v in dragging = v != nil }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            dLeft = left
            dRight = right
            dSearch = searchInBar
            dOrder = TabFunction.parseOrder(order)
        }
    }

    // MARK: - Копия меню

    private var preview: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let vis = visible
                let w = max(1, (geo.size.width - 8) / CGFloat(max(1, vis.count)))
                // каждый пункт стоит в своей ячейке (offset = номер × ширина); перетаскиваемый — там, где палец, а не в
                // ячейке: перестановка соседей его не двигает
                ZStack(alignment: .topLeading) {
                    ForEach(vis, id: \.self) { t in cell(t, itemW: w, vis: vis) }
                }
                .frame(width: w * CGFloat(vis.count), height: 48, alignment: .topLeading)
                // жест считается в координатах ряда, а не самого пункта
                .coordinateSpace(name: "tabbar")
                .padding(4)
            }
            .frame(height: 56)
            .glassEffect(.regular, in: Capsule())
            if !dSearch {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
                    .onTapGesture { openPop = "S" }
                    .popover(isPresented: popBinding("S")) { searchOptions.presentationCompactAdaptation(.popover) }
            }
        }
        .animation(.snappy(duration: 0.3), value: dSearch)
        .animation(.snappy(duration: 0.25), value: dOrder)
    }

    /// Пункт копии: нажатие — варианты, зажать и вести — переставить
    @ViewBuilder private func cell(_ t: String, itemW: CGFloat, vis: [String]) -> some View {
        let isDrag = dragID == t
        let cur = vis.firstIndex(of: t) ?? 0
        content(t)
            .frame(width: itemW)
            .offset(x: isDrag ? dragCenter - itemW / 2 : CGFloat(cur) * itemW)
            .scaleEffect(isDrag ? 1.1 : 1)
            .shadow(color: .black.opacity(isDrag ? 0.22 : 0), radius: 8, y: 3)
            .zIndex(isDrag ? 1 : 0)
            .animation(.snappy(duration: 0.2), value: isDrag)
            .onTapGesture { tapped(t) }
            .popover(isPresented: popBinding(t)) { options(t).presentationCompactAdaptation(.popover) }
            .simultaneousGesture(dragGesture(t, itemW: itemW, vis: vis))
    }

    @ViewBuilder private func content(_ t: String) -> some View {
        switch t {
        case "B": item("Библия", "book", active: true)
        case "M": item("Ещё", "line.3.horizontal")
        case "S": item("Поиск", "magnifyingglass")
        default:
            let f = TabFunction.of(t == "L" ? dLeft : dRight)
            if f == .none { item("Пусто", "plus.circle.dashed", empty: true) } else { item(LocalizedStringKey(f.barTitle), f.symbol) }
        }
    }

    /// Пункт меню (как в настоящем: значок и подпись)
    private func item(_ title: LocalizedStringKey, _ symbol: String, active: Bool = false, empty: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(height: 24)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(active ? Color.accentColor : (empty ? Color.secondary : Color.primary))
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            if active { Capsule().fill(Color.primary.opacity(0.07)) }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Нажатие и перетаскивание

    private func tapped(_ t: String) {
        // после перетаскивания палец отпускается — это не нажатие
        guard dragID == nil, Date().timeIntervalSince(lastDrag) > 0.35 else { return }
        if t == "L" || t == "R" || t == "S" { openPop = t }
    }

    private func popBinding(_ t: String) -> Binding<Bool> {
        Binding(get: { openPop == t }, set: { if !$0, openPop == t { openPop = nil } })
    }

    private func dragGesture(_ t: String, itemW: CGFloat, vis: [String]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("tabbar")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let now = visible
                if dragID != t {
                    dragID = t
                    // за какое место пункта взяли: он едет за пальцем, не прыгая центром под палец
                    grab = drag.startLocation.x - (CGFloat(now.firstIndex(of: t) ?? 0) + 0.5) * itemW
                    openPop = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                // центр пункта — прямо по положению пальца в ряду; на каком он месте — по нему
                let center = drag.location.x - grab
                dragCenter = center
                let target = min(max(0, Int(floor(center / itemW))), max(0, now.count - 1))
                if let cur = now.firstIndex(of: t), cur != target { move(t, to: target) }
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.2)) { dragID = nil }
                lastDrag = Date()
            }
    }

    /// Пункт t становится на место target, а тот, что стоял там, — на прежнее место t (остальные не двигаются).
    /// Поиск вне меню в порядке всегда остаётся последним
    private func move(_ t: String, to target: Int) {
        var v = visible
        guard let cur = v.firstIndex(of: t), target >= 0, target < v.count, target != cur else { return }
        v.swapAt(cur, target)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.25)) { dOrder = dSearch ? v : v + ["S"] }
    }

    // MARK: - Варианты

    @ViewBuilder private func options(_ t: String) -> some View {
        if t == "S" {
            searchOptions
        } else {
            let mine = t == "L" ? dLeft : dRight
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(TabFunction.allCases) { x in
                        Button {
                            choose(x, in: t)
                            openPop = nil
                        } label: {
                            HStack {
                                Label(x.title, systemImage: x.symbol)
                                Spacer(minLength: 12)
                                if x.rawValue == mine { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if x != TabFunction.allCases.last { Divider().padding(.leading, 16) }
                    }
                }
            }
            // запас от краёв: системное окошко сильно скруглено, и строки вплотную к краю упирались в углы
            .padding(.vertical, 8)
            .frame(width: 262)
            .frame(maxHeight: 400)
        }
    }

    private var searchOptions: some View {
        VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { inBar in
                Button {
                    withAnimation(.snappy) { dSearch = inBar }
                    openPop = nil
                } label: {
                    HStack {
                        Label(inBar ? "В меню" : "Отдельной кнопкой", systemImage: inBar ? "capsule" : "circle")
                        Spacer(minLength: 12)
                        if dSearch == inBar { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !inBar { Divider().padding(.leading, 16) }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 262)
    }

    /// Выбрали раздел для «L» или «R»: тот же, что на другом месте, — меняются местами
    private func choose(_ x: TabFunction, in t: String) {
        let other = t == "L" ? dRight : dLeft
        let mine = t == "L" ? dLeft : dRight
        if x != .none && x.rawValue == other {
            if t == "L" { dRight = mine } else { dLeft = mine }
        }
        if t == "L" { dLeft = x.rawValue } else { dRight = x.rawValue }
    }
}
