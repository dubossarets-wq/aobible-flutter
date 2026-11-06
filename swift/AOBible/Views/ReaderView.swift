import SwiftUI

/// Чтение: глава выбранного перевода. Переход — по названию вверху, перевод — слева, соседние главы — стрелками
/// или свайпом по тексту
struct ReaderView: View {
    @EnvironmentObject private var store: ModuleStore
    @AppStorage("readerModule") private var moduleId = ""
    @AppStorage("readerBook") private var bookId = "Gen"
    @AppStorage("readerChapter") private var chapter = 1
    @AppStorage("readerVerse") private var verse = 0
    @State private var showGoto = false
    @State private var showModules = false

    private var module: InstalledModule? {
        store.module(moduleId) ?? store.bibles.first
    }

    private var bookName: String {
        module?.books.first { $0.id == bookId }?.name ?? Books.info(bookId)?.name ?? bookId
    }

    var body: some View {
        NavigationStack {
            Group {
                if let m = module {
                    ChapterText(module: m, book: bookId, chapter: chapter, focus: verse, onSwipe: step)
                } else {
                    ContentUnavailableView {
                        Label("Нет переводов", systemImage: "book")
                    } description: {
                        Text("Скачайте перевод Библии, чтобы начать читать.")
                    } actions: {
                        Button("Выбрать перевод") { showModules = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(module?.name ?? "Перевод") { showModules = true }
                }
                ToolbarItem(placement: .principal) {
                    Button("\(bookName) \(chapter)") { showGoto = true }
                        .fontWeight(.semibold)
                        .disabled(module == nil)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(module == nil)
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(module == nil)
                }
            }
            .sheet(isPresented: $showGoto) {
                if let m = module {
                    GotoSheet(module: m) { b, c in
                        bookId = b
                        chapter = c
                        verse = 0
                    }
                }
            }
            .sheet(isPresented: $showModules) {
                NavigationStack {
                    ModulesList(selected: $moduleId)
                        .navigationTitle("Переводы")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Готово") { showModules = false }
                            }
                        }
                }
            }
            .onAppear {
                if moduleId.isEmpty, let m = store.bibles.first { moduleId = m.id }
            }
            .onChange(of: moduleId) { _, _ in
                // в другом переводе может не быть этой книги — тогда первая
                if let m = module, !m.books.contains(where: { $0.id == bookId }), let first = m.books.first {
                    bookId = first.id
                    chapter = 1
                }
            }
        }
    }

    /// Соседняя глава; за последней главой книги — следующая книга
    private func step(_ delta: Int) {
        guard let m = module, let i = m.books.firstIndex(where: { $0.id == bookId }) else { return }
        var c = chapter + delta
        var b = i
        if c < 1 {
            guard b > 0 else { return }
            b -= 1
            c = m.books[b].chapters
        } else if c > m.books[i].chapters {
            guard b < m.books.count - 1 else { return }
            b += 1
            c = 1
        }
        bookId = m.books[b].id
        chapter = max(1, c)
        verse = 0
    }
}

struct StrongRequest: Identifiable {
    let id = UUID()
    let key: String
}

enum StudyPanel: Identifiable {
    case commentary(Int)
    case xrefs(Int)

    var id: String {
        switch self {
        case .commentary(let v): return "c\(v)"
        case .xrefs(let v): return "x\(v)"
        }
    }
}

/// Текст главы: нажатие выбирает стих, внизу — панель действий (копировать, поделиться, подсветка, закладка, заметка)
struct ChapterText: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    let module: InstalledModule
    let book: String
    let chapter: Int
    let focus: Int
    let onSwipe: (Int) -> Void

    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("lineHeight") private var lineHeight = 1.45
    @AppStorage("showVerseNumbers") private var showNumbers = true
    @AppStorage("showStrongs") private var showStrongs = false
    @State private var selected: Set<Int> = []
    @State private var noteVerse: Int?
    @State private var noteText = ""
    @State private var strong: StrongRequest?
    @State private var panel: StudyPanel?

    private let colorNames = ["Жёлтый", "Зелёный", "Синий", "Розовый", "Оранжевый"]

    private var bookName: String {
        module.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
    }

    var body: some View {
        let verses = store.verses(module: module.id, book: book, chapter: chapter)
        let heads = store.headings(module: module.id, book: book, chapter: chapter)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.55) {
                    ForEach(verses) { v in
                        VStack(alignment: .leading, spacing: 6) {
                            if let h = heads[v.num] {
                                Text(h)
                                    .font(.headline)
                                    .padding(.top, 8)
                            }
                            Text(attributed(v))
                                .font(.system(size: fontSize, design: .serif))
                                .lineSpacing(fontSize * (lineHeight - 1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(background(v.num), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    if marks.isBookmarked(book, chapter, v.num) {
                                        Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(v.num) }
                        }
                        .id(v.num)
                    }
                    if verses.isEmpty {
                        Text("В этом переводе нет такой главы.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: focus) { _, _ in scroll(proxy) }
        }
        .id("\(module.id)|\(book)|\(chapter)")
        .simultaneousGesture(
            DragGesture(minimumDistance: 50).onEnded { g in
                if abs(g.translation.width) > abs(g.translation.height) * 2 {
                    onSwipe(g.translation.width < 0 ? 1 : -1)
                }
            }
        )
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                selectionBar(verses)
            }
        }
        .sheet(isPresented: Binding(get: { noteVerse != nil }, set: { if !$0 { noteVerse = nil } })) {
            noteEditor
        }
        .onChange(of: chapter) { _, _ in selected = [] }
        .environment(\.openURL, OpenURLAction { url in
            if let k = StrongLinks.key(from: url) {
                strong = StrongRequest(key: k)
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $strong) { r in
            StrongSheet(keys: [r.key])
        }
        .sheet(item: $panel) { p in
            switch p {
            case .commentary(let v):
                CommentarySheet(book: book, chapter: chapter, verse: v)
            case .xrefs(let v):
                XrefsSheet(module: module, book: book, chapter: chapter, verse: v)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard focus > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(focus, anchor: .top) }
        }
    }

    private func toggle(_ n: Int) {
        if selected.contains(n) { selected.remove(n) } else { selected.insert(n) }
    }

    private func background(_ n: Int) -> Color {
        if selected.contains(n) { return Color.accentColor.opacity(0.22) }
        if let c = marks.highlight(MarksStore.key(book, chapter, n)) {
            return highlightColors[min(c, highlightColors.count - 1)].opacity(0.35)
        }
        if n == focus { return Color.yellow.opacity(0.3) }
        return Color.clear
    }

    private func attributed(_ v: Verse) -> AttributedString {
        var out = AttributedString()
        if showNumbers {
            var n = AttributedString("\(v.num) ")
            n.font = .system(size: fontSize * 0.62, weight: .semibold)
            n.baselineOffset = fontSize * 0.32
            n.foregroundColor = Color.secondary
            out += n
        }
        for t in Markup.parse(v.text) {
            var s = AttributedString(t.text)
            if t.italic {
                s.font = .system(size: fontSize, design: .serif).italic()
            }
            out += s
            if showStrongs && !t.strongs.isEmpty {
                // номера Стронга — ссылки: нажатие открывает словарную статью
                for key in t.strongs {
                    var n = AttributedString(" " + key)
                    n.font = .system(size: fontSize * 0.55)
                    n.baselineOffset = fontSize * 0.3
                    n.foregroundColor = Color.accentColor
                    n.link = URL(string: "aobstrong:" + key)
                    out += n
                }
            }
        }
        return out
    }

    // MARK: - Панель действий

    private func keys() -> [String] {
        selected.sorted().map { MarksStore.key(book, chapter, $0) }
    }

    private func rangeText() -> String {
        let nums = selected.sorted()
        guard let first = nums.first, let last = nums.last else { return "" }
        if nums.count == 1 { return "\(first)" }
        if last - first + 1 == nums.count { return "\(first)-\(last)" }
        return nums.map(String.init).joined(separator: ",")
    }

    private func quote(_ verses: [Verse]) -> String {
        let text = verses.filter { selected.contains($0.num) }.map { Markup.plain($0.text) }.joined(separator: " ")
        return "\(text)\n— \(bookName) \(chapter):\(rangeText()) (\(module.name))"
    }

    private func selectionBar(_ verses: [Verse]) -> some View {
        let first = selected.sorted().first ?? 1
        let bookmarked = marks.isBookmarked(book, chapter, first)
        return HStack(spacing: 18) {
            Button {
                UIPasteboard.general.string = quote(verses)
                selected = []
            } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("Копировать")
            ShareLink(item: quote(verses)) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Поделиться")
            Menu {
                ForEach(0..<highlightColors.count, id: \.self) { i in
                    Button(colorNames[i]) {
                        marks.setHighlight(keys: keys(), color: i)
                        selected = []
                    }
                }
                Button("Убрать подсветку", role: .destructive) {
                    marks.setHighlight(keys: keys(), color: nil)
                    selected = []
                }
            } label: { Image(systemName: "highlighter") }
                .accessibilityLabel("Подсветка")
            Button {
                for n in selected.sorted() where marks.isBookmarked(book, chapter, n) == bookmarked {
                    marks.toggleBookmark(book, chapter, n)
                }
                selected = []
            } label: { Image(systemName: bookmarked ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel("Закладка")
            Button {
                noteText = marks.note(MarksStore.key(book, chapter, first)) ?? ""
                noteVerse = first
            } label: { Image(systemName: "note.text") }
                .accessibilityLabel("Заметка")
            Button { panel = .commentary(first) } label: { Image(systemName: "text.book.closed") }
                .accessibilityLabel("Толкования")
            Button { panel = .xrefs(first) } label: { Image(systemName: "arrow.triangle.branch") }
                .accessibilityLabel("Параллельные места")
            Button { selected = [] } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Снять выделение")
        }
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 8)
    }

    private var noteEditor: some View {
        NavigationStack {
            TextEditor(text: $noteText)
                .padding(12)
                .navigationTitle("Заметка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { noteVerse = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            if let v = noteVerse { marks.setNote(MarksStore.key(book, chapter, v), noteText) }
                            noteVerse = nil
                            selected = []
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

private struct BookSection: Identifiable {
    let title: String
    let books: [ModuleBook]
    var id: String { title }
}

/// Переход: книги по разделам → номера глав
struct GotoSheet: View {
    let module: InstalledModule
    let onPick: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sections: [BookSection] {
        let ot = module.books.filter { Books.info($0.id)?.t == "OT" }
        let nt = module.books.filter { Books.info($0.id)?.t == "NT" }
        let rest = module.books.filter { Books.info($0.id)?.t != "OT" && Books.info($0.id)?.t != "NT" }
        var out: [BookSection] = []
        if !ot.isEmpty { out.append(BookSection(title: "Ветхий Завет", books: ot)) }
        if !nt.isEmpty { out.append(BookSection(title: "Новый Завет", books: nt)) }
        if !rest.isEmpty { out.append(BookSection(title: "Другие книги", books: rest)) }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { sec in
                    Section(sec.title) {
                        ForEach(sec.books) { b in
                            NavigationLink {
                                ChapterGrid(book: b) { c in
                                    onPick(b.id, c)
                                    dismiss()
                                }
                            } label: {
                                Text(b.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Перейти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

struct ChapterGrid: View {
    let book: ModuleBook
    let onPick: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                ForEach(1...max(1, book.chapters), id: \.self) { n in
                    Button { onPick(n) } label: {
                        Text("\(n)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
            .padding(16)
        }
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
