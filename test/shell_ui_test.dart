// Оболочка: окна «Ещё», «Настройки», «Оформление», «Библиотека» — как их нажимает человек.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/shell/help_sheet.dart';
import 'package:aobible/features/shell/library_sheet.dart';
import 'package:aobible/features/shell/more_sheet.dart';
import 'package:aobible/features/shell/prefs_sheet.dart';
import 'package:aobible/features/shell/appearance_sheet.dart';
import 'package:aobible/features/shell/about_sheet.dart';
import 'package:aobible/features/shell/news_sheet.dart';
import 'package:aobible/features/shell/welcome_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

void fakeModule(String id, String type, String name, String lang) {
  final db = sqlite3.open('${dir.path}/$id.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': id, 'type': type, 'name': name, 'title': 'Тест $name', 'language': lang})]);
  db.close();
}

/// Кнопка, которая открывает окно — как вкладка «Ещё» на главном экране
Widget app(void Function(BuildContext, WidgetRef) open, {ProviderContainer? container}) => UncontrolledProviderScope(
      container: container ?? ProviderContainer(),
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => open(context, ref), child: const Text('открыть')))),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_shell_ui_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    fakeModule('t1', 'bible', 'ТТ1', 'ru');
    fakeModule('t2', 'bible', 'EN2', 'en');
    fakeModule('d1', 'dictionary', 'Словарик', 'ru');
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.moreItems.clear();
  });

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('«Ещё»: чужие пункты и свои; действие закрывает лист, переключатель — нет', (tester) async {
    await bigScreen(tester);
    var ran = 0;
    Hub.moreItems.add(MoreItem(id: 'x', icon: Icons.star, label: 'Чужой пункт', order: 10, run: (c, r, p) => ran++));
    Hub.moreItems.add(MoreItem(id: 'hidden', icon: Icons.star, label: 'Скрытый', visible: (r) => false, run: (c, r, p) {}));
    await tester.pumpWidget(app((c, r) => openMore(c, r, 0)));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    for (final label in ['Ещё', 'Чужой пункт', 'Оформление', 'Настройки', 'Инструкция', 'Сообщить о проблеме', 'Что нового', 'О приложении']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Скрытый'), findsNothing);
    expect(find.text('Режим чтения'), findsNothing); // по умолчанию выключено в меню
    await tester.tap(find.text('Чужой пункт'));
    await tester.pumpAndSettle();
    expect(ran, 1);
    expect(find.text('Оформление'), findsNothing); // лист закрылся
  });

  testWidgets('«Ещё»: пункты можно скрыть в настройках меню, переключатель «Режим чтения» работает', (tester) async {
    await bigScreen(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier).set({'menu': {'help': false, 'focus': true}});
    await tester.pumpWidget(app((ctx, r) => openMore(ctx, r, 0), container: c));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Инструкция'), findsNothing);
    expect(find.text('Сообщить о проблеме'), findsNothing);
    expect(find.text('Режим чтения'), findsOneWidget);
    expect(find.text('выкл'), findsOneWidget);
    await tester.tap(find.text('Режим чтения'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).get<bool>('focusMode'), true);
    expect(find.text('вкл'), findsOneWidget);
    expect(find.text('Оформление'), findsOneWidget); // лист остался
  });

  testWidgets('Настройки: меню «Ещё» — переключатель пишет настройку menu', (tester) async {
    await bigScreen(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(app((ctx, r) => openPrefs(ctx), container: c));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    for (final label in ['Язык', 'Инструкция', 'Оформление', 'Меню «Ещё»', 'Аудио', 'Библиотека модулей', 'Что нового', 'О приложении']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text('Меню «Ещё»').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проповеди'));
    await tester.pumpAndSettle();
    final menu = c.read(settingsProvider).j['menu'] as Map;
    expect(menu['sermons'], false);
    expect(menu['help'], true); // остальные пункты сохранились
  });

  testWidgets('Настройки: смена языка меняет надписи сразу', (tester) async {
    await bigScreen(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(app((ctx, r) => openPrefs(ctx), container: c));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Язык').first);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('English'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(currentLang, 'en');
    expect(prefs.getString('lang'), 'en');
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('Оформление: тема, шрифт, размер, цвета, сброс', (tester) async {
    await bigScreen(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(app((ctx, r) => openAppearance(ctx), container: c));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    Settings s() => c.read(settingsProvider);
    // 10 тем
    expect(themes.length, 10);
    for (final p in themes.values.take(8)) {
      expect(find.text(p.label), findsOneWidget, reason: p.label); // остальные — правее, лента прокручивается
    }
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(s().get<String>('theme'), 'dark');
    // размер: кнопка «больше» у ползунка
    final before = s().d('fontSize');
    await tester.tap(find.byTooltip('Размер текста: больше'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(s().d('fontSize'), before + 1);
    // вид текста
    await tester.tap(find.text('Сплошной'));
    await tester.pumpAndSettle();
    expect(s().get<bool>('continuousVerses'), true);
    // шрифт
    await tester.tap(find.text('Шрифт'));
    await tester.pumpAndSettle();
    for (final f in ['Системный', 'PT Serif', 'Literata', 'Noto Serif', 'Lora', 'PT Sans', 'IBM Plex Sans', 'Georgia']) {
      expect(find.text(f), findsOneWidget, reason: f);
    }
    await tester.tap(find.text('Lora'));
    await tester.pumpAndSettle();
    expect(s().get<String>('fontFamily'), 'Lora');
    await tester.tap(find.text('По ширине'));
    await tester.pumpAndSettle();
    expect(s().get<String>('textAlign'), 'justify');
    // назад → цвета: акцент синим, потом «как в теме»
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Цвета'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Синий').first);
    await tester.pumpAndSettle();
    expect((s().j['colorOverrides'] as Map)['accent'], '#2563eb');
    await tester.tap(find.text('Все цвета — как в теме'));
    await tester.pumpAndSettle();
    expect((s().j['colorOverrides'] as Map), isEmpty);
    // кнопки и панели
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кнопки и панели'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Высота верхней панели: больше'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(s().d('barHeight'), 56);
    // сброс
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('Сбросить оформление'), find.byType(ListView).last, const Offset(0, -200));
    await tester.tap(find.text('Сбросить оформление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Да, сбросить'));
    await tester.pumpAndSettle();
    expect(s().get<String>('theme'), 'light');
    expect(s().get<String>('fontFamily'), 'system');
    expect(s().d('fontSize'), 19);
  });

  testWidgets('Библиотека: установленные, фильтры по виду и языку (пустые языки не показываем), основной перевод', (tester) async {
    await bigScreen(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(app((ctx, r) => openLibrary(ctx), container: c));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('ТТ1'), findsOneWidget);
    expect(find.text('EN2'), findsOneWidget);
    expect(find.text('Словарик'), findsOneWidget);
    // языки: русский и английский есть, японского нет
    expect(find.text('Русский  2'), findsOneWidget);
    expect(find.text('English  1'), findsOneWidget);
    expect(find.textContaining('Японский'), findsNothing);
    // фильтр по виду
    await tester.tap(find.widgetWithText(ChoiceChip, 'Словари  1'));
    await tester.pumpAndSettle();
    expect(find.text('ТТ1'), findsNothing);
    expect(find.text('Словарик'), findsOneWidget);
    // у словарей нет английских — язык English исчез
    expect(find.textContaining('English  '), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Все'));
    await tester.pumpAndSettle();
    // поиск
    await tester.enterText(find.byType(TextField), 'en2');
    await tester.pumpAndSettle();
    expect(find.text('ТТ1'), findsNothing);
    expect(find.text('EN2'), findsOneWidget); // регистр не важен
    // основной перевод
    await tester.tap(find.byTooltip('Сделать основным'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).get<String>('primaryModule'), 't2');
    // удаление с подтверждением
    await tester.tap(find.text('EN2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    expect(ModuleStore.instance.get('t2'), isNull);
    expect(File('${dir.path}/t2.db').existsSync(), false);
  });

  testWidgets('О приложении, Что нового, Приветствие, Инструкция открываются и листаются', (tester) async {
    await bigScreen(tester);
    await tester.pumpWidget(app((ctx, r) => openAbout(ctx)));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('AO Bible · версия $appVersion'), findsOneWidget);
    expect(find.text('dubossarets@gmail.com'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    await tester.tap(find.text('Конфиденциальность'));
    await tester.pumpAndSettle();
    expect(find.text('Коротко: приложение ничего о вас не собирает.'), findsOneWidget);
    await tester.tap(find.text('Лицензии и авторы'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Лицензии и авторы'), findsOneWidget);
  });

  testWidgets('Что нового и Приветствие', (tester) async {
    await bigScreen(tester);
    await tester.pumpWidget(app((ctx, r) => openNews(ctx)));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Что нового'), findsOneWidget);
    expect(find.text('Понятно'), findsOneWidget);
    expect(prefs.getString('newsSeen'), isNotNull);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.text('Что нового'), findsNothing);

    prefs.setBool('welcomePending', true);
    await tester.pumpWidget(app((ctx, r) => openWelcome(ctx)));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('welcomePending'), false);
    expect(find.text('Шаг 1 из 3'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Зажмите стих'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Нажмите на слово'), findsOneWidget);
    await tester.tap(find.text('Начать чтение'));
    await tester.pumpAndSettle();
    expect(find.text('Добро пожаловать'), findsNothing);
  });

  testWidgets('Инструкция: уроки, поиск, шаги', (tester) async {
    await bigScreen(tester);
    await tester.pumpWidget(app((ctx, r) => openHelp(ctx)));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Перейти к книге, главе, стиху'), findsOneWidget);
    expect(find.text('4 шага'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'проповедь');
    await tester.pumpAndSettle();
    expect(find.text('Перейти к книге, главе, стиху'), findsNothing);
    expect(find.text('Проповеди'), findsOneWidget);
    await tester.tap(find.text('Проповеди'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Проповеди'), findsOneWidget);
  });
}
