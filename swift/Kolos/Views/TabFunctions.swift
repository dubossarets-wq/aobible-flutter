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

/// Настройка нижнего меню: вверху — его копия. Нажатие на пункт — варианты замены (на поиск — отдельной кнопкой или в
/// меню); зажать пункт и перетащить — поменять порядок. Меняется только копия; настоящее меню — по «Применить»
struct TabBarSettings: View {
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
    @State private var dragDX: CGFloat = 0
    @State private var dragStart = 0
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
                HStack(spacing: 0) {
                    ForEach(vis, id: \.self) { t in cell(t, itemW: w, vis: vis) }
                }
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
            .offset(x: isDrag ? dragDX - CGFloat(cur - dragStart) * itemW : 0)
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
            if f == .none { item("Пусто", "plus.circle.dashed", empty: true) } else { item(f.title, f.symbol) }
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
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragID != t {
                    dragID = t
                    dragStart = vis.firstIndex(of: t) ?? 0
                    openPop = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                let dx = drag?.translation.width ?? 0
                dragDX = dx
                // где сейчас центр пункта — на какое место он попал
                let pos = (CGFloat(dragStart) + 0.5) * itemW + dx
                let n = visible.count
                let target = min(max(0, Int(pos / itemW)), max(0, n - 1))
                if target != (visible.firstIndex(of: t) ?? target) { move(t, to: target) }
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.2)) {
                    dragID = nil
                    dragDX = 0
                }
                lastDrag = Date()
            }
    }

    /// Пункт t — на место target среди видимых (поиск вне меню в порядке всегда остаётся последним)
    private func move(_ t: String, to target: Int) {
        var v = visible
        v.removeAll { $0 == t }
        v.insert(t, at: min(max(0, target), v.count))
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
            .frame(width: 250)
            .frame(maxHeight: 380)
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
        .frame(width: 250)
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
