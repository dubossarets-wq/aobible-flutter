import Foundation
import SwiftUI

/// Ссылка OSIS: «Gen.1.1», «Gen.1.1-3», «Gen.1.1-2.3»
struct OsisRef {
    let book: String
    let chapter: Int
    let verse: Int
    var endChapter: Int?
    var endVerse: Int?

    init?(_ s: String) {
        let parts = s.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { return nil }
        let a = head.split(separator: ".").map(String.init)
        guard a.count >= 2, let c = Int(a[1]) else { return nil }
        let v = a.count > 2 ? Int(a[2]) : 1
        guard let vv = v else { return nil }
        book = a[0]
        chapter = c
        verse = vv
        if parts.count > 1 {
            let b = parts[1].split(separator: ".").map(String.init)
            if b.count == 1 {
                endChapter = c
                endVerse = Int(b[0])
            } else if b.count == 2 {
                endChapter = Int(b[0])
                endVerse = Int(b[1])
            } else if b.count >= 3 {
                endChapter = Int(b[1])
                endVerse = Int(b[2])
            }
        }
    }
}

struct DictHit: Identifiable, Hashable {
    let module: InstalledModule
    let key: String
    let word: String
    var id: String { module.id + "|" + key }
    static func == (a: DictHit, b: DictHit) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct BibleIllustration: Identifiable, Hashable {
    let img: String
    let thumb: String
    let title: String
    let author: String
    let year: String
    let license: String
    let src: String
    var id: String { img }
}

struct OtherEntry: Identifiable {
    let module: InstalledModule
    let entry: [String: Any]
    var id: String { module.id }
}

struct CommentaryItem: Identifiable {
    let id = UUID()
    let module: InstalledModule
    let title: String
    let text: String
}

extension ModuleStore {
    /// Словари: словарь Стронга на русском — первым, затем другие русские, затем остальные
    var dictionaries: [InstalledModule] {
        func rank(_ m: InstalledModule) -> Int {
            if m.dictionaryKind == "strongs" && m.language == "ru" { return 0 }
            return m.language == "ru" ? 1 : 2
        }
        return installed.filter { $0.type == "dictionary" }.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name
        }
    }

    var commentaries: [InstalledModule] {
        installed.filter { $0.type == "commentary" }
    }

    var crossrefModules: [InstalledModule] {
        installed.filter { $0.type == "crossrefs" }
    }

    func dictEntry(module m: InstalledModule, key: String) -> [String: Any]? {
        guard let d = db(m.id) else { return nil }
        let rows = d.query("SELECT json FROM dict WHERE key = ?", [key]) { $0.text(0) }
        guard let s = rows.first, let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Статьи, ключ которых начинается с основы слова
    func dictPrefix(module m: InstalledModule, prefix: String, limit: Int) -> [DictHit] {
        guard let d = db(m.id) else { return [] }
        let rows = d.query("SELECT key, word FROM dict WHERE key >= ? AND key < ? ORDER BY key LIMIT ?", [prefix, prefix + "\u{FFFF}", limit]) {
            (key: $0.text(0), word: $0.text(1))
        }
        return rows.map { DictHit(module: m, key: $0.key, word: $0.word) }
    }

    func commentary(book: String, chapter: Int, verse: Int) -> [CommentaryItem] {
        var out: [CommentaryItem] = []
        for m in commentaries {
            guard let d = db(m.id) else { continue }
            let rows = d.query("SELECT title, text FROM comm WHERE book = ? AND chapter = ? AND verse = ?", [book, chapter, verse]) {
                (title: $0.text(0), text: $0.text(1))
            }
            for r in rows {
                out.append(CommentaryItem(module: m, title: r.title, text: r.text))
            }
        }
        return out
    }

    /// Параллельные места стиха: из самого перевода, затем из модулей параллельных мест (без повторов)
    func xrefs(module: String, book: String, chapter: Int, verse: Int) -> [OsisRef] {
        var seen = Set<String>()
        var out: [OsisRef] = []
        func add(_ s: String) {
            if seen.insert(s).inserted, let r = OsisRef(s) { out.append(r) }
        }
        func read(_ json: String) {
            guard let data = json.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return }
            list.forEach(add)
        }
        if let d = db(module) {
            for s in d.query("SELECT refs FROM xrefs WHERE book = ? AND chapter = ? AND verse = ?", [book, chapter, verse], { $0.text(0) }) {
                read(s)
            }
        }
        for m in crossrefModules {
            guard let d = db(m.id) else { continue }
            for s in d.query("SELECT refs FROM xr WHERE book = ? AND chapter = ? AND verse = ?", [book, chapter, verse], { $0.text(0) }) {
                read(s)
            }
        }
        return out
    }

    /// Сколько параллельных мест у каждого стиха главы (для числа после стиха): из самого перевода и из модулей
    func xrefCounts(module: String, book: String, chapter: Int) -> [Int: Int] {
        var out: [Int: Int] = [:]
        if let d = db(module) {
            for (v, s) in d.query("SELECT verse, refs FROM xrefs WHERE book = ? AND chapter = ?", [book, chapter], { ($0.int(0), $0.text(1)) }) {
                if let data = s.data(using: .utf8), let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                    out[v, default: 0] += list.count
                }
            }
        }
        for m in crossrefModules {
            guard let d = db(m.id) else { continue }
            for (v, n) in d.query("SELECT verse, n FROM xr WHERE book = ? AND chapter = ?", [book, chapter], { ($0.int(0), $0.int(1)) }) {
                out[v, default: 0] += n
            }
        }
        return out
    }

    /// Сколько стихов в каждой главе книги: глава → число стихов
    func verseCounts(module: String, book: String) -> [Int: Int] {
        guard let d = db(module) else { return [:] }
        var out: [Int: Int] = [:]
        for (c, n) in d.query("SELECT chapter, MAX(verse) FROM verses WHERE book = ? GROUP BY chapter", [book], { ($0.int(0), $0.int(1)) }) {
            out[c] = n
        }
        return out
    }

    /// Сколько иллюстраций у каждого стиха главы
    func illustrationCounts(book: String, chapter: Int) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for m in installed where m.type == "illustrations" {
            guard let d = db(m.id) else { continue }
            for (v, s) in d.query("SELECT verse, json FROM illus WHERE book = ? AND chapter = ?", [book, chapter], { ($0.int(0), $0.text(1)) }) {
                if let data = s.data(using: .utf8), let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                    out[v, default: 0] += list.count
                }
            }
        }
        return out
    }

    /// Иллюстрации стиха
    func illustrations(book: String, chapter: Int, verse: Int) -> [BibleIllustration] {
        var out: [BibleIllustration] = []
        for m in installed where m.type == "illustrations" {
            guard let d = db(m.id) else { continue }
            for s in d.query("SELECT json FROM illus WHERE book = ? AND chapter = ? AND verse = ?", [book, chapter, verse], { $0.text(0) }) {
                guard let data = s.data(using: .utf8), let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
                for x in list {
                    guard let img = x["img"] as? String else { continue }
                    out.append(BibleIllustration(
                        img: img, thumb: x["thumb"] as? String ?? img, title: x["title"] as? String ?? "",
                        author: x["author"] as? String ?? "", year: x["year"] as? String ?? "",
                        license: x["license"] as? String ?? "", src: x["src"] as? String ?? ""
                    ))
                }
            }
        }
        return out
    }

    /// Статьи на то же слово в других словарях «по словам» (значения из других модулей)
    func otherEntries(key: String, excluding: String) -> [OtherEntry] {
        let keys = [Lexicon.dictKey(key), key.lowercased(), key]
        var out: [OtherEntry] = []
        for m in dictionaries where m.id != excluding && m.dictionaryKind != "strongs" {
            if let f = dictGetMany(module: m, keys: keys).first { out.append(OtherEntry(module: m, entry: f.1)) }
        }
        return out
    }

    /// Текст ссылки (до четырёх стихов диапазона)
    func refText(module: String, _ r: OsisRef) -> String {
        guard let endVerse = r.endVerse, (r.endChapter ?? r.chapter) == r.chapter, endVerse > r.verse else {
            return verseText(module: module, book: r.book, chapter: r.chapter, verse: r.verse) ?? ""
        }
        var parts: [String] = []
        for v in r.verse...min(endVerse, r.verse + 3) {
            if let t = verseText(module: module, book: r.book, chapter: r.chapter, verse: v) {
                parts.append(t)
            }
        }
        return parts.joined(separator: " ")
    }
}

extension InstalledModule {
    /// Короткое название для шапки панели — не длиннее 4 знаков
    var shortName: String {
        let known = ["rst-interlinear": "Подс", "vin-interlinear": "Вин", "rst-plus": "RST+", "byz-rp2018": "Byz", "oshb": "OSHB"]
        if let k = known[id] { return k }
        if name.count <= 4 { return name }
        let first = name.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == "—" || $0 == "-" }).first.map(String.init) ?? name
        return String(first.prefix(4))
    }
}
