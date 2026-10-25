// Интерактивная инструкция (TourOverlay.jsx, tour.js, tours.js): экран затемнён, нужное место подсвечено мигающей рамкой,
// у него — облачко с текстом, внизу (или вверху) — «Назад / Далее». Нажать можно куда угодно: нажали подсвеченное — урок
// идёт дальше, «Далее» делает действие за человека. Подсветка и облачко следят за местом каждый кадр и плавно переезжают.
import 'dart:async';


import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../../ui/navigator_sheet.dart';
import '../../ui/search_screen.dart';
import '../hub.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'library_sheet.dart';
import 'prefs_sheet.dart';
import 'sheet.dart';
import 'tour_targets.dart';

/// Какой урок идёт и на каком шаге (tour.js)
final tourState = ValueNotifier<({String? id, int step})>((id: null, step: 0));

OverlayEntry? _entry;

/// Начать урок: поверх приложения встаёт TourOverlay
void startTour(String id) {
  final nav = Hub.navigatorKey.currentState ?? (appContext() == null ? null : Navigator.of(appContext()!));
  final overlay = nav?.overlay;
  if (overlay == null) return;
  tourState.value = (id: id, step: 0);
  // прежний (если остался от закрытого экрана) убираем: окно инструкции всегда одно и в нужном Overlay
  _entry?.remove();
  _entry = OverlayEntry(builder: (_) => const TourOverlay());
  overlay.insert(_entry!);
}

void stopTour() {
  tourState.value = (id: null, step: 0);
  _entry?.remove();
  _entry?.dispose();
  _entry = null;
}

void goStep(int step) => tourState.value = (id: tourState.value.id, step: step);

/// Идёт ли урок
bool get tourActive => _entry != null;

/// Чем шаг управляет приложением: открыть окно, закрыть всё, нажать на место (api в tours.js)
class TourApi {
  TourApi(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;

  void openSheet(String kind) {
    switch (kind) {
      case 'search':
        openSearch(context, 0);
      case 'nav':
        openNavigator(context, 0);
      case 'plans':
        Hub.openPlans?.call(context, ref, 0);
      case 'bookmarks':
        Hub.openBookmarks?.call(context, ref, 0);
      case 'prefs':
        openPrefs(context);
      case 'settings':
        openAppearance(context);
      case 'library':
        openLibrary(context);
      default:
        // «Проповеди», «Карты» — пункты других функций в меню «Ещё»
        Hub.moreItems.where((m) => m.id == kind).firstOrNull?.run(context, ref, 0);
    }
  }

  void closeSheet() => closeAllSheets(context);

  /// Чистый экран: без окон, выделения и карты (reset в TourOverlay.jsx)
  void reset() {
    closeAllSheets(context);
    ref.read(selectionProvider.notifier).clear(0);
    ref.read(mapPaneProvider.notifier).close();
  }

  /// Нажать на место (click(el) в веб-версии): касание пальцем в середине прямоугольника
  void click(Rect? r) {
    if (r == null) return;
    final id = _pointerId++;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: id, position: r.center));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: id, position: r.center));
  }

  /// Зажать стих (selectVerse): выделяем стих, который сейчас в начале читалки
  void selectVerse() {
    if (ref.read(selectionProvider)[0]?.isNotEmpty ?? false) return;
    final at = livePositions[0]?.value ?? ref.read(panesProvider).first.ref;
    ref.read(selectionProvider.notifier).toggle(0, at);
  }

  static int _pointerId = 9100;
}

/// Один шаг урока (tours.js). target — id цели (tour_targets.dart) или null (подсветки нет, затемнён весь экран);
/// before — подготовить экран при входе в шаг; next — сделать действие за человека по кнопке «Далее»;
/// until — шаг выполнен сам (условие стало верным после того, как было неверным)
class TourStep {
  const TourStep(this.text, {this.target, this.before, this.next, this.until});
  final String text;
  final String? target;
  final void Function(TourApi api)? before;
  final void Function(TourApi api)? next;
  final bool Function(TourApi api)? until;
}

class TourDef {
  const TourDef(this.id, this.icon, this.title, this.group, this.steps);
  final String id, title, group;
  final IconData icon;

  /// Шаги зависят от раскладки: на телефоне поиск, «Планы», «Закладки» — вкладки внизу, пункты меню ⋮ — в листе «Ещё»
  final List<TourStep> Function(bool phone) steps;
}

bool phoneLayout() {
  final c = appContext();
  return c == null ? true : MediaQuery.sizeOf(c).width < 900;
}

// --- Условия и помощники шагов -----------------------------------------------------------------------------------

bool _selected(TourApi a) => a.ref.read(selectionProvider)[0]?.isNotEmpty ?? false;
bool _second(TourApi a) => a.ref.read(panesProvider).length > 1;
bool _mapOpen(TourApi a) => a.ref.read(mapPaneProvider) != null;
bool _wordPop() => hasType('_Popover');
bool _menuOpen() => hasText(t('Ещё')) && sheetOpen();

void _openMenu(TourApi a, bool phone) {
  if (!_menuOpen()) a.click(targetRect(phone ? 'tab-more' : 'tb-more'));
}

/// Пункт меню ⋮ / листа «Ещё» по подписи — для подсветки
Rect? _menuItem(String text) {
  if (!sheetOpen()) return null;
  final label = t(text);
  final e = findElement((e) => e.widget is Text && ((e.widget as Text).data ?? '') == label);
  final r = rectOfElement(e);
  return r == null ? null : Rect.fromLTRB(r.left - 44, r.top - 12, r.right + 16, r.bottom + 12);
}

/// Подсвечиваемое место, заданное функцией: id 'menu:<подпись>' ищет пункт меню по подписи, 'pref:<подпись>' — строку настроек
Rect? _special(String id) {
  if (id.startsWith('menu:') || id.startsWith('pref:')) return _menuItem(id.substring(id.indexOf(':') + 1));
  return null;
}

Rect? stepRect(TourStep s) {
  final id = s.target;
  if (id == null) return null;
  return _special(id) ?? targetRect(id) ?? sheetRect(); // места нет — подсвечено открытое окно (как document.querySelector('.sheet'))
}

final tourDefs = <TourDef>[
  TourDef('read', LucideIcons.bookOpen, 'Перейти к книге, главе, стиху', 'Основное', (phone) => [
    TourStep('Нажмите — откроется список книг.', target: 'tb-ref', next: (a) => a.click(targetRect('tb-ref'))),
    TourStep('Цвет — это раздел: Пятикнижие, пророки, Евангелия… Выберите книгу, главу и стих.', target: 'sheet', before: (a) => sheetOpen() ? null : a.openSheet('nav'), until: (a) => !sheetOpen()),
    TourStep('Или впишите ссылку, например «Ин 3:16», и нажмите стрелку.', target: 'sheet', before: (a) => sheetOpen() ? null : a.openSheet('nav'), until: (a) => !sheetOpen()),
    TourStep('Стрелка «назад» вернёт туда, где вы были.', target: 'tb-hist', before: (a) => a.closeSheet()),
  ]),
  TourDef('word', LucideIcons.mousePointerClick, 'Значение слова', 'Основное', (phone) => [
    TourStep('Нажмите на любое слово.', target: 'word', next: (a) => a.click(targetRect('word')), until: (a) => _wordPop()),
    TourStep(
      'Вот словари с этим словом. Нажмите на любой — откроется статья.',
      target: 'word-pop',
      before: (a) => !_wordPop() && !sheetOpen() ? a.click(targetRect('word')) : null,
      until: (a) => sheetOpen() || _mapOpen(a),
    ),
    TourStep('Это статья (или карта, если выбрали место). Закрыть — крестик вверху справа.', target: 'sheet', until: (a) => !sheetOpen() && !_mapOpen(a)),
    TourStep('Снять выделение — нажмите в любом другом месте.', before: (a) => a.reset()),
  ]),
  TourDef('verse', LucideIcons.highlighter, 'Действия со стихом', 'Основное', (phone) => [
    TourStep('Зажмите стих на полсекунды — он выделится.', target: 'verse', next: (a) => a.selectVerse(), until: _selected),
    TourStep('Вверху — действия: перевод рядом, комментарии, цвет, заметка, закладка. «⋯» — ещё.', target: 'selection-bar', before: (a) => a.selectVerse()),
    TourStep('Под стихом — «Слушать» и «В проповедь».', target: 'sel-inline', before: (a) => a.selectVerse()),
    TourStep('Галочка слева вверху снимает выделение. Нажмите её.', target: 'selection-bar', until: (a) => !_selected(a)),
    TourStep('Совет: дважды коснитесь стиха — он станет любимым (сердечко).', before: (a) => a.reset()),
  ]),
  TourDef('xref', LucideIcons.link2, 'Параллельные места', 'Основное', (phone) => [
    TourStep('Число после стиха — сколько у него параллельных мест. Нажмите на него.', target: 'xref', next: (a) => a.click(targetRect('xref')), until: (a) => sheetOpen()),
    TourStep('Здесь места Библии о том же. Нажмите на любое — оно откроется на второй половине экрана.', target: 'sheet', before: (a) => !sheetOpen() ? a.click(targetRect('xref')) : null, until: (a) => !sheetOpen() && _second(a)),
    TourStep('Место открылось внизу (или справа). Закрыть — крестик вверху.', target: 'tb-split', until: (a) => !_second(a) && !sheetOpen()),
  ]),
  TourDef('split', LucideIcons.columns2, 'Два перевода рядом', 'Основное', (phone) => [
    TourStep('Эта кнопка делит экран надвое — в каждой части свой перевод. Нажмите её.', target: 'tb-split', next: (a) => !_second(a) ? a.click(targetRect('tb-split')) : null, until: _second),
    TourStep('Перевод меняется кнопкой с его названием.', target: 'tb-module'),
    TourStep('Крестик на месте той же кнопки закрывает вторую часть.', target: 'tb-split', until: (a) => !_second(a)),
  ]),
  TourDef('search', LucideIcons.search, 'Поиск', 'Основное', (phone) => [
    TourStep('Нажмите на лупу.', target: phone ? 'tab-search' : 'tb-search', next: (a) => a.openSheet('search'), until: (a) => sheetOpen()),
    TourStep('Введите слово — места появятся сразу. Или ссылку: «Ин 3:16».', target: 'sheet', before: (a) => sheetOpen() ? null : a.openSheet('search')),
  ]),
  TourDef('saved', LucideIcons.heart, 'Закладки, заметки, любимые', 'Мои записи', (phone) => [
    TourStep(phone ? 'Откройте «Ещё» — правая кнопка на нижней панели.' : 'Откройте меню — три точки вверху справа.', target: phone ? 'tab-more' : 'tb-more', next: (a) => _openMenu(a, phone), until: (a) => _menuOpen()),
    TourStep('«Закладка на это место» запомнит, где вы читаете. Закладок — сколько угодно.', target: 'menu:Закладка на это место', before: (a) => _openMenu(a, phone)),
    phone
        ? TourStep('Все закладки, заметки, любимые стихи и выделения — на вкладке «Закладки» внизу.', target: 'tab-saved', before: (a) => a.closeSheet(), next: (a) => a.openSheet('bookmarks'))
        : TourStep('Здесь все закладки, заметки, любимые стихи и выделения.', target: 'menu:Закладки и заметки', before: (a) => _openMenu(a, phone), next: (a) => a.openSheet('bookmarks')),
  ]),
  TourDef('sermons', LucideIcons.scrollText, 'Проповеди', 'Мои записи', (phone) => [
    TourStep('Зажмите стих, который понравился.', target: 'verse', next: (a) => a.selectVerse(), until: _selected),
    TourStep('Нажмите «В проповедь».', target: 'sel-inline', before: (a) => a.selectVerse(), next: (a) => a.click(byTextRect(t('В проповедь'))), until: (a) => hasType('SermonAddSheet')),
    TourStep('Впишите название и нажмите «Создать» — или выберите проповедь из списка. Стих добавится сам.', target: 'sheet', until: (a) => hasText(t('Открыть проповедь'))),
    TourStep('Стих добавлен. «Открыть проповедь» — посмотреть её, «Читать дальше» — вернуться к чтению.', target: 'sheet', until: (a) => !hasText(t('Открыть проповедь'))),
    TourStep(phone ? 'Все проповеди — «Ещё» → «Проповеди».' : 'Все проповеди — в меню ⋮ → «Проповеди».', target: 'menu:Проповеди', before: (a) {
      a.reset();
      Timer(const Duration(milliseconds: 150), () => _openMenu(a, phone));
    }, next: (a) => a.openSheet('sermons')),
    TourStep('«Текст» — своя мысль. Зажмите блок, чтобы перетащить. «Кафедра» — крупный текст для служения.', target: 'sheet', before: (a) => sheetOpen() ? null : a.openSheet('sermons')),
  ]),
  TourDef('plans', LucideIcons.calendarCheck, 'Планы чтения', 'Чтение', (phone) => [
    phone
        ? TourStep('Нажмите «Планы» на нижней панели.', target: 'tab-plans', next: (a) => a.openSheet('plans'), until: (a) => sheetOpen())
        : TourStep('Меню ⋮ → «Планы чтения».', target: 'menu:Планы чтения', before: (a) => _openMenu(a, phone), next: (a) => a.openSheet('plans')),
    TourStep('Выберите план и нажмите «Начать». Дальше каждый день — «Читать»: всё на одной странице, отметки ставятся сами.', target: 'sheet', before: (a) => sheetOpen() ? null : a.openSheet('plans')),
  ]),
  TourDef('audio', LucideIcons.headphones, 'Слушать Библию', 'Чтение', (phone) => [
    TourStep('Нажмите на наушники — чтец начнёт с того места, где вы читаете.', target: 'listen-fab', next: (a) => a.click(targetRect('listen-fab')), until: (a) => hasType('AudioBar')),
    TourStep('Пауза, стих назад и вперёд. Стрелка вниз — скачать книгу и слушать без интернета.', target: 'audio-bar', before: (a) => !hasType('AudioBar') ? a.click(targetRect('listen-fab')) : null),
    TourStep('Ползунки — скорость и таймер сна. Крестик закрывает проигрыватель.', target: 'audio-bar'),
  ]),
  TourDef('image', LucideIcons.image, 'Картинка со стихом', 'Чтение', (phone) => [
    TourStep('Зажмите стих.', target: 'verse', next: (a) => a.selectVerse(), until: _selected),
    TourStep('Нажмите «⋯» — там «Картинка со стихом».', target: 'selection-bar', before: (a) => a.selectVerse()),
    TourStep('Нажмите «Картинка со стихом».', target: 'menu:Картинка со стихом'),
    TourStep('Выберите фон и формат. Двигайте текст пальцем, меняйте размер двумя. «Поделиться» — отправить.', target: 'sheet'),
  ]),
  TourDef('font', LucideIcons.type, 'Размер букв и оформление', 'Настройка', (phone) => [
    TourStep('Разведите два пальца на тексте — буквы станут крупнее. Сведите — мельче.', target: 'scroller', before: (a) => a.reset()),
    TourStep(phone ? 'Тема, шрифт и интервалы — «Ещё» → «Оформление».' : 'Тема, шрифт и интервалы — меню ⋮ → «Оформление».', target: 'menu:Оформление', before: (a) => _openMenu(a, phone), next: (a) => a.openSheet('settings')),
  ]),
  TourDef('maps', LucideIcons.map, 'Карты', 'Настройка', (phone) => [
    TourStep('Нажмите на название города или места — в списке будет «Карта». Место откроется на второй половине экрана.', target: 'verse'),
    TourStep(phone ? 'Все карты — «Ещё» → «Карты».' : 'Все карты — меню ⋮ → «Карты».', target: 'menu:Карты', before: (a) => _openMenu(a, phone), next: (a) => a.openSheet('maps')),
  ]),
  TourDef('library', LucideIcons.library, 'Переводы и словари', 'Настройка', (phone) => [
    TourStep('Перевод меняется этой кнопкой.', target: 'tb-module'),
    TourStep('Новые переводы, словари, комментарии — в Настройках → «Библиотека модулей».', target: 'pref:Библиотека модулей', before: (a) => a.openSheet('prefs'), next: (a) => a.openSheet('library')),
    TourStep('Во вкладке «Каталог» нажмите стрелку справа от модуля — он скачается.', target: 'sheet', before: (a) => hasText(t('Каталог')) && sheetOpen() ? null : a.openSheet('library')),
  ]),
  TourDef('data', LucideIcons.hardDrive, 'Перенос на другой телефон', 'Настройка', (phone) => [
    TourStep('Настройки → «Мои данные».', target: 'pref:Мои данные', before: (a) => a.openSheet('prefs'), next: (a) => a.click(_menuItem('Мои данные'))),
    TourStep('«Сохранить в файл» — и отправьте в облако или мессенджер. На новом телефоне — «Восстановить из файла».', target: 'sheet'),
  ]),
  TourDef('updates', LucideIcons.refreshCw, 'Обновления', 'Настройка', (phone) => [
    TourStep('Приложение обновляется само — записи и настройки остаются.'),
    TourStep('Здесь можно проверить обновления и вернуться к прежней версии.', target: 'pref:Что нового', before: (a) => a.openSheet('prefs')),
  ]),
];

Rect? byTextRect(String text) {
  final e = findElement((e) => e.widget is Text && ((e.widget as Text).data ?? '') == text);
  return rectOfElement(e);
}

// --- Окно поверх приложения ----------------------------------------------------------------------------------------

const _pad = 6.0;
const _gap = 14.0;

class TourOverlay extends ConsumerStatefulWidget {
  const TourOverlay({super.key});
  @override
  ConsumerState<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<TourOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final TourApi _api = TourApi(context, ref);
  final _bubbleKey = GlobalKey(), _ctrlKey = GlobalKey();

  String _stepKey = '';
  bool _moving = false;
  bool _armed = false;
  int _frame = 0;
  Timer? _enter;

  // Подсветка и облачко сейчас на экране
  Rect? _cur;
  double? _curY;
  Rect? _goalRaw; // место без отступов — для нажатия «на подсвеченное»
  bool _ctrlTop = false;
  bool _hasTarget = false;
  double? _arrowX;
  String? _arrowSide;

  TourDef? get _tour => tourDefs.where((x) => x.id == tourState.value.id).firstOrNull;
  List<TourStep> get _steps => _tour?.steps(phoneLayout()) ?? const [];
  TourStep? get _step {
    final s = _steps, i = tourState.value.step;
    return i < s.length ? s[i] : null;
  }

  @override
  void initState() {
    super.initState();
    tourState.addListener(_onStep);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _ticker = createTicker(_tick)..start();
    // первый шаг — после сборки кадра: он сбрасывает выделение (провайдер), а менять их во время сборки нельзя
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onStep();
    });
  }

  @override
  void dispose() {
    tourState.removeListener(_onStep);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _ticker.dispose();
    _enter?.cancel();
    super.dispose();
  }

  // Вход в шаг: в начале урока — чистый экран, затем подготовка шага
  void _onStep() {
    final st = tourState.value;
    _stepKey = '${st.id}:${st.step}';
    _moving = false;
    final step = _step;
    if (step == null) return;
    _armed = !(step.until?.call(_api) ?? false);
    _enter?.cancel();
    if (st.step == 0) _api.reset();
    _enter = Timer(Duration(milliseconds: st.step == 0 ? 250 : 80), () {
      if (mounted) step.before?.call(_api);
    });
  }

  void _advance(bool doAction, [String? key]) {
    final step = _step, tour = _tour;
    if (step == null || tour == null || _moving || (key ?? _stepKey) != _stepKey) return;
    _moving = true;
    final st = tourState.value;
    if (doAction && step.next != null && !(step.until?.call(_api) ?? false)) step.next!(_api);
    Timer(Duration(milliseconds: doAction && step.next != null ? 350 : 0), () {
      _moving = false;
      if (!mounted) return;
      if (st.step + 1 >= _steps.length) {
        stopTour();
      } else {
        goStep(st.step + 1);
      }
    });
  }

  void _close() {
    _api.reset();
    stopTour();
  }

  // Человек сам нажал на подсвеченное — шаг сделан
  void _onPointer(PointerEvent e) {
    if (e is! PointerUpEvent) return;
    final step = _step, goal = _goalRaw;
    if (step?.next == null || goal == null || !goal.contains(e.position)) return;
    final key = _stepKey;
    Timer(const Duration(milliseconds: 350), () {
      if (mounted) _advance(false, key);
    });
  }

  void _tick(Duration _) {
    final step = _step;
    if (step == null || !mounted) return;
    _frame++;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final W = size.width, H = size.height - MediaQuery.viewInsetsOf(context).bottom;
    final raw = stepRect(step);
    _goalRaw = step.target == null ? null : raw;
    final has = step.target != null && raw != null;
    final Rect goal = has
        ? Rect.fromLTRB(
            (raw.left - _pad).clamp(4, W - 4).toDouble(),
            (raw.top - _pad).clamp(4, H - 4).toDouble(),
            (raw.right + _pad).clamp(4, W - 4).toDouble(),
            (raw.bottom + _pad).clamp(4, H - 4).toDouble(),
          )
        : Rect.fromLTWH(W / 2, H / 2, 0, 0); // места нет — затемнён весь экран
    final ctrlH = (_ctrlKey.currentContext?.size?.height) ?? 110;
    final bubbleH = (_bubbleKey.currentContext?.size?.height) ?? 90;
    // Кнопки — внизу, а если место в нижней части экрана или доходит до низа — наверху
    final wantTop = has ? (goal.top + goal.bottom) / 2 > H * 0.6 || goal.bottom > H - ctrlH - 16 : false;
    final limTop = wantTop ? top + 10 + ctrlH + 10 : top + 10;
    final limBot = wantTop ? H - 10 : H - MediaQuery.paddingOf(context).bottom - 12 - ctrlH - 10;
    double y;
    String? side;
    if (!has) {
      y = (limTop + limBot - bubbleH) / 2;
    } else if (limBot - goal.bottom - _gap >= bubbleH) {
      y = goal.bottom + _gap;
      side = 'up';
    } else if (goal.top - _gap - limTop >= bubbleH) {
      y = goal.top - _gap - bubbleH;
      side = 'down';
    } else {
      y = wantTop ? limTop : limBot - bubbleH;
    }
    double ease(double? from, double to, double k) => from == null || (to - from).abs() < 0.5 ? to : from + (to - from) * k;
    final c = _cur;
    final k = c == null ? 1.0 : 0.25;
    _cur = Rect.fromLTRB(ease(c?.left, goal.left, k), ease(c?.top, goal.top, k), ease(c?.right, goal.right, k), ease(c?.bottom, goal.bottom, k));
    _curY = ease(_curY, y, k);
    _ctrlTop = wantTop;
    _hasTarget = has;
    _arrowSide = side;
    _arrowX = side == null ? null : (_cur!.left + _cur!.right) / 2;
    // Шаг выполнен сам: условие стало верным после того, как было неверным
    if (_frame % 10 == 0 && step.until != null) {
      final done = step.until!(_api);
      if (!_armed && !done) {
        _armed = true;
      } else if (_armed && done) {
        _advance(false);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final step = _step, tour = _tour;
    if (step == null || tour == null) return const SizedBox.shrink();
    final pal = effectivePalette(ref.watch(settingsProvider));
    final st = tourState.value;
    final steps = _steps;
    final last = st.step == steps.length - 1;
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = size.width - 24 > 520 ? 520.0 : size.width - 24;
    final left = (size.width - width) / 2;
    final cur = _cur ?? Rect.fromLTWH(size.width / 2, size.height / 2, 0, 0);
    final phase = (DateTime.now().millisecondsSinceEpoch % 1400) / 1400;
    final pulse = 1 - (phase * 2 - 1).abs(); // 0..1..0 за 1,4 с (tour-pulse)

    final bubble = Container(
      key: _bubbleKey,
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(kRadius + 4), boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 34, offset: Offset(0, 12))]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('{title} · шаг {n} из {total}', {'title': t(tour.title), 'n': '${st.step + 1}', 'total': '${steps.length}'}), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.muted, decoration: TextDecoration.none)),
        const SizedBox(height: 3),
        Text(t(step.text), style: TextStyle(fontSize: 17.3, height: 1.5, fontWeight: FontWeight.w400, color: pal.text, decoration: TextDecoration.none)),
      ]),
    );

    final ctrl = Container(
      key: _ctrlKey,
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(kRadius + 6), boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 34, offset: Offset(0, 12))]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 28,
          child: Row(children: [
            for (var i = 0; i < steps.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                width: i == st.step ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == st.step ? pal.accent : i < st.step ? mix(pal.accent, 0.45, pal.line) : pal.line, borderRadius: BorderRadius.circular(4)),
              ),
            const Spacer(),
            IconBtn(icon: LucideIcons.x, size: 20, tooltip: t('Закончить инструкцию'), onTap: _close),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (st.step > 0) ...[
            AobButton(icon: LucideIcons.chevronLeft, label: t('Назад'), onTap: () => goStep(st.step - 1)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: AobButton(
              kind: BtnKind.primary,
              wide: true,
              icon: last ? LucideIcons.check : null,
              label: last ? t('Понятно') : t('Далее'),
              onTap: () => last ? _close() : _advance(true),
            ),
          ),
        ]),
      ]),
    );

    return Semantics(
      container: true,
      label: t('Инструкция: {title}', {'title': t(tour.title)}),
      child: Stack(children: [
        // затемнение с окошком и мигающая рамка — касания проходят сквозь них
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DimPainter(cur, _hasTarget, pal.accent, pulse)))),
        Positioned(
          left: left,
          top: _curY ?? 0,
          child: Stack(clipBehavior: Clip.none, children: [
            bubble,
            if (_arrowSide != null && _arrowX != null)
              Positioned(
                left: (_arrowX! - left - 7).clamp(18, width - 30).toDouble(),
                top: _arrowSide == 'up' ? -6 : null,
                bottom: _arrowSide == 'down' ? -6 : null,
                child: Transform.rotate(angle: 0.785398, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(2)))),
              ),
          ]),
        ),
        Positioned(left: left, top: _ctrlTop ? MediaQuery.paddingOf(context).top + 10 : null, bottom: _ctrlTop ? null : bottom + 12, child: ctrl),
      ]),
    );
  }
}

/// Затемнение вокруг подсвеченного места и рамка вокруг него (.tour-dim, .tour-ring)
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.ring, this.accent, this.pulse);
  final Rect hole;
  final bool ring;
  final Color accent;
  final double pulse;
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final rr = RRect.fromRectAndRadius(hole, const Radius.circular(12));
    final path = ring ? (Path.combine(PathOperation.difference, full, Path()..addRRect(rr))) : full;
    canvas.drawPath(path, Paint()..color = const Color(0x800A0A0C));
    if (!ring) return;
    // рамка: 3 px акцента и широкий мягкий ореол, который «дышит»
    canvas.drawRRect(rr.inflate(3 + 2 + 4 * pulse), Paint()..color = accent.withValues(alpha: 0.35 - 0.25 * pulse)..style = PaintingStyle.stroke..strokeWidth = 4 + 6 * pulse);
    canvas.drawRRect(rr.inflate(1.5), Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_DimPainter old) => true;
}
