import SwiftUI

/// Часть стиха: нажмите первое и последнее слово — выделится отрезок; его можно скопировать, отправить,
/// сделать любимым или добавить в проповедь
struct PartSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @EnvironmentObject private var sermons: SermonStore
    @Environment(\.dismiss) private var dismiss
    let module: InstalledModule
    let book: String
    let chapter: Int
    let verse: Int
    @State private var a: Int?
    @State private var b: Int?
    @State private var message: String?

    private var words: [String] {
        let t = store.verseText(module: module.id, book: book, chapter: chapter, verse: verse) ?? ""
        return t.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    private var range: ClosedRange<Int>? {
        guard let a else { return nil }
        let e = b ?? a
        return min(a, e)...max(a, e)
    }

    private var partText: String {
        guard let r = range else { return "" }
        let w = words
        guard r.upperBound < w.count else { return "" }
        return w[r].joined(separator: " ")
    }

    private var ref: String {
        let name = module.books.first { $0.id == book }?.name ?? Books.info(book)?.name ?? book
        return "\(name) \(chapter):\(verse) (часть)"
    }

    private var quote: String {
        "\(partText)\n— \(ref) (\(module.name))"
    }

    private func tap(_ i: Int) {
        if a == nil || b != nil {
            a = i
            b = nil
        } else {
            b = i
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Нажмите первое слово части, затем последнее.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(words.indices, id: \.self) { i in
                            let on = range?.contains(i) ?? false
                            Button { tap(i) } label: {
                                Text(words[i])
                                    .font(.system(size: 19))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(on ? Color.accentColor.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if range != nil, !partText.isEmpty {
                        Divider()
                        Text("«\(partText)»").font(.system(size: 19, design: .serif))
                        HStack {
                            Button {
                                UIPasteboard.general.string = quote
                                message = "Скопировано"
                            } label: { Label("Копировать", systemImage: "doc.on.doc") }
                            ShareLink(item: quote) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                            Button {
                                if let r = range {
                                    marks.toggleFavorite(book, chapter, verse, text: partText, part: Part(from: r.lowerBound, to: r.upperBound))
                                    message = "Любимые обновлены"
                                }
                            } label: { Label("Любимое", systemImage: "heart") }
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.iconOnly)
                        Menu {
                            ForEach(sermons.sermons.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(10)) { s in
                                Button(s.title.isEmpty ? "Без названия" : s.title) { add(s.id) }
                            }
                            Button("Новая проповедь") { add(sermons.create("Новая проповедь").id) }
                        } label: { Label("В проповедь", systemImage: "scroll") }
                            .buttonStyle(.bordered)
                    }
                    if let m = message {
                        Text(m).font(.footnote).foregroundStyle(.green)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Часть стиха")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ id: String) {
        sermons.addVerses(to: id, items: [VerseItem(book: book, chapter: chapter, verse: verse, text: partText, moduleId: module.id, part: true)], moduleId: module.id)
        message = "Добавлено в проповедь"
    }
}
