// Сценарии оболочки и карт: фон под текстом, комментарии и подписи цветов в «Оформлении», тема «Как в системе»,
// библиотека (импорт файла, свой каталог, включение и выключение), меню «Ещё» (флаги, широкий экран), инструкция с подсветкой.
// Экран 400×830, светлая и тёмная тема, крупный шрифт; любое исключение Flutter (переполнение, setState после dispose) роняет тест.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/bookmarks/marks.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/maps/maps.dart' as maps;
import 'package:aobible/features/shell/appearance_sheet.dart';
import 'package:aobible/features/shell/background.dart';
import 'package:aobible/features/shell/help_sheet.dart';
import 'package:aobible/features/shell/library_import.dart';
import 'package:aobible/features/shell/library_sheet.dart';
import 'package:aobible/features/shell/more_sheet.dart';
import 'package:aobible/features/shell/prefs_sheet.dart';
import 'package:aobible/features/shell/sheet.dart' show loadCatalog, loadSiteJson;
import 'package:aobible/features/shell/tour.dart';
import 'package:aobible/features/shell/tour_targets.dart';
import 'package:aobible/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

// Настоящая картинка 1×1 (PNG)
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void fakeModule(String id, String type, String name, String lang) {
  final db = sqlite3.open('${dir.path}/$id.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': id, 'type': type, 'name': name, 'title': 'Тест $name', 'language': lang})]);
  db.close();
}

enum Look { light, dark, big }

Widget host(ProviderContainer c, void Function(BuildContext, WidgetRef) open, Look look, {Widget? extra}) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: Hub.navigatorKey,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(look == Look.big ? 1.3 : 1.0)), child: child!),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(children: [
              ElevatedButton(onPressed: () => open(context, ref), child: const Text('открыть')),
              ?extra,
            ]),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_fsm_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    userBgDir = Directory('${dir.path}/ubg');
    UserBg.version.value = 0;
    fakeModule('t1', 'bible', 'ТТ1', 'ru');
    fakeModule('d1', 'dictionary', 'Словарик', 'ru');
    fakeModule('c1', 'commentary', 'Толкование', 'ru');
    fakeModule('c2', 'commentary', 'Второе', 'ru');
    fakeModule('mp', 'maps', 'Карты Библии', 'ru');
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    loadCatalog = () async => [CatalogEntry({'id': 'cat-ru', 'type': 'dictionary', 'name': 'Даль', 'title': 'Словарь Даля', 'language': 'ru', 'version': '1'})];
    loadSiteJson = (_) async => {
          'images': [
            {'id': 'p1', 'title': 'Горы', 'file': 'p1.jpg', 'thumb': 'p1t.jpg'},
            {'id': 'p2', 'title': 'Море', 'file': 'p2.jpg', 'thumb': 'p2t.jpg'},
          ],
        };
    loadSiteBytes = (_) async => Uint8List.fromList(png);
    pickBgImage = () async => Uint8List.fromList(png);
  });

  void screen(WidgetTester tester, {double w = 400, double h = 830}) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<ProviderContainer> start(WidgetTester tester, Look look, void Function(BuildContext, WidgetRef) open, {double w = 400, Widget? extra, String? theme}) async {
    screen(tester, w: w);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final t0 = theme ?? (look == Look.dark ? 'dark' : null);
    if (t0 != null) c.read(settingsProvider.notifier).set({'theme': t0});
    await tester.pumpWidget(host(c, open, look, extra: extra));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    return c;
  }

  // Настоящая работа в потоке (Isolate, файлы) идёт вне «ложных» часов теста
  Future<void> real(WidgetTester tester, [int ms = 400]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pumpAndSettle();
  }

  // Ждём окончания чтения или установки файла: пока на карточке вертушка (прогресс), даём потоку работать
  Future<void> imported(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await real(tester, 150);
      if (find.byType(AobProgress).evaluate().isEmpty) return;
    }
  }

  Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
    final f = last ? find.text(text).last : find.text(text).first;
    if (find.text(text).evaluate().isEmpty) {
      await tester.dragUntilVisible(find.text(text), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -150));
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  // Список в окне ленивый: к началу — прокрутить вверх, чтобы кнопка «Выбрать файлы» снова была в дереве
  Future<void> pickFiles(WidgetTester tester) async {
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last;
    await tester.drag(list, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать файлы'));
    await imported(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
  }

  for (final look in Look.values) {
    group('вид ${look.name}', () {
      testWidgets('Оформление → Фон: готовое фото, своё фото, «Картинку видно», «Размытие», без фона', (tester) async {
        final c = await start(tester, look, (ctx, r) => openAppearance(ctx));
        Settings s() => c.read(settingsProvider);
        expect(find.text('Без фона'), findsOneWidget); // подпись строки подраздела
        await tapText(tester, 'Фон', last: true);
        expect(find.byTooltip('Назад'), findsOneWidget);
        expect(find.text('Без фона'), findsOneWidget);
        expect(find.text('Своё фото'), findsOneWidget);
        expect(find.byTooltip('Горы'), findsOneWidget);
        expect(find.byTooltip('Море'), findsOneWidget);
        expect(find.text('Картинку видно'), findsNothing); // пока фона нет, ползунков нет
        expect(find.text('Картинка хранится только на этом устройстве.'), findsOneWidget);

        // готовое фото
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Горы'));
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await tester.pumpAndSettle();
        expect(s().j['bgPhoto'], 'p1');
        expect((s().j['bgImage'] as num) > 0, isTrue);
        expect(find.text('Картинку видно'), findsOneWidget);
        expect(find.text('Размытие'), findsOneWidget);
        expect(find.text('нет'), findsOneWidget); // размытие 0
        expect(File('${userBgDir!.path}/bg.img').existsSync(), isTrue);

        // ползунки: «видно» = 100 − вуаль (по умолчанию 72 → 28%)
        expect(find.text('28%'), findsOneWidget);
        final plus = find.byTooltip('Больше');
        if (plus.evaluate().isNotEmpty) {
          await tester.tap(plus.first);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 300));
          expect((s().j['bgVeil'] as num) < 72, isTrue);
        }
        c.read(settingsProvider.notifier).set({'bgBlur': 10});
        await tester.pumpAndSettle();
        expect(find.text('среднее'), findsOneWidget);

        // своё фото
        await tester.runAsync(() async {
          await tester.tap(find.text('Своё фото'));
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await tester.pumpAndSettle();
        expect(s().j['bgPhoto'], isNull);
        expect((s().j['bgImage'] as num) > 0, isTrue);

        // без фона
        await tester.runAsync(() async {
          await tester.tap(find.text('Без фона'));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(s().j['bgImage'], 0);
        expect(find.text('Картинку видно'), findsNothing);
        await back(tester);
        expect(find.text('Без фона'), findsOneWidget);
      });

      testWidgets('ReaderBackground: рисует картинку, пока фон включён; без фона — пусто', (tester) async {
        screen(tester);
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: SizedBox(width: 300, height: 300, child: ReaderBackground()))),
        ));
        expect(find.byType(Image), findsNothing);
        await tester.runAsync(() => UserBg.save(Uint8List.fromList(png)));
        c.read(settingsProvider.notifier).set({'bgImage': 5, 'bgVeil': 60, 'bgBlur': 4});
        await real(tester, 100);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(ImageFiltered), findsWidgets);
        c.read(settingsProvider.notifier).set({'bgImage': 0});
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
      });

      testWidgets('Оформление → Комментарии: размер текста и какие видны после стиха', (tester) async {
        final c = await start(tester, look, (ctx, r) => openAppearance(ctx));
        Settings s() => c.read(settingsProvider);
        expect(find.text('2 из 2'), findsOneWidget);
        await tapText(tester, 'Комментарии', last: true);
        expect(find.text('Так выглядит текст комментария.'), findsOneWidget);
        expect(find.text('Комментарии в тексте'), findsOneWidget);
        expect(find.textContaining('Толкование', findRichText: true), findsOneWidget);
        expect(find.textContaining('Второе', findRichText: true), findsOneWidget);
        // выключили «Второе»: остаётся один
        await tester.tap(find.byType(AobSwitch).last);
        await tester.pumpAndSettle();
        expect(s().j['inlineCommentaries'], ['c1']);
        await tester.tap(find.byType(AobSwitch).last);
        await tester.pumpAndSettle();
        expect((s().j['inlineCommentaries'] as List).toSet(), {'c1', 'c2'});
        c.read(settingsProvider.notifier).set({'commentaryFontSize': 24.0});
        await tester.pumpAndSettle();
        expect(find.text('24 px'), findsOneWidget);
        await back(tester);
        expect(find.text('2 из 2'), findsOneWidget);
        // сброс оформления возвращает «все комментарии»
        await tester.dragUntilVisible(find.text('Сбросить оформление'), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -200));
        await tester.ensureVisible(find.text('Сбросить оформление'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сбросить оформление'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Да, сбросить'));
        await tester.pumpAndSettle();
        expect(s().j['inlineCommentaries'], isNull);
        expect(s().d('commentaryFontSize'), 19.0);
      });

      testWidgets('Оформление → Цвета: подписи цветов выделений сохраняются как в веб-версии', (tester) async {
        final c = await start(tester, look, (ctx, r) => openAppearance(ctx));
        await tapText(tester, 'Цвета', last: true);
        await tester.dragUntilVisible(find.text('Цвета выделений'), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -200));
        await tester.ensureVisible(find.text('Цвета выделений'));
        await tester.pumpAndSettle();
        expect(find.text('Дайте цветам названия — например, «Обетования», «Вопросы».'), findsOneWidget);
        final field = find.widgetWithText(TextField, '').first;
        await tester.ensureVisible(field);
        await tester.enterText(find.byType(TextField).first, 'Обетования');
        await tester.pumpAndSettle();
        expect(c.read(marksProvider).hlLabels['1'], 'Обетования');
        expect(jsonDecode(prefs.getString('highlightLabels')!), {'1': 'Обетования'});
        expect(hlColors.length, 6);
      });

      testWidgets('Тема «Как в системе»', (tester) async {
        final c = await start(tester, look, (ctx, r) => openAppearance(ctx));
        final tile = find.text('Системная');
        await tester.dragUntilVisible(tile, find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal).first, const Offset(-150, 0));
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(c.read(settingsProvider).get<String>('theme'), 'auto');
        systemDark.value = true;
        expect(c.read(settingsProvider).palette.dark, isTrue);
        systemDark.value = false;
        expect(c.read(settingsProvider).palette.dark, isFalse);
      });

      testWidgets('Библиотека → Импорт: словарь, перевод списком стихов, ошибки; замена; выключение', (tester) async {
        final c = await start(tester, look, (ctx, r) => openLibrary(ctx));
        Settings s() => c.read(settingsProvider);
        expect(s().get<String>('primaryModule'), isNotEmpty);
        await tester.ensureVisible(find.text('Импорт', findRichText: true));
        await tester.tap(find.text('Импорт', findRichText: true));
        await tester.pumpAndSettle();
        expect(find.text('Выбрать файлы'), findsOneWidget);
        expect(find.byType(AobInput), findsNothing); // на вкладке «Импорт» нет поиска

        // 1) словарь в родном формате
        pickModuleFiles = () async => [('my-dict.json', Uint8List.fromList(utf8.encode(moduleSample)))];
        await pickFiles(tester);
        expect(find.text('Мой словарь'), findsOneWidget);
        expect(find.textContaining('my-dictionary'), findsOneWidget);
        expect(find.text('Установить'), findsOneWidget);
        await tester.tap(find.text('Установить'));
        await imported(tester);
        expect(ModuleStore.instance.get('my-dictionary')?.type, 'dictionary');
        expect(find.text('Установлен'), findsOneWidget);

        // 2) тот же файл ещё раз — «Заменить установленный»
        await pickFiles(tester);
        expect(find.text('Заменить установленный'), findsOneWidget);

        // 3) не модуль и каталог — ошибки понятным текстом
        pickModuleFiles = () async => [
              ('bad.json', Uint8List.fromList(utf8.encode('{"a": 1}'))),
              ('cat.json', Uint8List.fromList(utf8.encode('{"format":"aob-catalog","modules":[]}'))),
              ('broken.json', Uint8List.fromList(utf8.encode('{не json'))),
            ];
        await pickFiles(tester);
        expect(find.textContaining('Не удалось определить тип модуля'), findsOneWidget);
        expect(find.textContaining('Это файл каталога, а не модуль'), findsOneWidget);
        expect(find.textContaining('Файл не является корректным JSON'), findsOneWidget);
        // карточку с ошибкой можно убрать
        await tester.ensureVisible(find.text('Убрать').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Убрать').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('Файл не является корректным JSON'), findsNothing);

        // 4) перевод списком стихов
        final verses = jsonEncode([
          {'book': 'Gen', 'chapter': 1, 'verse': 1, 'text': 'Вначале'},
          {'book': 'Gen', 'chapter': 1, 'verse': 2, 'text': 'Земля'},
          {'book': 'Исход', 'chapter': 1, 'verse': 1, 'text': 'Вот имена'},
        ]);
        pickModuleFiles = () async => [('мой перевод.json.gz', Uint8List.fromList(gzip.encode(utf8.encode(verses))))];
        await pickFiles(tester);
        await tester.dragUntilVisible(find.textContaining('2 кн., 3 стихов', findRichText: true), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -150));
        expect(find.textContaining('2 кн., 3 стихов', findRichText: true), findsOneWidget);
        await tester.ensureVisible(find.text('Установить').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Установить').last);
        await imported(tester);
        final bible = ModuleStore.instance.bibles.where((b) => b.id.startsWith('мой-перевод')).single;
        expect(bible.meta['stats']['verses'], 3);

        // «К установленным»: импортированный словарь в списке, у него переключатель
        await tester.ensureVisible(find.text('К установленным').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('К установленным').first);
        await tester.pumpAndSettle();
        expect(find.text('Мой словарь'), findsOneWidget);
      });

      testWidgets('Библиотека: переключатель и свайп включают и выключают небиблейский модуль', (tester) async {
        await start(tester, look, (ctx, r) => openLibrary(ctx));
        final store = ModuleStore.instance;
        final before = store.changes.value;
        expect(find.byType(RowSwitch), findsWidgets);
        expect(store.installed.map((m) => m.id), contains('d1'));
        // у перевода переключателя нет, только звезда
        expect(find.byType(RowSwitch).evaluate().length, store.allInstalled.where((m) => m.type != 'bible').length);

        // нажатие
        final sw = find.byType(RowSwitch).first;
        await tester.runAsync(() async {
          await tester.tap(sw);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final off = store.allInstalled.where((m) => m.type != 'bible' && !store.isEnabled(m.id)).toList();
        expect(off.length, 1);
        expect(store.installed.map((m) => m.id), isNot(contains(off.first.id))); // не участвует в словарях и комментариях
        expect(store.get(off.first.id), isNotNull); // но остаётся установленным
        expect(store.changes.value, greaterThan(before));

        // свайп вправо возвращает
        final pos = tester.getCenter(find.byType(RowSwitch).first);
        await tester.runAsync(() async {
          await tester.dragFrom(pos, const Offset(60, 0));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(store.allInstalled.where((m) => m.type != 'bible' && !store.isEnabled(m.id)), isEmpty);

        // решение переживает перезапуск
        await tester.runAsync(() async {
          await tester.tap(find.byType(RowSwitch).first);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final id = store.allInstalled.firstWhere((m) => !store.isEnabled(m.id)).id;
        await tester.runAsync(() => ModuleStore.initAt(dir));
        expect(ModuleStore.instance.isEnabled(id), isFalse);
        expect(ModuleStore.instance.installed.where((m) => m.id == id), isEmpty);
      });

      testWidgets('Библиотека → Каталог: «Источник каталога», «Обновить список», «Встроенный каталог»', (tester) async {
        await start(tester, look, (ctx, r) => openLibrary(ctx));
        await tester.tap(find.text('Каталог', findRichText: true));
        await tester.pumpAndSettle();
        expect(find.text('Даль'), findsOneWidget);
        await tapText(tester, 'Источник каталога');
        expect(find.textContaining('Сейчас — встроенный каталог.'), findsOneWidget);
        expect(find.text('Встроенный каталог'), findsNothing);
        await tester.tap(find.text('Обновить список'));
        await tester.pumpAndSettle();
        expect(find.text('Даль'), findsOneWidget);
        // свой адрес (сети в тесте нет — понятная ошибка), вернуться к встроенному
        await tester.enterText(find.byType(TextField).last, 'http://127.0.0.1:1/catalog.json');
        await tester.tap(find.text('Подключить'));
        await real(tester, 600);
        expect(find.textContaining('http://127.0.0.1:1/catalog.json'), findsWidgets);
        expect(find.text('Встроенный каталог'), findsOneWidget);
        await tester.ensureVisible(find.text('Встроенный каталог'));
        // ensureVisible подводит кнопку к самому низу окна, а там вкладки поверх — докручиваем до конца: запас прокрутки поднимает её над вкладками
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Встроенный каталог'));
        await real(tester, 100);
        expect(find.text('Даль'), findsOneWidget);
        expect(find.text('Встроенный каталог'), findsNothing);
      });

      testWidgets('Меню «Ещё»: флаги прячут пункты; «Карты» — только с модулем карт', (tester) async {
        Hub.moreItems
          ..add(MoreItem(id: 'sermons', icon: LucideIcons.scrollText, label: 'Проповеди', order: 20, run: (c, r, p) {}))
          ..add(MoreItem(id: 'mydata', icon: LucideIcons.hardDrive, label: 'Мои данные', order: 80, run: (c, r, p) {}))
          ..add(MoreItem(id: 'audio', icon: LucideIcons.headphones, label: 'Аудио', order: 60, run: (c, r, p) {}));
        maps.register();
        Hub.listenFrom = (c, r, p, at) {};
        final c = await start(tester, look, (ctx, r) => openMore(ctx, r, 0));
        for (final label in ['Закладка на это место', 'Проповеди', 'Карты', 'Слушать с этого места', 'Оформление', 'Настройки']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('Мои данные'), findsNothing); // их в веб-версии в «Ещё» нет — они в «Настройках»
        expect(find.text('Аудио'), findsNothing);
        expect(find.text('Закладки и заметки'), findsNothing); // на телефоне у них своя вкладка
        expect(find.text('Планы чтения'), findsNothing);
        expect(find.text('К последней закладке'), findsNothing); // закладок ещё нет

        Future<void> reopen() async {
          Navigator.of(tester.element(find.text('Ещё').first)).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.text('открыть'));
          await tester.pumpAndSettle();
        }

        c.read(settingsProvider.notifier).set({
          'menu': {...Settings.defaults['menu'] as Map, 'sermons': false, 'maps': false, 'listen': false},
        });
        await reopen();
        expect(find.text('Проповеди'), findsNothing);
        expect(find.text('Карты'), findsNothing);
        expect(find.text('Слушать с этого места'), findsNothing);
        expect(find.text('Закладка на это место'), findsOneWidget);

        // флаг включён, но модуля карт нет — пункта нет
        c.read(settingsProvider.notifier).set({
          'menu': {...Settings.defaults['menu'] as Map, 'maps': true},
        });
        await tester.runAsync(() => ModuleStore.instance.remove('mp'));
        await reopen();
        expect(find.text('Карты'), findsNothing);
        expect(find.text('Проповеди'), findsOneWidget);

        // закладка на это место и «К последней закладке»
        await tester.tap(find.text('Закладка на это место'));
        await tester.pumpAndSettle();
        expect(c.read(marksProvider).bookmarks.length, 1);
        expect(find.text('Ещё'), findsNothing); // действие закрыло меню
        await tester.tap(find.text('открыть'));
        await tester.pumpAndSettle();
        expect(find.text('Убрать закладку'), findsOneWidget);
        expect(find.text('К последней закладке'), findsOneWidget);
        c.read(settingsProvider.notifier).set({
          'menu': {...Settings.defaults['menu'] as Map, 'lastBookmark': false},
        });
        await reopen();
        expect(find.text('К последней закладке'), findsNothing);
      });

      testWidgets('Широкий экран: в меню ⋮ «Закладки и заметки» и «Планы чтения»; страница настроек называется «Меню ⋮»', (tester) async {
        var plans = 0, saved = 0;
        Hub.openPlans = (c, r, p) => plans++;
        Hub.openBookmarks = (c, r, p) => saved++;
        final c = await start(tester, look, (ctx, r) => openMore(ctx, r, 0), w: 1000);
        expect(find.text('Закладки и заметки'), findsOneWidget);
        expect(find.text('Планы чтения'), findsOneWidget);
        await tester.tap(find.text('Планы чтения'));
        await tester.pumpAndSettle();
        expect(plans, 1);
        await tester.tap(find.text('открыть'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Закладки и заметки'));
        await tester.pumpAndSettle();
        expect(saved, 1);
        // флаг «Планы чтения» прячет пункт
        c.read(settingsProvider.notifier).set({
          'menu': {...Settings.defaults['menu'] as Map, 'plans': false},
        });
        await tester.tap(find.text('открыть'));
        await tester.pumpAndSettle();
        expect(find.text('Планы чтения'), findsNothing);
        Navigator.of(tester.element(find.text('Ещё').first)).pop();
        await tester.pumpAndSettle();

        // настройки на широком экране
        await tester.tap(find.text('открыть'));
        await tester.pumpAndSettle();
        openPrefs(tester.element(find.text('открыть')));
        await tester.pumpAndSettle();
        expect(find.text('Меню ⋮'), findsOneWidget);
        expect(find.text('Выбрать пункты меню'), findsOneWidget);
        await tester.tap(find.text('Меню ⋮'));
        await tester.pumpAndSettle();
        expect(find.text('Отметьте, что показывать в меню ⋮. Остальное всегда есть в настройках.'), findsOneWidget);
        expect(find.text('Меню «Ещё»'), findsNothing);
      });

      testWidgets('Инструкция: подсветка, «Далее», «Назад», условия шага, закрытие', (tester) async {
        var tapped = 0;
        final c = await start(
          tester,
          look,
          (ctx, r) => openHelp(ctx),
          extra: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: tourKey('tb-ref'),
              onTap: () => tapped++,
              child: Container(width: 120, height: 40, color: Colors.amber, child: const Text('Быт 1:1')),
            ),
          ),
        );
        await tester.tap(find.text('Перейти к книге, главе, стиху'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tourActive, isTrue);
        expect(find.text('Нажмите — откроется список книг.'), findsOneWidget);
        expect(find.textContaining('шаг 1 из 4'), findsOneWidget);
        expect(find.text('Назад'), findsNothing);
        // рамка встала на ключевой виджет (с отступом 6)
        final target = tester.getRect(find.byKey(tourKey('tb-ref')));
        expect(targetRect('tb-ref'), target);
        // «Далее» делает действие за человека: нажимает на подсвеченное и открывает «книги»
        await tester.tap(find.text('Далее'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tapped, 1);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('шаг 2 из 4'), findsOneWidget);
        expect(find.text('Назад'), findsOneWidget);
        await tester.tap(find.text('Назад'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('шаг 1 из 4'), findsOneWidget);
        // человек сам нажал на подсвеченное — урок идёт дальше
        await tester.tapAt(target.center);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tapped, 2);
        expect(find.textContaining('шаг 2 из 4'), findsOneWidget);
        // последний шаг — «Понятно»
        goStep(3);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Понятно'), findsOneWidget);
        await tester.tap(find.text('Понятно'));
        await tester.pumpAndSettle();
        expect(tourActive, isFalse);
        expect(find.textContaining('шаг'), findsNothing);
        expect(c.read(panesProvider).length, 1);
      });

      testWidgets('Инструкция: шаг с условием идёт сам, когда условие выполнено («Два перевода рядом»)', (tester) async {
        final c = await start(tester, look, (ctx, r) => openHelp(ctx));
        startTour('split');
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('шаг 1 из 3'), findsOneWidget);
        c.read(panesProvider.notifier).toggleSplit();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('шаг 2 из 3'), findsOneWidget);
        stopTour();
        await tester.pumpAndSettle();
        expect(tourActive, isFalse);
      });

      testWidgets('Инструкция: все уроки проходятся до конца без ошибок (телефон и широкий экран)', (tester) async {
        for (final w in [400.0, 1000.0]) {
          await start(tester, look, (ctx, r) => openHelp(ctx), w: w);
          // реальные окна ниже открывают шаги — здесь они мешают только поиску; сеть и аудио в тесте не нужны
          Navigator.of(tester.element(find.text('Инструкция').first)).pop();
          await tester.pumpAndSettle();
          for (final def in tourDefs) {
            final n = def.steps(w < 900).length;
            startTour(def.id);
            await tester.pump(const Duration(milliseconds: 600));
            for (var i = 0; i < n; i++) {
              expect(find.textContaining('шаг ${i + 1} из $n'), findsOneWidget, reason: '${def.id} шаг ${i + 1} (ширина $w)');
              // подсказка с текстом шага на экране
              final text = def.steps(w < 900)[i].text;
              expect(find.text(t(text)), findsOneWidget, reason: text);
              if (i == n - 1) {
                await tester.tap(find.text('Понятно'));
              } else {
                goStep(i + 1);
              }
              await tester.pump(const Duration(milliseconds: 400));
            }
            await tester.pumpAndSettle();
            expect(tourActive, isFalse, reason: def.id);
            // чистый экран для следующего урока
            if (Navigator.of(tester.element(find.text('открыть').first)).canPop()) {
              Navigator.of(tester.element(find.text('открыть').first)).pop();
              await tester.pumpAndSettle();
            }
          }
        }
      });
    });
  }

  testWidgets('Оформление: сброс возвращает фон к «без фона»', (tester) async {
    final c = await start(tester, Look.light, (ctx, r) => openAppearance(ctx));
    await tester.runAsync(() => UserBg.save(Uint8List.fromList(png)));
    c.read(settingsProvider.notifier).set({'bgImage': 7, 'bgPhoto': 'p1', 'bgVeil': 40, 'bgBlur': 9});
    await tester.pumpAndSettle();
    expect(find.text('С картинкой'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Сбросить оформление'), find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last, const Offset(0, -200));
    await tester.ensureVisible(find.text('Сбросить оформление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить оформление'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Да, сбросить'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final j = c.read(settingsProvider).j;
    expect(j['bgImage'], 0);
    expect(j['bgPhoto'], isNull);
    expect(j['bgVeil'], 72);
    expect(j['bgBlur'], 0);
    expect(find.text('Без фона'), findsOneWidget);
  });
}
