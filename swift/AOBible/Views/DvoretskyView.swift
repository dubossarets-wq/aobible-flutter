import SwiftUI

/// Статья словаря Дворецкого в удобном для чтения виде (поле `rich` модуля dvoretsky-gr):
/// слово крупно, значения под номерами, у значения авторы отдельной строкой, греческие примеры с переводом —
/// каждый на своей строке с чертой слева, внизу — годы авторов, названных в примерах.
struct DvoretskyArticle: View {
    @Environment(\.readerPalette) private var pal
    let blocks: [[String: Any]]
    /// Сколько блоков показывать (nil — все): для свёрнутого вида
    var limit: Int? = nil

    private var shown: [[String: Any]] {
        guard let limit else { return blocks }
        return Array(blocks.prefix(limit)).filter { ($0["k"] as? String) != "legend" }
    }

    private var hasNumbers: Bool {
        blocks.contains { ($0["n"] as? String) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, b in
                blockView(b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ b: [String: Any]) -> some View {
        switch (b["k"] as? String) ?? "" {
        case "h":
            Text(attr(b["s"], size: 17)).fixedSize(horizontal: false, vertical: true)
        case "p":
            Text(attr(b["s"], size: 17)).fixedSize(horizontal: false, vertical: true)
        case "hr":
            Divider().padding(.vertical, 2)
        case "legend":
            legend(b)
        default:
            sense(b)
        }
    }

    private func sense(_ b: [String: Any]) -> some View {
        let level = (b["l"] as? Int) ?? 0
        let num = b["n"] as? String
        let meaning = attr(b["m"], size: 17)
        let hasMeaning = !meaning.characters.isEmpty
        let authors = b["au"] as? String
        let examples = (b["x"] as? [[String: Any]]) ?? []
        return HStack(alignment: .top, spacing: 8) {
            if hasNumbers {
                Text(num ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.accent)
                    .frame(width: 26, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                if hasMeaning {
                    Text(meaning).fixedSize(horizontal: false, vertical: true)
                }
                if let authors {
                    Text(authors).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(examples.enumerated()), id: \.offset) { _, x in
                    example(x)
                }
            }
        }
        .padding(.leading, CGFloat(level) * 18)
    }

    private func example(_ x: [String: Any]) -> some View {
        let quote = attr(x["q"], size: 16)
        let tr = attr(x["t"], size: 15)
        return VStack(alignment: .leading, spacing: 3) {
            Text(quote).fixedSize(horizontal: false, vertical: true)
            if !tr.characters.isEmpty {
                Text(tr).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(pal.accent.opacity(0.35)).frame(width: 3)
        }
    }

    private func legend(_ b: [String: Any]) -> some View {
        let rows = (b["a"] as? [[Any]]) ?? []
        let line = rows.compactMap { r -> String? in
            guard r.count >= 2, let n = r[0] as? String, let y = r[1] as? String else { return nil }
            return "\(n) (\(y))"
        }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Авторы примеров").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(line).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Спаны [текст, стиль] → одна строка с оформлением
    private func attr(_ any: Any?, size: CGFloat) -> AttributedString {
        var out = AttributedString()
        for p in (any as? [[Any]]) ?? [] {
            guard p.count >= 2, let t = p[0] as? String, let st = p[1] as? String else { continue }
            var a = AttributedString(t)
            switch st {
            case "g":
                a.font = .system(size: size + 1, design: .serif)
            case "k":
                // изучаемое слово в примере (в нужной форме): жирным и цветной подложкой
                a.font = .system(size: size + 1, weight: .bold, design: .serif)
                a.backgroundColor = pal.accent.opacity(0.2)
            case "h":
                a.font = .system(size: size + 6, weight: .bold, design: .serif)
            case "b":
                a.font = .system(size: size, weight: .semibold)
            case "i":
                a.font = .system(size: size - 2).italic()
                a.foregroundColor = Color.secondary
            case "a":
                a.font = .system(size: size - 3, weight: .medium)
                a.foregroundColor = Color.secondary
            default:
                a.font = .system(size: size)
            }
            out += a
        }
        return out
    }
}
