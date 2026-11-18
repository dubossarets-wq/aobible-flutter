import UIKit

extension NSAttributedString.Key {
    /// Цельная скруглённая плашка под текстом (выделение части стиха, любимая часть стиха) — значение PlateStyle
    static let aobPlate = NSAttributedString.Key("aobPlate")
}

/// Вид плашки: цвет, радиус скругления и поля вокруг текста
final class PlateStyle: NSObject {
    let color: UIColor
    let radius: CGFloat
    let inflate: CGFloat

    init(_ color: UIColor, radius: CGFloat = 3, inflate: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.inflate = inflate
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? PlateStyle else { return false }
        return o.color == color && o.radius == radius && o.inflate == inflate
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(color)
        h.combine(radius)
        h.combine(inflate)
        return h.finalize()
    }
}

/// Раскладка текста, которая под отрезками с меткой aobPlate рисует ОДНУ цельную плашку на весь отрезок
/// (как во Flutter, part_plate.dart): строки стыкуются посередине межстрочного промежутка, каждый угол контура
/// скруглён — выпуклые наружу, «ступеньки» между строками разной длины внутрь; закрашивается один раз
final class PlateLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard shown.length > 0 else { return }
        storage.enumerateAttribute(.aobPlate, in: shown, options: []) { value, range, _ in
            guard let st = value as? PlateStyle else { return }
            // плашка целиком (она может начинаться раньше показанного куска)
            var full = NSRange()
            _ = storage.attribute(.aobPlate, at: range.location, longestEffectiveRange: &full, in: NSRange(location: 0, length: storage.length))
            let lines = lineRects(full, within: glyphsToShow)
            guard !lines.isEmpty else { return }
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.addPath(Self.platePath(lines, r: st.radius, pad: st.inflate))
            ctx.setFillColor(st.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    /// Прямоугольники строк отрезка (по одному на строку), высотой со строку текста — без межстрочного интервала
    private func lineRects(_ chars: NSRange, within shown: NSRange) -> [CGRect] {
        let g = glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        let target = NSIntersectionRange(g, shown)
        guard target.length > 0 else { return [] }
        var rects: [CGRect] = []
        var i = target.location
        while i < NSMaxRange(target) {
            var lineRange = NSRange()
            let used = lineFragmentUsedRect(forGlyphAt: i, effectiveRange: &lineRange)
            let sub = NSIntersectionRange(lineRange, target)
            if sub.length > 0, let tc = textContainer(forGlyphAt: sub.location, effectiveRange: nil) {
                let b = boundingRect(forGlyphRange: sub, in: tc)
                let ci = characterIndexForGlyph(at: sub.location)
                let ps = textStorage?.attribute(.paragraphStyle, at: ci, effectiveRange: nil) as? NSParagraphStyle
                let h = max(1, used.height - (ps?.lineSpacing ?? 0))
                let r = CGRect(x: b.minX, y: used.minY, width: b.width, height: h)
                if r.width >= 1 { rects.append(r) }
            }
            if NSMaxRange(lineRange) <= i { break }
            i = NSMaxRange(lineRange)
        }
        return rects
    }

    /// Контур цельной плашки по прямоугольникам строк (порт partPlatePath из Flutter)
    static func platePath(_ src: [CGRect], r: CGFloat, pad: CGFloat) -> CGPath {
        var ls = src.sorted { $0.minY < $1.minY }.map { [$0.minX - pad, $0.minY, $0.maxX + pad, $0.maxY] }
        let path = CGMutablePath()
        guard !ls.isEmpty else { return path }
        if ls.count > 1 {
            for i in 1..<ls.count {
                let y = (ls[i - 1][3] + ls[i][1]) / 2
                ls[i - 1][3] = y
                ls[i][1] = y
            }
        }
        ls[0][1] -= pad
        ls[ls.count - 1][3] += pad
        // обход по часовой стрелке: правый край сверху вниз, затем левый снизу вверх
        var pts: [CGPoint] = []
        for l in ls {
            pts.append(CGPoint(x: l[2], y: l[1]))
            pts.append(CGPoint(x: l[2], y: l[3]))
        }
        for l in ls.reversed() {
            pts.append(CGPoint(x: l[0], y: l[3]))
            pts.append(CGPoint(x: l[0], y: l[1]))
        }
        // убрать совпадающие и лежащие на одной прямой вершины
        var v: [CGPoint] = []
        for q in pts where v.isEmpty || hypot(v[v.count - 1].x - q.x, v[v.count - 1].y - q.y) > 0.01 {
            v.append(q)
        }
        if v.count > 1, hypot(v[0].x - v[v.count - 1].x, v[0].y - v[v.count - 1].y) < 0.01 { v.removeLast() }
        var again = true
        while again && v.count > 3 {
            again = false
            for i in 0..<v.count {
                let p0 = v[(i + v.count - 1) % v.count], p1 = v[i], p2 = v[(i + 1) % v.count]
                let cr = (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x)
                if abs(cr) < 0.01 {
                    v.remove(at: i)
                    again = true
                    break
                }
            }
        }
        let n = v.count
        guard n >= 3 else { return path }
        // начинаем с середины ребра, входящего в первую вершину; каждая вершина — дуга радиуса r
        path.move(to: CGPoint(x: (v[n - 1].x + v[0].x) / 2, y: (v[n - 1].y + v[0].y) / 2))
        for i in 0..<n {
            let p0 = v[(i + n - 1) % n], p1 = v[i], p2 = v[(i + 1) % n]
            let d1 = hypot(p0.x - p1.x, p0.y - p1.y), d2 = hypot(p2.x - p1.x, p2.y - p1.y)
            let rad = min(r, d1 / 2, d2 / 2)
            path.addArc(tangent1End: p1, tangent2End: p2, radius: rad)
        }
        path.closeSubpath()
        return path
    }
}
