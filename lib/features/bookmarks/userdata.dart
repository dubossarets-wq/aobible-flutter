// «Мои данные»: всё пользовательское — в файл и обратно (core/dataFile.js) и резервные копии (core/backup.js).
// Формат файла тот же, что у веб-версии: {format:'aob-userdata', version:1, exportedAt, data:{ключ: строка JSON}},
// поэтому файл из веб-версии открывается здесь и наоборот. Модули (переводы, словари) в файл не входят.
// Копии лежат в prefs ('backups'): последние 5, не больше ~1,5 млн символов; делаются перед каждым восстановлением.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import 'legacy.dart';
import 'marks.dart';

const dataFormat = 'aob-userdata';

/// Служебные ключи: в файл и копии не попадают и при восстановлении не трогаются
/// (копии, сведения этого телефона — скачанные книги и аудио, ход переноса)
const serviceKeys = {'backups', 'offlineAudio', 'autoAudio', 'lastBuild', 'activeBuild', 'autoUpdate2', 'knownBuilds', 'notifiedBuild', 'lateStarter', 'bootstrapped', 'errorLog', 'playUpdateNotified', legacyDoneKey, legacyDumpKey};
const _maxBackups = 5;
const _budget = 1500000;

Iterable<String> _userKeys() => prefs.getKeys().where((k) => !serviceKeys.contains(k) && prefs.get(k) is String);

/// Значение ключа в виде, как оно лежит в localStorage веб-версии (язык там — JSON-строка, расположение панелей не переносим)
Map<String, String> _asWeb() => {
      for (final k in _userKeys())
        if (k != 'panes') k: k == 'lang' ? jsonEncode(prefs.getString(k)) : prefs.getString(k)!,
    };

Map<String, dynamic> exportData() => {'format': dataFormat, 'version': 1, 'exportedAt': DateTime.now().toUtc().toIso8601String(), 'data': _asWeb()};

int _count(Object? raw) {
  try {
    final v = jsonDecode(raw is String ? raw : 'null');
    return v is List ? v.length : (v is Map ? v.length : 0);
  } catch (_) {
    return 0;
  }
}

/// Что лежит в файле — показать перед восстановлением
Map<String, Object?> describeData(Map<String, dynamic> file) {
  final d = (file['data'] as Map?) ?? const {};
  return {
    'at': file['exportedAt'] != null ? DateTime.tryParse('${file['exportedAt']}')?.toLocal() : null,
    for (final k in ['bookmarks', 'notes', 'favorites', 'highlights', 'plans', 'sermons']) k: _count(d[k]),
  };
}

Map<String, dynamic> parseDataFile(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    throw FormatException(t('Это не файл с данными AO Bible.'));
  }
  if (json is! Map || json['format'] != dataFormat || json['data'] is! Map) throw FormatException(t('Это не файл с данными AO Bible.'));
  return json.cast<String, dynamic>();
}

/// Из записи файла/копии — в то, что кладём в prefs (язык — обычной строкой, панели — в наш формат)
MapEntry<String, String>? _toPrefs(String k, Object? v) {
  if (v is! String || serviceKeys.contains(k)) return null;
  if (k == 'lang') {
    try {
      final d = jsonDecode(v);
      return MapEntry(k, d is String ? d : v);
    } catch (_) {
      return MapEntry(k, v);
    }
  }
  if (k == 'panes') {
    final p = convertWebPanes(v);
    return p == null ? null : MapEntry(k, p);
  }
  return MapEntry(k, v);
}

// --- резервные копии ---

List<Map<String, dynamic>> _backups() {
  try {
    return [for (final b in jsonDecode(prefs.getString('backups') ?? '[]') as List) if (b is Map && b['data'] is Map) b.cast<String, dynamic>()];
  } catch (_) {
    return [];
  }
}

/// Копия всех данных человека (причина хранится по-русски — переводим при показе)
void snapshot(String reason) {
  try {
    final data = {for (final k in _userKeys()) k: prefs.getString(k)!};
    if (data.isEmpty) return;
    var list = [
      {'at': DateTime.now().millisecondsSinceEpoch, 'build': '', 'reason': reason, 'data': data},
      ..._backups(),
    ].take(_maxBackups).toList();
    while (list.length > 1 && jsonEncode(list).length > _budget) {
      list = list.sublist(0, list.length - 1);
    }
    prefs.setString('backups', jsonEncode(list));
  } catch (_) {
    // нет места или хранилище недоступно — данные важнее копий
  }
}

class BackupInfo {
  const BackupInfo(this.at, this.reason, this.bookmarks, this.notes, this.favorites);
  final int at;
  final String reason;
  final int bookmarks, notes, favorites;
}

List<BackupInfo> listBackups() => [
      for (final b in _backups())
        BackupInfo((b['at'] as num).toInt(), '${b['reason'] ?? ''}', _count((b['data'] as Map)['bookmarks']), _count((b['data'] as Map)['notes']), _count((b['data'] as Map)['favorites'])),
    ];

String reasonLabel(String reason) {
  final m = RegExp(r'^(до обновления с версии|перед переходом на версию) (.+)$').firstMatch(reason);
  if (m != null) return m.group(1)!.startsWith('до') ? t('до обновления с версии {v}', {'v': m.group(2)!}) : t('перед переходом на версию {v}', {'v': m.group(2)!});
  return reason.isEmpty ? '' : t(reason);
}

/// Заменить данные человека целиком; если запись оборвалась — вернуть, как было
bool replaceAll(Map<String, String> entries) {
  final before = {for (final k in _userKeys()) k: prefs.getString(k)!};
  try {
    for (final k in before.keys) {
      prefs.remove(k);
    }
    entries.forEach((k, v) => prefs.setString(k, v));
    return true;
  } catch (_) {
    for (final k in _userKeys().toList()) {
      prefs.remove(k);
    }
    before.forEach((k, v) => prefs.setString(k, v));
    return false;
  }
}

/// Новые значения уже в prefs — заставить приложение прочитать их заново
Future<void> reloadAfterReplace(WidgetRef ref) async {
  ref.invalidate(settingsProvider);
  ref.invalidate(panesProvider);
  ref.read(marksProvider.notifier).reload();
  await setLang(prefs.getString('lang') ?? 'ru');
}

/// Восстановление из файла: сначала копия нынешних данных, потом замена
bool importData(Map<String, dynamic> json) {
  snapshot('перед восстановлением из файла');
  final incoming = <String, String>{};
  (json['data'] as Map).forEach((k, v) {
    final e = _toPrefs('$k', v);
    if (e != null) incoming[e.key] = e.value;
  });
  return replaceAll(incoming);
}

bool restoreBackup(int at) {
  final b = _backups().where((x) => x['at'] == at).firstOrNull;
  if (b == null) return false;
  snapshot('перед восстановлением из копии');
  return replaceAll({for (final e in (b['data'] as Map).entries) if (e.value is String && !serviceKeys.contains(e.key)) '${e.key}': e.value as String});
}
