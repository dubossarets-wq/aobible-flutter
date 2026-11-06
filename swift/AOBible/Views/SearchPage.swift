import SwiftUI

enum SearchScope: Hashable {
    case all, ot, nt, book
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var hits: [SearchHit] = []
    @Published var running = false
    @Published var searched = ""
    private var task: Task<Void, Never>?

    func run(path: String?, query: String, whole: Bool, books: Set<String>?) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let path, q.count >= 2 else {
            hits = []
            running = false
            searched = ""
            return
        }
        running = true
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .userInitiated) {
                SearchEngine.run(path: path, query: q, wholeWord: whole, books: books)
            }.value
            if Task.isCancelled { return }
            hits = result
            searched = q
            running = false
        }
    }
}

/// Страница поиска: внизу — стеклянная кнопка «назад» и системное поле поиска (над клавиатурой)
struct SearchPage: View {
    @EnvironmentObject private var store: ModuleStore
    @Binding var query: String
    let onClose: () -> Void
    let onOpen: (String, Int, Int) -> Void

    @AppStorage("readerModule") private var moduleId = ""
    @AppStorage("readerBook") private var currentBook = "Gen"
    @AppStorage("searchWhole") private var whole = false
    @State private var scope: SearchScope = .all
    @State private var searching = false
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
            // касание в любом другом месте убирает клавиатуру (кнопки результатов при этом нажимаются как обычно)
            .simultaneousGesture(TapGesture().onEnded { searching = false })
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
            try? await Task.sleep(nanoseconds: 450_000_000)
            searching = true
        }
        .onChange(of: query) { _, _ in rerun() }
        .onChange(of: scope) { _, _ in rerun() }
        .onChange(of: whole) { _, _ in rerun() }
        .onAppear { rerun() }
    }

    private func rerun() {
        shown = 50
        model.run(path: module?.path, query: query, whole: whole, books: booksFilter)
    }
}
