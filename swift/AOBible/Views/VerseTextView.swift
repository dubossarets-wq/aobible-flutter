import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// Ссылка на слове, номере Стронга, метке (aobword:…, aobstrong:…, aobxref:…, aobillus:…, aobverse:…)
    static let aobURL = NSAttributedString.Key("aobURL")
    /// Номер стиха, которому принадлежит символ
    static let aobVerse = NSAttributedString.Key("aobVerse")
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: false)
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
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        let long = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.long(_:)))
        long.minimumPressDuration = 0.25
        long.allowableMovement = 12
        for g in [single, double, long] as [UIGestureRecognizer] {
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
        // при каждой перестройке экрана: тот же объект текста — сравнивать нечего (в длинной главе блоков много)
        guard c.lastText !== text else { return }
        c.lastText = text
        if !tv.attributedText.isEqual(to: text) {
            tv.attributedText = text
            c.measuredWidth = -1
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

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: VerseTextView
        var lastText: NSAttributedString?
        var measuredWidth: CGFloat = -1
        var measuredHeight: CGFloat = 0
        private var lpActive = false
        private var lpEnded = Date.distantPast
        /// Где палец коснулся: сдвинулся дальше 12 пт — это жест (свайп, прокрутка), а не нажатие на слово
        /// (системное нажатие терпит сдвиг до ~40 пт, и короткий свайп по тексту открывал словарь)
        private var downAt: CGPoint?

        init(_ p: VerseTextView) { parent = p }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g is UITapGestureRecognizer, (g as? UITapGestureRecognizer)?.numberOfTapsRequired == 1 {
                downAt = touch.location(in: g.view)
            }
            return true
        }

        private func moved(_ g: UIGestureRecognizer) -> Bool {
            guard let d = downAt else { return false }
            let p = g.location(in: g.view)
            return hypot(p.x - d.x, p.y - d.y) > 12
        }

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

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let tv = g.view as? UITextView else { return }
            // отпускание пальца после долгого нажатия — не нажатие
            if lpActive || Date().timeIntervalSince(lpEnded) < 0.4 || moved(g) { return }
            let h = hit(tv, g.location(in: tv))
            parent.onTap(h.url, h.verse)
        }

        @objc func double(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let tv = g.view as? UITextView else { return }
            parent.onDouble(hit(tv, g.location(in: tv)).verse)
        }

        @objc func long(_ g: UILongPressGestureRecognizer) {
            guard let tv = g.view as? UITextView else { return }
            switch g.state {
            case .began:
                lpActive = true
                parent.onLong(hit(tv, g.location(in: tv)).verse)
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
            // свои три жеста работают вместе; с прокруткой — по обычным правилам
            g.view != nil && g.view === other.view
        }
    }
}
