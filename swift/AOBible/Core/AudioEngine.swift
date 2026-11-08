import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI

/// Запись одной главы: адрес файла и время начала стихов (секунды от начала файла).
/// start/end есть, когда на несколько глав один файл (тогда глава — кусок файла)
struct AudioChapter {
    let url: String
    let verses: [(Int, Double)]
    let start: Double?
    let end: Double?

    var shared: Bool { end != nil }

    /// С какой секунды начинать стих: первый стих — с начала главы, иначе — с начала стиха
    func startFor(_ verse: Int) -> Double {
        if verse == 1, let s = start { return s }
        if let v = verses.first(where: { $0.0 == verse }) { return v.1 }
        return start ?? 0
    }

    /// Какой стих звучит в секунду sec (с запасом 0,05 с); nil — до первого стиха
    func verseAt(_ sec: Double) -> Int? {
        let t = sec + 0.05
        var cur: Int?
        for v in verses {
            if v.1 <= t { cur = v.0 } else { break }
        }
        return cur
    }
}

/// Аудиомодуль: перевод, к которому записи подходят, и озвученные главы («Книга.глава» → запись)
final class AudioPack: @unchecked Sendable {
    /// Чтец (из описания модуля: «чтец: …»)
    var reader: String?
    let id: String
    let name: String
    let title: String
    let translation: String?
    let language: String
    let chapters: [String: AudioChapter]

    init(id: String, name: String, title: String, translation: String?, language: String, chapters: [String: AudioChapter]) {
        self.id = id
        self.name = name
        self.title = title
        self.translation = translation
        self.language = language
        self.chapters = chapters
    }

    static func parse(_ raw: String) -> AudioPack? {
        guard let data = raw.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = j["id"] as? String else { return nil }
        var ch: [String: AudioChapter] = [:]
        for (k, v) in (j["chapters"] as? [String: Any]) ?? [:] {
            guard let m = v as? [String: Any], let url = m["url"] as? String else { continue }
            var verses: [(Int, Double)] = []
            for p in (m["verses"] as? [[Any]]) ?? [] where p.count >= 2 {
                if let n = p[0] as? NSNumber, let t = p[1] as? NSNumber { verses.append((n.intValue, t.doubleValue)) }
            }
            ch[k] = AudioChapter(url: url, verses: verses, start: (m["start"] as? NSNumber)?.doubleValue, end: (m["end"] as? NSNumber)?.doubleValue)
        }
        let name = j["name"] as? String ?? id
        let pack = AudioPack(id: id, name: name, title: j["title"] as? String ?? name, translation: j["translation"] as? String, language: j["language"] as? String ?? "ru", chapters: ch)
        if let d = j["description"] as? String,
           let r = d.range(of: "чтец[а-яё]*:\\s*[^)\\.;]+", options: .regularExpression) {
            let t = String(d[r])
            if let colon = t.firstIndex(of: ":") {
                let v = t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { pack.reader = v }
            }
        }
        return pack
    }

    func has(_ book: String, _ chapter: Int) -> Bool { chapters["\(book).\(chapter)"] != nil }

    /// Адреса файлов всех глав книги (без повторов: на несколько глав бывает один файл)
    func urls(of book: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for (k, c) in chapters where k.split(separator: ".").first.map(String.init) == book {
            if seen.insert(c.url).inserted { out.append(c.url) }
        }
        return out
    }

    func books() -> [String] {
        var set = Set<String>()
        for k in chapters.keys { if let b = k.split(separator: ".").first { set.insert(String(b)) } }
        return Books.all.map { $0.id }.filter { set.contains($0) }
    }
}

/// Синодальный с разметкой и без — один и тот же текст
private let rstIds: Set<String> = ["rst", "rst-plus", "rst-dc"]

func audioFits(_ translation: String?, _ bibleId: String) -> Bool {
    guard let t = translation, !t.isEmpty else { return true }
    return t == bibleId || (rstIds.contains(t) && rstIds.contains(bibleId))
}

/// Книги без интернета: записи глав скачиваются в папку приложения audio/; проигрыватель сначала ищет файл там.
/// Имена файлов — те же, что у Flutter-версии (FNV-1a по адресу), скачанное ею подхватывается
enum OfflineAudio {
    static func dir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let d = base.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func fileName(_ url: String) -> String {
        var h1: UInt64 = 0x811c9dc5
        var h2: UInt64 = 0x01234567
        for b in url.utf8 {
            h1 = ((h1 ^ UInt64(b)) &* 0x01000193) & 0xffffffff
            h2 = (((h2 &+ UInt64(b)) &* 0x2f0b4a27) ^ (h2 >> 7)) & 0xffffffff
        }
        let low = url.lowercased()
        let ext = low.contains(".m4a") ? "m4a" : (low.contains(".ogg") ? "ogg" : "mp3")
        return String(h1, radix: 16) + String(h2, radix: 16) + "." + ext
    }

    static func localURL(_ url: String) -> URL? {
        let f = dir().appendingPathComponent(fileName(url))
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path), (attrs[.size] as? Int ?? 0) > 0 else { return nil }
        return f
    }

    static func isBookOffline(_ pack: AudioPack, _ book: String) -> Bool {
        let urls = pack.urls(of: book)
        return !urls.isEmpty && urls.allSatisfy { localURL($0) != nil }
    }

    static func bytes(_ pack: AudioPack, _ book: String) -> Int {
        pack.urls(of: book).reduce(0) { sum, u in
            if let f = localURL(u), let a = try? FileManager.default.attributesOfItem(atPath: f.path) { return sum + (a[.size] as? Int ?? 0) }
            return sum
        }
    }

    static func remove(_ pack: AudioPack, _ book: String) {
        for u in pack.urls(of: book) {
            try? FileManager.default.removeItem(at: dir().appendingPathComponent(fileName(u)))
        }
    }

    /// Скачать все записи книги; progress(готово, всего)
    static func download(_ pack: AudioPack, _ book: String, progress: @escaping @MainActor (Int, Int) -> Void) async throws {
        let urls = pack.urls(of: book)
        for (i, u) in urls.enumerated() {
            try Task.checkCancellation()
            if localURL(u) == nil, let remote = URL(string: u) {
                let (tmp, resp) = try await URLSession.shared.download(from: remote)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let target = dir().appendingPathComponent(fileName(u))
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: tmp, to: target)
            }
            await progress(i + 1, urls.count)
        }
    }
}

/// Проигрыватель Библии: запись главы, стих по времени, соседний стих и глава, скорость, таймер сна, экран блокировки
@MainActor
final class AudioEngine: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var playing = false
    @Published private(set) var current: Place?
    @Published private(set) var pack: AudioPack?
    @Published private(set) var moduleId = ""
    /// Перевод, текст которого показан в раскрытом проигрывателе (как слова песни в Apple Music)
    @Published var textModule = ""
    /// Секунды в файле (для общих файлов на несколько глав — от начала файла)
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    /// Секунды внутри главы: по ним ползунок и время в проигрывателе
    @Published private(set) var chapterPos = 0.0
    @Published private(set) var chapterDur = 0.0
    @Published private(set) var sleepLeft: Int?
    /// Таймер сна «До конца главы»
    @Published private(set) var sleepAtChapterEnd = false
    @Published var rate: Float = 1.0 {
        didSet { if playing { player?.rate = rate } }
    }
    @Published var message: String?

    private var player: AVPlayer?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var packs: [String: AudioPack] = [:]
    private var sleepTask: Task<Void, Never>?
    private weak var store: ModuleStore?
    private var commandsReady = false

    private var chapter: AudioChapter? {
        guard let p = pack, let c = current else { return nil }
        return p.chapters["\(c.book).\(c.chapter)"]
    }

    // MARK: - Модули записей

    private func loadPack(_ store: ModuleStore, _ id: String) async -> AudioPack? {
        if let p = packs[id] { return p }
        guard let raw = store.db(id)?.query("SELECT json FROM payload", [], { $0.text(0) }).first else { return nil }
        let p = await Task.detached(priority: .userInitiated) { AudioPack.parse(raw) }.value
        if let p { packs[id] = p }
        return p
    }

    func forget(_ id: String) { packs.removeValue(forKey: id) }

    func audioModules(_ store: ModuleStore) -> [InstalledModule] {
        store.installed.filter { $0.type == "audio" }
    }

    func allPacks(_ store: ModuleStore) async -> [AudioPack] {
        var out: [AudioPack] = []
        for m in audioModules(store) {
            if let p = await loadPack(store, m.id) { out.append(p) }
        }
        return out
    }

    // MARK: - Запуск

    /// Слушать с этого места: запись, подходящая к переводу moduleId (иначе любая, где есть глава)
    func listen(store: ModuleStore, moduleId: String, from place: Place) async {
        self.store = store
        var fits: [AudioPack] = []
        var other: [AudioPack] = []
        for p in await allPacks(store) where p.has(place.book, place.chapter) {
            if audioFits(p.translation, moduleId) { fits.append(p) } else { other.append(p) }
        }
        // «Озвучка следует за переводом» (по умолчанию): запись другого перевода не подставляем
        let follows = UserDefaults.standard.object(forKey: "audioFollowsTranslation") as? Bool ?? true
        guard let pick = fits.first ?? (follows ? nil : other.first) else {
            message = "Для этой главы нет аудиозаписи."
            return
        }
        self.moduleId = moduleId
        textModule = moduleId
        pack = pick
        active = true
        play(book: place.book, chapter: place.chapter, verse: max(1, place.verse))
    }

    private func setupSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio)
        try? s.setActive(true)
        guard !commandsReady else { return }
        commandsReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextVerse() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousVerse() }
            return .success
        }
    }

    private func play(book: String, chapter c: Int, verse: Int) {
        guard let pk = pack, let ch = pk.chapters["\(book).\(c)"] else { return }
        setupSession()
        current = Place(book: book, chapter: c, verse: verse)
        let source: URL
        if let local = OfflineAudio.localURL(ch.url) {
            source = local
        } else if let remote = URL(string: ch.url) {
            source = remote
        } else {
            return
        }
        stopObserving()
        let item = AVPlayerItem(url: source)
        let pl = AVPlayer(playerItem: item)
        player = pl
        let start = ch.startFor(verse)
        pl.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        pl.playImmediately(atRate: rate)
        playing = true
        observer = pl.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.nextChapter() }
        }
        updateNowPlaying()
    }

    private func stopObserving() {
        if let o = observer { player?.removeTimeObserver(o) }
        observer = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
    }

    private func tick(_ sec: Double) {
        position = sec
        if let item = player?.currentItem {
            let d = item.duration.seconds
            if d.isFinite { duration = d }
        }
        if let ch = chapter {
            let start = ch.start ?? 0
            let end = ch.end ?? duration
            chapterPos = max(0, sec - start)
            chapterDur = max(0, end - start)
        } else {
            chapterPos = sec
            chapterDur = duration
        }
        guard let ch = chapter, var cur = current else { return }
        if let end = ch.end, sec >= end {
            nextChapter()
            return
        }
        if let v = ch.verseAt(sec), v != cur.verse {
            cur.verse = v
            current = cur
            updateNowPlaying()
        }
    }

    // MARK: - Управление

    func pause() {
        player?.pause()
        playing = false
        updateNowPlaying()
    }

    func resume() {
        guard player != nil else { return }
        player?.playImmediately(atRate: rate)
        playing = true
        updateNowPlaying()
    }

    func toggle() {
        playing ? pause() : resume()
    }

    func stop() {
        player?.pause()
        stopObserving()
        player = nil
        playing = false
        active = false
        current = nil
        sleepTask?.cancel()
        sleepLeft = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Другая запись (язык чтеца) — с того же стиха
    func switchPack(_ p: AudioPack) {
        guard let c = current, p.has(c.book, c.chapter) else { return }
        pack = p
        play(book: c.book, chapter: c.chapter, verse: c.verse)
    }

    /// Перемотка: sec — секунды внутри главы
    func seek(to sec: Double) {
        let file = sec + (chapter?.start ?? 0)
        player?.seek(to: CMTime(seconds: file, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = file
        chapterPos = sec
    }

    func seekVerse(_ verse: Int) {
        guard let c = current else { return }
        play(book: c.book, chapter: c.chapter, verse: verse)
    }

    func nextVerse() {
        guard let ch = chapter, let cur = current else { return }
        if let n = ch.verses.map({ $0.0 }).sorted().first(where: { $0 > cur.verse }) {
            if ch.shared, let t = ch.verses.first(where: { $0.0 == n })?.1 {
                player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                current?.verse = n
            } else {
                seekWithin(ch, n)
            }
        } else {
            nextChapter()
        }
    }

    func previousVerse() {
        guard let ch = chapter, let cur = current else { return }
        let nums = ch.verses.map { $0.0 }.sorted()
        // в начале стиха (первые секунды) — предыдущий, иначе — повтор этого
        let startOfCur = ch.startFor(cur.verse)
        let target: Int
        if position - startOfCur > 2 {
            target = cur.verse
        } else if let p = nums.last(where: { $0 < cur.verse }) {
            target = p
        } else {
            previousChapter()
            return
        }
        seekWithin(ch, target)
    }

    private func seekWithin(_ ch: AudioChapter, _ verse: Int) {
        player?.seek(to: CMTime(seconds: ch.startFor(verse), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        current?.verse = verse
        updateNowPlaying()
    }

    private func neighbour(_ delta: Int) -> Place? {
        guard let cur = current, let store, let m = store.module(moduleId), let bi = m.books.firstIndex(where: { $0.id == cur.book }) else { return nil }
        var c = cur.chapter + delta
        var b = bi
        if c < 1 {
            guard b > 0 else { return nil }
            b -= 1
            c = m.books[b].chapters
        } else if c > m.books[bi].chapters {
            guard b < m.books.count - 1 else { return nil }
            b += 1
            c = 1
        }
        return Place(book: m.books[b].id, chapter: c, verse: 1)
    }

    func nextChapter() {
        // таймер сна «До конца главы»: глава закончилась — останавливаемся
        if sleepAtChapterEnd {
            sleepAtChapterEnd = false
            stop()
            return
        }
        if let p = neighbour(1), pack?.has(p.book, p.chapter) == true {
            play(book: p.book, chapter: p.chapter, verse: 1)
        } else {
            stop()
        }
    }

    func previousChapter() {
        if let p = neighbour(-1), pack?.has(p.book, p.chapter) == true {
            let last = pack?.chapters["\(p.book).\(p.chapter)"]?.verses.map { $0.0 }.max() ?? 1
            play(book: p.book, chapter: p.chapter, verse: last)
        }
    }

    // MARK: - Таймер сна

    /// Таймер сна «До конца главы»
    func setSleepAtChapterEnd() {
        sleepTask?.cancel()
        sleepLeft = nil
        sleepAtChapterEnd = true
    }

    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepAtChapterEnd = false
        guard let m = minutes else {
            sleepLeft = nil
            return
        }
        sleepLeft = m * 60
        sleepTask = Task {
            while !Task.isCancelled, let left = sleepLeft, left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                sleepLeft = (sleepLeft ?? 1) - 1
            }
            if !Task.isCancelled {
                pause()
                sleepLeft = nil
            }
        }
    }

    // MARK: - Экран блокировки

    /// Обложка для острова и экрана блокировки: значок книги на цвете приложения
    private static let artwork: MPMediaItemArtwork = {
        let size = CGSize(width: 512, height: 512)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.42, green: 0.31, blue: 0.86, alpha: 1).cgColor, UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let cfg = UIImage.SymbolConfiguration(pointSize: 250, weight: .semibold)
            if let sym = UIImage(systemName: "book.fill", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let r = CGRect(x: (size.width - sym.size.width) / 2, y: (size.height - sym.size.height) / 2, width: sym.size.width, height: sym.size.height)
                sym.draw(in: r)
            }
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in img }
    }()

    private func updateNowPlaying() {
        guard let c = current, let pk = pack else { return }
        let name = Books.info(c.book)?.name ?? c.book
        var info: [String: Any] = [
            // название: «От Матфея 1:10»; ниже — кто читает; альбом — перевод и глава (виден на экране блокировки)
            MPMediaItemPropertyTitle: "\(name) \(c.chapter):\(c.verse)",
            MPMediaItemPropertyArtist: pk.reader ?? pk.name,
            MPMediaItemPropertyAlbumTitle: "\(name) \(c.chapter) · AO Bible",
            MPMediaItemPropertyArtwork: Self.artwork,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: chapterPos,
        ]
        if chapterDur > 0 { info[MPMediaItemPropertyPlaybackDuration] = chapterDur }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
