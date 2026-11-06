import Foundation

/// План чтения: формат тот же, что у Flutter-версии (JSON). Отрывок: «Gen.1» — глава, «Ps.119-120» — главы,
/// «Ps.9.1-21» — стихи главы
struct Plan: Codable, Identifiable, Hashable {
    var uid: String
    var planId: String
    var name: String
    var readings: [[String]]
    var calendar: Bool
    var start: String
    var year: Int?
    var done: [String: Double]
    var parts: [String: [String: Double]]
    var history: [String: Int]

    var id: String { uid }

    init(uid: String, planId: String, name: String, readings: [[String]], calendar: Bool, start: String) {
        self.uid = uid
        self.planId = planId
        self.name = name
        self.readings = readings
        self.calendar = calendar
        self.start = start
        self.year = calendar ? Calendar.current.component(.year, from: Date()) : nil
        self.done = [:]
        self.parts = [:]
        self.history = [:]
    }

    enum CodingKeys: String, CodingKey {
        case uid, planId, name, readings, calendar, start, year, done, parts, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? UUID().uuidString
        planId = try c.decodeIfPresent(String.self, forKey: .planId) ?? "custom"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        readings = try c.decodeIfPresent([[String]].self, forKey: .readings) ?? []
        calendar = try c.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? PlanLogic.localDate()
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        done = try c.decodeIfPresent([String: Double].self, forKey: .done) ?? [:]
        parts = try c.decodeIfPresent([String: [String: Double]].self, forKey: .parts) ?? [:]
        history = try c.decodeIfPresent([String: Int].self, forKey: .history) ?? [:]
    }
}

struct ReadingUnit {
    let book: String
    let chapter: Int
    let from: Int
    let to: Int? // nil — до конца главы
    let key: String // по нему отмечаются прочитанные отрывки дня
}

struct ReadLogData: Codable {
    var days: [String: [String]] = [:]
}

struct DayCount: Identifiable {
    let day: String
    let n: Int
    var id: String { day }
}

struct ReadStats {
    let today: Int
    let week: Int
    let total: Int
    let streak: Int
    let days7: [DayCount]
}

enum PlanLogic {
    // MARK: даты

    static func localDate(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func day0(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        if p.count >= 3, let d = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) {
            return d
        }
        return Calendar.current.startOfDay(for: Date())
    }

    /// Разница в днях по календарю (переход на летнее время не сбивает счёт)
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        let c = Calendar.current
        return c.dateComponents([.day], from: c.startOfDay(for: a), to: c.startOfDay(for: b)).day ?? 0
    }

    /// Календарный план (М'Чейн): день плана = день года, 29 февраля чтений нет (берём 28-е)
    static func calendarIndex(_ date: Date = Date()) -> Int {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let jan1 = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? date
        var i = daysBetween(jan1, date)
        let leap = (cal.range(of: .day, in: .year, for: date)?.count ?? 365) == 366
        if leap && i >= 59 { i -= 1 }
        return min(364, i)
    }

    static func todayIndex(start: String, days: Int, now: Date = Date()) -> Int {
        max(0, min(days - 1, daysBetween(day0(start), now)))
    }

    static func planToday(_ p: Plan, now: Date = Date()) -> Int {
        p.calendar ? calendarIndex(now) : todayIndex(start: p.start, days: p.readings.count, now: now)
    }

    static func dayDone(_ p: Plan, _ day: Int) -> Bool {
        p.done["\(day)"] != nil
    }

    /// Пропущенные дни до сегодняшнего (с начала плана)
    static func behindDays(_ p: Plan, now: Date = Date()) -> [Int] {
        let today = planToday(p, now: now)
        let from = p.calendar ? min(today, calendarIndex(day0(p.start))) : 0
        guard today > from else { return [] }
        return (from..<today).filter { !dayDone(p, $0) }
    }

    // MARK: отрывки

    static func readingUnits(_ r: String) -> [ReadingUnit] {
        let p = r.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let book = p[0]
        if p.count > 2, !p[2].isEmpty {
            let v = p[2].split(separator: "-").map { Int($0) ?? 0 }
            let chapter = Int(p[1]) ?? 1
            let from = v.first ?? 1
            let to = v.count > 1 && v[1] > 0 ? v[1] : from
            return [ReadingUnit(book: book, chapter: chapter, from: from, to: to, key: r)]
        }
        let raw = (p.count > 1 && !p[1].isEmpty) ? p[1] : "1"
        let cs = raw.split(separator: "-").map { Int($0) ?? 1 }
        let a = cs.first ?? 1
        let b = cs.count > 1 ? cs[1] : a
        return (0...max(0, b - a)).map { ReadingUnit(book: book, chapter: a + $0, from: 1, to: nil, key: "\(book).\(a + $0)") }
    }

    static func dayUnits(_ p: Plan, _ day: Int) -> [ReadingUnit] {
        guard day >= 0, day < p.readings.count else { return [] }
        return p.readings[day].flatMap { readingUnits($0) }
    }

    static func unitDone(_ p: Plan, _ day: Int, _ key: String) -> Bool {
        dayDone(p, day) || p.parts["\(day)"]?[key] != nil
    }

    static func readingDone(_ p: Plan, _ day: Int, _ r: String) -> Bool {
        readingUnits(r).allSatisfy { unitDone(p, day, $0.key) }
    }

    /// Подпись отрывка: «Быт 1», «Пс 9:1–21», «Пс 119–120»
    static func readingLabel(_ r: String) -> String {
        let p = r.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var name = Books.info(p[0])?.short ?? p[0]
        if name.hasSuffix(".") { name.removeLast() }
        if p.count > 2, !p[2].isEmpty {
            return "\(name) \(p[1]):\(p[2].replacingOccurrences(of: "-", with: "–"))"
        }
        let c = (p.count > 1 && !p[1].isEmpty) ? p[1] : "1"
        return "\(name) \(c.replacingOccurrences(of: "-", with: "–"))"
    }

    static func readingTarget(_ r: String) -> (book: String, chapter: Int, verse: Int) {
        let u = readingUnits(r)[0]
        return (u.book, u.chapter, u.from)
    }

    // MARK: отметки

    /// Отметить отрывки дня прочитанными; finished — день завершён этим
    static func markUnits(_ plans: [Plan], uid: String, day: Int, keys: [String], now: Double = Date().timeIntervalSince1970 * 1000) -> (plans: [Plan], finished: Bool) {
        var finished = false
        let out = plans.map { p -> Plan in
            guard p.uid == uid, !dayDone(p, day) else { return p }
            var q = p
            var have = q.parts["\(day)"] ?? [:]
            let add = keys.filter { have[$0] == nil }
            if add.isEmpty { return p }
            for k in add { have[k] = now }
            q.parts["\(day)"] = have
            let all = dayUnits(q, day).allSatisfy { have[$0.key] != nil }
            finished = all
            if all { q.done["\(day)"] = now }
            return q
        }
        return (out, finished)
    }

    /// Глава дочитана в обычном чтении: засчитываем её в планы — сначала в сегодняшний день, потом в пропущенные
    static func creditChapter(_ plans: [Plan], book: String, chapter: Int, now: Date = Date()) -> (plans: [Plan], credited: [String], finished: [String]) {
        var cur = plans
        var credited: [String] = []
        var finished: [String] = []
        for p0 in plans {
            guard let p = cur.first(where: { $0.uid == p0.uid }) else { continue }
            for d in [planToday(p, now: now)] + behindDays(p, now: now) {
                if dayDone(p, d) { continue }
                let keys = dayUnits(p, d)
                    .filter { $0.book == book && $0.chapter == chapter && p.parts["\(d)"]?[$0.key] == nil }
                    .map { $0.key }
                if keys.isEmpty { continue }
                credited.append(p.name)
                let r = markUnits(cur, uid: p.uid, day: d, keys: keys)
                cur = r.plans
                if r.finished { finished.append(p.name) }
                break
            }
        }
        return (cur, credited, finished)
    }

    /// Календарный план в новом году начинается заново: отметки прошлого года не считаются прочитанными в этом
    static func applyNewYear(_ list: [Plan], year: Int = Calendar.current.component(.year, from: Date())) -> [Plan] {
        list.map { p in
            guard p.calendar else { return p }
            let py = p.year ?? Int(p.start.prefix(4)) ?? year
            if py == year {
                var q = p
                q.year = year
                return q
            }
            var q = p
            q.history["\(py)"] = p.done.count
            q.year = year
            q.start = "\(year)-01-01"
            q.done = [:]
            q.parts = [:]
            return q
        }
    }

    // MARK: учёт прочитанного

    /// Сколько секунд нужно провести на главе из n стихов (быстрое чтение, с запасом)
    static func minSeconds(_ n: Int) -> Double {
        max(8, min(120, Double(n) * 2.5))
    }

    static func stats(_ log: ReadLogData, now: Date = Date()) -> ReadStats {
        let cal = Calendar.current
        func ago(_ i: Int) -> Date { cal.date(byAdding: .day, value: -i, to: now) ?? now }
        func cnt(_ i: Int) -> Int { log.days[localDate(ago(i))]?.count ?? 0 }
        let weekAgo = localDate(ago(6))
        var all = Set<String>()
        var week = 0
        for (d, list) in log.days {
            for k in list {
                all.insert(k)
                if d >= weekAgo { week += 1 }
            }
        }
        let days7 = [6, 5, 4, 3, 2, 1, 0].map { DayCount(day: localDate(ago($0)), n: cnt($0)) }
        var streak = 0
        var i = cnt(0) > 0 ? 0 : 1
        while cnt(i) > 0 {
            streak += 1
            i += 1
        }
        return ReadStats(today: cnt(0), week: week, total: all.count, streak: streak, days7: days7)
    }

    // MARK: свой план

    /// Главы поровну по дням (по числу стихов): ровно days дней, дни без глав пропускаются
    static func splitChapters(_ chapters: [(ref: String, n: Int)], days: Int) -> [[String]] {
        let total = chapters.reduce(0) { $0 + $1.n }
        guard total > 0, days >= 1 else { return [] }
        let per = Double(total) / Double(days)
        var readings = Array(repeating: [String](), count: days)
        var acc = 0
        for c in chapters {
            let day = min(days - 1, Int((Double(acc) + Double(c.n) / 2) / per))
            readings[day].append(c.ref)
            acc += c.n
        }
        return readings.filter { !$0.isEmpty }
    }
}
