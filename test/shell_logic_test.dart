// Оболочка: логика без экрана — ссылки на лицензии, свои цвета поверх темы, формы чисел, стартовые модули,
// «Что нового», письмо о проблеме, первый запуск.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/shell/about_sheet.dart';
import 'package:aobible/features/shell/colors.dart';
import 'package:aobible/features/shell/fonts.dart';
import 'package:aobible/features/shell/news_data.dart';
import 'package:aobible/features/shell/news_sheet.dart';
import 'package:aobible/features/shell/plural.dart';
import 'package:aobible/features/shell/report.dart';
import 'package:aobible/features/shell/starter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    final dir = Directory('${Directory.systemTemp.path}/aob_shell_test_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    await ModuleStore.initAt(dir);
    await setLang('ru');
  });

  test('ссылки на тексты лицензий', () {
    expect(licenseUrl('CC BY-SA 4.0'), 'https://creativecommons.org/licenses/by-sa/4.0/');
    expect(licenseUrl('CC BY-NC 4.0'), 'https://creativecommons.org/licenses/by-nc/4.0/');
    expect(licenseUrl('CC BY 3.0 US'), 'https://creativecommons.org/licenses/by/3.0/us/');
    expect(licenseUrl('CC0 1.0'), 'https://creativecommons.org/publicdomain/zero/1.0/');
    expect(licenseUrl('SIL Open Font License 1.1'), 'https://openfontlicense.org');
    expect(licenseUrl('Public Domain'), isNull);
  });

  test('свои цвета поверх темы; сброс возвращает цвет темы', () {
    const base = Settings({'theme': 'dark'});
    expect(effectivePalette(base).accent, themes['dark']!.accent);
    final s = base.copyWith({'colorOverrides': {'accent': '#2563eb', 'bar': '#ffffff'}});
    expect(effectivePalette(s).accent, const Color(0xFF2563EB));
    expect(effectivePalette(s).bg, themes['dark']!.bg);
    expect(strongColor(s), const Color(0xFF2563EB)); // номера Стронга и заголовки по умолчанию — цвет акцента
    expect(headingColor(s.copyWith({'colorOverrides': {'heading': '#be185d'}})), const Color(0xFFBE185D));
    expect(parseHex('#zzzzzz'), isNull);
    expect(toHex(const Color(0xFF8C5E28)), '#8c5e28');
    expect(isLight(const Color(0xFFFFFFFF)), true);
    expect(isLight(const Color(0xFF0C0C0D)), false);
  });

  test('шрифты: все из веб-версии, толщина', () {
    expect(fontDefs.keys, ['system', 'PT Serif', 'Literata', 'Noto Serif', 'Lora', 'PT Sans', 'IBM Plex Sans', 'Georgia']);
    final st = readerTextStyle(const Settings({'fontFamily': 'Literata', 'fontWeight': 600, 'fontSize': 22}));
    expect(st.fontFamily, 'Literata');
    expect(st.fontSize, 22);
    expect(st.fontWeight, FontWeight.w600);
    expect(st.fontVariations!.single.value, 600);
    expect(readerTextStyle(const Settings({})).fontFamily, isNull);
    expect(menuFlag(const Settings({}), 'help'), true);
    expect(menuFlag(const Settings({}), 'focus'), false);
    expect(menuFlag(const Settings({'menu': {'help': false}}), 'help'), false);
  });

  test('формы чисел: русский и английский', () async {
    expect(plural('{n} шаг|{n} шага|{n} шагов', 1), '1 шаг');
    expect(plural('{n} шаг|{n} шага|{n} шагов', 3), '3 шага');
    expect(plural('{n} шаг|{n} шага|{n} шагов', 5), '5 шагов');
    expect(plural('{n} шаг|{n} шага|{n} шагов', 21), '21 шаг');
    expect(plural('{n} шаг|{n} шага|{n} шагов', 12), '12 шагов');
    await setLang('en');
    await loadPlurals();
    expect(plural('{n} шаг|{n} шага|{n} шагов', 1), '1 step');
    expect(plural('{n} шаг|{n} шага|{n} шагов', 4), '4 steps');
  });

  test('стартовые модули зависят от языка интерфейса', () async {
    expect(homeBible(), 'rst-plus');
    expect(starter().first, 'rst-plus');
    expect(starter(), containsAll(['xrefs-rst', 'lopukhin', 'bible-maps', 'vin-interlinear', 'rst-interlinear', 'nikifor']));
    expect(starter().toSet().length, starter().length);
    await setLang('de');
    expect(homeBible(), 'luther1912');
    expect(starter(), containsAll(['luther1912', 'easton', 'strongs-hebrew', 'strongs-greek']));
    expect(starter(), isNot(contains('nikifor')));
    await setLang('uk');
    expect(starter(), containsAll(['rst-plus', 'ukr-kulish', 'nikifor']));
    expect(lateStarter(), containsAll(['bible-places', 'lopukhin']));
  });

  test('первый запуск: перевод на языке интерфейса и приветствие; не первый — ничего', () async {
    await setLang('fr');
    prepareFirstRun(news.first.id);
    expect(jsonDecode(prefs.getString('settings')!)['primaryModule'], 'segond1910');
    expect(prefs.getBool('welcomePending'), true);
    expect(prefs.getString('newsSeen'), news.first.id);
    expect(pendingNews(), isEmpty);
    // выбор человека не перетирается
    SharedPreferences.setMockInitialValues({'settings': jsonEncode({'primaryModule': 'kjv'})});
    prefs = await SharedPreferences.getInstance();
    prepareFirstRun(news.first.id);
    expect(jsonDecode(prefs.getString('settings')!)['primaryModule'], 'kjv');
  });

  test('«Что нового»: показывается один раз после обновления', () {
    // пользовался раньше, но не видел — последняя запись
    expect(pendingNews().map((n) => n.id), [news.first.id]);
    markNewsSeen();
    expect(pendingNews(), isEmpty);
    // вышла запись новее просмотренной
    prefs.setString('newsSeen', news[1].id);
    expect(pendingNews().map((n) => n.id), [news.first.id]);
    expect(fmtNewsDate('2026-10-24'), '24 октября'); // как toLocaleDateString(ru, {day, month: 'long'}) в веб-версии
    expect(news.every((n) => n.items.isNotEmpty), true);
  });

  test('письмо о проблеме: адрес, версия, устройство, модули, ошибки', () async {
    // установленный модуль для списка
    final dir = ModuleStore.instance.dir.path;
    final db = sqlite3.open('$dir/x1.db');
    db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
    db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'x1', 'type': 'bible', 'name': 'X', 'language': 'ru'})]);
    db.close();
    await ModuleStore.initAt(Directory(dir));
    prefs.setString('errorLog', jsonEncode([{'t': '2026-10-24 10:00', 'm': 'тестовая ошибка'}]));
    final u = problemReportUri(subject: 'AO Bible: проблема', intro: 'Что случилось:', screen: const Size(1080, 2400));
    expect(u.scheme, 'mailto');
    expect(u.path, supportEmail);
    final body = u.queryParameters['body']!;
    expect(u.queryParameters['subject'], 'AO Bible: проблема');
    expect(body, contains('AO Bible $appVersion'));
    expect(body, contains('1080×2400 · ru'));
    expect(body, contains('modules: 1 — x1'));
    expect(body, contains('тестовая ошибка'));
    expect(u.toString().contains('+'), false); // пробелы — %20, а не «+»: почтовые программы не превращают их обратно
  });
}
