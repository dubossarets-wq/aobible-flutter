// Надписи с числами («5 дней подряд») и даты. Ядро t() не знает форм множественного числа (в словарях это объекты
// {one, other…}) и пояснений «@@», поэтому здесь свой разбор тех же словарей assets/i18n/<язык>.json.
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/i18n.dart' show currentLang;

final _dicts = <String, Map<String, dynamic>>{};

/// Прочитать словарь текущего языка (один раз); до этого формы берутся по русским правилам
Future<void> ensureDict() async {
  final code = currentLang;
  if (code == 'ru' || _dicts.containsKey(code)) return;
  try {
    _dicts[code] = (jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map).cast<String, dynamic>();
  } catch (_) {
    _dicts[code] = const {};
  }
}

/// Категория множественного числа (упрощённые правила Intl.PluralRules)
String pluralCategory(String lang, int n) {
  n = n.abs();
  switch (lang) {
    case 'ru' || 'uk' || 'be' || 'sr':
      if (n % 10 == 1 && n % 100 != 11) return 'one';
      if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return 'few';
      return 'many';
    case 'pl':
      if (n == 1) return 'one';
      if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return 'few';
      return 'many';
    case 'cs':
      if (n == 1) return 'one';
      if (n >= 2 && n <= 4) return 'few';
      return 'other';
    case 'zh' || 'ja' || 'ko' || 'id':
      return 'other';
    case 'fr' || 'pt':
      return n == 0 || n == 1 ? 'one' : 'other';
    case 'hi':
      return n == 0 || n == 1 ? 'one' : 'other';
    default:
      return n == 1 ? 'one' : 'other';
  }
}

/// Как t() веб-версии: пояснение после «@@» отбрасывается; формы через «|» выбираются по числу params['n']
String tx(String key, [Map<String, Object?>? params]) {
  final at = key.indexOf('@@');
  final k = at >= 0 ? key.substring(0, at) : key;
  final lang = currentLang;
  final dictVal = lang == 'ru' ? null : _dicts[lang]?[key];
  String s;
  if (!k.contains('|')) {
    s = dictVal is String && dictVal.isNotEmpty ? dictVal : k;
  } else {
    final n = ((params?['n'] as num?) ?? 0).toInt();
    if (dictVal is Map) {
      s = (dictVal[pluralCategory(lang, n)] ?? dictVal['other'] ?? dictVal['many'] ?? dictVal['one'] ?? k) as String;
    } else {
      final forms = k.split('|');
      final cat = pluralCategory('ru', n);
      final i = cat == 'one' ? 0 : cat == 'many' ? 2 : 1;
      s = forms[i < forms.length ? i : forms.length - 1];
    }
  }
  params?.forEach((p, v) => s = s.replaceAll('{$p}', '$v'));
  return s;
}

const _monthsRu = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
const _monthsRuShort = ['янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'];
const _monthsUk = ['січня', 'лютого', 'березня', 'квітня', 'травня', 'червня', 'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekRu = ['П', 'В', 'С', 'Ч', 'П', 'С', 'В']; // понедельник … воскресенье
const _weekUk = ['П', 'В', 'С', 'Ч', 'П', 'С', 'Н'];
const _weekEn = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// «15 окт.» / «15 октября 2026» (русский, украинский, английский; для остальных языков — «15.10»)
String fmtDay(DateTime d, {bool full = false, bool year = false}) {
  final l = currentLang;
  if (l == 'ru') return '${d.day} ${full ? _monthsRu[d.month - 1] : _monthsRuShort[d.month - 1]}${year ? ' ${d.year}' : ''}';
  if (l == 'uk') {
    final m = _monthsUk[d.month - 1];
    return '${d.day} ${full ? m : m.substring(0, 3)}${year ? ' ${d.year}' : ''}';
  }
  if (l == 'en') {
    final m = _monthsEn[d.month - 1];
    return '${d.day} ${full ? m : m.substring(0, 3)}${year ? ' ${d.year}' : ''}';
  }
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}${year ? '.${d.year}' : ''}';
}

/// Первая буква дня недели (1 — понедельник … 7 — воскресенье)
String weekdayLetter(int weekday) => (currentLang == 'ru' ? _weekRu : currentLang == 'uk' ? _weekUk : _weekEn)[weekday - 1];

/// Короткое название дня недели (1 — понедельник … 7 — воскресенье) для кнопок напоминаний, как в будильнике iPhone:
/// «Пн Вт Ср…». Та же таблица, что в веб-версии (core/weekdays.js)
String weekdayShort(int weekday) => (_weekShort[currentLang] ?? _weekShort['en']!)[weekday - 1];
const _weekShort = <String, List<String>>{
  'ru': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
  'uk': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
  'be': ['Пн', 'Аў', 'Ср', 'Чц', 'Пт', 'Сб', 'Нд'],
  'bg': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
  'cs': ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne'],
  'de': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  'es': ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'],
  'fr': ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
  'hi': ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'],
  'hy': ['Երկ', 'Երք', 'Չրք', 'Հնգ', 'Ուր', 'Շբթ', 'Կիր'],
  'id': ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'],
  'it': ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'],
  'ja': ['月', '火', '水', '木', '金', '土', '日'],
  'ka': ['ორშ', 'სამ', 'ოთხ', 'ხუთ', 'პარ', 'შაბ', 'კვი'],
  'ko': ['월', '화', '수', '목', '금', '토', '일'],
  'pl': ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sb', 'Nd'],
  'pt': ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'],
  'ro': ['Lun', 'Mar', 'Mie', 'Joi', 'Vin', 'Sâm', 'Dum'],
  'sr': ['Пон', 'Уто', 'Сре', 'Чет', 'Пет', 'Суб', 'Нед'],
  'sw': ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jms', 'Jpi'],
  'zh': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
};
