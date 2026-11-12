import Foundation

/// Одно место в истории чтения: глава, стих, где остановился, и когда там был
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var book: String
    var chapter: Int
    var verse: Int
    /// Когда открыл это место
    var start: Date
    /// Когда был там последний раз (прокрутка внутри главы продлевает запись)
    var time: Date
}

/// История всех мест, где человек читал, с датой и временем (файл «history.json»). Каждая открытая глава — запись;
/// если в ту же главу вернулся в течение получаса, обновляется старая запись, а не появляется новая
@MainActor
final class ReadingHistory: ObservableObject {
    /// Старые в начале, новые в конце
    @Published private(set) var items: [HistoryEntry] = []
    private let url: URL
    private var saveTask: Task<Void, Never>?
    /// Сколько записей хранить
    private let limit = 5000
    /// В течение какого времени возврат в ту же главу считается тем же чтением
    private let merge: TimeInterval = 30 * 60

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        url = base.appendingPathComponent("history.json")
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        if let d = try? Data(contentsOf: url), let list = try? dec.decode([HistoryEntry].self, from: d) {
            items = list
        } else if let s = UserDefaults.standard.string(forKey: "flutter.readingHistory"), let d = s.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
            // установлено поверх Flutter-версии: её история ({b, c, v, s, t}, время в мс)
            items = list.compactMap { m in
                guard let b = m["b"] as? String, let c = (m["c"] as? NSNumber)?.intValue,
                      let t = (m["t"] as? NSNumber)?.doubleValue else { return nil }
                let v = (m["v"] as? NSNumber)?.intValue ?? 0
                let s = (m["s"] as? NSNumber)?.doubleValue ?? t
                return HistoryEntry(book: b, chapter: c, verse: v, start: Date(timeIntervalSince1970: s / 1000), time: Date(timeIntervalSince1970: t / 1000))
            }
        }
    }

    /// Человек сейчас в этом месте
    func record(_ book: String, _ chapter: Int, _ verse: Int) {
        let now = Date()
        // та же глава недавно — продлить ту запись и поднять её наверх
        var k = items.count - 1
        while k >= 0, now.timeIntervalSince(items[k].time) < merge {
            if items[k].book == book, items[k].chapter == chapter {
                var e = items.remove(at: k)
                if verse > 0 { e.verse = verse }
                e.time = now
                items.append(e)
                scheduleSave()
                return
            }
            k -= 1
        }
        items.append(HistoryEntry(book: book, chapter: chapter, verse: verse, start: now, time: now))
        if items.count > limit { items.removeFirst(items.count - limit) }
        scheduleSave()
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func restore(_ list: [HistoryEntry]) {
        items = (items + list).sorted { $0.time < $1.time }
        scheduleSave()
    }

    func clear() {
        items = []
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { save() }
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        if let d = try? enc.encode(items) { try? d.write(to: url, options: .atomic) }
    }
}
