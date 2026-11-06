import Foundation
import SwiftUI

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    let book: String
    let chapter: Int
    let verse: Int
    let date: Date
}

struct MarksData: Codable {
    var highlights: [String: Int] = [:]
    var notes: [String: String] = [:]
    var bookmarks: [Bookmark] = []
}

/// Цвета подсветки
let highlightColors: [Color] = [.yellow, .green, .blue, .pink, .orange]

/// Закладки, заметки и подсветка стихов — одним файлом в «Application Support»
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
        }
    }

    static func key(_ book: String, _ chapter: Int, _ verse: Int) -> String {
        "\(book).\(chapter).\(verse)"
    }

    func highlight(_ key: String) -> Int? {
        data.highlights[key]
    }

    func setHighlight(keys: [String], color: Int?) {
        for k in keys {
            if let c = color { data.highlights[k] = c } else { data.highlights.removeValue(forKey: k) }
        }
        save()
    }

    func isBookmarked(_ book: String, _ chapter: Int, _ verse: Int) -> Bool {
        data.bookmarks.contains { $0.book == book && $0.chapter == chapter && $0.verse == verse }
    }

    func toggleBookmark(_ book: String, _ chapter: Int, _ verse: Int) {
        if let i = data.bookmarks.firstIndex(where: { $0.book == book && $0.chapter == chapter && $0.verse == verse }) {
            data.bookmarks.remove(at: i)
        } else {
            data.bookmarks.insert(Bookmark(book: book, chapter: chapter, verse: verse, date: Date()), at: 0)
        }
        save()
    }

    func removeBookmark(_ b: Bookmark) {
        data.bookmarks.removeAll { $0.id == b.id }
        save()
    }

    func note(_ key: String) -> String? {
        data.notes[key]
    }

    func setNote(_ key: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { data.notes.removeValue(forKey: key) } else { data.notes[key] = t }
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
