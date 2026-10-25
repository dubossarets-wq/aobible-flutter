// Сценарная проверка оболочки и карт: экран 400×830, светлая/тёмная тема, textScale 1.3.
// Любое исключение Flutter (переполнение, бесконечные ограничения, setState после dispose) роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/maps/map_pane.dart';
import 'package:aobible/features/maps/maps_sheet.dart';
import 'package:aobible/features/maps/places_data.dart';
import 'package:aobible/features/shell/about_sheet.dart';
import 'package:aobible/features/shell/help_sheet.dart';
import 'package:aobible/features/shell/library_sheet.dart';
import 'package:aobible/features/shell/more_sheet.dart';
import 'package:aobible/features/shell/news_sheet.dart';
import 'package:aobible/features/shell/prefs_sheet.dart';
import 'package:aobible/features/shell/sheet.dart' show loadCatalog, loadSiteJson;
import 'package:aobible/features/shell/appearance_sheet.dart';
import 'package:aobible/features/shell/welcome_sheet.dart';
import 'package:aobible/ui/kit.dart';
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

void fakePlaces() {
  final j = {
    'places': [
      {'id': 'hebron', 'name': 'Хеврон', 'lat': 31.53, 'lng': 35.09, 'type': 'населённый пункт', 'confidence': 90, 'modern': 'Эль-Халиль', 'description': 'Город в горах Иудеи', 'stems': ['хевр'], 'refs': ['Josh.14.15', 'Gen.23.2']},
      {'id': 'galilee', 'name': 'Галилея', 'lat': 32.8, 'lng': 35.5, 'type': 'область', 'stems': ['гали'], 'refs': ['Matt.4.15']},
    ],
  };
  final db = sqlite3.open('${dir.path}/bible-places.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  convertPlaces(db, j);
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'bible-places', 'type': 'maps', 'name': 'Места', 'language': 'ru'})]);
  db.close();
}

void fakeMaps() {
  final db = sqlite3.open('${dir.path}/bible-maps.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('CREATE TABLE payload(json TEXT)');
  db.execute('INSERT INTO payload VALUES (?)', [
    jsonEncode({
      'maps': [
        {'id': 'm1', 'title': 'Исход', 'description': 'Путь из Египта', 'image': 'maps/none.png', 'refs': ['Exod.12.37']},
      ],
    })
  ]);
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'bible-maps', 'type': 'maps', 'name': 'Карты Библии', 'language': 'ru'})]);
  db.close();
}

enum Look { light, dark, big }

Widget host(ProviderContainer c, void Function(BuildContext, WidgetRef) open, Look look) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(look == Look.big ? 1.3 : 1.0)), child: child!),
        home: Consumer(builder: (context, ref, _) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => open(context, ref), child: const Text('открыть'))))),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_qa_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    fakeModule('t1', 'bible', 'ТТ1', 'ru');
    fakeModule('t2', 'bible', 'EN2', 'en');
    fakeModule('t3', 'bible', 'DE3', 'de');
    fakeModule('d1', 'dictionary', 'Словарик', 'ru');
    fakeModule('c1', 'commentary', 'Толкование', 'ru');
    fakeModule('a1', 'audio', 'Слушаем', 'en');
    fakePlaces();
    fakeMaps();
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.moreItems.clear();
    // Сеть в тестах не трогаем: каталог и список фото — свои
    loadCatalog = () async => [
          CatalogEntry({'id': 'cat-en', 'type': 'bible', 'name': 'KJV', 'title': 'King James', 'language': 'en', 'version': '1'}),
          CatalogEntry({'id': 'cat-ru', 'type': 'dictionary', 'name': 'Даль', 'title': 'Словарь Даля', 'language': 'ru', 'version': '1'}),
        ];
    loadSiteJson = (_) async => {
          'images': [
            {'id': 'p1', 'title': 'Горы', 'author': 'Автор Фото', 'license': 'CC0'},
          ],
        };
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 830);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<ProviderContainer> start(WidgetTester tester, Look look, void Function(BuildContext, WidgetRef) open) async {
    phone(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    if (look == Look.dark) c.read(settingsProvider.notifier).set({'theme': 'dark'});
    await tester.pumpWidget(host(c, open, look));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
    final f = last ? find.text(text).last : find.text(text).first;
    // список ленивый: нужной строки может ещё не быть в дереве — прокручиваем, пока не появится
    if (find.text(text).evaluate().isEmpty) {
      await tester.dragUntilVisible(find.text(text), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -150));
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  // Плашка в ряду, который прокручивается вбок: сначала показать, потом нажать
  Future<void> chip(WidgetTester tester, String label) async {
    final f = find.widgetWithText(AobChip, label).first;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.chevronLeft).last);
    await tester.pumpAndSettle();
  }

  for (final look in Look.values) {
    group('вид ${look.name}', () {
      testWidgets('«Ещё»: каждый пункт открывается на весь экран, «назад» возвращает, крестик закрывает все окна', (tester) async {
        Hub.moreItems.add(MoreItem(id: 'maps', icon: LucideIcons.map, label: 'Карты', order: 60, run: openMapsSheet));
        await start(tester, look, (c, r) => openMore(c, r, 0));
        for (final label in ['Карты', 'Оформление', 'Настройки', 'Инструкция', 'Что нового', 'О приложении']) {
          await tapText(tester, label);
          expect(find.byTooltip('Назад'), findsOneWidget, reason: label);
          await back(tester);
          expect(find.text('Ещё'), findsOneWidget, reason: 'после «назад» из «$label»');
        }
        await tapText(tester, 'Настройки');
        await tapText(tester, 'Язык');
        await tester.tap(find.byTooltip('Закрыть').last);
        await tester.pumpAndSettle();
        expect(find.text('Ещё'), findsNothing);
        expect(find.text('Настройки'), findsNothing);
        expect(find.text('открыть'), findsOneWidget);
      });

      testWidgets('Настройки: каждая строка; язык и обратно; меню; аудио', (tester) async {
        final c = await start(tester, look, (ctx, r) => openPrefs(ctx));
        await tapText(tester, 'Меню «Ещё»');
        for (final m in ['Проповеди', 'Планы чтения', 'Карты']) {
          await tapText(tester, m);
        }
        expect((c.read(settingsProvider).j['menu'] as Map)['maps'], isNotNull);
        await back(tester);
        await tapText(tester, 'Аудио');
        await tester.tap(find.textContaining('ИИ-диктор, когда нет записи'));
        await tester.pumpAndSettle();
        await back(tester);
        for (final label in ['Инструкция', 'Оформление', 'Библиотека модулей', 'Что нового', 'О приложении']) {
          await tapText(tester, label, last: label == 'Оформление');
          expect(find.byTooltip('Назад'), findsOneWidget, reason: label);
          await back(tester);
        }
        await tapText(tester, 'Язык');
        await tester.runAsync(() async {
          await tester.tap(find.text('English'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(currentLang, 'en');
        expect(find.text('Settings'), findsOneWidget);
        await tester.tap(find.text('Language'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Русский'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(currentLang, 'ru');
        expect(find.text('Настройки'), findsOneWidget);
      });

      testWidgets('Оформление: все подразделы, все темы, свои цвета, сброс с подтверждением', (tester) async {
        final c = await start(tester, look, (ctx, r) => openAppearance(ctx));
        Settings s() => c.read(settingsProvider);
        for (final e in themes.entries) {
          final tile = find.text(e.value.label);
          await tester.ensureVisible(tile.first);
          await tester.tap(tile.first);
          await tester.pumpAndSettle();
          expect(s().get<String>('theme'), e.key);
        }
        for (final k in ['По стихам', 'Сплошной', 'Как книга']) {
          await tapText(tester, k);
        }
        for (final block in ['Шрифт', 'Номера и заголовки', 'Цвета', 'Кнопки и панели']) {
          await tapText(tester, block, last: true);
          expect(find.byTooltip('Назад'), findsOneWidget, reason: block);
          if (block == 'Цвета') {
            await tester.tap(find.byTooltip('Синий').first);
            await tester.pumpAndSettle();
            expect((s().j['colorOverrides'] as Map)['accent'], '#2563eb');
            await tester.tap(find.byTooltip('Свой цвет').first);
            await tester.pumpAndSettle();
            await tapText(tester, 'Готово');
            await tapText(tester, 'Все цвета — как в теме');
            expect(s().j['colorOverrides'] as Map, isEmpty);
          }
          if (block == 'Номера и заголовки') {
            for (var k = 0; k < 3; k++) {
              final sw = find.byType(AobSwitch).first;
              await tester.ensureVisible(sw);
              await tester.tap(sw);
              await tester.pumpAndSettle();
            }
          }
          if (block == 'Кнопки и панели') {
            await tapText(tester, 'Рядом');
            await tapText(tester, 'Друг над другом');
            await tapText(tester, 'Авто');
          }
          await back(tester);
        }
        await tester.dragUntilVisible(find.text('Сбросить оформление'), find.byType(ListView).last, const Offset(0, -200));
        await tester.ensureVisible(find.text('Сбросить оформление'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сбросить оформление'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Да, сбросить'));
        await tester.pumpAndSettle();
        expect(s().get<String>('theme'), 'light');
      });

      testWidgets('Библиотека: вкладки, любые сочетания типа и языка, карточка, основной, удаление', (tester) async {
        final c = await start(tester, look, (ctx, r) => openLibrary(ctx));
        expect(find.text('ТТ1'), findsOneWidget);
        for (final lang in ['Русский', 'English', 'Немецкий']) {
          await chip(tester, lang);
          await tester.pumpAndSettle();
          expect(find.text('Ничего не найдено.'), findsNothing, reason: 'Все типы + $lang');
          expect(find.byIcon(LucideIcons.chevronDown), findsWidgets, reason: lang);
        }
        await chip(tester, 'Все языки');
        await tester.pumpAndSettle();
        for (final kind in ['Переводы', 'Комментарии', 'Словари', 'Аудиокниги', 'Все']) {
          await chip(tester, kind);
          await tester.pumpAndSettle();
          expect(find.text('Модулей нет'), findsNothing, reason: kind);
        }
        await chip(tester, 'Переводы');
        await tester.pumpAndSettle();
        await chip(tester, 'English');
        await tester.pumpAndSettle();
        expect(find.text('EN2'), findsOneWidget);
        expect(find.text('ТТ1'), findsNothing);
        await chip(tester, 'Словари');
        await tester.pumpAndSettle();
        expect(find.text('Словарик'), findsOneWidget);
        await chip(tester, 'Все');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'яяяя');
        await tester.pumpAndSettle();
        expect(find.text('Ничего не найдено.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        await chip(tester, 'Все языки');
        await tester.tap(find.text('Каталог'));
        await tester.pumpAndSettle();
        expect(find.text('KJV'), findsOneWidget);
        expect(find.text('Даль'), findsOneWidget);
        await chip(tester, 'English');
        expect(find.text('Даль'), findsNothing);
        await chip(tester, 'Все языки');
        await tester.tap(find.text('Установленные'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('EN2'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AobButton, 'Сделать основным'));
        await tester.pumpAndSettle();
        expect(c.read(settingsProvider).get<String>('primaryModule'), 't2');
        await tester.tap(find.text('Удалить'));
        await tester.pumpAndSettle();
        expect(ModuleStore.instance.get('t2'), isNotNull);
        await tester.runAsync(() async {
          await tester.tap(find.text('Удалить').last);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(ModuleStore.instance.get('t2'), isNull);
      });

      testWidgets('О приложении: три вкладки, «Фотографии»', (tester) async {
        await start(tester, look, (ctx, r) => openAbout(ctx));
        for (final tab in ['Лицензии и авторы', 'Конфиденциальность', 'О приложении']) {
          final f = find.text(tab);
          await tester.ensureVisible(f.last);
          await tester.tap(f.last);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Лицензии и авторы'));
        await tester.tap(find.text('Лицензии и авторы'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Фотографии'));
        expect(find.text('Горы'), findsOneWidget);
        expect(find.text('Фотографии'), findsOneWidget);
      });

      testWidgets('Что нового', (tester) async {
        await start(tester, look, (ctx, r) => openNews(ctx));
        expect(find.text('Что нового'), findsOneWidget);
        await tapText(tester, 'Понятно');
        await tester.pumpAndSettle();
        expect(find.text('Что нового'), findsNothing);
      });

      testWidgets('Приветствие: три шага', (tester) async {
        prefs.setBool('welcomePending', true);
        await start(tester, look, (ctx, r) => openWelcome(ctx));
        await tapText(tester, 'Далее');
        await tapText(tester, 'Далее');
        await tapText(tester, 'Начать чтение');
        expect(find.text('Добро пожаловать'), findsNothing);
      });

      testWidgets('Инструкция: уроки, поиск без результатов, шаги', (tester) async {
        await start(tester, look, (ctx, r) => openHelp(ctx));
        await tester.enterText(find.byType(TextField), 'яяяяя');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        // урок закрывает окно и подсвечивает места прямо в приложении
        await tester.tap(find.text('Перейти к книге, главе, стиху'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Нажмите — откроется список книг.'), findsOneWidget);
        await tester.tap(find.byTooltip('Закончить инструкцию'));
        await tester.pumpAndSettle();
        expect(find.text('Нажмите — откроется список книг.'), findsNothing);
      });

      testWidgets('Карты: список, поиск мест, пустой поиск, плитка карты', (tester) async {
        await start(tester, look, (c, r) => openMapsSheet(c, r, 0));
        expect(find.text('Исход'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'хев');
        await tester.pumpAndSettle();
        expect(find.text('Хеврон'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'яяя');
        await tester.pumpAndSettle();
        expect(find.text('Ничего не найдено.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Исход'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Увеличить'));
        await tester.tap(find.byTooltip('Уменьшить'));
        await tester.pumpAndSettle();
        expect(find.text('Путь из Египта'), findsOneWidget);
        await tester.tap(find.byIcon(LucideIcons.chevronLeft).last);
        await tester.pumpAndSettle();
        expect(find.text('Исход'), findsOneWidget);
      });
    });
  }

  testWidgets('Карта места: панель с карточкой, сворачивание, стих, закрытие', (tester) async {
    phone(tester);
    mapViewBuilder = (target, zoom, onCreated, onStyle) => const SizedBox.expand(); // платформенной карты в тестах нет
    final place = PlaceStore.search('Хеврон').single;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var closed = false;
    VerseRef? opened;
    for (final dark in [false, true]) {
      c.read(settingsProvider.notifier).set({'theme': dark ? 'dark' : 'light'});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(dark ? 1.3 : 1.0)), child: child!),
          home: Scaffold(body: MapPaneView(key: ValueKey(dark), place: place, onClose: () => closed = true, onOpenVerse: (r) => opened = r)),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Хеврон'), findsWidgets);
      await tester.tap(find.textContaining('населённый пункт').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Город в горах Иудеи'), findsOneWidget);
      expect(find.textContaining('Эль-Халиль'), findsOneWidget);
      await tester.tap(find.byType(AobChip).first);
      await tester.pump();
      expect(opened, isNotNull);
      await tester.tap(find.byTooltip('Закрыть карту'));
      expect(closed, true);
      closed = false;
      opened = null;
    }
  });
}
