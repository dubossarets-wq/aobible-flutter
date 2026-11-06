import SwiftUI

/// Закладки, заметки, подсветка и любимые — списки мест; нажатие открывает место в чтении
struct BookmarksView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var panes: PanesStore
    @Environment(\.openVerse) private var openVerse
    @State private var kind = 0

    private struct Place: Identifiable {
        let id: String
        let book: String
        let chapter: Int
        let verse: Int
        var text: String? = nil
        var note: String? = nil
        var color: String? = nil
    }

    private var module: InstalledModule? {
        store.module(panes.primaryModule) ?? store.bibles.first
    }

    private func parts(_ key: String) -> (String, Int, Int)? {
        let p = key.split(separator: ".")
        guard p.count == 3, let c = Int(p[1]), let v = Int(p[2]) else { return nil }
        return (String(p[0]), c, v)
    }

    private func order(_ a: Place, _ b: Place) -> Bool {
        let oa = Books.all.firstIndex { $0.id == a.book } ?? 999
        let ob = Books.all.firstIndex { $0.id == b.book } ?? 999
        if oa != ob { return oa < ob }
        if a.chapter != b.chapter { return a.chapter < b.chapter }
        return a.verse < b.verse
    }

    private var places: [Place] {
        switch kind {
        case 0:
            return marks.data.bookmarks.map { Place(id: $0.id, book: $0.book, chapter: $0.chapter, verse: $0.verse, text: $0.text) }
        case 1:
            return marks.data.notes.compactMap { k, e in
                guard let (b, c, v) = parts(k) else { return nil }
                return Place(id: k, book: b, chapter: c, verse: v, note: e.text)
            }.sorted(by: order)
        case 3:
            return marks.data.favorites.map { Place(id: $0.id, book: $0.book, chapter: $0.chapter, verse: $0.verse, text: $0.text) }
        default:
            return marks.data.highlights.compactMap { k, color in
                guard let (b, c, v) = parts(k) else { return nil }
                return Place(id: k, book: b, chapter: c, verse: v, color: color)
            }.sorted(by: order)
        }
    }

    private func label(_ p: Place) -> String {
        let name = module?.books.first { $0.id == p.book }?.name ?? Books.info(p.book)?.name ?? p.book
        return "\(name) \(p.chapter):\(p.verse)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Что показывать", selection: $kind) {
                        Text("Закладки").tag(0)
                        Text("Заметки").tag(1)
                        Text("Подсветка").tag(2)
                        Text("Любимые").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                let list = places
                if list.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(kind == 0 ? "Нет закладок" : (kind == 1 ? "Нет заметок" : (kind == 3 ? "Нет любимых стихов" : "Нет подсветки")), systemImage: kind == 0 ? "bookmark" : (kind == 1 ? "note.text" : (kind == 3 ? "heart" : "highlighter")))
                        } description: {
                            Text("Зажмите стих в чтении, чтобы выбрать его, и воспользуйтесь панелью внизу. Двойное касание делает стих любимым.")
                        }
                    }
                } else {
                    Section {
                        ForEach(list) { p in
                            Button {
                                openVerse(p.book, p.chapter, p.verse)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        if let c = hlColor(p.color) {
                                            Circle().fill(c.color).frame(width: 12, height: 12)
                                        }
                                        Text(label(p)).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                                    }
                                    if let n = p.note {
                                        Text(n).foregroundStyle(.primary)
                                    }
                                    if let t = p.text, !t.isEmpty {
                                        Text(t).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                    } else if let m = module, let t = store.verseText(module: m.id, book: p.book, chapter: p.chapter, verse: p.verse) {
                                        Text(t).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Удалить", role: .destructive) { remove(p) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Закладки")
        }
    }

    private func remove(_ p: Place) {
        switch kind {
        case 0:
            if let b = marks.data.bookmarks.first(where: { $0.id == p.id }) { marks.removeBookmark(b) }
        case 1: marks.setNote(p.id, "")
        case 3: marks.removeFavorite(p.id)
        default: marks.setHighlight(keys: [p.id], color: nil)
        }
    }
}
