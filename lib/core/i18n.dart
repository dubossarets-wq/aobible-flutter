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
// Значение — строка или формы числа {one, few, many, other} (ключ вида «{n} шаг|{n} шага|{n} шагов»)
Map<String, dynamic> _dict = const {};
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

/// Что сделать после смены языка (main: перерегистрировать функции — у пунктов меню новые подписи)
void Function()? onLangChanged;

Future<void> setLang(String code) async {
  final changed = _lang != code;
  _lang = code;
  _dict = code == 'ru' ? const {} : (jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map).cast<String, dynamic>();
  Books.instance.lang = code;
  await prefs.setString('lang', code);
  if (changed) onLangChanged?.call();
}

/// Перевод фразы. «История@@формат картинки» — после @@ пояснение для переводчика (одно русское слово в разных смыслах)
String t(String key, [Map<String, String>? params]) {
  final v = _dict[key];
  var s = v is String ? v : v is Map ? (v['other'] ?? v.values.first).toString() : _bare(key);
  params?.forEach((k, val) => s = s.replaceAll('{$k}', val));
  return s;
}

String _bare(String key) {
  final at = key.indexOf('@@');
  final k = at >= 0 ? key.substring(0, at) : key;
  return k.contains('|') ? k.split('|').last : k;
}

/// Фраза с числом в нужной форме: tn('{n} шаг|{n} шага|{n} шагов', 3) → «3 шага» / «3 steps»
String tn(String key, int n, [Map<String, String>? params]) {
  final v = _dict[key];
  String pick;
  if (v is Map) {
    pick = (v[pluralCategory(_lang, n)] ?? v['other'] ?? v.values.first).toString();
  } else if (v is String && v.isNotEmpty) {
    pick = v;
  } else {
    final f = key.split('|'); // русский: один | несколько | много
    final c = pluralCategory('ru', n);
    pick = f[c == 'one' ? 0 : c == 'few' ? (f.length > 1 ? 1 : 0) : f.length - 1];
  }
  var s = pick.replaceAll('{n}', '$n');
  params?.forEach((k, val) => s = s.replaceAll('{$k}', val));
  return s;
}

/// Категория числа по правилам языка (как Intl.PluralRules в веб-версии)
String pluralCategory(String lang, int n) {
  final m10 = n % 10, m100 = n % 100;
  switch (lang) {
    case 'ru' || 'uk' || 'be' || 'sr':
      return m10 == 1 && m100 != 11 ? 'one' : (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) ? 'few' : 'many';
    case 'pl':
      return n == 1 ? 'one' : (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) ? 'few' : 'many';
    case 'cs':
      return n == 1 ? 'one' : (n >= 2 && n <= 4) ? 'few' : 'other';
    case 'ro':
      return n == 1 ? 'one' : (n == 0 || (m100 >= 2 && m100 <= 19)) ? 'few' : 'other';
    case 'ja' || 'zh' || 'ko' || 'id':
      return 'other';
    default:
      return n == 1 ? 'one' : 'other';
  }
}
