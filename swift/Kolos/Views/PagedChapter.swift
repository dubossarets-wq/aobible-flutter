import SwiftUI
import UIKit

/// Режим «Страницы»: глава разбита на страницы по размеру окна. Страницы лежат лентой и листаются жестом вправо и влево
/// или нажатием у левого или правого края: текст уезжает в сторону, следующий приезжает (без «заворота» листа). За
/// последней страницей — следующая глава, перед первой — предыдущая (тоже сдвигом). Нажатие на слово, двойное касание
/// и долгое нажатие работают как в обычном режиме.
struct PagedChapter: UIViewControllerRepresentable {
    let text: NSAttributedString
    /// Меняется, когда главу надо разбить заново (другая глава, перевод, шрифт, поля)
    let key: String
    /// Стих, с которого открыть; 9999 — последняя страница (пришли назад из следующей главы)
    let focus: Int
    /// Стих, который не помещается на странице, уходит на следующую целиком (иначе — только строки, что не поместились)
    var wholeVerses = false
    let insets: UIEdgeInsets
    /// Цвет фона темы (страницы прозрачные: под ними неподвижный фон, по нему едет только текст)
    var pageColor: UIColor = .systemBackground
    var onTap: (URL?, Int) -> Void
    var onDouble: (Int) -> Void
    var onLong: (Int) -> Void
    /// Идёт выделение: одиночное касание срабатывает сразу (двойного не ждём)
    var selecting = false
    /// Страница показана: верхний стих, номер страницы (с 1), число страниц, листнул ли её сам человек
    /// (тогда за ней листают и другие окна — см. PageSync)
    var onPage: (Int, Int, Int, Bool) -> Void
    /// Дошли до края главы: +1 — следующая, −1 — предыдущая
    var onEdge: (Int) -> Void
    /// Окно и общая синхронизация страниц окон
    var paneID: UUID? = nil
    var sync: PageSync? = nil
    /// Подстрочный перевод: страницы собираются из готовых блоков (заголовок, стих столбиками), а не из текста.
    /// Блоки — самостоятельные SwiftUI-вью (без окружения); высота каждого измеряется, потом они кладутся на страницы
    var blocks: [PageBlock]? = nil
    /// Расстояние между блоками на странице
    var blockSpacing: CGFloat = 8
    /// Щипок (размер букв): страницу масштабируем картинкой напрямую, без перерисовки экрана (см. PinchBox)
    var zoomBox: PinchBox? = nil

    func makeUIViewController(context: Context) -> PagerHost {
        let h = PagerHost()
        h.apply(self)
        if let id = paneID { sync?.register(id, h) }
        zoomBox?.host = h
        return h
    }

    func updateUIViewController(_ h: PagerHost, context: Context) {
        h.apply(self)
        if let id = paneID { sync?.register(id, h) }
        zoomBox?.host = h
    }
}

/// Связь жеста щипка с листалкой: пока пальцы двигаются, меняется только масштаб картинки страниц (мгновенно), а
/// настоящий размер букв — один раз в конце. Ссылочный тип: изменения не перерисовывают экран чтения
final class PinchBox {
    weak var host: PagerHost?
}

/// Блок страницы подстрочного перевода. verse — стих, к которому он относится (заголовок раздела — стих после него);
/// keepWithNext — заголовок не остаётся один внизу страницы, уходит вместе со стихом
struct PageBlock: Identifiable {
    let id: Int
    let verse: Int
    let keepWithNext: Bool
    let view: AnyView
}

/// Страничный режим при нескольких окнах — как синхронная прокрутка (ScrollSync): окно, которое листают, ведёт, другие
/// едут вместе с ним в том же кадре. Ведущая страница i → ведомая — страница, где начинается первый стих страницы i;
/// между страницами ведомая сдвигается пропорционально (если тот же стих у неё на той же странице — стоит). Отпустили —
/// ведомые встают ровно на страницу. Окно в другой главе переходит в главу ведущего (тоже сдвигом)
@MainActor
final class PageSync {
    private struct Ref { weak var host: PagerHost? }
    weak var store: PanesStore?
    private var hosts: [UUID: Ref] = [:]

    func register(_ id: UUID, _ h: PagerHost) {
        if hosts[id]?.host !== h { hosts[id] = Ref(host: h) }
    }

    /// Какие стихи начинают страницы у каждого окна (после разбивки главы)
    private var starts: [UUID: Set<Int>] = [:]

    func forget(_ id: UUID) { starts[id] = nil }

    /// Окно разбило главу на страницы. Чтобы на одной странице у окон были одни и те же стихи, границы страниц у всех
    /// окон одной главы — объединение границ каждого: если хоть в одном окне стих не поместился и начал новую страницу,
    /// во всех окнах с него начинается страница. Все страницы после этого — части прежних, поэтому места хватает
    func layoutReady(_ id: UUID, starts s: Set<Int>) {
        starts[id] = s
        guard let store else { return }
        guard store.panes.count > 1, let me = store.panes.first(where: { $0.id == id }) else {
            hosts[id]?.host?.setForcedBreaks([])
            return
        }
        var union = Set<Int>()
        var group: [UUID] = []
        for p in store.panes where p.book == me.book && p.chapter == me.chapter {
            if let st = starts[p.id] {
                union.formUnion(st)
                group.append(p.id)
            }
        }
        for g in group { hosts[g]?.host?.setForcedBreaks(union) }
    }

    private var on: Bool {
        guard let store else { return false }
        return store.panes.count > 1 && (UserDefaults.standard.object(forKey: "syncScroll") as? Bool ?? true)
    }

    private func followers(of id: UUID) -> [(PaneState, PagerHost)] {
        guard let store, let src = store.panes.first(where: { $0.id == id }) else { return [] }
        return store.panes.compactMap { f in
            guard f.id != id, f.book == src.book, f.chapter == src.chapter,
                  let h = hosts[f.id]?.host, h.viewIfLoaded?.window != nil else { return nil }
            return (f, h)
        }
    }

    /// Ведущее окно сдвинулось: page — дробный номер страницы (0 — первая)
    func scrolled(_ id: UUID, page: CGFloat, anchors: [Int]) {
        guard on else { return }
        for (_, h) in followers(of: id) { h.mirror(page, anchors: anchors) }
    }

    /// Ведущее окно встало на страницу (листнул человек): у верха страницы стих verse главы book/chapter
    func turned(_ id: UUID, book: String, chapter: Int, verse: Int) {
        guard on, let store else { return }
        let lead = hosts[id]?.host
        let anchor = lead?.anchorVerse ?? verse
        let dir = lead?.takeEdgeDir() ?? 0
        for f in store.panes where f.id != id {
            if f.book == book && f.chapter == chapter, let h = hosts[f.id]?.host, h.viewIfLoaded?.window != nil {
                h.follow(anchor)
            } else {
                // в другой главе — туда же, с тем же сдвигом, что у ведущего
                if dir != 0 { hosts[f.id]?.host?.expectSlide(dir) }
                store.go(f.id, book, chapter, max(1, anchor), record: false)
            }
        }
    }
}

final class PagerHost: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let storage = NSTextStorage()
    private let layout = PlateLayoutManager()
    private var containers: [NSTextContainer] = []
    /// Страницы на экране и рядом (остальные не создаются)
    private var cells: [Int: UIView] = [:]
    /// Режим блоков (подстрочник): блоки каждой страницы и стих у её верха
    private var blockPages: [[Int]] = []
    private var blockTops: [Int] = []
    private let measurer = UIHostingController(rootView: AnyView(EmptyView()))
    private var isBlocks: Bool { cfg?.blocks != nil }
    private var pageCount: Int { isBlocks ? blockPages.count : containers.count }
    private var current = 0
    /// Листнули за край главы: соседняя глава въедет с этой стороны (+1 — справа, −1 — слева)
    private var pendingDir = 0
    /// Последний переход в соседнюю главу (для других окон)
    private var edgeDir = 0
    /// В соседнюю главу перелистнул человек в этом окне (а не пришли следом за другим)
    private var ownEdge = false
    private(set) var cfg: PagedChapter?
    /// Стихи, с которых страница начинается принудительно (границы, о которых договорились окна, см. PageSync)
    private var forced: Set<Int> = []
    private var builtForced: Set<Int> = []
    private var builtKey = ""
    private var builtSize = CGSize.zero
    private var lastFocus = -1
    /// Стих у верха текущей страницы: при пересборке (другой шрифт, дозагрузились модули) остаёмся на нём
    private var topVerse = 1
    /// Опорный стих страницы: первый, что на ней начинается (нет — стих у её верха). По нему встают другие окна
    private(set) var anchors: [Int] = []
    /// Стихи по порядку и страница, где каждый начинается
    private var verseOrder: [Int] = []
    private var verseStart: [Int: Int] = [:]
    private let counter = UILabel()
    /// Листание нажатием у края — ведёт это окно
    private var userAnimating = false
    /// Смещение ставит другое окно — дальше не передаём
    private var applying = false

    var anchorVerse: Int { current < anchors.count ? anchors[current] : topVerse }

    /// Щипок идёт: страницы растянуты картинкой (1 — без растяжения)
    private var zoomPending = false

    func setZoom(_ s: CGFloat) {
        zoomPending = false
        view.transform = s == 1 ? .identity : CGAffineTransform(scaleX: s, y: s)
    }

    /// Щипок закончился, новый размер уже записан: растянутая страница остаётся, пока не готова новая вёрстка
    /// (иначе на миг мелькнул бы прежний размер); страховка — не дольше секунды
    func holdZoomUntilRebuild() {
        zoomPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.zoomPending else { return }
            self.zoomPending = false
            self.view.transform = .identity
        }
    }

    func takeEdgeDir() -> Int {
        let d = edgeDir
        edgeDir = 0
        return d
    }

    /// Окна договорились о границах страниц: пересобираем страницы с ними
    func setForcedBreaks(_ u: Set<Int>) {
        guard u != forced else { return }
        forced = u
        if isViewLoaded { rebuildIfNeeded() }
    }

    /// Другое окно ушло в соседнюю главу — эта глава въедет с той же стороны
    func expectSlide(_ dir: Int) { pendingDir = dir }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        storage.addLayoutManager(layout)
        scroll.delegate = self
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.decelerationRate = .fast
        view.addSubview(scroll)
        counter.font = .systemFont(ofSize: 12, weight: .medium)
        counter.textColor = .secondaryLabel
        counter.textAlignment = .center
        view.addSubview(counter)
        rebuildIfNeeded()
    }

    func apply(_ c: PagedChapter) {
        cfg = c
        if isViewLoaded { rebuildIfNeeded() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scroll.frame != view.bounds { scroll.frame = view.bounds }
        counter.frame = CGRect(x: 0, y: view.bounds.height - 26, width: view.bounds.width, height: 18)
        rebuildIfNeeded()
    }

    private var pageSize: CGSize? {
        guard let c = cfg else { return nil }
        let i = insets(c)
        let s = CGSize(width: view.bounds.width - i.left - i.right, height: view.bounds.height - i.top - i.bottom)
        return s.width > 60 && s.height > 100 ? s : nil
    }

    /// Поля страницы плюс то, что закрывает сверху (шапка) и снизу
    func insets(_ c: PagedChapter) -> UIEdgeInsets {
        UIEdgeInsets(top: c.insets.top + view.safeAreaInsets.top, left: c.insets.left, bottom: c.insets.bottom + view.safeAreaInsets.bottom, right: c.insets.right)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        rebuildIfNeeded()
    }

    /// Тап в поле слева (−1) или справа (+1) от текста; на самом тексте — nil. Поле — отступ страницы от края окна,
    /// но не уже 24 пт (иначе в него не попасть пальцем)
    func marginSide(_ x: CGFloat, in width: CGFloat) -> Int? {
        guard let c = cfg else { return nil }
        let ins = insets(c)
        if x < max(ins.left, 24) { return -1 }
        if x > width - max(ins.right, 24) { return 1 }
        return nil
    }

    private var pageWidth: CGFloat { max(1, scroll.bounds.width) }

    private func rebuildIfNeeded() {
        guard let c = cfg, let size = pageSize else { return }
        if c.key == builtKey && size == builtSize && forced == builtForced && (c.blocks != nil || c.text.length == storage.length) {
            // тот же вид: изменился только вид текста (выделение, закладки) — вёрстка прежняя
            if c.blocks != nil {
                refreshBlocks(c)
            } else if !storage.isEqual(to: c.text) {
                storage.setAttributedString(c.text)
            }
            if c.focus != lastFocus {
                lastFocus = c.focus
                let i = pageIndex(forVerse: c.focus)
                if i != current { show(i) }
            }
            return
        }
        // пересборка: первый раз — на стихе из панели, дальше — на том же стихе, что был у верха страницы;
        // перешли в соседнюю главу — на стихе из панели (начало или конец главы)
        let dir = pendingDir
        pendingDir = 0
        let sameChapter = !builtKey.isEmpty && c.key.split(separator: "|").prefix(3) == builtKey.split(separator: "|").prefix(3)
        let startVerse = dir != 0 || !sameChapter ? c.focus : topVerse
        let own = ownEdge
        ownEdge = false
        // другая глава, шрифт или размер окна — прежние общие границы не годятся, окна договариваются заново
        if c.key != builtKey || size != builtSize {
            forced = []
            if let id = c.paneID { c.sync?.forget(id) }
        }
        // снимок нынешней страницы — он уедет, новая глава въедет следом
        let snap: UIView? = dir != 0 && !builtKey.isEmpty ? scroll.snapshotView(afterScreenUpdates: false) : nil
        builtKey = c.key
        builtSize = size
        builtForced = forced
        lastFocus = c.focus
        for (_, cell) in cells { cell.removeFromSuperview() }
        cells = [:]
        if let blocks = c.blocks {
            containers = []
            buildBlocks(blocks, c, size)
        } else {
            blockPages = []
            blockTops = []
            storage.setAttributedString(c.text)
            while layout.textContainers.count > 0 { layout.removeTextContainer(at: 0) }
            containers = []
            // где начинается каждый стих (для принудительных границ)
            var firstLoc: [Int: Int] = [:]
            if !forced.isEmpty, storage.length > 0 {
                storage.enumerateAttribute(.aobVerse, in: NSRange(location: 0, length: storage.length), options: []) { val, r, _ in
                    if let n = val as? Int, firstLoc[n] == nil { firstLoc[n] = r.location }
                }
            }
            for _ in 0..<500 {
                let tc = NSTextContainer(size: size)
                tc.lineFragmentPadding = 0
                layout.addTextContainer(tc)
                containers.append(tc)
                layout.ensureLayout(for: tc)
                if !forced.isEmpty { applyForcedBreak(tc, size, firstLoc) }
                if NSMaxRange(layout.glyphRange(for: tc)) >= layout.numberOfGlyphs { break }
                if c.wholeVerses { pushStraddlingVerse(tc, size) }
            }
            indexVerses()
        }
        let w = pageWidth
        scroll.contentSize = CGSize(width: w * CGFloat(max(1, pageCount)), height: scroll.bounds.height)
        let i = pageIndex(forVerse: startVerse)
        current = i
        applying = true
        scroll.setContentOffset(CGPoint(x: CGFloat(i) * w, y: 0), animated: false)
        applying = false
        tile()
        if zoomPending {
            zoomPending = false
            view.transform = .identity
        }
        if let s = snap {
            // старая глава уезжает, новая въезжает с той же стороны — одним движением
            if own { edgeDir = dir }
            s.frame = scroll.frame
            view.insertSubview(s, aboveSubview: scroll)
            scroll.transform = CGAffineTransform(translationX: CGFloat(dir) * w, y: 0)
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                s.transform = CGAffineTransform(translationX: -CGFloat(dir) * w, y: 0)
                self.scroll.transform = .identity
            } completion: { _ in s.removeFromSuperview() }
        }
        // в соседнюю главу перелистнул сам человек — за ним и другие окна
        report(i, user: own && dir != 0)
        // границы страниц — окнам одной главы: чтобы на странице у всех были одни и те же стихи
        if let id = c.paneID, let sync = c.sync {
            let starts = Set(anchors)
            DispatchQueue.main.async { sync.layoutReady(id, starts: starts) }
        }
    }

    /// Подстрочник: измеряем высоту каждого блока и кладём блоки на страницы подряд (стих целиком; заголовок — вместе
    /// со стихом). Опорный стих страницы — первый на ней
    private func buildBlocks(_ blocks: [PageBlock], _ c: PagedChapter, _ size: CGSize) {
        measurer.sizingOptions = []
        var heights: [CGFloat] = []
        for b in blocks {
            measurer.rootView = AnyView(b.view.frame(width: size.width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true))
            heights.append(ceil(measurer.sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude)).height))
        }
        let gap = c.blockSpacing
        var pages: [[Int]] = [[]]
        var y: CGFloat = 0
        for i in blocks.indices {
            var need = heights[i]
            if blocks[i].keepWithNext, i + 1 < blocks.count { need += gap + heights[i + 1] }
            // страница начинается с этого стиха по общей договорённости окон
            let startsVerse = i == 0 || blocks[i].verse != blocks[i - 1].verse
            if y > 0, (startsVerse && forced.contains(blocks[i].verse)) || y + need > size.height {
                pages.append([])
                y = 0
            }
            pages[pages.count - 1].append(i)
            y += heights[i] + gap
        }
        blockPages = pages.filter { !$0.isEmpty }
        blockTops = blockPages.map { blocks[$0[0]].verse }
        verseOrder = []
        verseStart = [:]
        for (p, idxs) in blockPages.enumerated() {
            for k in idxs {
                let n = blocks[k].verse
                if n > 0, verseStart[n] == nil {
                    verseStart[n] = p
                    verseOrder.append(n)
                }
            }
        }
        anchors = blockTops
    }

    /// Блоки обновились (выделение, любимые) — страницы на экране получают новые вью, вёрстка прежняя
    private func refreshBlocks(_ c: PagedChapter) {
        guard let blocks = c.blocks else { return }
        for (i, cell) in cells {
            guard let bc = cell as? BlockPageCell, i < blockPages.count else { continue }
            bc.show(blockPages[i].map { blocks[$0] }, spacing: c.blockSpacing, ins: insets(c))
        }
    }

    /// На этой странице начинается стих из общих границ (не с самого верха) — остаток страницы закрываем: стих и всё
    /// после него ляжет на следующую
    private func applyForcedBreak(_ tc: NSTextContainer, _ size: CGSize, _ firstLoc: [Int: Int]) {
        let gr = layout.glyphRange(for: tc)
        let cr = layout.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        let end = NSMaxRange(cr)
        guard cr.length > 0, end < storage.length else { return }
        var at: Int?
        for v in forced {
            if let loc = firstLoc[v], loc > cr.location, loc < end, at == nil || loc < at! { at = loc }
        }
        guard let loc = at else { return }
        let g = layout.glyphIndexForCharacter(at: loc)
        let y = layout.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY
        guard y > 1, y < size.height else { return }
        tc.exclusionPaths = [UIBezierPath(rect: CGRect(x: -20, y: y, width: size.width + 40, height: size.height))]
        layout.invalidateLayout(forCharacterRange: NSRange(location: cr.location, length: storage.length - cr.location), actualCharacterRange: nil)
        layout.ensureLayout(for: tc)
    }

    /// Последний стих страницы переходит на следующую: если он начался на этой странице (не с самого верха), закрываем
    /// ему остаток страницы — текст стиха (и заголовок раздела перед ним) сам ляжет на следующую
    private func pushStraddlingVerse(_ tc: NSTextContainer, _ size: CGSize) {
        let gr = layout.glyphRange(for: tc)
        let cr = layout.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        let end = NSMaxRange(cr)
        guard cr.length > 0, end < storage.length,
              let v = storage.attribute(.aobVerse, at: end - 1, effectiveRange: nil) as? Int,
              (storage.attribute(.aobVerse, at: end, effectiveRange: nil) as? Int) == v else { return }
        // где этот стих начинается
        var first = end - 1
        while first > cr.location, (storage.attribute(.aobVerse, at: first - 1, effectiveRange: nil) as? Int) == v { first -= 1 }
        guard first > cr.location else { return }   // с самого верха страницы и всё равно не помещается — не трогаем
        let g = layout.glyphIndexForCharacter(at: first)
        let y = layout.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY
        guard y > 1, y < size.height else { return }
        tc.exclusionPaths = [UIBezierPath(rect: CGRect(x: -20, y: y, width: size.width + 40, height: size.height))]
        layout.invalidateLayout(forCharacterRange: NSRange(location: cr.location, length: storage.length - cr.location), actualCharacterRange: nil)
        layout.ensureLayout(for: tc)
    }

    /// Где начинается каждый стих и опорный стих каждой страницы
    private func indexVerses() {
        verseOrder = []
        verseStart = [:]
        var firstOnPage = [Int](repeating: 0, count: containers.count)
        guard storage.length > 0, !containers.isEmpty else { anchors = []; return }
        storage.enumerateAttribute(.aobVerse, in: NSRange(location: 0, length: storage.length), options: []) { val, r, _ in
            guard let n = val as? Int, verseStart[n] == nil else { return }
            var range = NSRange()
            guard let tc = layout.textContainer(forGlyphAt: layout.glyphIndexForCharacter(at: r.location), effectiveRange: &range),
                  let p = containers.firstIndex(where: { $0 === tc }) else { return }
            verseStart[n] = p
            verseOrder.append(n)
            if firstOnPage[p] == 0 { firstOnPage[p] = n }
        }
        anchors = containers.indices.map { p in firstOnPage[p] != 0 ? firstOnPage[p] : verseAtTop(p) }
    }

    private func verseAtTop(_ p: Int) -> Int {
        if isBlocks { return p < blockTops.count ? blockTops[p] : 1 }
        let gr = layout.glyphRange(for: containers[p])
        let cr = layout.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        guard cr.length > 0, cr.location < storage.length else { return 1 }
        return (storage.attribute(.aobVerse, at: cr.location, effectiveRange: nil) as? Int) ?? 1
    }

    /// Страница, где начинается стих; такого стиха нет в этом переводе — ближайший следующий
    private func pageIndex(forVerse v: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        if v >= 9999 { return pageCount - 1 }
        if let p = verseStart[v] { return p }
        if let n = verseOrder.first(where: { $0 >= v }), let p = verseStart[n] { return p }
        return v > (verseOrder.last ?? 0) ? pageCount - 1 : 0
    }

    // MARK: - Страницы на экране

    /// Создаёт страницы у текущей (и по одной с каждой стороны), убирает дальние
    private func tile() {
        guard pageCount > 0, let c = cfg else { return }
        let w = pageWidth
        let p = Int(floor(scroll.contentOffset.x / w))
        let lo = max(0, p - 1), hi = min(pageCount - 1, p + 2)
        for (i, cell) in cells where i < lo || i > hi {
            cell.removeFromSuperview()
            cells[i] = nil
        }
        guard lo <= hi else { return }
        let ins = insets(c)
        for i in lo...hi where cells[i] == nil {
            let frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: scroll.bounds.height)
            if let blocks = c.blocks, i < blockPages.count {
                let cell = BlockPageCell(host: self)
                cell.frame = frame
                cell.show(blockPages[i].map { blocks[$0] }, spacing: c.blockSpacing, ins: ins)
                scroll.addSubview(cell)
                cells[i] = cell
            } else if i < containers.count {
                let cell = PageCell(container: containers[i], host: self)
                cell.frame = frame
                cell.layoutText(ins)
                scroll.addSubview(cell)
                cells[i] = cell
            }
        }
    }

    private func show(_ i: Int) {
        guard i >= 0, i < pageCount else { return }
        applying = true
        scroll.setContentOffset(CGPoint(x: CGFloat(i) * pageWidth, y: 0), animated: false)
        applying = false
        tile()
        landed(i, user: false)
    }

    /// Листание нажатием у края: +1 вперёд, −1 назад (сдвигом; другие окна едут вместе)
    func turn(_ d: Int) {
        let t = current + d
        if t < 0 { edge(-1); return }
        if t >= pageCount { edge(1); return }
        userAnimating = true
        scroll.setContentOffset(CGPoint(x: CGFloat(t) * pageWidth, y: 0), animated: true)
    }

    /// За краем главы — сразу соседняя глава
    private func edge(_ d: Int) {
        guard pendingDir == 0 else { return }
        pendingDir = d
        ownEdge = true
        cfg?.onEdge(d)
        // в начале или конце Библии главы нет — ключ не сменится, ждать нечего
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.pendingDir = 0
            self?.ownEdge = false
        }
    }

    // MARK: - Ведомое окно

    /// Ведущее окно на дробной странице page (её опорные стихи — anchors): встаём на соответствующее место
    func mirror(_ page: CGFloat, anchors la: [Int]) {
        guard !scroll.isTracking, !la.isEmpty, pageCount > 0 else { return }
        let last = la.count - 1
        let i = min(max(0, Int(floor(page))), last)
        let f = min(max(0, page - CGFloat(i)), 1)
        let ji = pageIndex(forVerse: la[i])
        let jn = i < last ? pageIndex(forVerse: la[i + 1]) : ji
        let target = min(max(0, CGFloat(ji) + f * CGFloat(jn - ji)), CGFloat(pageCount - 1))
        let x = (target * pageWidth).rounded()
        guard abs(scroll.contentOffset.x - x) > 0.25 else { return }
        applying = true
        scroll.contentOffset = CGPoint(x: x, y: 0)
        applying = false
        tile()
    }

    /// Ведущее окно встало на страницу: ровно на страницу с её опорным стихом
    func follow(_ verse: Int) {
        guard pageCount > 0 else { return }
        lastFocus = verse
        let i = pageIndex(forVerse: verse)
        if i != current || abs(scroll.contentOffset.x - CGFloat(i) * pageWidth) > 0.5 { show(i) }
    }

    // MARK: - Прокрутка

    private var leading: Bool { scroll.isTracking || scroll.isDragging || scroll.isDecelerating || userAnimating }

    func scrollViewDidScroll(_ s: UIScrollView) {
        tile()
        guard !applying, leading, let id = cfg?.paneID else { return }
        cfg?.sync?.scrolled(id, page: s.contentOffset.x / pageWidth, anchors: anchors)
    }

    func scrollViewWillEndDragging(_ s: UIScrollView, withVelocity v: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // потянули за первую или последнюю страницу — соседняя глава
        let w = pageWidth
        let maxX = s.contentSize.width - w
        if s.contentOffset.x < -w * 0.12 || (current == 0 && s.contentOffset.x < 0 && v.x < -0.6) {
            edge(-1)
        } else if s.contentOffset.x > maxX + w * 0.12 || (current == pageCount - 1 && s.contentOffset.x > maxX && v.x > 0.6) {
            edge(1)
        }
    }

    func scrollViewDidEndDecelerating(_ s: UIScrollView) { settle() }

    func scrollViewDidEndDragging(_ s: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { settle() }
    }

    func scrollViewDidEndScrollingAnimation(_ s: UIScrollView) {
        userAnimating = false
        settle()
    }

    /// Остановились: страница, на которой стоим, — текущая
    private func settle() {
        guard pageCount > 0 else { return }
        let i = min(max(0, Int((scroll.contentOffset.x / pageWidth).rounded())), pageCount - 1)
        if i != current { landed(i, user: true) }
    }

    private func landed(_ i: Int, user: Bool) {
        current = i
        report(i, user: user)
    }

    private func report(_ i: Int, user: Bool) {
        guard i >= 0, i < pageCount else { return }
        topVerse = verseAtTop(i)
        let total = max(1, pageCount)
        counter.text = "\(i + 1) / \(total)"
        cfg?.onPage(topVerse, i + 1, total, user)
    }
}

/// Страница подстрочника: блоки (SwiftUI) столбиком сверху вниз
final class BlockPageCell: UIView {
    private let hc = UIHostingController(rootView: AnyView(EmptyView()))
    private weak var host: PagerHost?

    init(host: PagerHost) {
        self.host = host
        super.init(frame: .zero)
        backgroundColor = .clear
        hc.view.backgroundColor = .clear
        hc.sizingOptions = []
        if #available(iOS 16.4, *) { hc.safeAreaRegions = [] }
        host.addChild(hc)
        addSubview(hc.view)
        hc.didMove(toParent: host)
        // поля по бокам от столбиков (вне содержимого) — листание тапом
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let h = host, let side = h.marginSide(g.location(in: self).x, in: bounds.width) else { return }
        h.turn(side)
    }

    func show(_ blocks: [PageBlock], spacing: CGFloat, ins: UIEdgeInsets) {
        hc.rootView = AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(blocks) { $0.view }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
        hc.view.frame = bounds.inset(by: ins)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hc.view.frame = bounds.inset(by: host?.cfg.map { host?.insets($0) ?? .zero } ?? .zero)
    }

    override func removeFromSuperview() {
        hc.willMove(toParent: nil)
        hc.view.removeFromSuperview()
        hc.removeFromParent()
        super.removeFromSuperview()
    }
}

/// Страница текста: свой кусок главы (свой NSTextContainer общей вёрстки) и нажатия
final class PageCell: UIView {
    private let textView: UITextView
    private var touch: PageTouch?

    init(container: NSTextContainer, host: PagerHost) {
        textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        backgroundColor = .clear
        let tv = textView
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        // запас по краям для плашек части стиха (см. VerseTextView.bleed); поле на столько же шире страницы текста
        tv.textContainerInset = UIEdgeInsets(top: VerseTextView.bleed, left: VerseTextView.bleed, bottom: VerseTextView.bleed, right: VerseTextView.bleed)
        tv.isUserInteractionEnabled = false
        addSubview(tv)
        let t = PageTouch(host: host, textView: tv)
        t.attach(to: self)
        touch = t
    }

    required init?(coder: NSCoder) { nil }

    func layoutText(_ ins: UIEdgeInsets) {
        textView.frame = bounds.inset(by: ins).insetBy(dx: -VerseTextView.bleed, dy: -VerseTextView.bleed)
    }
}

/// Нажатия на странице: у левого и правого края — листание, иначе слово, двойное касание, долгое нажатие
final class PageTouch: NSObject, UIGestureRecognizerDelegate {
    private weak var host: PagerHost?
    private weak var textView: UITextView?
    private var lpActive = false
    private var lpEnded = Date.distantPast
    /// Где палец коснулся: сдвинулся дальше 12 пт — это листание, а не нажатие
    private var downAt: CGPoint?

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let t = g as? UITapGestureRecognizer, t.numberOfTapsRequired == 1 { downAt = touch.location(in: g.view) }
        return true
    }

    init(host: PagerHost, textView: UITextView) {
        self.host = host
        self.textView = textView
    }

    func attach(to v: UIView) {
        let single = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let double = UITapGestureRecognizer(target: self, action: #selector(double(_:)))
        double.numberOfTapsRequired = 2
        let long = UILongPressGestureRecognizer(target: self, action: #selector(long(_:)))
        long.minimumPressDuration = 0.25
        long.allowableMovement = 12
        for g in [single, double, long] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            v.addGestureRecognizer(g)
        }
    }

    private func hit(_ p: CGPoint, in v: UIView) -> (url: URL?, verse: Int) {
        guard let tv = textView else { return (nil, 1) }
        var q = tv.convert(p, from: v)
        q.x -= tv.textContainerInset.left
        q.y -= tv.textContainerInset.top
        let lm = tv.layoutManager
        let tc = tv.textContainer
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: q, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        let storage = tv.textStorage
        guard idx >= 0, idx < storage.length else { return (nil, 1) }
        let verse = (storage.attribute(.aobVerse, at: idx, effectiveRange: nil) as? Int) ?? 1
        let g = lm.glyphIndexForCharacter(at: idx)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        guard rect.insetBy(dx: -6, dy: -6).contains(q) else { return (nil, verse) }
        return (storage.attribute(.aobURL, at: idx, effectiveRange: nil) as? URL, verse)
    }

    @objc func tap(_ g: UITapGestureRecognizer) {
        #if DEBUG
        SyncTrace.write("T,tap,\(g.state.rawValue),\(g.location(in: g.view).x),\(g.view?.bounds.width ?? 0),lp=\(lpActive)")
        #endif
        guard g.state == .ended, let v = g.view else { return }
        if lpActive || Date().timeIntervalSince(lpEnded) < 0.4 { return }
        let p = g.location(in: v)
        if let d = downAt, hypot(p.x - d.x, p.y - d.y) > 12 { return }
        // листание тапом — только в полях слева и справа от текста (до края окна), на словах — слово
        if let side = host?.marginSide(p.x, in: v.bounds.width) { host?.turn(side); return }
        let h = hit(p, in: v)
        pendingTap?.cancel()
        if host?.cfg?.selecting == true {
            pendingTap = nil
            host?.cfg?.onTap(h.url, h.verse)
            return
        }
        // ждём, не будет ли второго касания (см. VerseTextView)
        let item = DispatchWorkItem { [weak self] in
            self?.pendingTap = nil
            self?.host?.cfg?.onTap(h.url, h.verse)
        }
        pendingTap = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: item)
    }

    private var pendingTap: DispatchWorkItem?

    @objc func double(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let v = g.view else { return }
        pendingTap?.cancel()
        pendingTap = nil
        if lpActive || Date().timeIntervalSince(lpEnded) < 0.4 { return }
        host?.cfg?.onDouble(hit(g.location(in: v), in: v).verse)
    }

    @objc func long(_ g: UILongPressGestureRecognizer) {
        guard let v = g.view else { return }
        switch g.state {
        case .began:
            lpActive = true
            pendingTap?.cancel()
            pendingTap = nil
            host?.cfg?.onLong(hit(g.location(in: v), in: v).verse)
        case .ended, .cancelled, .failed:
            if lpActive {
                lpActive = false
                lpEnded = Date()
            }
        default:
            break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g.view != nil && g.view === other.view
    }
}
