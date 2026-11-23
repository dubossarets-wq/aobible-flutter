import SwiftUI

extension View {
    /// Горизонтальная лента плашек: у краёв плавно гаснет, а не обрезается резким срезом посреди плашки
    func softEdges(_ width: CGFloat = 16) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: width)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
            }
        )
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

/// Переключатель в одну строку на всю ширину: общая стеклянная плашка с тонкими разделителями (как «перевод | книга»
/// в шапке Библии), выбранный пункт — стеклянная капсула акцента, которая переезжает на новое место. Можно нажать
/// на пункт или провести пальцем по плашке: капсула следует за пальцем (как в нижнем меню), пункты меняются на ходу
struct CapsuleSwitcher<T: Hashable>: View {
    let options: [(value: T, title: Text)]
    @Binding var selection: T
    @Namespace private var ns
    @State private var frames: [Int: CGRect] = [:]
    @State private var dragging = false

    private func pick(_ i: Int) {
        guard options.indices.contains(i), options[i].value != selection else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.25)) { selection = options[i].value }
    }

    /// Пункт под пальцем (за краями плашки — крайний)
    private func index(at x: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let hit = frames.first(where: { $0.value.minX <= x && x <= $0.value.maxX }) { return hit.key }
        return x < (frames.values.map(\.minX).min() ?? 0) ? frames.keys.min() : frames.keys.max()
    }

    var body: some View {
        ProportionalRow {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let on = o.value == selection
                // разделитель справа от пункта — если ни он, ни следующий не выбраны
                let divider = i < options.count - 1 && !on && options[i + 1].value != selection
                Button {
                    pick(i)
                } label: {
                    o.title
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on {
                                Color.clear
                                    .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
                                    .scaleEffect(dragging ? 1.07 : 1)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if divider {
                                Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 18)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("capsuleSwitcher")) } action: { frames[i] = $0 }
            }
        }
        .padding(3)
        .coordinateSpace(.named("capsuleSwitcher"))
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    if !dragging { withAnimation(.snappy(duration: 0.2)) { dragging = true } }
                    if let i = index(at: v.location.x) { pick(i) }
                }
                .onEnded { _ in withAnimation(.snappy(duration: 0.25)) { dragging = false } }
        )
        .glassEffect(.regular, in: Capsule())
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
