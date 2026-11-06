import SwiftUI

/// «Ещё»: сгруппированный список с крупным заголовком — шапка, сворачивание заголовка, края прокрутки и стекло
/// рисует сама система
struct MoreView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    @EnvironmentObject private var audio: AudioEngine
    @Environment(\.openVerse) private var openVerse

    var body: some View {
        NavigationStack {
            List {
                Section {
                    link("Закладка на это место", "bookmark.fill", .orange)
                    NavigationLink {
                        SermonsView()
                    } label: {
                        IconLabel(title: "Проповеди", symbol: "doc.text.fill", color: Color(red: 0.35, green: 0.34, blue: 0.84))
                    }
                    Button {
                        if let p = panes.panes.first {
                            openVerse(p.book, p.chapter, max(1, p.verse))
                            Task { await audio.listen(store: store, moduleId: p.moduleId, from: Place(book: p.book, chapter: p.chapter, verse: max(1, p.verse))) }
                        }
                    } label: {
                        IconLabel(title: "Слушать с этого места", symbol: "headphones", color: Color(red: 1.0, green: 0.18, blue: 0.33))
                    }
                    .buttonStyle(.plain)
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
                        AudioSettingsView()
                    } label: {
                        IconLabel(title: "Аудио", symbol: "waveform", color: Color(red: 1.0, green: 0.18, blue: 0.33))
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
                    NavigationLink {
                        MyDataView()
                    } label: {
                        IconLabel(title: "Мои данные", symbol: "externaldrive.fill", color: .gray)
                    }
                    NavigationLink {
                        HelpView()
                    } label: {
                        IconLabel(title: "Инструкция", symbol: "book.fill", color: .blue)
                    }
                    NavigationLink {
                        ReportView()
                    } label: {
                        IconLabel(title: "Сообщить о проблеме", symbol: "exclamationmark.bubble.fill", color: .red)
                    }
                    NavigationLink {
                        NewsView()
                    } label: {
                        IconLabel(title: "Что нового", symbol: "sparkles", color: .orange)
                    }
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
        @EnvironmentObject private var panes: PanesStore

        var body: some View {
            ModulesList(selected: panes.primaryBinding())
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
