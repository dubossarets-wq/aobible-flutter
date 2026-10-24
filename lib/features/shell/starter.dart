// Стартовые модули (src/core/modules.js): на первом запуске ядро ставит только основной перевод, остальное
// (xrefs, симфония, Стронг, места, оригиналы, словарь на языке, Лопухин, карты, подстрочники) доустанавливаем
// в фоне — читать можно сразу. Тем, кто пользовался приложением раньше, один раз доставляем новые базовые модули.
// Об изученных модулях — одно уведомление «Добавлено для изучения: …».
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'sheet.dart';

const originals = ['oshb', 'byz-rp2018'];

/// Для изучения — у каждого сразу: карты, толкования Лопухина, подстрочники (большой «Подстрочник» — последним)
const study = ['bible-maps', 'lopukhin', 'vin-interlinear', 'rst-interlinear'];

// Словарь на языке интерфейса: русский — для русского, украинского и белорусского; на других языках в каталоге
// только английские словари
const _langDictionary = {'ru': 'nikifor', 'uk': 'nikifor', 'be': 'nikifor'};
String langDictionary() => _langDictionary[currentLang] ?? 'easton';

// Перевод на языке интерфейса — новому человеку первым и основным. Полной Библии на языке нет — для кириллических
// языков остаётся Синодальный, для остальных — английский BSB; Новый Завет на родном языке ставится дополнительно.
const _fullBible = {
  'cs': 'kralicka', 'de': 'luther1912', 'en': 'bsb', 'es': 'rv1909', 'fr': 'segond1910', 'hi': 'hin-irv', 'it': 'riveduta', 'ja': 'bungo',
  'ko': 'korrv', 'pl': 'gdanska', 'pt': 'biblia-livre', 'sr': 'dk-cyr', 'sw': 'swh-ulb', 'zh': 'cuv-s',
};
const _ntBible = {'hy': 'arm-nt1853', 'id': 'alkitab-gratis', 'ro': 'ronbl', 'uk': 'ukr-kulish', 'be': 'be-nt1931'};
const _cyrillic = {'ru', 'uk', 'be', 'bg', 'sr'};

String homeBible() => _fullBible[currentLang] ?? (_cyrillic.contains(currentLang) ? 'rst-plus' : 'bsb');

List<String> _langExtras() => [
      if (_ntBible[currentLang] != null) _ntBible[currentLang]!,
      if (!_cyrillic.contains(currentLang)) ...['strongs-hebrew', 'strongs-greek'],
    ];

List<String> starter() => {
      homeBible(), 'rst-plus', 'xrefs-rst', 'rst-symphony', 'strongs-ru-hebrew', 'strongs-ru-greek', 'bible-places', 'bible-illustrations',
      ...originals, langDictionary(), ..._langExtras(), ...study,
    }.toList();

/// Модули, которые один раз доустанавливаются тем, кто начал пользоваться приложением до их появления
List<String> lateStarter() => {'bible-places', 'bible-illustrations', 'strongs-ru-hebrew', 'strongs-ru-greek', ...originals, langDictionary(), ...study}.toList();

List<String> _done() {
  final raw = prefs.getString('lateStarter');
  return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
}

/// Вызывается один раз при запуске (до runApp): на самом первом запуске — основной перевод на языке интерфейса
/// и отметка «показать приветствие»; «Что нового» новому человеку не нужно.
void prepareFirstRun(String latestNewsId) {
  if (ModuleStore.instance.bibles.isNotEmpty || prefs.getBool('bootstrapped') == true) return;
  final raw = prefs.getString('settings');
  final j = raw == null ? <String, dynamic>{} : (jsonDecode(raw) as Map).cast<String, dynamic>();
  if (j['primaryModule'] == null) {
    j['primaryModule'] = homeBible();
    prefs.setString('settings', jsonEncode(j));
  }
  prefs.setBool('welcomePending', true);
  prefs.setString('newsSeen', latestNewsId);
}

/// Фоновая доустановка (Hub.afterStart). Ждёт, пока появится хотя бы один перевод (первая установка), затем
/// ставит недостающее по одному; модули, которые не нашлись в каталоге, пробуем снова при следующем запуске.
Future<void> installStarterModules(WidgetRef ref) async {
  final store = ModuleStore.instance;
  for (var i = 0; store.bibles.isEmpty; i++) {
    if (i > 1200) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final first = prefs.getBool('bootstrapped') != true;
  final done = _done();
  final want = first ? starter() : lateStarter();
  final todo = want.where((id) => !done.contains(id) && store.get(id) == null).toList();
  if (todo.isEmpty) {
    if (first) await prefs.setBool('bootstrapped', true);
    await prefs.setString('lateStarter', jsonEncode({...done, ...want}.toList()));
    return;
  }
  try {
    final cat = await store.catalog();
    if (first) await prefs.setBool('bootstrapped', true);
    final missing = todo.where((id) => !cat.any((c) => c.id == id)).toList();
    final tried = [...done, ...want.where((id) => !missing.contains(id))];
    await prefs.setString('lateStarter', jsonEncode(tried.toSet().toList()));
    final learned = <String>[];
    for (final id in todo) {
      final e = cat.where((c) => c.id == id).firstOrNull;
      if (e == null || e.unavailable) continue;
      try {
        await store.install(e);
      } catch (err) {
        debugPrint('starter ${e.id}: $err');
        // не вышло — пусть попробуется при следующем запуске
        final cur = _done()..remove(e.id);
        await prefs.setString('lateStarter', jsonEncode(cur));
        continue;
      }
      if (study.contains(e.id) || e.id == langDictionary()) {
        if (!first || study.contains(e.id)) learned.add(e.name);
        continue;
      }
      if (first) continue; // новому человеку — только общее уведомление
      if (e.id == 'strongs-ru-greek' || originals.contains(e.id)) continue; // о русском Стронге — одно уведомление; оригиналы молча
      toast(
        null,
        e.type == 'illustrations'
            ? t('Добавлены иллюстрации к стихам: нажмите на значок картинки в конце стиха')
            : e.id == 'strongs-ru-hebrew'
                ? t('Добавлен словарь Стронга на русском: нажмите на слово или номер Стронга')
                : t('Установлен «{name}»: нажмите на город в стихе — он покажется на карте', {'name': e.name}),
      );
    }
    if (learned.isNotEmpty) toast(null, t('Добавлено для изучения: {names}', {'names': learned.join(', ')}));
  } catch (e) {
    debugPrint('starter: $e'); // нет сети — повторим при следующем запуске
    await prefs.setString('lateStarter', jsonEncode(done));
  }
}
