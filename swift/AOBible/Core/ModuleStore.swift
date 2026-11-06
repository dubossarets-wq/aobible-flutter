import Compression
import Foundation
import SwiftUI

struct ModuleBook: Hashable, Identifiable {
    let id: String
    let name: String
    let short: String
    let chapters: Int
}

struct InstalledModule: Identifiable, Hashable {
    let id: String
    let name: String
    let title: String
    let language: String
    let type: String
    let path: String
    let books: [ModuleBook]
    /// Перевод по сети (без текста внутри файла) — пока не читается
    let online: Bool
}

struct CatalogEntry: Identifiable {
    let json: [String: Any]

    var id: String { json["id"] as? String ?? "" }
    var type: String { json["type"] as? String ?? "bible" }
    var name: String { json["name"] as? String ?? id }
    var title: String { json["title"] as? String ?? name }
    var language: String { json["language"] as? String ?? "ru" }
    var version: String { json["version"].map { "\($0)" } ?? "" }
    var url: String? { json["url"] as? String }
    var urlGz: String? { json["urlGz"] as? String }
    var size: Int { (json["sizeGz"] as? Int) ?? (json["size"] as? Int) ?? 0 }
    /// Можно скачать целиком одним файлом (без переводов по сети и из сторонних источников)
    var downloadable: Bool {
        json["online"] == nil && json["helloao"] == nil && json["unavailable"] as? Bool != true && (url != nil || urlGz != nil)
    }
}

struct Verse: Identifiable {
    let num: Int
    let text: String
    var id: Int { num }
}

enum ConvertError: Error {
    case format
}

/// Модули: те же файлы .db (SQLite), что и у Flutter-версии, — лежат в «Application Support/modules»
@MainActor
final class ModuleStore: ObservableObject {
    @Published private(set) var installed: [InstalledModule] = []
    @Published private(set) var catalog: [CatalogEntry] = []
    @Published var busy: [String: String] = [:]
    @Published var catalogLoading = false
    @Published var catalogError: String?

    let dir: URL
    private var opened: [String: SQLiteDB] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scan()
    }

    var bibles: [InstalledModule] {
        installed.filter { $0.type == "bible" && !$0.online }
    }

    func module(_ id: String) -> InstalledModule? {
        installed.first { $0.id == id }
    }

    // MARK: - Установленные

    func scan() {
        opened.removeAll()
        var list: [InstalledModule] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "db" {
            guard let db = try? SQLiteDB(path: f.path, readOnly: true) else { continue }
            let raw = db.query("SELECT value FROM meta WHERE key = 'json'") { $0.text(0) }
            guard let s = raw.first,
                  let data = s.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = j["id"] as? String else { continue }
            let list2 = (j["bookList"] as? [[String: Any]]) ?? []
            let books = list2.map { b in
                ModuleBook(
                    id: b["id"] as? String ?? "",
                    name: b["name"] as? String ?? "",
                    short: b["short"] as? String ?? "",
                    chapters: b["chapters"] as? Int ?? 0
                )
            }
            let name = j["name"] as? String ?? id
            list.append(InstalledModule(
                id: id,
                name: name,
                title: j["title"] as? String ?? name,
                language: j["language"] as? String ?? "ru",
                type: j["type"] as? String ?? "bible",
                path: f.path,
                books: books,
                online: j["online"] != nil
            ))
        }
        installed = list.sorted {
            let a = $0.language == "ru" ? 0 : 1
            let b = $1.language == "ru" ? 0 : 1
            return a != b ? a < b : $0.name < $1.name
        }
    }

    private func db(_ id: String) -> SQLiteDB? {
        if let d = opened[id] { return d }
        guard let m = module(id), let d = try? SQLiteDB(path: m.path, readOnly: true) else { return nil }
        opened[id] = d
        return d
    }

    func verses(module: String, book: String, chapter: Int) -> [Verse] {
        guard let d = db(module) else { return [] }
        return d.query("SELECT verse, text FROM verses WHERE book = ? AND chapter = ? ORDER BY verse", [book, chapter]) {
            Verse(num: $0.int(0), text: $0.text(1))
        }
    }

    func headings(module: String, book: String, chapter: Int) -> [Int: String] {
        guard let d = db(module) else { return [:] }
        var out: [Int: String] = [:]
        for (v, t) in d.query("SELECT verse, text FROM headings WHERE book = ? AND chapter = ?", [book, chapter], { ($0.int(0), $0.text(1)) }) {
            out[v] = t
        }
        return out
    }

    func verseText(module: String, book: String, chapter: Int, verse: Int) -> String? {
        guard let d = db(module) else { return nil }
        let rows = d.query("SELECT text FROM verses WHERE book = ? AND chapter = ? AND verse = ?", [book, chapter, verse]) { $0.text(0) }
        return rows.first.map { Markup.plain($0) }
    }

    func remove(_ id: String) {
        opened[id] = nil
        if let m = module(id) {
            try? FileManager.default.removeItem(atPath: m.path)
        }
        scan()
    }

    // MARK: - Каталог и установка

    private let bases = ["https://aobible.app/", "https://dubossarets-wq.github.io/ao-bible/"]

    private func fetch(_ path: String) async throws -> Data {
        var lastError: Error = ConvertError.format
        for base in bases {
            guard let url = URL(string: base + path) else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 60
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return data
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func loadCatalog() async {
        catalogLoading = true
        catalogError = nil
        defer { catalogLoading = false }
        do {
            let data = try await fetch("modules/catalog.json")
            guard let j = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let list = j["modules"] as? [[String: Any]] else { throw ConvertError.format }
            catalog = list.map { CatalogEntry(json: $0) }
        } catch {
            catalogError = "Не удалось загрузить каталог. Проверьте интернет."
        }
    }

    func install(_ e: CatalogEntry) async {
        busy[e.id] = "Загрузка…"
        defer { busy[e.id] = nil }
        do {
            let gz = e.urlGz != nil
            guard let path = e.urlGz ?? e.url else { return }
            let data = try await fetch("modules/" + path)
            busy[e.id] = "Подготовка…"
            let id = e.id
            let version = e.version
            let target = dir.appendingPathComponent("\(id).db")
            opened[id] = nil
            try await Task.detached(priority: .userInitiated) {
                let raw = gz ? try Gzip.decode(data) : data
                try ModuleConverter.convert(json: raw, to: target, catalogVersion: version)
            }.value
            scan()
        } catch {
            catalogError = "Не удалось установить «\(e.name)»."
        }
    }
}

// MARK: - gzip

enum Gzip {
    /// Распаковка .gz: заголовок снимаем сами, дальше — системный deflate
    static func decode(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b else { throw ConvertError.format }
        let flags = b[3]
        var pos = 10
        if flags & 4 != 0 {
            let xlen = Int(b[pos]) | (Int(b[pos + 1]) << 8)
            pos += 2 + xlen
        }
        if flags & 8 != 0 {
            while pos < b.count && b[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 16 != 0 {
            while pos < b.count && b[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 2 != 0 { pos += 2 }
        guard pos < b.count - 8 else { throw ConvertError.format }
        let body = Data(b[pos..<(b.count - 8)]) as NSData
        let out = try body.decompressed(using: .zlib)
        return out as Data
    }
}

// MARK: - JSON модуля → SQLite (тот же формат, что у Flutter-версии)

enum ModuleConverter {
    static func convert(json: Data, to target: URL, catalogVersion: String) throws {
        guard let j = (try JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let books = j["books"] as? [[String: Any]] else { throw ConvertError.format }
        let tmp = target.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: tmp)

        do {
            let db = try SQLiteDB(path: tmp.path, readOnly: false)
            try db.exec("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; BEGIN;")
            try db.exec("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)")

            var meta = j
            for k in ["books", "entries", "refs", "places", "wordIndex", "chapters"] {
                meta.removeValue(forKey: k)
            }
            if !catalogVersion.isEmpty { meta["catalogVersion"] = catalogVersion }
            meta["bookList"] = books.map { b -> [String: Any] in
                [
                    "id": b["id"] ?? "",
                    "name": b["name"] ?? "",
                    "short": b["short"] ?? "",
                    "chapters": (b["chapters"] as? [Any])?.count ?? 0,
                ]
            }

            try db.exec("""
                CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
                CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
                CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
            """)
            let hasFTS = (try? db.exec("CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2')")) != nil

            var vrows: [[Any]] = []
            var frows: [[Any]] = []
            var hrows: [[Any]] = []
            var xrows: [[Any]] = []
            var id = 0
            for b in books {
                let bid = b["id"] as? String ?? ""
                let chapters = b["chapters"] as? [[Any]] ?? []
                for (ci, ch) in chapters.enumerated() {
                    for (vi, v) in ch.enumerated() {
                        guard let raw = v as? String, !raw.isEmpty else { continue }
                        id += 1
                        vrows.append([id, bid, ci + 1, vi + 1, raw])
                        frows.append([id, Markup.plain(raw)])
                    }
                }
                if let h = b["headings"] as? [String: Any] {
                    for (k, t) in h {
                        let p = k.split(separator: ":")
                        if p.count == 2, let c = Int(p[0]), let v = Int(p[1]), let txt = t as? String {
                            hrows.append([bid, c, v, txt])
                        }
                    }
                }
                if let x = b["xrefs"] as? [String: Any] {
                    for (k, refs) in x {
                        let p = k.split(separator: ":")
                        if p.count == 2, let c = Int(p[0]), let v = Int(p[1]),
                           JSONSerialization.isValidJSONObject(refs),
                           let d = try? JSONSerialization.data(withJSONObject: refs),
                           let s = String(data: d, encoding: .utf8) {
                            xrows.append([bid, c, v, s])
                        }
                    }
                }
            }
            try db.insert("INSERT INTO verses VALUES (?, ?, ?, ?, ?)", vrows)
            if hasFTS { try db.insert("INSERT INTO verses_fts(rowid, plain) VALUES (?, ?)", frows) }
            try db.insert("INSERT INTO headings VALUES (?, ?, ?, ?)", hrows)
            try db.insert("INSERT INTO xrefs VALUES (?, ?, ?, ?)", xrows)
            try db.exec("CREATE INDEX verses_ref ON verses(book, chapter, verse); CREATE INDEX headings_ref ON headings(book, chapter, verse);")

            let metaData = try JSONSerialization.data(withJSONObject: meta)
            try db.insert("INSERT INTO meta VALUES (?, ?)", [["json", String(data: metaData, encoding: .utf8) ?? "{}"]])
            try db.exec("COMMIT")
        }

        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
