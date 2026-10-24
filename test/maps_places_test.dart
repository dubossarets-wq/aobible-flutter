// «Места»: установка в таблицы, поиск по названию, место по слову стиха, разбор ссылок, масштаб карты.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/features/maps/map_pane.dart';
import 'package:aobible/features/maps/places_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final fake = {
    'format': 'aob-module', 'type': 'maps', 'id': 'bible-places', 'name': 'Места', 'license': 'CC BY 4.0',
    'places': [
      {'id': 'hebron', 'name': 'Хеврон', 'lat': 31.53, 'lng': 35.09, 'type': 'населённый пункт', 'confidence': 90, 'modern': 'Эль-Халиль', 'description': 'Город', 'stems': ['хевр'], 'refs': ['Josh.14.15', 'Gen.23.2']},
      {'id': 'galilee', 'name': 'Галилея', 'lat': 32.8, 'lng': 35.5, 'type': 'область', 'confidence': 70, 'stems': ['гали'], 'refs': ['Matt.4.15']},
      {'id': 'yordan', 'name': 'Иордан', 'lat': 32.0, 'lng': 35.5, 'type': 'река', 'stems': ['иорд'], 'refs': ['Matt.3.13-14']},
    ],
  };

  late Directory dir;

  Future<void> install(Map<String, dynamic> j) async {
    final path = '${dir.path}/${j['id']}.db';
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
    db.execute('PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; BEGIN;'); // как при настоящей установке
    convertPlaces(db, j);
    final meta = Map<String, dynamic>.of(j)..remove('places');
    db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode(meta)]);
    db.execute('COMMIT');
    db.close();
    await ModuleStore.initAt(dir);
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Books.load();
    dir = Directory.systemTemp.createTempSync('aob_places');
    await install(fake);
  });

  test('слово стиха → место (по основе названия и списку упоминаний)', () {
    expect(PlaceStore.forWord('Хеврону', const VerseRef('Josh', 14, 15)).map((p) => p.id), ['hebron']);
    expect(PlaceStore.forWord('Хеврон,', const VerseRef('Josh', 14, 15)).length, 1);
    // другой стих — места нет, даже если слово совпадает
    expect(PlaceStore.forWord('Хеврон', const VerseRef('Josh', 14, 16)), isEmpty);
    // стих тот же, а слово — другое
    expect(PlaceStore.forWord('отдали', const VerseRef('Josh', 14, 15)), isEmpty);
  });

  test('поиск по названию: регистр, «ё», минимум 2 буквы, спецсимволы', () {
    expect(PlaceStore.search('ХЕВР').map((p) => p.name), ['Хеврон']);
    expect(PlaceStore.search('х'), isEmpty);
    expect(PlaceStore.search('%'), isEmpty);
    expect(PlaceStore.search('ан').map((p) => p.id), ['yordan']);
    expect(PlaceStore.count, 3);
  });

  test('карточка: поля и стихи, диапазон берётся с первого стиха', () {
    final p = PlaceStore.search('Иордан').single;
    expect(p.verses, [const VerseRef('Matt', 3, 13)]);
    expect(p.confidence, isNull);
    final h = PlaceStore.search('Хеврон').single;
    expect(h.confidence, 90);
    expect(h.modern, 'Эль-Халиль');
    expect(h.moduleName, 'Места');
    expect(parseOsis('мусор'), isNull);
  });

  test('масштаб по типу места', () {
    expect(zoomFor('область'), 6.5);
    expect(zoomFor('река'), 8.5);
    expect(zoomFor('населённый пункт'), 11);
  });

  test('слои подложки: заливки отличаются от подписей и границ', () {
    expect(isFillLayer('water'), true);
    expect(isFillLayer('landcover_wood'), true);
    expect(isFillLayer('background'), true);
    expect(isFillLayer('water_name'), false);
    expect(isFillLayer('building'), false);
    expect(isFillLayer('road_major'), false);
  });

  // Настоящие данные из веб-проекта (если есть рядом): 1321 место, скорость запросов
  test('настоящий bible-places.json', () async {
    final f = File(r'E:\AO Bible\public\modules\bible-places.json');
    if (!f.existsSync()) return;
    final j = jsonDecode(utf8.decode(f.readAsBytesSync())) as Map<String, dynamic>;
    final real = Directory.systemTemp.createTempSync('aob_places_real');
    final saved = dir;
    dir = real;
    final sw = Stopwatch()..start();
    await install(j);
    // ignore: avoid_print
    print('установка мест: ${sw.elapsedMilliseconds} мс');
    expect(PlaceStore.count, (j['places'] as List).length);
    final p = (j['places'] as List).cast<Map>().firstWhere((p) => (p['refs'] as List?)?.isNotEmpty == true && (p['stems'] as List?)?.isNotEmpty == true);
    final v = parseOsis((p['refs'] as List).first as String)!;
    sw.reset();
    final hit = PlaceStore.forWord('${(p['stems'] as List).first}ы', v);
    // ignore: avoid_print
    print('место по слову: ${sw.elapsedMicroseconds} мкс');
    expect(hit.any((x) => x.id == p['id']), true);
    expect(PlaceStore.search('Вифлеем'), isNotEmpty);
    dir = saved;
    await ModuleStore.initAt(saved);
  });
}
