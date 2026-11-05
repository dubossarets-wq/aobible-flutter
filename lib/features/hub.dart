// Точки подключения функций к читалке и оболочке. Каждая функция (папка lib/features/<имя>/) в своей register()
// заполняет нужные поля; ядро (lib/ui, lib/core) зовёт их, ничего не зная о самих функциях.
// Так функции делаются независимо и не правят чужие файлы.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/markup.dart';
import '../core/settings.dart';
import '../ui/kit.dart';

/// Нажатие на слово в тексте
class WordTap {
  WordTap({required this.pane, required this.moduleId, required this.ref, required this.token, required this.tokenIndex, required this.rect, required this.verseText});
  final int pane;
  final String moduleId;
  final VerseRef ref;
  final Token token; // слово (с номерами Стронга, если размечено)
  final int tokenIndex;
  final Rect rect; // где на экране (для выборки над словом)
  final String verseText; // сырой текст стиха
}

/// Что добавить к стиху: фон (цвет выделения) и значки/пометки в конце стиха
class VerseDecor {
  const VerseDecor({this.background, this.trailing = const [], this.leading = const [], this.afterNumber = const [], this.below, this.above, this.parts = const []});
  final Color? background;
  final Widget? below; // под текстом стиха, на всю ширину колонки (строка действий под выделенным стихом)
  final Widget? above; // перед стихом, на всю ширину колонки (введение к книге или главе — перед первым стихом)
  /// Любимые части стиха: диапазоны слов (индексы слов в стихе, включительно) — читалка подчёркивает их, как .fav-part
  final List<(int, int)> parts;
  final List<InlineSpan> trailing;
  final List<InlineSpan> leading; // до номера стиха
  final List<InlineSpan> afterNumber; // между номером и текстом (закладка, сердце, подборка — как в веб-версии)
}

/// Пункт в выборке над словом (словарь, «Карта» для места и т. п.)
class WordMenuItem {
  const WordMenuItem({required this.label, this.sub, required this.onTap, this.order = 100});
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final int order;
}

/// Пункт меню «Ещё» (телефон) / ⋮ (широкий экран)
class MoreItem {
  const MoreItem({required this.id, required this.icon, required this.label, required this.run, this.order = 100, this.visible});
  final String id;
  final IconData icon;
  final String label;
  final PaneAction run;
  final int order;
  final bool Function(WidgetRef ref)? visible;
}

typedef VerseDecorator = VerseDecor? Function(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book);
typedef PaneAction = void Function(BuildContext context, WidgetRef ref, int pane);

/// Выбор части стиха (PartInline в веб-версии): стих, первое и последнее слово (null — ещё не выбрано)
class PartSelection {
  const PartSelection(this.pane, this.ref, this.moduleId, {this.from, this.to});
  final int pane;
  final VerseRef ref;
  final String moduleId;
  final int? from;
  final int? to;
}

/// Слово под выборкой или статьёй (.w.active): читалка подсвечивает его, пока выборка открыта
final activeWord = ValueNotifier<({int pane, VerseRef ref, int token})?>(null);

/// Идёт выбор части стиха (null — нет): кнопка «Часть стиха» ставит, читалка ведёт выбор слов
final partSelection = ValueNotifier<PartSelection?>(null);

/// Раскрытый комментарий под стихом: ключ «панель|книга.глава.стих», sel — какой из комментариев стиха;
/// closing — идёт плавное сворачивание
final openComment = ValueNotifier<({String key, int sel, bool closing})?>(null);

class Hub {
  // Чтение
  static void Function(BuildContext context, WidgetRef ref, WordTap tap)? onWordTap;
  static final List<VerseDecorator> verseDecorators = [];

  /// Панель действий с выделенными стихами (вместо шапки панели, пока есть выделение)
  static Widget Function(BuildContext context, WidgetRef ref, int pane)? selectionBar;

  // Вкладки и меню (телефон: нижние вкладки; широкий экран: меню ⋮)
  static PaneAction? openPlans;
  static PaneAction? openBookmarks;
  static PaneAction? openMore;
  static PaneAction? openSettings;
  static PaneAction? openLibrary;
  static void Function(BuildContext context, String tab)? openLibraryTab; // вкладка: installed | catalog | import
  static PaneAction? openAudio; // «Слушать» с текущего места
  // нижнее меню: открыть вкладку (как нажатие на неё); с какой вкладки пришли в поиск (кнопка возврата у поля поиска)
  static void Function(WidgetRef ref, String id)? openTab;
  static String searchFrom = 'bible';
  static Widget Function(BuildContext context, WidgetRef ref)? audioBar; // мини-проигрыватель над вкладками

  // Связи между функциями (каждую заполняет та функция, что её умеет)
  static final List<List<WordMenuItem> Function(BuildContext context, WidgetRef ref, WordTap tap)> wordMenuItems = [];
  static void Function(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId)? addToSermon;
  static void Function(BuildContext context, WidgetRef ref, VerseRef at, String moduleId)? openInterlinear;
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef from)? listenFrom;
  static void Function(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId)? compareTranslations;
  // Панель выделения (кнопки и меню «Ещё», как SelectionBar.jsx): окна других функций
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef at)? openCommentary; // изучение
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef at)? openXrefs; // изучение
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef at, String moduleId)? openVerseGuide; // «Всё о стихе», изучение
  static void Function(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId)? openVerseImage; // планы
  static final List<MoreItem> moreItems = [];

  /// Карта места во второй половине экрана (вместо второй панели чтения): что рисовать (даёт функция карт);
  /// открыть/закрыть — mapPaneProvider
  static Widget Function(BuildContext context, WidgetRef ref, Object place)? mapPaneBuilder;
  // Пересоздать состояние приложения целиком (main.dart; Hub.reset его не сбрасывает)
  static VoidCallback? restartApp;

  /// Введение из комментариев над заголовком: bookLevel — к книге (над названием книги), иначе к главе (над «Глава N»)
  static Widget? Function(BuildContext context, WidgetRef ref, int pane, String moduleId, String book, int chapter, {required bool bookLevel})? chapterIntro;

  /// Панель под верхним меню панели чтения (например, «Вернуться к проповеди»); null — нечего показывать
  static Widget? Function(BuildContext context, WidgetRef ref, int pane)? underBar;

  /// Круглая кнопка «Слушать» внизу панели чтения (даёт функция аудио)
  static Widget Function(BuildContext context, WidgetRef ref, int pane)? listenFab;

  // --- Жесты читалки и «Часть стиха» (ChapterView.jsx, BibleReader.jsx) ---
  /// Двойное касание стиха — в любимые / из любимых, с пульсом сердечка (закладки)
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef at, String moduleId)? onVerseDoubleTap;
  /// Нажатие на номер Стронга в тексте — статья словаря сразу на всю высоту (изучение)
  /// closeToParent — «×» статьи возвращает в окно, откуда её открыли (проповедь), а не закрывает всё
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef at, String strongNum, {bool closeToParent})? openStrong;
  /// «Часть стиха»: выбранные слова from..to (индексы слов) — в любимые частью (закладки)
  static void Function(BuildContext context, WidgetRef ref, VerseRef at, String moduleId, int from, int to, String text)? addFavoritePart;
  /// «Часть стиха» → «В проповедь»: фрагмент текста (проповеди)
  static void Function(BuildContext context, WidgetRef ref, VerseRef at, String moduleId, String fragment)? addFragmentToSermon;
  /// Режим плана в панели (PlanView): что рисовать вместо читалки, когда planMode[pane] задан (планы)
  static Widget Function(BuildContext context, WidgetRef ref, int pane)? planView;

  /// Поиск по номеру Стронга (G26, H7225): карточка — слово оригинала, значение, все места (даёт функция изучения).
  /// filter — часть Библии из настроек поиска; onOpen — открыть место; onArticle — статья словаря (null — не показывать)
  static Widget Function(BuildContext context, WidgetRef ref, int pane, String num, bool Function(VerseRef r)? filter, void Function(VerseRef r) onOpen, VoidCallback? onArticle)? strongSearchCard;

  /// Уведомление внизу экрана из любого места (в том числе из Hub.afterStart, где нет context)
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navigatorKey = GlobalKey<NavigatorState>();
  /// Верхний слой поверх всего, включая нижние вкладки (инструкция затемняет и их, как в веб-версии):
  /// его рисует слой вкладок (TabBarOverlay) последним; topLayerHost — есть ли такой слой на экране
  static final topLayer = ValueNotifier<Widget?>(null);
  static final topLayerHost = GlobalKey(debugLabel: 'topLayer');

  /// Глава прочитана (видна до конца и на ней провели достаточно времени) — учёт для планов и статистики
  static void Function(BuildContext context, WidgetRef ref, String book, int chapter)? onChapterRead;
  static void toast(String text, {String? actionLabel, VoidCallback? action}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    final pal = ProviderScope.containerOf(m.context, listen: false).read(settingsProvider).palette;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(aobSnackBar(pal, text, actionLabel: actionLabel, action: action == null ? null : () {
        m.hideCurrentSnackBar();
        action();
      }));
  }

  /// Смена языка: подписи пунктов меню и т. п. задаются при регистрации — регистрируем заново
  static void reset() {
    onWordTap = null;
    verseDecorators.clear();
    underBar = null;
    chapterIntro = null;
    selectionBar = null;
    openPlans = openBookmarks = openMore = openSettings = openLibrary = openAudio = null;
    openLibraryTab = null;
    audioBar = null;
    wordMenuItems.clear();
    addToSermon = openInterlinear = compareTranslations = null;
    openCommentary = openXrefs = null;
    openVerseGuide = null;
    openVerseImage = null;
    listenFrom = null;
    moreItems.clear();
    mapPaneBuilder = null;
    listenFab = null;
    onVerseDoubleTap = null;
    openStrong = null;
    addFavoritePart = null;
    addFragmentToSermon = null;
    planView = null;
    strongSearchCard = null;
    onChapterRead = null;
  }

  /// Запуск: что сделать после показа первого экрана (доустановка модулей, перенос данных, напоминания…)
  static final List<Future<void> Function(WidgetRef ref)> afterStart = [];
}

/// Выделенные стихи: панель → набор стихов. Долгое нажатие или нажатие на номер стиха — выделить.
class SelectionNotifier extends Notifier<Map<int, Set<VerseRef>>> {
  @override
  Map<int, Set<VerseRef>> build() => const {};

  void toggle(int pane, VerseRef r) {
    final cur = {...?state[pane]};
    cur.contains(r) ? cur.remove(r) : cur.add(r);
    state = {...state, pane: cur};
  }

  void clear(int pane) => state = {...state, pane: const {}};
}

final selectionProvider = NotifierProvider<SelectionNotifier, Map<int, Set<VerseRef>>>(SelectionNotifier.new);

/// Счётчик «отметки у стихов изменились» (закладки, выделения, заметки…): функции увеличивают его
/// после изменения данных — видимые стихи перерисовываются
class DecorVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final decorVersionProvider = NotifierProvider<DecorVersion, int>(DecorVersion.new);
