import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Файл «Мои данные» — тот же формат, что у веб-версии и Flutter-версии:
/// {format: "aob-userdata", version: 1, exportedAt, data: {ключ: строка JSON}}.
/// Модули (переводы, словари) в файл не входят
struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupInfo: Identifiable {
    let at: Double
    let reason: String
    let entries: [String: String]
    var id: Double { at }
}

enum UserDataError: LocalizedError {
    case notData

    var errorDescription: String? {
        "Это не файл с данными AO Bible."
    }
}

enum UserData {
    static let format = "aob-userdata"

    /// Настройки, которые уходят в файл и возвращаются из него
    private static let settingKeys: [(String, String)] = [
        ("theme", "s"), ("fontFamily", "s"), ("fontSize", "d"), ("fontWeight", "d"), ("lineHeight", "d"),
        ("verseSpacing", "d"), ("showVerseNumbers", "b"), ("showStrongs", "b"), ("showHeadings", "b"),
        ("continuousVerses", "b"), ("showXrefs", "b"), ("textMargin", "d"), ("verseNumPos", "s"),
        ("syncScroll", "b"), ("panesStacked", "b"),
    ]

    static func settingsJSON() -> String {
        var j: [String: Any] = [:]
        let ud = UserDefaults.standard
        for (k, t) in settingKeys {
            guard let v = ud.object(forKey: k) else { continue }
            switch t {
            case "s": if let s = v as? String { j[k] = s }
            case "d": if let d = v as? Double { j[k] = d } else if let n = v as? NSNumber { j[k] = n.doubleValue }
            default: if let b = v as? Bool { j[k] = b }
            }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: j), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func applySettings(_ json: String) {
        guard let d = json.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        let ud = UserDefaults.standard
        for (k, t) in settingKeys {
            guard let v = j[k] else { continue }
            switch t {
            case "s": if let s = v as? String { ud.set(s, forKey: k) }
            case "d": if let n = v as? NSNumber { ud.set(n.doubleValue, forKey: k) }
            default: if let b = v as? Bool { ud.set(b, forKey: k) }
            }
        }
    }

    @MainActor
    static func collect(marks: MarksStore, plans: PlansStore, sermons: SermonStore) -> [String: String] {
        var e = marks.exportEntries()
        for (k, v) in plans.exportEntries() { e[k] = v }
        e["sermons"] = sermons.exportEntry()
        e["settings"] = settingsJSON()
        return e
    }

    @MainActor
    static func apply(_ entries: [String: String], marks: MarksStore, plans: PlansStore, sermons: SermonStore) {
        marks.importEntries(entries)
        plans.importEntries(entries)
        sermons.importEntry(entries["sermons"])
        if let s = entries["settings"] { applySettings(s) }
    }

    static func exportFile(_ entries: [String: String]) -> Data {
        let obj: [String: Any] = [
            "format": format,
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "data": entries,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])) ?? Data()
    }

    static func parse(_ data: Data) throws -> (entries: [String: String], at: Date?) {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              j["format"] as? String == format, let d = j["data"] as? [String: Any] else { throw UserDataError.notData }
        var entries: [String: String] = [:]
        for (k, v) in d {
            if let s = v as? String { entries[k] = s }
        }
        let at = (j["exportedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return (entries, at)
    }

    /// Сколько чего в данных — показать перед восстановлением
    static func counts(_ entries: [String: String]) -> [(String, Int)] {
        func count(_ key: String) -> Int {
            guard let s = entries[key], let d = s.data(using: .utf8), let v = try? JSONSerialization.jsonObject(with: d) else { return 0 }
            if let a = v as? [Any] { return a.count }
            if let m = v as? [String: Any] { return m.count }
            return 0
        }
        return [
            ("закладок", count("bookmarks")), ("заметок", count("notes")), ("любимых стихов", count("favorites")),
            ("выделений", count("highlights")), ("планов", count("plans")), ("проповедей", count("sermons")),
        ]
    }

    // MARK: - Резервные копии (последние 5)

    private static var backupsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("backups.json")
    }

    static func backups() -> [BackupInfo] {
        guard let d = try? Data(contentsOf: backupsURL),
              let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return list.compactMap { b in
            guard let at = (b["at"] as? NSNumber)?.doubleValue, let data = b["data"] as? [String: String] else { return nil }
            return BackupInfo(at: at, reason: b["reason"] as? String ?? "", entries: data)
        }
    }

    @MainActor
    static func snapshot(_ reason: String, marks: MarksStore, plans: PlansStore, sermons: SermonStore) {
        let entries = collect(marks: marks, plans: plans, sermons: sermons)
        var list: [[String: Any]] = [["at": Date().timeIntervalSince1970 * 1000, "reason": reason, "data": entries]]
        for b in backups().prefix(4) { list.append(["at": b.at, "reason": b.reason, "data": b.entries]) }
        // не больше ~1,5 млн символов: лишние старые копии отбрасываем
        while list.count > 1, ((try? JSONSerialization.data(withJSONObject: list))?.count ?? 0) > 1_500_000 {
            list.removeLast()
        }
        if let d = try? JSONSerialization.data(withJSONObject: list) { try? d.write(to: backupsURL, options: .atomic) }
    }
}
