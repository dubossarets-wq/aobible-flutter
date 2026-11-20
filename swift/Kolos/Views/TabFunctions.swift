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

/// Настройка нижнего меню: вверху — его копия. Нажатие на пункт — варианты замены; на поиск — отдельной кнопкой или
/// в меню. Меняется только копия; настоящее меню — по «Применить»
struct TabBarSettings: View {
    @AppStorage(TabFunction.leftKey) private var left = TabFunction.plans.rawValue
    @AppStorage(TabFunction.rightKey) private var right = TabFunction.saved.rawValue
    @AppStorage(TabFunction.searchKey) private var searchInBar = false

    /// Черновик: что видно в копии меню
    @State private var dLeft = TabFunction.plans.rawValue
    @State private var dRight = TabFunction.saved.rawValue
    @State private var dSearch = false
    @State private var loaded = false

    private var changed: Bool { dLeft != left || dRight != right || dSearch != searchInBar }
    private var isDefault: Bool {
        dLeft == TabFunction.plans.rawValue && dRight == TabFunction.saved.rawValue && !dSearch
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
            Text("Нажмите на пункт, чтобы заменить его. «Библия» и «Ещё» в меню всегда; убранные «Планы» и «Закладки» остаются в «Ещё». Меню изменится после «Применить».")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            dLeft = left
            dRight = right
            dSearch = searchInBar
        }
    }

    // MARK: - Копия меню

    private var preview: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                slot($dLeft, other: $dRight)
                item("Библия", "book", active: true)
                slot($dRight, other: $dLeft)
                item("Ещё", "line.3.horizontal")
                if dSearch { searchMenu { item("Поиск", "magnifyingglass") } }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
            if !dSearch {
                searchMenu {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: dSearch)
        .animation(.snappy(duration: 0.3), value: dLeft)
        .animation(.snappy(duration: 0.3), value: dRight)
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

    /// Место, которое можно заменить: нажали — список разделов (выбранный отмечен)
    private func slot(_ value: Binding<String>, other: Binding<String>) -> some View {
        let f = TabFunction.of(value.wrappedValue)
        return Menu {
            Picker(selection: Binding(get: { value.wrappedValue }, set: { new in
                // то же, что на другом месте, — меняются местами
                if new != TabFunction.none.rawValue && new == other.wrappedValue { other.wrappedValue = value.wrappedValue }
                value.wrappedValue = new
            })) {
                ForEach(TabFunction.allCases) { x in
                    Label(x.title, systemImage: x.symbol).tag(x.rawValue)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            if f == .none {
                item("Пусто", "plus.circle.dashed", empty: true)
            } else {
                item(f.title, f.symbol)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    /// Поиск: отдельной круглой кнопкой справа или пунктом меню
    private func searchMenu<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        Menu {
            Picker(selection: $dSearch) {
                Label("Отдельной кнопкой", systemImage: "circle").tag(false)
                Label("В меню", systemImage: "capsule").tag(true)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}
