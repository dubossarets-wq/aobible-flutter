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
                showSearch = true
            } else {
                lastTab = new
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(query: $query) { showSearch = false }
        }
    }
}
