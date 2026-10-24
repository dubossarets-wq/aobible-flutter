// Таблицы для словарей, комментариев, параллельных мест и иллюстраций: при установке модуля исходный JSON
// раскладывается по таблицам с индексами (вместо одного большого JSON в payload) — выбор статьи, стиха, слова
// занимает доли миллисекунды. Функция вызывается из lib/core/modules.dart (в отдельном потоке) и из
// миграции старых установок (study_data.dart).
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Типы модулей, которые разбираем по таблицам
const studyTypes = {'dictionary', 'commentary', 'crossrefs', 'illustrations'};

/// Таблицы уже построены (маркер st_ready)
bool hasStudyTables(Database db) => db.select("SELECT 1 FROM sqlite_master WHERE name = 'st_ready'").isNotEmpty;

/// Ключ «Gen.1.1», «Josh.14.1-5», «Gen.1.1-2.3» → (книга, глава, первый стих); null — не ссылка
(String, int, int)? parseOsisStart(String key) {
  final a = key.split('-').first.split('.');
  if (a.length < 2) return null;
  final c = int.tryParse(a[1]);
  if (c == null) return null;
  final v = a.length > 2 ? int.tryParse(a[2]) : 1;
  if (v == null) return null;
  return (a[0], c, v);
}

void buildStudyTables(Database db, Map<String, dynamic> j, String type) {
  db.execute('CREATE TABLE st_ready(v INTEGER)');
  db.execute('INSERT INTO st_ready VALUES (1)');
  switch (type) {
    case 'dictionary':
      _dictionary(db, j);
    case 'commentary':
      _commentary(db, j);
    case 'crossrefs':
      _crossrefs(db, j);
    case 'illustrations':
      _illustrations(db, j);
  }
}

void _dictionary(Database db, Map<String, dynamic> j) {
  // Ключ — номер Стронга («H7225») или слово в нижнем регистре; диапазон по ключу — поиск слов с той же основой
  db.execute('CREATE TABLE dict(key TEXT PRIMARY KEY, word TEXT, json TEXT) WITHOUT ROWID');
  final ins = db.prepare('INSERT OR REPLACE INTO dict VALUES (?, ?, ?)');
  final entries = (j['entries'] as Map?) ?? const {};
  entries.forEach((k, e) {
    if (e is! Map) return;
    ins.execute([k as String, (e['word'] ?? e['lemma'] ?? k).toString(), jsonEncode(e)]);
  });
  ins.close();
  // Обратный индекс «словоформа → номера Стронга» (симфония RST+)
  final wi = j['wordIndex'];
  if (wi is Map) {
    db.execute('CREATE TABLE windex(word TEXT PRIMARY KEY, json TEXT) WITHOUT ROWID');
    final w = db.prepare('INSERT OR REPLACE INTO windex VALUES (?, ?)');
    wi.forEach((k, v) => w.execute([k as String, jsonEncode(v)]));
    w.close();
  }
}

void _commentary(Database db, Map<String, dynamic> j) {
  // Статья лежит у первого стиха своего диапазона (там же и пометка в тексте)
  db.execute('CREATE TABLE comm(book TEXT, chapter INTEGER, verse INTEGER, key TEXT, title TEXT, text TEXT)');
  final ins = db.prepare('INSERT INTO comm VALUES (?, ?, ?, ?, ?, ?)');
  final entries = (j['entries'] as Map?) ?? const {};
  entries.forEach((k, e) {
    final p = parseOsisStart(k as String);
    if (p == null) return;
    final String title, text;
    if (e is Map) {
      title = (e['title'] ?? '').toString();
      text = (e['text'] ?? '').toString();
    } else {
      title = '';
      text = e.toString();
    }
    ins.execute([p.$1, p.$2, p.$3, k, title, text]);
  });
  ins.close();
  db.execute('CREATE INDEX comm_ref ON comm(book, chapter, verse)');
}

void _crossrefs(Database db, Map<String, dynamic> j) {
  db.execute('CREATE TABLE xr(book TEXT, chapter INTEGER, verse INTEGER, n INTEGER, refs TEXT)');
  final ins = db.prepare('INSERT INTO xr VALUES (?, ?, ?, ?, ?)');
  final refs = (j['refs'] as Map?) ?? const {};
  refs.forEach((k, v) {
    final p = parseOsisStart(k as String);
    if (p == null || v is! List) return;
    ins.execute([p.$1, p.$2, p.$3, v.length, jsonEncode(v)]);
  });
  ins.close();
  db.execute('CREATE INDEX xr_ref ON xr(book, chapter, verse)');
}

void _illustrations(Database db, Map<String, dynamic> j) {
  db.execute('CREATE TABLE illus(book TEXT, chapter INTEGER, verse INTEGER, json TEXT)');
  final ins = db.prepare('INSERT INTO illus VALUES (?, ?, ?, ?)');
  final entries = (j['entries'] as Map?) ?? const {};
  entries.forEach((k, v) {
    final p = parseOsisStart(k as String);
    if (p == null) return;
    ins.execute([p.$1, p.$2, p.$3, jsonEncode(v)]);
  });
  ins.close();
  db.execute('CREATE INDEX illus_ref ON illus(book, chapter, verse)');
}
