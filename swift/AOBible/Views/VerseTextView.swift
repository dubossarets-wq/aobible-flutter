import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// Ссылка на слове, номере Стронга, метке (aobword:…, aobstrong:…, aobxref:…, aobillus:…, aobverse:…)
    static let aobURL = NSAttributedString.Key("aobURL")
    /// Номер стиха, которому принадлежит символ
    static let aobVerse = NSAttributedString.Key("aobVerse")
}

extension Notification.Name {
    /// В каком-то тексте началось системное выделение — в остальных оно снимается
    static let aobNativeSelStart = Notification.Name("aobNativeSelStart")
}

/// Системное выделение текста (как везде в iPhone): какие стихи задеты и крайние слова
struct NativeSel: Equatable {
    let verses: [Int]
    /// первое и последнее слово (ссылки aobword), хотя бы частично попавшие в выделение
    let firstWord: URL?
    let lastWord: URL?
    /// выделен один стих не целиком — это часть стиха
    let partial: Bool
}

/// Часть стиха, выделенная системным выделением: номера слов (как у «Части стиха»)
struct NativePart: Equatable {
    let verse: Int
    let range: ClosedRange<Int>
}

/// Текст стиха (или сплошного блока): свой слой нажатий вместо ссылок SwiftUI. Нажатие на слово открывает словарь,
/// двойное — любимый, долгое нажатие выделяет стих в ЛЮБОМ месте, в том числе на слове (ссылки SwiftUI долгое
/// нажатие на словах перехватывали, и стих выделялся только на пустом месте строки)
struct VerseTextView: UIViewRepresentable {
    let text: NSAttributedString
    /// Стих по умолчанию (если под пальцем символ без номера стиха)
    let verse: Int
    var onTap: (URL?, Int) -> Void
    var onDouble: (Int) -> Void
    var onLong: (Int) -> Void
    /// Куда записать текстовый блок (по ним синхронная прокрутка узнаёт положения стихов)
    var views: VerseViews?
    /// Идёт ли системное выделение (false — снять его, если оно здесь есть)
    var selActive = false
    /// Долгое нажатие выделяет стих системным выделением с ручками; ручки двигаются — сюда приходят задетые стихи;
    /// nil — выделение снято (нажатие мимо)
    var onSelect: ((NativeSel?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        // своя связка TextKit 1: раскладка рисует цельные скруглённые плашки (PlateLayoutManager)
        let storage = NSTextStorage()
        let layout = PlateLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = UITextView(frame: .zero, textContainer: container)
        context.coordinator.storage = storage
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.isOpaque = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.isUserInteractionEnabled = true

        let c = context.coordinator
        tv.delegate = c
        c.textView = tv
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        let long = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.long(_:)))
        long.minimumPressDuration = 0.25
        long.allowableMovement = 12
        // палец сдвинулся (свайп, прокрутка) — это не нажатие на слово: системное нажатие терпит сдвиг до ~40 пт,
        // и короткий свайп по тексту открывал словарь. Детектор сдвига срабатывает с ~10 пт, нажатия ждут его неудачи
        let mover = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.moved(_:)))
        c.mover = mover
        single.require(toFail: mover)
        double.require(toFail: mover)
        for g in [single, double, long, mover] as [UIGestureRecognizer] {
            g.delegate = c
            g.cancelsTouchesInView = false
            tv.addGestureRecognizer(g)
        }
        views?.add(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if !selActive && c.native { c.end(tv, report: false) }
        // при каждой перестройке экрана: тот же объект текста — сравнивать нечего (в длинной главе блоков много)
        guard c.lastText !== text else { return }
        c.lastText = text
        if !tv.attributedText.isEqual(to: text) {
            tv.attributedText = text
            c.measuredWidth = -1
            // новый текст снимает выделение — сообщить (после обновления экрана)
            if c.native {
                DispatchQueue.main.async { c.end(tv, report: true) }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var w = proposal.width ?? 320
        if !w.isFinite || w <= 0 { w = 320 }
        let c = context.coordinator
        if c.measuredWidth != w {
            c.measuredHeight = ceil(uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
            c.measuredWidth = w
        }
        return CGSize(width: w, height: c.measuredHeight)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UITextViewDelegate {
        var parent: VerseTextView
        /// Текст поля (держим сами: UITextView со своей связкой TextKit его не удерживает)
        var storage: NSTextStorage?
        var lastText: NSAttributedString?
        var measuredWidth: CGFloat = -1
        var measuredHeight: CGFloat = 0
        private var lpActive = false
        private var lpEnded = Date.distantPast
        /// Детектор сдвига пальца (см. makeUIView)
        weak var mover: UIPanGestureRecognizer?

        weak var textView: UITextView?
        /// Здесь сейчас системное выделение
        private(set) var native = false
        private var lastSel: NativeSel?
        private var observer: NSObjectProtocol?

        init(_ p: VerseTextView) {
            parent = p
            super.init()
            observer = NotificationCenter.default.addObserver(forName: .aobNativeSelStart, object: nil, queue: .main) { [weak self] n in
                guard let self, (n.object as AnyObject?) !== self, self.native, let tv = self.textView else { return }
                self.end(tv, report: false)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        // MARK: системное выделение

        /// Слова стиха: диапазон от первого до последнего слова (без номера, сердечка, меток после)
        private func verseRange(_ s: NSTextStorage, _ v: Int) -> NSRange? {
            var lo = Int.max, hi = -1
            var vlo = Int.max, vhi = -1
            let all = NSRange(location: 0, length: s.length)
            s.enumerateAttribute(.aobVerse, in: all) { val, r, _ in
                guard (val as? Int) == v else { return }
                vlo = min(vlo, r.location)
                vhi = max(vhi, NSMaxRange(r))
            }
            guard vhi > vlo else { return nil }
            let vr = NSRange(location: vlo, length: vhi - vlo)
            s.enumerateAttribute(.aobURL, in: vr) { val, r, _ in
                guard let u = val as? URL, u.scheme == "aobword" else { return }
                lo = min(lo, r.location)
                hi = max(hi, NSMaxRange(r))
            }
            return hi > lo ? NSRange(location: lo, length: hi - lo) : vr
        }

        /// Первое и последнее слово стиха
        private func verseWords(_ s: NSTextStorage, _ v: Int) -> (URL?, URL?) {
            var first: URL?, last: URL?
            s.enumerateAttribute(.aobURL, in: NSRange(location: 0, length: s.length)) { val, _, _ in
                guard let u = val as? URL, u.scheme == "aobword",
                      u.absoluteString.dropFirst("aobword:".count).split(separator: ",").first.flatMap({ Int($0) }) == v else { return }
                if first == nil { first = u }
                last = u
            }
            return (first, last)
        }

        func begin(_ tv: UITextView, verse: Int) {
            guard let r = verseRange(tv.textStorage, verse) else { return }
            NotificationCenter.default.post(name: .aobNativeSelStart, object: self)
            native = true
            lastSel = nil
            tv.isSelectable = true
            _ = tv.becomeFirstResponder()
            tv.selectedRange = r
            report(tv)
        }

        func end(_ tv: UITextView, report: Bool) {
            guard native else { return }
            native = false
            lastSel = nil
            tv.selectedRange = NSRange(location: 0, length: 0)
            if tv.isFirstResponder { tv.resignFirstResponder() }
            // свои нажатия снова работают; системные жесты выделения выключаются после текущего касания
            DispatchQueue.main.async { [weak self] in
                if self?.native != true { tv.isSelectable = false }
            }
            if report { parent.onSelect?(nil) }
        }

        private func report(_ tv: UITextView) {
            let r = tv.selectedRange
            let s = tv.textStorage
            guard r.length > 0, NSMaxRange(r) <= s.length else { return }
            var verses: [Int] = []
            var first: URL?, last: URL?
            s.enumerateAttribute(.aobVerse, in: r) { val, _, _ in
                if let n = val as? Int, !verses.contains(n) { verses.append(n) }
            }
            s.enumerateAttribute(.aobURL, in: r) { val, _, _ in
                guard let u = val as? URL, u.scheme == "aobword" else { return }
                if first == nil { first = u }
                last = u
            }
            var partial = false
            if verses.count == 1, first != nil {
                let w = verseWords(s, verses[0])
                partial = w.0 != first || w.1 != last
            }
            let sel = NativeSel(verses: verses, firstWord: first, lastWord: last, partial: partial)
            guard sel != lastSel, !verses.isEmpty else { return }
            lastSel = sel
            parent.onSelect?(sel)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard native else { return }
            if tv.selectedRange.length == 0 {
                end(tv, report: true)
            } else {
                report(tv)
            }
        }

        @objc func moved(_ g: UIPanGestureRecognizer) {}

        /// Что под пальцем: ссылка (слово, номер Стронга…) и номер стиха
        private func hit(_ tv: UITextView, _ p: CGPoint) -> (url: URL?, verse: Int) {
            let lm = tv.layoutManager
            let tc = tv.textContainer
            let q = CGPoint(x: p.x - tv.textContainerInset.left, y: p.y - tv.textContainerInset.top)
            var frac: CGFloat = 0
            let idx = lm.characterIndex(for: q, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
            let storage = tv.textStorage
            guard idx >= 0, idx < storage.length else { return (nil, parent.verse) }
            let verse = (storage.attribute(.aobVerse, at: idx, effectiveRange: nil) as? Int) ?? parent.verse
            // палец должен быть именно на символе, а не за концом строки
            let g = lm.glyphIndexForCharacter(at: idx)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
            guard rect.insetBy(dx: -6, dy: -6).contains(q) else { return (nil, verse) }
            return (storage.attribute(.aobURL, at: idx, effectiveRange: nil) as? URL, verse)
        }

        /// Одиночное касание ждёт, не будет ли второго: иначе первое открывало окно слова, и второе попадало
        /// уже в окно — двойное касание («в любимые») не срабатывало
        private var pendingTap: DispatchWorkItem?

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let tv = g.view as? UITextView, !native else { return }
            // отпускание пальца после долгого нажатия — не нажатие
            if lpActive || Date().timeIntervalSince(lpEnded) < 0.4 { return }
            let h = hit(tv, g.location(in: tv))
            pendingTap?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.pendingTap = nil
                self?.parent.onTap(h.url, h.verse)
            }
            pendingTap = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: item)
        }

        @objc func double(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let tv = g.view as? UITextView else { return }
            pendingTap?.cancel()
            pendingTap = nil
            if native || lpActive || Date().timeIntervalSince(lpEnded) < 0.4 { return }
            parent.onDouble(hit(tv, g.location(in: tv)).verse)
        }

        @objc func long(_ g: UILongPressGestureRecognizer) {
            guard let tv = g.view as? UITextView else { return }
            switch g.state {
            case .began:
                // в выделенном тексте долгое нажатие — системное (лупа, выделение слова)
                if native { return }
                lpActive = true
                pendingTap?.cancel()
                pendingTap = nil
                let v = hit(tv, g.location(in: tv)).verse
                parent.onLong(v)
                // стих выделяется системным выделением с ручками — их можно тянуть до любого слова
                if parent.onSelect != nil { begin(tv, verse: v) }
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
            // детектор сдвига никому не мешает (прокрутке, свайпу глав); свои три жеста работают вместе;
            // с прокруткой — по обычным правилам
            if g === mover || other === mover { return true }
            return g.view != nil && g.view === other.view
        }
    }
}
