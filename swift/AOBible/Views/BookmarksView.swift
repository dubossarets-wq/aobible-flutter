import SwiftUI

/// «Закладки и заметки»: Закладки · Любимые стихи · Заметки · Выделения · Подборки · История (у каждой число).
/// Удаление — смахиванием влево, сразу, с «Отменить» внизу
struct BookmarksView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.openVerse) private var openVerse

    private enum Tab: String, CaseIterable, Identifiable {
        case bookmarks = "Закладки"
        case favorites = "Любимые стихи"
        case notes = "Заметки"
        case highlights = "Выделения"
        case collections = "Подборки"
        case history = "История"
        var id: String { rawValue }
    }

    @State private var tab = Tab.bookmarks
    @State private var noteQuery = ""
    @State private var colorFilter = "all"
    @State private var openCollection: String?
    @State private var undo: (text: String, run: () -> Void)?

    // MARK: - Данные

    private var module: InstalledModule? {
        store.module(panes.primaryModule) ?? store.bibles.first
    }

    private func parts(_ key: String) -> (String, Int, Int)? {
        let p = key.split(separator: ".")
        guard p.count == 3, let c = Int(p[1]), let v = Int(p[2]) else { return nil }
        return (String(p[0]), c, v)
    }

    private func bibleOrder(_ a: String, _ b: String) -> Bool {
        guard let x = parts(a), let y = parts(b) else { return a < b }
        let oa = Books.all.firstIndex { $0.id == x.0 } ?? 999
        let ob = Books.all.firstIndex { $0.id == y.0 } ?? 999
        if oa != ob { return oa < ob }
        if x.1 != y.1 { return x.1 < y.1 }
        return x.2 < y.2
    }

    private func name(_ book: String, _ chapter: Int, _ verse: Int) -> String {
        let n = module?.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
        return "\(n) \(chapter):\(verse)"
    }

    private func count(_ t: Tab) -> Int {
        switch t {
        case .bookmarks: return marks.data.bookmarks.count
        case .favorites: return marks.data.favorites.count
        case .notes: return marks.data.notes.count
        case .highlights: return marks.data.highlights.count
        case .collections: return marks.data.collections.count
        case .history: return panes.panes.first?.history.count ?? 0
        }
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm"
        return f
    }()

    private func date(_ ms: Double?) -> String {
        guard let ms, ms > 0 else { return "" }
        return Self.dateFormat.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    private func fold(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    // MARK: - Вид

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabs
                List {
                    switch tab {
                    case .bookmarks: bookmarksList
                    case .favorites: favoritesList
                    case .notes: notesList
                    case .highlights: highlightsList
                    case .collections: collectionsList
                    case .history: historyList
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Закладки и заметки")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if let u = undo {
                    HStack(spacing: 14) {
                        Text(u.text).font(.subheadline)
                        Button("Отменить") {
                            u.run()
                            undo = nil
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: undo?.text)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        HStack(spacing: 5) {
                            Text(LocalizedStringKey(t.rawValue))
                            Text("\(count(t))").foregroundStyle(tab == t ? .white.opacity(0.8) : .secondary)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(tab == t ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
                        .foregroundStyle(tab == t ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func empty(_ icon: String, _ title: LocalizedStringKey, _ hint: LocalizedStringKey) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(hint)
            }
        }
    }

    private func row(title: String, icon: String? = nil, tint: Color = .accentColor, meta: String = "", sub: String? = nil, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).font(.footnote).foregroundStyle(tint) }
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
                    if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
                }
                if let sub, !sub.isEmpty {
                    Text(sub).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func offer(_ text: String, _ run: @escaping () -> Void) {
        undo = (text, run)
        let t = text
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if undo?.text == t { undo = nil }
        }
    }

    // MARK: - Закладки

    @ViewBuilder private var bookmarksList: some View {
        if let p = panes.panes.first {
            Section {
                Button {
                    openVerse(p.book, p.chapter, max(p.verse, 1))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill").foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Продолжить чтение").font(.caption).foregroundStyle(.secondary)
                            Text(name(p.book, p.chapter, max(p.verse, 1))).font(.headline).foregroundStyle(.primary)
                            if let m = module, let t = store.verseText(module: m.id, book: p.book, chapter: p.chapter, verse: max(p.verse, 1)) {
                                Text(t).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if marks.data.bookmarks.isEmpty {
            empty("bookmark", "Закладок пока нет", "Зажмите стих и нажмите «Закладка».")
        } else {
            Section {
                ForEach(marks.data.bookmarks, id: \.at) { b in
                    row(title: name(b.book, b.chapter, b.verse), icon: "bookmark.fill", meta: date(b.at), sub: b.text) {
                        openVerse(b.book, b.chapter, b.verse)
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) {
                            let i = marks.data.bookmarks.firstIndex { $0.at == b.at } ?? 0
                            marks.removeBookmark(b)
                            offer(String(localized: "Закладка удалена")) { marks.restoreBookmark(b, at: i) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Любимые

    @ViewBuilder private var favoritesList: some View {
        if marks.data.favorites.isEmpty {
            empty("heart", "Любимых стихов пока нет", "Дважды нажмите на стих — он станет любимым.")
        } else {
            Section {
                ForEach(marks.data.favorites, id: \.at) { f in
                    row(title: name(f.book, f.chapter, f.verse), icon: "heart.fill", tint: Color(hex: 0xd9475e), sub: f.text) {
                        openVerse(f.book, f.chapter, f.verse)
                    }
                    .swipeActions {
                        Button("Убрать", role: .destructive) {
                            let i = marks.data.favorites.firstIndex { $0.at == f.at } ?? 0
                            marks.removeFavorite(f.id)
                            offer(String(localized: "Убрано из любимых стихов")) { marks.restoreFavorite(f, at: i) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Заметки

    private struct NoteRow: Identifiable {
        let key: String
        let entry: NoteEntry
        var id: String { key }
    }

    private var sortedNotes: [NoteRow] {
        marks.data.notes.compactMap { k, e -> NoteRow? in
            parts(k) == nil ? nil : NoteRow(key: k, entry: e)
        }.sorted { ($0.entry.updated ?? $0.entry.at ?? 0) > ($1.entry.updated ?? $1.entry.at ?? 0) }
    }

    @ViewBuilder private var notesList: some View {
        let all = sortedNotes
        if all.isEmpty {
            empty("note.text", "Заметок пока нет", "Зажмите стих и нажмите «Заметка».")
        } else {
            if all.count > 3 {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск по заметкам", text: $noteQuery)
                            .autocorrectionDisabled()
                    }
                }
            }
            let q = fold(noteQuery.trimmingCharacters(in: .whitespaces))
            let list = q.isEmpty ? all : all.filter { n in
                guard let (b, c, v) = parts(n.key) else { return false }
                return fold(n.entry.text + " " + (n.entry.label ?? "") + " " + name(b, c, v)).contains(q)
            }
            Section {
                ForEach(list) { n in
                    if let (b, c, v) = parts(n.key) {
                        row(title: n.entry.label?.isEmpty == false ? n.entry.label! : name(b, c, v), icon: "note.text",
                            meta: date(n.entry.updated ?? n.entry.at), sub: n.entry.text) {
                            openVerse(b, c, v)
                        }
                        .swipeActions {
                            Button("Удалить", role: .destructive) {
                                if let e = marks.removeNote(n.key) {
                                    offer(String(localized: "Заметка удалена")) { marks.restoreNote(n.key, e) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Выделения

    @ViewBuilder private var highlightsList: some View {
        if marks.data.highlights.isEmpty {
            empty("highlighter", "Выделений пока нет", "Зажмите стих и нажмите маркер.")
        } else {
            let used = hlColors.filter { c in marks.data.highlights.values.contains(c.id) }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Все", count: marks.data.highlights.count, color: nil, on: colorFilter == "all") { colorFilter = "all" }
                        ForEach(used) { c in
                            chip(marks.colorName(c), count: marks.data.highlights.values.filter { $0 == c.id }.count, color: c.color, on: colorFilter == c.id) {
                                colorFilter = c.id
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            let keys = marks.data.highlights.filter { colorFilter == "all" || $0.value == colorFilter }.map { $0.key }.sorted(by: bibleOrder)
            Section {
                ForEach(keys.indices, id: \.self) { i in
                    let k = keys[i]
                    if let (b, c, v) = parts(k) {
                        let col = hlColor(marks.data.highlights[k])
                        Button {
                            openVerse(b, c, v)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle().fill(col?.color ?? .secondary).frame(width: 12, height: 12)
                                    Text(name(b, c, v)).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                                }
                                if i < 200, let m = module, let t = store.verseText(module: m.id, book: b, chapter: c, verse: v) {
                                    Text(t).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Убрать", role: .destructive) {
                                let old = marks.data.highlights[k]
                                marks.setHighlight(keys: [k], color: nil)
                                offer(String(localized: "Выделение убрано")) { marks.setHighlight(keys: [k], color: old) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, count: Int, color: Color?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(LocalizedStringKey(title))
                Text("\(count)").foregroundStyle(on ? .white.opacity(0.8) : .secondary)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Подборки

    @ViewBuilder private var collectionsList: some View {
        if let id = openCollection, let c = marks.data.collections.first(where: { $0.id == id }) {
            Section {
                Button {
                    openCollection = nil
                } label: {
                    Label("Все подборки", systemImage: "chevron.left").font(.subheadline)
                }
            }
            Section("\(c.name) · \(c.items.count)") {
                ForEach(c.items.sorted { bibleOrder($0.id, $1.id) }, id: \.id) { it in
                    row(title: name(it.book, it.chapter, it.verse), sub: it.text) {
                        openVerse(it.book, it.chapter, it.verse)
                    }
                    .swipeActions {
                        Button("Убрать", role: .destructive) {
                            let i = c.items.firstIndex { $0.id == it.id } ?? 0
                            marks.removeFromCollection(c.id, item: it.id)
                            offer(String(localized: "Убрано из подборки")) { marks.restoreCollectionItem(c.id, it, at: i) }
                        }
                    }
                }
            }
        } else if marks.data.collections.isEmpty {
            empty("folder", "Подборок пока нет", "Зажмите стих → «⋯» → «В подборку…».")
        } else {
            Section {
                ForEach(marks.data.collections) { c in
                    Button {
                        openCollection = c.id
                    } label: {
                        HStack {
                            Label(c.name, systemImage: "folder").foregroundStyle(.primary)
                            Spacer()
                            Text("\(c.items.count) ст.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) {
                            let i = marks.data.collections.firstIndex { $0.id == c.id } ?? 0
                            marks.removeCollection(c.id)
                            offer(String(localized: "Подборка «\(c.name)» удалена")) { marks.restoreCollection(c, at: i) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - История

    @ViewBuilder private var historyList: some View {
        if let p = panes.panes.first {
            Section {
                // новые сверху; текущее место отмечено
                ForEach(Array(p.history.indices.reversed()), id: \.self) { i in
                    let h = p.history[i]
                    let now = i == p.hIndex
                    Button {
                        panes.goHistory(p.id, i)
                        openVerse(h.book, h.chapter, h.verse)
                    } label: {
                        HStack {
                            Label(name(h.book, h.chapter, max(h.verse, 1)), systemImage: "clock")
                                .fontWeight(now ? .semibold : .regular)
                                .foregroundStyle(now ? Color.accentColor : .primary)
                            Spacer()
                            if now { Text("сейчас").font(.subheadline).foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            }
        }
    }
}
