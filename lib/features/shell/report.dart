// «Сообщить о проблеме» (src/core/errorLog.js): последние ошибки приложения хранятся только на устройстве и
// попадают в письмо, которое человек сам видит и отправляет. Никуда автоматически ничего не уходит.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'about_sheet.dart';
import 'sheet.dart';

const _key = 'errorLog';
const _max = 12;

void _remember(Object? text) {
  final msg = '$text'.replaceAll(RegExp(r'\s+'), ' ');
  if (msg.isEmpty) return;
  final short = msg.length > 220 ? msg.substring(0, 220) : msg;
  final raw = prefs.getString(_key);
  final list = raw == null ? <dynamic>[] : (jsonDecode(raw) as List);
  if (list.isNotEmpty && list.last['m'] == short) return; // одна и та же ошибка подряд — один раз
  list.add({'t': DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' '), 'm': short});
  prefs.setString(_key, jsonEncode(list.length > _max ? list.sublist(list.length - _max) : list));
}

/// Запоминать ошибки Flutter и необработанные ошибки (поверх уже стоящих обработчиков)
void installErrorLog() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    _remember(d.exceptionAsString().split('\n').take(2).join(' '));
    prev?.call(d);
  };
  final prevPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, st) {
    _remember('$e ${'$st'.split('\n').firstOrNull ?? ''}');
    return prevPlatform?.call(e, st) ?? false;
  };
}

/// Письмо разработчику: версия, устройство, язык, модули и последние ошибки
Uri problemReportUri({required String subject, required String intro, required Size screen}) {
  final raw = prefs.getString(_key);
  final errors = raw == null ? const [] : (jsonDecode(raw) as List);
  final modules = ModuleStore.instance.installed.map((m) => m.id).toList();
  final info = [
    'AO Bible $appVersion (Flutter${kReleaseMode ? '' : ', debug'})',
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '${screen.width.round()}×${screen.height.round()} · $currentLang',
    'modules: ${modules.length} — ${modules.take(40).join(', ')}',
    errors.isNotEmpty ? 'errors:\n${errors.map((e) => '${e['t']} ${e['m']}').join('\n')}' : 'errors: —',
  ].join('\n');
  var body = '$intro\n\n\n\n— — —\n$info';
  if (body.length > 1800) body = body.substring(0, 1800); // длинные ссылки mailto обрезаются почтовыми программами
  return Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
}

Future<void> reportProblem(BuildContext context) async {
  final size = MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
  var ok = false;
  try {
    ok = await launchUrl(problemReportUri(subject: t('AO Bible: проблема'), intro: t('Что случилось и что вы делали перед этим:'), screen: size));
  } catch (_) {
    // нет почтовой программы — покажем адрес
  }
  if (!ok && context.mounted) toast(context, supportEmail);
}
