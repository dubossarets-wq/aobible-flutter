import Foundation

/// Похожие по написанию слова — для подсказок «Возможно, вы искали» (карты, словарь, поиск по стихам)
enum Fuzzy {
    /// Расстояние Дамерау — Левенштейна (вставка, удаление, замена, перестановка соседних букв)
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = min(cur[j], prev2[j - 2] + 1)
                }
            }
            prev2 = prev
            prev = cur
        }
        return prev[b.count]
    }

    /// Сколько ошибок прощаем слову такой длины: одну на каждые три буквы, но не меньше одной
    static func allowed(_ length: Int) -> Int { max(1, length / 3) }

    /// Насколько слово n близко к запросу q: расстояние до всего слова или до его начала такой же длины (недописанное
    /// слово тоже подходит, но на единицу хуже); nil — слишком далеко
    static func score(_ q: [Character], _ n: [Character], allowed: Int) -> Int? {
        var best = Int.max
        if abs(n.count - q.count) <= allowed { best = distance(q, n) }
        if n.count > q.count {
            best = min(best, distance(q, Array(n.prefix(q.count))) + 1)
        }
        return best <= allowed ? best : nil
    }
}
