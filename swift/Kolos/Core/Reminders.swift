import Foundation
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#endif

/// Одно напоминание: время (или промежуток «с — до» с шагом every минут), дни недели, обычное или будильник.
/// Формат тот же, что у Flutter-версии (ключ planReminder): {on, time, list:[{id,time,every,until,days,alarm?}]}
struct ReminderItem: Codable, Identifiable, Hashable {
    var id: String
    var time: String
    var every: Int
    var until: String
    var days: [Int]
    var alarm: Bool?
    /// Конкретные даты «yyyy-MM-dd» (календарь — например, при сменном графике); заданы — дни недели не действуют
    var dates: [String]?
    /// Напоминание выключено (остаётся в списке)
    var off: Bool?

    init(id: String = String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 36), time: String = "08:00", every: Int = 0, until: String = "20:00", days: [Int] = [], alarm: Bool = false, dates: [String]? = nil) {
        self.id = id
        self.time = time
        self.every = every
        self.until = until
        self.days = days
        self.alarm = alarm ? true : nil
        self.dates = dates
    }

    var isAlarm: Bool { alarm == true }
    var isOn: Bool { off != true }
    var byCalendar: Bool { !(dates ?? []).isEmpty }

    /// Срабатывает ли в этот день: по датам календаря, иначе по дням недели (1 = понедельник … 7 = воскресенье)
    func applies(weekday wd: Int, day: String) -> Bool {
        if let ds = dates, !ds.isEmpty { return ds.contains(day) }
        return days.isEmpty || days.contains(wd)
    }

    /// «2026-11-16» для даты
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
}

struct ReminderData: Codable {
    var on: Bool
    var time: String
    var list: [ReminderItem]

    init(on: Bool = false, time: String = "08:00", list: [ReminderItem]? = nil) {
        self.on = on
        self.time = time
        self.list = list ?? [ReminderItem(id: "r1", time: time)]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? "08:00"
        let l = try c.decodeIfPresent([ReminderItem].self, forKey: .list) ?? []
        // прежний формат {on, time} без списка — одно напоминание r1
        list = l.isEmpty ? [ReminderItem(id: "r1", time: time)] : l
    }
}

/// Напоминания о чтении: сколько угодно, в любое время или промежутком, по дням недели; обычные (уведомление)
/// и будильники (звонят, как будильник, даже в беззвучном режиме — через системные будильники iOS 26).
/// Расписание — на 14 дней вперёд, в тексте — отрывки планов на этот день; iOS хранит не больше 64 уведомлений
@MainActor
enum Reminders {
    private static let key = "planReminder"
    private static let alarmIDsKey = "reminderAlarmIDs"
    private static let maxNotifications = 60
    private static let maxAlarms = 24

    static var data: ReminderData {
        get {
            let ud = UserDefaults.standard
            if let s = ud.string(forKey: key), let d = s.data(using: .utf8), let r = try? JSONDecoder().decode(ReminderData.self, from: d) {
                return r
            }
            // прежние настройки (одно напоминание)
            if ud.object(forKey: "reminderOn") != nil || ud.string(forKey: "reminderTime") != nil {
                return ReminderData(on: ud.bool(forKey: "reminderOn"), time: ud.string(forKey: "reminderTime") ?? "20:00")
            }
            return ReminderData()
        }
        set {
            var v = newValue
            if let first = v.list.first { v.time = first.time }
            if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) {
                UserDefaults.standard.set(s, forKey: key)
            }
        }
    }

    static var isOn: Bool { data.on }

    /// Для файла «Мои данные»
    static var jsonString: String? {
        guard let d = try? JSONEncoder().encode(data) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func importJSON(_ s: String?) {
        guard let s, let d = s.data(using: .utf8), let r = try? JSONDecoder().decode(ReminderData.self, from: d) else { return }
        data = r
    }

    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Разрешение на будильники (iOS 26)
    static func requestAlarmAccess() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return await Alarms.authorize() }
        #endif
        return false
    }

    // MARK: - Моменты напоминания

    private static func minutes(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 480
    }

    /// Минуты дня, когда срабатывает напоминание: одно время, либо от «с» до «до» включительно с шагом every (не больше 48)
    static func times(_ r: ReminderItem) -> [Int] {
        let from = minutes(r.time)
        guard r.every > 0 else { return [from] }
        let to = minutes(r.until)
        guard to > from else { return [from] }
        var out: [Int] = []
        var m = from
        while m <= to && out.count < 48 {
            out.append(m)
            m += r.every
        }
        return out
    }

    private static func planDayOn(_ p: Plan, _ day: Date) -> Int? {
        let idx = p.calendar ? PlanLogic.calendarIndex(day) : PlanLogic.daysBetween(PlanLogic.day0(p.start), day)
        return (idx >= 0 && idx < p.readings.count) ? idx : nil
    }

    // MARK: - Расписание

    private struct Moment {
        let date: Date
        let alarm: Bool
        let body: String
    }

    /// Пересобрать расписание (при запуске и при любом изменении планов и напоминаний)
    /// Пересборки идут строго по очереди: две одновременные теряли будильники (их номера затирались,
    /// и такой будильник уже нельзя было отменить)
    private static var running: Task<Void, Never>?

    static func schedule(_ plans: [Plan]) {
        let prev = running
        running = Task {
            await prev?.value
            await rebuild(plans)
        }
    }

    /// Звонящий будильник — остановить (приложение открыли: значит, услышали)
    static func stopRinging() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { Alarms.stopAlerting() }
        #endif
    }

    private static func rebuild(_ plans: [Plan]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        await cancelAlarms()
        let d = data
        guard d.on else { return }
        let cal = Calendar.current
        let now = Date()
        var moments: [Moment] = []
        for k in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: k, to: cal.startOfDay(for: now)) else { continue }
            // 1 = понедельник … 7 = воскресенье
            let wd = (cal.component(.weekday, from: day) + 5) % 7 + 1
            var byMinute: [Int: Bool] = [:]
            let dk = ReminderItem.dayKey(day)
            for r in d.list where r.isOn && r.applies(weekday: wd, day: dk) {
                for m in times(r) { byMinute[m] = (byMinute[m] ?? false) || r.isAlarm }
            }
            if byMinute.isEmpty { continue }
            var lines: [String] = []
            for p in plans {
                guard let i = planDayOn(p, day), !PlanLogic.dayDone(p, i) else { continue }
                lines.append("\(p.title): " + p.readings[i].map { PlanLogic.readingLabel($0) }.joined(separator: ", "))
            }
            // планов нет — простое напоминание; план есть, но на этот день всё прочитано — не беспокоим
            if lines.isEmpty && !plans.isEmpty { continue }
            let body = lines.isEmpty ? String(localized: "Время читать Библию") : lines.joined(separator: "\n")
            for m in byMinute.keys.sorted() {
                guard let at = cal.date(byAdding: .minute, value: m, to: day), at.timeIntervalSince(now) >= 60 else { continue }
                moments.append(Moment(date: at, alarm: byMinute[m] == true, body: body))
            }
        }
        moments.sort { $0.date < $1.date }

        // будильники — системные (iOS 26): ближайшие; остальное и всё без разрешения — уведомления
        var alarmOK = false
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), moments.contains(where: { $0.alarm }) { alarmOK = await Alarms.isAuthorized() }
        #endif
        var ids: [String] = []
        var used = 0
        for m in moments {
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *), m.alarm, alarmOK, ids.count < maxAlarms {
                if let id = await Alarms.schedule(at: m.date) {
                    ids.append(id)
                    continue
                }
            }
            #endif
            guard used < maxNotifications else { break }
            let c = UNMutableNotificationContent()
            c.title = plans.isEmpty ? "Колос" : String(localized: "Чтение на сегодня")
            c.body = m.body
            c.sound = .default
            if m.alarm { c.interruptionLevel = .timeSensitive }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: m.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "reminder-\(used)", content: c, trigger: trigger))
            used += 1
        }
        UserDefaults.standard.set(ids, forKey: alarmIDsKey)
    }

    private static func cancelAlarms() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for s in UserDefaults.standard.stringArray(forKey: alarmIDsKey) ?? [] {
                if let u = UUID(uuidString: s) { try? AlarmManager.shared.cancel(id: u) }
            }
            // и все остальные будильники приложения — в том числе «потерянные» прежними версиями
            Alarms.cancelAll()
        }
        #endif
        UserDefaults.standard.removeObject(forKey: alarmIDsKey)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct ReadingAlarmData: AlarmMetadata {}

/// Системные будильники iOS 26 (AlarmKit): звонят, даже когда телефон в беззвучном режиме или в «Фокусе»
@available(iOS 26.0, *)
@MainActor
enum Alarms {
    static func isAuthorized() async -> Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    static func authorize() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        }
    }

    /// Все будильники приложения — отменить
    static func cancelAll() {
        for a in (try? AlarmManager.shared.alarms) ?? [] {
            try? AlarmManager.shared.cancel(id: a.id)
        }
    }

    /// Звонящие сейчас — остановить
    static func stopAlerting() {
        for a in (try? AlarmManager.shared.alarms) ?? [] where a.state == .alerting {
            try? AlarmManager.shared.stop(id: a.id)
        }
    }

    /// Один будильник на дату; возвращает его номер для отмены. «Стоп» явно останавливает именно его
    static func schedule(at date: Date) async -> String? {
        let stop = AlarmButton(text: "Стоп", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: "Время читать Библию", stopButton: stop)
        let attrs = AlarmAttributes<ReadingAlarmData>(presentation: AlarmPresentation(alert: alert), tintColor: .orange)
        let id = UUID()
        let cfg = AlarmManager.AlarmConfiguration.alarm(schedule: Alarm.Schedule.fixed(date), attributes: attrs, stopIntent: StopReadingAlarm(id: id))
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)
            return id.uuidString
        } catch {
            return nil
        }
    }
}

/// «Стоп» на будильнике: останавливает его (выполняется системой, приложение не открывается)
@available(iOS 26.0, *)
struct StopReadingAlarm: LiveActivityIntent {
    static let title: LocalizedStringResource = "Остановить будильник"
    static let isDiscoverable = false

    @Parameter(title: "Будильник")
    var alarmID: String

    init() {}

    init(id: UUID) {
        alarmID = id.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let u = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: u) }
        return .result()
    }
}
#endif
