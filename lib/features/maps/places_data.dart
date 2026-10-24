// Модуль «Места» (bible-places, тип maps): 1321 место с координатами. Установка раскладывает места по таблицам SQLite
// (поиск по названию и по стиху — запросами с индексом, без разбора JSON при каждом открытии).
// Образец — src/core/places.js веб-версии: место предлагается только в стихе из его списка упоминаний
// и только если слово начинается с основы названия («Хеврону» → «хевр» → Хеврон).
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/books.dart';
import '../../core/modules.dart';

/// Слово для сравнения с основами: строчные, «ё» → «е» (как normalizeWord в веб-версии)
String normWord(String w) => w.toLowerCase().replaceAll('ё', 'е');

class Place {
  Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.type = '',
    this.confidence,
    this.modern = '',
    this.description = '',
    this.stems = const [],
    this.refs = const [],
    this.moduleId = '',
    this.moduleName = '',
    this.license = '',
  });

  final String id, name, type, modern, description, moduleId, moduleName, license;
  final double lat, lng;
  final int? confidence;
  final List<String> stems;
  final List<String> refs; // OSIS: «Josh.14.15»

  /// Ссылки на стихи (диапазон «Deut.8.7-9» берём с первого стиха), нераспознанные пропускаем
  List<VerseRef> get verses {
    final out = <VerseRef>[];
    for (final r in refs) {
      final v = parseOsis(r);
      if (v != null) out.add(v);
    }
    return out;
  }
}

/// «Josh.14.15», «Deut.8.7-9» → ссылка; иначе null
VerseRef? parseOsis(String s) {
  final p = s.split('.');
  if (p.length < 3) return null;
  final c = int.tryParse(p[1]);
  final v = int.tryParse(p[2].split('-').first);
  if (c == null || v == null) return null;
  return VerseRef(p[0], c, v);
}

/// Установка: места → таблицы (вызывается из modules.dart в отдельном потоке)
void convertPlaces(Database db, Map<String, dynamic> j) {
  db.execute('''
    CREATE TABLE places(id TEXT PRIMARY KEY, ord INTEGER, name TEXT, name_norm TEXT, lat REAL, lng REAL, type TEXT,
      confidence INTEGER, modern TEXT, descr TEXT, stems TEXT, refs TEXT);
    CREATE TABLE place_refs(ref TEXT NOT NULL, place_id TEXT NOT NULL);
  ''');
  final insP = db.prepare('INSERT OR REPLACE INTO places VALUES (?,?,?,?,?,?,?,?,?,?,?,?)');
  final insR = db.prepare('INSERT INTO place_refs VALUES (?,?)');
  var ord = 0;
  for (final p in (j['places'] as List).cast<Map>()) {
    final id = p['id'] as String;
    final name = (p['name'] as String?) ?? id;
    final refs = [for (final r in (p['refs'] as List? ?? const [])) r as String];
    insP.execute([
      id, ord++, name, normWord(name), (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble(),
      p['type'] ?? '', (p['confidence'] as num?)?.toInt(), p['modern'] ?? '', p['description'] ?? '',
      jsonEncode(p['stems'] ?? const []), jsonEncode(refs),
    ]);
    for (final r in refs) {
      insR.execute([r, id]);
    }
  }
  insP.close();
  insR.close();
  db.execute('CREATE INDEX place_refs_ref ON place_refs(ref); CREATE INDEX places_name ON places(name_norm);');
}

/// Запросы к установленным модулям «Места» (тип maps с таблицей places)
class PlaceStore {
  PlaceStore._();

  static final Map<String, bool> _has = {}; // id модуля → есть таблица places

  static bool _hasPlaces(InstalledModule m) => _has[m.id + m.path] ??= () {
        try {
          final r = ModuleStore.instance.db(m.id).select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='places'");
          return r.isNotEmpty;
        } catch (_) {
          return false;
        }
      }();

  /// Сбросить кэш (после установки/удаления модуля)
  static void reset() => _has.clear();

  static List<InstalledModule> get modules => ModuleStore.instance.installed.where((m) => m.type == 'maps' && _hasPlaces(m)).toList();

  static Place _row(Row r, InstalledModule m) => Place(
        id: r['id'] as String,
        name: r['name'] as String,
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lng'] as num).toDouble(),
        type: r['type'] as String? ?? '',
        confidence: r['confidence'] as int?,
        modern: r['modern'] as String? ?? '',
        description: r['descr'] as String? ?? '',
        stems: (jsonDecode(r['stems'] as String? ?? '[]') as List).cast<String>(),
        refs: (jsonDecode(r['refs'] as String? ?? '[]') as List).cast<String>(),
        moduleId: m.id,
        moduleName: m.name,
        license: (m.meta['license'] as String?) ?? '',
      );

  static int get count {
    var n = 0;
    for (final m in modules) {
      n += ModuleStore.instance.db(m.id).select('SELECT COUNT(*) AS n FROM places').first['n'] as int;
    }
    return n;
  }

  /// Места, упомянутые в стихе (по списку упоминаний)
  static List<Place> inVerse(VerseRef ref) {
    final out = <Place>[];
    for (final m in modules) {
      final rows = ModuleStore.instance.db(m.id).select('SELECT p.* FROM place_refs r JOIN places p ON p.id = r.place_id WHERE r.ref = ?', [ref.toString()]);
      out.addAll(rows.map((r) => _row(r, m)));
    }
    return out;
  }

  /// Места, о которых говорит нажатое слово этого стиха
  static List<Place> forWord(String word, VerseRef ref) {
    final w = normWord(word);
    if (w.isEmpty) return const [];
    final seen = <String>{};
    return [
      for (final p in inVerse(ref))
        if (!seen.contains(p.id) && p.stems.any(w.startsWith) && seen.add(p.id)) p,
    ];
  }

  /// Поиск по названию (подстрока, до [limit] мест)
  static List<Place> search(String q, {int limit = 50}) {
    final query = normWord(q.trim());
    if (query.length < 2) return const [];
    final like = '%${query.replaceAll(r'\', r'\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final out = <Place>[];
    for (final m in modules) {
      final rows = ModuleStore.instance.db(m.id).select(r"SELECT * FROM places WHERE name_norm LIKE ? ESCAPE '\' ORDER BY ord LIMIT ?", [like, limit - out.length]);
      out.addAll(rows.map((r) => _row(r, m)));
      if (out.length >= limit) break;
    }
    return out;
  }
}
