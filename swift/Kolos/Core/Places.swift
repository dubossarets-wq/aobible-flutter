import Foundation
import SQLite3

/// Библейское место: название, координаты, современное отождествление, описание и стихи, где оно упомянуто
struct BiblePlace: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let type: String
    let confidence: Int?
    let modern: String
    let descr: String
    let stems: [String]
    let refs: [String]
    let moduleName: String
    let license: String
}

/// Карта-картинка из модуля карт (Wikimedia Commons)
struct MapImage: Identifiable, Hashable {
    let id: String
    let title: String
    let descr: String
    let image: String
    let refs: [String]

    var url: URL? {
        image.hasPrefix("http") ? URL(string: image) : URL(string: Net.bases[0] + image)
    }
}

private var placeNameCache: [String: [(String, String)]] = [:]

extension ModuleStore {
    /// Модули с таблицей мест
    var placeModules: [InstalledModule] {
        installed.filter { m in
            m.type == "maps" && !(db(m.id)?.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='places'") { $0.int(0) }.isEmpty ?? true)
        }
    }

    private func place(_ r: Row, _ m: InstalledModule) -> BiblePlace {
        func arr(_ s: String) -> [String] {
            guard let d = s.data(using: .utf8), let a = (try? JSONSerialization.jsonObject(with: d)) as? [String] else { return [] }
            return a
        }
        return BiblePlace(
            id: r.text(0), name: r.text(1), lat: sqlite3_column_double(r.stmt, 2), lng: sqlite3_column_double(r.stmt, 3),
            type: r.text(4), confidence: r.int(5) > 0 ? r.int(5) : nil, modern: r.text(6), descr: r.text(7),
            stems: arr(r.text(8)), refs: arr(r.text(9)), moduleName: m.name, license: m.license
        )
    }

    private static let placeCols = "id, name, lat, lng, type, confidence, modern, descr, stems, refs"

    /// Места, упомянутые в стихе
    func placesIn(book: String, chapter: Int, verse: Int) -> [BiblePlace] {
        var out: [BiblePlace] = []
        for m in placeModules {
            guard let d = db(m.id) else { continue }
            out.append(contentsOf: d.query("SELECT p.id, p.name, p.lat, p.lng, p.type, p.confidence, p.modern, p.descr, p.stems, p.refs FROM place_refs r JOIN places p ON p.id = r.place_id WHERE r.ref = ?", ["\(book).\(chapter).\(verse)"]) { place($0, m) })
        }
        return out
    }

    /// Места, о которых говорит нажатое слово этого стиха: слово начинается с основы названия
    func placesFor(word: String, book: String, chapter: Int, verse: Int) -> [BiblePlace] {
        let w = Lexicon.normalizeWord(word)
        guard !w.isEmpty else { return [] }
        var seen = Set<String>()
        return placesIn(book: book, chapter: chapter, verse: verse).filter { p in
            p.stems.contains { w.hasPrefix($0) } && seen.insert(p.id).inserted
        }
    }

    /// Поиск по названию (подстрока)
    func searchPlaces(_ q: String, limit: Int = 50) -> [BiblePlace] {
        let query = Lexicon.normalizeWord(q.trimmingCharacters(in: .whitespaces))
        guard query.count >= 2 else { return [] }
        var out: [BiblePlace] = []
        for m in placeModules {
            guard let d = db(m.id) else { continue }
            let like = "%" + query.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "") + "%"
            out.append(contentsOf: d.query("SELECT \(Self.placeCols) FROM places WHERE name_norm LIKE ? ORDER BY ord LIMIT ?", [like, limit - out.count]) { place($0, m) })
            if out.count >= limit { break }
        }
        return out
    }

    /// «Возможно, вы искали»: названия, близкие к запросу (опечатка, лишняя или пропущенная буква, перестановка).
    /// Расстояние считается и до всего названия, и до его начала такой же длины — недописанное слово тоже подходит
    func suggestPlaces(_ q: String, limit: Int = 6) -> [BiblePlace] {
        let query = Array(Lexicon.normalizeWord(q.trimmingCharacters(in: .whitespaces)))
        guard query.count >= 3 else { return [] }
        let allowed = max(1, query.count / 3)
        var out: [BiblePlace] = []
        for m in placeModules {
            guard let d = db(m.id) else { continue }
            let names = Self.placeNames(m.id, d)
            var scored: [(score: Int, len: Int, id: String)] = []
            for (id, norm) in names {
                let n = Array(norm)
                if let s = Fuzzy.score(query, n, allowed: allowed) { scored.append((s, n.count, id)) }
            }
            scored.sort { $0.score != $1.score ? $0.score < $1.score : $0.len < $1.len }
            let ids = scored.prefix(limit - out.count).map(\.id)
            guard !ids.isEmpty else { continue }
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let found = d.query("SELECT \(Self.placeCols) FROM places WHERE id IN (\(marks))", ids) { place($0, m) }
            // в порядке близости
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            out.append(contentsOf: found.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) })
            if out.count >= limit { break }
        }
        return out
    }

    /// Названия мест модуля (нормализованные) — читаются один раз
    private static func placeNames(_ moduleId: String, _ d: SQLiteDB) -> [(String, String)] {
        if let c = placeNameCache[moduleId] { return c }
        let rows = d.query("SELECT id, name_norm FROM places") { ($0.text(0), $0.text(1)) }
        placeNameCache[moduleId] = rows
        return rows
    }

    /// Карты-картинки из установленных модулей карт
    func mapImages() -> [MapImage] {
        var out: [MapImage] = []
        for m in installed where m.type == "maps" {
            guard let raw = db(m.id)?.query("SELECT json FROM payload", [], { $0.text(0) }).first,
                  let d = raw.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let list = j["maps"] as? [[String: Any]] else { continue }
            for x in list {
                guard let id = x["id"] as? String, let image = x["image"] as? String else { continue }
                out.append(MapImage(id: m.id + "|" + id, title: x["title"] as? String ?? id, descr: x["description"] as? String ?? "", image: image, refs: (x["refs"] as? [String]) ?? []))
            }
        }
        return out
    }
}
