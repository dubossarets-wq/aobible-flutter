// Аккаунт Колоса: вход через Google и синхронизация «Моих данных» (закладки, заметки, любимые, выделения, подборки,
// проповеди, планы, история чтения, настройки) с сервером aobible.app/sync — одно и то же на всех устройствах человека.
//
// Как сходится: у каждого ключа «Моих данных» запоминаем отпечаток значения на момент последней синхронизации.
// Значение изменилось с тех пор — значит, его поменяли на этом телефоне, и оно уходит на сервер. Пришло с сервера
// новое, а здесь ключ не трогали — берём серверное. Поменяли и там, и здесь — объединяем: записи списков (закладки,
// проповеди, планы) и словарей (заметки, выделения, настройки) складываются, совпадающие — из этого телефона.
// Модули (переводы, словари, аудио), место чтения и язык не переносятся.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../core/settings.dart';
import '../hub.dart';
import 'userdata.dart' show serviceKeys, snapshot;

/// Адрес сервера (в проверках — локальный)
String syncBase = 'https://aobible.app/sync';

/// Клиент OAuth Google «веб» (serverClientId): ID-токены для него принимает сервер. Пусто — вход ещё не настроен
const googleWebClientId = '';

const _stateKey = 'syncState';

/// Не переносятся между устройствами: место чтения, язык, запрос поиска, служебное этого телефона
const _localOnly = {'panes', 'lang', 'searchQuery', _stateKey, 'lateStarter', 'newsSeen', 'widgetDay'};

/// История чтения — служебный ключ для файла (большой), но в аккаунте она нужна
const _alsoSync = {'readingHistory'};

bool _syncable(String k) => !_localOnly.contains(k) && (!serviceKeys.contains(k) || _alsoSync.contains(k));

Iterable<String> _localKeys() => prefs.getKeys().where((k) => _syncable(k) && prefs.get(k) is String);

/// Отпечаток значения (FNV-1a): одинаков на всех запусках
String _fp(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return '${s.length}:${h.toRadixString(16)}';
}

// ---- объединение ----

/// Одна и та же запись списка на разных устройствах: по id / key, по месту (книга, глава, стих), иначе целиком
String _identity(Object? x) {
  if (x is Map) {
    for (final k in const ['id', 'key', 'uid']) {
      if (x[k] != null) return '$k:${x[k]}';
    }
    if (x['book'] != null) return 'ref:${x['book']}.${x['chapter']}.${x['verse']}.${x['from'] ?? ''}.${x['to'] ?? ''}';
    final r = x['ref'];
    if (r is Map) return 'ref:${r['book']}.${r['chapter']}.${r['verse']}';
  }
  return jsonEncode(x);
}

Object? _merge(Object? local, Object? remote) {
  if (local is Map && remote is Map) {
    final out = <String, Object?>{for (final e in remote.entries) '${e.key}': e.value};
    for (final e in local.entries) {
      final k = '${e.key}';
      out[k] = out.containsKey(k) ? _merge(e.value, out[k]) : e.value;
    }
    return out;
  }
  if (local is List && remote is List) {
    final seen = <String>{};
    return [
      for (final x in [...local, ...remote])
        if (seen.add(_identity(x))) x,
    ];
  }
  return local;
}

/// Значение ключа, изменённое и здесь, и на другом устройстве: записи складываются, совпадающие — из этого телефона
String mergeValues(String local, String remote) {
  try {
    final m = _merge(jsonDecode(local), jsonDecode(remote));
    return jsonEncode(m);
  } catch (_) {
    return local;
  }
}

// ---- состояние ----

class SyncState {
  SyncState({this.token, this.email, this.name, this.rev = 0, Map<String, String>? prints, this.lastSync, this.error}) : prints = prints ?? {};
  String? token, email, name, error;
  int rev;
  int? lastSync;
  Map<String, String> prints;

  bool get signedIn => token != null;

  factory SyncState.load() {
    try {
      final j = jsonDecode(prefs.getString(_stateKey) ?? '{}') as Map;
      return SyncState(
        token: j['token'] as String?,
        email: j['email'] as String?,
        name: j['name'] as String?,
        rev: (j['rev'] as num?)?.toInt() ?? 0,
        prints: {for (final e in ((j['prints'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        lastSync: (j['lastSync'] as num?)?.toInt(),
        error: j['error'] as String?,
      );
    } catch (_) {
      return SyncState();
    }
  }

  void save() => prefs.setString(_stateKey, jsonEncode({'token': token, 'email': email, 'name': name, 'rev': rev, 'prints': prints, 'lastSync': lastSync, 'error': error}));
}

/// Для экрана: вошёл ли человек, когда последний раз сошлись данные, идёт ли сейчас синхронизация
final accountState = ValueNotifier<SyncState>(SyncState.load());
final syncBusy = ValueNotifier<bool>(false);

class SyncError implements Exception {
  SyncError(this.message);
  final String message;
  @override
  String toString() => message;
}

Map<String, String> _headers(String? token) => {'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token'};

Future<Map<String, dynamic>> _call(String method, String path, {String? token, Object? body}) async {
  final uri = Uri.parse('$syncBase$path');
  final http.Response r;
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: _headers(token)).timeout(const Duration(seconds: 30));
    case 'DELETE':
      r = await http.delete(uri, headers: _headers(token)).timeout(const Duration(seconds: 30));
    default:
      r = await http.post(uri, headers: _headers(token), body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 60));
  }
  Map<String, dynamic> j;
  try {
    j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
  } catch (_) {
    j = {};
  }
  if (r.statusCode == 401 && path != '/login') throw SyncError('auth');
  if (r.statusCode != 200) throw SyncError('${j['error'] ?? r.statusCode}');
  return j;
}

// ---- синхронизация ----

Future<bool>? _running;

/// Свести данные телефона и аккаунта. true — данные на телефоне поменялись (приложению нужно перечитать их)
Future<bool> syncNow() {
  final st = accountState.value;
  if (!st.signedIn) return Future.value(false);
  return _running ??= _sync(st).whenComplete(() => _running = null);
}

Future<bool> _sync(SyncState st) async {
  syncBusy.value = true;
  var changed = false;
  try {
    // 1. Забрать новое с сервера
    var since = st.rev;
    for (;;) {
      final r = await _call('GET', '/pull?since=$since', token: st.token);
      for (final it in (r['items'] as List? ?? const []).cast<Map>()) {
        if (_applyRemote(st, '${it['key']}', it['deleted'] == true ? null : it['value'] as String?)) changed = true;
      }
      since = (r['rev'] as num?)?.toInt() ?? since;
      if (r['more'] != true) break;
    }
    st.rev = since;

    // 2. Отправить изменённое здесь (что сервер не принял, потому что у него новее, — объединить и отправить снова)
    for (var round = 0; round < 3; round++) {
      final items = <Map<String, Object?>>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      final local = {for (final k in _localKeys()) k: prefs.getString(k)!};
      local.forEach((k, v) {
        if (st.prints[k] != _fp(v)) items.add({'key': k, 'value': v, 'updated': now});
      });
      for (final k in st.prints.keys.toList()) {
        if (!local.containsKey(k) && _syncable(k)) items.add({'key': k, 'deleted': true, 'updated': now});
      }
      if (items.isEmpty) break;
      var again = false;
      for (var i = 0; i < items.length; i += 200) {
        final part = items.sublist(i, i + 200 > items.length ? items.length : i + 200);
        final r = await _call('POST', '/push', token: st.token, body: {'items': part});
        final applied = {for (final k in (r['applied'] as List? ?? const [])) '$k'};
        for (final it in part) {
          final k = it['key'] as String;
          if (!applied.contains(k)) continue;
          if (it['deleted'] == true) {
            st.prints.remove(k);
          } else {
            st.prints[k] = _fp(it['value'] as String);
          }
        }
        for (final it in (r['newer'] as List? ?? const []).cast<Map>()) {
          if (_applyRemote(st, '${it['key']}', it['deleted'] == true ? null : it['value'] as String?)) changed = true;
          again = true;
        }
      }
      if (!again) break;
    }
    st.lastSync = DateTime.now().millisecondsSinceEpoch;
    st.error = null;
  } on SyncError catch (e) {
    if (e.message == 'auth') {
      // вход больше не действует (вышли на другом устройстве, аккаунт удалён) — данные телефона остаются
      st
        ..token = null
        ..error = 'auth';
    } else {
      st.error = e.message;
    }
  } catch (e) {
    st.error = e is SocketException || e is TimeoutException ? 'offline' : '$e';
  } finally {
    st.save();
    accountState.value = SyncState.load();
    syncBusy.value = false;
  }
  return changed;
}

/// Запись с сервера (null — удалена там). true — значение на телефоне поменялось
bool _applyRemote(SyncState st, String key, String? remote) {
  if (!_syncable(key)) return false;
  final local = prefs.getString(key);
  final last = st.prints[key];
  final localChanged = local == null ? last != null : _fp(local) != last;
  if (!localChanged) {
    // здесь не трогали — берём с сервера
    if (remote == null) {
      st.prints.remove(key);
      if (local == null) return false;
      prefs.remove(key);
      return true;
    }
    st.prints[key] = _fp(remote);
    if (local == remote) return false;
    prefs.setString(key, remote);
    return true;
  }
  // поменяли и здесь, и там
  if (remote == null) {
    // там удалили, здесь изменили — изменённое важнее: уйдёт на сервер снова
    st.prints.remove(key);
    return false;
  }
  if (local == null) {
    // здесь удалили, там изменили — ничего не теряем: берём изменённое
    st.prints[key] = _fp(remote);
    prefs.setString(key, remote);
    return true;
  }
  final merged = mergeValues(local, remote);
  // отпечаток — серверного значения: объединённое отличается от него и уйдёт на сервер
  st.prints[key] = _fp(remote);
  if (merged == local) return false;
  prefs.setString(key, merged);
  return true;
}

// ---- вход и выход ----

bool _googleReady = false;

/// Вход через Google. null — вошли (и данные уже сведены), иначе текст ошибки
Future<String?> signInWithGoogle() async {
  if (googleWebClientId.isEmpty) return 'not-configured';
  try {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
      _googleReady = true;
    }
    final acc = await GoogleSignIn.instance.authenticate(scopeHint: const ['email']);
    final idToken = acc.authentication.idToken;
    if (idToken == null) return 'google';
    final r = await _call('POST', '/login', body: {'idToken': idToken, 'device': Platform.isAndroid ? 'Android' : Platform.operatingSystem});
    // первое объединение с аккаунтом: прежде — копия данных телефона (её можно вернуть в «Моих данных»)
    snapshot('перед первой синхронизацией с аккаунтом');
    final st = SyncState(token: r['token'] as String?, email: (r['user'] as Map?)?['email'] as String?, name: (r['user'] as Map?)?['name'] as String?);
    st.save();
    accountState.value = st;
    if (await syncNow()) Hub.restartApp?.call();
    return accountState.value.error;
  } on GoogleSignInException catch (e) {
    return e.code == GoogleSignInExceptionCode.canceled ? 'canceled' : 'google';
  } on SyncError catch (e) {
    return e.message;
  } catch (e) {
    return e is SocketException || e is TimeoutException ? 'offline' : '$e';
  }
}

/// Выйти на этом телефоне: данные остаются и здесь, и в аккаунте
Future<void> signOut() async {
  final st = accountState.value;
  if (st.token != null) {
    try {
      await _call('POST', '/logout', token: st.token);
    } catch (_) {}
  }
  try {
    if (_googleReady) await GoogleSignIn.instance.signOut();
  } catch (_) {}
  prefs.remove(_stateKey);
  accountState.value = SyncState();
}

/// Удалить аккаунт и все данные на сервере (на этом телефоне данные остаются). null — удалено, иначе ошибка
Future<String?> deleteAccount() async {
  final st = accountState.value;
  if (st.token == null) return null;
  try {
    await _call('DELETE', '/account', token: st.token);
  } on SyncError catch (e) {
    if (e.message != 'auth') return e.message;
  } catch (e) {
    return e is SocketException || e is TimeoutException ? 'offline' : '$e';
  }
  await signOut();
  return null;
}

// ---- когда сводить ----

bool _reloadOnResume = false;
int _lastAuto = 0;

class _Lifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!accountState.value.signedIn) return;
    if (state == AppLifecycleState.paused) {
      // ушли из приложения — отправить сделанное; пришедшее применится при возвращении
      syncNow().then((c) => _reloadOnResume = _reloadOnResume || c);
    } else if (state == AppLifecycleState.resumed) {
      if (_reloadOnResume) {
        _reloadOnResume = false;
        Hub.restartApp?.call();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAuto < 60000) return;
      _lastAuto = now;
      syncNow().then((c) {
        if (c) Hub.restartApp?.call();
      });
    }
  }
}

bool _watching = false;

/// Запуск приложения: свести данные; пришло новое — приложение перечитывает всё. Дальше — при уходе и возвращении
Future<void> syncOnStart() async {
  if (!_watching) {
    _watching = true;
    WidgetsBinding.instance.addObserver(_Lifecycle());
  }
  if (!accountState.value.signedIn) return;
  _lastAuto = DateTime.now().millisecondsSinceEpoch;
  if (await syncNow()) Hub.restartApp?.call();
}

/// Проверка с локальным сервером (wrangler dev --var ALLOW_TEST_LOGIN:1): вход без Google
@visibleForTesting
Future<void> debugSignInTest(String name) async {
  final r = await _call('POST', '/login', body: {'test': name, 'device': 'test'});
  final st = SyncState(token: r['token'] as String?, email: (r['user'] as Map?)?['email'] as String?);
  st.save();
  accountState.value = st;
}
