import Foundation
import UserNotifications

/// Напоминание о чтении: ежедневно в выбранное время; на дни, когда все планы уже прочитаны, не напоминает.
/// В уведомлении — отрывки сегодняшнего дня первого плана
@MainActor
enum Reminders {
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "reminderOn") }
        set { UserDefaults.standard.set(newValue, forKey: "reminderOn") }
    }

    /// Время «HH:mm»
    static var time: String {
        get { UserDefaults.standard.string(forKey: "reminderTime") ?? "20:00" }
        set { UserDefaults.standard.set(newValue, forKey: "reminderTime") }
    }

    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Пересобрать расписание на ближайшие 7 дней (вызывается при запуске и при любом изменении планов)
    static func schedule(_ plans: [Plan]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isOn else { return }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let cal = Calendar.current
        let now = Date()
        for i in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = parts[0]
            comps.minute = parts[1]
            guard let fire = cal.date(from: comps), fire > now else { continue }
            // сегодня: если все планы дня уже прочитаны — не напоминаем
            var body = "Время читать Библию."
            if !plans.isEmpty {
                let pending = plans.filter { p in
                    let d = PlanLogic.planToday(p, now: day)
                    return d < p.readings.count && (i > 0 || !PlanLogic.dayDone(p, d))
                }
                if i == 0 && pending.isEmpty { continue }
                if let p = pending.first {
                    let d = PlanLogic.planToday(p, now: day)
                    body = "\(p.name): " + p.readings[d].map { PlanLogic.readingLabel($0) }.joined(separator: " · ")
                }
            }
            let content = UNMutableNotificationContent()
            content.title = "AO Bible"
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "reminder-\(i)", content: content, trigger: trigger))
        }
    }
}
