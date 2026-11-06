import SwiftUI

/// Вкладки нижнего меню. Поиск — системная вкладка iOS 26: круглая кнопка справа, которая раскрывается в поле поиска
/// (всё — от самой системы: стекло, клавиатура, сворачивание меню).
enum AppTab: Hashable {
    case plans, bible, saved, more, search
}

struct RootView: View {
    @State private var tab: AppTab = .bible
    @State private var lastTab: AppTab = .bible
    @State private var query = ""
    @State private var showSearch = false
    @AppStorage("theme") private var theme = "system"
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var plans: PlansStore
    @EnvironmentObject private var sermons: SermonStore
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @AppStorage("lastBuild") private var lastBuild = ""
    @AppStorage("interfaceLanguage") private var lang = "ru"

    /// Тема приложения: «как в системе» — без принуждения; тёмные темы Flutter-версии (dark, ocean, black) — тёмная
    private var scheme: ColorScheme? {
        AppThemes.scheme(theme)
    }

    /// Открыть место в чтении
    private func open(_ book: String, _ chapter: Int, _ verse: Int) {
        panes.open(book, chapter, verse)
        showSearch = false
        tab = .bible
        lastTab = .bible
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Планы", systemImage: "calendar", value: AppTab.plans) {
                PlansView()
            }
            Tab("Библия", systemImage: "book", value: AppTab.bible) {
                ReaderView()
            }
            Tab("Закладки", systemImage: "heart", value: AppTab.saved) {
                BookmarksView()
            }
            Tab("Ещё", systemImage: "line.3.horizontal", value: AppTab.more) {
                MoreView()
            }
            Tab(value: AppTab.search, role: .search) {
                Color.clear
            }
        }
        // мини-проигрыватель над нижним меню, пока идёт аудио
        .modifier(AudioAccessory(active: audio.active))
        .sheet(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) {
            WelcomeSheet()
        }
        .task {
            // перед обновлением приложения — копия данных (последние 5)
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            if !lastBuild.isEmpty, lastBuild != build {
                UserData.snapshot("до обновления с версии \(lastBuild)", marks: marks, plans: plans, sermons: sermons)
            }
            lastBuild = build
            // первый запуск: основной перевод, затем остальное в фоне
            await Starter.run(store: store, lang: lang)
        }
        // кнопка поиска в меню — вход: страница поиска открывается поверх меню со своей нижней панелью
        // (слева всегда «назад», рядом системное поле поиска), а выбранной остаётся прежняя вкладка
        .onChange(of: tab) { _, new in
            if new == .search {
                tab = lastTab
                // страница поиска появляется сразу, без анимации выезда — как системная вкладка, и клавиатура
                // не ждёт окончания анимации
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { showSearch = true }
            } else {
                lastTab = new
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(query: $query, onClose: { showSearch = false }, onOpen: open)
                .preferredColorScheme(scheme)
        }
        .environment(\.openVerse, OpenVerse(run: open))
        .environment(\.readerPalette, AppThemes.palette(theme))
        .tint(theme == "system" ? nil : AppThemes.palette(theme).accent)
        .preferredColorScheme(scheme)
    }
}

/// Мини-проигрыватель над нижним меню: на iOS 26.1 и новее — только пока идёт аудио
private struct AudioAccessory: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: active) { AudioBar() }
        } else {
            content.tabViewBottomAccessory { AudioBar() }
        }
    }
}
