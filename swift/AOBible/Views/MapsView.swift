import MapKit
import SwiftUI

/// Карты: места на карте (поиск по названию) и карты-картинки (с увеличением)
struct MapsView: View {
    @EnvironmentObject private var store: ModuleStore
    @State private var kind = 0
    @State private var query = ""
    @State private var found: [BiblePlace] = []

    var body: some View {
        List {
            Section {
                Picker("Что показывать", selection: $kind) {
                    Text("Места").tag(0)
                    Text("Карты").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if kind == 0 {
                if store.placeModules.isEmpty {
                    Section {
                        Text("Установите модуль «Места»: «Ещё» → «Библиотека модулей».").foregroundStyle(.secondary)
                    }
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    Section {
                        Text("Введите название места, например «Иерусалим» или «Вифлеем».").foregroundStyle(.secondary)
                    }
                }
                ForEach(found) { p in
                    NavigationLink {
                        PlaceDetail(place: p)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            if !p.modern.isEmpty { Text(p.modern).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } else {
                let maps = store.mapImages()
                if maps.isEmpty {
                    Section {
                        Text("Установите модуль «Карты»: «Ещё» → «Библиотека модулей».").foregroundStyle(.secondary)
                    }
                }
                ForEach(maps) { m in
                    NavigationLink {
                        MapImageView(map: m)
                    } label: {
                        Text(m.title)
                    }
                }
            }
        }
        .navigationTitle("Карты")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Название места")
        .onChange(of: query) { _, q in found = store.searchPlaces(q) }
    }
}

/// Место: карта Apple с отметкой, описание и стихи, где оно упомянуто
struct PlaceDetail: View {
    @Environment(\.openVerse) private var openVerse
    @Environment(\.dismiss) private var dismiss
    let place: BiblePlace

    private func ref(_ osis: String) -> (String, Int, Int)? {
        guard let r = OsisRef(osis) else { return nil }
        return (r.book, r.chapter, r.verse)
    }

    var body: some View {
        let coord = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)))) {
                    Marker(place.name, coordinate: coord)
                }
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if !place.type.isEmpty { LabeledContent("Что это", value: place.type) }
                if !place.modern.isEmpty { LabeledContent("Сейчас", value: place.modern) }
                if let c = place.confidence { LabeledContent("Уверенность отождествления", value: "\(c)%") }
                if !place.descr.isEmpty { Text(place.descr) }
            }
            if !place.refs.isEmpty {
                Section("Где упомянуто") {
                    ForEach(place.refs, id: \.self) { r in
                        if let x = ref(r) {
                            Button {
                                dismiss()
                                openVerse(x.0, x.1, x.2)
                            } label: {
                                Text("\(Books.info(x.0)?.short ?? x.0) \(x.1):\(x.2)").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            Section {
                Text("\(place.moduleName) · \(place.license)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Карта-картинка с увеличением двумя пальцами
struct MapImageView: View {
    let map: MapImage
    @State private var scale = 1.0
    @State private var base = 1.0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            AsyncImage(url: map.url) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ProgressView().padding(60)
            }
            .frame(width: UIScreen.main.bounds.width * scale)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { scale = min(6, max(1, base * $0.magnification)) }
                .onEnded { _ in base = scale }
        )
        .safeAreaInset(edge: .bottom) {
            Text(map.descr)
                .font(.footnote)
                .lineLimit(5)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
        }
        .navigationTitle(map.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Подстрочник стиха: слова перевода, под каждым — слово оригинала и номер Стронга
struct InterlinearSheet: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let book: String
    let chapter: Int
    let verse: Int
    @State private var moduleId = ""
    @State private var word: WordRequest?

    private var modules: [InstalledModule] {
        store.bibles.filter { $0.interlinear }
    }

    var body: some View {
        NavigationStack {
            List {
                if modules.isEmpty {
                    Section {
                        Text("Установите подстрочник: «Ещё» → «Библиотека модулей» → «Переводы» → «Подстрочник».")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if modules.count > 1 {
                        Section {
                            Picker("Подстрочник", selection: $moduleId) {
                                ForEach(modules) { m in Text(m.name).tag(m.id) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Section {
                        let id = modules.contains { $0.id == moduleId } ? moduleId : (modules.first?.id ?? "")
                        if let raw = store.verseRaw(module: id, book: book, chapter: chapter, verse: verse) {
                            FlowLayout(spacing: 10) {
                                ForEach(Array(Markup.parse(raw).enumerated()), id: \.offset) { _, t in
                                    column(t)
                                }
                            }
                            .padding(.vertical, 6)
                        } else {
                            Text("В этом подстрочнике нет такого стиха.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("\(Books.info(book)?.short ?? book) \(chapter):\(verse)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .sheet(item: $word) { WordSheet(req: $0) }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func column(_ t: Token) -> some View {
        let words = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            VStack(spacing: 2) {
                if let o = t.orig {
                    Text(o).font(.system(size: 19, design: .serif)).foregroundStyle(.tint)
                }
                Text(words).font(.system(size: 17, weight: .semibold))
                if !t.strongs.isEmpty {
                    Text(t.strongs.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                if !t.strongs.isEmpty {
                    word = WordRequest(text: words, strongs: t.strongs, morph: t.morph, book: book, chapter: chapter, verse: verse)
                }
            }
        }
    }
}

/// Слова переносятся на следующую строку, как текст
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x)
        }
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
