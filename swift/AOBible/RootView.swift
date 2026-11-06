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

    /// Тема приложения: «как в системе» — без принуждения; тёмные темы Flutter-версии (dark, ocean, black) — тёмная
    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark", "ocean", "black": return .dark
        default: return nil
        }
    }

    /// Открыть место в чтении
    private func open(_ book: String, _ chapter: Int, _ verse: Int) {
        let d = UserDefaults.standard
        d.set(book, forKey: "readerBook")
        d.set(chapter, forKey: "readerChapter")
        d.set(verse, forKey: "readerVerse")
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
        .preferredColorScheme(scheme)
    }
}
