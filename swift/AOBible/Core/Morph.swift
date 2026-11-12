import Foundation

// Расшифровка морфологических кодов на русском (порт morph.dart Flutter-версии):
//  • коды Стронга TVM для иврита (RST+, например TH8804) — по сетке FHL;
//  • коды Робинсона для греческого (byz-rp2018, например V-PAI-1S) и коды OSHB для иврита и арамейского
//    (oshb, например HC/Vqw3ms) — по таблицам morph-data.json и greek-tvm.json (те же, что во Flutter).
// Для неизвестных кодов — nil (показывается сам код).
enum Morph {
    private static let forms = ["перфект", "имперфект", "повелительное наклонение", "инфинитив", "действительное причастие", "страдательное причастие", "причастие"]
    private static let grid: [(String, [Int?])] = [
        ("Кал (Qal)", [8804, 8799, 8798, 8800, 8802, 8803, 8801]),
        ("Пиэль (Piel)", [8765, 8762, 8761, 8763, nil, nil, 8764]),
        ("Пуаль (Pual)", [8795, 8792, nil, nil, nil, nil, 8794]),
        ("Нифаль (Niphal)", [8738, 8735, 8734, 8736, nil, nil, 8737]),
        ("Хифиль (Hiphil)", [8689, 8686, 8685, 8687, nil, nil, 8688]),
        ("Хофаль (Hophal)", [8717, 8714, nil, 8715, nil, nil, 8716]),
        ("Хитпаэль (Hithpael)", [8694, 8691, 8690, 8692, nil, nil, 8693]),
        ("Полель (Polel)", [8790, 8787, nil, 8788, nil, nil, 8789]),
        ("Пеэль/Пеиль (Peel/Peil)", [nil, nil, nil, 8756, nil, nil, nil]),
        ("Поэль (Poel)", [nil, 8779, nil, 8780, nil, nil, 8781]),
        ("Поаль (Poal)", [8776, nil, nil, nil, nil, nil, nil]),
        ("Пилпель (Pilpel)", [8773, 8770, 8769, 8771, nil, nil, 8772]),
        ("Пилель (Pilel)", [8768, 8766, nil, nil, nil, nil, nil]),
        ("Пулаль (Pulal)", [8797, nil, nil, nil, nil, nil, nil]),
        ("Хитпоэль (Hithpoel)", [nil, 8704, 8703, nil, nil, nil, 8706]),
        ("Хитполель (Hithpolel)", [8712, 8709, nil, nil, nil, nil, nil]),
        ("Хитпалпель (Hithpalpel)", [nil, 8698, nil, nil, nil, nil, nil]),
        ("Шафель (Shaphel)", [8806, nil, nil, nil, nil, nil, nil]),
    ]

    private static let tvm: [Int: (String, String)] = {
        var m: [Int: (String, String)] = [:]
        for (stem, codes) in grid {
            for (i, c) in codes.enumerated() {
                if let c { m[c] = (stem, forms[i]) }
            }
        }
        return m
    }()

    private static func load(_ name: String) -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return j
    }

    private static let data = load("morph-data")
    private static let greekTvm = load("greek-tvm")

    private static func t(_ s: String) -> String {
        NSLocalizedString(s, comment: "")
    }

    private struct Slot {
        let name: String
        let key: String
        let value: [String: Any]?
    }

    private static func slotTable(_ section: [String: Any], _ name: String, _ lang: String?) -> [String: Any] {
        if let byLang = section["slotsByLanguage"] as? [String: Any], let m = byLang[name] as? [String: Any] {
            if let lang, let x = m[lang] as? [String: Any] { return x }
            return [:]
        }
        return ((section["slots"] as? [String: Any])?[name] as? [String: Any]) ?? [:]
    }

    private static func matchForm(_ section: [String: Any], _ form: [String: Any], _ body: String, _ lang: String? = nil) -> [Slot]? {
        let ph = section["placeholder"] as? String
        let b = Array(body)
        var pos = 0
        var out: [Slot] = []
        for name in (form["slots"] as? [String]) ?? [] {
            if pos == b.count {
                if section["allowShort"] as? Bool == true { break }
                return nil
            }
            if name == "-" {
                if b[pos] != "-" { return nil }
                pos += 1
                continue
            }
            if let ph, String(b[pos]) == ph {
                out.append(Slot(name: name, key: ph, value: nil))
                pos += 1
                continue
            }
            let table = slotTable(section, name, lang)
            var key: String?
            var n = min(4, b.count - pos)
            while n > 0 {
                let k = String(b[pos..<(pos + n)])
                if table[k] != nil {
                    key = k
                    break
                }
                n -= 1
            }
            guard let key else { return nil }
            out.append(Slot(name: name, key: key, value: table[key] as? [String: Any]))
            pos += key.count
        }
        if pos != b.count { return nil }
        let when = form["when"] as? [String: Any] ?? [:]
        for (k, v) in when {
            if let got = out.first(where: { $0.name == k })?.key, got != ph, !((v as? [String]) ?? []).contains(got) { return nil }
        }
        return out
    }

    private struct Seg {
        var info: [String: Any]?
        var slots: [Slot] = []
        var error = false
        var suffixes: [[String: Any]] = []
    }

    private static func parseBody(_ section: [String: Any], _ posCode: String, _ body: String, _ lang: String? = nil) -> Seg {
        guard let info = (section["pos"] as? [String: Any])?[posCode] as? [String: Any] else { return Seg(error: true) }
        for form in (info["forms"] as? [[String: Any]]) ?? [] {
            if let slots = matchForm(section, form, body, lang) { return Seg(info: info, slots: slots) }
        }
        return Seg(info: info, error: true)
    }

    private static func parseGreek(_ code: String) -> [Seg]? {
        guard let g = data["greek"] as? [String: Any], let sep = g["separator"] as? String else { return nil }
        let suffixTable = g["suffixes"] as? [String: Any] ?? [:]
        var parts = code.components(separatedBy: sep)
        var suffixes: [String] = []
        while parts.count > 1, let last = parts.last, suffixTable[last] != nil {
            suffixes.insert(parts.removeLast(), at: 0)
        }
        var seg = parseBody(g, parts[0], parts.dropFirst().joined(separator: sep))
        seg.suffixes = suffixes.compactMap { suffixTable[$0] as? [String: Any] }
        return [seg]
    }

    private static func parseHebrew(_ code: String) -> [Seg]? {
        guard let h = data["hebrew"] as? [String: Any], let first = code.first,
              let langs = h["languages"] as? [String: Any], langs[String(first)] != nil,
              let sep = h["segmentSeparator"] as? String else { return nil }
        let lang = String(first)
        return String(code.dropFirst()).components(separatedBy: sep).map { s in
            guard let p = s.first else { return Seg(error: true) }
            return parseBody(h, String(p), String(s.dropFirst()), lang)
        }
    }

    private static func describeParsed(_ segs: [Seg]?) -> String? {
        guard let segs, !segs.contains(where: { $0.error }) else { return nil }
        return segs.map { s in
            var parts: [String] = []
            if let r = s.info?["ru"] as? String { parts.append(r) }
            parts += s.slots.compactMap { $0.value?["ru"] as? String }
            parts += s.suffixes.compactMap { $0["ru"] as? String }
            return parts.map(t).joined(separator: ", ")
        }.joined(separator: " + ")
    }

    private static let tvmRe = try! NSRegularExpression(pattern: "^T?([HG])(\\d+)$")
    private static let hebRe = try! NSRegularExpression(pattern: "^[HA][A-Za-z0-9/]*$")

    /// Расшифровка кода; nil — не знаем
    static func describe(_ code: String) -> String? {
        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = tvmRe.firstMatch(in: code, range: full) {
            let letter = ns.substring(with: m.range(at: 1))
            guard let n = Int(ns.substring(with: m.range(at: 2))) else { return nil }
            if letter == "H" {
                guard let v = tvm[n] else { return nil }
                return "\(t(v.0)), \(t(v.1))"
            }
            // в коде TVM нет лица, числа и падежа — только время, залог и наклонение
            guard let rob = greekTvm["\(n)"] as? String, let g = data["greek"] as? [String: Any] else { return nil }
            let body = rob.firstIndex(of: "-").map { String(rob[rob.index(after: $0)...]) } ?? ""
            guard let slots = matchForm(g, ["slots": ["tense", "voice", "mood"]], body) else { return nil }
            var parts: [String] = []
            if let v = ((g["pos"] as? [String: Any])?["V"] as? [String: Any])?["ru"] as? String { parts.append(v) }
            parts += slots.compactMap { $0.value?["ru"] as? String }
            return parts.map(t).joined(separator: ", ")
        }
        let g = data["greek"] as? [String: Any] ?? [:]
        let greekPos = g["pos"] as? [String: Any] ?? [:]
        let hebrew = hebRe.firstMatch(in: code, range: full) != nil && !code.contains("-") && greekPos[code] == nil
        return describeParsed(hebrew ? parseHebrew(code) : parseGreek(code))
    }
}
