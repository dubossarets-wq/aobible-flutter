import QuartzCore
import SwiftUI
import UIKit

// Синхронная прокрутка панелей — принцип Flutter-версии (reader_pane.dart), но напрямую на UIScrollView.
//
// Ведущая — панель, которую сейчас двигает палец (или инерция после него). Её место — это стих у верха окна и параметр
// внутри промежутка «верх этого стиха — верх следующего». Ведомые встают на тот же стих и тот же параметр на своей кривой:
// между верхними краями стихов идёт монотонная кубическая кривая (Эрмит, наклоны — среднее гармоническое соседних
// промежутков), поэтому края стихов совпадают точно, а скорость ведомой меняется плавно.
//
// Что здесь важно и почему:
//  • Смещение меняется прямо на UIScrollView в обработчике смещения ведущей — обе панели сдвигаются в одном кадре.
//    Через состояние SwiftUI ведомая отставала на кадр и каждый раз перестраивала весь экран.
//  • Положения берутся у настоящих текстовых блоков. Глава при нескольких панелях строится сразу (VStack): в LazyVStack
//    положения ещё не показанных строк приблизительные и меняются по ходу прокрутки — отсюда были скачки.
//  • Верх стиха — верх его текста: заголовок раздела входит в промежуток предыдущего стиха (в другом переводе его может не быть).
//  • Опорные точки — только стихи, которые есть в обоих переводах: стих, которого нет в одном из них, не даёт разрыва.

/// Текстовые блоки панели (UITextView стихов). Номера стихов берутся из самого текста (атрибут aobVerse)
final class VerseViews {
    private struct Ref {
        weak var view: UITextView?
    }

    private var refs: [ObjectIdentifier: Ref] = [:]

    /// Точки привязки стихов, у которых нет UITextView (подстрочный вид — столбики)
    private struct Anchor {
        weak var view: UIView?
        let verse: Int
    }

    private var anchors: [ObjectIdentifier: Anchor] = [:]

    func add(_ v: UITextView) {
        refs[ObjectIdentifier(v)] = Ref(view: v)
    }

    func addAnchor(_ verse: Int, _ v: UIView) {
        anchors[ObjectIdentifier(v)] = Anchor(view: v, verse: verse)
    }

    func aliveAnchors() -> [(verse: Int, view: UIView)] {
        anchors = anchors.filter { $0.value.view != nil }
        return anchors.values.compactMap { a in a.view.map { (a.verse, $0) } }
    }

    func alive() -> [UITextView] {
        refs = refs.filter { $0.value.view != nil }
        return refs.values.compactMap { $0.view }
    }
}

/// Размеры панели, от которых зависит расчёт. Положение «верх окна» считаем в координатах содержимого: смещение + верхний отступ
private struct PaneGeometry: Equatable {
    let contentHeight: CGFloat
    let boundsHeight: CGFloat
    let insetTop: CGFloat
    let insetBottom: CGFloat

    init(_ sv: UIScrollView) {
        contentHeight = sv.contentSize.height
        boundsHeight = sv.bounds.height
        insetTop = sv.adjustedContentInset.top
        insetBottom = sv.adjustedContentInset.bottom
    }

    /// Наибольшее положение верха окна
    var maxTop: CGFloat { max(0, contentHeight + insetTop + insetBottom - boundsHeight) }
}

/// Соответствие «верх окна ведущей → верх окна ведомой»
private struct SyncCurve {
    let from: [CGFloat]
    let to: [CGFloat]
    let fromSlope: [CGFloat]
    let toSlope: [CGFloat]
    let fromGeo: PaneGeometry
    let toGeo: PaneGeometry
    /// Поправка у конца главы: когда ведущая дошла до конца, ведомая тоже стоит у своего конца
    var delta: CGFloat = 0
    var rampStart: CGFloat = 0
    var rampLength: CGFloat = 1

    private static func harmonic(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        a > 0 && b > 0 ? 2 * a * b / (a + b) : max(a, b)
    }

    private static func hermite(_ s: CGFloat, _ d: CGFloat, _ m0: CGFloat, _ m1: CGFloat) -> CGFloat {
        let s2 = s * s, s3 = s2 * s
        return (-2 * s3 + 3 * s2) * d + (s3 - 2 * s2 + s) * m0 + (s3 - s2) * m1
    }

    /// Наклоны кривой в опорных точках: среднее гармоническое соседних промежутков — кривая монотонна и без изломов
    private static func slopes(_ y: [CGFloat]) -> [CGFloat] {
        var m = [CGFloat](repeating: 0, count: y.count)
        guard y.count >= 2 else { return m }
        m[0] = y[1] - y[0]
        m[y.count - 1] = y[y.count - 1] - y[y.count - 2]
        if y.count > 2 {
            for i in 1..<(y.count - 1) { m[i] = harmonic(y[i] - y[i - 1], y[i + 1] - y[i]) }
        }
        return m
    }

    /// Опорные точки: начало содержимого, верхи стихов, которые есть в обеих панелях, конец содержимого
    static func make(fromTops a: [Int: CGFloat], _ fromGeo: PaneGeometry, toTops b: [Int: CGFloat], _ toGeo: PaneGeometry) -> SyncCurve? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        var f: [CGFloat] = [0]
        var t: [CGFloat] = [0]
        for k in Set(a.keys).intersection(b.keys).sorted() {
            guard let ya = a[k], let yb = b[k] else { continue }
            // в сплошном тексте несколько стихов могут начинаться на одной строке
            if ya > (f.last ?? 0) + 0.5, yb > (t.last ?? 0) + 0.5 {
                f.append(ya)
                t.append(yb)
            }
        }
        f.append(max((f.last ?? 0) + 1, fromGeo.contentHeight))
        t.append(max((t.last ?? 0) + 1, toGeo.contentHeight))
        var m = SyncCurve(from: f, to: t, fromSlope: slopes(f), toSlope: slopes(t), fromGeo: fromGeo, toGeo: toGeo)
        let end = fromGeo.maxTop
        if end > 1 {
            let d = toGeo.maxTop - m.forward(end)
            let length = min(end, max(fromGeo.boundsHeight, abs(d) * 2.5))
            m.delta = d
            m.rampLength = max(1, length)
            m.rampStart = end - length
        }
        return m
    }

    /// Где верх окна ведущей: номер промежутка и параметр кривой внутри него
    func locate(_ yIn: CGFloat) -> (i: Int, s: CGFloat) {
        let y = min(max(yIn, from[0]), from[from.count - 1])
        var lo = 0, hi = from.count - 2
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if from[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        let d = from[lo + 1] - from[lo]
        let local = y - from[lo]
        var a: CGFloat = 0, b: CGFloat = 1
        for _ in 0..<24 {
            let mid = (a + b) / 2
            if Self.hermite(mid, d, fromSlope[lo], fromSlope[lo + 1]) < local { a = mid } else { b = mid }
        }
        return (lo, (a + b) / 2)
    }

    func forward(_ y: CGFloat) -> CGFloat {
        let p = locate(y)
        return to[p.i] + Self.hermite(p.s, to[p.i + 1] - to[p.i], toSlope[p.i], toSlope[p.i + 1])
    }

    /// Верх окна ведомой для верха окна ведущей
    func target(_ y: CGFloat) -> CGFloat {
        var t = forward(y)
        if delta != 0 {
            let u = min(1, max(0, (y - rampStart) / rampLength))
            t += delta * u * u * (3 - 2 * u)
        }
        return min(max(0, t), toGeo.maxTop)
    }
}

@MainActor
final class ScrollSync {
    private final class Pane {
        weak var scrollView: UIScrollView?
        var observation: NSKeyValueObservation?
        let views = VerseViews()
        /// Где был верх окна до этого события: при начале движения ведомую сравниваем с ним, а не с уже сдвинувшимся
        var lastTop: CGFloat?
    }

    private struct Follower {
        var mapping: SyncCurve
        /// Разница, которая была в начале движения: сходит на нет по пути, а не скачком
        var bias: CGFloat
        var fade: CGFloat
        var startTravel: CGFloat
    }

    private struct Session {
        let leader: UUID
        var lastEvent: CFTimeInterval
        var lastY: CGFloat
        var travel: CGFloat = 0
        var followers: [UUID: Follower] = [:]
    }

    weak var store: PanesStore?
    private var panes: [UUID: Pane] = [:]
    private var session: Session?
    private var applying = false

    private func pane(_ id: UUID) -> Pane {
        if let p = panes[id] { return p }
        let p = Pane()
        panes[id] = p
        return p
    }

    func views(_ id: UUID) -> VerseViews { pane(id).views }

    /// Прокрутка панели (UIScrollView), если она уже найдена
    func scrollView(_ id: UUID) -> UIScrollView? { panes[id]?.scrollView }

    /// Прокрутка панели найдена (см. ScrollFinder): следим за её смещением
    func attach(_ id: UUID, _ sv: UIScrollView) {
        let p = pane(id)
        guard p.scrollView !== sv else { return }
        p.scrollView = sv
        p.observation = sv.observe(\.contentOffset, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.offsetChanged(id) }
        }
    }

    func detach(_ id: UUID) {
        panes[id]?.observation?.invalidate()
        panes[id] = nil
        if session?.leader == id { session = nil }
    }

    /// Лист панели уходит с экрана (сменилась глава): наблюдение снимаем ДО того, как лист освободится, иначе
    /// система падает с «объект освобождён, пока за ним следят»
    func release(_ id: UUID, _ sv: UIScrollView) {
        guard let p = panes[id], p.scrollView === sv else { return }
        p.observation?.invalidate()
        p.observation = nil
        p.scrollView = nil
        if session?.leader == id { session = nil }
    }

    /// Верхние края текста стихов в координатах содержимого
    private func tops(_ p: Pane, _ sv: UIScrollView) -> [Int: CGFloat] {
        var out: [Int: CGFloat] = [:]
        for tv in p.views.alive() where tv.isDescendant(of: sv) {
            let storage = tv.textStorage
            guard storage.length > 0 else { continue }
            let lm = tv.layoutManager
            lm.ensureLayout(for: tv.textContainer)
            storage.enumerateAttribute(.aobVerse, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
                guard let n = v as? Int, out[n] == nil else { return }
                let g = lm.glyphIndexForCharacter(at: r.location)
                let line = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                out[n] = tv.convert(CGPoint(x: 0, y: line.minY + tv.textContainerInset.top), to: sv).y
            }
        }
        for a in p.views.aliveAnchors() where a.view.isDescendant(of: sv) && out[a.verse] == nil {
            out[a.verse] = a.view.convert(CGPoint.zero, to: sv).y
        }
        return out
    }

    private func stopOthers(except id: UUID) {
        applying = true
        for (k, p) in panes where k != id {
            if let v = p.scrollView, v.isDecelerating { v.setContentOffset(v.contentOffset, animated: false) }
        }
        applying = false
    }

    private func offsetChanged(_ id: UUID) {
        guard let p = panes[id], let sv = p.scrollView else { return }
        let previousTop = p.lastTop
        p.lastTop = sv.contentOffset.y + sv.adjustedContentInset.top
        guard !applying, let store else { return }
        // только движение от пальца: переходы к стиху и смещения, поставленные отсюда же, никуда не передаются
        guard sv.isTracking || sv.isDragging || sv.isDecelerating else { return }
        guard store.panes.count > 1, UserDefaults.standard.object(forKey: "syncScroll") as? Bool ?? true else {
            session = nil
            return
        }
        guard let srcIndex = store.index(id) else { return }
        let src = store.panes[srcIndex]
        let start = CACurrentMediaTime()
        let geo = PaneGeometry(sv)
        let y = sv.contentOffset.y + geo.insetTop

        if session == nil || session?.leader != id || start - (session?.lastEvent ?? 0) > 0.12 {
            // другую панель прямо сейчас держит другой палец — эта едет сама по себе
            if let s = session, s.leader != id, panes[s.leader]?.scrollView?.isTracking == true { return }
            session = Session(leader: id, lastEvent: start, lastY: previousTop ?? y)
            stopOthers(except: id)
        }
        let previousY = session?.lastY ?? y
        session?.travel += abs(y - previousY)
        session?.lastY = y
        session?.lastEvent = start
        let travel = session?.travel ?? 0

        for f in store.panes where f.id != id {
            guard let fp = panes[f.id], let fv = fp.scrollView, fv.window != nil, !fv.isTracking else { continue }
            if f.book != src.book || f.chapter != src.chapter {
                store.go(f.id, src.book, src.chapter, 0, record: false)
                session?.followers[f.id] = nil
                continue
            }
            let fgeo = PaneGeometry(fv)
            var st = session?.followers[f.id]
            if st == nil || st?.mapping.fromGeo != geo || st?.mapping.toGeo != fgeo {
                guard let m = SyncCurve.make(fromTops: tops(p, sv), geo, toTops: tops(fp, fv), fgeo) else { continue }
                // панели стояли немного не вместе (открыли новую, поменялась раскладка) — догоняем по пути, без рывка;
                // совсем в другом месте — сразу встаём на нужное
                var bias = fv.contentOffset.y + fgeo.insetTop - m.target(previousTop ?? y)
                if abs(bias) < 0.5 || abs(bias) > fgeo.boundsHeight { bias = 0 }
                let made = Follower(mapping: m, bias: bias, fade: max(240, abs(bias) * 4), startTravel: travel)
                st = made
                session?.followers[f.id] = made
                trace("S,\(start),\(srcIndex),\(y),\(m.from.count),\(m.delta),\(m.rampLength),\(bias),\(geo.contentHeight),\(fgeo.contentHeight)")
            }
            guard let cur = st else { continue }
            let t = min(1, (travel - cur.startTravel) / cur.fade)
            let g = 1 - t * t * (3 - 2 * t)
            let target = min(max(0, cur.mapping.target(y) + cur.bias * g), fgeo.maxTop)
            let scale = max(1, fv.traitCollection.displayScale)
            let offset = ((target - fgeo.insetTop) * scale).rounded() / scale
            let before = fv.contentOffset.y
            if abs(offset - before) >= 0.01 {
                applying = true
                fv.contentOffset = CGPoint(x: fv.contentOffset.x, y: offset)
                applying = false
            }
            trace("E,\(start),\(srcIndex),\(sv.isTracking ? 1 : 0)\(sv.isDragging ? 1 : 0)\(sv.isDecelerating ? 1 : 0),\(y),\(before),\(offset),\(fv.contentOffset.y),\(Int((CACurrentMediaTime() - start) * 1_000_000))")
        }
    }

    // MARK: - Проверка на симуляторе

    private func trace(_ line: @autoclosure () -> String) {
        #if DEBUG
        SyncTrace.write(line())
        #endif
    }

    /// -debugSync YES: две панели с разными переводами на одной главе (для автотеста и журнала sync-trace.csv)
    static func debugSetup(store: ModuleStore, panes: PanesStore) {
        #if DEBUG
        SyncTrace.write("L,start")
        guard UserDefaults.standard.bool(forKey: "debugSync"), panes.panes.count < 2 else { return }
        Task { @MainActor in
            for _ in 0..<280 {
                if store.module("rst-plus") != nil, store.module("vin-interlinear") != nil, store.starterStatus == nil { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard store.module("rst-plus") != nil, store.module("vin-interlinear") != nil else { return }
            let place = Place(book: "Matt", chapter: 5, verse: 1)
            panes.panes = ["rst-plus", "vin-interlinear"].map {
                PaneState(moduleId: $0, book: place.book, chapter: place.chapter, verse: 1, history: [place])
            }
        }
        #endif
    }
}

#if DEBUG
/// Журнал синхронной прокрутки: Documents/sync-trace.csv (только при -debugSync YES)
enum SyncTrace {
    static let on = UserDefaults.standard.bool(forKey: "debugSync") || UserDefaults.standard.bool(forKey: "debugTrace")
    private static var buffer = ""
    private static var scheduled = false
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sync-trace.csv")

    static func write(_ line: String) {
        guard on else { return }
        buffer += line + "\n"
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flush() }
    }

    private static func flush() {
        scheduled = false
        guard !buffer.isEmpty, let d = buffer.data(using: .utf8) else { return }
        buffer = ""
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(d)
            try? h.close()
        } else {
            try? d.write(to: url)
        }
    }
}
#endif

/// Находит UIScrollView, в котором лежит содержимое SwiftUI-панели, и подключает её к синхронной прокрутке
/// Свайп глав и щипок размера букв — жесты UIKit прямо на прокрутке главы. Они распознаются одновременно с прокруткой
/// и не могут её отнять. (Жесты SwiftUI на содержимом после закрытия окон — картинки, карты — начинали через раз
/// перехватывать касание, и текст прокручивался не с первого раза.)
final class ReaderGestures: NSObject, UIGestureRecognizerDelegate {
    /// dx, dy, x начала, ширина панели
    var onSwipe: (CGFloat, CGFloat, CGFloat, CGFloat) -> Void = { _, _, _, _ in }
    var onPinch: (UIGestureRecognizer.State, CGFloat) -> Void = { _, _ in }
    private weak var scrollView: UIScrollView?
    private var pan: UIPanGestureRecognizer?
    private var pinch: UIPinchGestureRecognizer?
    private var startX: CGFloat = 0

    func attach(_ sv: UIScrollView) {
        guard scrollView !== sv else { return }
        detach()
        scrollView = sv
        let p = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        let z = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        for g in [p, z] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            sv.addGestureRecognizer(g)
        }
        pan = p
        pinch = z
    }

    func detach() {
        if let p = pan { p.view?.removeGestureRecognizer(p) }
        if let z = pinch { z.view?.removeGestureRecognizer(z) }
        pan = nil
        pinch = nil
        scrollView = nil
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        switch g.state {
        case .began:
            startX = g.location(in: v).x - v.bounds.minX - g.translation(in: v).x
        case .ended:
            let t = g.translation(in: v)
            onSwipe(t.x, t.y, startX, v.bounds.width)
        default:
            break
        }
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        onPinch(g.state, g.scale)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

struct ScrollFinder: UIViewRepresentable {
    let sync: ScrollSync
    let paneID: UUID
    var gestures: ReaderGestures? = nil

    final class FinderView: UIView {
        var onFound: ((UIScrollView) -> Void)?
        var onGone: ((UIScrollView) -> Void)?
        private weak var found: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                if let sv = found { onGone?(sv) }
            } else {
                lookUp()
            }
        }

        func lookUp() {
            guard window != nil else { return }
            var v = superview
            while let cur = v {
                if let sv = cur as? UIScrollView {
                    found = sv
                    onFound?(sv)
                    return
                }
                v = cur.superview
            }
        }
    }

    func makeUIView(context: Context) -> FinderView {
        let v = FinderView()
        v.isUserInteractionEnabled = false
        v.onFound = { [sync, paneID, gestures] sv in
            sync.attach(paneID, sv)
            gestures?.attach(sv)
        }
        v.onGone = { [sync, paneID, gestures] sv in
            sync.release(paneID, sv)
            gestures?.detach()
        }
        return v
    }

    func updateUIView(_ v: FinderView, context: Context) {
        v.onFound = { [sync, paneID, gestures] sv in
            sync.attach(paneID, sv)
            gestures?.attach(sv)
        }
        v.lookUp()
    }
}
