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

    // MARK: - Чужие ключи файла (Flutter, веб): хранятся как есть и уходят в файл обратно, чтобы ничего не терялось

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
    private static var extraURL: URL { supportDir.appendingPathComponent("userdata_extra.json") }
    private static var settingsRawURL: URL { supportDir.appendingPathComponent("userdata_settings.json") }

    /// Ключи, которые Swift-версия разбирает сама
    private static let handledKeys: Set<String> = [
        "bookmarks", "favorites", "notes", "highlights", "highlightLabels", "collections", "plans", "readLog", "sermons", "settings",
    ]

    private static func loadExtra() -> [String: String] {
        guard let d = try? Data(contentsOf: extraURL), let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] else { return [:] }
        return m
    }

    private static func loadSettingsRaw() -> [String: Any] {
        guard let d = try? Data(contentsOf: settingsRawURL), let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return m
    }

    static func settingsJSON() -> String {
        // начинаем с настроек, какими их принесли из файла (ключи, которых Swift не знает, остаются), затем свои
        var j: [String: Any] = loadSettingsRaw()
        let ud = UserDefaults.standard
        for (k, t) in settingKeys {
            guard let v = ud.object(forKey: k) else { continue }
            switch t {
            case "s": if let s = v as? String { j[k] = s }
            case "d": if let d = v as? Double { j[k] = d } else if let n = v as? NSNumber { j[k] = n.doubleValue }
            default: if let b = v as? Bool { j[k] = b }
            }
        }
        // имена ключей Flutter-версии и веба
        if let x = j.removeValue(forKey: "showXrefs") { j["showXrefButtons"] = x }
        if let stacked = j.removeValue(forKey: "panesStacked") as? Bool {
            if stacked { j["splitLayout"] = "rows" } else if j["splitLayout"] as? String == "rows" { j["splitLayout"] = "columns" }
        }
        if j["theme"] as? String == "system" { j["theme"] = "auto" }
        guard let d = try? JSONSerialization.data(withJSONObject: j), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func applySettings(_ json: String) {
        guard let d = json.data(using: .utf8), var j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        try? d.write(to: settingsRawURL, options: .atomic)
        // имена Flutter-версии и веба → имена Swift
        if let x = j["showXrefButtons"] { j["showXrefs"] = x }
        if let l = j["splitLayout"] as? String { j["panesStacked"] = (l == "rows") }
        if j["theme"] as? String == "auto" { j["theme"] = "system" }
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
        // ключи, которых Swift не знает (панели, язык, история чтения, свои планы…), уходят как пришли
        for (k, v) in loadExtra() where e[k] == nil { e[k] = v }
        return e
    }

    @MainActor
    static func apply(_ entries: [String: String], marks: MarksStore, plans: PlansStore, sermons: SermonStore) {
        let extra = entries.filter { !handledKeys.contains($0.key) }
        if let d = try? JSONSerialization.data(withJSONObject: extra) { try? d.write(to: extraURL, options: .atomic) }
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
        // Flutter пишет время с долями секунды
        let plain = ISO8601DateFormatter()
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let at = (j["exportedAt"] as? String).flatMap { frac.date(from: $0) ?? plain.date(from: $0) }
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
