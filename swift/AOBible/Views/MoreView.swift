import SwiftUI

/// «Ещё»: сгруппированный список с крупным заголовком — шапка, сворачивание заголовка, края прокрутки и стекло
/// рисует сама система
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    link("Закладка на это место", "bookmark.fill", .orange)
                    link("Проповеди", "doc.text.fill", Color(red: 0.35, green: 0.34, blue: 0.84))
                    link("Слушать с этого места", "headphones", Color(red: 1.0, green: 0.18, blue: 0.33))
                    link("Карты", "map.fill", .green)
                }
                Section {
                    link("Синхронная прокрутка", "link", .blue)
                    link("Панели друг над другом", "rectangle.split.1x2.fill", Color(red: 0.35, green: 0.34, blue: 0.84))
                    NavigationLink {
                        LibraryScreen()
                    } label: {
                        IconLabel(title: "Библиотека модулей", symbol: "books.vertical.fill", color: .teal)
                    }
                    NavigationLink {
                        DictionaryView()
                    } label: {
                        IconLabel(title: "Словарь", symbol: "character.book.closed.fill", color: .brown)
                    }
                }
                Section {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        IconLabel(title: "Оформление", symbol: "paintbrush.fill", color: .purple)
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        IconLabel(title: "Настройки", symbol: "gearshape.fill", color: .gray)
                    }
                    link("Инструкция", "book.fill", .blue)
                    link("Сообщить о проблеме", "exclamationmark.bubble.fill", .red)
                    link("Что нового", "sparkles", .orange)
                    NavigationLink {
                        AboutView()
                    } label: {
                        IconLabel(title: "О приложении", symbol: "info.circle.fill", color: .gray)
                    }
                }
            }
            .navigationTitle("Ещё")
        }
    }

    private struct LibraryScreen: View {
        @AppStorage("readerModule") private var moduleId = ""

        var body: some View {
            ModulesList(selected: $moduleId)
                .navigationTitle("Библиотека модулей")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func link(_ title: String, _ symbol: String, _ color: Color) -> some View {
        NavigationLink {
            SoonView(title: title, symbol: symbol)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            IconLabel(title: title, symbol: symbol, color: color)
        }
    }
}
