import SwiftUI

enum SearchScope: Hashable {
    case all, ot, nt, book
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var hits: [SearchHit] = []
    @Published var running = false
    @Published var searched = ""
    private var generation = 0

    /// Поиск без пауз: на каждое изменение запроса — новый проход по готовому индексу (миллисекунды);
    /// устаревший результат отбрасывается
    func run(path: String?, query: String, whole: Bool, books: Set<String>?) {
        generation += 1
        let g = generation
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let path, q.count >= 2 else {
            hits = []
            running = false
            searched = ""
            return
        }
        running = hits.isEmpty
        Task.detached(priority: .userInitiated) { [weak self] in
            let idx = SearchIndex.index(path: path)
            let result = idx.map { SearchEngine.run(index: $0, query: q, wholeWord: whole, books: books) } ?? []
            await MainActor.run {
                guard let self, g == self.generation else { return }
                self.hits = result
                self.searched = q
                self.running = false
            }
        }
    }
}

/// Страница поиска: внизу — стеклянная кнопка «назад» и системное поле поиска (над клавиатурой)
struct SearchPage: View {
    @EnvironmentObject private var store: ModuleStore
    @Binding var query: String
    let onClose: () -> Void
    let onOpen: (String, Int, Int) -> Void

    @EnvironmentObject private var panes: PanesStore
    private var moduleId: String { panes.primaryModule }
    private var currentBook: String { panes.panes.first?.book ?? "Gen" }
    @AppStorage("searchWhole") private var whole = false
    @State private var scope: SearchScope = .all
    // поле поиска активно с самого начала: клавиатура выезжает вместе со страницей, без паузы
    @State private var searching = true
    @State private var shown = 50
    @StateObject private var model = SearchModel()

    private var module: InstalledModule? {
        store.module(moduleId) ?? store.bibles.first
    }

    private var booksFilter: Set<String>? {
        switch scope {
        case .all: return nil
        case .ot: return Set(Books.all.filter { $0.t == "OT" }.map { $0.id })
        case .nt: return Set(Books.all.filter { $0.t == "NT" }.map { $0.id })
        case .book: return [currentBook]
        }
    }

    private func label(_ book: String, _ chapter: Int, _ verse: Int) -> String {
        let short = module?.books.first { $0.id == book }?.short ?? Books.info(book)?.short ?? book
        return "\(short) \(chapter):\(verse)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Где искать", selection: $scope) {
                        Text("Вся Библия").tag(SearchScope.all)
                        Text("ВЗ").tag(SearchScope.ot)
                        Text("НЗ").tag(SearchScope.nt)
                        Text(Books.info(currentBook)?.short ?? "Книга").tag(SearchScope.book)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Только целые слова", isOn: $whole)
                }

                if let r = RefParser.parse(query) {
                    Section {
                        Button {
                            onOpen(r.book, r.chapter, r.verse)
                        } label: {
                            Label("Перейти: \(label(r.book, r.chapter, r.verse))", systemImage: "arrow.turn.down.right")
                        }
                    }
                }

                if module == nil {
                    Section {
                        Text("Сначала скачайте перевод Библии: «Ещё» → «Библиотека модулей».")
                            .foregroundStyle(.secondary)
                    }
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    Section {
                        Text("Слово, ссылка вроде Ин 3:16 или номер Стронга, например G26.")
                            .foregroundStyle(.secondary)
                    }
                } else if model.running && model.hits.isEmpty {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Поиск…").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        ForEach(model.hits.prefix(shown)) { h in
                            Button {
                                onOpen(h.book, h.chapter, h.verse)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(label(h.book, h.chapter, h.verse))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                    Text(SearchEngine.highlighted(h.text, query: model.searched, wholeWord: whole))
                                        .foregroundStyle(.primary)
                                }
                            }
                            // обычная строка списка: текст стиха — основным цветом (белым в тёмной теме), не цветом кнопки
                            .buttonStyle(.plain)
                        }
                        if model.hits.count > shown {
                            Button("Показать ещё (\(model.hits.count - shown))") { shown += 50 }
                        }
                    } header: {
                        Text("Найдено: \(model.hits.count)")
                    } footer: {
                        if model.hits.isEmpty && !model.running {
                            Text("Попробуйте другую форму слова или отключите «только целые слова».")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.large)
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
            // страховка: если система не активировала поле сама
            try? await Task.sleep(nanoseconds: 120_000_000)
            searching = true
        }
        .onChange(of: query) { _, _ in rerun() }
        .onChange(of: scope) { _, _ in rerun() }
        .onChange(of: whole) { _, _ in rerun() }
        .onAppear {
            if let path = module?.path { SearchIndex.warm(path: path) }
            rerun()
        }
    }

    private func rerun() {
        shown = 50
        model.run(path: module?.path, query: query, whole: whole, books: booksFilter)
    }
}
