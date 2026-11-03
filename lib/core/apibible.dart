// Переводы API.Bible: не скачиваются, а читаются по сети через наш посредник (aobible.app/bapi, ключ — на сервере).
// «Добавить» создаёт модуль без текста (список книг); главы приходят по одной, когда их открывают, и хранятся
// в базе перевода недолго — по условиям API.Bible не больше 500 стихов подряд и не дольше 14 дней.
// Учёт показов (FUMS) нужен только сайту — у приложения для телефона его нет. То же в вебе — src/core/apibible.js.
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'bible.dart' show forgetBook;
import 'helloao.dart' show usfmToOsis;
import 'modules.dart';
import 'net.dart';
import 'versification.dart';

const _bases = ['https://aobible.app/bapi', 'https://aobible-apibible.apibible.workers.dev'];
const _keepVerses = 480;
const _keepDays = 14;

final _osisToUsfm = {for (final e in usfmToOsis.entries) e.value: e.key};

bool isOnline(String moduleId) => ModuleStore.instance.get(moduleId)?.meta['online'] is Map;

class OnlineError implements Exception {
  OnlineError(this.kind);
  final String kind; // 'limit' — исчерпан месячный лимит API.Bible; 'net' — нет связи
  @override
  String toString() => kind;
}

/// Строка каталога + книги (modules/api/ID.json) → модуль в формате aob-module без текста
Map<String, dynamic> onlineModule(Map<String, dynamic> entry, Map<String, dynamic> books, Map<String, List<String>> names) => {
      'format': 'aob-module',
      'type': 'bible',
      'id': entry['id'],
      'name': entry['name'],
      'title': entry['title'],
      'description': entry['description'] ?? '',
      'language': entry['language'],
      'license': entry['license'],
      'source': entry['source'],
      'versification': 'synodal',
      'online': entry['online'],
      'books': [
        for (final e in ((books['books'] as Map?) ?? const {}).entries)
          {'id': e.key, 'name': names[e.key]?[0] ?? e.key, 'short': names[e.key]?[1] ?? e.key, 'chapters': List.generate(e.value as int, (_) => <String>[])},
      ]..sort((a, b) => _order(a['id'] as String).compareTo(_order(b['id'] as String))),
    };

int _order(String osis) {
  final i = usfmToOsis.values.toList().indexOf(osis);
  return i < 0 ? 999 : i;
}

/// Есть ли глава в базе перевода
bool hasChapter(String moduleId, String book, int c) =>
    ModuleStore.instance.db(moduleId).select('SELECT 1 FROM verses WHERE book = ? AND chapter = ? LIMIT 1', [book, c]).isNotEmpty;

/// Авторские права перевода (приходят с главой)
String onlineCopyright(String moduleId) {
  try {
    final r = ModuleStore.instance.db(moduleId).select("SELECT value FROM meta WHERE key = 'copyright'");
    return r.isEmpty ? '' : r.first['value'] as String;
  } catch (_) {
    return '';
  }
}

final _loading = <String, Future<void>>{};

/// Загрузить главу (если её ещё нет) и записать в базу перевода
Future<void> loadChapter(String moduleId, String book, int c) {
  final key = '$moduleId|$book|$c';
  // обработчик — без возврата значения: remove вернул бы то же обещание, и whenComplete ждал бы сам себя
  return _loading[key] ??= _load(moduleId, book, c).whenComplete(() {
    _loading.remove(key);
  });
}

Future<void> _load(String moduleId, String book, int c) async {
  if (hasChapter(moduleId, book, c)) return;
  final m = ModuleStore.instance.get(moduleId);
  final api = (m?.meta['online'] as Map?)?['api'];
  final code = _osisToUsfm[book];
  if (api == null || code == null) throw OnlineError('net');
  // глава в синодальной нумерации — из одной или двух глав API (в нём западная нумерация, versification.dart)
  final v = <String>[];
  final h = <int, String>{};
  var copyright = '';
  for (final kc in westernChaptersFor(book, c)) {
    final data = await _fetch(api as String, code, kc);
    final (kv, kh, title) = parseChapter(data['content'] as List? ?? const []);
    placeSynodal(book, kc, kv, kh, c, v, h, title);
    if (copyright.isEmpty) copyright = data['copyright'] as String? ?? '';
  }
  _store(m!.path, book, c, v, h, copyright);
  forgetBook(moduleId, book);
}

Future<Map<String, dynamic>> _fetch(String api, String code, int c) async {
  const q = 'content-type=json&include-notes=false&include-titles=true&include-chapter-numbers=false&include-verse-numbers=true&include-verse-spans=false';
  Map<String, dynamic>? j;
  final client = await newHttpClient();
  for (final base in _bases) {
    try {
      final req = await client.getUrl(Uri.parse('$base/bibles/$api/chapters/$code.$c?$q'));
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      if (res.statusCode == 429 || res.statusCode == 403) throw OnlineError('limit');
      if (res.statusCode != 200) throw OnlineError('net');
      j = jsonDecode(body) as Map<String, dynamic>;
      break;
    } on OnlineError {
      client.close();
      rethrow; // сервер ответил — второй адрес не поможет
    } catch (_) {
      // нет связи с этим адресом — следующий
    }
  }
  client.close();
  if (j == null) throw OnlineError('net');
  return j['data'] as Map<String, dynamic>;
}

// Запись главы; старые главы уходят, пока в базе больше _keepVerses стихов или они старше _keepDays дней
void _store(String path, String book, int c, List<String> verses, Map<int, String> heads, String copyright) {
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE IF NOT EXISTS online(book TEXT, chapter INTEGER, at INTEGER, n INTEGER, PRIMARY KEY(book, chapter))');
    db.execute('BEGIN');
    var id = (db.select('SELECT MAX(id) AS m FROM verses').first['m'] as int?) ?? 0;
    for (var v = 0; v < verses.length; v++) {
      if (verses[v].isEmpty) continue;
      db.execute('INSERT INTO verses VALUES (?, ?, ?, ?, ?)', [++id, book, c, v + 1, verses[v]]);
    }
    for (final e in heads.entries) {
      db.execute('INSERT INTO headings VALUES (?, ?, ?, ?)', [book, c, e.key, e.value]);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('INSERT OR REPLACE INTO online VALUES (?, ?, ?, ?)', [book, c, now, verses.length]);
    if (copyright.isNotEmpty) db.execute("INSERT OR REPLACE INTO meta VALUES ('copyright', ?)", [copyright]);
    var total = 0;
    for (final r in db.select('SELECT book, chapter, at, n FROM online ORDER BY at DESC')) {
      total += r['n'] as int;
      final old = now - (r['at'] as int) > _keepDays * 86400000;
      final fresh = r['book'] == book && r['chapter'] == c;
      if (!fresh && (total > _keepVerses || old)) {
        db.execute('DELETE FROM verses WHERE book = ? AND chapter = ?', [r['book'], r['chapter']]);
        db.execute('DELETE FROM headings WHERE book = ? AND chapter = ?', [r['book'], r['chapter']]);
        db.execute('DELETE FROM online WHERE book = ? AND chapter = ?', [r['book'], r['chapter']]);
      }
    }
    db.execute('COMMIT');
  } finally {
    db.close();
  }
}

// --- Разбор главы (JSON API.Bible) → стихи с разметкой приложения ---------------------------

final _head = RegExp(r'^(s\d?|ms\d?|mr|sr|d|sp|qa|r)$');
const _added = {'add', 'it'}; // слова, добавленные переводчиками (курсив) → ‹…›
final _spaces = RegExp(r'\s+');

(List<String>, Map<int, String>, String) parseChapter(List content) {
  final v = <String>[];
  final h = <int, String>{};
  var head = <String>[];
  var title = ''; // надписание псалма (стиль d до первого стиха)
  String text(Map n) => n['type'] == 'text' ? '${n['text']}' : [for (final x in (n['items'] as List? ?? const []).whereType<Map>()) text(x)].join();
  void walk(Map n, bool added) {
    if (n['type'] == 'text') {
      final id = (n['attrs'] as Map?)?['verseId'] as String?;
      final num = id == null ? 0 : int.tryParse(id.split('.').last) ?? 0;
      if (num < 1) return;
      while (v.length < num) {
        v.add('');
      }
      final s = '${n['text']}'.replaceAll(RegExp(r'[{}]'), '');
      v[num - 1] += added ? '‹$s›' : s;
      return;
    }
    if (n['name'] == 'verse') {
      final num = int.tryParse('${(n['attrs'] as Map?)?['number']}'.split('-').first) ?? 0;
      if (num > 0 && head.isNotEmpty) {
        h[num] = head.join(' ');
        head = [];
      }
      return;
    }
    if (n['name'] == 'note') return;
    final style = '${(n['attrs'] as Map?)?['style'] ?? ''}';
    if (n['name'] == 'para' && _head.hasMatch(style)) {
      final s = text(n).trim();
      if (s.isNotEmpty && style == 'd' && v.isEmpty) {
        title = s;
      } else if (s.isNotEmpty) {
        head.add(s);
      }
      return;
    }
    for (final x in (n['items'] as List? ?? const []).whereType<Map>()) {
      walk(x, added || (n['name'] == 'char' && _added.contains(style)));
    }
  }

  for (final n in content.whereType<Map>()) {
    walk(n, false);
  }
  for (var i = 0; i < v.length; i++) {
    v[i] = v[i].replaceAll(_spaces, ' ').replaceAll(RegExp(r'›\s*‹'), ' ').trim();
  }
  return (v, h, title);
}
