// Оболочка и ядро как их использует человек: шапка с коротким именем перевода и окном выбора, «Перейти»
// (стихи, поиск по буквам, подсказка, проверки), две панели с разделителем, нижние вкладки, режим чтения,
// режим плана, тема «Как в системе», перенос старых настроек, Escape, размер шрифта окон.
// Телефон 400×830 и широкий экран 1200×800, светлая и тёмная тема; любое исключение Flutter роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/main.dart';
import 'package:aobible/ui/home_screen.dart';
import 'package:aobible/ui/kit.dart' show AobSheet;
import 'package:aobible/ui/reader_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

void makeBible(String id, String name, String lang, Map<String, List<List<String>>> books, {Map<String, dynamic>? features}) {
  final db = sqlite3.open('${dir.path}/$id.db');
  db.execute('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  var n = 0;
  final list = <Map<String, dynamic>>[];
  books.forEach((book, chapters) {
    list.add({'id': book, 'name': book, 'short': book, 'chapters': chapters.length});
    for (var c = 0; c < chapters.length; c++) {
      for (var v = 0; v < chapters[c].length; v++) {
        n++;
        db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, book, c + 1, v + 1, chapters[c][v]]);
        db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, chapters[c][v]]);
      }
    }
  });
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': id, 'type': 'bible', 'name': name, 'title': 'Тестовый $name', 'language': lang, 'bookList': list, 'features': ?features}),
  ]);
  db.close();
}

List<List<String>> chapters(String word, int count, int verses) => [
      for (var c = 1; c <= count; c++) [for (var v = 1; v <= verses; v++) 'Стих $v главы $c: $word светильник и свет мира.'],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BookInfo john;
  // Текст внутри окна (а не в читалке под ним)
  Finder inSheet(String text) => find.descendant(of: find.byType(AobSheet), matching: find.text(text));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    john = Books.instance.meta('John');
    dir = Directory('${Directory.systemTemp.path}/aob_shellcore_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final books = {
      'Gen': chapters('Бог', 3, 12),
      'Tob': chapters('Товит', 2, 6), // неканоническая (dc) — со звёздочкой
      'John': [...chapters('Слово', 2, 10), chapters('Любовь', 1, 20).first],
      'Phlm': chapters('Филимон', 1, 5), // книга из одной главы — сразу стихи
      'Enoch': chapters('Енох', 2, 4), // нет в справочнике — вкладка «Неканон»
    };
    makeBible('rst-plus', 'РСТ', 'ru', books);
    makeBible('kjv', 'KJV', 'en', books, features: {'strongs': true});
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
    focusHidden.value = false;
    planMode.value = {};
    readerMarks.value = {};
    updateAvailable.value = false;
    systemDark.value = false;
    tabActive.value = 'bible';
  });

  void screen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<ProviderContainer> start(WidgetTester tester, {String theme = 'light', Size size = const Size(400, 830), Map<String, dynamic>? settings, String? panes}) async {
    screen(tester, size);
    prefs.setString('settings', jsonEncode({'theme': theme, ...?settings}));
    if (panes != null) prefs.setString('panes', panes);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    return c;
  }

  Future<void> settle(WidgetTester tester, {int ms = 600}) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }


  // --- Настройки: чистая логика ---------------------------------------------------------------------

  test('Настройки: «Как в системе» — светлая или тёмная по системе; неизвестная тема — светлая', () {
    expect(resolveTheme('auto', true), 'dark');
    expect(resolveTheme('auto', false), 'light');
    expect(resolveTheme('sepia', true), 'sepia');
    expect(resolveTheme('нет-такой', false), 'light');
    systemDark.value = true;
    expect(const Settings({'theme': 'auto'}).palette.dark, isTrue);
    systemDark.value = false;
    expect(const Settings({'theme': 'auto'}).palette.dark, isFalse);
  });

  test('Настройки: старые customColors/colors переносятся в colorOverrides, остальное не трогаем', () {
    final m = migrateSettings({'customColors': true, 'colors': {'accent': '#112233'}, 'fontSize': 21.0, 'theme': 'warm'});
    expect(m['colorOverrides'], {'accent': '#112233'});
    expect(m['customColors'], false);
    expect(m.containsKey('colors'), isFalse);
    expect(m['fontSize'], 21.0);
    expect(m['theme'], 'warm');
    // выключенные «свои цвета» не переносятся
    expect(migrateSettings({'customColors': false, 'colors': {'accent': '#112233'}})['colorOverrides'], isEmpty);
    // уже новые настройки остаются как есть
    final fresh = migrateSettings({'colorOverrides': {'bg': '#ffffff'}, 'theme': 'auto'});
    expect(fresh['colorOverrides'], {'bg': '#ffffff'});
    expect(fresh['theme'], 'auto'); // у настроек без метки версии «Как в системе» сохраняется
    // явная версия 1: «Как в системе» тогда была светлой
    expect(migrateSettings({'v': 1, 'theme': 'auto'})['theme'], 'light');
  });

  test('Настройки читаются из prefs с переносом старых цветов', () async {
    await prefs.setString('settings', jsonEncode({'customColors': true, 'colors': {'accent': '#aa0000'}}));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    expect(s.palette.accent, const Color(0xFFAA0000));
  });

  test('Системные полосы: цвет по теме, значки светлые на тёмном и тёмные на светлом', () {
    final light = systemBarsStyle(themes['light']!);
    expect(light.statusBarColor, themes['light']!.bar);
    expect(light.systemNavigationBarColor, themes['light']!.panel);
    expect(light.statusBarIconBrightness, Brightness.dark);
    final dark = systemBarsStyle(themes['dark']!);
    expect(dark.statusBarColor, themes['dark']!.bar);
    expect(dark.systemNavigationBarColor, themes['dark']!.panel);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
  });

  testWidgets('Системные полосы действительно ставятся при запуске и при смене темы', (tester) async {
    final calls = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setSystemUIOverlayStyle') calls.add(Map.of(call.arguments as Map));
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = await start(tester, theme: 'dark');
    List<Map> real() => [for (final c in calls) if (c['statusBarColor'] != null) c];
    expect(real(), isNotEmpty, reason: '$calls');
    expect(real().last['statusBarColor'], themes['dark']!.bar.toARGB32());
    c.read(settingsProvider.notifier).set({'theme': 'light'});
    await tester.pump();
    expect(real().last['statusBarColor'], themes['light']!.bar.toARGB32());
    expect(tester.takeException(), isNull);
  });

  test('Короткие имена переводов: таблица и первые 5 знаков', () {
    InstalledModule m(String id, String name) => InstalledModule(id, {'id': id, 'name': name}, '');
    expect(shortName(m('rst-dc', 'Синодальный с неканоническими')), 'RSTНК');
    expect(shortName(m('luther1912', 'Lutherbibel 1912')), 'LUT');
    expect(shortName(m('kjv', 'KJV')), 'KJV');
    expect(shortName(m('x', 'Новый русский перевод')), 'Новый');
    expect(shortName(m('x', 'Синодальный')), 'Синод');
    expect(shortName(null), '—');
  });

  // --- Тема «Как в системе» в приложении ----------------------------------------------------------------

  testWidgets('Тема «Как в системе»: следует за темой устройства и перекрашивается при смене', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await start(tester, theme: 'auto');
    Color bg() => tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;
    expect(bg(), themes['dark']!.bg);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    await tester.pump();
    expect(bg(), themes['light']!.bg);
    expect(tester.takeException(), isNull);
  });

  // --- Шапка и выбор перевода ---------------------------------------------------------------------------------

  for (final theme in ['light', 'dark']) {
    testWidgets('Шапка: короткое имя перевода; окно выбора со звёздочкой, подзаголовком и «Стронга» — $theme', (tester) async {
      final c = await start(tester, theme: theme);
      expect(find.text('РСТ'), findsOneWidget);
      await tester.tap(find.text('РСТ'));
      await tester.pumpAndSettle();
      expect(find.text('Перевод'), findsOneWidget);
      expect(find.text('Основная панель'), findsOneWidget);
      expect(find.text('Тестовый KJV · номера Стронга'), findsOneWidget);
      expect(find.text('Тестовый РСТ'), findsOneWidget);
      // у основного перевода звезда закрашена и подписана, у другого — кнопка «Сделать основным»
      expect(find.byTooltip('Основной перевод'), findsOneWidget);
      await tester.tap(find.byTooltip('Сделать основным'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).get<String>('primaryModule'), 'kjv');
      expect(find.byTooltip('Сделать основным'), findsOneWidget);
      // выбор перевода сохраняет место
      await tester.tap(find.text('Тестовый KJV · номера Стронга'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].moduleId, 'kjv');
      expect(find.text('KJV'), findsOneWidget); // в шапке
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Окно выбора перевода: вторая панель, «Другие переводы» открывают библиотеку, список живёт по changes', (tester) async {
    String? libraryTab;
    Hub.openLibraryTab = (c, tab) => libraryTab = tab; // библиотека открывается через общую точку, с вкладкой
    final c = await start(tester);
    await tester.tap(find.byTooltip('Читать параллельно'));
    await tester.pumpAndSettle();
    expect(c.read(panesProvider).length, 2);
    await tester.tap(find.text('РСТ').last);
    await tester.pumpAndSettle();
    expect(find.text('Вторая панель'), findsOneWidget);
    // удалили перевод, пока окно открыто, — список обновился
    expect(find.text('Тестовый KJV · номера Стронга'), findsOneWidget);
    await tester.runAsync(() => ModuleStore.instance.remove('kjv'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Тестовый KJV · номера Стронга'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Другие переводы'));
    await tester.tap(find.text('Другие переводы'));
    await tester.pumpAndSettle();
    expect(find.text('Перевод'), findsNothing); // окно выбора закрылось
    expect(libraryTab, 'catalog'); // библиотека открыта на вкладке «Каталог»
    expect(tester.takeException(), isNull);
  });

  testWidgets('Перевод панели удалён: панель переходит на основной (или первый) перевод, место остаётся', (tester) async {
    final panes = jsonEncode([
      {'moduleId': 'kjv', 'ref': const VerseRef('John', 3, 5).toJson()},
      {'moduleId': 'rst-plus', 'ref': const VerseRef('Gen', 1, 1).toJson()},
    ]);
    final c = await start(tester, panes: panes);
    expect(c.read(panesProvider)[0].moduleId, 'kjv');
    await tester.runAsync(() => ModuleStore.instance.remove('kjv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(panesProvider)[0].moduleId, 'rst-plus'); // основной перевод по умолчанию
    await tester.pump(const Duration(seconds: 1)); // отложенное сохранение места
    expect(c.read(panesProvider)[0].ref, const VerseRef('John', 3, 5));
    expect(c.read(panesProvider)[1].moduleId, 'rst-plus');
    expect(tester.takeException(), isNull);
  });

  // --- «Перейти» ---------------------------------------------------------------------------------------------------

  for (final theme in ['light', 'dark']) {
    testWidgets('«Перейти»: поиск по буквам, Enter, главы, стихи, «С начала главы» — $theme', (tester) async {
      final c = await start(tester, theme: theme);
      await tester.tap(find.textContaining('1:1').first);
      await tester.pumpAndSettle();
      expect(find.text('Перейти'), findsOneWidget);
      expect(inSheet(Books.instance.meta('Gen').name), findsWidgets); // плитка и «недавние»
      await tester.enterText(find.byType(TextField), 'ин');
      await tester.pumpAndSettle();
      expect(inSheet(john.name), findsOneWidget); // список сузился до подходящих
      expect(inSheet(Books.instance.meta('Gen').name), findsNothing);
      expect(find.byTooltip('Очистить'), findsOneWidget);
      // Enter на названии открывает главы
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(inSheet('3'), findsOneWidget);
      expect(inSheet('4'), findsNothing); // в тестовом Иоанне три главы
      await tester.tap(inSheet('3'));
      await tester.pumpAndSettle();
      expect(find.text('С начала главы'), findsOneWidget);
      expect(inSheet('20'), findsOneWidget);
      expect(inSheet('21'), findsNothing);
      await tester.tap(inSheet('16'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].ref, const VerseRef('John', 3, 16));
      expect(find.text('Перейти'), findsNothing);
      // «С начала главы»
      await tester.tap(find.textContaining('3:16').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый Завет'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(john.name).first);
      await tester.pumpAndSettle();
      await tester.tap(inSheet('2'));
      await tester.pumpAndSettle();
      expect(inSheet('${john.name} 2'), findsOneWidget);
      await tester.tap(find.text('С начала главы'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].ref, const VerseRef('John', 2, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('«Перейти»: подсказка до Enter, поджатие к последнему стиху, проверки по модулю', (tester) async {
    await start(tester);
    await tester.tap(find.textContaining('1:1').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ин 3:16');
    await tester.pumpAndSettle();
    expect(find.text('Перейти: ${john.name} 3:16'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ин 3:99');
    await tester.pumpAndSettle();
    expect(find.text('Перейти: ${john.name} 3:20'), findsOneWidget); // нет такого стиха — последний
    await tester.enterText(find.byType(TextField), 'Ин 9:1');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('В книге «${john.name}» 3 глав.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Мф 1:1');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('В переводе РСТ нет этой книги.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'абракадабра 1 2 3 4');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('Не понял ссылку. Пример: Ин 3:16'), findsOneWidget);
    // подсказку можно нажать, не дожидаясь Enter
    await tester.enterText(find.byType(TextField), 'Ин 3:99');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перейти: ${john.name} 3:20'));
    await tester.pumpAndSettle();
    expect(readerMarks.value[0]!.ref, const VerseRef('John', 3, 20)); // читалка могла уже прокрутить, смотрим куда перешли
    // Enter на ссылке с большим стихом тоже поджимает
    await tester.tap(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').endsWith('Выбрать место')).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Быт 2:99');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(readerMarks.value[0]!.ref, const VerseRef('Gen', 2, 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Перейти»: кнопка очистки; книга из одной главы сразу открывает стихи; назад возвращает на шаг', (tester) async {
    final c = await start(tester);
    await tester.tap(find.textContaining('1:1').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Флм');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить'));
    await tester.pumpAndSettle();
    expect((tester.widget(find.byType(TextField)) as TextField).controller!.text, '');
    expect(find.byTooltip('Очистить'), findsNothing);
    // «Фил» → единственная подходящая, Enter открывает книгу без шага глав
    await tester.enterText(find.byType(TextField), 'Флм');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    final phlm = Books.instance.meta('Phlm').name;
    expect(find.text('С начала главы'), findsOneWidget);
    expect(inSheet(phlm), findsOneWidget); // заголовок без номера главы
    expect(inSheet('5'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('С начала главы'), findsNothing);
    expect(find.text('Перейти'), findsOneWidget); // сразу список, а не главы
    // глава → назад → список, прокрутка и шаги не ломаются
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(inSheet(Books.instance.meta('Gen').name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Перейти'), findsOneWidget);
    expect(c.read(panesProvider)[0].ref, startRef);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Перейти»: Ветхий / Новый Завет / Неканон, звёздочка у неканонических, свайп между заветами', (tester) async {
    await start(tester);
    await tester.tap(find.textContaining('1:1').first);
    await tester.pumpAndSettle();
    expect(find.text('Неканон'), findsOneWidget); // третья вкладка
    // в Ветхом: неканоническая книга со звёздочкой
    expect(inSheet(Books.instance.meta('Tob').short.replaceAll('.', '')), findsOneWidget);
    expect(inSheet('*'), findsOneWidget);
    expect(inSheet('Enoch'), findsNothing);
    // свайп влево по окну → Новый Завет → Неканон
    final body = find.text('Новый Завет');
    await tester.fling(body, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(inSheet(john.short.replaceAll('.', '')), findsOneWidget);
    expect(inSheet('Enoch'), findsNothing);
    await tester.fling(body, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(inSheet('Enoch'), findsWidgets);
    expect(inSheet(john.short.replaceAll('.', '')), findsNothing);
    // свайп вправо возвращает
    await tester.fling(body, const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    expect(inSheet(john.short.replaceAll('.', '')), findsOneWidget);
    // и нажатие на вкладку
    await tester.tap(find.text('Неканон'));
    await tester.pumpAndSettle();
    expect(inSheet('Enoch'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // --- Поиск → переход с подсветкой ----------------------------------------------------------------------------

  testWidgets('Поиск: переход к найденному стиху ведёт с подсветкой слова запроса', (tester) async {
    final c = await start(tester);
    await tester.tap(find.text('Поиск').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'светильник');
    await settle(tester);
    expect(find.textContaining('Найдено:'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AobSheet), matching: find.textContaining('главы')).first);
    await tester.pumpAndSettle();
    final mark = readerMarks.value[0];
    expect(mark, isNotNull);
    expect(mark!.highlight, 'светильник');
    expect(c.read(panesProvider)[0].ref.book, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  // --- Две панели --------------------------------------------------------------------------------------------------

  testWidgets('Две панели на широком экране: рядом, разделитель тянется, доля помнится', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await start(tester, size: const Size(1200, 800));
    await tester.tap(find.byTooltip('Читать параллельно'));
    await tester.pumpAndSettle();
    final panes = find.byType(ReaderPane);
    expect(panes, findsNWidgets(2));
    // колонки: вторая панель правее первой
    expect(tester.getTopLeft(panes.at(1)).dx, greaterThan(tester.getTopRight(panes.at(0)).dx - 1));
    expect(tester.getTopLeft(panes.at(1)).dy, tester.getTopLeft(panes.at(0)).dy);
    final w0 = tester.getSize(panes.at(0)).width;
    expect(w0, closeTo((1200 - 5) * 0.5, 2));
    final divider = find.bySemanticsLabel('Изменить размер панелей');
    expect(divider, findsOneWidget);
    await tester.drag(divider, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(panes.at(0)).width, closeTo((1200 - 5) * 0.7, 8));
    expect(c.read(settingsProvider).d('splitRatio'), closeTo(0.7, 0.01));
    // дальше предела 80 % не уехать
    await tester.drag(divider, const Offset(900, 0));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).d('splitRatio'), closeTo(0.8, 0.001));
    // доля помнится после перезапуска
    expect(jsonDecode(prefs.getString('settings')!)['splitRatio'], closeTo(0.8, 0.001));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('Две панели на телефоне: друг над другом, разделитель тянется вверх-вниз; настройка колонок переопределяет', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await start(tester);
    await tester.tap(find.byTooltip('Читать параллельно'));
    await tester.pumpAndSettle();
    final panes = find.byType(ReaderPane);
    expect(tester.getTopLeft(panes.at(1)).dy, greaterThan(tester.getBottomLeft(panes.at(0)).dy - 1));
    final h0 = tester.getSize(panes.at(0)).height;
    await tester.drag(find.bySemanticsLabel('Изменить размер панелей'), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(tester.getSize(panes.at(0)).height, lessThan(h0));
    expect(c.read(settingsProvider).d('splitRatio'), lessThan(0.5));
    c.read(settingsProvider.notifier).set({'splitLayout': 'columns'});
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(panes.at(1)).dy, tester.getTopLeft(panes.at(0)).dy);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('Авто-раскладка: ширина ≥ 720 и w > h·0.9 — колонки; уже или выше — строки', (tester) async {
    final two = jsonEncode([
      {'moduleId': 'rst-plus', 'ref': const VerseRef('Gen', 1, 1).toJson()},
      {'moduleId': 'rst-plus', 'ref': const VerseRef('Gen', 1, 1).toJson()},
    ]);
    await start(tester, size: const Size(800, 700), panes: two);
    var panes = find.byType(ReaderPane);
    expect(tester.getTopLeft(panes.at(1)).dy, tester.getTopLeft(panes.at(0)).dy); // 800 ≥ 720 и 800 > 630
    tester.view.physicalSize = const Size(800, 1000); // планшет вертикально
    await tester.pumpAndSettle();
    panes = find.byType(ReaderPane);
    expect(tester.getTopLeft(panes.at(1)).dy, greaterThan(tester.getTopLeft(panes.at(0)).dy));
    tester.view.physicalSize = const Size(700, 500); // уже 720 — строки
    await tester.pumpAndSettle();
    panes = find.byType(ReaderPane);
    expect(tester.getTopLeft(panes.at(1)).dy, greaterThan(tester.getTopLeft(panes.at(0)).dy));
    expect(tester.takeException(), isNull);
  });

  // --- Нижние вкладки -----------------------------------------------------------------------------------------------

  for (final theme in ['light', 'dark']) {
    testWidgets('Нижние вкладки: подсвечена вкладка открытого окна, плашка переезжает, провести пальцем — $theme', (tester) async {
      await start(tester, theme: theme);
      double pillX() => tester.getCenter(find.byKey(const ValueKey('tab-pill'))).dx;
      // центры вкладок: капсула 400 − 2·12, внутри поля по 5
      double tabX(String label) => 12 + 5 + (400 - 24 - 10) / 5 * ['Планы', 'Поиск', 'Библия', 'Закладки', 'Ещё'].indexOf(label) + (400 - 24 - 10) / 10;
      expect(tabActive.value, 'bible');
      expect(pillX(), closeTo(tabX('Библия'), 2));
      // «Поиск» открывает своё окно и подсвечивается
      await tester.tap(find.text('Поиск').last);
      await tester.pumpAndSettle();
      expect(tabActive.value, 'search');
      expect(pillX(), closeTo(tabX('Поиск'), 2));
      // окно закрылось — снова «Библия»
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tabActive.value, 'bible');
      expect(pillX(), closeTo(tabX('Библия'), 2));
      // проведение пальцем по панели вкладок: плашка идёт за пальцем, отпустили — раздел открылся
      final g = await tester.startGesture(tester.getCenter(find.text('Библия').last));
      await g.moveBy(const Offset(-30, 0));
      await tester.pump();
      await g.moveBy(const Offset(-43, 0));
      await tester.pump(); // кадр запускает движение плашки
      await tester.pump(const Duration(milliseconds: 200));
      expect(pillX(), closeTo(tabX('Поиск'), 2));
      await g.up();
      await tester.pumpAndSettle();
      expect(tabActive.value, 'search');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Точка «доступно обновление» на вкладке «Ещё» и на ⋮ широкого экрана', (tester) async {
    await start(tester);
    expect(find.bySemanticsLabel('Ещё. Доступно обновление'), findsNothing);
    final handle = tester.ensureSemantics();
    updateAvailable.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('Ещё. Доступно обновление'), findsOneWidget);
    updateAvailable.value = false;
    await tester.pump();
    expect(find.bySemanticsLabel('Ещё. Доступно обновление'), findsNothing);
    handle.dispose();
    // широкий экран: нижних вкладок нет — точка на ⋮
    tester.view.physicalSize = const Size(1200, 800);
    updateAvailable.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ещё. Доступно обновление'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // --- Режим чтения и режим плана -----------------------------------------------------------------------------------

  testWidgets('Режим чтения: шапка и вкладки уезжают при прокрутке вниз и возвращаются; без настройки не трогаем', (tester) async {
    await start(tester, settings: {'focusMode': true});
    expect(find.byTooltip('Читать параллельно').hitTestable(), findsOneWidget);
    expect(find.text('Библия').hitTestable(), findsOneWidget);
    focusHidden.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Читать параллельно').hitTestable(), findsNothing);
    expect(find.text('Библия').hitTestable(), findsNothing);
    focusHidden.value = false;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Читать параллельно').hitTestable(), findsOneWidget);
    expect(find.text('Библия').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Режим чтения выключен в настройках: панели на месте, даже если читалка просит спрятать', (tester) async {
    await start(tester);
    focusHidden.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Читать параллельно').hitTestable(), findsOneWidget);
    expect(find.text('Библия').hitTestable(), findsOneWidget);
  });

  testWidgets('Режим чтения: пока выделен стих — панели на месте; пока открыто окно — тоже', (tester) async {
    final c = await start(tester, settings: {'focusMode': true});
    focusHidden.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Библия').hitTestable(), findsNothing);
    c.read(selectionProvider.notifier).toggle(0, const VerseRef('Gen', 1, 1));
    await tester.pumpAndSettle();
    expect(find.text('Библия').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Читать параллельно').hitTestable(), findsOneWidget);
    c.read(selectionProvider.notifier).clear(0);
    focusHidden.value = true; // читалка сбрасывает при выделении — прокрутили вниз снова
    await tester.pumpAndSettle();
    expect(find.text('Библия').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Режим плана: вместо читалки рисуется Hub.planView; снимается — читалка возвращается', (tester) async {
    Hub.planView = (context, ref, pane) => Text('ПЛАН ПАНЕЛИ $pane');
    await start(tester);
    expect(find.byType(ReaderPane), findsOneWidget);
    setPlanMode(0, (uid: 'u1', day: 3));
    await tester.pump();
    expect(find.text('ПЛАН ПАНЕЛИ 0'), findsOneWidget);
    expect(find.byType(ReaderPane), findsNothing);
    expect(find.byTooltip('Читать параллельно'), findsOneWidget); // шапка осталась
    setPlanMode(0, null);
    await tester.pump();
    expect(find.text('ПЛАН ПАНЕЛИ 0'), findsNothing);
    expect(find.byType(ReaderPane), findsOneWidget);
    // без функции планов режим плана ничего не ломает
    Hub.planView = null;
    setPlanMode(0, (uid: 'u1', day: 3));
    await tester.pump();
    expect(find.byType(ReaderPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // --- Escape и размер шрифта окон ---------------------------------------------------------------------------------------

  testWidgets('Escape на широком экране: закрывает окно, снимает выделение', (tester) async {
    final c = await start(tester, size: const Size(1200, 800));
    c.read(selectionProvider.notifier).toggle(0, const VerseRef('Gen', 1, 2));
    await tester.pump();
    expect(c.read(selectionProvider)[0], isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.read(selectionProvider)[0], isEmpty);
    await tester.tap(find.textContaining('1:1').first);
    await tester.pumpAndSettle();
    expect(find.text('Перейти'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Перейти'), findsNothing);
    // в заполненном поле «Перейти» первый Escape стирает текст, второй закрывает окно
    await tester.tap(find.textContaining('1:1').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ин');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect((tester.widget(find.byType(TextField)) as TextField).controller!.text, '');
    expect(find.text('Перейти'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Перейти'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Размер шрифта меню и окон (uiFontSize) применяется и к обычным окнам AobSheet', (tester) async {
    Future<double> titleHeight(double size) async {
      await start(tester, settings: {'uiFontSize': size});
      await tester.tap(find.textContaining('1:1').first);
      await tester.pumpAndSettle();
      final h = tester.getSize(find.text('Перейти').first).height;
      await tester.pumpWidget(const SizedBox());
      return h;
    }

    final small = await titleHeight(15);
    final big = await titleHeight(20);
    expect(big, greaterThan(small * 1.25)); // 20/15 = 1.33
    expect(tester.takeException(), isNull);
  });
}
