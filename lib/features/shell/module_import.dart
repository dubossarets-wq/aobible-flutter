// Импорт модулей из файла (core/schema.js + ModuleImporter.jsx): определяем формат JSON (родной aob-module или один из
// распространённых), проверяем структуру и приводим к виду, как у модулей каталога — дальше ModuleStore кладёт его в SQLite.
// Разбор файла (распаковка .gz, JSON) — в отдельном потоке (parseModuleBytes); проверка — быстрый цикл по главам.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/net.dart';

class ModuleError implements Exception {
  ModuleError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Проверенный модуль: описание для показа, предупреждения и готовый к установке JSON (формат каталога)
class ImportPreview {
  ImportPreview(this.meta, this.json, this.warnings);
  final Map<String, dynamic> meta;
  final Map<String, dynamic> json;
  final List<String> warnings;
  String get id => meta['id'] as String;
}

/// Скачать файл по полному адресу (свой каталог, модули из него); onProgress(0..1)
Future<Uint8List> downloadUrl(String url, {void Function(double)? onProgress}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final res = await req.close();
    if (res.statusCode != 200) throw NetError(t('Сервер ответил ошибкой {status} для {url}.', {'status': '${res.statusCode}', 'url': url}));
    final total = res.contentLength;
    final b = BytesBuilder(copy: false);
    var got = 0;
    await for (final c in res) {
      b.add(c);
      got += c.length;
      if (total > 0) onProgress?.call(got / total);
    }
    return b.takeBytes();
  } finally {
    client.close(force: true);
  }
}

// Порядок книг в западных (протестантских) изданиях — для форматов, где книга задана номером
const _western = [
  'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth', '1Sam', '2Sam', '1Kgs', '2Kgs', '1Chr', '2Chr',
  'Ezra', 'Neh', 'Esth', 'Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Isa', 'Jer', 'Lam', 'Ezek', 'Dan', 'Hos', 'Joel',
  'Amos', 'Obad', 'Jonah', 'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal', 'Matt', 'Mark', 'Luke', 'John',
  'Acts', 'Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col', '1Thess', '2Thess', '1Tim', '2Tim', 'Titus', 'Phlm',
  'Heb', 'Jas', '1Pet', '2Pet', '1John', '2John', '3John', 'Jude', 'Rev',
];

final _osisVerse = RegExp(r'^[1-4]?[A-Za-z]+\.\d+\.\d+(-(\d+\.)?\d+)?$');
final _strongKey = RegExp(r'^[HG]\d+[a-z]?$', caseSensitive: false);

bool _isMap(Object? x) => x is Map;

/// Распаковать и разобрать JSON (в отдельном потоке: файл может быть в десятки мегабайт)
Object? parseModuleBytes(Uint8List bytes) {
  var raw = bytes;
  if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
    try {
      raw = Uint8List.fromList(gzip.decode(raw));
    } catch (_) {
      throw ModuleError(t('Файл не является корректным JSON: {error}', {'error': 'gzip'}));
    }
  }
  var text = utf8.decode(raw, allowMalformed: true);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) text = text.substring(1);
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw ModuleError(t('Файл не является корректным JSON: {error}', {'error': e.message}));
  }
}

String _slug(Object? s) {
  final v = '${s ?? 'module'}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), '-').replaceAll(RegExp(r'^-|-$'), '');
  final cut = v.length > 48 ? v.substring(0, 48) : v;
  return cut.isEmpty ? 'module' : cut;
}

String? _resolveBook(Object? b, int? index) {
  final books = Books.instance;
  if (b is num) return b >= 1 && b <= _western.length ? _western[b.toInt() - 1] : null;
  if (b is String) {
    if (RegExp(r'^\d+$').hasMatch(b)) {
      final n = int.parse(b);
      return n >= 1 && n <= _western.length ? _western[n - 1] : null;
    }
    return books.all.any((x) => x.id == b) ? b : books.findBookId(b);
  }
  return index != null && index < _western.length ? _western[index] : null;
}

String _verseText(Object? v) {
  if (v is String) return v;
  if (v is Map) return '${v['text'] ?? v['t'] ?? ''}';
  return v == null ? '' : '$v';
}

/// (формат, тип) — как detect() в schema.js
(String?, String?) detectFormat(Object? json) {
  if (json is Map && json['format'] == 'aob-module') return ('aob', json['type'] as String?);
  if (json is Map && json['format'] == 'aob-catalog') return ('catalog', null);
  if (json is List && json.isNotEmpty && json.first is Map && (json.first as Map)['chapters'] is List) return ('books-array', 'bible');
  final flat = json is List ? json : (json is Map && json['verses'] is List ? json['verses'] as List : null);
  if (flat != null && flat.isNotEmpty && flat.first is Map) {
    final f = flat.first as Map;
    if (f.containsKey('chapter') && f.containsKey('verse') && f.containsKey('text')) return ('flat-verses', 'bible');
  }
  if (json is Map && json['books'] is List) return ('aob', 'bible');
  if (json is Map && _isMap(json['entries'])) {
    final keys = (json['entries'] as Map).keys.take(20).toList();
    return ('aob', keys.isNotEmpty && keys.every((k) => _osisVerse.hasMatch('$k')) ? 'commentary' : 'dictionary');
  }
  if (json is Map && _isMap(json['refs'])) return ('aob', 'crossrefs');
  if (json is Map && (json['maps'] is List || json['places'] is List)) return ('aob', 'maps');
  if (json is Map) {
    final keys = json.keys.take(50).toList();
    if (keys.isNotEmpty && keys.every((k) => _strongKey.hasMatch('$k'))) return ('strongs-map', 'dictionary');
  }
  if (json is List && json.isNotEmpty && json.first is Map) {
    final f = json.first as Map;
    if ((f['word'] != null || f['term'] != null || f['topic'] != null) && (f['definition'] != null || f['text'] != null || f['description'] != null)) return ('word-list', 'dictionary');
  }
  return (null, null);
}

/// Проверка и приведение к виду каталога (normalize в schema.js)
ImportPreview normalizeModule(Object? json, String fileName) {
  final (format, type) = detectFormat(json);
  if (format == 'catalog') throw ModuleError(t('Это файл каталога, а не модуль. Откройте его во вкладке «Онлайн-каталог».'));
  if (format == null || type == null) {
    throw ModuleError(t('Не удалось определить тип модуля. Нужен JSON в формате aob-module (поле "format": "aob-module") или один из поддерживаемых форматов: массив книг с "chapters", список стихов {fields}, словарь {"H1": {...}} или список статей [{word, definition}].', {'fields': '{book, chapter, verse, text}'}));
  }
  final baseName = fileName.replaceAll(RegExp(r'(\.(json|gz))+$', caseSensitive: false), '');
  final src = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
  String s(Object? v) => v == null ? '' : '$v';
  String pick(List<Object?> l) => l.map(s).firstWhere((x) => x.isNotEmpty, orElse: () => '');
  final name = pick([src['name'], src['abbreviation'], baseName, t('Без названия')]);
  final meta = <String, dynamic>{
    'id': _slug(pick([src['id'], baseName, src['name']])),
    'type': type,
    'name': name.length > 40 ? name.substring(0, 40) : name,
    'title': pick([src['title'], src['name'], baseName]),
    'description': s(src['description']),
    'language': pick([src['language'], src['lang'], 'ru']),
    'version': s(src['version']),
    'author': s(src['author']),
    'source': pick([src['source'], fileName.isEmpty ? '' : t('Файл {name}', {'name': fileName})]),
    'license': pick([src['license'], t('не указана')]),
    'versification': pick([src['versification'], 'synodal']),
    'features': src['features'] is Map ? Map<String, dynamic>.from(src['features'] as Map) : <String, dynamic>{},
  };
  if (type == 'dictionary') meta['dictionaryKind'] = pick([src['dictionaryKind'], format == 'strongs-map' ? 'strongs' : 'words']);

  final warnings = <String>[];
  final Map<String, dynamic> data = switch (type) {
    'bible' => _bible(json, format, warnings),
    'dictionary' => _dictionary(json, format, meta, warnings),
    'crossrefs' => _crossrefs(src),
    'commentary' => _commentary(src, warnings),
    'maps' => _maps(src, warnings),
    'audio' => _audio(src, warnings),
    'illustrations' => _illustrations(src, warnings),
    _ => throw ModuleError(t('Неизвестный тип модуля «{type}». Допустимы: bible, commentary, dictionary, maps, crossrefs.', {'type': type})),
  };

  final stats = <String, dynamic>{};
  switch (type) {
    case 'bible':
      final books = (data['books'] as List).cast<Map<String, dynamic>>();
      if (meta['features']['strongs'] == null) {
        meta['features']['strongs'] = books.any((b) => (b['chapters'] as List).any((c) => (c as List).any((v) => (v as String).contains('{'))));
      }
      stats['books'] = books.length;
      stats['verses'] = books.fold<int>(0, (n, b) => n + (b['chapters'] as List).fold<int>(0, (m, c) => m + (c as List).length));
    case 'dictionary' || 'commentary':
      stats['entries'] = (data['entries'] as Map).length;
    case 'crossrefs':
      stats['verses'] = (data['refs'] as Map).length;
    case 'maps':
      stats['maps'] = (data['maps'] as List).length;
      stats['places'] = (data['places'] as List).length;
    case 'illustrations':
      stats['verses'] = (data['entries'] as Map).length;
      stats['images'] = (data['entries'] as Map).values.fold<int>(0, (n, l) => n + (l as List).length);
    case 'audio':
      stats['chapters'] = (data['chapters'] as Map).length;
      meta['translation'] = src['translation'];
      meta['chapterKeys'] = (data['chapters'] as Map).keys.toList();
  }
  meta['stats'] = stats;
  meta['origin'] = 'file';
  return ImportPreview(meta, {'format': 'aob-module', 'formatVersion': 1, ...meta, ...data}, warnings);
}

Map<String, dynamic> _bible(Object? json, String format, List<String> warnings) {
  final books = <Map<String, dynamic>>[];
  final bk = Books.instance;
  void push(String id, Map? src, List<dynamic> chapters) {
    final m = bk.meta(id);
    final tt = src?['t'];
    books.add({
      'id': id,
      'name': (src?['name'] as String?) ?? m.name,
      'short': (src?['short'] as String?) ?? m.short,
      't': ['OT', 'NT', 'AP'].contains(tt) ? tt : (m.order < 999 ? m.testament : 'AP'),
      'chapters': chapters,
      'headings': src?['headings'] is Map ? src!['headings'] : <String, dynamic>{},
      'xrefs': src?['xrefs'] is Map ? src!['xrefs'] : <String, dynamic>{},
    });
  }

  if (format == 'aob' || format == 'books-array') {
    final list = format == 'aob' ? (json as Map)['books'] : json;
    if (list is! List || list.isEmpty) throw ModuleError(t('В модуле нет книг (поле "books" пустое).'));
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      if (b is! Map) continue;
      final raw = b['id'] ?? b['osis'];
      var id = _resolveBook(raw ?? b['name'] ?? b['abbrev'], raw != null || b['name'] != null ? null : i);
      // Книга вне справочника (апокрифы): берём её код как есть, если у неё есть название
      if (id == null && raw is String && RegExp(r'^[0-9A-Za-z]{2,12}$').hasMatch(raw) && b['name'] != null) id = raw;
      // Совсем без опознаваемого кода — по порядку протестантского канона
      if (id == null && raw == null && b['name'] == null) id = _resolveBook(null, i);
      if (id == null && format == 'books-array' && raw == null) id = _resolveBook(null, i);
      if (id == null) {
        warnings.add(t('Книга №{n} («{name}») не распознана и пропущена.', {'n': '${i + 1}', 'name': '${b['name'] ?? b['id'] ?? b['abbrev'] ?? '?'}'}));
        continue;
      }
      if (b['chapters'] is! List) {
        warnings.add(t('У книги {id} нет массива "chapters" — пропущена.', {'id': id}));
        continue;
      }
      push(id, b, [for (final c in b['chapters'] as List) c is List ? [for (final v in c) _verseText(v)] : <String>[]]);
    }
  } else if (format == 'flat-verses') {
    final list = (json is List ? json : (json as Map)['verses']) as List;
    final map = <String, List<List<String>>>{};
    var skipped = 0;
    for (final v in list) {
      if (v is! Map) {
        skipped++;
        continue;
      }
      final id = _resolveBook(v['book'] ?? v['book_id'] ?? v['bookId'] ?? v['book_name'], null);
      final ch = v['chapter'], vs = v['verse'];
      if (id == null || ch is! num || vs is! num || ch <= 0 || vs <= 0) {
        skipped++;
        continue;
      }
      final chs = map.putIfAbsent(id, () => []);
      while (chs.length < ch) {
        chs.add([]);
      }
      final c = chs[ch.toInt() - 1];
      while (c.length < vs) {
        c.add('');
      }
      c[vs.toInt() - 1] = '${v['text']}';
    }
    if (skipped > 0) warnings.add(t('Пропущено записей без распознанной книги/главы/стиха: {n}.', {'n': '$skipped'}));
    final ids = map.keys.toList()..sort((a, b) => bk.order(a).compareTo(bk.order(b)));
    for (final id in ids) {
      push(id, null, map[id]!);
    }
  }
  if (books.isEmpty) throw ModuleError(t('Не найдено ни одной распознанной книги.'));
  final seen = <String>{};
  for (final b in books) {
    if (!seen.add(b['id'] as String)) throw ModuleError(t('Книга {id} встречается в модуле дважды.', {'id': '${b['id']}'}));
    if ((b['chapters'] as List).isEmpty) warnings.add(t('В книге {name} нет глав.', {'name': '${b['name']}'}));
  }
  return {'books': books};
}

Map<String, dynamic> _dictionary(Object? json, String format, Map<String, dynamic> meta, List<String> warnings) {
  var entries = <String, dynamic>{};
  if (format == 'strongs-map') {
    entries = Map<String, dynamic>.from(json as Map);
  } else if (format == 'word-list') {
    for (final e in (json as List).whereType<Map>()) {
      final word = '${e['word'] ?? e['term'] ?? e['topic'] ?? ''}'.trim();
      if (word.isEmpty) continue;
      entries[word.toLowerCase().replaceAll('ё', 'е')] = {'word': word, 'text': '${e['definition'] ?? e['text'] ?? e['description'] ?? ''}', 'refs': e['refs'] is List ? e['refs'] : []};
    }
  } else {
    final e = (json as Map)['entries'];
    if (e is Map) entries = Map<String, dynamic>.from(e);
  }
  if (entries.isEmpty) throw ModuleError(t('В словаре нет статей (поле "entries" пустое).'));
  if (meta['dictionaryKind'] == 'strongs') {
    final bad = entries.keys.where((k) => !_strongKey.hasMatch(k)).toList();
    if (bad.isNotEmpty) warnings.add(t('Ключи не похожи на номера Стронга и не будут найдены: {keys}', {'keys': bad.take(5).join(', ') + (bad.length > 5 ? '…' : '')}));
  } else {
    // Ключи словаря по словам приводим к нижнему регистру для поиска
    final norm = <String, dynamic>{};
    entries.forEach((k, v) {
      final e = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{'text': '$v'};
      norm[k.toLowerCase().replaceAll('ё', 'е')] = {'word': e['word'] ?? k, ...e};
    });
    entries = norm;
  }
  final out = <String, dynamic>{'entries': entries};
  if (json is Map && json['wordIndex'] is Map) out['wordIndex'] = json['wordIndex'];
  return out;
}

Map<String, dynamic> _commentary(Map<String, dynamic> json, List<String> warnings) {
  if (json['entries'] is! Map) throw ModuleError(t('В комментарии нет поля "entries" вида {example}.', {'example': '{"Gen.1.1": "…"}'}));
  final entries = <String, dynamic>{};
  var bad = 0;
  (json['entries'] as Map).forEach((k, v) {
    if (!_osisVerse.hasMatch('$k')) {
      bad++;
      return;
    }
    final e = v is Map ? {'title': v['title'] != null ? '${v['title']}' : '', 'text': '${v['text'] ?? ''}'} : {'text': '$v'};
    if (e['text']!.trim().isNotEmpty) entries['$k'] = e;
  });
  if (bad > 0) warnings.add(t('Пропущено статей с ключом не в формате "Книга.глава.стих": {n}.', {'n': '$bad'}));
  if (entries.isEmpty) throw ModuleError(t('В комментарии нет ни одной статьи с ключом вида "Gen.1.1".'));
  return {'entries': entries};
}

/// Основы названия места для поиска в стихе: «Вифлеем» → «вифл», «Гора Мориа» → «мор»
List<String> placeStems(String name) {
  const skip = ['гора', 'река', 'море', 'поток', 'долина', 'пустыня', 'земля', 'город', 'страна'];
  var words = name.toLowerCase().replaceAll('ё', 'е').split(RegExp(r'[\s\-–(),]+')).where((w) => w.length >= 3).toList();
  final rest = words.where((w) => !skip.contains(w)).toList();
  if (rest.isNotEmpty) words = rest;
  return {for (final w in words) w.substring(0, (w.length - 2).clamp(3, 5).clamp(0, w.length))}.toList();
}

Map<String, dynamic> _maps(Map<String, dynamic> json, List<String> warnings) {
  final maps = <Map<String, dynamic>>[];
  final list = json['maps'] is List ? json['maps'] as List : const [];
  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    final img = m is Map && m['image'] is String ? (m['image'] as String).trim() : '';
    final ok = RegExp(r'^(https?:|data:image/)').hasMatch(img) || (RegExp(r'^[\w./-]+\.(jpe?g|png|webp|gif|svg)$', caseSensitive: false).hasMatch(img) && !img.contains('..'));
    if (!ok) {
      warnings.add(t('Карта №{n} пропущена: нет поля "image" (адрес, data:image или путь к картинке).', {'n': '${i + 1}'}));
      continue;
    }
    m as Map;
    maps.add({
      'id': '${m['id'] ?? i + 1}',
      'title': '${m['title'] ?? t('Карта {n}', {'n': '${i + 1}'})}',
      'description': '${m['description'] ?? ''}',
      'image': img,
      'refs': m['refs'] is List ? [for (final r in m['refs'] as List) '$r'] : [],
    });
  }
  final places = <Map<String, dynamic>>[];
  var bad = 0;
  for (final p in (json['places'] is List ? json['places'] as List : const [])) {
    final lat = p is Map ? num.tryParse('${p['lat']}') : null;
    final lng = p is Map ? num.tryParse('${p['lng'] ?? p['lon']}') : null;
    if (p is! Map || p['name'] == null || '${p['name']}'.isEmpty || lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      bad++;
      continue;
    }
    places.add({
      ...p.cast<String, dynamic>(),
      'id': '${p['id'] ?? p['name']}',
      'name': '${p['name']}',
      'lat': lat,
      'lng': lng,
      'refs': p['refs'] is List ? [for (final r in p['refs'] as List) '$r'] : [],
      'stems': p['stems'] is List && (p['stems'] as List).isNotEmpty ? [for (final r in p['stems'] as List) '$r'] : placeStems('${p['name']}'),
    });
  }
  if (bad > 0) warnings.add(t('Пропущено мест без названия или координат: {n}.', {'n': '$bad'}));
  if (maps.isEmpty && places.isEmpty) throw ModuleError(t('В модуле карт нет ни карт с изображением, ни мест с координатами.'));
  return {'maps': maps, 'places': places};
}

Map<String, dynamic> _illustrations(Map<String, dynamic> json, List<String> warnings) {
  if (json['entries'] is! Map) throw ModuleError(t('В модуле иллюстраций нет поля «entries» вида {example}.', {'example': '{"Gen.1.3": [{img, …}]}'}));
  final entries = <String, dynamic>{};
  var bad = 0;
  (json['entries'] as Map).forEach((k, list) {
    if (!RegExp(r'^[1-4]?[A-Za-z]+\.\d+\.\d+$').hasMatch('$k') || list is! List) {
      bad++;
      return;
    }
    final items = [
      for (final x in list.whereType<Map>().where((x) => x['img'] is String && (x['img'] as String).startsWith('https://')).take(2))
        {
          'img': x['img'],
          'thumb': x['thumb'] is String ? x['thumb'] : x['img'],
          'w': num.tryParse('${x['w']}')?.toInt(),
          'h': num.tryParse('${x['h']}')?.toInt(),
          'title': '${x['title'] ?? ''}',
          'author': '${x['author'] ?? ''}',
          'year': '${x['year'] ?? ''}',
          'license': '${x['license'] ?? ''}',
          'src': x['src'] is String ? x['src'] : '',
        },
    ];
    if (items.isEmpty) {
      bad++;
    } else {
      entries['$k'] = items;
    }
  });
  if (bad > 0) warnings.add(t('Пропущено записей без адреса картинки или с неверным стихом: {n}.', {'n': '$bad'}));
  if (entries.isEmpty) throw ModuleError(t('В модуле иллюстраций нет ни одной картинки.'));
  return {'entries': entries};
}

Map<String, dynamic> _audio(Map<String, dynamic> json, List<String> warnings) {
  if (json['chapters'] is! Map) throw ModuleError(t('В аудиомодуле нет поля "chapters" вида {example}.', {'example': '{"John.3": {url, verses}}'}));
  final chapters = <String, dynamic>{};
  var bad = 0;
  (json['chapters'] as Map).forEach((k, c) {
    final ok = RegExp(r'^[1-4]?[A-Za-z]+\.\d+$').hasMatch('$k') &&
        c is Map &&
        c['url'] is String &&
        RegExp(r'^https?:|^[\w./-]+\.(mp3|m4a|ogg|opus|aac|wav)$', caseSensitive: false).hasMatch(c['url'] as String) &&
        c['verses'] is List &&
        (c['verses'] as List).isNotEmpty;
    if (!ok) {
      bad++;
      return;
    }
    final verses = [
      for (final x in (c['verses'] as List).whereType<List>().where((x) => x.length >= 2 && num.tryParse('${x[0]}') != null && num.tryParse('${x[1]}') != null)) [num.parse('${x[0]}'), num.parse('${x[1]}')],
    ]..sort((a, b) => a[1].compareTo(b[1]));
    chapters['$k'] = {'url': c['url'], 'verses': verses, 'duration': num.tryParse('${c['duration']}'), 'start': num.tryParse('${c['start']}'), 'end': num.tryParse('${c['end']}')};
  });
  if (bad > 0) warnings.add(t('Пропущено глав без адреса записи или разметки стихов: {n}.', {'n': '$bad'}));
  if (chapters.isEmpty) throw ModuleError(t('В аудиомодуле нет ни одной главы с записью и разметкой стихов.'));
  if (json['files'] is List && json['segments'] is Map) {
    final files = [for (final u in (json['files'] as List)) if (u is String && RegExp(r'^https?:').hasMatch(u)) u];
    final segments = <String, dynamic>{};
    (json['segments'] as Map).forEach((k, s) {
      if (RegExp(r'^[1-4]?[A-Za-z]+\.\d+\.\d+$').hasMatch('$k') && s is List && s.length >= 3 && s[0] is int && (s[0] as int) < files.length && s[1] is num && s[2] is num) segments['$k'] = s;
    });
    if (segments.isNotEmpty) return {'chapters': chapters, 'files': files, 'segments': segments};
  }
  return {'chapters': chapters};
}

Map<String, dynamic> _crossrefs(Map<String, dynamic> json) {
  final refs = <String, dynamic>{};
  (json['refs'] as Map).forEach((k, v) {
    if (v is List && RegExp(r'^[1-3]?[A-Za-z]+\.\d+\.\d+$').hasMatch('$k')) refs['$k'] = [for (final x in v) '$x'];
  });
  if (refs.isEmpty) throw ModuleError(t('В модуле нет ссылок вида {example}.', {'example': '"Gen.1.1": ["John.1.1", …]'}));
  return {'refs': refs};
}
