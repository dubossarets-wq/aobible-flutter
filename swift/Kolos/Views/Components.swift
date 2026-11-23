import SwiftUI

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
/// в шапке Библии), выбранный пункт — капсула акцента, которая переезжает на новое место
struct CapsuleSwitcher<T: Hashable>: View {
    let options: [(value: T, title: Text)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        ProportionalRow {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let on = o.value == selection
                // разделитель справа от пункта — если ни он, ни следующий не выбраны
                let divider = i < options.count - 1 && !on && options[i + 1].value != selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = o.value }
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
                                Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "sel", in: ns)
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
            }
        }
        .padding(3)
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
