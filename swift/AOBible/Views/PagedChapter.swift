import SwiftUI
import UIKit

/// Режим «Страницы» — как в «Книгах» (iBooks): глава разбита на страницы по размеру экрана, листаются жестом вправо и влево
/// (страница «заворачивается») и нажатием у левого или правого края. За последней страницей — следующая глава, перед
/// первой — предыдущая. Нажатие на слово, двойное касание и долгое нажатие работают как в обычном режиме.
struct PagedChapter: UIViewControllerRepresentable {
    let text: NSAttributedString
    /// Меняется, когда главу надо разбить заново (другая глава, перевод, шрифт, поля)
    let key: String
    /// Стих, с которого открыть; 9999 — последняя страница (пришли назад из следующей главы)
    let focus: Int
    let insets: UIEdgeInsets
    var onTap: (URL?, Int) -> Void
    var onDouble: (Int) -> Void
    var onLong: (Int) -> Void
    /// Страница показана: верхний стих, номер страницы (с 1), число страниц
    var onPage: (Int, Int, Int) -> Void
    /// Дошли до края главы: +1 — следующая, −1 — предыдущая
    var onEdge: (Int) -> Void

    func makeUIViewController(context: Context) -> PagerHost {
        let h = PagerHost()
        h.apply(self)
        return h
    }

    func updateUIViewController(_ h: PagerHost, context: Context) {
        h.apply(self)
    }
}

final class PagerHost: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let pvc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private var containers: [NSTextContainer] = []
    /// 0 — переход в предыдущую главу, последняя — в следующую, между ними — страницы текста
    private var pages: [UIViewController] = []
    private var current = 1
    private(set) var cfg: PagedChapter?
    private var builtKey = ""
    private var builtSize = CGSize.zero
    private var lastFocus = -1
    private let counter = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        storage.addLayoutManager(layout)
        pvc.dataSource = self
        pvc.delegate = self
        pvc.isDoubleSided = false
        addChild(pvc)
        view.addSubview(pvc.view)
        pvc.didMove(toParent: self)
        pvc.view.backgroundColor = .clear
        // встроенные нажатия у краёв заменены своими (см. PageTouch): рядом со словами они мешали бы
        for g in pvc.gestureRecognizers where g is UITapGestureRecognizer { g.isEnabled = false }
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
        pvc.view.frame = view.bounds
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

    private func rebuildIfNeeded() {
        guard let c = cfg, let size = pageSize else { return }
        if c.key == builtKey && size == builtSize {
            // тот же вид: изменился только текст (выделение, закладки) — вёрстка прежняя
            if !storage.isEqual(to: c.text) { storage.setAttributedString(c.text) }
            if c.focus != lastFocus {
                lastFocus = c.focus
                let i = pageIndex(forVerse: c.focus)
                if i != current { show(i, animated: false) }
            }
            return
        }
        builtKey = c.key
        builtSize = size
        lastFocus = c.focus
        storage.setAttributedString(c.text)
        while layout.textContainers.count > 0 { layout.removeTextContainer(at: 0) }
        containers = []
        for _ in 0..<500 {
            let tc = NSTextContainer(size: size)
            tc.lineFragmentPadding = 0
            layout.addTextContainer(tc)
            containers.append(tc)
            layout.ensureLayout(for: tc)
            if NSMaxRange(layout.glyphRange(for: tc)) >= layout.numberOfGlyphs { break }
        }
        var list: [UIViewController] = [EdgePage(direction: -1)]
        for tc in containers { list.append(TextPage(container: tc, host: self)) }
        list.append(EdgePage(direction: 1))
        pages = list
        let i = pageIndex(forVerse: c.focus)
        current = i
        pvc.setViewControllers([pages[i]], direction: .forward, animated: false)
        report(i)
    }

    /// Страница (номер в pages), на которой стих
    private func pageIndex(forVerse v: Int) -> Int {
        guard pages.count > 2 else { return 1 }
        if v >= 9999 { return pages.count - 2 }
        guard v > 0, storage.length > 0 else { return 1 }
        var loc: Int?
        storage.enumerateAttribute(.aobVerse, in: NSRange(location: 0, length: storage.length), options: []) { val, r, stop in
            if (val as? Int) == v {
                loc = r.location
                stop.pointee = true
            }
        }
        guard let l = loc else { return 1 }
        var range = NSRange()
        guard let tc = layout.textContainer(forGlyphAt: layout.glyphIndexForCharacter(at: l), effectiveRange: &range),
              let idx = containers.firstIndex(where: { $0 === tc }) else { return 1 }
        return idx + 1
    }

    private func show(_ i: Int, animated: Bool) {
        guard i >= 0, i < pages.count else { return }
        let dir: UIPageViewController.NavigationDirection = i >= current ? .forward : .reverse
        pvc.setViewControllers([pages[i]], direction: dir, animated: animated) { [weak self] done in
            if done { self?.landed(i) }
        }
        if !animated { landed(i) }
    }

    /// Листание нажатием у края: +1 вперёд, −1 назад
    func turn(_ d: Int) {
        let t = current + d
        guard t >= 0, t < pages.count else { return }
        show(t, animated: true)
    }

    private func landed(_ i: Int) {
        if i == 0 {
            cfg?.onEdge(-1)
        } else if i == pages.count - 1 {
            cfg?.onEdge(1)
        } else {
            current = i
            report(i)
        }
    }

    private func report(_ i: Int) {
        guard i >= 1, i - 1 < containers.count else { return }
        let gr = layout.glyphRange(for: containers[i - 1])
        let cr = layout.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        var verse = 1
        if cr.length > 0, cr.location < storage.length {
            verse = (storage.attribute(.aobVerse, at: cr.location, effectiveRange: nil) as? Int) ?? 1
        }
        let total = max(1, pages.count - 2)
        counter.text = "\(i) / \(total)"
        cfg?.onPage(verse, i, total)
    }

    // MARK: - Листание жестом

    func pageViewController(_ p: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let i = pages.firstIndex(of: vc), i > 0 else { return nil }
        return pages[i - 1]
    }

    func pageViewController(_ p: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let i = pages.firstIndex(of: vc), i < pages.count - 1 else { return nil }
        return pages[i + 1]
    }

    func pageViewController(_ p: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let vc = p.viewControllers?.first, let i = pages.firstIndex(of: vc) else { return }
        landed(i)
    }
}

/// Страница текста: свой кусок главы (свой NSTextContainer общей вёрстки) и нажатия
final class TextPage: UIViewController {
    private let container: NSTextContainer
    private weak var host: PagerHost?
    private var textView: UITextView?
    private var touch: PageTouch?

    init(container: NSTextContainer, host: PagerHost) {
        self.container = container
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let tv = UITextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.isUserInteractionEnabled = false
        view.addSubview(tv)
        textView = tv
        if let h = host {
            let t = PageTouch(host: h, textView: tv)
            t.attach(to: view)
            touch = t
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let c = host?.cfg else { return }
        textView?.frame = view.bounds.inset(by: host?.insets(c) ?? c.insets)
    }
}

/// Нажатия на странице: у левого и правого края — листание, иначе слово, двойное касание, долгое нажатие
final class PageTouch: NSObject, UIGestureRecognizerDelegate {
    private weak var host: PagerHost?
    private weak var textView: UITextView?
    private var lpActive = false
    private var lpEnded = Date.distantPast

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
        let q = tv.convert(p, from: v)
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
        guard g.state == .ended, let v = g.view else { return }
        if lpActive || Date().timeIntervalSince(lpEnded) < 0.4 { return }
        let p = g.location(in: v)
        // у краёв страницы — листание, как в «Книгах»
        if p.x < v.bounds.width * 0.22 { host?.turn(-1); return }
        if p.x > v.bounds.width * 0.78 { host?.turn(1); return }
        let h = hit(p, in: v)
        host?.cfg?.onTap(h.url, h.verse)
    }

    @objc func double(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let v = g.view else { return }
        host?.cfg?.onDouble(hit(g.location(in: v), in: v).verse)
    }

    @objc func long(_ g: UILongPressGestureRecognizer) {
        guard let v = g.view else { return }
        switch g.state {
        case .began:
            lpActive = true
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

/// Страница-переход: показывается, пока листаете к соседней главе; когда страница легла — глава меняется
final class EdgePage: UIViewController {
    private let direction: Int

    init(direction: Int) {
        self.direction = direction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let l = UILabel()
        l.text = direction > 0 ? "Следующая глава" : "Предыдущая глава"
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: view.centerXAnchor), l.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }
}
