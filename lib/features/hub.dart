// Точки подключения функций к читалке и оболочке. Каждая функция (папка lib/features/<имя>/) в своей register()
// заполняет нужные поля; ядро (lib/ui, lib/core) зовёт их, ничего не зная о самих функциях.
// Так функции делаются независимо и не правят чужие файлы.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/markup.dart';

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
  const VerseDecor({this.background, this.trailing = const [], this.leading = const [], this.afterNumber = const []});
  final Color? background;
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
  static PaneAction? openAudio; // «Слушать» с текущего места
  static Widget Function(BuildContext context, WidgetRef ref)? audioBar; // мини-проигрыватель над вкладками

  // Связи между функциями (каждую заполняет та функция, что её умеет)
  static final List<List<WordMenuItem> Function(BuildContext context, WidgetRef ref, WordTap tap)> wordMenuItems = [];
  static void Function(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId)? addToSermon;
  static void Function(BuildContext context, WidgetRef ref, VerseRef at, String moduleId)? openInterlinear;
  static void Function(BuildContext context, WidgetRef ref, int pane, VerseRef from)? listenFrom;
  static void Function(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId)? compareTranslations;
  static final List<MoreItem> moreItems = [];

  /// Карта места во второй половине экрана (вместо второй панели чтения): что рисовать (даёт функция карт);
  /// открыть/закрыть — mapPaneProvider
  static Widget Function(BuildContext context, WidgetRef ref, Object place)? mapPaneBuilder;

  /// Круглая кнопка «Слушать» внизу панели чтения (даёт функция аудио)
  static Widget Function(BuildContext context, WidgetRef ref, int pane)? listenFab;

  /// Уведомление внизу экрана из любого места (в том числе из Hub.afterStart, где нет context)
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Глава прочитана (видна до конца и на ней провели достаточно времени) — учёт для планов и статистики
  static void Function(BuildContext context, WidgetRef ref, String book, int chapter)? onChapterRead;
  static void toast(String text, {String? actionLabel, VoidCallback? action}) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: actionLabel != null && action != null ? SnackBarAction(label: actionLabel, onPressed: action) : null,
      ));
  }

  /// Смена языка: подписи пунктов меню и т. п. задаются при регистрации — регистрируем заново
  static void reset() {
    onWordTap = null;
    verseDecorators.clear();
    selectionBar = null;
    openPlans = openBookmarks = openMore = openSettings = openLibrary = openAudio = null;
    audioBar = null;
    wordMenuItems.clear();
    addToSermon = openInterlinear = compareTranslations = null;
    listenFrom = null;
    moreItems.clear();
    mapPaneBuilder = null;
    listenFab = null;
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
