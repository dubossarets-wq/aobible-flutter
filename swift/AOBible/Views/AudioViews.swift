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

/// Раскрытый проигрыватель — как в Apple Music: большая обложка, название, ползунок, управление, громкость;
/// внизу — текст стиха (как слова песни) с переключением языка и язык чтеца, AirPlay
struct AudioFullView: View {
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openVerse) private var openVerse
    @State private var scrub: Double?
    @State private var showText = false
    @State private var packs: [AudioPack] = []

    private func clock(_ s: Double) -> String {
        let v = Int(max(0, s))
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    private var verseText: String {
        guard let c = audio.current else { return "" }
        return store.verseText(module: audio.textModule.isEmpty ? audio.moduleId : audio.textModule, book: c.book, chapter: c.chapter, verse: c.verse) ?? ""
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)
            if let c = audio.current {
                let name = Books.info(c.book)?.name ?? c.book
                if showText {
                    ScrollView {
                        Text(verseText)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                } else {
                    Spacer(minLength: 0)
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x2F4B7C), Color(hex: 0x0F1A2A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(spacing: 6) {
                            Image(systemName: "book.closed.fill").font(.system(size: 46)).foregroundStyle(.white.opacity(0.9))
                            Text(name).font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(.white)
                            Text("\(c.chapter)").font(.system(size: 54, weight: .bold, design: .serif)).foregroundStyle(.white)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                    .padding(.horizontal, 12)
                    Spacer(minLength: 0)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(name) \(c.chapter):\(c.verse)").font(.title3.weight(.bold)).lineLimit(1)
                        Text(audio.pack?.title ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button(role: .destructive) { audio.stop(); dismiss() } label: { Label("Закрыть проигрыватель", systemImage: "xmark") }
                        Button { dismiss(); openVerse(c.book, c.chapter, c.verse) } label: { Label("К тексту", systemImage: "book") }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { scrub ?? audio.position }, set: { scrub = $0 }), in: 0...max(1, audio.duration)) { editing in
                        if !editing, let s = scrub {
                            audio.seek(to: s)
                            scrub = nil
                        }
                    }
                    HStack {
                        Text(clock(scrub ?? audio.position))
                        Spacer()
                        Text("-" + clock(max(0, audio.duration - (scrub ?? audio.position))))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 34) {
                    Button { audio.previousVerse() } label: { Image(systemName: "backward.fill").font(.system(size: 32)) }
                    Button { audio.toggle() } label: { Image(systemName: audio.playing ? "pause.fill" : "play.fill").font(.system(size: 46)) }
                    Button { audio.nextVerse() } label: { Image(systemName: "forward.fill").font(.system(size: 32)) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    VolumeSlider().frame(height: 30)
                    Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    // текст стиха — как слова песни
                    Button { showText.toggle() } label: {
                        Image(systemName: showText ? "quote.bubble.fill" : "quote.bubble").font(.title3)
                    }
                    Spacer()
                    // язык: перевод текста и запись чтеца — как переключение перевода слов в Apple Music
                    Menu {
                        Section("Текст") {
                            ForEach(store.bibles.filter { !$0.interlinear }) { m in
                                Button {
                                    audio.textModule = m.id
                                    showText = true
                                } label: {
                                    if m.id == audio.textModule { Label(m.name + " — " + m.title, systemImage: "checkmark") } else { Text(m.name + " — " + m.title) }
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
                        Image(systemName: "translate").font(.title3)
                    }
                    Spacer()
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                            Button("\(r, specifier: "%g")×") { audio.rate = Float(r) }
                        }
                        Divider()
                        ForEach([15, 30, 45, 60], id: \.self) { m in
                            Button("Таймер сна: \(m) мин") { audio.setSleep(minutes: m) }
                        }
                        if audio.sleepLeft != nil {
                            Button("Выключить таймер", role: .destructive) { audio.setSleep(minutes: nil) }
                        }
                    } label: {
                        Image(systemName: audio.sleepLeft == nil ? "gauge.with.dots.needle.33percent" : "moon.zzz.fill").font(.title3)
                    }
                    Spacer()
                    RoutePicker().frame(width: 30, height: 30)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
            } else {
                ContentUnavailableView("Ничего не звучит", systemImage: "headphones")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            guard let c = audio.current else { return }
            packs = await audio.allPacks(store).filter { $0.has(c.book, c.chapter) }
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
