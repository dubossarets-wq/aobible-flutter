import SwiftUI

/// Что можно поставить в нижнее меню по обе стороны от «Библии» (по умолчанию — «Планы» и «Закладки»).
/// «Библия», «Ещё» и поиск в меню всегда. Убранные из меню «Планы» и «Закладки» появляются вверху «Ещё»
enum TabFunction: String, CaseIterable, Identifiable {
    case plans, saved, history, sermons, dictionary, maps, library, audio, appearance, settings, none

    var id: String { rawValue }

    static let leftKey = "tabLeft"
    static let rightKey = "tabRight"

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

/// Настройка нижнего меню: что стоит слева и справа от «Библии»
struct TabBarSettings: View {
    @AppStorage(TabFunction.leftKey) private var left = TabFunction.plans.rawValue
    @AppStorage(TabFunction.rightKey) private var right = TabFunction.saved.rawValue

    var body: some View {
        Section {
            picker("Слева от «Библии»", $left, other: $right)
            picker("Справа от «Библии»", $right, other: $left)
        } header: {
            Text("Нижнее меню")
        } footer: {
            Text("«Библия», «Ещё» и поиск в меню всегда. Убранные «Планы» и «Закладки» остаются в «Ещё».")
        }
    }

    private func picker(_ title: LocalizedStringKey, _ value: Binding<String>, other: Binding<String>) -> some View {
        Picker(selection: Binding(get: { value.wrappedValue }, set: { new in
            // то же, что на другом месте, — меняются местами
            if new != TabFunction.none.rawValue && new == other.wrappedValue { other.wrappedValue = value.wrappedValue }
            value.wrappedValue = new
        })) {
            ForEach(TabFunction.allCases) { f in
                Label(f.title, systemImage: f.symbol).tag(f.rawValue)
            }
        } label: {
            Text(title)
        }
        .pickerStyle(.menu)
    }
}
