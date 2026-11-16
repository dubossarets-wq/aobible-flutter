import SwiftUI

/// Метка слова, которое нужно подсветить в тексте статьи (изучаемое слово в примере)
struct KeyWordAttribute: TextAttribute {}

/// Рисует мягкую скруглённую подложку под словами с меткой KeyWordAttribute, поверх — сам текст
struct KeyWordRenderer: TextRenderer {
    var color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[KeyWordAttribute.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: -3, dy: -1)
                context.fill(Path(roundedRect: rect, cornerRadius: 6, style: .continuous), with: .color(color))
            }
        }
        for line in layout {
            for run in line {
                context.draw(run)
            }
        }
    }
}

/// Статья словаря Дворецкого в удобном для чтения виде (поле `rich` модуля dvoretsky-gr):
/// слово крупно, под ним формы (степени сравнения, времена) по строкам, значения под номерами, у значения авторы
/// отдельной строкой, греческие примеры с переводом — каждый на своей строке с чертой слева, внизу — годы авторов.
struct DvoretskyArticle: View {
    @Environment(\.readerPalette) private var pal
    let blocks: [[String: Any]]
    /// Сколько значений показывать (nil — все): для свёрнутого вида; шапка и формы показываются всегда
    var limit: Int? = nil

    private var shown: [[String: Any]] {
        guard let limit else { return blocks }
        var out: [[String: Any]] = []
        var senses = 0
        for b in blocks {
            let k = b["k"] as? String
            if k == "legend" { continue }
            if k == "s" {
                senses += 1
                if senses > limit { break }
            }
            out.append(b)
        }
        return out
    }

    /// Ширина колонки номера по самому длинному номеру («9.» уже, чем «10.»)
    private var numberWidth: CGFloat {
        let longest = blocks.compactMap { $0["n"] as? String }.map { $0.count }.max() ?? 0
        return longest == 0 ? 0 : CGFloat(longest) * 9 + 3
    }

    private var keyRenderer: KeyWordRenderer {
        KeyWordRenderer(color: pal.accent.opacity(0.13))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, b in
                blockView(b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ b: [String: Any]) -> some View {
        switch (b["k"] as? String) ?? "" {
        case "h":
            line(b["s"], size: 17)
        case "p":
            line(b["s"], size: 17)
        case "f":
            forms(b)
        case "hr":
            Divider().padding(.vertical, 2)
        case "legend":
            legend(b)
        default:
            sense(b)
        }
    }

    private func line(_ spans: Any?, size: CGFloat) -> some View {
        rich(spans, size: size)
            .textRenderer(keyRenderer)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Формы слова: «Сравнительная степень» — слова; «Будущее время» — слово…
    private func forms(_ b: [String: Any]) -> some View {
        let rows = (b["rows"] as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 1) {
                    Text((r["label"] as? String) ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    line(r["s"], size: 16)
                }
            }
        }
    }

    private func sense(_ b: [String: Any]) -> some View {
        let level = (b["l"] as? Int) ?? 0
        let num = b["n"] as? String
        let hasMeaning = !plain(b["m"]).isEmpty
        let authors = b["au"] as? String
        let examples = (b["x"] as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            // номер и значение: номер у левого края, перенос строк — под текстом значения
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if numberWidth > 0 {
                    Text(num ?? "")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pal.accent)
                        .frame(width: numberWidth, alignment: .leading)
                }
                if hasMeaning {
                    line(b["m"], size: 17)
                }
            }
            // авторы и примеры — на всю ширину, без отступа под номер
            if let authors {
                Text(authors).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(examples.enumerated()), id: \.offset) { _, x in
                example(x)
            }
        }
        .padding(.leading, CGFloat(level) * 14)
    }

    private func example(_ x: [String: Any]) -> some View {
        let hasTr = !plain(x["t"]).isEmpty
        return VStack(alignment: .leading, spacing: 2) {
            line(x["q"], size: 16)
            if hasTr {
                rich(x["t"], size: 15)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(pal.accent.opacity(0.35)).frame(width: 3)
        }
    }

    private func legend(_ b: [String: Any]) -> some View {
        let rows = (b["a"] as? [[Any]]) ?? []
        let text = rows.compactMap { r -> String? in
            guard r.count >= 2, let n = r[0] as? String, let y = r[1] as? String else { return nil }
            return "\(n) (\(y))"
        }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Авторы примеров").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Текст спанов без оформления — для проверки «пусто ли»
    private func plain(_ any: Any?) -> String {
        ((any as? [[Any]]) ?? []).compactMap { $0.first as? String }.joined()
    }

    /// Спаны [текст, стиль] → одна строка с оформлением
    private func rich(_ any: Any?, size: CGFloat) -> Text {
        var out = Text(verbatim: "")
        for p in (any as? [[Any]]) ?? [] {
            guard p.count >= 2, let s = p[0] as? String, let st = p[1] as? String else { continue }
            out = out + piece(s, st, size)
        }
        return out
    }

    private func piece(_ s: String, _ st: String, _ size: CGFloat) -> Text {
        let t = Text(verbatim: s)
        switch st {
        case "g":
            return t.font(.system(size: size + 1, design: .serif))
        case "k":
            // изучаемое слово в примере: чуть плотнее шрифт, подложку рисует KeyWordRenderer
            return t.font(.system(size: size + 1, weight: .semibold, design: .serif)).customAttribute(KeyWordAttribute())
        case "h":
            return t.font(.system(size: size + 6, weight: .bold, design: .serif))
        case "b":
            return t.font(.system(size: size, weight: .semibold))
        case "i":
            return t.font(.system(size: size - 2).italic()).foregroundStyle(Color.secondary)
        case "a":
            return t.font(.system(size: size - 3, weight: .medium)).foregroundStyle(Color.secondary)
        default:
            return t.font(.system(size: size))
        }
    }
}
