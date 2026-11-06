import Foundation
import SwiftUI

/// Блок проповеди: стих (с текстом на момент добавления), свой текст или заметка для себя (в «Поделиться» не уходит)
struct SermonBlock: Codable, Identifiable, Hashable {
    var id: String
    var type: String // verse | text | note
    var book: String?
    var chapter: Int?
    var verse: Int?
    var to: Int?
    var text: String
    var texts: [String]?
    var moduleId: String?
    var part: Bool?
    var alt: [Alt]?

    struct Alt: Codable, Hashable {
        var m: String?
        var n: String?
        var t: [String]?
        var il: Bool?
    }

    var isVerse: Bool { type == "verse" }

    init(id: String = SermonStore.newId(), type: String, book: String? = nil, chapter: Int? = nil, verse: Int? = nil, to: Int? = nil, text: String, texts: [String]? = nil, moduleId: String? = nil, part: Bool? = nil, alt: [Alt]? = nil) {
        self.id = id
        self.type = type
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.to = to
        self.text = text
        self.texts = texts
        self.moduleId = moduleId
        self.part = part
        self.alt = alt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, book, chapter, verse, to, text, texts, moduleId, part, alt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? SermonStore.newId()
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        book = try c.decodeIfPresent(String.self, forKey: .book)
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter)
        verse = try c.decodeIfPresent(Int.self, forKey: .verse)
        to = try c.decodeIfPresent(Int.self, forKey: .to)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        texts = try c.decodeIfPresent([String].self, forKey: .texts)
        moduleId = try c.decodeIfPresent(String.self, forKey: .moduleId)
        part = try c.decodeIfPresent(Bool.self, forKey: .part)
        alt = try c.decodeIfPresent([Alt].self, forKey: .alt)
    }
}

struct Sermon: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var series: String?
    var date: String?
    var blocks: [SermonBlock]
    var createdAt: Double?
    var updatedAt: Double?

    init(title: String) {
        id = SermonStore.newId()
        self.title = title
        subtitle = nil
        series = nil
        date = PlanLogic.localDate()
        blocks = []
        let now = Date().timeIntervalSince1970 * 1000
        createdAt = now
        updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, series, date, blocks, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? SermonStore.newId()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        series = try c.decodeIfPresent(String.self, forKey: .series)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        blocks = try c.decodeIfPresent([SermonBlock].self, forKey: .blocks) ?? []
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
    }
}

/// Что добавляется в проповедь: стих (текст уже известен)
struct VerseItem {
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
    var moduleId: String? = nil
    var part = false
}

/// Проповеди: тот же формат, что в веб-версии; файл «sermons.json»; если его нет, но есть проповеди Flutter-версии
/// (тот же контейнер), они подхватываются
@MainActor
final class SermonStore: ObservableObject {
    @Published private(set) var sermons: [Sermon] = []
    private let url: URL
    nonisolated(unsafe) private static var seq = 0

    nonisolated static func newId() -> String {
        seq += 1
        return String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(seq, radix: 36)
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("sermons.json")
        if let d = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Sermon].self, from: d) {
            sermons = list
        } else if let s = UserDefaults.standard.string(forKey: "flutter.sermons"),
                  let d = s.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Sermon].self, from: d) {
            sermons = list
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(sermons) { try? d.write(to: url, options: .atomic) }
    }

    func exportEntry() -> String {
        String(data: (try? JSONEncoder().encode(sermons)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    func importEntry(_ s: String?) {
        if let s, let d = s.data(using: .utf8), let list = try? JSONDecoder().decode([Sermon].self, from: d) {
            sermons = list
        } else {
            sermons = []
        }
        save()
    }

    func get(_ id: String) -> Sermon? {
        sermons.first { $0.id == id }
    }

    func upsert(_ s: Sermon) {
        var x = s
        x.updatedAt = Date().timeIntervalSince1970 * 1000
        if let i = sermons.firstIndex(where: { $0.id == x.id }) {
            sermons[i] = x
        } else {
            sermons.insert(x, at: 0)
        }
        save()
    }

    func remove(_ id: String) {
        sermons.removeAll { $0.id == id }
        save()
    }

    func create(_ title: String) -> Sermon {
        let s = Sermon(title: title)
        upsert(s)
        return s
    }

    /// Выделенные стихи → блоки: стихи подряд одной главы складываются в один блок «Ин 3:16–18»
    static func versesToBlocks(_ items: [VerseItem], moduleId: String) -> [SermonBlock] {
        var blocks: [SermonBlock] = []
        for it in items {
            if !it.part, var last = blocks.last, last.part != true, last.book == it.book, last.chapter == it.chapter,
               (last.to ?? last.verse ?? 0) + 1 == it.verse {
                last.to = it.verse
                last.texts = (last.texts ?? [last.text]) + [it.text]
                last.text = last.text + " " + it.text
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(SermonBlock(type: "verse", book: it.book, chapter: it.chapter, verse: it.verse, to: nil, text: it.text, moduleId: it.moduleId ?? moduleId, part: it.part ? true : nil))
            }
        }
        return blocks
    }

    func addVerses(to id: String, items: [VerseItem], moduleId: String) {
        guard var s = get(id) else { return }
        s.blocks.append(contentsOf: Self.versesToBlocks(items, moduleId: moduleId))
        upsert(s)
    }

    // MARK: - Текст проповеди

    static func shortBook(_ id: String) -> String {
        var s = Books.info(id)?.short ?? id
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func ref(_ b: SermonBlock, full: Bool = false) -> String {
        guard let book = b.book, let c = b.chapter, let v = b.verse else { return "" }
        let name = full ? (Books.info(book)?.name ?? book) : shortBook(book)
        let to = b.to.map { "–\($0)" } ?? ""
        let part = b.part == true ? " (часть)" : ""
        return "\(name) \(c):\(v)\(to)\(part)"
    }

    /// Текст блока по стихам: [текст 16, текст 17, …]; nil — у старого блока-диапазона разбивки ещё нет
    static func verseTexts(_ b: SermonBlock) -> [String]? {
        guard b.isVerse, let v = b.verse else { return nil }
        guard let to = b.to, to != v else { return [b.text] }
        if let t = b.texts, t.count == to - v + 1 { return t }
        return nil
    }

    private static let fmtRe = try! NSRegularExpression(pattern: "\\*\\*([^*\\n]+)\\*\\*|\\*([^*\\n]+)\\*")

    /// Свой текст: **жирный**, *курсив* → AttributedString
    static func formatted(_ text: String) -> AttributedString {
        var out = AttributedString()
        let ns = text as NSString
        var at = 0
        for m in fmtRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > at {
                out += AttributedString(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            }
            if m.range(at: 1).location != NSNotFound {
                var s = AttributedString(ns.substring(with: m.range(at: 1)))
                s.inlinePresentationIntent = .stronglyEmphasized
                out += s
            } else {
                var s = AttributedString(ns.substring(with: m.range(at: 2)))
                s.inlinePresentationIntent = .emphasized
                out += s
            }
            at = m.range.location + m.range.length
        }
        if at < ns.length { out += AttributedString(ns.substring(from: at)) }
        return out
    }

    static func plainFmt(_ text: String) -> String {
        String(formatted(text).characters)
    }

    static func dayText(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: PlanLogic.day0(s))
    }

    /// Проповедь обычным текстом — чтобы отправить или распечатать
    static func text(_ s: Sermon) -> String {
        var parts: [String] = [s.title]
        if let sub = s.subtitle?.trimmingCharacters(in: .whitespaces), !sub.isEmpty { parts.append(sub) }
        if let d = dayText(s.date) { parts.append(d) }
        for b in s.blocks {
            if b.isVerse {
                let tx = verseTexts(b)
                let body: String
                if let tx, tx.count > 1, let v = b.verse {
                    body = tx.enumerated().map { "\(v + $0.offset) \($0.element)" }.joined(separator: "\n")
                } else {
                    body = b.text
                }
                parts.append("\(ref(b, full: true))\n«\(body)»")
                for a in b.alt ?? [] {
                    let at = (a.t ?? []).map { a.il == true ? Markup.plain($0) : $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    if !at.isEmpty { parts.append("\(a.n ?? ""): «\(at)»") }
                }
            } else if b.type != "note", !b.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(plainFmt(b.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
