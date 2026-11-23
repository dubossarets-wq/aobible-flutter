import SwiftUI

/// Сколько прокручено влево и сколько осталось вправо (доли ширины затухания, 0…1)
private struct SoftEdgeAmounts: Equatable {
    var lead: CGFloat = 0
    var trail: CGFloat = 0
}

private struct SoftEdgesModifier: ViewModifier {
    let width: CGFloat
    @State private var amounts = SoftEdgeAmounts()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: SoftEdgeAmounts.self) { g in
                let scrolled = max(0, g.contentOffset.x + g.contentInsets.leading)
                let total = max(0, g.contentSize.width + g.contentInsets.leading + g.contentInsets.trailing - g.containerSize.width)
                return SoftEdgeAmounts(lead: min(1, scrolled / width), trail: min(1, max(0, total - scrolled) / width))
            } action: { _, new in
                amounts = new
            }
            // прижато к левому краю — слева затухания нет; прижато к правому — справа нет; по мере прокрутки край плавно растёт
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: width * amounts.lead)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width * amounts.trail)
                }
            )
    }
}

extension View {
    /// Горизонтальная лента плашек: у края, за который ещё можно прокрутить, плавно гаснет вместо резкого среза
    /// посреди плашки; у края, к которому лента прижата, затухания нет
    func softEdges(_ width: CGFloat = 16) -> some View {
        modifier(SoftEdgesModifier(width: width))
    }

    /// Лента плашек до краёв экрана: отступ страницы (inset) отдан содержимому, а не обрезке; плашки уходят под край плавно
    func bleedingRow(_ inset: CGFloat = 16) -> some View {
        padding(.horizontal, -inset)
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .softEdges(inset)
    }
}

/// Строка списка со значком в цветном квадрате — как в «Настройках» iPhone
struct IconLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Пустая страница-заглушка: раздел ещё не перенесён на Swift
struct SoonView: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(title), systemImage: symbol)
        } description: {
            Text("Этот раздел скоро появится в новой версии.")
        }
    }
}

/// Строка, где каждый элемент получает ширину пропорционально своему тексту: короткие подписи не раздуваются,
/// длинные не режутся (на узком экране все ужимаются поровну по доле)
struct ProportionalRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? ideal.reduce(0) { $0 + $1.width }, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let sum = max(1, ideal.reduce(0, +))
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            let w = bounds.width * ideal[i] / sum
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w
        }
    }
}

/// Переключатель в одну строку на всю ширину — системный UISegmentedControl: стекло iOS 26, выбор нажатием или
/// проведением пальца по плашке, анимацию и отклик даёт сама система (свой рисованный переключатель подтормаживал).
/// Ширина пунктов — по содержимому (длинное название книги получает больше места)
struct CapsuleSwitcher<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        NativeSegments(
            titles: options.map(\.title),
            index: Binding(
                get: { options.firstIndex { $0.value == selection } ?? 0 },
                set: { if options.indices.contains($0) { selection = options[$0].value } }
            )
        )
    }
}

private struct NativeSegments: UIViewRepresentable {
    let titles: [String]
    @Binding var index: Int

    final class Coordinator: NSObject {
        var index: Binding<Int>
        init(_ index: Binding<Int>) { self.index = index }
        @objc func changed(_ sender: UISegmentedControl) { index.wrappedValue = sender.selectedSegmentIndex }
    }

    func makeCoordinator() -> Coordinator { Coordinator($index) }

    func makeUIView(context: Context) -> UISegmentedControl {
        let c = UISegmentedControl(items: titles)
        c.apportionsSegmentWidthsByContent = true
        c.selectedSegmentIndex = index
        c.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        c.setContentHuggingPriority(.defaultLow, for: .horizontal)
        c.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return c
    }

    func updateUIView(_ c: UISegmentedControl, context: Context) {
        context.coordinator.index = $index
        let current = (0..<c.numberOfSegments).map { c.titleForSegment(at: $0) ?? "" }
        if current != titles {
            c.removeAllSegments()
            for (i, t) in titles.enumerated() { c.insertSegment(withTitle: t, at: i, animated: false) }
        }
        if c.selectedSegmentIndex != index { c.selectedSegmentIndex = index }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        let ideal = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? ideal.width, height: ideal.height)
    }
}

/// «Возможно, вы искали»: карточка с исправленными запросами — значок, запрос, число найденного, стрелка «подставить»
struct SuggestionCard: View {
    let items: [(text: String, count: Int?)]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Возможно, вы искали", systemImage: "sparkle.magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    Button { onPick(it.text) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor.opacity(0.13), in: Circle())
                            Text(it.text)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let n = it.count {
                                Text("\(n)")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
