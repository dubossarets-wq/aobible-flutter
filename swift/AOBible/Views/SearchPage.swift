import SwiftUI

enum SearchScope: Hashable {
    case all, ot, nt, book
}

extension SearchHit {
    func tagged(_ module: String) -> SearchHit {
        var h = SearchHit(id: id, book: book, chapter: chapter, verse: verse, text: text)
        h.moduleId = module
        return h
    }
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var hits: [SearchHit] = []
    @Published var running = false
    @Published var searched = ""
    private var generation = 0

    /// Поиск без пауз: на каждое изменение запроса — новый проход по готовому индексу (миллисекунды);
    /// устаревший результат отбрасывается. targets — переводы, в которых ищем (id, файл)
    func run(targets: [(String, String)], query: String, whole: Bool, books: Set<String>?) {
        generation += 1
        let g = generation
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !targets.isEmpty, q.count >= 2 else {
            hits = []
            running = false
            searched = ""
            return
        }
        running = hits.isEmpty
        Task.detached(priority: .userInitiated) { [weak self] in
            var all: [SearchHit] = []
            for (id, path) in targets {
                if let idx = SearchIndex.index(path: path) {
                    all.append(contentsOf: SearchEngine.run(index: idx, query: q, wholeWord: whole, books: books).map { $0.tagged(id) })
                }
            }
            // несколько переводов: места в порядке Библии, у одного места — переводы подряд
            if targets.count > 1 {
                let order = Dictionary(uniqueKeysWithValues: Books.all.enumerated().map { ($1.id, $0) })
                all.sort {
                    let a = order[$0.book] ?? 999, b = order[$1.book] ?? 999
                    if a != b { return a < b }
                    if $0.chapter != $1.chapter { return $0.chapter < $1.chapter }
                    return $0.verse < $1.verse
                }
            }
            let result = all
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
    @AppStorage("searchAllModules") private var allMods = false
    @AppStorage("searchOriginals") private var withOrig = false
    @State private var scope: SearchScope = .all
    // поле поиска активно с самого начала: клавиатура выезжает вместе со страницей, без паузы
    @State private var searching = true
    @State private var shown = 50
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
    @StateObject private var model = SearchModel()

    private let originalIds: Set<String> = ["oshb", "byz-rp2018"]

    private var module: InstalledModule? {
        store.module(moduleId) ?? store.bibles.first
    }

    /// Переводы для поиска: открытый — или все (кроме помощников-подстрочников; оригиналы — по отдельному выбору)
    private var targets: [InstalledModule] {
        guard let m = module else { return [] }
        guard allMods else { return [m] }
        return store.bibles.filter { !$0.interlinear && (withOrig || !originalIds.contains($0.id)) }
    }

    private var hasOriginals: Bool {
        store.bibles.contains { originalIds.contains($0.id) }
    }

    private var canAll: Bool {
        store.bibles.filter { !$0.interlinear && !originalIds.contains($0.id) }.count > 1
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

    private func remember(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count > 1 else { return }
        history = ([t] + history.filter { $0 != t }).prefix(15).map { $0 }
        UserDefaults.standard.set(history, forKey: "searchHistory")
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
                    if canAll {
                        Toggle("Во всех модулях", isOn: $allMods)
                        if allMods && hasOriginals {
                            Toggle("И в оригиналах", isOn: $withOrig)
                        }
                    }
                }

                if let r = RefParser.parse(query) {
                    Section {
                        Button {
                            remember(query)
                            onOpen(r.book, r.chapter, r.verse)
                        } label: {
                            Label("Перейти: \(label(r.book, r.chapter, r.verse))", systemImage: "arrow.turn.down.right")
                        }
                    }
                }

                if let strong = SearchEngine.strongNumber(query), !store.dictionaries.isEmpty {
                    Section {
                        NavigationLink {
                            StrongList(keys: [strong]) { _ in }
                                .navigationTitle(strong)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("\(strong) — словарная статья", systemImage: "character.book.closed")
                        }
                    }
                }

                if module == nil {
                    Section {
                        Text("Сначала скачайте перевод Библии: «Ещё» → «Библиотека модулей».")
                            .foregroundStyle(.secondary)
                    }
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    if history.isEmpty {
                        Section {
                            Text("Слово, ссылка вроде Ин 3:16 или номер Стронга, например G26.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        historySection
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
                        ForEach(model.hits.prefix(shown), id: \.uid) { h in
                            Button {
                                remember(query)
                                onOpen(h.book, h.chapter, h.verse)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(label(h.book, h.chapter, h.verse))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tint)
                                        if targets.count > 1, let m = store.module(h.moduleId) {
                                            Text(m.name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(.fill.tertiary, in: Capsule())
                                        }
                                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Назад")
                }
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
            try? await Task.sleep(nanoseconds: 120_000_000)
            searching = true
        }
        .onChange(of: query) { _, _ in rerun() }
        .onChange(of: scope) { _, _ in rerun() }
        .onChange(of: whole) { _, _ in rerun() }
        .onChange(of: allMods) { _, _ in rerun() }
        .onChange(of: withOrig) { _, _ in rerun() }
        .onAppear {
            for m in targets { SearchIndex.warm(path: m.path) }
            rerun()
        }
        .onDisappear { remember(query) }
    }

    // MARK: - Недавние запросы

    private var historySection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                    ForEach(history, id: \.self) { h in
                        chip(h)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            Button("Очистить историю", role: .destructive) {
                history = []
                UserDefaults.standard.removeObject(forKey: "searchHistory")
            }
        } header: {
            Text("Недавние")
        }
    }

    private func chip(_ h: String) -> some View {
        Button {
            query = h
        } label: {
            Text(h).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .contextMenu {
            Button("Убрать из истории", role: .destructive) {
                history.removeAll { $0 == h }
                UserDefaults.standard.set(history, forKey: "searchHistory")
            }
        }
    }

    private func rerun() {
        shown = 50
        model.run(targets: targets.map { ($0.id, $0.path) }, query: query, whole: whole, books: booksFilter)
    }
}
