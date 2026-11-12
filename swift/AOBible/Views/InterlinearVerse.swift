import SwiftUI
import UIKit

/// Стих подстрочного перевода (features.interlinear): каждое слово с разметкой — столбик «перевод / оригинал / номер Стронга»
/// (как во Flutter-версии). Слова без разметки идут столбиками из одной строки. Нажатие на столбик открывает слово,
/// двойное — любимый стих, долгое — выделение стиха.
struct InterlinearVerse: View {
    let verse: Verse
    let fontSize: CGFloat
    let fontFamily: String
    let fontWeight: Double
    let showNumber: Bool
    let numberColor: Color
    let textColor: Color
    let accent: Color
    let showGloss: Bool
    let showOrig: Bool
    let showStrong: Bool
    var favorite = false
    var xrefs = 0
    var illus = 0
    /// Подкраска слова по его номеру в стихе (выбор части стиха, любимая часть)
    var mark: (Int) -> Color? = { _ in nil }
    var onTap: (URL?, Int) -> Void
    var onDouble: (Int) -> Void
    var onLong: (Int) -> Void
    var views: VerseViews?

    private static let wordRe = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:[-’'][\\p{L}\\p{M}]+)*")
    private static let strongRe = try! NSRegularExpression(pattern: "^[GHgh]0*(\\d+)[a-z]?$")

    private struct Word: Identifiable {
        let id: Int
        let ti: Int
        let k: Int
        let gloss: String
        let orig: String?
        let strong: String?
        let italic: Bool
    }

    /// «H0430» → «430», «G976a» → «976»
    private static func strongNumber(_ key: String) -> String {
        let ns = key as NSString
        if let m = strongRe.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: m.range(at: 1))
        }
        return key
    }

    private func words() -> [Word] {
        var out: [Word] = []
        for (ti, t) in Markup.parse(verse.text).enumerated() {
            if !t.strongs.isEmpty {
                out.append(Word(id: out.count, ti: ti, k: -1, gloss: t.text, orig: t.orig, strong: Self.strongNumber(t.strongs[0]), italic: t.italic))
            } else {
                let ns = t.text as NSString
                var k = 0
                for m in Self.wordRe.matches(in: t.text, range: NSRange(location: 0, length: ns.length)) {
                    out.append(Word(id: out.count, ti: ti, k: k, gloss: ns.substring(with: m.range), orig: nil, strong: nil, italic: t.italic))
                    k += 1
                }
            }
        }
        return out
    }

    private var glossFont: Font { ReadingFonts.font(fontFamily, size: fontSize, weight: fontWeight) }

    @ViewBuilder private func column(_ w: Word) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if showGloss {
                // слово-прочерк «·» — сверху пусто (высота строки остаётся)
                Text(w.gloss == "·" ? " " : w.gloss)
                    .font(glossFont)
                    .italic(w.italic)
                    .foregroundStyle(textColor)
            }
            if showOrig, let o = w.orig {
                Text(o)
                    .font(.system(size: fontSize * 0.78, design: .serif))
                    .foregroundStyle(textColor.opacity(0.75))
            }
            if showStrong, let s = w.strong {
                Text(s)
                    .font(.system(size: max(9, fontSize * 0.55), weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
            }
        }
        .fixedSize()
        .padding(.horizontal, 2)
        .background(mark(w.id).map { c in RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c) })
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(URL(string: "aobword:\(verse.num),\(w.ti),\(w.k)"), verse.num)
        }
    }

    var body: some View {
        InterlinearFlow(hSpacing: 6, vSpacing: 10) {
            if showNumber {
                Text("\(verse.num)")
                    .font(.system(size: fontSize * 0.62, weight: .semibold))
                    .foregroundStyle(numberColor)
                    .padding(.trailing, 2)
                    .onTapGesture { onTap(URL(string: "aobverse:\(verse.num)"), verse.num) }
            }
            if favorite {
                Text("♥").font(.system(size: fontSize * 0.62)).foregroundStyle(Color(hex: 0xd9475e))
            }
            ForEach(words().filter { showOrig || showStrong || !["·", ""].contains($0.gloss.trimmingCharacters(in: .whitespaces)) }) { column($0) }
            if xrefs > 0 {
                Text("⇅\(xrefs)")
                    .font(.system(size: fontSize * 0.62, weight: .medium))
                    .foregroundStyle(accent)
                    .onTapGesture { onTap(URL(string: "aobxref:\(verse.num)"), verse.num) }
            }
            if illus > 0 {
                Text("🖼\(illus)")
                    .font(.system(size: fontSize * 0.62, weight: .medium))
                    .onTapGesture { onTap(URL(string: "aobillus:\(verse.num)"), verse.num) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerseAnchor(verse: verse.num, views: views))
        .contentShape(Rectangle())
        .onTapGesture { onTap(nil, verse.num) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDouble(verse.num) })
        .onLongPressGesture(minimumDuration: 0.25) { onLong(verse.num) }
    }
}

/// Перенос по строкам: столбики идут слева направо и переходят на следующую строку, строка — по верхнему краю
struct InterlinearFlow: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, _ maxWidth: CGFloat) -> [Line] {
        var out: [Line] = [Line()]
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            let add = (out[out.count - 1].items.isEmpty ? 0 : hSpacing) + size.width
            if out[out.count - 1].width + add > maxWidth, !out[out.count - 1].items.isEmpty {
                out.append(Line())
            }
            var l = out[out.count - 1]
            l.width += (l.items.isEmpty ? 0 : hSpacing) + size.width
            l.height = max(l.height, size.height)
            l.items.append((i, size))
            out[out.count - 1] = l
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let ls = lines(subviews, maxW)
        let h = ls.reduce(0) { $0 + $1.height } + vSpacing * CGFloat(max(0, ls.count - 1))
        let w = maxW.isFinite ? maxW : (ls.map { $0.width }.max() ?? 0)
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, bounds.width) {
            var x = bounds.minX
            for it in line.items {
                subviews[it.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(it.size))
                x += it.size.width + hSpacing
            }
            y += line.height + vSpacing
        }
    }
}

/// Невидимая точка привязки стиха: по ней синхронная прокрутка узнаёт положение верха стиха
struct VerseAnchor: UIViewRepresentable {
    let verse: Int
    var views: VerseViews?

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        views?.addAnchor(verse, v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Панель подстрочника под шапкой: что показывать в столбике (перевод, оригинал, номер Стронга) и «Свернуть»
struct InterlinearBar: View {
    /// Высота панели вместе с отступом снизу
    static let height: CGFloat = 46
    @AppStorage("ilGloss") private var gloss = true
    @AppStorage("ilOrig") private var orig = true
    @AppStorage("ilStrong") private var strong = true
    @AppStorage("ilBar") private var open = true
    @Environment(\.readerPalette) private var pal

    private func toggle(_ b: Binding<Bool>) {
        // последнюю включённую часть выключить нельзя
        if b.wrappedValue && [gloss, orig, strong].filter({ $0 }).count == 1 { return }
        b.wrappedValue.toggle()
    }

    /// Отдельная плашка высотой 40, как кнопки шапки; включённая — подкрашена цветом акцента
    private func part(_ title: LocalizedStringKey, _ b: Binding<Bool>) -> some View {
        Button { toggle(b) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(b.wrappedValue ? pal.accent : pal.muted)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .contentShape(Capsule())
                .glassEffect(.regular.tint(b.wrappedValue ? pal.accent.opacity(0.18) : nil).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 8) {
            part("Перевод", $gloss)
            part("Оригинал", $orig)
            part("Стронг", $strong)
            Spacer(minLength: 4)
            Button { open = false } label: {
                Image(systemName: "chevron.up").chromeCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Свернуть")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .frame(height: Self.height)
    }
}
