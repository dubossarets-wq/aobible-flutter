// Модули на устройстве: каждый — отдельный файл SQLite в папке modules/.
// Установка: JSON (aob-module) с сайта → SQLite один раз; дальше чтение главы и поиск — запросы к базе
// (полнотекстовый поиск FTS5 по всей Библии — доли секунды вместо секунд в веб-версии).
// Тяжёлая работа (разбор JSON, запись в базу) — в отдельном потоке (Isolate.run), интерфейс не замирает.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../features/maps/places_data.dart';
import '../features/shell/module_import.dart';
import '../features/study/study_tables.dart';
import 'i18n.dart';
import 'markup.dart';
import 'net.dart';

/// Короткие названия модулей (не длиннее «Лопухин»): длинные не помещались в строки и подписи.
/// Полное название остаётся в title. Действует и для уже скачанных модулей
const shortModuleNames = {'desp-notes': 'Десницкий', 'otnt-notes': 'Откр. НЗ'};

class CatalogEntry {
  CatalogEntry(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get type => json['type'] as String? ?? 'bible';
  String get name => shortModuleNames[id] ?? json['name'] as String? ?? id;
  String get title => json['title'] as String? ?? name;
  String get language => json['language'] as String? ?? 'ru';
  String get version => json['version']?.toString() ?? '';
  bool get unavailable => json['unavailable'] == true;
  String? get url => json['url'] as String?;
  String? get urlGz => json['urlGz'] as String?;
  /// Адреса целиком (каталог по своему адресу): иначе — относительно modules/ на сайте
  bool get absolute => json['_abs'] == true;
  int get size => (json['sizeGz'] ?? json['size'] ?? 0) as int;
}

class InstalledModule {
  InstalledModule(this.id, this.meta, this.path);
  final String id;
  final Map<String, dynamic> meta;
  final String path;
  String get type => meta['type'] as String? ?? 'bible';
  String get name => shortModuleNames[id] ?? meta['name'] as String? ?? id;
  String get title => meta['title'] as String? ?? name;
  String get language => meta['language'] as String? ?? 'ru';
  Map<String, dynamic> get features => (meta['features'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class ModuleStore {
  ModuleStore._(this.dir);
  final Directory dir;
  static late ModuleStore instance;

  final Map<String, InstalledModule> _installed = {};
  final Set<String> _disabled = {}; // выключенные небиблейские модули (в списке есть, в словарях и комментариях не участвуют)
  final Map<String, Database> _open = {};

  static Future<ModuleStore> init() async {
    final base = await getApplicationSupportDirectory();
    return initAt(Directory('${base.path}${Platform.pathSeparator}modules'));
  }

  /// Папка модулей задана явно (тесты)
  static Future<ModuleStore> initAt(Directory dir) async {
    await dir.create(recursive: true);
    final s = instance = ModuleStore._(dir);
    s._scan();
    s._loadDisabled();
    return s;
  }

  File get _disabledFile => File('${dir.path}${Platform.pathSeparator}disabled.json');

  void _loadDisabled() {
    _disabled.clear();
    try {
      if (_disabledFile.existsSync()) _disabled.addAll((jsonDecode(_disabledFile.readAsStringSync()) as List).cast<String>());
    } catch (_) {
      // повреждённый список — все модули включены
    }
  }

  void _scan() {
    _installed.clear();
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db'))) {
      try {
        final db = sqlite3.open(f.path, mode: OpenMode.readOnly);
        final row = db.select("SELECT value FROM meta WHERE key = 'json'");
        db.close();
        if (row.isEmpty) continue;
        final meta = jsonDecode(row.first['value'] as String) as Map<String, dynamic>;
        _installed[meta['id'] as String] = InstalledModule(meta['id'] as String, meta, f.path);
      } catch (_) {
        // недописанный файл (оборвалась установка) — пропускаем, при следующей установке перезапишется
      }
    }
  }

  /// Включённые модули: их берут словари, комментарии, карты, поиск (выключенных здесь нет — как enabled !== false в веб-версии)
  List<InstalledModule> get installed => _installed.values.where((m) => !_disabled.contains(m.id)).toList();

  /// Все установленные, и выключенные тоже — для библиотеки модулей
  List<InstalledModule> get allInstalled => _installed.values.toList();
  List<InstalledModule> get bibles => installed.where((m) => m.type == 'bible').toList();
  InstalledModule? get(String id) => _installed[id];

  bool isEnabled(String id) => !_disabled.contains(id);

  /// Включить / выключить небиблейский модуль (переводы выключать нельзя); решение переживает обновление и переустановку
  Future<void> setEnabled(String id, bool on) async {
    if (_installed[id]?.type == 'bible' || on == isEnabled(id)) return;
    on ? _disabled.remove(id) : _disabled.add(id);
    await _disabledFile.writeAsString(jsonEncode(_disabled.toList()));
    changes.value++;
  }

  /// Растёт при каждой установке, удалении, импорте, включении/выключении модуля — подписчики перечитывают список
  final changes = ValueNotifier<int>(0);

  /// Открытая база модуля (только чтение; держим открытой — повторные запросы мгновенны)
  Database db(String id) => _open[id] ??= sqlite3.open(_installed[id]!.path, mode: OpenMode.readOnly);

  /// Каталог. url — свой каталог (aob-catalog по адресу, «Источник каталога» в веб-версии); без него — встроенный
  Future<List<CatalogEntry>> catalog({String? url}) async {
    if (url == null || url.isEmpty) {
      final bytes = await download('modules/catalog.json');
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return (j['modules'] as List).map((m) => CatalogEntry((m as Map).cast<String, dynamic>())).toList();
    }
    final Uint8List bytes;
    try {
      bytes = await downloadUrl(url);
    } catch (_) {
      throw NetError(t('Не удалось подключиться к {url}. Проверьте адрес и интернет.', {'url': url}));
    }
    Map<String, dynamic>? j;
    try {
      final raw = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b ? gzip.decode(bytes) : bytes;
      j = (jsonDecode(utf8.decode(raw)) as Map).cast<String, dynamic>();
    } catch (_) {
      // не JSON — ниже то же сообщение
    }
    if (j == null || j['format'] != 'aob-catalog' || j['modules'] is! List) throw NetError(t('По этому адресу нет каталога в формате aob-catalog.'));
    final base = Uri.parse(url);
    return [
      for (final m in (j['modules'] as List).whereType<Map>())
        CatalogEntry({
          ...m.cast<String, dynamic>(),
          '_abs': true,
          if (m['url'] != null) 'url': base.resolve('${m['url']}').toString(),
          if (m['urlGz'] != null) 'urlGz': base.resolve('${m['urlGz']}').toString(),
        }),
    ];
  }

  Future<void> install(CatalogEntry e, {void Function(double, String)? onProgress}) async {
    final gz = e.urlGz != null;
    final path = gz ? e.urlGz! : e.url!;
    void onP(double p) => onProgress?.call(p * 0.6, 'Загрузка');
    final bytes = e.absolute ? await downloadUrl(path, onProgress: onP) : await download('modules/$path', onProgress: onP);
    onProgress?.call(0.65, 'Подготовка');
    final target = '${dir.path}${Platform.pathSeparator}${e.id}.db';
    final tmp = '$target.part';
    await _convertInIsolate(bytes, gz, tmp, e.version);
    await _finish(e.id, tmp, target);
    onProgress?.call(1, 'Готово');
  }

  Future<void> _finish(String id, String tmp, String target) async {
    _open.remove(id)?.close();
    await File(tmp).rename(target);
    _scan();
    changes.value++;
  }

  /// Импорт: читаем файл (.json или .json.gz) и проверяем структуру — в отдельном потоке (importFile в modules.js)
  Future<ImportPreview> previewImport(Uint8List bytes, String fileName) async {
    final json = await Isolate.run(() => parseModuleBytes(bytes)); // распаковка и JSON — в потоке; проверка — быстрый цикл
    return normalizeModule(json, fileName);
  }

  /// Установить проверенный модуль; с тем же id — заменяет установленный
  Future<void> installPreview(ImportPreview p, {void Function(double, String)? onProgress}) async {
    final id = p.json['id'] as String;
    final target = '${dir.path}${Platform.pathSeparator}$id.db';
    final tmp = '$target.part';
    onProgress?.call(0.1, 'Сохранение…');
    final j = p.json;
    await Isolate.run(() => _convertJson(j, tmp, ''));
    await _finish(id, tmp, target);
    onProgress?.call(1, 'Готово');
  }

  Future<void> remove(String id) async {
    _open.remove(id)?.close();
    final m = _installed.remove(id);
    if (m != null) await File(m.path).delete();
    if (_disabled.remove(id)) await _disabledFile.writeAsString(jsonEncode(_disabled.toList()));
    changes.value++;
  }
}

// --- Преобразование JSON → SQLite (в отдельном потоке) --------------------------------------------

// Отдельная функция: в поток уходят только данные (замыкание внутри метода прихватило бы и обработчик
// прогресса с объектами интерфейса — их передавать между потоками нельзя)
Future<void> _convertInIsolate(List<int> bytes, bool gz, String path, String version) =>
    Isolate.run(() => _convert(gz ? gzip.decode(bytes) : bytes, path, version));

void _convert(List<int> bytes, String path, String catalogVersion) => _convertJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>, path, catalogVersion);

void _convertJson(Map<String, dynamic> j, String path, String catalogVersion) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; BEGIN;');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  final meta = Map<String, dynamic>.of(j)
    ..remove('books')
    ..remove('entries')
    ..remove('refs')
    ..remove('places')
    ..remove('wordIndex')
    ..remove('chapters'); // главы аудиомодуля (до 3 МБ) — в payload, не в описании
  if (catalogVersion.isNotEmpty) meta['catalogVersion'] = catalogVersion; // у импортированных из файла версии каталога нет
  final type = j['type'] as String? ?? 'bible';
  if (type == 'bible') {
    meta['bookList'] = [
      for (final b in (j['books'] as List).cast<Map>())
        {'id': b['id'], 'name': b['name'], 'short': b['short'], 'chapters': (b['chapters'] as List).length},
    ];
    _convertBible(db, j);
  } else if (type == 'maps' && j['places'] is List) {
    // «Места»: таблицы с индексом по названию и по стиху (lib/features/maps/places_data.dart)
    convertPlaces(db, j);
  } else if (studyTypes.contains(type)) {
    // Словари, комментарии, параллельные места, иллюстрации: таблицы с индексами (lib/features/study/study_tables.dart)
    buildStudyTables(db, j, type);
  } else {
    // Словари, комментарии, параллельные места, карты: исходный JSON целиком — разберём по мере переноса функций
    db.execute('CREATE TABLE payload(json TEXT)');
    db.execute('INSERT INTO payload VALUES (?)', [jsonEncode(j)]);
  }
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode(meta)]);
  db.execute('COMMIT');
  db.close();
}

void _convertBible(Database db, Map<String, dynamic> j) {
  // verses.id — сквозной номер стиха в модуле: по нему же строится индекс поиска
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  final insV = db.prepare('INSERT INTO verses VALUES (?, ?, ?, ?, ?)');
  final insF = db.prepare('INSERT INTO verses_fts(rowid, plain) VALUES (?, ?)');
  final insH = db.prepare('INSERT INTO headings VALUES (?, ?, ?, ?)');
  final insX = db.prepare('INSERT INTO xrefs VALUES (?, ?, ?, ?)');
  var id = 0;
  for (final b in (j['books'] as List).cast<Map>()) {
    final book = b['id'] as String;
    final chapters = b['chapters'] as List;
    for (var c = 0; c < chapters.length; c++) {
      final verses = chapters[c] as List;
      for (var v = 0; v < verses.length; v++) {
        final raw = verses[v] as String? ?? '';
        if (raw.isEmpty) continue;
        id++;
        insV.execute([id, book, c + 1, v + 1, raw]);
        insF.execute([id, plainText(raw)]);
      }
    }
    (b['headings'] as Map?)?.forEach((k, text) {
      final p = (k as String).split(':');
      insH.execute([book, int.parse(p[0]), int.parse(p[1]), text]);
    });
    (b['xrefs'] as Map?)?.forEach((k, refs) {
      final p = (k as String).split(':');
      insX.execute([book, int.parse(p[0]), int.parse(p[1]), jsonEncode(refs)]);
    });
  }
  for (final s in [insV, insF, insH, insX]) {
    s.close();
  }
  db.execute('CREATE INDEX verses_ref ON verses(book, chapter, verse); CREATE INDEX headings_ref ON headings(book, chapter, verse);');
}
