import SwiftUI

/// Куда ведёт ссылка в тексте толкования. Открывается страницей поверх толкования: «назад» возвращает к тексту
enum CommLink: Hashable {
    case verse(book: String, chapter: Int, verse: Int, end: Int?)
    case strong(String)
    case word(String)
    case comment(book: String, chapter: Int, verse: Int)

    var url: URL? {
        switch self {
        case .verse(let b, let c, let v, let e):
            return URL(string: "aobverse:\(b)/\(c)/\(v)/\(e ?? 0)")
        case .strong(let k):
            return URL(string: "aobstrong:\(k)")
        case .word(let w):
            guard let enc = w.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
            return URL(string: "aobword:\(enc)")
        case .comment(let b, let c, let v):
            return URL(string: "aobcomm:\(b)/\(c)/\(v)")
        }
    }

    init?(url: URL) {
        let s = url.absoluteString
        func rest(_ p: String) -> String { String(s.dropFirst(p.count)) }
        switch url.scheme {
        case "aobverse":
            let p = rest("aobverse:").split(separator: "/").map(String.init)
            guard p.count == 4, let c = Int(p[1]), let v = Int(p[2]), let e = Int(p[3]) else { return nil }
            self = .verse(book: p[0], chapter: c, verse: v, end: e > v ? e : nil)
        case "aobcomm":
            let p = rest("aobcomm:").split(separator: "/").map(String.init)
            guard p.count == 3, let c = Int(p[1]), let v = Int(p[2]) else { return nil }
            self = .comment(book: p[0], chapter: c, verse: v)
        case "aobstrong":
            guard let k = StrongLinks.key(from: url), !k.isEmpty else { return nil }
            self = .strong(Lexicon.strongKey(k))
        case "aobword":
            guard let w = rest("aobword:").removingPercentEncoding, !w.isEmpty else { return nil }
            self = .word(w)
        default:
            return nil
        }
    }
}

/// Ссылки в тексте толкования: места Писания («Иез XVI:8», «Лев XXV:25-26; 3 Цар XVI:11», «ст. 13», «IV:3-5»),
/// номера Стронга и слова на греческом и иврите (а также «евр. goel»)
enum CommentaryLinks {
    private static let romanChars = "IVXLC"

    /// «XVI» → 16; не римское число — nil
    static func roman(_ s: String) -> Int? {
        guard !s.isEmpty, s.allSatisfy({ romanChars.contains($0) }) else { return nil }
        let val: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100]
        var total = 0
        var prev = 0
        for ch in s.reversed() {
            let v = val[ch] ?? 0
            total += v < prev ? -v : v
            prev = max(prev, v)
        }
        return total > 0 && total <= 150 ? total : nil
    }

    private static func number(_ s: String) -> Int? {
        Int(s) ?? roman(s)
    }

    private static let verseList = #"\d+(?:\s*[-\x{2010}-\x{2015}\x{2212}]\s*\d+)?(?:\s*,\s*\d+(?:\s*[-\x{2010}-\x{2015}\x{2212}]\s*\d+)?)*"#
    private static let chap = #"(?:\d+|[IVXLC]+)"#
    /// Книга (с номером впереди и, возможно, вторым словом: «Иис. Нав.»), глава (цифрами или римскими), стихи
    private static let bookRe = try! NSRegularExpression(
        pattern: #"((?:[1-4]\s?)?[А-ЯЁ][а-яё]+\.?)(\s[А-ЯЁ][а-яё]+\.?)?\s*("# + chap + #")\s*[:.]\s*("# + verseList + #")"#)
    /// Без книги — глава и стихи той же книги («IV:3-5»)
    private static let chapOnlyRe = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d])([IVXLC]+)\s*:\s*("# + verseList + #")"#)
    /// «ст. 13», «стт. 3-5»
    private static let verseOnlyRe = try! NSRegularExpression(
        pattern: #"(?<![\p{L}])стт?\.\s*("# + verseList + #")"#)
    private static let partRe = try! NSRegularExpression(pattern: #"(\d+)(?:\s*[-\x{2010}-\x{2015}\x{2212}]\s*(\d+))?"#)
    private static let strongRe = try! NSRegularExpression(pattern: #"(?<![A-Za-z])[HG]\d+"#)
    private static let originalRe = try! NSRegularExpression(pattern: "[\u{0370}-\u{03FF}\u{1F00}-\u{1FFF}]{2,}|[\u{0590}-\u{05FF}]{2,}")
    /// Слово латиницей после «евр.» / «греч.» — транслитерация слова оригинала
    private static let translitRe = try! NSRegularExpression(pattern: #"(?:евр|греч|арам)\.\s*([A-Za-z][A-Za-z'’ʼ]{1,})"#)

    /// Текст толкования со ссылками. Место ведёт целиком («Иез XVI:8» → ссылка «Иез 16:8»: римские главы заменены
    /// арабскими); у номеров Стронга и слов оригинала текст прежний
    @MainActor
    static func attributed(_ s: String, book: String, chapter: Int) -> AttributedString {
        let ns = s as NSString
        let all = NSRange(location: 0, length: ns.length)
        // что показываем вместо куска исходного текста и куда он ведёт
        var spans: [(r: NSRange, text: String, link: CommLink, lead: Bool)] = []

        func free(_ r: NSRange) -> Bool { !spans.contains { NSIntersectionRange($0.r, r).length > 0 } }
        // lead — перед местом нужен пробел, если оно приклеено к слову («путьИн 14:6» → «путь Ин 14:6»)
        func put(_ r: NSRange, _ text: String, _ link: CommLink, lead: Bool = false) {
            if free(r) { spans.append((r, text, link, lead)) }
        }

        /// Место целиком: от начала («Иез 16:») до первого стиха — одна ссылка; «25-26», «6, 9» — у остальных частей своя
        func putPlace(from start: Int, label: String, list: NSRange, book b: String, chapter c: Int) {
            var first = true
            for m in partRe.matches(in: s, range: list) {
                guard let v = Int(ns.substring(with: m.range(at: 1))) else { continue }
                let e = m.range(at: 2).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 2)))
                let part = ns.substring(with: m.range)
                let link = CommLink.verse(book: b, chapter: c, verse: v, end: e)
                if first {
                    put(NSRange(location: start, length: m.range.location + m.range.length - start), label + part, link, lead: true)
                    first = false
                } else {
                    put(m.range, part, link)
                }
            }
        }

        // 1. С названием книги
        for m in bookRe.matches(in: s, range: all) {
            let first = ns.substring(with: m.range(at: 1))
            let hasSecond = m.range(at: 2).location != NSNotFound
            let second = hasSecond ? ns.substring(with: m.range(at: 2)) : nil
            // «Иис. Нав.» целиком; нет — второе слово («Ср. Иез» → Иез); нет — первое
            var b: String?
            var from = m.range(at: 1).location
            if let second, let x = RefParser.findBook(first + second) {
                b = x
            } else if let second, let x = RefParser.findBook(second) {
                b = x
                from = m.range(at: 2).location + 1
            } else {
                b = RefParser.findBook(first)
            }
            let chapRange = m.range(at: 3)
            guard let b, let c = number(ns.substring(with: chapRange)), c >= 1 else { continue }
            let name = ns.substring(with: NSRange(location: from, length: chapRange.location - from)).trimmingCharacters(in: .whitespaces)
            putPlace(from: from, label: "\(name) \(c):", list: m.range(at: 4), book: b, chapter: c)
        }
        // 2. Глава римскими без книги — книга толкования («IV:10» → «4:10»)
        for m in chapOnlyRe.matches(in: s, range: all) {
            guard let c = roman(ns.substring(with: m.range(at: 1))) else { continue }
            if !free(m.range) { continue }
            putPlace(from: m.range.location, label: "\(c):", list: m.range(at: 2), book: book, chapter: c)
        }
        // 3. «ст. 13» — стих этой же главы
        for m in verseOnlyRe.matches(in: s, range: all) {
            let list = m.range(at: 1)
            let label = ns.substring(with: NSRange(location: m.range.location, length: list.location - m.range.location))
            putPlace(from: m.range.location, label: label, list: list, book: book, chapter: chapter)
        }
        // 4. Номера Стронга
        for m in strongRe.matches(in: s, range: all) {
            let t = ns.substring(with: m.range)
            put(m.range, t, .strong(Lexicon.strongKey(t)))
        }
        // 5. Слова на греческом и иврите
        for m in originalRe.matches(in: s, range: all) {
            let t = ns.substring(with: m.range)
            put(m.range, t, .word(t))
        }
        for m in translitRe.matches(in: s, range: all) {
            let t = ns.substring(with: m.range(at: 1))
            put(m.range(at: 1), t, .word(t))
        }

        // сборка: нетронутый текст — как есть, ссылки — с новым текстом
        var out = AttributedString()
        var at = 0
        for sp in spans.sorted(by: { $0.r.location < $1.r.location }) {
            if sp.r.location > at {
                out += AttributedString(ns.substring(with: NSRange(location: at, length: sp.r.location - at)))
            }
            // место приклеено к слову или знаку («Твое» + «Пс 109:3») — между ними пробел
            if sp.lead, sp.r.location > 0, let u = UnicodeScalar(ns.character(at: sp.r.location - 1)),
               CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: ")»”.,;:!?")).contains(u) {
                out += AttributedString(" ")
            }
            var piece = AttributedString(sp.text)
            piece.link = sp.link.url
            out += piece
            at = sp.r.location + sp.r.length
        }
        if at < ns.length { out += AttributedString(ns.substring(from: at)) }
        return out
    }
}

/// Поиск статей Стронга по слову оригинала: греческому, ивриту или транслитерации. Без диакритики, придыханий
/// и огласовок (в толкованиях они обычно потеряны)
@MainActor
enum OriginalWords {
    private static var lemmaCache: [String: [String: [String]]] = [:]
    private static var xlitCache: [String: [String: [String]]] = [:]

    private static let finals: [Character: Character] = ["ς": "σ", "ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ"]

    /// Нижний регистр, без диакритики и знаков, конечные формы букв — в обычные
    static func fold(_ s: String) -> String {
        var out = ""
        for u in s.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            switch u.properties.generalCategory {
            case .lowercaseLetter, .uppercaseLetter, .otherLetter:
                let ch = Character(u)
                out.append(finals[ch] ?? ch)
            default:
                continue
            }
        }
        return out
    }

    private static func index(_ store: ModuleStore, _ m: InstalledModule, translit: Bool) -> [String: [String]] {
        if let c = (translit ? xlitCache : lemmaCache)[m.id] { return c }
        var map: [String: [String]] = [:]
        if let d = store.db(m.id) {
            let sql = translit ? "SELECT key, ifnull(json_extract(json, '$.xlit'), '') FROM dict" : "SELECT key, word FROM dict"
            for (key, w) in d.query(sql, [], { ($0.text(0), $0.text(1)) }) {
                let f = fold(w)
                if !f.isEmpty { map[f, default: []].append(key) }
            }
        }
        if translit { xlitCache[m.id] = map } else { lemmaCache[m.id] = map }
        return map
    }

    /// Номера Стронга для слова: точное совпадение; нет — слова с тем же началом (формы слова: «αγχιστευς» ≈ «αγχιστευσ»)
    static func keys(store: ModuleStore, word: String) -> [(module: InstalledModule, key: String)] {
        let f = fold(word)
        guard f.count >= 2 else { return [] }
        let latin = f.unicodeScalars.allSatisfy { $0.isASCII }
        let mods = store.dictionaries.filter { $0.dictionaryKind == "strongs" }
        var out: [(module: InstalledModule, key: String)] = []
        var seen = Set<String>()

        func add(_ m: InstalledModule, _ ks: [String]) {
            for k in ks where seen.insert(k).inserted { out.append((m, k)) }
        }

        for m in mods {
            add(m, index(store, m, translit: latin)[f] ?? [])
        }
        if out.isEmpty, f.count >= 5 {
            let stem = String(f.dropLast(2))
            for m in mods {
                let idx = index(store, m, translit: latin)
                let near = idx.keys.filter { $0.hasPrefix(stem) && abs($0.count - f.count) <= 2 }.sorted()
                for k in near.prefix(4) { add(m, idx[k] ?? []) }
            }
        }
        return Array(out.prefix(6))
    }
}

/// Слово оригинала из толкования: найденные статьи Стронга; нажатие открывает статью, «назад» — к толкованию
struct OriginalWordPage: View {
    @EnvironmentObject private var store: ModuleStore
    let word: String
    @State private var rows: [DictArticle]?

    var body: some View {
        List {
            if let rows {
                if rows.isEmpty {
                    Text("Статей для «\(word)» нет").foregroundStyle(.secondary)
                }
                ForEach(rows) { a in
                    NavigationLink {
                        DictEntryPage(start: a)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                StrongBadge()
                                Text(a.word).font(.body.weight(.medium))
                            }
                            let sn = a.snippet(store)
                            if !sn.isEmpty {
                                Text(sn).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ищу в словарях…").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(word)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await Task.yield()
            rows = OriginalWords.keys(store: store, word: word).compactMap { h in
                guard let e = store.strongOrWordEntry(module: h.module, key: h.key) else { return nil }
                return store.article(h.module, key: h.key, word: ModuleStore.strongWord(e, h.key))
            }
        }
    }
}

/// Номер Стронга из толкования: полная статья (если словарь есть) или список статей
struct CommentaryStrongPage: View {
    @EnvironmentObject private var store: ModuleStore
    let key: String
    let onLink: (String) -> Void

    var body: some View {
        if let m = store.dictionaries.first(where: { $0.dictionaryKind == "strongs" && store.strongOrWordEntry(module: $0, key: key) != nil }),
           let e = store.strongOrWordEntry(module: m, key: key) {
            DictEntryPage(start: store.article(m, key: key, word: ModuleStore.strongWord(e, key)))
        } else {
            StrongList(keys: [key], onLink: onLink)
                .navigationTitle(key)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Место Писания из толкования: текст стиха (или нескольких) основного перевода, кнопки «Читать» и «Толкования»
struct CommentaryVersePage: View {
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var panes: PanesStore
    let book: String
    let chapter: Int
    let verse: Int
    let end: Int?
    let onRead: (String, Int, Int) -> Void
    let onComment: (String, Int, Int) -> Void

    private var module: InstalledModule? { store.module(panes.primaryModule) ?? store.bibles.first }

    private var title: String {
        let short = module?.books.first { $0.id == book }?.short ?? Books.info(book)?.short ?? book
        var s = "\(short) \(chapter):\(verse)"
        if let e = end { s += "–\(e)" }
        return s
    }

    private var texts: [(Int, String)] {
        guard let m = module else { return [] }
        let last = min(end ?? verse, verse + 40)
        return (verse...max(verse, last)).compactMap { v in
            store.verseText(module: m.id, book: book, chapter: chapter, verse: v).map { (v, $0) }
        }
    }

    var body: some View {
        let list = texts
        List {
            Section {
                if list.isEmpty {
                    Text("Такого стиха в этом переводе нет.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(list, id: \.0) { v, t in
                            (Text("\(v) ").font(.system(size: 12, weight: .bold)).foregroundColor(.accentColor).baselineOffset(5)
                                + Text(t).font(.system(size: 18, design: .serif)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                if let m = module { Text(m.name) }
            }
            Section {
                Button { onRead(book, chapter, verse) } label: {
                    Label("Читать", systemImage: "book")
                }
                if !store.commentary(book: book, chapter: chapter, verse: verse).isEmpty {
                    Button { onComment(book, chapter, verse) } label: {
                        Label("Толкования", systemImage: "text.book.closed")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
