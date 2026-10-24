// Перенос данных из старого приложения (Capacitor, Google Play): его данные лежат в localStorage встроенного
// браузера под адресом https://localhost, ключи с префиксом «aob.». Новое приложение — то же приложение Google Play
// (тот же пакет), поэтому хранилище браузера на телефоне то же самое: открываем невидимый WebView с этим адресом,
// читаем localStorage и раскладываем в prefs. Один раз, только на Android. Старые данные не удаляем — при любой
// ошибке перенос просто повторится при следующем запуске, а полная копия всего прочитанного лежит в prefs ('legacyWeb').
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'marks.dart';

const legacyDoneKey = 'legacyMigrated';
const legacyDumpKey = 'legacyWeb';
const _origin = 'https://localhost/';

/// Ключи старого приложения, которые не переносим: копии, сведения о версиях, скачанное на тот телефон
const _skip = {'backups', 'offlineAudio', 'autoAudio', 'lastBuild', 'activeBuild', 'autoUpdate2', 'knownBuilds', 'notifiedBuild', 'lateStarter', 'bootstrapped', 'errorLog', 'playUpdateNotified', 'welcomePending', 'widgetDay'};

/// Читает все ключи с префиксом «aob.» и отдаёт одной JSON-строкой через канал AOB
const _readJs = '''
(function () {
  try {
    var o = {};
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (k && k.indexOf('aob.') === 0) o[k] = localStorage.getItem(k);
    }
    AOB.postMessage(JSON.stringify(o));
  } catch (e) {
    AOB.postMessage('ERR:' + e);
  }
})();
''';

/// Содержимое localStorage → то, что переносим: без префикса, только строки, без служебных
Map<String, String> filterLegacy(Map<String, dynamic> localStorage) => {
      for (final e in localStorage.entries)
        if (e.key.startsWith('aob.') && e.value is String && !_skip.contains(e.key.substring(4))) e.key.substring(4): e.value as String,
    };

/// Расположение панелей веб-версии ([{kind, moduleId, ref{book,chapter,verse}, history…}, null]) → наше [{moduleId, ref}]
String? convertWebPanes(String raw, {bool Function(String moduleId)? known, String fallback = 'rst-plus'}) {
  try {
    final out = <Map<String, dynamic>>[];
    for (final p in jsonDecode(raw) as List) {
      if (p is! Map || (p['kind'] != null && p['kind'] != 'bible')) continue;
      var id = p['moduleId'];
      final r = p['ref'] is Map ? refOf(p['ref'] as Map) : null;
      if (id is! String || r == null) continue;
      if (known != null && !known(id)) id = fallback;
      out.add({'moduleId': id, 'ref': r.toJson()});
      if (out.length == 2) break;
    }
    return out.isEmpty ? null : jsonEncode(out);
  } catch (_) {
    return null;
  }
}

bool _empty(String? v) => v == null || v == '[]' || v == '{}' || v == 'null' || v.isEmpty;

/// Разложить перенесённое по prefs. Язык, настройки и панели — старые (на первом запуске своих ещё нет);
/// остальное — только если в новом приложении там пусто (не затираем то, что человек уже успел сделать).
/// Возвращает, сколько ключей записано.
int applyLegacy(Map<String, String> data, {bool Function(String moduleId)? known}) {
  var n = 0;
  void put(String k, String v) {
    prefs.setString(k, v);
    n++;
  }

  data.forEach((k, v) {
    switch (k) {
      case 'lang':
      case 'searchQuery': // в старом приложении это JSON-строка, у нас — обычная
        try {
          final d = jsonDecode(v);
          if (d is String && d.isNotEmpty && (k == 'lang' || _empty(prefs.getString(k)))) put(k, d);
        } catch (_) {}
      case 'settings':
        try {
          final old = (jsonDecode(v) as Map).cast<String, dynamic>();
          final cur = prefs.getString('settings');
          final now = cur == null ? <String, dynamic>{} : (jsonDecode(cur) as Map).cast<String, dynamic>();
          put(k, jsonEncode({...now, ...old}));
        } catch (_) {}
      case 'panes':
        final p = convertWebPanes(v, known: known);
        if (p != null) put(k, p);
      default:
        if (_empty(prefs.getString(k)) && !_empty(v)) put(k, v);
    }
  });
  return n;
}

/// Прочитать localStorage старого приложения. null — не удалось (повторим в другой раз); пусто — старых данных нет.
Future<Map<String, String>?> readOldStorage({Duration timeout = const Duration(seconds: 25)}) async {
  final done = Completer<String>();
  final c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('AOB', onMessageReceived: (m) => done.isCompleted ? null : done.complete(m.message));
  c.setNavigationDelegate(NavigationDelegate(
    onPageFinished: (_) async {
      try {
        await c.runJavaScript(_readJs);
      } catch (e) {
        if (!done.isCompleted) done.complete('ERR:$e');
      }
    },
    onWebResourceError: (e) => done.isCompleted ? null : done.complete('ERR:${e.description}'),
  ));
  try {
    // Страница своя и пустая, но адрес https://localhost/ — значит, источник тот же, что у старого приложения,
    // и localStorage — его; в сеть при этом никто не ходит
    await c.loadHtmlString('<!doctype html><html><body></body></html>', baseUrl: _origin);
    final msg = await done.future.timeout(timeout);
    if (msg.startsWith('ERR:')) return null;
    return filterLegacy((jsonDecode(msg) as Map).cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

/// Hub.afterStart: перенос при первом запуске (один раз). Ничего не бросает наружу.
Future<void> migrateFromOldApp(WidgetRef ref) async {
  try {
    if (!Platform.isAndroid || prefs.getBool(legacyDoneKey) == true) return;
    final data = await readOldStorage();
    if (data == null) return; // не вышло — попробуем при следующем запуске
    if (data.isNotEmpty) {
      await prefs.setString(legacyDumpKey, jsonEncode(data)); // сначала — полная копия прочитанного
      applyLegacy(data, known: (id) => ModuleStore.instance.get(id) != null);
    }
    await prefs.setBool(legacyDoneKey, true);
    if (data.isNotEmpty) {
      ref.invalidate(settingsProvider);
      ref.invalidate(panesProvider);
      ref.read(marksProvider.notifier).reload();
      await setLang(prefs.getString('lang') ?? 'ru');
    }
  } catch (e) {
    debugPrint('Перенос данных не удался: $e');
  }
}

/// Для Hub: ссылка на запуск
void registerLegacy() => Hub.afterStart.add(migrateFromOldApp);
