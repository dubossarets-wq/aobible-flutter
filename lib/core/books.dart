// Справочник книг: OSIS-коды, русские названия (assets/books.json) и английские — для интерфейса не на кириллице.
// Разбор ссылок «Ин 3:16», «1 Кор 13:4-7», «John 3:16».
import 'dart:convert';

import 'package:flutter/services.dart';

class BookInfo {
  const BookInfo(this.id, this.name, this.short, this.testament, this.order, {this.dc = false});
  final String id;
  final String name;
  final String short;
  final String testament; // OT, NT, AP
  final int order;
  final bool dc; // неканоническая книга (в планах «Вся Библия» и «Ветхий Завет» её нет)
}

const _en = <String, List<String>>{
  'Gen': ['Genesis', 'Gen'], 'Exod': ['Exodus', 'Exod'], 'Lev': ['Leviticus', 'Lev'], 'Num': ['Numbers', 'Num'],
  'Deut': ['Deuteronomy', 'Deut'], 'Josh': ['Joshua', 'Josh'], 'Judg': ['Judges', 'Judg'], 'Ruth': ['Ruth', 'Ruth'],
  '1Sam': ['1 Samuel', '1 Sam'], '2Sam': ['2 Samuel', '2 Sam'], '1Kgs': ['1 Kings', '1 Kgs'], '2Kgs': ['2 Kings', '2 Kgs'],
  '1Chr': ['1 Chronicles', '1 Chr'], '2Chr': ['2 Chronicles', '2 Chr'], 'PrMan': ['Prayer of Manasseh', 'Pr Man'],
  'Ezra': ['Ezra', 'Ezra'], 'Neh': ['Nehemiah', 'Neh'], '1Esd': ['1 Esdras', '1 Esd'], 'Tob': ['Tobit', 'Tob'],
  'Jdt': ['Judith', 'Jdt'], 'Esth': ['Esther', 'Esth'], 'Job': ['Job', 'Job'], 'Ps': ['Psalms', 'Ps'],
  'Prov': ['Proverbs', 'Prov'], 'Eccl': ['Ecclesiastes', 'Eccl'], 'Song': ['Song of Songs', 'Song'],
  'Wis': ['Wisdom of Solomon', 'Wis'], 'Sir': ['Sirach', 'Sir'], 'Isa': ['Isaiah', 'Isa'], 'Jer': ['Jeremiah', 'Jer'],
  'Lam': ['Lamentations', 'Lam'], 'EpJer': ['Letter of Jeremiah', 'Ep Jer'], 'Bar': ['Baruch', 'Bar'],
  'Ezek': ['Ezekiel', 'Ezek'], 'Dan': ['Daniel', 'Dan'], 'Hos': ['Hosea', 'Hos'], 'Joel': ['Joel', 'Joel'],
  'Amos': ['Amos', 'Amos'], 'Obad': ['Obadiah', 'Obad'], 'Jonah': ['Jonah', 'Jonah'], 'Mic': ['Micah', 'Mic'],
  'Nah': ['Nahum', 'Nah'], 'Hab': ['Habakkuk', 'Hab'], 'Zeph': ['Zephaniah', 'Zeph'], 'Hag': ['Haggai', 'Hag'],
  'Zech': ['Zechariah', 'Zech'], 'Mal': ['Malachi', 'Mal'], '1Macc': ['1 Maccabees', '1 Macc'],
  '2Macc': ['2 Maccabees', '2 Macc'], '3Macc': ['3 Maccabees', '3 Macc'], '2Esd': ['2 Esdras', '2 Esd'],
  'Matt': ['Matthew', 'Matt'], 'Mark': ['Mark', 'Mark'], 'Luke': ['Luke', 'Luke'], 'John': ['John', 'John'],
  'Acts': ['Acts', 'Acts'], 'Jas': ['James', 'Jas'], '1Pet': ['1 Peter', '1 Pet'], '2Pet': ['2 Peter', '2 Pet'],
  '1John': ['1 John', '1 John'], '2John': ['2 John', '2 John'], '3John': ['3 John', '3 John'], 'Jude': ['Jude', 'Jude'],
  'Rom': ['Romans', 'Rom'], '1Cor': ['1 Corinthians', '1 Cor'], '2Cor': ['2 Corinthians', '2 Cor'],
  'Gal': ['Galatians', 'Gal'], 'Eph': ['Ephesians', 'Eph'], 'Phil': ['Philippians', 'Phil'], 'Col': ['Colossians', 'Col'],
  '1Thess': ['1 Thessalonians', '1 Thess'], '2Thess': ['2 Thessalonians', '2 Thess'], '1Tim': ['1 Timothy', '1 Tim'],
  '2Tim': ['2 Timothy', '2 Tim'], 'Titus': ['Titus', 'Titus'], 'Phlm': ['Philemon', 'Phlm'], 'Heb': ['Hebrews', 'Heb'],
  'Rev': ['Revelation', 'Rev'],
  'Ps151': ['Psalm 151', 'Ps 151'],
  'PrAzar': ['Prayer of Azariah', 'Pr Azar'],
  'Sus': ['Susanna', 'Sus'],
  'Bel': ['Bel and the Dragon', 'Bel'],
  '1En': ['1 Enoch', '1 En'],
  'Jub': ['Jubilees', 'Jub'],
  'TReu': ['Testament of Reuben', 'T. Reu.'],
  'TSim': ['Testament of Simeon', 'T. Sim.'],
  'TLevi': ['Testament of Levi', 'T. Levi'],
  'TJud': ['Testament of Judah', 'T. Jud.'],
  'TIss': ['Testament of Issachar', 'T. Iss.'],
  'TZeb': ['Testament of Zebulun', 'T. Zeb.'],
  'TDan': ['Testament of Dan', 'T. Dan'],
  'TNaph': ['Testament of Naphtali', 'T. Naph.'],
  'TGad': ['Testament of Gad', 'T. Gad'],
  'TAsh': ['Testament of Asher', 'T. Ash.'],
  'TJos': ['Testament of Joseph', 'T. Jos.'],
  'TBenj': ['Testament of Benjamin', 'T. Benj.'],
};

// Сокращения для ввода ссылок (как в веб-версии: src/core/books.js)
const _extraAliases = <String, List<String>>{
  'Gen': ['бт', 'бытия'], 'Exod': ['исход'], 'Num': ['чисел', 'числ'], 'Deut': ['вт', 'второзак'],
  'Josh': ['иисуснавин', 'навин', 'ииснав'], 'Judg': ['судей'], '1Sam': ['1царств', '1цар', '1sam'],
  '2Sam': ['2царств', '2цар'], '1Kgs': ['3царств', '3цар'], '2Kgs': ['4царств', '4цар'],
  '1Chr': ['1пар', '1паралипоменон'], '2Chr': ['2пар', '2паралипоменон'], 'Ezra': ['ездр', 'ездры'],
  'Neh': ['неемии'], 'Esth': ['есфири'], 'Ps': ['псалом', 'псалмы', 'псалтирь', 'пс'], 'Prov': ['притч', 'пр'],
  'Eccl': ['екл', 'еккл', 'екклесиаста'], 'Song': ['песн', 'песнь', 'песньпесней'], 'Isa': ['исаии', 'исаия'],
  'Jer': ['иеремии'], 'Lam': ['плачиеремии'], 'Ezek': ['иезекииля', 'иез'], 'Dan': ['даниила'],
  'Hos': ['осии'], 'Joel': ['иоиля'], 'Jonah': ['ионы'], 'Mic': ['михея'], 'Hab': ['аввакума'], 'Zeph': ['софонии'],
  'Hag': ['аггея'], 'Zech': ['захарии'], 'Mal': ['малахии'],
  'Matt': ['мф', 'мтф', 'матф', 'матфея', 'отматфея', 'мт'], 'Mark': ['мк', 'мар', 'марк', 'марка', 'отмарка'],
  'Luke': ['лк', 'лук', 'луки', 'отлуки'], 'John': ['ин', 'иоан', 'иоанна', 'отиоанна'],
  'Acts': ['деян', 'деяния'], 'Jas': ['иак', 'иакова'], '1Pet': ['1пет', '1петра'], '2Pet': ['2пет', '2петра'],
  '1John': ['1ин', '1иоан', '1иоанна'], '2John': ['2ин', '2иоан'], '3John': ['3ин', '3иоан'],
  'Jude': ['иуд', 'иуды'], 'Rom': ['рим', 'римлянам'], '1Cor': ['1кор'], '2Cor': ['2кор'], 'Gal': ['гал'],
  'Eph': ['еф', 'ефес'], 'Phil': ['флп', 'фил', 'филип'], 'Col': ['кол'], '1Thess': ['1фес', '1фесс'],
  '2Thess': ['2фес', '2фесс'], '1Tim': ['1тим'], '2Tim': ['2тим'], 'Titus': ['тит'], 'Phlm': ['флм', 'филим'],
  'Heb': ['евр'], 'Rev': ['откр', 'апок', 'откровение', 'апокалипсис'],
};

const _cyrillicUi = {'ru', 'uk', 'be', 'bg', 'sr'};

class Books {
  Books._(this._ru);
  final Map<String, BookInfo> _ru;
  final Map<String, String> _aliases = {};
  String lang = 'ru';

  static late Books instance;

  static Future<Books> load() async {
    final list = jsonDecode(await rootBundle.loadString('assets/books.json')) as List;
    final map = <String, BookInfo>{};
    for (var i = 0; i < list.length; i++) {
      final b = list[i] as Map<String, dynamic>;
      map[b['id'] as String] = BookInfo(b['id'] as String, b['name'] as String, b['short'] as String, b['t'] as String, i, dc: b['dc'] == true);
    }
    final books = Books._(map);
    void add(String key, String id) => books._aliases[_norm(key)] = id;
    for (final b in map.values) {
      add(b.id, b.id);
      add(b.name, b.id);
      add(b.short, b.id);
      for (final n in _en[b.id] ?? const <String>[]) {
        add(n, b.id);
      }
    }
    _extraAliases.forEach((id, keys) => keys.forEach((k) => add(k, id)));
    books._generated();
    return instance = books;
  }

  
  /// Сокращения, которых нет в списках: начала названия от двух букв («фе», «фес», «фесс»), сокращения по согласным
  /// («фс», «флп», «тм», «кр»), номер книги в любом виде («1фс», «1-е фес»); без номера — первая книга («фс» → 1 Фес).
  /// Готовые сокращения и названия не перезаписываются; при совпадении побеждает книга, что раньше в Библии.
  void _generated() {
    // неканонические книги — после канонических: короткое сокращение достаётся канонической книге
    final books = [
      ..._ru.values.where((b) => !b.dc),
      ..._ru.values.where((b) => b.dc),
    ];
    void put(String key, String id) {
      if (key.length >= 2) _aliases.putIfAbsent(key, () => id);
    }

    final forms = <(String, String?, List<String>, List<String>)>[]; // id, номер, начала, согласные
    for (final b in books) {
      final m = RegExp(r'^([1-4])(?:-?[а-яё]{1,2})?\s*(.*)$').firstMatch(b.name.toLowerCase());
      final n = m?.group(1);
      var base = (m?.group(2) ?? b.name.toLowerCase()).replaceAll('ё', 'е');
      final bases = <String>{base.replaceAll(RegExp(r'[\s.-]'), '')};
      if (base.startsWith('от ')) bases.add(base.substring(3).replaceAll(RegExp(r'[\s.-]'), '')); // «От Матфея» → «матфея»
      final starts = <String>[], skel = <String>[];
      for (final x in bases) {
        for (var k = 2; k <= x.length; k++) {
          starts.add(x.substring(0, k));
        }
        // сокращение по согласным: первая буква + согласные дальше («фессалоникийцам» → «фсслнкцм»)
        final cons = x[0] + x.substring(1).replaceAll(RegExp(r'[аеиоуыэюяйъь]'), '');
        for (var k = 2; k <= cons.length; k++) {
          skel.add(cons.substring(0, k));
        }
      }
      forms.add((b.id, n, starts, skel));
    }
    // сначала начала названий всех книг, потом сокращения по согласным — «пр» скорее «Притчи», чем что-то по согласным
    for (final pass in [0, 1]) {
      for (final (id, n, starts, skel) in forms) {
        for (final f in pass == 0 ? starts : skel) {
          if (n != null) {
            put('$n$f', id);
            if (n == '1') put(f, id);
          } else {
            put(f, id);
          }
        }
      }
    }
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s.]'), '').replaceAll('ё', 'е');

  bool get latinNames => !_cyrillicUi.contains(lang);

  /// Книга с названиями на языке интерфейса; неизвестная — по названиям из модуля
  BookInfo meta(String id, {String? name, String? short}) {
    final b = _ru[id];
    if (b == null) return BookInfo(id, name ?? id, short ?? id, 'AP', 1000);
    final en = latinNames ? _en[id] : null;
    return en == null ? b : BookInfo(id, en[0], en[1], b.testament, b.order, dc: b.dc);
  }

  int order(String id) => _ru[id]?.order ?? 1000;
  Iterable<BookInfo> get all => _ru.values;

  String formatRef(String book, int chapter, int verse, {bool full = false}) {
    final m = meta(book);
    return '${full ? m.name : m.short} $chapter:$verse';
  }

  String? findBookId(String text) {
    final key = _norm(text);
    final hit = _aliases[key];
    if (hit != null) return hit;
    if (key.length < 3) return null;
    for (final e in _aliases.entries) {
      if (e.key.startsWith(key)) return e.value;
    }
    return null;
  }

  static final _refRe = RegExp(r'^((?:[1-4]\s*)?[^\d\s:.,][^\d:,]*?)\.?\s*(\d+)(?:(?:\s*[:.,]\s*|\s+)(\d+)(?:\s*[-–]\s*(\d+))?)?\s*$');

  /// «Ин 3:16», «1 Кор 13:4-7», «Пс 22» → ссылка или null
  VerseRef? parseHuman(String input) {
    final m = _refRe.firstMatch(input.trim());
    if (m == null) return null;
    final book = findBookId(m.group(1)!);
    if (book == null) return null;
    return VerseRef(book, int.parse(m.group(2)!), m.group(3) != null ? int.parse(m.group(3)!) : 1);
  }
}

class VerseRef {
  const VerseRef(this.book, this.chapter, this.verse);
  final String book;
  final int chapter;
  final int verse;

  Map<String, dynamic> toJson() => {'book': book, 'chapter': chapter, 'verse': verse};
  static VerseRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final b = j['book'], c = j['chapter'], v = j['verse'];
    if (b is! String || c is! int || v is! int) return null;
    return VerseRef(b, c, v);
  }

  @override
  bool operator ==(Object other) => other is VerseRef && other.book == book && other.chapter == chapter && other.verse == verse;
  @override
  int get hashCode => Object.hash(book, chapter, verse);
  @override
  String toString() => '$book.$chapter.$verse';
}
