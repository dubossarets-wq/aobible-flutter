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
                    Button(role: .destructive) { audio.stop() } label: { Label("Закрыть проигрыватель", systemImage: "xmark") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
            .onTapGesture { expanded = true }
            .sheet(isPresented: $expanded) { AudioFullView() }
        }
    }
}

/// Системные громкость и AirPlay — как в Apple Music
private struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = false
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(frame: .zero)
        v.tintColor = .label
        v.activeTintColor = .systemBlue
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Раскрытый проигрыватель — как в Apple Music: тёмный фон, сверху обложка с названием, звёздочка и меню;
/// в середине текст стиха-главы, как слова песни (звучащий стих — крупно и ярко, остальные размыты; нажатие —
/// перемотка к стиху); ползунок с временем; управление; громкость; внизу — слова, AirPlay и список
struct AudioFullView: View {
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var marks: MarksStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openVerse) private var openVerse
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

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A1E26), Color(hex: 0x1A1620), Color(hex: 0x0E1824)], startPoint: .topTrailing, endPoint: .bottomLeading)
                .ignoresSafeArea()
            if let c = audio.current {
                VStack(spacing: 16) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).padding(.top, 8)
                    header(c)
                    if lyrics {
                        lyricsView(c)
                    } else {
                        Spacer(minLength: 0)
                        artwork(c)
                        Spacer(minLength: 0)
                    }
                    progress
                    controls
                    volume
                    bottomRow(c)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            } else {
                ContentUnavailableView("Ничего не звучит", systemImage: "headphones")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
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
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2F4B7C), Color(hex: 0x0F1A2A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: size * 0.03) {
                Image(systemName: "book.closed.fill").font(.system(size: size * 0.28))
                Text("\(c.chapter)").font(.system(size: size * 0.3, weight: .bold, design: .serif))
            }
        }
        .frame(width: size, height: size)
    }

    private func header(_ c: Place) -> some View {
        HStack(spacing: 14) {
            cover(78, c)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bookName(c)) \(c.chapter):\(c.verse)").font(.title3.weight(.bold)).lineLimit(1)
                Text(audio.pack?.title ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            let key = MarksStore.key(c.book, c.chapter, c.verse)
            Button {
                marks.toggleFavorite(c.book, c.chapter, c.verse, text: store.verseText(module: textId, book: c.book, chapter: c.chapter, verse: c.verse) ?? "")
            } label: {
                Image(systemName: marks.isFavorite(key) ? "star.fill" : "star").font(.title2)
            }
            Menu {
                Button { dismiss(); openVerse(c.book, c.chapter, c.verse) } label: { Label("К тексту", systemImage: "book") }
                Button(role: .destructive) { audio.stop(); dismiss() } label: { Label("Закрыть проигрыватель", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis").font(.title2).frame(width: 34, height: 34)
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
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(verses) { v in
                            let on = v.num == c.verse
                            Text(Markup.plain(v.text))
                                .font(.system(size: 31, weight: .bold))
                                .opacity(on ? 1 : 0.38)
                                .blur(radius: on ? 0 : 2.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { audio.seekVerse(v.num) }
                                .id(v.num)
                        }
                    }
                    .padding(.vertical, 120)
                    .animation(.easeInOut(duration: 0.3), value: c.verse)
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onChange(of: c.verse) { _, v in
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(v, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(c.verse, anchor: .center) }
            }
            // язык текста и чтеца — как переключение перевода слов в Apple Music
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
                Image(systemName: "translate").font(.title3).frame(width: 46, height: 46)
                    .background(.white.opacity(0.18), in: Circle())
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { scrub ?? audio.position }, set: { scrub = $0 }), in: 0...max(1, audio.duration)) { editing in
                if !editing, let s = scrub {
                    audio.seek(to: s)
                    scrub = nil
                }
            }
            .tint(.white.opacity(0.75))
            HStack {
                Text(clock(scrub ?? audio.position))
                Spacer()
                Text("−" + clock(max(0, audio.duration - (scrub ?? audio.position))))
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var controls: some View {
        HStack {
            Button { audio.previousVerse() } label: { Image(systemName: "backward.fill").font(.system(size: 38)) }
            Spacer()
            Button { audio.toggle() } label: { Image(systemName: audio.playing ? "pause.fill" : "play.fill").font(.system(size: 54)) }
            Spacer()
            Button { audio.nextVerse() } label: { Image(systemName: "forward.fill").font(.system(size: 38)) }
        }
        .padding(.horizontal, 46)
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.white.opacity(0.6))
            VolumeSlider().frame(height: 30)
            Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func bottomRow(_ c: Place) -> some View {
        HStack {
            Button { lyrics.toggle() } label: {
                Image(systemName: lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.title2)
                    .frame(width: 56, height: 46)
                    .background(lyrics ? Color.white.opacity(0.25) : Color.clear, in: Capsule())
            }
            Spacer()
            RoutePicker().frame(width: 34, height: 34)
            Spacer()
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
                Image(systemName: "list.bullet").font(.title2).frame(width: 56, height: 46)
            }
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
