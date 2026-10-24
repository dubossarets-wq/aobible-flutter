// Языки интерфейса — те же словари, что в веб-версии (assets/i18n/<язык>.json): ключ — русская фраза,
// значение — перевод. t('Глава {n}', {'n': '3'}). Русский — без словаря.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'books.dart';
import 'settings.dart';

class Lang {
  const Lang(this.code, this.name, this.flag);
  final String code, name, flag;
}

const langs = [
  Lang('ru', 'Русский', 'ru'), Lang('uk', 'Українська', 'ua'), Lang('ro', 'Română', 'ro'), Lang('en', 'English', 'gb'),
  Lang('es', 'Español', 'es'), Lang('pt', 'Português', 'br'), Lang('fr', 'Français', 'fr'), Lang('de', 'Deutsch', 'de'),
  Lang('it', 'Italiano', 'it'), Lang('pl', 'Polski', 'pl'), Lang('be', 'Беларуская', 'by'), Lang('bg', 'Български', 'bg'),
  Lang('sr', 'Српски', 'rs'), Lang('cs', 'Čeština', 'cz'), Lang('ka', 'ქართული', 'ge'), Lang('hy', 'Հայերեն', 'am'),
  Lang('ko', '한국어', 'kr'), Lang('zh', '中文（简体）', 'cn'), Lang('ja', '日本語', 'jp'), Lang('id', 'Bahasa Indonesia', 'id'),
  Lang('hi', 'हिन्दी', 'in'), Lang('sw', 'Kiswahili', 'tz'),
];

String _lang = 'ru';
Map<String, String> _dict = const {};
String get currentLang => _lang;

/// Первый запуск — язык телефона (если он есть среди наших), потом — выбранный
Future<void> initI18n() async {
  final saved = prefs.getString('lang');
  var code = 'ru';
  if (saved != null) {
    code = saved;
  } else {
    for (final l in PlatformDispatcher.instance.locales) {
      if (langs.any((x) => x.code == l.languageCode)) {
        code = l.languageCode;
        break;
      }
    }
  }
  await setLang(code);
}

Future<void> setLang(String code) async {
  _lang = code;
  _dict = code == 'ru' ? const {} : (jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map).cast<String, String>();
  Books.instance.lang = code;
  await prefs.setString('lang', code);
}

String t(String key, [Map<String, String>? params]) {
  var s = _dict[key] ?? key;
  params?.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}
