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
    /// Глава верхнего видимого стиха — в сплошном тексте книги она меняется прямо при прокрутке
    @Published var chapter: [UUID: Int] = [:]
    /// Сколько прочитано книги, 0…1 (полоска вверху панели)
    @Published var progress: [UUID: Double] = [:]
}

/// Спрятаны ли шапки панелей (при прокрутке вниз уходят, вверх — возвращаются)
@MainActor
final class ChromeState: ObservableObject {
    @Published var hidden: [UUID: Bool] = [:]
    /// На сколько опустить кнопки «глава назад / слушать / вперёд», когда нижнее меню ушло: их нижний край встаёт
    /// ровно туда, где был нижний край меню (меряется на устройстве)
    @Published var bottomShift: CGFloat = 50
}


/// Панели чтения: до шести, у каждой свой перевод и история. Хранятся файлом «panes.json»; если его ещё нет, но есть
/// панели Flutter-версии (тот же контейнер), они подхватываются
@MainActor
final class PanesStore: ObservableObject {
    @Published var panes: [PaneState] = []
    let live = LivePlace()
    let chrome = ChromeState()
    /// История всех мест с датой и временем («Ещё» → «История»)
    let log = ReadingHistory()
    /// Синхронная прокрутка панелей
    let scrollSync = ScrollSync()
    /// Страничный режим: окна листают вместе
    let pageSync = PageSync()
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
        pageSync.store = self
    }

    private func save() {
        // место на диске — то, где человек сейчас читает (верхний видимый стих)
        var out = panes
        for i in out.indices {
            if let v = live.verse[out[i].id] { out[i].verse = v }
            if let c = live.chapter[out[i].id] { out[i].chapter = c }
        }
        if let d = try? JSONEncoder().encode(out) { try? d.write(to: url, options: .atomic) }
    }

    /// Верхний видимый стих панели (при прокрутке); на диск пишется не чаще раза в секунду
    /// chapter — глава этого стиха (сплошной текст книги: прокрутка уже в другой главе, а текущей она станет при остановке)
    func setLive(_ id: UUID, _ verse: Int, chapter: Int? = nil) {
        guard let i = index(id) else { return }
        let c = chapter ?? panes[i].chapter
        guard live.verse[id] != verse || (live.chapter[id] ?? panes[i].chapter) != c else { return }
        live.verse[id] = verse
        if chapter != nil, live.chapter[id] != c { live.chapter[id] = c }
        // место для истории и сохранения — когда прокрутка остановилась (раз в секунду), а не на каждом стихе: при быстрой
        // прокрутке это были десятки записей и перестроек в секунду
        let book = panes[i].book
        liveTask?.cancel()
        liveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if verse > 0 { log.record(book, c, verse) }
            save()
        }
    }

    /// Где сейчас читает панель: верхний видимый стих, иначе записанное место
    func livePlace(_ id: UUID) -> Place? {
        guard let i = index(id) else { return nil }
        var p = panes[i].place
        if let v = live.verse[id] { p.verse = v }
        if let c = live.chapter[id] { p.chapter = c }
        return p
    }

    /// Сколько окон можно открыть: в режиме «Страницы» — одно (параллельные окна на страницах пока отключены),
    /// при прокрутке — шесть
    var paneLimit: Int {
        (UserDefaults.standard.string(forKey: "readingStyle") ?? "scroll") == "pages" ? 1 : maxPanes
    }

    /// Включили «Страницы», а окон больше одного — остаётся первое
    func trimToLimit() {
        guard panes.count > paneLimit else { return }
        panes = Array(panes.prefix(paneLimit))
        save()
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
        trimToLimit()
    }

    // MARK: - Первая панель (остальной код читает перевод по умолчанию отсюда)

    /// Основной перевод — тот, что отмечен звёздочкой в библиотеке (ключ primaryModule, как у Flutter-версии);
    /// не отмечен — перевод первой панели. По нему подписываются закладки, планы, проповеди, поиск и «Стих дня»
    @Published private(set) var explicitPrimary: String = UserDefaults.standard.string(forKey: "primaryModule") ?? ""

    var primaryModule: String {
        explicitPrimary.isEmpty ? (panes.first?.moduleId ?? "") : explicitPrimary
    }

    func setExplicitPrimary(_ id: String) {
        explicitPrimary = id
        UserDefaults.standard.set(id, forKey: "primaryModule")
    }

    // MARK: - Панель подстрочника — у каждого окна своя

    /// Развёрнута ли панель подстрочника в окне. Одно окно — как запомнено; несколько окон — по умолчанию свёрнута
    @Published private(set) var ilBarOpen: [UUID: Bool] = [:]

    func ilBar(_ id: UUID) -> Bool {
        if let v = ilBarOpen[id] { return v }
        if panes.count > 1 { return false }
        return UserDefaults.standard.object(forKey: "ilBar") as? Bool ?? true
    }

    func setIlBar(_ id: UUID, _ v: Bool) {
        ilBarOpen[id] = v
        if panes.count == 1 { UserDefaults.standard.set(v, forKey: "ilBar") }
    }

    // MARK: - Избранные переводы

    /// Избранные переводы (можно несколько): в окне выбора перевода они стоят наверху, в порядке добавления.
    /// Раньше «звёздочка» отмечала один основной перевод — он становится первым избранным
    @Published private(set) var favorites: [String] = {
        let d = UserDefaults.standard
        if let a = d.stringArray(forKey: "favoriteModules") { return a }
        if let p = d.string(forKey: "primaryModule"), !p.isEmpty { return [p] }
        return []
    }()

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
        UserDefaults.standard.set(favorites, forKey: "favoriteModules")
    }

    func setPrimary(_ id: String) {
        guard !panes.isEmpty else { return }
        panes[0].moduleId = id
        save()
    }

    func primaryBinding() -> Binding<String> {
        Binding(get: { self.panes.first?.moduleId ?? "" }, set: { self.setPrimary($0) })
    }

    func index(_ id: UUID) -> Int? {
        panes.firstIndex { $0.id == id }
    }

    /// Вторая и следующие панели, лежащие под первой: шапка у них не прячется при прокрутке и не заходит под строку
    /// состояния — стоит на месте, высотой ровно по содержимому
    func isLowerPane(_ id: UUID) -> Bool {
        let stacked = UserDefaults.standard.object(forKey: "panesStacked") as? Bool ?? true
        return stacked && panes.count > 1 && (index(id) ?? 0) > 0
    }

    // MARK: - Переходы

    /// Перейти в панели. record — запомнить в истории (переход по ссылке, из навигатора, поиска);
    /// соседняя глава стрелками и свайпом в историю не пишется
    /// Куда только что перешли (закладка, поиск, ссылка, навигатор): там стих на пару секунд подсвечивается,
    /// а после поиска — и найденные слова
    struct Jump {
        let id: UUID
        let at: Date
        let words: String?
        let whole: Bool
    }

    var lastJump: Jump?
    /// Номер перехода: растёт при каждом переходе по ссылке, закладке, поиску — даже на то же самое место
    /// (повторный переход на тот же стих снова прокручивает и подсвечивает его)
    @Published var jumpSeq = 0
    /// Поиск перед переходом кладёт сюда запрос — переход забирает его в lastJump
    var pendingWords: (query: String, whole: Bool)?

    func go(_ id: UUID, _ book: String, _ chapter: Int, _ verse: Int, record: Bool = true) {
        guard let i = index(id) else { return }
        if record && verse > 0 && verse < 9999 {
            lastJump = Jump(id: id, at: Date(), words: pendingWords?.query, whole: pendingWords?.whole ?? false)
            jumpSeq += 1
        }
        pendingWords = nil
        panes[i].book = book
        panes[i].chapter = chapter
        panes[i].verse = verse
        live.verse[id] = nil
        live.chapter[id] = nil
        log.record(book, chapter, verse)
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
            guard panes.count < paneLimit else {
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
        live.verse[id] = nil
        live.chapter[id] = nil
        panes[i].book = p.book
        panes[i].chapter = p.chapter
        panes[i].verse = p.verse
        log.record(p.book, p.chapter, p.verse)
        save()
    }

    func forward(_ id: UUID) {
        guard let i = index(id), panes[i].hIndex < panes[i].history.count - 1 else { return }
        panes[i].hIndex += 1
        let p = panes[i].history[panes[i].hIndex]
        live.verse[id] = nil
        live.chapter[id] = nil
        panes[i].book = p.book
        panes[i].chapter = p.chapter
        panes[i].verse = p.verse
        log.record(p.book, p.chapter, p.verse)
        save()
    }

    /// Соседняя глава; за последней главой книги — следующая книга
    /// atEnd — открыть конец предыдущей главы (листаем страницами назад)
    func step(_ id: UUID, _ delta: Int, module m: InstalledModule, atEnd: Bool = false) {
        guard let i = index(id), let bi = m.books.firstIndex(where: { $0.id == panes[i].book }) else { return }
        // от главы, которую читают сейчас (в окне глав и в сплошном тексте книги она меняется прокруткой)
        var c = (live.chapter[id] ?? panes[i].chapter) + delta
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
        go(id, m.books[b].id, max(1, c), atEnd ? 9999 : 0, record: false)
    }

    func setModule(_ id: UUID, _ moduleId: String, _ store: ModuleStore) {
        guard let i = index(id) else { return }
        // другой перевод открывается там, где читали (верхний видимый стих), а не там, куда переходили последний раз
        if let c = live.chapter[id] { panes[i].chapter = c }
        if let v = live.verse[id] { panes[i].verse = v }
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
        guard panes.count < paneLimit, let i = index(id) else { return }
        var here = panes[i].place
        if let v = live.verse[id] { here.verse = v }
        if let c = live.chapter[id] { here.chapter = c }
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
