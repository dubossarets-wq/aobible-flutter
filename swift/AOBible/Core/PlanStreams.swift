import Foundation

/// Раздел параллельного плана. ВЗ и НЗ — «широкие»: книги узких разделов в них не повторяются
struct PlanStream: Identifiable {
    let key: String
    let label: String
    let short: String
    let wide: Bool
    var id: String { key }
}

struct StreamSel {
    let key: String
    let perDay: Int
    let books: [String]
}

typealias ChapterRef = (ref: String, n: Int)

extension PlanLogic {
    /// В библейском порядке: так же идут и в чтении за день
    static let streams: [PlanStream] = [
        PlanStream(key: "ot", label: "Ветхий Завет", short: "ВЗ", wide: true),
        PlanStream(key: "ps", label: "Псалтирь", short: "Псалтирь", wide: false),
        PlanStream(key: "prov", label: "Притчи", short: "Притчи", wide: false),
        PlanStream(key: "gospels", label: "Евангелия", short: "Евангелия", wide: false),
        PlanStream(key: "nt", label: "Новый Завет", short: "НЗ", wide: true),
        PlanStream(key: "own", label: "Свои книги", short: "Свои книги", wide: false),
    ]

    /// Псалтирь и Притчи читаются по кругу, остальное — один раз
    static let cyclicStreams: Set<String> = ["ps", "prov"]

    static func streamBooks(_ key: String, own: [String]) -> [String] {
        switch key {
        case "ot": return Books.all.filter { $0.t == "OT" && $0.dc != true }.map { $0.id }
        case "nt": return Books.all.filter { $0.t == "NT" }.map { $0.id }
        case "ps": return ["Ps"]
        case "prov": return ["Prov"]
        case "gospels": return ["Matt", "Mark", "Luke", "John"]
        default: return own
        }
    }

    /// Книги разделов без повторов (как во Flutter-версии): книги узких разделов не читаются ещё раз в ВЗ/НЗ,
    /// а в своих книгах — те, что уже есть в Псалтири, Притчах, Евангелиях. Порядок — по первой книге
    static func streamList(on: [String: Int], own: [String]) -> [StreamSel] {
        let keys = streams.filter { on[$0.key] != nil }
        var fixed = Set<String>()
        var narrow = Set<String>()
        for s in keys where !s.wide {
            let b = streamBooks(s.key, own: own)
            narrow.formUnion(b)
            if s.key != "own" { fixed.formUnion(b) }
        }
        var out: [StreamSel] = keys.map { s in
            let books: [String]
            if s.wide {
                books = streamBooks(s.key, own: []).filter { !narrow.contains($0) }
            } else if s.key == "own" {
                books = own.filter { !fixed.contains($0) }
            } else {
                books = streamBooks(s.key, own: own)
            }
            return StreamSel(key: s.key, perDay: on[s.key] ?? 1, books: books)
        }
        var pos: [String: Int] = [:]
        for (i, b) in Books.all.enumerated() { pos[b.id] = i }
        func first(_ x: StreamSel) -> Int { x.books.map { pos[$0] ?? 1 << 30 }.min() ?? 1 << 30 }
        let idx = out.indices.sorted { a, b in
            let fa = first(out[a]), fb = first(out[b])
            return fa != fb ? fa < fb : a < b
        }
        out = idx.map { out[$0] }
        return out
    }

    /// Главы поровну по дням (по числу стихов): ровно days дней, пустые дни остаются
    static func splitChaptersRaw(_ chapters: [ChapterRef], days: Int) -> [[String]] {
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
        return readings
    }

    /// Длина плана: по самому длинному разделу из читаемых один раз (только Псалтирь/Притчи — по ним)
    static func parallelDays(_ sel: [StreamSel], chapters: ([String]) -> [ChapterRef]) -> Int {
        var once = 0, loop = 0
        for x in sel {
            let n = chapters(x.books).count
            guard n > 0, x.perDay > 0 else { continue }
            let d = (n + x.perDay - 1) / x.perDay
            if cyclicStreams.contains(x.key) { loop = max(loop, d) } else { once = max(once, d) }
        }
        return min(3650, once > 0 ? once : loop)
    }

    /// Дни параллельного плана. period — число дней: каждый раздел делится на них поровну, все кончаются в последний день
    static func makeParallelPlan(_ sel: [StreamSel], chapters: ([String]) -> [ChapterRef], period: Int? = nil) -> [[String]] {
        if let period {
            var parts: [[[String]]] = []
            for x in sel {
                let ch = chapters(x.books)
                if !ch.isEmpty { parts.append(splitChaptersRaw(ch, days: period)) }
            }
            var out: [[String]] = []
            for d in 0..<period where parts.contains(where: { $0.count > d && !$0[d].isEmpty }) {
                var seen = Set<String>()
                var day: [String] = []
                for p in parts where p.count > d {
                    for r in p[d] where seen.insert(r).inserted { day.append(r) }
                }
                out.append(day)
            }
            return out
        }
        struct Ok { let loop: Bool; let per: Int; let ch: [ChapterRef] }
        var ok: [Ok] = []
        for x in sel {
            let ch = chapters(x.books)
            if x.perDay > 0, !ch.isEmpty { ok.append(Ok(loop: cyclicStreams.contains(x.key), per: x.perDay, ch: ch)) }
        }
        guard !ok.isEmpty else { return [] }
        let days = parallelDays(sel, chapters: chapters)
        var out: [[String]] = []
        for d in 0..<days {
            var seen = Set<String>()
            var day: [String] = []
            for x in ok {
                for k in 0..<min(x.per, x.ch.count) where x.loop || d * x.per + k < x.ch.count {
                    let r = x.ch[(d * x.per + k) % x.ch.count].ref
                    if seen.insert(r).inserted { day.append(r) }
                }
            }
            out.append(day)
        }
        return out
    }

    /// Первый день параллельного плана: «Быт. 1–2 · Пс. 1 · Мф. 1»
    static func firstDayText(_ sel: [StreamSel], chapters: ([String]) -> [ChapterRef]) -> String {
        func name(_ ref: String) -> String {
            let p = ref.split(separator: ".").map(String.init)
            return "\(Books.info(p[0])?.short ?? p[0]) \(p.count > 1 ? p[1] : "")"
        }
        var parts: [String] = []
        for x in sel {
            let ch = chapters(x.books).prefix(x.perDay).map { $0.ref }
            guard let f = ch.first, let l = ch.last else { continue }
            if ch.count == 1 {
                parts.append(name(f))
            } else {
                let a = f.split(separator: "."), b = l.split(separator: ".")
                parts.append(a[0] == b[0] ? "\(name(f))–\(b[1])" : "\(name(f)) – \(name(l))")
            }
        }
        return parts.joined(separator: " · ")
    }
}
