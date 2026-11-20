import SwiftUI
import UIKit

/// Текст без нажатий, у которого подсвеченные отрезки (атрибут aobPlate) рисуются цельными скруглёнными плашками
/// (SwiftUI Text умеет только прямоугольную подложку с острыми углами). Для результатов поиска и списков стихов
struct PlateLabel: View {
    let text: NSAttributedString

    var body: some View {
        // запас по краям для плашек, выступающих за текст (как в VerseTextView)
        PlateLabelRep(text: text)
            .padding(-VerseTextView.bleed)
    }
}

private struct PlateLabelRep: UIViewRepresentable {
    let text: NSAttributedString

    final class Coordinator {
        var storage: NSTextStorage?
        var last: NSAttributedString?
        var width: CGFloat = -1
        var height: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = PlateLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let tv = UITextView(frame: .zero, textContainer: container)
        context.coordinator.storage = storage
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.isUserInteractionEnabled = false
        tv.backgroundColor = .clear
        tv.isOpaque = false
        tv.textContainerInset = UIEdgeInsets(top: VerseTextView.bleed, left: VerseTextView.bleed, bottom: VerseTextView.bleed, right: VerseTextView.bleed)
        tv.adjustsFontForContentSizeCategory = false
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        guard c.last !== text else { return }
        c.last = text
        if !tv.attributedText.isEqual(to: text) {
            tv.attributedText = text
            c.width = -1
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var w = proposal.width ?? 320
        if !w.isFinite || w <= 0 { w = 320 }
        let c = context.coordinator
        if c.width != w {
            c.height = ceil(uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
            c.width = w
        }
        return CGSize(width: w, height: c.height)
    }
}
