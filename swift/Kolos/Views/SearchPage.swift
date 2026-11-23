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
    /// Ничего не нашлось — запросы с исправленными словами («Возможно, вы искали»)
    @Published var suggestions: [QuerySuggestion] = []
    private var generation = 0

    /// Поиск без пауз: на каждое изменение запроса — новый проход по готовому индексу (миллисекунды);
    /// устаревший результат отбрасывается. targets — переводы, в которых ищем (id, файл)
    func run(targets: [(String, String)], query: String, whole: Bool, ordered: Bool = false, books: Set<String>?) {
        generation += 1
        let g = generation
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !targets.isEmpty, q.count >= 2 else {
            hits = []
            suggestions = []
            running = false
            searched = ""
            return
        }
        running = hits.isEmpty
        Task.detached(priority: .userInitiated) { [weak self] in
            var all: [SearchHit] = []
            var indexes: [SearchIndex] = []
            for (id, path) in targets {
                if let idx = SearchIndex.index(path: path) {
                    indexes.append(idx)
                    all.append(contentsOf: SearchEngine.run(index: idx, query: q, wholeWord: whole, ordered: ordered, books: books).map { $0.tagged(id) })
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
                if !result.isEmpty { self.suggestions = [] }
            }
            // ничего не нашлось — ищем исправления опечаток (словарь слов перевода строится один раз)
            guard result.isEmpty else { return }
            let near = SearchEngine.suggestions(indexes: indexes, query: q, wholeWord: whole, ordered: ordered, books: books)
            await MainActor.run {
                guard let self, g == self.generation else { return }
                self.suggestions = near
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
    /// слова в заданном порядке (иначе — в любом порядке и с пропусками)
    @AppStorage("searchOrdered") private var ordered = false
    @AppStorage("searchAllModules") private var allMods = false
    @AppStorage("searchOriginals") private var withOrig = false
    @State private var scope: SearchScope = .all
    // поле поиска активно с самого начала: клавиатура выезжает вместе со страницей, без паузы
    @State private var searching = true
    @State private var shown = 50
    /// Недавние: сразу видно 20, «Раскрыть все» — до 50
    @State private var historyOpen = false
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
    @StateObject private var model = SearchModel()
    /// Смахивание вправо от левого края: страница едет за пальцем и закрывается (страница открыта поверх
    /// всего экрана, системного «назад» свайпом у неё нет)
    @State private var dragX: CGFloat = 0
    @State private var pageW: CGFloat = 400

    private let originalIds: Set<String> = ["oshb", "byz-rp2018"]

    private var module: InstalledModule? {
        store.module(moduleId) ?? store.bibles.first
    }

    private var bookShortName: String { Books.info(currentBook)?.short ?? "Книга" }

    /// Полное название книги в открытом переводе
    private var bookFullName: String {
        module?.books.first { $0.id == currentBook }?.name ?? Books.info(currentBook)?.name ?? bookShortName
    }

    private func scopeSwitcher(book: String) -> some View {
        CapsuleSwitcher(
            options: [
                (SearchScope.all, String(localized: "Вся Библия")),
                (SearchScope.ot, String(localized: "ВЗ")),
                (SearchScope.nt, String(localized: "НЗ")),
                (SearchScope.book, book),
            ],
            selection: $scope
        )
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
        history = ([t] + history.filter { $0 != t }).prefix(50).map { $0 }
        UserDefaults.standard.set(history, forKey: "searchHistory")
    }

    var body: some View {
        NavigationStack {
            List {
                // где искать — переключатель прямо на сером фоне, вне белого блока с настройками
                Section {
                    // название книги — целиком, если помещается («Сирах», «Руфь»); нет — сокращённое («1Фес»)
                    ViewThatFits(in: .horizontal) {
                        scopeSwitcher(book: bookFullName)
                        scopeSwitcher(book: bookShortName)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    Toggle("Только целые слова", isOn: $whole)
                    Toggle("Слова в заданном порядке", isOn: $ordered)
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
                    // слово с опечаткой: предлагаем близкие слова перевода, у которых есть результаты
                    if model.hits.isEmpty && !model.running && !model.suggestions.isEmpty {
                        Section("Возможно, вы искали") {
                            ForEach(model.suggestions) { s in
                                Button {
                                    query = s.query
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 30, height: 30)
                                            .background(Color.accentColor.opacity(0.13), in: Circle())
                                        Text(s.query).font(.body.weight(.medium)).foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(s.count)")
                                            .font(.footnote.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            .background(Color.primary.opacity(0.07), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(model.hits.prefix(shown), id: \.uid) { h in
                            Button {
                                remember(query)
                                // в открытом стихе найденные слова на пару секунд подсветятся
                                panes.pendingWords = (query, whole)
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
                                    // найденное — на скруглённых плашках
                                    PlateLabel(text: SearchEngine.highlightedNS(h.text, query: model.searched, wholeWord: whole))
                                }
                                // нажатие работает на всей строке, в том числе по тексту стиха, а не только по ссылке
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
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
            // только на первой странице: на открытых из поиска страницах работает системный свайп «назад»
            .overlay(alignment: .leading) { edgeSwipe }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, isPresented: $searching, prompt: "Слово, Ин 3:16 или G26")
            .onSubmit(of: .search) {
                if let r = RefParser.parse(query) {
                    remember(query)
                    onOpen(r.book, r.chapter, r.verse)
                } else {
                    remember(query)
                    rerun()
                }
            }
            .submitLabel(.search)
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .offset(x: dragX)
        .shadow(color: .black.opacity(dragX > 0 ? 0.2 : 0), radius: 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageW = $0 }
        .task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            searching = true
        }
        .onChange(of: query) { _, _ in rerun() }
        .onChange(of: scope) { _, _ in rerun() }
        .onChange(of: whole) { _, _ in rerun() }
        .onChange(of: ordered) { _, _ in rerun() }
        .onChange(of: allMods) { _, _ in rerun() }
        .onChange(of: withOrig) { _, _ in rerun() }
        .onAppear {
            for m in targets { SearchIndex.warm(path: m.path) }
            rerun()
        }
        .onDisappear { remember(query) }
    }

    /// Полоска у левого края: потянули вправо больше трети экрана (или быстро) — страница уезжает и закрывается
    private var edgeSwipe: some View {
        Color.clear
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { g in dragX = max(0, g.translation.width) }
                    .onEnded { g in
                        if g.translation.width > pageW * 0.3 || g.predictedEndTranslation.width > pageW * 0.6 {
                            withAnimation(.easeOut(duration: 0.2)) { dragX = pageW }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { onClose() }
                            }
                        } else {
                            withAnimation(.spring(duration: 0.3)) { dragX = 0 }
                        }
                    }
            )
    }

    // MARK: - Недавние запросы

    private var historySection: some View {
        Section {
            let shown = Array(history.prefix(historyOpen ? 50 : 20))
            VStack(alignment: .leading, spacing: 10) {
                // плашки переносятся на следующую строку и не выходят за край экрана
                FlowLayout(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(.secondary).frame(height: 32)
                    ForEach(shown, id: \.self) { h in
                        chip(h)
                    }
                }
                if history.count > 20 {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { historyOpen.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(historyOpen ? "Свернуть" : "Раскрыть все")
                            if !historyOpen { Text(verbatim: "· \(min(50, history.count))").foregroundStyle(.secondary) }
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).rotationEffect(.degrees(historyOpen ? 180 : 0))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            Button("Очистить историю", role: .destructive) {
                history = []
                historyOpen = false
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
            Text(h).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: 260)
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
        model.run(targets: targets.map { ($0.id, $0.path) }, query: query, whole: whole, ordered: ordered, books: booksFilter)
    }
}
