import Foundation

/// Английские названия книг и дополнительные сокращения для ввода ссылок —
/// те же таблицы, что в lib/core/books.dart Flutter-версии (сгенерировано, руками не править)
enum BookNames {
    static let en: [String: [String]] = [
        "Gen": ["Genesis", "Gen"],
        "Exod": ["Exodus", "Exod"],
        "Lev": ["Leviticus", "Lev"],
        "Num": ["Numbers", "Num"],
        "Deut": ["Deuteronomy", "Deut"],
        "Josh": ["Joshua", "Josh"],
        "Judg": ["Judges", "Judg"],
        "Ruth": ["Ruth", "Ruth"],
        "1Sam": ["1 Samuel", "1 Sam"],
        "2Sam": ["2 Samuel", "2 Sam"],
        "1Kgs": ["1 Kings", "1 Kgs"],
        "2Kgs": ["2 Kings", "2 Kgs"],
        "1Chr": ["1 Chronicles", "1 Chr"],
        "2Chr": ["2 Chronicles", "2 Chr"],
        "PrMan": ["Prayer of Manasseh", "Pr Man"],
        "Ezra": ["Ezra", "Ezra"],
        "Neh": ["Nehemiah", "Neh"],
        "1Esd": ["1 Esdras", "1 Esd"],
        "Tob": ["Tobit", "Tob"],
        "Jdt": ["Judith", "Jdt"],
        "Esth": ["Esther", "Esth"],
        "Job": ["Job", "Job"],
        "Ps": ["Psalms", "Ps"],
        "Prov": ["Proverbs", "Prov"],
        "Eccl": ["Ecclesiastes", "Eccl"],
        "Song": ["Song of Songs", "Song"],
        "Wis": ["Wisdom of Solomon", "Wis"],
        "Sir": ["Sirach", "Sir"],
        "Isa": ["Isaiah", "Isa"],
        "Jer": ["Jeremiah", "Jer"],
        "Lam": ["Lamentations", "Lam"],
        "EpJer": ["Letter of Jeremiah", "Ep Jer"],
        "Bar": ["Baruch", "Bar"],
        "Ezek": ["Ezekiel", "Ezek"],
        "Dan": ["Daniel", "Dan"],
        "Hos": ["Hosea", "Hos"],
        "Joel": ["Joel", "Joel"],
        "Amos": ["Amos", "Amos"],
        "Obad": ["Obadiah", "Obad"],
        "Jonah": ["Jonah", "Jonah"],
        "Mic": ["Micah", "Mic"],
        "Nah": ["Nahum", "Nah"],
        "Hab": ["Habakkuk", "Hab"],
        "Zeph": ["Zephaniah", "Zeph"],
        "Hag": ["Haggai", "Hag"],
        "Zech": ["Zechariah", "Zech"],
        "Mal": ["Malachi", "Mal"],
        "1Macc": ["1 Maccabees", "1 Macc"],
        "2Macc": ["2 Maccabees", "2 Macc"],
        "3Macc": ["3 Maccabees", "3 Macc"],
        "2Esd": ["2 Esdras", "2 Esd"],
        "Matt": ["Matthew", "Matt"],
        "Mark": ["Mark", "Mark"],
        "Luke": ["Luke", "Luke"],
        "John": ["John", "John"],
        "Acts": ["Acts", "Acts"],
        "Jas": ["James", "Jas"],
        "1Pet": ["1 Peter", "1 Pet"],
        "2Pet": ["2 Peter", "2 Pet"],
        "1John": ["1 John", "1 John"],
        "2John": ["2 John", "2 John"],
        "3John": ["3 John", "3 John"],
        "Jude": ["Jude", "Jude"],
        "Rom": ["Romans", "Rom"],
        "1Cor": ["1 Corinthians", "1 Cor"],
        "2Cor": ["2 Corinthians", "2 Cor"],
        "Gal": ["Galatians", "Gal"],
        "Eph": ["Ephesians", "Eph"],
        "Phil": ["Philippians", "Phil"],
        "Col": ["Colossians", "Col"],
        "1Thess": ["1 Thessalonians", "1 Thess"],
        "2Thess": ["2 Thessalonians", "2 Thess"],
        "1Tim": ["1 Timothy", "1 Tim"],
        "2Tim": ["2 Timothy", "2 Tim"],
        "Titus": ["Titus", "Titus"],
        "Phlm": ["Philemon", "Phlm"],
        "Heb": ["Hebrews", "Heb"],
        "Rev": ["Revelation", "Rev"],
        "Ps151": ["Psalm 151", "Ps 151"],
        "PrAzar": ["Prayer of Azariah", "Pr Azar"],
        "Sus": ["Susanna", "Sus"],
        "Bel": ["Bel and the Dragon", "Bel"],
        "1En": ["1 Enoch", "1 En"],
        "Jub": ["Jubilees", "Jub"],
        "TReu": ["Testament of Reuben", "T. Reu."],
        "TSim": ["Testament of Simeon", "T. Sim."],
        "TLevi": ["Testament of Levi", "T. Levi"],
        "TJud": ["Testament of Judah", "T. Jud."],
        "TIss": ["Testament of Issachar", "T. Iss."],
        "TZeb": ["Testament of Zebulun", "T. Zeb."],
        "TDan": ["Testament of Dan", "T. Dan"],
        "TNaph": ["Testament of Naphtali", "T. Naph."],
        "TGad": ["Testament of Gad", "T. Gad"],
        "TAsh": ["Testament of Asher", "T. Ash."],
        "TJos": ["Testament of Joseph", "T. Jos."],
        "TBenj": ["Testament of Benjamin", "T. Benj."],
    ]

    /// Порядок записей важен: при совпадении ключей побеждает последний, а поиск по началу идёт в порядке добавления
    static let extra: [(String, [String])] = [
        ("Gen", ["бт", "бытия"]),
        ("Exod", ["исход"]),
        ("Num", ["чисел", "числ"]),
        ("Deut", ["вт", "второзак"]),
        ("Josh", ["иисуснавин", "навин", "ииснав"]),
        ("Judg", ["судей"]),
        ("1Sam", ["1царств", "1цар", "1sam"]),
        ("2Sam", ["2царств", "2цар"]),
        ("1Kgs", ["3царств", "3цар"]),
        ("2Kgs", ["4царств", "4цар"]),
        ("1Chr", ["1пар", "1паралипоменон"]),
        ("2Chr", ["2пар", "2паралипоменон"]),
        ("Ezra", ["ездр", "ездры"]),
        ("Neh", ["неемии"]),
        ("Esth", ["есфири"]),
        ("Ps", ["псалом", "псалмы", "псалтирь", "пс"]),
        ("Prov", ["притч", "пр"]),
        ("Eccl", ["екл", "еккл", "екклесиаста"]),
        ("Song", ["песн", "песнь", "песньпесней"]),
        ("Isa", ["исаии", "исаия"]),
        ("Jer", ["иеремии"]),
        ("Lam", ["плачиеремии"]),
        ("Ezek", ["иезекииля", "иез"]),
        ("Dan", ["даниила"]),
        ("Hos", ["осии"]),
        ("Joel", ["иоиля"]),
        ("Jonah", ["ионы"]),
        ("Mic", ["михея"]),
        ("Hab", ["аввакума"]),
        ("Zeph", ["софонии"]),
        ("Hag", ["аггея"]),
        ("Zech", ["захарии"]),
        ("Mal", ["малахии"]),
        ("Matt", ["мф", "мтф", "матф", "матфея", "отматфея", "мт"]),
        ("Mark", ["мк", "мар", "марк", "марка", "отмарка"]),
        ("Luke", ["лк", "лук", "луки", "отлуки"]),
        ("John", ["ин", "иоан", "иоанна", "отиоанна"]),
        ("Acts", ["деян", "деяния"]),
        ("Jas", ["иак", "иакова"]),
        ("1Pet", ["1пет", "1петра"]),
        ("2Pet", ["2пет", "2петра"]),
        ("1John", ["1ин", "1иоан", "1иоанна"]),
        ("2John", ["2ин", "2иоан"]),
        ("3John", ["3ин", "3иоан"]),
        ("Jude", ["иуд", "иуды"]),
        ("Rom", ["рим", "римлянам"]),
        ("1Cor", ["1кор"]),
        ("2Cor", ["2кор"]),
        ("Gal", ["гал"]),
        ("Eph", ["еф", "ефес"]),
        ("Phil", ["флп", "фил", "филип"]),
        ("Col", ["кол"]),
        ("1Thess", ["1фес", "1фесс"]),
        ("2Thess", ["2фес", "2фесс"]),
        ("1Tim", ["1тим"]),
        ("2Tim", ["2тим"]),
        ("Titus", ["тит"]),
        ("Phlm", ["флм", "филим"]),
        ("Heb", ["евр"]),
        ("Rev", ["откр", "апок", "откровение", "апокалипсис"]),
    ]
}

/// Названия книг и «Глава N» на языке интерфейса (как в веб-версии: books.js → localBook). Русский — названия из модуля
/// и справочника; украинский, белорусский, сербский и другие — Resources/book-names.json (собран
/// tool/book_names_helloao.py из открытого API helloao); языка нет в таблице — английские. Краткие названия: у кириллицы
/// — русские, у латиницы — английские сокращения, у остальных письменностей — полное название
enum BookLocale {
    /// Язык интерфейса; меняется в настройках (RootView следит)
    private(set) static var lang: String = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "ru"

    static func set(_ l: String) {
        if lang != l { lang = l }
    }

    private static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "book-names", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              var j = try? JSONDecoder().decode([String: [String: String]].self, from: d) else { return [:] }
        // украинский Ветхий Завет — современные названия (в источнике — правопис Куліша)
        j["uk", default: [:]].merge(ukOT) { _, new in new }
        return j
    }()

    private static let ukOT: [String: String] = [
        "Gen": "Буття", "Exod": "Вихід", "Lev": "Левит", "Num": "Числа", "Deut": "Повторення Закону", "Josh": "Ісус Навин",
        "Judg": "Суддів", "Ruth": "Рут", "1Sam": "1 Самуїлова", "2Sam": "2 Самуїлова", "1Kgs": "1 Царів", "2Kgs": "2 Царів",
        "1Chr": "1 Хронік", "2Chr": "2 Хронік", "Ezra": "Ездра", "Neh": "Неемія", "Esth": "Естер", "Job": "Йов",
        "Ps": "Псалми", "Prov": "Приповісті", "Eccl": "Екклезіяст", "Song": "Пісня над піснями", "Isa": "Ісая",
        "Jer": "Єремія", "Lam": "Плач Єремії", "Ezek": "Єзекіїль", "Dan": "Даниїл", "Hos": "Осія", "Joel": "Йоіл",
        "Amos": "Амос", "Obad": "Овдій", "Jonah": "Йона", "Mic": "Михей", "Nah": "Наум", "Hab": "Авакум",
        "Zeph": "Софонія", "Hag": "Огій", "Zech": "Захарія", "Mal": "Малахія",
    ]

    /// Кириллица: сокращения — русские
    private static let cyrillic: Set<String> = ["ru", "uk", "be", "bg", "sr"]
    /// Латиница: сокращения — английские
    private static let latin: Set<String> = ["en", "de", "fr", "es", "it", "pt", "pl", "cs", "ro", "id", "sw"]

    private static var cache: [String: String] = [:]
    private static var cacheLang = ""

    /// Полное название; lang — другой язык (место для отправки толкования — на языке толкования)
    static func name(_ id: String, _ raw: String, lang other: String? = nil) -> String {
        let l = other.map { String($0.lowercased().prefix { $0 != "-" && $0 != "_" }) } ?? lang
        if l == "ru" || l == "bg" || l == "cu" || l.isEmpty { return raw }
        if other != nil { return table[l == "el" ? "grc" : l]?[id] ?? table["en"]?[id] ?? BookNames.en[id]?.first ?? raw }
        if cacheLang != l { cache = [:]; cacheLang = l }
        if let c = cache[id] { return c }
        let n = table[l]?[id] ?? table["en"]?[id] ?? BookNames.en[id]?.first ?? raw
        cache[id] = n
        return n
    }

    static func short(_ id: String, _ raw: String) -> String {
        let l = lang
        if cyrillic.contains(l) { return raw }
        if latin.contains(l) { return BookNames.en[id]?.last ?? raw }
        return name(id, raw)
    }

    /// «Глава N» («Псалом N») на языке перевода (other) или интерфейса: языки приложения — из его перевода,
    /// остальные — из этой таблицы, нет и там — английские
    private static let chapterWords: [String: (String, String)] = [
        "grc": ("Κεφάλαιον %d", "Ψαλμός %d"), "el": ("Κεφάλαιο %d", "Ψαλμός %d"), "he": ("פרק %d", "מזמור %d"),
        "la": ("Caput %d", "Psalmus %d"), "hu": ("%d. fejezet", "%d. zsoltár"), "fi": ("Luku %d", "Psalmi %d"),
        "hr": ("Poglavlje %d", "Psalam %d"), "ar": ("الأصحاح %d", "المزمور %d"), "vi": ("Chương %d", "Thi Thiên %d"),
        "sq": ("Kapitulli %d", "Psalmi %d"), "da": ("Kapitel %d", "Salme %d"), "et": ("Peatükk %d", "Psalm %d"),
        "eo": ("Ĉapitro %d", "Psalmo %d"), "lv": ("%d. nodaļa", "%d. psalms"), "nb": ("Kapittel %d", "Salme %d"),
        "fa": ("فصل %d", "مزمور %d"), "sk": ("Kapitola %d", "Žalm %d"), "nl": ("Hoofdstuk %d", "Psalm %d"),
        "sv": ("Kapitel %d", "Psalm %d"), "tl": ("Kabanata %d", "Awit %d"), "tr": ("Bölüm %d", "Mezmur %d"),
    ]

    /// «Глава %d» и «Псалом %d» для языка — при установке перевода, у которого в источнике этих слов нет (helloao):
    /// из перевода самого приложения, иначе из таблицы; нет — английские; русский — nil (по умолчанию русские)
    static func chapterFormats(_ language: String) -> (String, String)? {
        let l = String(language.lowercased().prefix { $0 != "-" && $0 != "_" })
        if l == "ru" || l == "cu" || l.isEmpty { return nil }
        let folder = l == "zh" ? "zh-Hans" : l
        if let p = Bundle.main.path(forResource: folder, ofType: "lproj"), let b = Bundle(path: p) {
            let c = b.localizedString(forKey: "Глава %lld", value: nil, table: nil)
            let ps = b.localizedString(forKey: "Псалом %lld", value: nil, table: nil)
            if c != "Глава %lld", ps != "Псалом %lld" {
                return (c.replacingOccurrences(of: "%1$lld", with: "%d").replacingOccurrences(of: "%lld", with: "%d"),
                        ps.replacingOccurrences(of: "%1$lld", with: "%d").replacingOccurrences(of: "%lld", with: "%d"))
            }
        }
        return chapterWords[l] ?? ("Chapter %d", "Psalm %d")
    }

    /// Русские названия годятся только русским и церковнославянским переводам; остальным без своих названий — английские
    private static func russianModule(_ language: String) -> Bool {
        let l = String(language.lowercased().prefix { $0 != "-" && $0 != "_" })
        return l == "ru" || l == "cu" || l.isEmpty
    }

    /// Название книги над текстом, когда в самом модуле его нет: русским модулям — русское, остальным — английское
    static func fallbackName(_ id: String, raw: String, language: String) -> String {
        russianModule(language) ? raw : (BookNames.en[id]?.first ?? raw)
    }

    /// «Глава N» («Псалом N») над текстом: слово — из самого модуля; нет его — русское (русским модулям) или английское
    static func chapterTitle(book: String, chapter: Int, module m: InstalledModule) -> String {
        let psalm = book == "Ps"
        let fmt = psalm ? m.psalmWord : m.chapterWord
        if !fmt.isEmpty { return fmt.replacingOccurrences(of: "%d", with: "\(chapter)") } // слово из чужого модуля: не String(format:), там %@ роняет
        if russianModule(m.language) { return psalm ? "Псалом \(chapter)" : "Глава \(chapter)" }
        return psalm ? "Psalm \(chapter)" : "Chapter \(chapter)"
    }
}
