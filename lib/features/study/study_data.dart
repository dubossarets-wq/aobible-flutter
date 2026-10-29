// Данные «изучения»: словари, комментарии, параллельные места, иллюстрации, тексты стихов, статистика слов.
// Всё — запросы к SQLite (таблицы строятся при установке, см. study_tables.dart); для модулей, установленных
// до этой версии, таблицы строятся один раз при первом обращении (в отдельном потоке).
import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import 'study_tables.dart';

/// Ссылка OSIS с возможным концом диапазона: «Gen.1.1», «Gen.1.1-3», «Gen.1.1-2.3»
class OsisRef {
  OsisRef(this.book, this.chapter, this.verse, [this.end]);
  final String book;
  final int chapter;
  final int verse;
  final VerseRef? end;
  VerseRef get start => VerseRef(book, chapter, verse);
}

OsisRef? parseOsisRef(String ref) {
  final parts = ref.split('-');
  final pa = parts.first.split('.');
  if (pa.length < 2) return null;
  final c = int.tryParse(pa[1]);
  final v = pa.length > 2 ? int.tryParse(pa[2]) : 1;
  if (c == null || v == null) return null;
  final book = pa[0];
  VerseRef? end;
  if (parts.length > 1 && parts[1].isNotEmpty) {
    final pb = parts[1].split('.');
    if (pb.length == 1) {
      end = VerseRef(book, c, int.tryParse(pb[0]) ?? v);
    } else if (pb.length == 2) {
      end = VerseRef(book, int.tryParse(pb[0]) ?? c, int.tryParse(pb[1]) ?? v);
    } else {
      end = VerseRef(pb[0], int.tryParse(pb[1]) ?? c, int.tryParse(pb[2]) ?? v);
    }
  }
  return OsisRef(book, c, v, end);
}

/// «Ин. 3:16», «Быт. 1:1–3», полное название книги — при full
String fmtRef(VerseRef r, {bool full = false, VerseRef? end}) {
  final m = Books.instance.meta(r.book);
  var s = '${full ? m.name : m.short} ${r.chapter}:${r.verse}';
  if (end != null) {
    if (end.chapter != r.chapter) {
      s += '–${end.chapter}:${end.verse}';
    } else if (end.verse != r.verse) {
      s += '–${end.verse}';
    }
  }
  return s;
}

String fmtOsis(OsisRef r, {bool full = false}) => fmtRef(r.start, full: full, end: r.end);

bool isNt(String book) => Books.instance.meta(book).testament == 'NT';

class StudyData {
  static ModuleStore get _store => ModuleStore.instance;

  // --- Миграция старых установок -------------------------------------------------------------

  static final _checked = <String>{};
  static Future<void>? _ensuring;

  /// Гарантирует, что у всех словарей, комментариев, параллельных мест и иллюстраций есть таблицы
  /// (модули, установленные до этой версии, хранили только JSON). Обычно — мгновенно.
  static Future<void> ensure() {
    final pending = _store.installed.where((m) => studyTypes.contains(m.type) && !_checked.contains(m.id)).toList();
    if (pending.isEmpty) return Future.value();
    return _ensuring ??= _run(pending).whenComplete(() => _ensuring = null);
  }

  static Future<void> _run(List<InstalledModule> list) async {
    for (final m in list) {
      try {
        if (!hasStudyTables(_store.db(m.id))) {
          final path = m.path;
          await Isolate.run(() => _migrate(path));
        }
      } catch (_) {
        // не вышло — пробуем при следующем обращении
        continue;
      }
      _checked.add(m.id);
    }
    _clearCaches();
  }

  static void _migrate(String path) {
    final db = sqlite3.open(path);
    try {
      final row = db.select('SELECT json FROM payload');
      if (row.isEmpty) return;
      final j = jsonDecode(row.first['json'] as String) as Map<String, dynamic>;
      db.execute('BEGIN');
      buildStudyTables(db, j, j['type'] as String? ?? 'dictionary');
      db.execute('COMMIT');
    } finally {
      db.close();
    }
  }

  // --- Модули и подписи кэшей ----------------------------------------------------------------

  static String _sig = '';
  static int _sigAt = 0;
  static final _bookCache = <String, Object>{};

  static void _clearCaches() {
    _bookCache.clear();
    _statsCache.clear();
    _hasWindex.clear();
  }

  /// Сменился набор модулей — кэши стихов и книг сбрасываются (проверка не чаще раза в две секунды)
  static void _touch() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _sigAt < 2000) return;
    _sigAt = now;
    final s = (_store.installed.where((m) => m.type != 'bible').map((m) => '${m.id}:${m.meta['catalogVersion']}').toList()..sort()).join(',');
    if (s != _sig) {
      _sig = s;
      _clearCaches();
    }
  }

  static List<InstalledModule> _ofType(String type) {
    final l = _store.installed.where((m) => m.type == type && studyReady(m)).toList();
    int ru(InstalledModule m) => m.language == 'ru' ? 0 : 1;
    l.sort((a, b) => ru(a) != ru(b) ? ru(a) - ru(b) : a.id.compareTo(b.id));
    return l;
  }

  /// Таблицы модуля готовы (или ещё строятся — тогда модуль пока пропускаем)
  static bool studyReady(InstalledModule m) {
    if (_checked.contains(m.id)) return true;
    try {
      if (hasStudyTables(_store.db(m.id))) {
        _checked.add(m.id);
        return true;
      }
    } catch (_) {
      // файл заменяется — считаем неготовым
    }
    return false;
  }

  static List<InstalledModule> commentaries() => _ofType('commentary');
  static List<InstalledModule> crossrefModules() => _ofType('crossrefs');
  static List<InstalledModule> illustrationModules() => _ofType('illustrations');

  static String dictKind(InstalledModule m) => m.meta['dictionaryKind'] as String? ?? 'words';

  /// Словари: русский Стронг первым (он открывается по умолчанию), затем другие русские, затем остальные
  static List<InstalledModule> dictionaries({bool strongsOnly = false}) {
    int rank(InstalledModule m) => dictKind(m) == 'strongs' && m.language == 'ru' && m.id != 'rst-symphony' ? 0 : m.language == 'ru' ? 1 : 2;
    final l = _ofType('dictionary').where((m) => !strongsOnly || dictKind(m) == 'strongs').toList();
    final idx = {for (var i = 0; i < l.length; i++) l[i].id: i};
    l.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : idx[a.id]! - idx[b.id]!);
    return l;
  }

  static bool isInstalled(String id) => _store.get(id) != null;

  // --- Словари -------------------------------------------------------------------------------

  static Map<String, dynamic>? dictGet(String id, String key) {
    if (_store.get(id) == null) return null; // словаря нет на устройстве — статьи нет (а не ошибка)
    final r = _store.db(id).select('SELECT json FROM dict WHERE key = ?', [key]);
    return r.isEmpty ? null : (jsonDecode(r.first['json'] as String) as Map).cast<String, dynamic>();
  }

  /// Те ключи из списка, что есть в словаре (в порядке списка)
  static List<(String, Map<String, dynamic>)> dictGetMany(String id, List<String> keys) {
    if (keys.isEmpty || _store.get(id) == null) return const [];
    final r = _store.db(id).select('SELECT key, json FROM dict WHERE key IN (${List.filled(keys.length, '?').join(',')})', keys);
    final found = {for (final row in r) row['key'] as String: row['json'] as String};
    return [
      for (final k in keys)
        if (found[k] != null) (k, (jsonDecode(found[k]!) as Map).cast<String, dynamic>()),
    ];
  }

  /// Ключи, начинающиеся с основы слова (по возрастанию, не больше limit)
  static List<String> dictPrefix(String id, String prefix, int limit) {
    final r = _store.db(id).select('SELECT key FROM dict WHERE key >= ? AND key < ? ORDER BY key LIMIT ?', [prefix, '$prefix￿', limit]);
    return [for (final row in r) row['key'] as String];
  }

  static final _hasWindex = <String, bool>{};

  /// «Словоформа → [[номер Стронга, частота], …]» из обратного индекса словаря (если он есть)
  static List<(String, int)> windex(String id, String word) {
    _touch();
    final has = _hasWindex[id] ??= _store.db(id).select("SELECT 1 FROM sqlite_master WHERE name = 'windex'").isNotEmpty;
    if (!has) return const [];
    final r = _store.db(id).select('SELECT json FROM windex WHERE word = ?', [word]);
    if (r.isEmpty) return const [];
    return [for (final p in jsonDecode(r.first['json'] as String) as List) ((p as List)[0] as String, (p[1] as num).toInt())];
  }

  // --- Тексты стихов -------------------------------------------------------------------------

  static String? verseRaw(String moduleId, String book, int chapter, int verse) {
    if (!isInstalled(moduleId)) return null;
    try {
      final r = _store.db(moduleId).select('SELECT text FROM verses WHERE book = ? AND chapter = ? AND verse = ?', [book, chapter, verse]);
      return r.isEmpty ? null : r.first['text'] as String;
    } catch (_) {
      return null;
    }
  }

  static String? verse(String moduleId, VerseRef r) => verseRaw(moduleId, r.book, r.chapter, r.verse);

  /// Число глав книги и стихов главы в модуле (для перехода к соседнему стиху подстрочника)
  static int chapterCount(String moduleId, String book) {
    final r = _store.db(moduleId).select('SELECT MAX(chapter) AS c FROM verses WHERE book = ?', [book]);
    return r.isEmpty ? 0 : (r.first['c'] as int?) ?? 0;
  }

  static int verseCount(String moduleId, String book, int chapter) {
    final r = _store.db(moduleId).select('SELECT MAX(verse) AS v FROM verses WHERE book = ? AND chapter = ?', [book, chapter]);
    return r.isEmpty ? 0 : (r.first['v'] as int?) ?? 0;
  }

  /// Текст ссылки (до maxVerses стихов диапазона) из указанного перевода
  static (List<({int chapter, int verse, String text})>, bool) textForRef(String moduleId, OsisRef ref, {int maxVerses = 4}) {
    final parts = <({int chapter, int verse, String text})>[];
    var book = ref.book, chapter = ref.chapter, verse = ref.verse;
    final end = ref.end ?? ref.start;
    var count = 0;
    while (count < maxVerses) {
      final v = verseRaw(moduleId, book, chapter, verse);
      if (v == null) {
        // конец главы — следующая глава диапазона
        if (chapter < end.chapter && verseRaw(moduleId, book, chapter + 1, 1) != null) {
          chapter++;
          verse = 1;
          continue;
        }
        break;
      }
      parts.add((chapter: chapter, verse: verse, text: _plain(v)));
      count++;
      if (chapter == end.chapter && verse >= end.verse) break;
      if (chapter > end.chapter) break;
      verse++;
    }
    final totalInRange = ref.end != null && ref.end!.chapter == ref.chapter ? ref.end!.verse - ref.verse + 1 : null;
    final truncated = totalInRange != null ? totalInRange > parts.length : ref.end != null && count >= maxVerses;
    return (parts, truncated);
  }

  static final _markup = RegExp(r'\{([^|}]*)\|[^}]*\}');
  static String _plain(String raw) => raw.replaceAllMapped(_markup, (m) => m.group(1)!).replaceAll('‹', '').replaceAll('›', '');

  // --- Параллельные места --------------------------------------------------------------------

  /// Ссылки стиха: из самого перевода, затем из модулей параллельных мест (без повторов)
  static List<({String osis, OsisRef ref, String source})> refsForVerse(String moduleId, VerseRef at) {
    final seen = <String>{};
    final out = <({String osis, OsisRef ref, String source})>[];
    void add(String r, String source) {
      if (!seen.add(r)) return;
      final p = parseOsisRef(r);
      if (p != null) out.add((osis: r, ref: p, source: source));
    }

    try {
      final r = _store.db(moduleId).select('SELECT refs FROM xrefs WHERE book = ? AND chapter = ? AND verse = ?', [at.book, at.chapter, at.verse]);
      for (final row in r) {
        for (final x in jsonDecode(row['refs'] as String) as List) {
          add(x as String, t('перевод'));
        }
      }
    } catch (_) {
      // у перевода нет своих параллельных мест
    }
    for (final m in crossrefModules()) {
      final r = _store.db(m.id).select('SELECT refs FROM xr WHERE book = ? AND chapter = ? AND verse = ?', [at.book, at.chapter, at.verse]);
      for (final row in r) {
        for (final x in jsonDecode(row['refs'] as String) as List) {
          add(x as String, m.name);
        }
      }
    }
    return out;
  }

  /// Число параллельных мест у каждого стиха книги (для значка [⇅ n]): глава * 1000 + стих → число
  static Map<int, int> xrefCounts(String moduleId, String book) {
    _touch();
    final key = 'xr|$moduleId|$book';
    final hit = _bookCache[key];
    if (hit != null) return hit as Map<int, int>;
    final m = <int, int>{};
    try {
      for (final row in _store.db(moduleId).select('SELECT chapter, verse, refs FROM xrefs WHERE book = ?', [book])) {
        final k = (row['chapter'] as int) * 1000 + (row['verse'] as int);
        m[k] = (m[k] ?? 0) + (jsonDecode(row['refs'] as String) as List).length;
      }
    } catch (_) {
      // у перевода нет своих параллельных мест
    }
    for (final mod in crossrefModules()) {
      for (final row in _store.db(mod.id).select('SELECT chapter, verse, n FROM xr WHERE book = ?', [book])) {
        final k = (row['chapter'] as int) * 1000 + (row['verse'] as int);
        m[k] = (m[k] ?? 0) + (row['n'] as int);
      }
    }
    return _bookCache[key] = m;
  }

  // --- Комментарии ---------------------------------------------------------------------------

  /// Какие комментарии начинаются с каждого стиха книги: глава * 1000 + стих → [(id, имя)]
  static Map<int, List<(String, String)>> commentaryIndex(String book) {
    _touch();
    final key = 'cm|$book';
    final hit = _bookCache[key];
    if (hit != null) return hit as Map<int, List<(String, String)>>;
    final m = <int, List<(String, String)>>{};
    for (final mod in commentaries()) {
      for (final row in _store.db(mod.id).select('SELECT DISTINCT chapter, verse FROM comm WHERE book = ?', [book])) {
        (m[(row['chapter'] as int) * 1000 + (row['verse'] as int)] ??= []).add((mod.id, mod.name));
      }
    }
    return _bookCache[key] = m;
  }

  /// Все статьи включённых комментариев, начинающиеся с этого стиха
  static List<({InstalledModule module, List<({String key, OsisRef ref, String title, String text})> items})> commentaryFor(VerseRef at) {
    final out = <({InstalledModule module, List<({String key, OsisRef ref, String title, String text})> items})>[];
    for (final m in commentaries()) {
      final r = _store.db(m.id).select('SELECT key, title, text FROM comm WHERE book = ? AND chapter = ? AND verse = ?', [at.book, at.chapter, at.verse]);
      final items = [
        for (final row in r)
          if (parseOsisRef(row['key'] as String) case final p?) (key: row['key'] as String, ref: p, title: row['title'] as String, text: row['text'] as String),
      ];
      if (items.isNotEmpty) out.add((module: m, items: items));
    }
    return out;
  }

  // --- Иллюстрации ---------------------------------------------------------------------------

  static const _maxIllus = 2;

  /// Сколько картинок у каждого стиха книги (не больше двух): глава * 1000 + стих → число
  static Map<int, int> illustrationCounts(String book) {
    _touch();
    final key = 'il|$book';
    final hit = _bookCache[key];
    if (hit != null) return hit as Map<int, int>;
    final m = <int, int>{};
    for (final mod in illustrationModules()) {
      for (final row in _store.db(mod.id).select('SELECT chapter, verse, json FROM illus WHERE book = ?', [book])) {
        final k = (row['chapter'] as int) * 1000 + (row['verse'] as int);
        final n = (jsonDecode(row['json'] as String) as List).length;
        m[k] = ((m[k] ?? 0) + n).clamp(0, _maxIllus);
      }
    }
    return _bookCache[key] = m;
  }

  static List<Map<String, dynamic>> illustrationsFor(VerseRef at) {
    final out = <Map<String, dynamic>>[];
    for (final mod in illustrationModules()) {
      for (final row in _store.db(mod.id).select('SELECT json FROM illus WHERE book = ? AND chapter = ? AND verse = ?', [at.book, at.chapter, at.verse])) {
        for (final it in jsonDecode(row['json'] as String) as List) {
          final m = (it as Map).cast<String, dynamic>();
          if (out.length < _maxIllus && !out.any((x) => x['img'] == m['img'])) out.add(m);
        }
      }
    }
    return out;
  }

  // --- Статистика слова оригинала ------------------------------------------------------------

  static final _statsCache = <String, WordStats?>{};

  /// Где и сколько раз встречается номер Стронга в переводе с разметкой (RST+): считается один раз, запоминается
  /// Статистика номера Стронга по переводу с номерами. Просмотр всего текста (LIKE по всем стихам) — в отдельном
  /// потоке: первый подсчёт слова не останавливает интерфейс; результат запоминается.
  static Future<WordStats?> strongStats(String num) async {
    _touch();
    if (_statsCache.containsKey(num)) return _statsCache[num];
    final mods = _store.bibles.where((m) => m.features['strongs'] == true).toList();
    final mod = mods.where((m) => m.id == 'rst-plus').firstOrNull ?? mods.where((m) => m.language == 'ru').firstOrNull ?? mods.firstOrNull;
    if (mod == null) return null; // перевода с номерами ещё нет — не запоминаем
    final path = mod.path;
    final esc = num.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final s = await Isolate.run(() => _scanStrong(path, esc));
    return _statsCache[num] = WordStats(
      module: mod.name,
      moduleId: mod.id,
      total: s.total,
      verses: s.refs.length,
      byBook: s.byBook,
      renderings: s.renderings,
      refs: s.refs,
    );
  }
}

/// Подсчёт в отдельном потоке: база открывается здесь по пути к файлу
({int total, List<(String, int)> byBook, List<(String, int)> renderings, List<(VerseRef, List<String>)> refs}) _scanStrong(String path, String esc) {
  // {слово|H1254 H853|TH8804} — номер среди номеров второго поля
  final re = RegExp(r'\{([^|}]*)\|(?:[^|}]*\s)?' + esc + r'(?=[\s|}])[^}]*\}');
  final byBook = <String, int>{};
  final renderings = <String, int>{};
  final refs = <(VerseRef, List<String>)>[];
  var total = 0;
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final rows = db.select('SELECT book, chapter, verse, text FROM verses WHERE text LIKE ? ORDER BY id', ['%$esc%']);
    for (final row in rows) {
      final words = <String>[];
      for (final m in re.allMatches(row['text'] as String)) {
        final w = m.group(1)!.trim().toLowerCase();
        words.add(w);
        renderings[w] = (renderings[w] ?? 0) + 1;
      }
      if (words.isEmpty) continue;
      final book = row['book'] as String;
      byBook[book] = (byBook[book] ?? 0) + words.length;
      total += words.length;
      refs.add((VerseRef(book, row['chapter'] as int, row['verse'] as int), words));
    }
  } finally {
    db.close();
  }
  // по убыванию числа; при равенстве — в порядке первого появления (сортировка в Dart не стабильна)
  final order = {for (final (i, e) in renderings.entries.indexed) e.key: i};
  final sorted = renderings.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : order[a.key]!.compareTo(order[b.key]!));
  return (
    total: total,
    byBook: [for (final e in byBook.entries) (e.key, e.value)],
    renderings: [for (final e in sorted) (e.key, e.value)],
    refs: refs,
  );
}

class WordStats {
  WordStats({required this.module, required this.moduleId, required this.total, required this.verses, required this.byBook, required this.renderings, required this.refs});
  final String module;
  final String moduleId;
  final int total;
  final int verses;
  final List<(String, int)> byBook; // книга, число употреблений — в порядке Библии
  final List<(String, int)> renderings;
  final List<(VerseRef, List<String>)> refs;
}
