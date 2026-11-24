// Аккаунт Колоса: объединение данных и синхронизация двух «телефонов» через локальный сервер
// (worker/sync: npx wrangler dev -c ../sync/wrangler.toml --local --port 8799 --var ALLOW_TEST_LOGIN:1).
// Сервер не запущен — проверки синхронизации пропускаются, объединение проверяется всегда.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolos/core/settings.dart';
import 'package:kolos/features/bookmarks/account_sync.dart';

Future<void> device(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  prefs = await SharedPreferences.getInstance();
  accountState.value = SyncState.load();
}

Map<String, String> dump() => {for (final k in prefs.getKeys()) if (prefs.get(k) is String) k: prefs.getString(k)!};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('объединение: списки складываются по записи, словари — по ключу, совпадающее — с этого телефона', () {
    final m = jsonDecode(mergeValues(
      jsonEncode({'Gen.1.1': {'text': 'здесь'}, 'Jn.3.16': {'text': 'а'}}),
      jsonEncode({'Gen.1.1': {'text': 'там'}, 'Rom.8.28': {'text': 'б'}}),
    )) as Map;
    expect(m.keys.toSet(), {'Gen.1.1', 'Jn.3.16', 'Rom.8.28'});
    expect(m['Gen.1.1']['text'], 'здесь');
    final l = jsonDecode(mergeValues(
      jsonEncode([{'book': 'Gen', 'chapter': 1, 'verse': 1}, {'id': 's1', 'title': 'здесь'}]),
      jsonEncode([{'book': 'Gen', 'chapter': 1, 'verse': 1}, {'id': 's1', 'title': 'там'}, {'id': 's2'}]),
    )) as List;
    expect(l.length, 3);
    expect(l[1]['title'], 'здесь');
    // вложенные словари (журнал чтения): дни обоих телефонов
    final d = jsonDecode(mergeValues(jsonEncode({'days': {'2026-11-20': 3}}), jsonEncode({'days': {'2026-11-21': 2}}))) as Map;
    expect((d['days'] as Map).length, 2);
    expect(mergeValues('не json', '{}'), 'не json');
  });

  group('синхронизация двух телефонов', () {
    var up = false;
    setUpAll(() async {
      // flutter_test подменяет сеть заглушкой — для этой проверки нужна настоящая (локальный сервер)
      HttpOverrides.global = null;
      syncBase = 'http://127.0.0.1:8799/sync';
      try {
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final r = await (await c.getUrl(Uri.parse('$syncBase/me'))).close();
        up = r.statusCode == 401;
      } catch (_) {
        up = false;
      }
    });

    test('закладки, заметки, настройки и удаление сходятся', () async {
      if (!up) {
        markTestSkipped('локальный сервер не запущен');
        return;
      }
      final who = 'flutter${DateTime.now().millisecondsSinceEpoch}';

      // телефон A: свои закладки и заметки, место чтения (не переносится)
      await device({
        'bookmarks': jsonEncode([{'book': 'Gen', 'chapter': 1, 'verse': 1}]),
        'notes': jsonEncode({'Gen.1.1': {'text': 'A'}}),
        'panes': '[{"moduleId":"rst"}]',
      });
      await debugSignInTest(who);
      expect(await syncNow(), false);
      expect(accountState.value.error, isNull);
      final a = dump();

      // телефон B: другие закладки и заметки, свои настройки
      await device({
        'bookmarks': jsonEncode([{'book': 'Jn', 'chapter': 3, 'verse': 16}]),
        'notes': jsonEncode({'Jn.3.16': {'text': 'B'}}),
        'settings': jsonEncode({'fontSize': 22}),
        'panes': '[{"moduleId":"kjv"}]',
      });
      await debugSignInTest(who);
      expect(await syncNow(), true); // пришло с A
      final bm = jsonDecode(prefs.getString('bookmarks')!) as List;
      expect(bm.length, 2, reason: 'закладки обоих телефонов');
      expect((jsonDecode(prefs.getString('notes')!) as Map).keys.toSet(), {'Gen.1.1', 'Jn.3.16'});
      expect(prefs.getString('panes'), '[{"moduleId":"kjv"}]', reason: 'место чтения своё');
      // B удаляет настройку «settings» целиком и меняет заметку
      prefs.remove('settings');
      prefs.setString('notes', jsonEncode({'Gen.1.1': {'text': 'A'}, 'Jn.3.16': {'text': 'B2'}}));
      await syncNow();
      final b = dump();

      // снова A: получает всё с B
      await device(a);
      expect(await syncNow(), true);
      expect((jsonDecode(prefs.getString('bookmarks')!) as List).length, 2);
      expect((jsonDecode(prefs.getString('notes')!) as Map)['Jn.3.16']['text'], 'B2');
      expect(prefs.getString('panes'), '[{"moduleId":"rst"}]');
      // повторная синхронизация ничего не меняет
      expect(await syncNow(), false);

      // B ещё раз — ничего нового
      await device(b);
      expect(await syncNow(), false);
    });
  });
}
