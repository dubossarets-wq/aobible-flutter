import MapKit
import SwiftUI

/// Карты: места на карте (поиск по названию) и карты-картинки (с увеличением)
struct MapsView: View {
    @EnvironmentObject private var store: ModuleStore
    @State private var kind = 0
    @State private var query = ""
    @State private var found: [BiblePlace] = []
    /// Ничего не нашлось — близкие по написанию названия («Возможно, вы искали»)
    @State private var suggestions: [BiblePlace] = []

    var body: some View {
        List {
            Section {
                Picker("Что показывать", selection: $kind) {
                    Text("Места").tag(0)
                    Text("Карты").tag(1)
                }
                .pickerStyle(.segmented)
                // переключатель лежит прямо на сером фоне, без белого блока вокруг
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                // не нашлось — предлагаем похожие названия; нажатие открывает место
                if found.isEmpty, query.trimmingCharacters(in: .whitespaces).count >= 2, !store.placeModules.isEmpty {
                    if suggestions.isEmpty {
                        Section {
                            Text("Мест с таким названием нет.").foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Возможно, вы искали") {
                            ForEach(suggestions) { p in
                                NavigationLink {
                                    PlaceDetail(place: p)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name)
                                        if !p.modern.isEmpty { Text(p.modern).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
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
        .bottomSearch($query, prompt: "Название места")
        .onChange(of: query) { _, q in
            found = store.searchPlaces(q)
            suggestions = found.isEmpty ? store.suggestPlaces(q) : []
        }
    }
}

/// Место: карта Apple с отметкой, описание и стихи, где оно упомянуто
struct PlaceDetail: View {
    @Environment(\.openVerse) private var openVerse
    @Environment(\.dismiss) private var dismiss
    let place: BiblePlace
    /// «Обычная карта / Спутник»
    @State private var satellite = false
    /// Книга, места которой показаны в «Где упомянуто» (нет выбора — первая)
    @State private var bookFilter: String?

    /// Масштаб по виду места: область — крупно, хребет, долина, река, водоём, пустыня — средне, остальное — город с окрестностями
    private var span: Double {
        let t = place.type.lowercased()
        if ["област", "страна", "регион", "царств", "земля", "провинц", "полуостров", "остров"].contains(where: { t.contains($0) }) { return 6 }
        if ["хребет", "долин", "рек", "озер", "озёр", "мор", "залив", "пустын", "ручей", "поток"].contains(where: { t.contains($0) }) { return 2.5 }
        return 0.4
    }

    private func ref(_ osis: String) -> (String, Int, Int)? {
        guard let r = OsisRef(osis) else { return nil }
        return (r.book, r.chapter, r.verse)
    }

    /// Упоминания по книгам (в порядке книг Библии): глава и стих
    private var groups: [(book: String, items: [(chapter: Int, verse: Int)])] {
        var by: [String: [(chapter: Int, verse: Int)]] = [:]
        for r in place.refs {
            guard let x = ref(r) else { continue }
            by[x.0, default: []].append((x.1, x.2))
        }
        let order = Dictionary(uniqueKeysWithValues: Books.all.enumerated().map { ($1.id, $0) })
        return by.keys.sorted { (order[$0] ?? 999) < (order[$1] ?? 999) }.map { ($0, by[$0] ?? []) }
    }

    var body: some View {
        let coord = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))) {
                    Marker(place.name, coordinate: coord)
                }
                .mapStyle(satellite ? .hybrid : .standard)
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
                Picker("Карта", selection: $satellite) {
                    Text("Обычная карта").tag(false)
                    Text("Спутник").tag(true)
                }
                .pickerStyle(.segmented)
                Link("Спутник Google", destination: URL(string: "https://www.google.com/maps/@\(place.lat),\(place.lng),2000m/data=!3m1!1e3")!)
            }
            Section {
                if !place.type.isEmpty { LabeledContent("Что это", value: place.type) }
                if !place.modern.isEmpty { LabeledContent("Сейчас", value: place.modern) }
                if let c = place.confidence { LabeledContent("Уверенность отождествления", value: "\(c)%") }
                if !place.descr.isEmpty { Text(place.descr) }
            }
            if !place.refs.isEmpty {
                // не весь список подряд: сначала книги, где упомянуто, под ними — места выбранной книги плашками
                let gs = groups
                let sel = gs.first { $0.book == bookFilter } ?? gs.first
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(gs, id: \.book) { g in
                                RefChip(label: (Books.info(g.book)?.short ?? g.book).replacingOccurrences(of: ".", with: ""),
                                        count: g.items.count, on: g.book == sel?.book) {
                                    bookFilter = g.book
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if let sel {
                        FlowRow {
                            ForEach(Array(sel.items.enumerated()), id: \.offset) { _, it in
                                RefChip(label: "\(it.chapter):\(it.verse)") {
                                    dismiss()
                                    openVerse(sel.book, it.chapter, it.verse)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Где упомянуто")
                } footer: {
                    Text("Выберите книгу — ниже её места. Нажатие открывает стих.")
                }
            }
            Section {
                Text("\(place.moduleName) · \(place.license.isEmpty ? "OpenBible.info, CC BY 4.0" : place.license)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Карта-картинка с увеличением двумя пальцами
struct MapImageView: View {
    let map: MapImage

    var body: some View {
        // настоящая прокрутка с масштабом UIKit: щипок, двойное касание, сдвиг пальцем в увеличенном виде
        ZoomScrollImage(url: map.url)
            .ignoresSafeArea(edges: .horizontal)
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

/// Картинка с настоящим масштабом (UIScrollView): щипок до 8×, двойное касание — 3× в этой точке и обратно
struct ZoomScrollImage: UIViewRepresentable {
    let url: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FitScroll {
        let sv = FitScroll()
        let c = context.coordinator
        sv.delegate = c
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 8
        sv.bouncesZoom = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.backgroundColor = .clear
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        sv.addSubview(iv)
        sv.imageView = iv
        c.imageView = iv
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        sv.addSubview(spinner)
        sv.spinner = spinner
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        sv.addGestureRecognizer(double)
        c.scroll = sv
        c.load(url, into: sv)
        return sv
    }

    func updateUIView(_ sv: FitScroll, context: Context) {
        context.coordinator.load(url, into: sv)
    }

    /// Прокрутка, которая держит картинку по размеру окна, пока не увеличена
    final class FitScroll: UIScrollView {
        var imageView: UIImageView?
        var spinner: UIActivityIndicatorView?

        override func layoutSubviews() {
            super.layoutSubviews()
            spinner?.center = CGPoint(x: bounds.midX, y: bounds.midY)
            guard let iv = imageView, zoomScale == 1 else { return }
            if iv.frame.size != bounds.size {
                iv.frame = CGRect(origin: .zero, size: bounds.size)
                contentSize = bounds.size
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scroll: FitScroll?
        private var loaded: URL?

        func load(_ url: URL?, into sv: FitScroll) {
            guard let url, url != loaded else { return }
            loaded = url
            sv.spinner?.startAnimating()
            Task { @MainActor [weak self, weak sv] in
                let data = try? await URLSession.shared.data(from: url).0
                guard let self, let sv, self.loaded == url else { return }
                sv.spinner?.stopAnimating()
                if let data, let img = UIImage(data: data) {
                    self.imageView?.image = img
                    sv.setZoomScale(1, animated: false)
                    sv.setNeedsLayout()
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = scroll, let iv = imageView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: iv)
                let z: CGFloat = 3
                let size = CGSize(width: sv.bounds.width / z, height: sv.bounds.height / z)
                sv.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Подстрочник стиха: слова перевода, под каждым — слово оригинала и номер Стронга. Три источника: Винокуров
/// (главный; Новый Завет), подстрочник на основе синодального перевода и Вульгата (значения по словарю)
struct InterlinearSheet: View {
    private enum Source: String {
        case vin, syn, vulg

        var module: String {
            switch self {
            case .vin: return "vin-interlinear"
            case .syn: return "rst-interlinear"
            case .vulg: return "vulg-interlinear"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .vin: return "Винокуров"
            case .syn: return "Синодальный"
            case .vulg: return "Вульгата"
            }
        }
    }

    private struct VulgWord {
        let form: String
        let lemma: String
        let gloss: String
    }

    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    let book: String
    let chapter: Int
    let verse: Int
    /// Выбор помнится; по умолчанию — Винокуров
    @AppStorage("ilSource") private var sourceRaw = "vin"
    /// Окна слова и статьи — те же, что в тексте Библии (со формой слова «В этом стихе»)
    @StateObject private var req = StudyRequests()
    @Environment(\.openVerse) private var openVerse
    /// Модуль подстрочника ставится при первом открытии вкладки
    @State private var loading = false
    @State private var failed = false

    /// Винокуров переводит только Новый Завет
    private var sources: [Source] {
        Books.info(book)?.t == "NT" ? [.vin, .syn, .vulg] : [.syn, .vulg]
    }

    private var source: Source {
        let s = Source(rawValue: sourceRaw) ?? .vin
        return sources.contains(s) ? s : sources[0]
    }

    var body: some View {
        NavigationStack {
            List {
                // переключатель — как в окне Стронга: сегменты прямо на фоне, без белой карточки вокруг
                Picker("Подстрочник", selection: Binding(get: { source }, set: { sourceRaw = $0.rawValue })) {
                    ForEach(sources, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                Section {
                    content
                } footer: {
                    if !loading && !failed { Text(hint) }
                }
            }
            .navigationTitle("\(Books.info(book)?.short ?? book) \(chapter):\(verse)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .background(StudySheets(req: req) { b, c, v in
                openVerse(b, c, v)
                dismiss()
            })
            .task(id: source.module) { await ensure(source.module) }
        }
        .presentationDetents([.medium, .large])
        // Непрозрачный фон — внутри окна, а не presentationBackground: со своим presentationBackground система в iOS 26 не растягивает окно плавно из «парящего» вида на всю ширину (поднимается, а ширина прибавляется рывком)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Загрузка…").foregroundStyle(.secondary)
            }
        } else if failed {
            if source == .vulg {
                Text("Подстрочник к Вульгате пока недоступен.").foregroundStyle(.secondary)
            } else {
                Text("Оригинальный текст пока недоступен.").foregroundStyle(.secondary)
            }
        } else if let raw = store.verseRaw(module: source.module, book: book, chapter: chapter, verse: verse) {
            FlowLayout(spacing: 10) {
                if source == .vulg {
                    ForEach(Array(vulgWords(raw).enumerated()), id: \.offset) { _, w in vulgColumn(w) }
                } else {
                    let toks = Markup.parse(raw)
                    ForEach(Array(toks.enumerated()), id: \.offset) { i, t in column(t, i, toks) }
                }
            }
            .padding(.vertical, 6)
        } else {
            Text("В этом подстрочнике нет такого стиха.").foregroundStyle(.secondary)
        }
    }

    private var hint: LocalizedStringKey {
        switch source {
        case .vin: return "Подстрочник А. Винокурова — с разрешения автора. Под словом: чтение, перевод и номер Стронга."
        case .syn: return "Под словом: чтение, перевод и номер Стронга; бледным — обычное значение. Нажмите на слово — откроется словарь."
        case .vulg: return "Вульгата — латинская Библия бл. Иеронима (Климентинское издание). Под словом: начальная форма и значение. Значения — из Викисловаря (CC BY-SA 4.0), формы — по Collatinus."
        }
    }

    /// Ставит модуль подстрочника, если его ещё нет (Вульгата не входит в стартовый набор)
    private func ensure(_ id: String) async {
        failed = false
        guard store.module(id) == nil else { return }
        loading = true
        if store.catalog.isEmpty { await store.loadCatalog() }
        if let e = store.catalog.first(where: { $0.id == id }), e.downloadable {
            await store.install(e)
        }
        loading = false
        failed = store.module(id) == nil
    }

    /// Слово Вульгаты в модуле: «форма|лемма|значение», пробелы в значении записаны «_»
    private func vulgWords(_ raw: String) -> [VulgWord] {
        raw.split(separator: " ").map { cell in
            let p = cell.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return VulgWord(form: p[0], lemma: p.count > 1 ? p[1] : "", gloss: (p.count > 2 ? p[2] : "").replacingOccurrences(of: "_", with: " "))
        }
    }

    private func vulgColumn(_ w: VulgWord) -> some View {
        VStack(spacing: 2) {
            Text(w.form).font(.system(size: 19, design: .serif))
            Text(w.lemma.isEmpty ? " " : w.lemma).font(.caption).italic().foregroundStyle(.secondary)
            // значение по словарю — бледным: это не перевод данного места
            Text(w.gloss.isEmpty ? " " : w.gloss).font(.system(size: 15)).italic().foregroundStyle(Color.accentColor.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func column(_ t: Token, _ index: Int, _ toks: [Token]) -> some View {
        let words = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagged = t.orig != nil || !t.strongs.isEmpty
        // знаки препинания между словами — не слова; «·» у Винокурова — слово оригинала без перевода
        if tagged || words.rangeOfCharacter(from: .letters) != nil {
            VStack(spacing: 2) {
                if let o = t.orig {
                    Text(o).font(.system(size: 19, design: .serif)).foregroundStyle(.tint)
                    // чтение русскими буквами (греческий — по эразмову произношению, еврейский — по огласовкам)
                    let tr = Translit.of(o)
                    if !tr.isEmpty {
                        Text(tr).font(.system(size: 13)).italic().foregroundStyle(.secondary)
                    }
                }
                Text(words == "·" || words.isEmpty ? " " : words).font(.system(size: 17, weight: .semibold))
                if !t.strongs.isEmpty {
                    Text(t.strongs.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                guard !t.strongs.isEmpty else { return }
                // слово оригинала и его разбор — в статье Стронга видно, какой именно формой слово стоит в этом стихе
                // (статья — по начальной форме: «βοάω», а в стихе «ἐβόησεν»)
                var ow: OrigInfo?
                if let o = t.orig, let n = t.strongs.first {
                    let key = Align.strongNum(n)
                    let occ = toks[..<index].filter { $0.strongs.first.map(Align.strongNum) == key }.count
                    ow = OrigInfo(orig: o, morph: t.morph.first ?? Align.origMorph(store: store, book: book, chapter: chapter, verse: verse, num: n, occurrence: occ), num: key)
                }
                let title = words.isEmpty || words == "·" ? (t.orig ?? words) : words
                req.openedAt = Date()
                req.open(.word(WordRequest(text: title, strongs: t.strongs, morph: t.morph, book: book, chapter: chapter, verse: verse, origWord: ow)))
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
