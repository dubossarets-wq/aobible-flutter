import Foundation
import SwiftUI

struct Place: Codable, Hashable {
    var book: String
    var chapter: Int
    var verse: Int
}

/// Панель чтения: свой перевод, своё место и своя история переходов
struct PaneState: Identifiable, Codable, Hashable {
    var id = UUID()
    var moduleId: String
    var book: String
    var chapter: Int
    var verse: Int
    var history: [Place] = []
    var hIndex = 0

    var place: Place { Place(book: book, chapter: chapter, verse: verse) }
}

/// Сколько панелей чтения можно открыть рядом
let maxPanes = 6

/// Живое место: верхний видимый стих каждой панели. Меняется при прокрутке, поэтому лежит отдельно от панелей —
/// перерисовывается только то, что его читает (шапка), а не весь экран
@MainActor
final class LivePlace: ObservableObject {
    @Published var verse: [UUID: Int] = [:]
}


/// Панели чтения: до шести, у каждой свой перевод и история. Хранятся файлом «panes.json»; если его ещё нет, но есть
/// панели Flutter-версии (тот же контейнер), они подхватываются
@MainActor
final class PanesStore: ObservableObject {
    @Published var panes: [PaneState] = []
    let live = LivePlace()
    /// Синхронная прокрутка панелей
    let scrollSync = ScrollSync()
    private var liveTask: Task<Void, Never>?
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("panes.json")
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([PaneState].self, from: d) {
            panes = p
        } else if let s = UserDefaults.standard.string(forKey: "flutter.panes"),
                  let d = s.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
            panes = list.compactMap { m in
                guard let mod = m["moduleId"] as? String, let r = m["ref"] as? [String: Any],
                      let b = r["book"] as? String, let c = r["chapter"] as? Int, let v = r["verse"] as? Int else { return nil }
                return PaneState(moduleId: mod, book: b, chapter: c, verse: v, history: [Place(book: b, chapter: c, verse: v)])
            }
        }
        scrollSync.store = self
    }

    private func save() {
        // место на диске — то, где человек сейчас читает (верхний видимый стих)
        var out = panes
        for i in out.indices { if let v = live.verse[out[i].id] { out[i].verse = v } }
        if let d = try? JSONEncoder().encode(out) { try? d.write(to: url, options: .atomic) }
    }

    /// Верхний видимый стих панели (при прокрутке); на диск пишется не чаще раза в секунду
    func setLive(_ id: UUID, _ verse: Int) {
        guard index(id) != nil, live.verse[id] != verse else { return }
        live.verse[id] = verse
        liveTask?.cancel()
        liveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { save() }
        }
    }

    /// Где сейчас читает панель: верхний видимый стих, иначе записанное место
    func livePlace(_ id: UUID) -> Place? {
        guard let i = index(id) else { return nil }
        var p = panes[i].place
        if let v = live.verse[id] { p.verse = v }
        return p
    }

    /// Первая панель при самом первом запуске; панели без установленного перевода получают первый имеющийся
    func ensureStarted(_ store: ModuleStore) {
        guard let first = store.bibles.first else { return }
        if panes.isEmpty {
            let p = Place(book: "Gen", chapter: 1, verse: 1)
            panes = [PaneState(moduleId: first.id, book: p.book, chapter: p.chapter, verse: 0, history: [p])]
        }
        var changed = false
        for i in panes.indices where store.module(panes[i].moduleId) == nil || store.module(panes[i].moduleId)?.type != "bible" {
            panes[i].moduleId = first.id
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Первая панель (остальной код читает перевод по умолчанию отсюда)

    var primaryModule: String {
        panes.first?.moduleId ?? ""
    }

    func setPrimary(_ id: String) {
        guard !panes.isEmpty else { return }
        panes[0].moduleId = id
        save()
    }

    func primaryBinding() -> Binding<String> {
        Binding(get: { self.primaryModule }, set: { self.setPrimary($0) })
    }

    func index(_ id: UUID) -> Int? {
        panes.firstIndex { $0.id == id }
    }

    // MARK: - Переходы

    /// Перейти в панели. record — запомнить в истории (переход по ссылке, из навигатора, поиска);
    /// соседняя глава стрелками и свайпом в историю не пишется
    func go(_ id: UUID, _ book: String, _ chapter: Int, _ verse: Int, record: Bool = true) {
        guard let i = index(id) else { return }
        panes[i].book = book
        panes[i].chapter = chapter
        panes[i].verse = verse
        live.verse[id] = nil
        if record {
            var h = Array(panes[i].history.prefix(panes[i].hIndex + 1))
            let p = Place(book: book, chapter: chapter, verse: verse)
            if h.last?.book != book || h.last?.chapter != chapter { h.append(p) }
            panes[i].history = Array(h.suffix(60))
            panes[i].hIndex = panes[i].history.count - 1
        }
        save()
    }

    /// Открыть место в первой панели (из поиска, закладок, планов)
    func open(_ book: String, _ chapter: Int, _ verse: Int) {
        guard let first = panes.first else { return }
        go(first.id, book, chapter, verse)
    }

    /// Открыть место во второй панели относительно данной; если её нет — она создаётся (параллельные места)
    func openSecond(from id: UUID, _ book: String, _ chapter: Int, _ verse: Int) {
        guard let i = index(id) else { return }
        if i + 1 >= panes.count {
            guard panes.count < maxPanes else {
                go(id, book, chapter, verse)
                return
            }
            addPane(after: id, moduleId: panes[i].moduleId)
        }
        go(panes[i + 1].id, book, chapter, verse)
    }

    /// Перейти по истории панели на запись i (без новой записи в историю)
    func goHistory(_ id: UUID, _ i: Int) {
        guard let k = index(id), i >= 0, i < panes[k].history.count else { return }
        panes[k].hIndex = i
        let p = panes[k].history[i]
        go(id, p.book, p.chapter, p.verse, record: false)
    }

    func canBack(_ id: UUID) -> Bool {
        guard let i = index(id) else { return false }
        return panes[i].hIndex > 0
    }

    func canForward(_ id: UUID) -> Bool {
        guard let i = index(id) else { return false }
        return panes[i].hIndex < panes[i].history.count - 1
    }

    func back(_ id: UUID) {
        guard let i = index(id), panes[i].hIndex > 0 else { return }
        panes[i].hIndex -= 1
        let p = panes[i].history[panes[i].hIndex]
        panes[i].book = p.book
        panes[i].chapter = p.chapter
        panes[i].verse = p.verse
        save()
    }

    func forward(_ id: UUID) {
        guard let i = index(id), panes[i].hIndex < panes[i].history.count - 1 else { return }
        panes[i].hIndex += 1
        let p = panes[i].history[panes[i].hIndex]
        panes[i].book = p.book
        panes[i].chapter = p.chapter
        panes[i].verse = p.verse
        save()
    }

    /// Соседняя глава; за последней главой книги — следующая книга
    func step(_ id: UUID, _ delta: Int, module m: InstalledModule) {
        guard let i = index(id), let bi = m.books.firstIndex(where: { $0.id == panes[i].book }) else { return }
        var c = panes[i].chapter + delta
        var b = bi
        if c < 1 {
            guard b > 0 else { return }
            b -= 1
            c = m.books[b].chapters
        } else if c > m.books[bi].chapters {
            guard b < m.books.count - 1 else { return }
            b += 1
            c = 1
        }
        go(id, m.books[b].id, max(1, c), 0, record: false)
    }

    func setModule(_ id: UUID, _ moduleId: String, _ store: ModuleStore) {
        guard let i = index(id) else { return }
        panes[i].moduleId = moduleId
        // в другом переводе может не быть этой книги — тогда первая
        if let m = store.module(moduleId), !m.books.contains(where: { $0.id == panes[i].book }), let f = m.books.first {
            panes[i].book = f.id
            panes[i].chapter = 1
            panes[i].verse = 0
        }
        save()
    }

    // MARK: - Панели

    func addPane(after id: UUID, moduleId: String) {
        guard panes.count < maxPanes, let i = index(id) else { return }
        var here = panes[i].place
        if let v = live.verse[id] { here.verse = v }
        let p = PaneState(moduleId: moduleId, book: here.book, chapter: here.chapter, verse: here.verse, history: [here])
        panes.insert(p, at: i + 1)
        save()
    }

    func closePane(_ id: UUID) {
        guard panes.count > 1 else { return }
        panes.removeAll { $0.id == id }
        scrollSync.detach(id)
        save()
    }

    /// Недавние книги (по истории переходов всех панелей), самые свежие первыми
    func recentBooks() -> [String] {
        var out: [String] = []
        for p in panes {
            for h in p.history.reversed() where !out.contains(h.book) {
                out.append(h.book)
            }
        }
        return Array(out.prefix(8))
    }
}
