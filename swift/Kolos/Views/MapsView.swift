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
                CapsuleSwitcher(options: [(0, String(localized: "Места")), (1, String(localized: "Карты"))], selection: $kind)
                // переключатель лежит прямо на сером фоне, без белого блока вокруг
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
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
                CapsuleSwitcher(options: [(false, String(localized: "Обычная карта")), (true, String(localized: "Спутник"))], selection: $satellite)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                    .softEdges()
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
        .toolbar {
            // место уходит текстом: название, координаты и ссылки на карты Apple и Google
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: place.shareText, subject: Text(place.name)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться")
            }
        }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareImageButton(url: map.url, caption: [map.title, map.descr].filter { !$0.isEmpty }.joined(separator: "\n"))
                }
            }
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

/// Подстрочник стиха: слова перевода, под каждым — слово оригинала, его чтение и номер Стронга. Три источника: Винокуров
/// (главный; Новый Завет), подстрочник на основе синодального перевода и Вульгата (значения по словарю).
/// Над словами закреплены переключатель переводов и стих; кнопки в шапке и смахивание влево-вправо листают стихи
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
    /// Перевод, из которого открыли окно: его стих написан над подстрочником
    let moduleId: String
    /// Какой стих показан сейчас (стрелками и смахиванием листается)
    @State private var c: Int
    @State private var v: Int
    /// Откуда въезжает следующий стих (при листании назад — с другой стороны)
    @State private var dir: Edge = .trailing
    /// Сколько стихов в каждой главе книги — для листания через границу главы
    @State private var counts: [Int: Int] = [:]
    /// Окно всегда открывается на Винокурове; выбранное в этом окне — пока оно открыто
    @State private var picked: Source?
    /// Окна слова и статьи — те же, что в тексте Библии (со формой слова «В этом стихе»)
    @StateObject private var req = StudyRequests()
    @Environment(\.openVerse) private var openVerse
    /// Модуль подстрочника ставится при первом открытии вкладки
    @State private var loading = false
    @State private var failed = false

    init(book: String, chapter: Int, verse: Int, moduleId: String) {
        self.book = book
        self.moduleId = moduleId
        _c = State(initialValue: chapter)
        _v = State(initialValue: verse)
    }

    /// Винокуров переводит только Новый Завет
    private var sources: [Source] {
        Books.info(book)?.t == "NT" ? [.vin, .syn, .vulg] : [.syn, .vulg]
    }

    private var source: Source {
        if let p = picked, sources.contains(p) { return p }
        return sources[0]
    }

    private var chapterCount: Int {
        store.module(moduleId)?.books.first { $0.id == book }?.chapters ?? c
    }

    private var canPrev: Bool { c > 1 || v > 1 }
    private var canNext: Bool { c < chapterCount || v < (counts[c] ?? v) }

    /// Соседний стих (через границу главы тоже)
    private func step(_ d: Int) {
        var nc = c
        var nv = v + d
        if nv < 1 {
            guard c > 1 else { return }
            nc = c - 1
            nv = max(1, counts[nc] ?? 1)
        } else if nv > (counts[c] ?? v) {
            guard c < chapterCount else { return }
            nc = c + 1
            nv = 1
        }
        dir = d > 0 ? .trailing : .leading
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.3)) {
                c = nc
                v = nv
            }
        }
    }

    /// Другой перевод: слова въезжают с той стороны, куда он стоит в переключателе
    private func select(_ new: Source) {
        guard new != source else { return }
        let from = sources.firstIndex(of: source) ?? 0
        let to = sources.firstIndex(of: new) ?? 0
        dir = to > from ? .trailing : .leading
        // направление должно попасть в уходящий вид раньше, чем он начнёт уходить, — меняем перевод следующим проходом
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.3)) { picked = new }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // сверху закреплено: переключатель переводов и стих — прокручиваются только слова под ними
                VStack(spacing: 10) {
                    switcher
                    quoteCard
                        .id("\(c):\(v)")
                        .transition(.push(from: dir))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .clipped()
                // слова уезжают целиком вместе с прокруткой, на их место въезжают другие (в сторону смахивания)
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            content
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !loading && !failed {
                                Text(hint).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id("\(c):\(v):\(source.rawValue)")
                    .transition(.push(from: dir))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
                .clipped()
            }
            // смахивание влево — следующий стих, вправо — предыдущий (перевод переключают плашки сверху)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { g in
                    let dx = g.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(g.translation.height) * 1.5 else { return }
                    step(dx < 0 ? 1 : -1)
                }
            )
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(Books.info(book)?.short ?? book) \(c):\(v)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // две круглые кнопки слева от заголовка — к предыдущему и следующему стиху
                ToolbarItem(placement: .topBarLeading) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(!canPrev)
                        .accessibilityLabel("Предыдущий стих")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(!canNext)
                        .accessibilityLabel("Следующий стих")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .background(StudySheets(req: req) { bb, cc, vv in
                openVerse(bb, cc, vv)
                dismiss()
            })
            .task(id: source.module) { await ensure(source.module) }
            .task { counts = store.verseCounts(module: moduleId, book: book) }
        }
        .presentationDetents([.large])
        // Непрозрачный фон — внутри окна, а не presentationBackground: со своим presentationBackground система в iOS 26 не растягивает окно плавно из «парящего» вида на всю ширину (поднимается, а ширина прибавляется рывком)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var switcher: some View {
        CapsuleSwitcher(options: sources.map { (value: $0, title: Text($0.title)) }, selection: Binding(get: { source }, set: { select($0) }))
    }

    /// Высота текста стиха — чтобы длинный стих прокручивался внутри карточки, а короткий не оставлял пустоты
    @State private var quoteHeight: CGFloat = 0

    /// Стих с номером на карточке: компактная (длинный стих прокручивается внутри, не отнимая место у слов)
    @ViewBuilder private var quoteCard: some View {
        let q = store.verseText(module: moduleId, book: book, chapter: c, verse: v) ?? ""
        if !q.isEmpty {
            ScrollView(showsIndicators: false) {
                (Text("\(v) ").font(.system(size: 12, weight: .bold)).foregroundColor(.accentColor).baselineOffset(5)
                    + Text(q).font(.system(size: 17, design: .serif)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { quoteHeight = $0 }
            }
            .frame(height: quoteHeight > 0 ? min(quoteHeight, 132) : nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
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
        } else if let raw = store.verseRaw(module: source.module, book: book, chapter: c, verse: v) {
            FlowLayout(spacing: 10) {
                if source == .vulg {
                    ForEach(Array(vulgWords(raw).enumerated()), id: \.offset) { _, w in vulgColumn(w) }
                } else {
                    let toks = Markup.parse(raw)
                    ForEach(Array(toks.enumerated()), id: \.offset) { i, t in column(t, i, toks) }
                }
            }
        } else {
            Text("В этом подстрочнике нет такого стиха.").foregroundStyle(.secondary)
        }
    }

    /// Коротко, что это за перевод
    private var hint: LocalizedStringKey {
        switch source {
        case .vin: return "Подстрочный перевод Нового Завета А. Винокурова."
        case .syn: return "Синодальный перевод; под словами — оригинал, чтение и номер Стронга."
        case .vulg: return "Латинская Вульгата; под словами — значение и начальная форма."
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

    /// Колонка слова: четыре строки одной высоты у всех слов — оригинал, чтение, перевод, номер (пустая строка
    /// остаётся пустой, но место держит: перевод у всех слов на одном уровне)
    private func cell(_ top: String, _ reading: String?, _ gloss: String, _ foot: String) -> some View {
        VStack(spacing: 2) {
            Text(top.isEmpty ? " " : top).font(.system(size: 19, design: .serif)).foregroundStyle(.tint)
            // чтение русскими буквами — у греческого и еврейского; у латинского слова строки нет
            if let reading {
                Text(reading.isEmpty ? " " : reading).font(.system(size: 13)).italic().foregroundStyle(.secondary)
            }
            Text(gloss.isEmpty ? " " : gloss).font(.system(size: 17, weight: .semibold))
            Text(foot.isEmpty ? " " : foot).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Вульгата — в том же виде, что Винокуров: слово, значение по словарю, начальная форма
    private func vulgColumn(_ w: VulgWord) -> some View {
        cell(w.form, nil, w.gloss, w.lemma.isEmpty ? w.form.lowercased() : w.lemma)
    }

    @ViewBuilder
    private func column(_ t: Token, _ index: Int, _ toks: [Token]) -> some View {
        let words = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagged = t.orig != nil || !t.strongs.isEmpty
        // знаки препинания между словами — не слова; «·» у Винокурова — слово оригинала без перевода
        if tagged || words.rangeOfCharacter(from: .letters) != nil {
            // слово без оригинала (в синодальном: «я», «был», «, то») — такая же по высоте колонка, только пустая сверху
            // и снизу: слово стоит там же, где перевод у остальных
            cell(t.orig ?? "", t.orig.map { Translit.of($0) } ?? "", words == "·" ? "" : words, t.strongs.joined(separator: " "))
                .onTapGesture {
                    guard !t.strongs.isEmpty else { return }
                    // слово оригинала и его разбор — в статье Стронга видно, какой именно формой слово стоит в этом стихе
                    // (статья — по начальной форме: «βοάω», а в стихе «ἐβόησεν»)
                    var ow: OrigInfo?
                    if let o = t.orig, let n = t.strongs.first {
                        let key = Align.strongNum(n)
                        let occ = toks[..<index].filter { $0.strongs.first.map(Align.strongNum) == key }.count
                        ow = OrigInfo(orig: o, morph: t.morph.first ?? Align.origMorph(store: store, book: book, chapter: c, verse: v, num: n, occurrence: occ), num: key)
                    }
                    let title = words.isEmpty || words == "·" ? (t.orig ?? words) : words
                    req.openedAt = Date()
                    req.open(.word(WordRequest(text: title, strongs: t.strongs, morph: t.morph, book: book, chapter: c, verse: v, origWord: ow)))
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
            // ширина — без промежутка после последнего слова строки: иначе плотная строка выходила за край на spacing,
            // и блок целиком съезжал влево (отступы по бокам менялись от перевода к переводу)
            w = max(w, x - spacing)
        }
        return CGSize(width: min(w, maxW), height: y + rowH)
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
