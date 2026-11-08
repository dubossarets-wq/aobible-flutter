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
                    Text((audio.pack?.name ?? "") + (audio.sleepLeft.map { " · сон \(clock($0))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                        ForEach([15, 30, 45, 60], id: \.self) { m in
                            Button("\(m) мин") { audio.setSleep(minutes: m) }
                        }
                        if audio.sleepLeft != nil {
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
        .background(VolumeHost(volume: volume).frame(width: 1, height: 1))
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

    private func cover(_ size: CGFloat, _ c: Place) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x6B4FDB), Color(hex: 0x3373F2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "book.fill").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
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

    /// Слова песни: стихи главы; звучащий — крупно и ярко, остальные — тусклее и размыты
    private func lyricsView(_ c: Place) -> some View {
        let verses = store.verses(module: textId, book: c.book, chapter: c.chapter)
        return ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(verses) { v in
                            let on = v.num == c.verse
                            Text(Markup.plain(v.text))
                                .font(.system(size: 31, weight: .bold))
                                .opacity(on ? 1 : 0.4)
                                .blur(radius: on ? 0 : 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { audio.seekVerse(v.num) }
                                .id(v.num)
                        }
                    }
                    .padding(.vertical, 120)
                    .animation(.easeInOut(duration: 0.3), value: c.verse)
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onChange(of: c.verse) { _, v in
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(v, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(c.verse, anchor: .center) }
            }
            // язык текста и чтеца — вертикальная «таблетка» справа, как переключатель слов в Apple Music
            Menu {
                Section("Текст") {
                    ForEach(store.bibles.filter { !$0.interlinear }) { m in
                        Button {
                            audio.textModule = m.id
                        } label: {
                            if m.id == textId { Label(m.name + " — " + m.title, systemImage: "checkmark") } else { Text(m.name + " — " + m.title) }
                        }
                    }
                }
                if packs.count > 1 {
                    Section("Чтец") {
                        ForEach(packs, id: \.id) { p in
                            Button {
                                audio.switchPack(p)
                            } label: {
                                if p.id == audio.pack?.id { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                            }
                        }
                    }
                }
            } label: {
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.22)).frame(width: 44, height: 92)
                    Circle().fill(.white.opacity(0.7)).frame(width: 44, height: 44)
                        .overlay(Image(systemName: "translate").font(.body.weight(.semibold)).foregroundStyle(Color(hex: 0x14395C)))
                }
            }
        }
    }

    private var progress: some View {
        let total = max(1, audio.duration)
        let pos = scrub ?? audio.position
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
                Text("−" + clock(max(0, audio.duration - pos)))
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

    private func bottomRow(_ c: Place) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button { lyrics.toggle() } label: {
                Image(systemName: lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(lyrics ? 0.9 : 0.55))
                    .frame(width: 52, height: 52)
                    .background(lyrics ? Color.white.opacity(0.25) : Color.clear, in: Circle())
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                RoutePicker().frame(width: 34, height: 34).frame(height: 52)
                if let r = routeName {
                    Text(r).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            // список: скорость и таймер сна
            Menu {
                Section("Скорость") {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button {
                            audio.rate = Float(r)
                        } label: {
                            if Double(audio.rate) == r { Label("\(r, specifier: "%g")×", systemImage: "checkmark") } else { Text("\(r, specifier: "%g")×") }
                        }
                    }
                }
                Section("Таймер сна") {
                    ForEach([15, 30, 45, 60], id: \.self) { m in
                        Button("\(m) мин") { audio.setSleep(minutes: m) }
                    }
                    if audio.sleepLeft != nil {
                        Button("Выключить таймер", role: .destructive) { audio.setSleep(minutes: nil) }
                    }
                }
            } label: {
                Image(systemName: "list.bullet").font(.title3).foregroundStyle(.white.opacity(0.55)).frame(width: 52, height: 52)
            }
            .frame(maxWidth: .infinity)
        }
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
