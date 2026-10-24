// «Мои данные» и перенос из старого приложения: файл, копии, разбор localStorage веб-версии.
import 'dart:convert';

import 'package:aobible/core/settings.dart';
import 'package:aobible/features/bookmarks/legacy.dart';
import 'package:aobible/features/bookmarks/userdata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> fresh(Map<String, Object> init) async {
  SharedPreferences.setMockInitialValues(init);
  prefs = await SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('файл: выгрузка в формате веб-версии и обратно', () async {
    await fresh({
      'bookmarks': '[{"book":"John","chapter":3,"verse":16,"text":"t","at":1}]',
      'notes': '{"John.3.16":{"text":"n","label":"","at":1,"updated":1}}',
      'lang': 'uk',
      'panes': '[{"moduleId":"rst-plus","ref":{"book":"Gen","chapter":1,"verse":1}}]',
      'backups': '[]',
      'offlineAudio': '{}',
    });
    final f = exportData();
    expect(f['format'], 'aob-userdata');
    expect(f['version'], 1);
    final data = f['data'] as Map;
    expect(data['lang'], '"uk"'); // как в localStorage веб-версии
    expect(data.containsKey('panes'), isFalse);
    expect(data.containsKey('backups'), isFalse);
    expect(data.containsKey('offlineAudio'), isFalse);
    expect(describeData(f)['bookmarks'], 1);
    expect(describeData(f)['notes'], 1);

    // на «другом телефоне»
    await fresh({'bookmarks': '[]', 'sermons': '[1,2]'});
    final parsed = parseDataFile(jsonEncode(f));
    expect(importData(parsed), isTrue);
    expect(prefs.getString('lang'), 'uk');
    expect(jsonDecode(prefs.getString('bookmarks')!), hasLength(1));
    expect(prefs.getString('sermons'), isNull); // всё заменяется данными из файла
    // перед заменой сделана копия, и в ней прежнее
    final b = listBackups();
    expect(b, hasLength(1));
    expect(b.first.reason, 'перед восстановлением из файла');
  });

  test('файл не от AO Bible отвергается', () {
    expect(() => parseDataFile('не json'), throwsFormatException);
    expect(() => parseDataFile('{"format":"x","data":{}}'), throwsFormatException);
    expect(() => parseDataFile('{"format":"aob-userdata"}'), throwsFormatException);
  });

  test('копии: не больше пяти, восстановление возвращает данные', () async {
    await fresh({'bookmarks': '[1]', 'notes': '{}'});
    for (var i = 0; i < 7; i++) {
      snapshot('причина $i');
    }
    expect(listBackups(), hasLength(5));
    await prefs.setString('bookmarks', '[1,2,3]');
    final first = listBackups().first;
    expect(first.bookmarks, 1);
    expect(restoreBackup(first.at), isTrue);
    expect(prefs.getString('bookmarks'), '[1]');
    expect(listBackups().first.reason, 'перед восстановлением из копии');
    expect(restoreBackup(123), isFalse);
  });

  test('перенос: localStorage старого приложения → prefs', () async {
    await fresh({'lang': 'ru'});
    final ls = <String, dynamic>{
      'aob.bookmarks': '[{"book":"Ps","chapter":22,"verse":1,"text":"x","at":5}]',
      'aob.notes': '{"Ps.22.1":{"text":"n","at":1}}',
      'aob.lang': '"en"',
      'aob.settings': '{"theme":"dark","fontSize":22}',
      'aob.searchQuery': '"love"',
      'aob.sermons': '[{"id":"a"}]',
      'aob.backups': '[{"huge":true}]',
      'aob.offlineAudio': '{}',
      'other.key': 'x',
      'aob.number': 5,
    };
    final data = filterLegacy(ls);
    expect(data.keys, containsAll(['bookmarks', 'notes', 'lang', 'settings', 'sermons']));
    expect(data.keys, isNot(contains('backups')));
    expect(data.keys, isNot(contains('offlineAudio')));
    expect(data.keys, isNot(contains('other.key')));
    expect(data.keys, isNot(contains('number')));

    final n = applyLegacy(data);
    expect(n, greaterThan(4));
    expect(prefs.getString('lang'), 'en');
    expect(prefs.getString('searchQuery'), 'love');
    expect(jsonDecode(prefs.getString('settings')!), {'theme': 'dark', 'fontSize': 22});
    expect(prefs.getString('sermons'), '[{"id":"a"}]');
    expect(jsonDecode(prefs.getString('bookmarks')!), hasLength(1));
  });

  test('перенос: то, что человек уже успел сделать в новом приложении, не затирается', () async {
    await fresh({'bookmarks': '[{"book":"Gen","chapter":1,"verse":1,"text":"новое","at":9}]', 'notes': '{}', 'settings': '{"fontSize":30,"showStrongs":true}'});
    applyLegacy({'bookmarks': '[{"book":"Ps","chapter":1,"verse":1,"text":"старое","at":1}]', 'notes': '{"Ps.1.1":{"text":"a","at":1}}', 'settings': '{"fontSize":22}'});
    expect((jsonDecode(prefs.getString('bookmarks')!) as List).single['text'], 'новое');
    expect(jsonDecode(prefs.getString('notes')!), hasLength(1)); // пусто было — заполнили
    expect(jsonDecode(prefs.getString('settings')!), {'fontSize': 22, 'showStrongs': true}); // настройки старые, новые ключи сохранены
  });

  test('панели веб-версии → наши: вторая пустая и не-библейские пропускаются, неизвестный перевод заменяется', () {
    const web = '[{"kind":"bible","moduleId":"kjv","ref":{"book":"John","chapter":3,"verse":16},"history":[],"hIndex":0,"nav":4},'
        '{"kind":"map","moduleId":"x","ref":{"book":"Gen","chapter":1,"verse":1}},null]';
    final out = jsonDecode(convertWebPanes(web, known: (id) => id == 'rst-plus')!) as List;
    expect(out, hasLength(1));
    expect(out.single['moduleId'], 'rst-plus');
    expect(out.single['ref'], {'book': 'John', 'chapter': 3, 'verse': 16});
    expect(convertWebPanes('[null,null]'), isNull);
    expect(convertWebPanes('мусор'), isNull);
  });
}
