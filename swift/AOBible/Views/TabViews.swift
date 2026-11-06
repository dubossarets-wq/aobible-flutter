import SwiftUI

/// Планы чтения — пока заглушка
struct PlansView: View {
    var body: some View {
        NavigationStack {
            SoonView(title: "Планы чтения", symbol: "calendar")
                .navigationTitle("Планы чтения")
        }
    }
}

/// Закладки — пока заглушка
struct BookmarksView: View {
    var body: some View {
        NavigationStack {
            SoonView(title: "Закладки", symbol: "heart")
                .navigationTitle("Закладки")
        }
    }
}

/// Страница поиска: внизу — стеклянная кнопка «назад» и системное поле поиска (над клавиатурой), посередине результаты
struct SearchPage: View {
    @Binding var query: String
    let onClose: () -> Void
    @State private var searching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("Поиск", systemImage: "magnifyingglass")
                    } description: {
                        Text("Слово, ссылка вроде Ин 3:16 или номер Стронга, например G26.")
                    }
                    .padding(.top, 80)
                } else {
                    ContentUnavailableView {
                        Label("Поиск по тексту скоро появится", systemImage: "magnifyingglass")
                    } description: {
                        Text("Запрос: \(query)")
                    }
                    .padding(.top, 80)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Поиск")
            .searchable(text: $query, isPresented: $searching, prompt: "Слово, Ин 3:16 или G26")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Назад")
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .task {
            // поле поиска открывается сразу — клавиатура на экране
            try? await Task.sleep(nanoseconds: 450_000_000)
            searching = true
        }
    }
}
