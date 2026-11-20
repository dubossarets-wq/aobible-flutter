import AVKit
import MediaPlayer
import SwiftUI

/// Мини-проигрыватель над нижним меню: стих, пауза, стих назад/вперёд, скорость, таймер сна, закрыть
struct AudioBar: View {
    @EnvironmentObject private var audio: AudioEngine
    @State private var expanded = false

    private func clock(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        if let c = audio.current {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Books.info(c.book)?.short.replacingOccurrences(of: ".", with: "") ?? c.book) \(c.chapter):\(c.verse)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    AudioClockReader(clock: audio.clock) {
                        Text((audio.pack?.reader ?? audio.pack?.name ?? "") + (audio.sleepLeft.map { " · сон \(clock($0))" } ?? (audio.sleepAtChapterEnd ? " · сон до конца главы" : "")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button { audio.previousVerse() } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Стих назад")
                Button { audio.toggle() } label: { Image(systemName: audio.playing ? "pause.fill" : "play.fill").font(.title3) }
                    .accessibilityLabel(audio.playing ? "Пауза" : "Слушать")
                Button { audio.nextVerse() } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel("Стих вперёд")
                Menu {
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                            Button {
                                audio.rate = Float(r)
                            } label: {
                                if Double(audio.rate) == r { Label("\(r, specifier: "%g")×", systemImage: "checkmark") } else { Text("\(r, specifier: "%g")×") }
                            }
                        }
                    } label: { Label("Скорость", systemImage: "speedometer") }
                    Menu {
                        Button("До конца главы") { audio.setSleepAtChapterEnd() }
                        ForEach([5, 10, 15, 30, 45, 60, 90, 120], id: \.self) { m in
                            Button("\(m) мин") { audio.setSleep(minutes: m) }
                        }
                        if audio.sleepLeft != nil || audio.sleepAtChapterEnd {
                            Button("Выключить таймер", role: .destructive) { audio.setSleep(minutes: nil) }
                        }
                    } label: { Label("Таймер сна", systemImage: "moon.zzz") }
                    Button(role: .destructive) { audio.stop() } label: { Label("Закрыть", systemImage: "xmark") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
            .onTapGesture { expanded = true }
            .sheet(isPresented: $expanded) { AudioFullView() }
        }
    }
}

/// Системная громкость: ползунок рисуем сами (без кружка), а звук меняет скрытый MPVolumeView — так делает Apple Music
@MainActor
final class SystemVolume: ObservableObject {
    @Published var value: Double = Double(AVAudioSession.sharedInstance().outputVolume)
    fileprivate weak var host: MPVolumeView?
    private var obs: NSKeyValueObservation?

    init() {
        try? AVAudioSession.sharedInstance().setActive(true)
        obs = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor in self?.value = Double(v) }
        }
    }

    func set(_ v: Double) {
        value = v
        (host?.subviews.first { $0 is UISlider } as? UISlider)?.value = Float(v)
    }
}

/// Невидимый MPVolumeView: без него система не даёт менять громкость
private struct VolumeHost: UIViewRepresentable {
    let volume: SystemVolume

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.showsRouteButton = false
        v.alpha = 0.01
        volume.host = v
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(frame: .zero)
        v.tintColor = UIColor.white.withAlphaComponent(0.55)
        v.activeTintColor = .white
        v.prioritizesVideoDevices = false
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Тонкий ползунок без кружка, как в Apple Music: при касании утолщается
private struct SlimBar: View {
    @Binding var value: Double
    var onEnd: (() -> Void)? = nil
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let h: CGFloat = dragging ? 10 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(0.88)).frame(width: max(h, g.size.width * min(1, max(0, value))))
            }
            .frame(height: h)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        value = min(1, max(0, v.location.x / max(1, g.size.width)))
                    }
                    .onEnded { _ in
                        dragging = false
                        onEnd?()
                    }
            )
            .animation(.easeOut(duration: 0.15), value: dragging)
        }
        .frame(height: 26)
    }
}

/// Раскрытый проигрыватель — как экран слов в Apple Music: сверху обложка с названием, звёздочка и меню; в середине
/// текст главы как слова песни (звучащий стих — крупно и ярко, остальные размыты; нажатие — перемотка к стиху);
/// тонкий ползунок со временем; перемотка и пауза; громкость; внизу — слова, AirPlay и список
struct AudioFullView: View {
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openVerse) private var openVerse
    @StateObject private var volume = SystemVolume()
    @State private var scrub: Double?
    @State private var lyrics = true
    @State private var packs: [AudioPack] = []
    @State private var showChapters = false
    /// Открытый выбор перевода текста или озвучки
    @State private var picker: PickerKind?

    private enum PickerKind: Identifiable {
        case text, audio
        var id: Int { self == .text ? 0 : 1 }
    }

    private func clock(_ s: Double) -> String {
        let v = Int(max(0, s))
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    private var textId: String {
        audio.textModule.isEmpty ? audio.moduleId : audio.textModule
    }

    private var routeName: String? {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return nil }
        switch port.portType {
        case .builtInSpeaker, .builtInReceiver: return nil
        default: return port.portName
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x14395C), Color(hex: 0x0E2238), Color(hex: 0x0A121C)], startPoint: .topTrailing, endPoint: .bottomLeading)
                .ignoresSafeArea()
            if let c = audio.current {
                VStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 22)
                    header(c)
                    if lyrics {
                        lyricsView(c).padding(.top, 10)
                    } else {
                        Spacer(minLength: 0)
                        artwork(c)
                        Spacer(minLength: 0)
                    }
                    pickersRow.padding(.top, 10)
                    progress.padding(.top, 14)
                    controls.padding(.top, 26)
                    volumeRow.padding(.top, 30)
                    bottomRow(c).padding(.top, 26)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            } else {
                ContentUnavailableView("Ничего не звучит", systemImage: "headphones")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        // свой цвет акцента — белый: значки в меню совпадают с подписями, а не синие
        .tint(.white)
        .background(VolumeHost(volume: volume).frame(width: 1, height: 1))
        .sheet(item: $picker) { kind in pickerSheet(kind) }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            guard let c = audio.current else { return }
            packs = await audio.allPacks(store).filter { $0.has(c.book, c.chapter) }
        }
    }

    private func bookName(_ c: Place) -> String {
        Books.info(c.book)?.name ?? c.book
    }

    /// Обложка — сам логотип «Колос», обрезанный скруглённым квадратом (без своей плитки вокруг: внутри был виден квадрат)
    private func cover(_ size: CGFloat, _ c: Place) -> some View {
        Image("Logo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private func header(_ c: Place) -> some View {
        HStack(spacing: 14) {
            cover(64, c)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bookName(c)) \(c.chapter):\(c.verse)").font(.headline.weight(.bold)).lineLimit(1)
                Text(audio.pack?.reader ?? audio.pack?.name ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 8)
            let key = MarksStore.key(c.book, c.chapter, c.verse)
            Button {
                marks.toggleFavorite(c.book, c.chapter, c.verse, text: store.verseText(module: textId, book: c.book, chapter: c.chapter, verse: c.verse) ?? "")
            } label: {
                Image(systemName: marks.isFavorite(key) ? "star.fill" : "star").font(.title3).frame(width: 36, height: 44)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Menu {
                Button { dismiss(); openVerse(c.book, c.chapter, c.verse) } label: { Label("К тексту", systemImage: "book") }
                Button(role: .destructive) { audio.stop(); dismiss() } label: { Label("Закрыть", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 36, height: 44)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func artwork(_ c: Place) -> some View {
        cover(300, c)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    /// Слова песни: стихи главы; звучащий — крупно и ярко, остальные тусклее. Размыты те, что далеко от середины окна:
    /// листаете — стихи у середины становятся чёткими (яркость при этом не меняется)
    private func lyricsView(_ c: Place) -> some View {
        let verses = store.verses(module: textId, book: c.book, chapter: c.chapter)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(verses) { v in
                        let on = v.num == c.verse
                        Text(Markup.plain(v.text))
                            .font(.system(size: 31, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // запас вокруг текста внутри самого блока: края размытия не обрезаются границей блока
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .visualEffect { content, geo in
                                let h = geo.bounds(of: .scrollView)?.height ?? 600
                                let d = min(1, abs(geo.frame(in: .scrollView).midY - h / 2) / max(1, h / 2))
                                // у середины окна — чётко, дальше — быстро (в пределах пятой части высоты) размывается
                                let sharp = on ? 1 : max(0, min(1, 1 - (d - 0.12) / 0.2))
                                return content.opacity(on ? 1 : 0.4).blur(radius: 3 * (1 - sharp))
                            }
                            .animation(.easeInOut(duration: 0.3), value: on)
                            .contentShape(Rectangle())
                            .onTapGesture { audio.seekVerse(v.num) }
                            .id(v.num)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 112)
            }
            // прокрутка шире поля на 18 пт с каждой стороны и не обрезает содержимое — размытый край виден целиком
            .scrollClipDisabled()
            .padding(.horizontal, -18)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: c.verse) { _, v in
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(v, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(c.verse, anchor: .center) }
        }
    }

    /// Перевод текста и озвучка — одной строкой на всю ширину, две кнопки; выбор — в листе, где названия видны целиком
    private var pickersRow: some View {
        HStack(spacing: 10) {
            pickerButton("text.alignleft", "Текст", store.module(textId)?.name ?? "") { picker = .text }
            pickerButton("headphones", "Озвучка", audio.pack?.reader ?? audio.pack?.name ?? "") { picker = .audio }
        }
    }

    private func pickerButton(_ icon: String, _ caption: LocalizedStringKey, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Лист выбора: название крупно, полное описание под ним (переносится, не обрезается), выбранный — с галочкой
    @ViewBuilder private func pickerSheet(_ kind: PickerKind) -> some View {
        NavigationStack {
            List {
                if kind == .text {
                    ForEach(store.bibles.filter { !$0.interlinear }) { m in
                        optionRow(m.name, m.title, selected: m.id == textId) {
                            audio.textModule = m.id
                            picker = nil
                        }
                    }
                } else {
                    ForEach(packs, id: \.id) { p in
                        optionRow(p.title, p.reader ?? "", selected: p.id == audio.pack?.id) {
                            audio.switchPack(p)
                            picker = nil
                        }
                    }
                }
            }
            .navigationTitle(kind == .text ? "Перевод текста" : "Озвучка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { picker = nil } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func optionRow(_ title: String, _ subtitle: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        AudioClockReader(clock: audio.clock) { progressBody }
    }

    private var progressBody: some View {
        let total = max(1, audio.chapterDur)
        let pos = scrub ?? audio.chapterPos
        return VStack(spacing: 2) {
            SlimBar(value: Binding(get: { pos / total }, set: { scrub = $0 * total })) {
                if let s = scrub {
                    audio.seek(to: s)
                    scrub = nil
                }
            }
            HStack {
                Text(clock(pos))
                Spacer()
                Text(store.module(textId)?.shortName ?? "")
                Spacer()
                Text("−" + clock(max(0, audio.chapterDur - pos)))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Три кнопки на равных расстояниях друг от друга
    private var controls: some View {
        HStack(spacing: 0) {
            Button { audio.previousVerse() } label: { Image(systemName: "backward.fill").font(.system(size: 34)) }
                .frame(maxWidth: .infinity)
            Button { audio.toggle() } label: { Image(systemName: audio.playing ? "pause.fill" : "play.fill").font(.system(size: 48)).frame(width: 60) }
                .frame(maxWidth: .infinity)
            Button { audio.nextVerse() } label: { Image(systemName: "forward.fill").font(.system(size: 34)) }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Громкость: значки по бокам стоят точно напротив ползунка
    private var volumeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).frame(width: 18)
            SlimBar(value: Binding(get: { volume.value }, set: { volume.set($0) }))
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).frame(width: 22)
        }
        .frame(height: 26)
    }

    private func roundIcon(_ icon: String, active: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(.white.opacity(active ? 0.95 : 0.55))
            .frame(width: 52, height: 52)
            .background(active ? Color.white.opacity(0.25) : Color.clear, in: Circle())
            .contentShape(Circle())
    }

    /// Нижний ряд: слова, скорость, таймер сна, AirPlay, главы — кнопки одного вида
    private func bottomRow(_ c: Place) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button { lyrics.toggle() } label: { roundIcon(lyrics ? "quote.bubble.fill" : "quote.bubble", active: lyrics) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button {
                        audio.rate = Float(r)
                    } label: {
                        if Double(audio.rate) == r { Label("\(r, specifier: "%g")×", systemImage: "checkmark") } else { Text("\(r, specifier: "%g")×") }
                    }
                }
            } label: {
                roundIcon("speedometer", active: audio.rate != 1)
            }
            .frame(maxWidth: .infinity)
            Menu {
                Button("До конца главы") { audio.setSleepAtChapterEnd() }
                ForEach([5, 10, 15, 30, 45, 60, 90, 120], id: \.self) { m in
                    Button("\(m) мин") { audio.setSleep(minutes: m) }
                }
                if audio.sleepLeft != nil || audio.sleepAtChapterEnd {
                    Button("Выключить таймер", role: .destructive) { audio.setSleep(minutes: nil) }
                }
            } label: {
                roundIcon("moon.zzz", active: audio.sleepLeft != nil || audio.sleepAtChapterEnd)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                RoutePicker().frame(width: 34, height: 34).frame(height: 52)
                if let r = routeName {
                    Text(r).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            // главы книги: нажали — выбрать, и озвучка переходит на неё
            Button { showChapters = true } label: { roundIcon("list.bullet", active: showChapters) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showChapters) { chaptersGrid(c) }
        }
    }

    @ViewBuilder private func chaptersGrid(_ c: Place) -> some View {
        let nums = (audio.pack?.chapters.keys.compactMap { k -> Int? in
            k.hasPrefix(c.book + ".") ? Int(k.dropFirst(c.book.count + 1)) : nil
        } ?? []).sorted()
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(nums, id: \.self) { n in
                    Button {
                        showChapters = false
                        audio.playChapter(n)
                    } label: {
                        Text("\(n)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color.white.opacity(n == c.chapter ? 0.3 : 0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 280)
        .frame(maxHeight: 360)
        .presentationCompactAdaptation(.popover)
    }
}

/// Аудио: записи (ставятся в «Библиотеке модулей» → «Аудио») и книги, скачанные для прослушивания без интернета
struct AudioSettingsView: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var audio: AudioEngine
    @State private var packs: [AudioPack] = []
    @State private var loaded = false
    @State private var progress: [String: (Int, Int)] = [:]
    @State private var tasks: [String: Task<Void, Never>] = [:]
    @State private var refresh = 0
    @AppStorage("audioFollowsTranslation") private var follows = true

    var body: some View {
        List {
            Section {
                Toggle("Запись на языке перевода", isOn: $follows)
            } footer: {
                Text("Поменяли перевод во время чтения вслух — запись подбирается на его языке.")
            }
            if loaded && packs.isEmpty {
                Section {
                    Text("Записей пока нет. Установите их: «Ещё» → «Библиотека модулей» → «Аудио».")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(packs, id: \.id) { pack in
                Section {
                    ForEach(pack.books(), id: \.self) { book in
                        let key = "\(pack.id)|\(book)"
                        let offline = OfflineAudio.isBookOffline(pack, book)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Books.info(book)?.name ?? book)
                                if offline {
                                    Text("Скачано · \(ByteCountFormatter.string(fromByteCount: Int64(OfflineAudio.bytes(pack, book)), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let p = progress[key] {
                                ProgressView(value: Double(p.0), total: Double(max(1, p.1)))
                                    .frame(width: 70)
                                Button { tasks[key]?.cancel() } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.plain)
                            } else if offline {
                                Button(role: .destructive) {
                                    OfflineAudio.remove(pack, book)
                                    refresh += 1
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                            } else {
                                Button { download(pack, book, key) } label: { Image(systemName: "arrow.down.circle") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                } header: {
                    Text(pack.title)
                }
            }
        }
        .id(refresh)
        .navigationTitle("Аудио")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            packs = await audio.allPacks(store)
            loaded = true
        }
    }

    private func download(_ pack: AudioPack, _ book: String, _ key: String) {
        progress[key] = (0, pack.urls(of: book).count)
        tasks[key] = Task {
            do {
                try await OfflineAudio.download(pack, book) { done, total in progress[key] = (done, total) }
            } catch {
                // остановили или нет сети — недокачанное остаётся и докачается в следующий раз
            }
            progress[key] = nil
            tasks[key] = nil
            refresh += 1
        }
    }
}
