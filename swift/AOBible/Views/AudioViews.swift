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

/// Раскрытый проигрыватель: звучащий стих крупно, перемотка, стих и глава назад/вперёд, скорость, таймер сна
struct AudioFullView: View {
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openVerse) private var openVerse
    @State private var scrub: Double?

    private func clock(_ s: Double) -> String {
        let v = Int(max(0, s))
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let c = audio.current {
                    let name = Books.info(c.book)?.name ?? c.book
                    Text("\(name) \(c.chapter):\(c.verse)").font(.title2.weight(.bold))
                    Text(audio.pack?.title ?? "").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ScrollView {
                        Text(store.verseText(module: audio.moduleId, book: c.book, chapter: c.chapter, verse: c.verse) ?? "")
                            .font(.system(size: 24, design: .serif))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { scrub ?? audio.position }, set: { scrub = $0 }), in: 0...max(1, audio.duration)) { editing in
                            if !editing, let s = scrub {
                                audio.seek(to: s)
                                scrub = nil
                            }
                        }
                        HStack {
                            Text(clock(scrub ?? audio.position))
                            Spacer()
                            Text(clock(audio.duration))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 26) {
                        Button { audio.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                        Button { audio.previousVerse() } label: { Image(systemName: "backward.fill") }
                        Button { audio.toggle() } label: { Image(systemName: audio.playing ? "pause.fill" : "play.fill").font(.largeTitle) }
                        Button { audio.nextVerse() } label: { Image(systemName: "forward.fill") }
                        Button { audio.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    HStack {
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                                Button("\(r, specifier: "%g")×") { audio.rate = Float(r) }
                            }
                        } label: { Label("\(Double(audio.rate), specifier: "%g")×", systemImage: "speedometer") }
                        Spacer()
                        Menu {
                            ForEach([15, 30, 45, 60], id: \.self) { m in
                                Button("\(m) мин") { audio.setSleep(minutes: m) }
                            }
                            if audio.sleepLeft != nil {
                                Button("Выключить таймер", role: .destructive) { audio.setSleep(minutes: nil) }
                            }
                        } label: {
                            Label(audio.sleepLeft.map { clock(Double($0)) } ?? "Таймер сна", systemImage: "moon.zzz")
                        }
                        Spacer()
                        Button {
                            dismiss()
                            openVerse(c.book, c.chapter, c.verse)
                        } label: { Label("К тексту", systemImage: "book") }
                    }
                    .buttonStyle(.bordered)
                } else {
                    ContentUnavailableView("Ничего не звучит", systemImage: "headphones")
                }
            }
            .padding(20)
            .navigationTitle("Аудио")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Свернуть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть плеер", role: .destructive) {
                        audio.stop()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
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
