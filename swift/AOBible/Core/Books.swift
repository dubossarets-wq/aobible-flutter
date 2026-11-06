import Foundation

struct BookInfo: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let t: String
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
