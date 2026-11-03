// Переводы Free Use Bible API (bible.helloao.org): скачиваются целиком (complete.json) прямо с их сайта
// и перекладываются в формат модуля приложения — дальше работают без сети, как любой скачанный перевод.
// То же в веб-версии — src/core/helloao.js.
/// USFM-код книги → OSIS-код приложения (scripts/usfm.mjs в веб-версии)
const usfmToOsis = <String, String>{
  'GEN': 'Gen', 'EXO': 'Exod', 'LEV': 'Lev', 'NUM': 'Num', 'DEU': 'Deut', 'JOS': 'Josh', 'JDG': 'Judg', 'RUT': 'Ruth', '1SA': '1Sam', '2SA': '2Sam',
  '1KI': '1Kgs', '2KI': '2Kgs', '1CH': '1Chr', '2CH': '2Chr', 'EZR': 'Ezra', 'NEH': 'Neh', 'EST': 'Esth', 'JOB': 'Job', 'PSA': 'Ps', 'PRO': 'Prov',
  'ECC': 'Eccl', 'SNG': 'Song', 'ISA': 'Isa', 'JER': 'Jer', 'LAM': 'Lam', 'EZK': 'Ezek', 'DAN': 'Dan', 'HOS': 'Hos', 'JOL': 'Joel', 'AMO': 'Amos',
  'OBA': 'Obad', 'JON': 'Jonah', 'MIC': 'Mic', 'NAM': 'Nah', 'HAB': 'Hab', 'ZEP': 'Zeph', 'HAG': 'Hag', 'ZEC': 'Zech', 'MAL': 'Mal',
  'MAT': 'Matt', 'MRK': 'Mark', 'LUK': 'Luke', 'JHN': 'John', 'ACT': 'Acts', 'ROM': 'Rom', '1CO': '1Cor', '2CO': '2Cor', 'GAL': 'Gal', 'EPH': 'Eph',
  'PHP': 'Phil', 'COL': 'Col', '1TH': '1Thess', '2TH': '2Thess', '1TI': '1Tim', '2TI': '2Tim', 'TIT': 'Titus', 'PHM': 'Phlm', 'HEB': 'Heb',
  'JAS': 'Jas', '1PE': '1Pet', '2PE': '2Pet', '1JN': '1John', '2JN': '2John', '3JN': '3John', 'JUD': 'Jude', 'REV': 'Rev',
  'TOB': 'Tob', 'JDT': 'Jdt', 'ESG': 'AddEsth', 'WIS': 'Wis', 'SIR': 'Sir', 'BAR': 'Bar', 'LJE': 'EpJer', 'S3Y': 'PrAzar', 'SUS': 'Sus', 'BEL': 'Bel',
  '1MA': '1Macc', '2MA': '2Macc', '3MA': '3Macc', '4MA': '4Macc', '1ES': '1Esd', '2ES': '2Esd', 'MAN': 'PrMan', 'PS2': 'Ps151',
};

final _braces = RegExp(r'[{}]');
final _spaces = RegExp(r'\s+');

// Содержимое стиха: строки и {text}; сноски ({noteId}) и разрывы строк пропускаем
String _text(Object? items) => [
      for (final x in (items as List?) ?? const [])
        if (x is String)
          x
        else if (x is Map && x['text'] is String)
          x['text'] as String,
    ].join(' ').replaceAll(_braces, '').replaceAll(_spaces, ' ').trim();

const _head = {'heading', 'hebrew_subtitle'};

/// complete.json → модуль в формате aob-module (дальше — обычная установка в SQLite).
/// names — названия книг {OSIS: [название, сокращение]}: считается в основном потоке (Books там, а не здесь)
Map<String, dynamic> fromHelloao(Map<String, dynamic> json, Map<String, dynamic> entry, Map<String, List<String>> names) {
  final books = <Map<String, dynamic>>[];
  for (final b in (json['books'] as List? ?? const []).whereType<Map>()) {
    final id = usfmToOsis[b['id']];
    if (id == null) continue;
    final chapters = <List<String>>[];
    final headings = <String, String>{};
    for (final ch in (b['chapters'] as List? ?? const []).whereType<Map>()) {
      final c = ch['chapter'] as Map?;
      final n = c?['number'];
      if (n is! int || n < 1) continue;
      final verses = <String>[];
      final head = <String>[];
      for (final it in (c!['content'] as List? ?? const []).whereType<Map>()) {
        if (_head.contains(it['type'])) {
          final s = _text(it['content']);
          if (s.isNotEmpty) head.add(s);
        } else if (it['type'] == 'verse' && it['number'] is int && (it['number'] as int) > 0) {
          final v = it['number'] as int;
          if (head.isNotEmpty) {
            headings['$n:$v'] = head.join(' ');
            head.clear();
          }
          while (verses.length < v) {
            verses.add('');
          }
          final s = _text(it['content']);
          verses[v - 1] = verses[v - 1].isEmpty ? s : '${verses[v - 1]} $s';
        }
      }
      while (chapters.length < n) {
        chapters.add(<String>[]);
      }
      chapters[n - 1] = verses;
    }
    if (chapters.isEmpty) continue;
    final n = names[id] ?? [id, id];
    books.add({'id': id, 'name': n[0], 'short': n[1], 'chapters': chapters, 'headings': headings});
  }
  return {
    'format': 'aob-module',
    'type': 'bible',
    'id': entry['id'],
    'name': entry['name'],
    'title': entry['title'],
    'description': entry['description'] ?? '',
    'language': entry['language'],
    'license': entry['license'],
    'source': entry['source'],
    'versification': 'kjv',
    'books': books,
  };
}
