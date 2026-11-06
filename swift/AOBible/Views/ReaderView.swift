import SwiftUI

/// Чтение: глава выбранного перевода. Переход — по названию вверху, перевод — слева, соседние главы — стрелками
/// или свайпом по тексту
struct ReaderView: View {
    @EnvironmentObject private var store: ModuleStore
    @AppStorage("readerModule") private var moduleId = ""
    @AppStorage("readerBook") private var bookId = "Gen"
    @AppStorage("readerChapter") private var chapter = 1
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
                    ChapterText(module: m, book: bookId, chapter: chapter, onSwipe: step)
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
    }
}

/// Текст главы
struct ChapterText: View {
    @EnvironmentObject private var store: ModuleStore
    let module: InstalledModule
    let book: String
    let chapter: Int
    let onSwipe: (Int) -> Void

    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("lineHeight") private var lineHeight = 1.45
    @AppStorage("showVerseNumbers") private var showNumbers = true

    var body: some View {
        let verses = store.verses(module: module.id, book: book, chapter: chapter)
        let heads = store.headings(module: module.id, book: book, chapter: chapter)
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
                    }
                }
                if verses.isEmpty {
                    Text("В этом переводе нет такой главы.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .id("\(module.id)|\(book)|\(chapter)")
        .simultaneousGesture(
            DragGesture(minimumDistance: 50).onEnded { g in
                if abs(g.translation.width) > abs(g.translation.height) * 2 {
                    onSwipe(g.translation.width < 0 ? 1 : -1)
                }
            }
        )
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
        }
        return out
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
