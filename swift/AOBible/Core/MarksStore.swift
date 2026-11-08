import Foundation
import SwiftUI

/// Цвета выделения (оттенки Okabe–Ito, как в веб-версии и во Flutter): id «1»…«6»
struct HlColor: Identifiable {
    let id: String
    let name: String
    let color: Color
}

let hlColors: [HlColor] = [
    HlColor(id: "1", name: "Жёлтый", color: Color(hex: 0xf3d36b)),
    HlColor(id: "2", name: "Голубой", color: Color(hex: 0x7fc4ec)),
    HlColor(id: "3", name: "Зелёный", color: Color(hex: 0x7ccfa4)),
    HlColor(id: "4", name: "Оранжевый", color: Color(hex: 0xf2a65a)),
    HlColor(id: "5", name: "Розовый", color: Color(hex: 0xe79ac0)),
    HlColor(id: "6", name: "Сиреневый", color: Color(hex: 0xb7a3e3)),
]

func hlColor(_ id: String?) -> HlColor? {
    hlColors.first { $0.id == id }
}

/// Часть стиха: номера слов от и до
struct Part: Codable, Hashable {
    var from: Int
    var to: Int
}

/// Закладка или любимый стих: {book, chapter, verse, text, at}
struct MarkItem: Codable, Identifiable, Hashable {
    var book: String
    var chapter: Int
    var verse: Int
    var text: String
    var at: Double
    var part: Part?
    var id: String { "\(book).\(chapter).\(verse)" }

    init(book: String, chapter: Int, verse: Int, text: String, part: Part? = nil) {
        self.part = part
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
        self.at = Date().timeIntervalSince1970 * 1000
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book = try c.decodeIfPresent(String.self, forKey: .book) ?? ""
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter) ?? 1
        verse = try c.decodeIfPresent(Int.self, forKey: .verse) ?? 1
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        part = try? c.decodeIfPresent(Part.self, forKey: .part)
    }
}

/// Заметка: {text, label, at, updated}
struct NoteEntry: Codable, Hashable {
    var text: String
    var label: String?
    var at: Double?
    var updated: Double?

    init(text: String) {
        self.text = text
        let now = Date().timeIntervalSince1970 * 1000
        at = now
        updated = now
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label)
        at = try c.decodeIfPresent(Double.self, forKey: .at)
        updated = try c.decodeIfPresent(Double.self, forKey: .updated)
    }
}

struct MarksData: Codable {
    var bookmarks: [MarkItem] = []
    var favorites: [MarkItem] = []
    var notes: [String: NoteEntry] = [:]
    var highlights: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookmarks = (try? c.decodeIfPresent([MarkItem].self, forKey: .bookmarks)) ?? []
        favorites = (try? c.decodeIfPresent([MarkItem].self, forKey: .favorites)) ?? []
        notes = (try? c.decodeIfPresent([String: NoteEntry].self, forKey: .notes)) ?? [:]
        highlights = (try? c.decodeIfPresent([String: String].self, forKey: .highlights)) ?? [:]
    }
}

/// Закладки, любимые стихи, заметки и подсветка — в том же формате, что в веб-версии и во Flutter-версии:
/// файл «Мои данные» открывается в любой из них. Хранятся файлом «marks.json»; если его нет, но есть данные
/// Flutter-версии (тот же контейнер), они подхватываются
@MainActor
final class MarksStore: ObservableObject {
    @Published private(set) var data = MarksData()
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("marks.json")
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(MarksData.self, from: d) {
            data = m
        } else {
            let ud = UserDefaults.standard
            var m = MarksData()
            func dec<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
                guard let s = ud.string(forKey: "flutter." + key), let d = s.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(type, from: d)
            }
            m.bookmarks = dec("bookmarks", [MarkItem].self) ?? []
            m.favorites = dec("favorites", [MarkItem].self) ?? []
            m.notes = dec("notes", [String: NoteEntry].self) ?? [:]
            m.highlights = dec("highlights", [String: String].self) ?? [:]
            data = m
        }
    }

    static func key(_ book: String, _ chapter: Int, _ verse: Int) -> String {
        "\(book).\(chapter).\(verse)"
    }

    // MARK: - Подсветка

    func highlight(_ key: String) -> String? {
        data.highlights[key]
    }

    func setHighlight(keys: [String], color: String?) {
        for k in keys {
            if let c = color { data.highlights[k] = c } else { data.highlights.removeValue(forKey: k) }
        }
        save()
    }

    // MARK: - Закладки

    func isBookmarked(_ book: String, _ chapter: Int, _ verse: Int) -> Bool {
        data.bookmarks.contains { $0.book == book && $0.chapter == chapter && $0.verse == verse }
    }

    func toggleBookmark(_ book: String, _ chapter: Int, _ verse: Int, text: String) {
        if let i = data.bookmarks.firstIndex(where: { $0.book == book && $0.chapter == chapter && $0.verse == verse }) {
            data.bookmarks.remove(at: i)
        } else {
            data.bookmarks.insert(MarkItem(book: book, chapter: chapter, verse: verse, text: text), at: 0)
        }
        save()
    }

    func removeBookmark(_ b: MarkItem) {
        data.bookmarks.removeAll { $0.id == b.id }
        save()
    }

    // MARK: - Любимые

    func isFavorite(_ key: String) -> Bool {
        data.favorites.contains { $0.id == key }
    }

    func toggleFavorite(_ book: String, _ chapter: Int, _ verse: Int, text: String, part: Part? = nil) {
        let key = Self.key(book, chapter, verse)
        if let i = data.favorites.firstIndex(where: { $0.id == key }) {
            data.favorites.remove(at: i)
        } else {
            data.favorites.insert(MarkItem(book: book, chapter: chapter, verse: verse, text: text, part: part), at: 0)
        }
        save()
    }

    func removeFavorite(_ key: String) {
        data.favorites.removeAll { $0.id == key }
        save()
    }

    // MARK: - Заметки

    func note(_ key: String) -> String? {
        data.notes[key]?.text
    }

    func setNote(_ key: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            data.notes.removeValue(forKey: key)
        } else if var e = data.notes[key] {
            e.text = t
            e.updated = Date().timeIntervalSince1970 * 1000
            data.notes[key] = e
        } else {
            data.notes[key] = NoteEntry(text: t)
        }
        save()
    }

    // MARK: - Файл «Мои данные»

    /// Ключи файла «Мои данные» (значения — строки JSON, как в localStorage веб-версии)
    func exportEntries() -> [String: String] {
        func js<T: Encodable>(_ v: T) -> String {
            String(data: (try? JSONEncoder().encode(v)) ?? Data("null".utf8), encoding: .utf8) ?? "null"
        }
        return [
            "bookmarks": js(data.bookmarks),
            "favorites": js(data.favorites),
            "notes": js(data.notes),
            "highlights": js(data.highlights),
        ]
    }

    func importEntries(_ d: [String: String]) {
        func dec<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
            guard let s = d[key], let x = s.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(type, from: x)
        }
        var m = MarksData()
        m.bookmarks = dec("bookmarks", [MarkItem].self) ?? []
        m.favorites = dec("favorites", [MarkItem].self) ?? []
        m.notes = dec("notes", [String: NoteEntry].self) ?? [:]
        m.highlights = dec("highlights", [String: String].self) ?? [:]
        data = m
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) {
            try? d.write(to: url, options: .atomic)
        }
    }
}

/// Открыть место в чтении (из поиска, закладок): ставит книгу, главу, стих и переключает на «Библию»
struct OpenVerse {
    var run: (String, Int, Int) -> Void = { _, _, _ in }

    func callAsFunction(_ book: String, _ chapter: Int, _ verse: Int) {
        run(book, chapter, verse)
    }
}

private struct OpenVerseKey: EnvironmentKey {
    static let defaultValue = OpenVerse()
}

extension EnvironmentValues {
    var openVerse: OpenVerse {
        get { self[OpenVerseKey.self] }
        set { self[OpenVerseKey.self] = newValue }
    }
}
