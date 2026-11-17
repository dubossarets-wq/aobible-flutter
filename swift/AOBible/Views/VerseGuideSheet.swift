import SwiftUI

/// «Всё о стихе»: на одном экране — ваши пометки, слова оригинала, комментарии, параллельные места, места на карте
/// (как «Всё о стихе» во Flutter-версии и в вебе)
struct VerseGuideSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @Environment(\.dismiss) private var dismiss
    let module: InstalledModule
    let book: String
    let chapter: Int
    let verse: Int
    /// открыть параллельное место рядом (во второй панели)
    let onOpen: (String, Int, Int) -> Void

    private struct GuideWord: Identifiable {
        let id: String
        let token: Token
        let num: String
        let lemma: String?
        let xlit: String?
        let def: String?
    }

    private struct GuideComm: Identifiable {
        let id: String
        let module: InstalledModule
        let text: String
    }

    private struct GuideRef: Identifiable {
        let id: Int
        let ref: OsisRef
        let text: String
    }

    @State private var loaded = false
    @State private var text = ""
    @State private var taggedName = ""
    @State private var words: [GuideWord] = []
    @State private var comms: [GuideComm] = []
    @State private var refs: [GuideRef] = []
    @State private var places: [BiblePlace] = []
    @State private var word: WordRequest?
    @State private var showComm = false
    @State private var place: BiblePlace?

    private var key: String { MarksStore.key(book, chapter, verse) }

    private var title: String {
        let short = Books.info(book)?.short ?? book
        return "\(short) \(chapter):\(verse)"
    }

    private func label(_ r: OsisRef) -> String {
        let short = module.books.first { $0.id == r.book }?.short ?? Books.info(r.book)?.short ?? r.book
        var s = "\(short) \(r.chapter):\(r.verse)"
        if let ev = r.endVerse {
            if let ec = r.endChapter, ec != r.chapter {
                s += "–\(ec):\(ev)"
            } else if ev != r.verse {
                s += "–\(ev)"
            }
        }
        return s
    }

    private func cut(_ s: String) -> String {
        s.count > 220 ? String(s.prefix(220)) + "…" : s
    }

    /// Слова оригинала берём из русского перевода со Стронгом (RST+): по одному на номер
    private func load() {
        text = store.verseText(module: module.id, book: book, chapter: chapter, verse: verse) ?? ""
        let tagged = store.bibles.first { $0.strongs && $0.language == "ru" }
        taggedName = tagged?.name ?? ""
        var out: [GuideWord] = []
        if let t = tagged, let raw = store.verseRaw(module: t.id, book: book, chapter: chapter, verse: verse) {
            for tk in Markup.parse(raw) where !tk.strongs.isEmpty {
                let num = tk.strongs[0]
                if out.contains(where: { $0.num == num }) { continue }
                let res = Lexicon.lookupWord(store: store, text: tk.text, strongs: tk.strongs, morph: tk.morph, book: book)
                let lex = res.results.first { $0.module.id.hasPrefix("strongs-") } ?? res.results.first
                let e = lex?.found.first?.entry
                var def = e?["definition"] as? String
                if def == nil, let rend = e?["renderings"] as? [Any], let first = rend.first as? [Any], let s = first.first {
                    def = "\(s)"
                }
                out.append(GuideWord(id: num, token: tk, num: num, lemma: e?["lemma"] as? String, xlit: e?["xlit"] as? String, def: def))
            }
        }
        words = out
        var grouped: [GuideComm] = []
        var seen = Set<String>()
        for it in store.commentary(book: book, chapter: chapter, verse: verse) where seen.insert(it.module.id).inserted {
            grouped.append(GuideComm(id: it.module.id, module: it.module, text: cut(it.text)))
        }
        comms = grouped
        refs = store.xrefs(module: module.id, book: book, chapter: chapter, verse: verse).prefix(8).enumerated().map {
            GuideRef(id: $0.offset, ref: $0.element, text: store.refText(module: module.id, $0.element))
        }
        var pseen = Set<String>()
        places = store.placesIn(book: book, chapter: chapter, verse: verse).filter { pseen.insert($0.id).inserted }
        loaded = true
    }

    private var collectionNames: [String] {
        marks.data.collections.filter { c in
            c.items.contains { $0.book == book && $0.chapter == chapter && $0.verse == verse }
        }.map { $0.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if !loaded {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    if !text.isEmpty {
                        Section {
                            Text(text).font(.body)
                        }
                    }
                    notesSection
                    if !words.isEmpty {
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                                ForEach(words) { w in wordCard(w) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        } header: {
                            Label("Слова оригинала · по \(taggedName)", systemImage: "character.book.closed")
                        }
                    }
                    if !comms.isEmpty {
                        Section {
                            ForEach(comms) { c in
                                Button { showComm = true } label: {
                                    (Text(c.module.name).fontWeight(.bold) + Text(" " + c.text))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        } header: {
                            Label("Комментарии", systemImage: "text.bubble")
                        }
                    }
                    if !refs.isEmpty {
                        Section {
                            ForEach(refs) { r in
                                Button {
                                    dismiss()
                                    onOpen(r.ref.book, r.ref.chapter, r.ref.verse)
                                } label: {
                                    (Text(label(r.ref)).fontWeight(.bold) + Text(" " + r.text))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        } header: {
                            Label("Параллельные места", systemImage: "arrow.triangle.branch")
                        }
                    }
                    if !places.isEmpty {
                        Section {
                            ForEach(places) { p in
                                Button { place = p } label: {
                                    Label(p.name, systemImage: "mappin.and.ellipse")
                                }
                            }
                        } header: {
                            Label("Места на карте", systemImage: "mappin.and.ellipse")
                        }
                    }
                }
            }
            .navigationTitle("Всё о стихе · \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $place) { PlaceDetail(place: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .task { if !loaded { load() } }
        .sheet(item: $word) { WordSheet(req: $0) }
        .sheet(isPresented: $showComm) { CommentarySheet(book: book, chapter: chapter, verse: verse) }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var notesSection: some View {
        let note = marks.data.notes[key]
        let hl = hlColor(marks.data.highlights[key])
        let cols = collectionNames
        if note != nil || hl != nil || !cols.isEmpty {
            Section {
                if let c = hl {
                    HStack(spacing: 8) {
                        Circle().fill(c.color).frame(width: 14, height: 14)
                        Text(marks.colorName(c))
                    }
                }
                if let n = note {
                    Text(n.text)
                }
                if !cols.isEmpty {
                    Text("В подборках: \(cols.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Ваши пометки", systemImage: "square.and.pencil")
            }
        }
    }

    /// Слово: русское слово, слово оригинала, «номер · чтение · значение»
    private func wordCard(_ w: GuideWord) -> some View {
        let heb = w.num.hasPrefix("H")
        let meta = w.num + (w.xlit.map { " · " + $0 } ?? "") + (w.def.map { " · " + $0 } ?? "")
        return Button {
            word = WordRequest(text: w.token.text, strongs: w.token.strongs, morph: w.token.morph, book: book, chapter: chapter, verse: verse)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.token.text).fontWeight(.bold)
                if let lemma = w.lemma {
                    Text(lemma)
                        .font(heb ? .custom("Noto Serif Hebrew", size: 18) : .system(size: 18))
                        .frame(maxWidth: .infinity, alignment: heb ? .trailing : .leading)
                        .environment(\.layoutDirection, heb ? .rightToLeft : .leftToRight)
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
