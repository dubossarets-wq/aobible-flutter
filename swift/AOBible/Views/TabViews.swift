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

/// Поиск: поле — системное (в нижнем меню), сюда приходит только текст запроса
struct SearchView: View {
    @Binding var query: String

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("Поиск", systemImage: "magnifyingglass")
                    } description: {
                        Text("Слово, ссылка вроде Ин 3:16 или номер Стронга, например G26.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("Поиск по тексту скоро появится", systemImage: "magnifyingglass")
                    } description: {
                        Text("Запрос: \(query)")
                    }
                }
            }
            .navigationTitle("Поиск")
        }
    }
}
