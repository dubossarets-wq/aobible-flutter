import Foundation

struct BookInfo: Decodable, Identifiable, Hashable {
    let id: String
    /// Русские названия из справочника (по ним разбираются ссылки)
    let rawName: String
    let rawShort: String
    let t: String
    var dc: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, t, dc
        case rawName = "name"
        case rawShort = "short"
    }

    /// Названия на языке интерфейса (см. BookLocale)
    var name: String { BookLocale.name(id, rawName) }
    var short: String { BookLocale.short(id, rawShort) }
}

/// Список книг (порядок Библии) — тот же файл, что у Flutter-версии
enum Books {
    static let all: [BookInfo] = {
        guard let url = Bundle.main.url(forResource: "books", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([BookInfo].self, from: data) else { return [] }
        return list
    }()

    static func info(_ id: String) -> BookInfo? {
        all.first { $0.id == id }
    }
}
