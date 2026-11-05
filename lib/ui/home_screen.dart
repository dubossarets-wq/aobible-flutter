// Главный экран: одна или две панели чтения, у каждой — шапка (перевод, место, история, вторая панель),
// внизу на телефоне — плавающая капсула вкладок «Планы, Поиск, Библия, Закладки, Ещё».
// Вид — как в веб-версии (ReaderToolbar.jsx, TabBar.jsx, SplitScreenReader.jsx, ModulePicker.jsx, styles.css).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cupertino_native_better/cupertino_native_better.dart' show CNSymbol, CNTabBar, CNTabBarItem, CNTabBarSearchController, CNTabBarSearchItem;
import 'package:flutter/cupertino.dart' show CupertinoColors;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart' show bookList;
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import '../features/shell/intl_data.dart' show langDisplayNames;
import '../features/shell/library_sheet.dart' show ModBusy, ModPill, fmtSize, langChips;
import '../features/shell/sheet.dart' show loadCatalog;
import 'glass.dart';
import 'ios_style.dart';
import 'kit.dart';
import 'navigator_sheet.dart';
import 'reader_pane.dart';
import 'search_screen.dart';

export 'kit.dart' show tabActive; // переехал в kit.dart (его подсвечивают и окна функций)


/// Главный экран на месте (не первая загрузка) — только тогда показываются нижние вкладки
final homeMounted = ValueNotifier<bool>(false);

/// Высота вкладок: 4 + капсула 64 + 12 + системный отступ снизу
double tabBarHeight(BuildContext context) => nativeGlass ? iosEdge + _nativeTabCapsule : 80 + MediaQuery.paddingOf(context).bottom;

// Системная панель вкладок iOS 26: капсула высотой ~57 точек, вокруг неё в своей рамке — поля ~18 по бокам
// и ~17 снизу (измерено по снимкам с iPhone). Свои отступы — так, чтобы сама капсула была в iosEdge от краёв и низа;
// стрелки глав и «Слушать» встают над капсулой (их отступ считается от tabBarHeight)
const _nativeTabCapsule = 58.0, _nativeTabSide = 18.0, _nativeTabBottom = 17.0;

// Короткое название перевода для верхней панели — не длиннее 5 знаков (moduleShort.js).
// Длинным названиям — общепринятые сокращения, остальным — первые 5 знаков первого слова.
const _shortNames = <String, String>{
  'rst-dc': 'RSTНК', 'rus-makarij': 'Макар', 'rus-pobedonostsev': 'Побед', 'rus-rbo-nt': 'РБО23', 'rus-yungerov': 'Юнгер',
  'rus-sergievsky': 'Серг', 'rst-interlinear': 'Подст', 'vin-interlinear': 'Винок', 'lxx-swete': 'LXX', 'goetze': 'Гёце',
  'ukr-ogienko': 'Огієн', 'cornilescu-cyr': 'Корн', 'dk-cyr': 'Данич', 'be-nt1931': 'НЗ31', 'arm-nt1853': 'ՆԿ53',
  'jps1917': 'JPS', 'luther1912': 'LUT', 'schlachter1951': 'SCH51', 'elberfelder1905': 'ELB', 'swe1917': 'SV17',
  'statenvertaling': 'SVV', 'vamvas': 'Βάμβ', 'sblgnt': 'SBL', 'vulgata': 'Vulg', 'peshitta': 'Pesh', 'heb-modern': 'תנ״ך',
  'cuv-t': '和合本繁', 'shinkaiyaku1965': '新改訳', 'van-dyck': 'SVD', 'esperanto': 'Esper', 'geneva1599': 'GNV',
  'segond1910': 'LSG', 'darby-fr': 'DBYfr', 'ostervald': 'OST', 'neo-crampon': 'NCR', 'rv1909': 'RV09', 'biblia-livre': 'BLV',
  'riveduta': 'RIV', 'diodati': 'Diod', 'gdanska': 'BG', 'slowo-zycia': 'SŁŻ', 'kralicka': 'BKR', 'ronbl': 'BLR',
};

String shortName(InstalledModule? m) {
  if (m == null) return '—';
  final s = _shortNames[m.id];
  if (s != null) return s;
  final n = m.name.trim().isEmpty ? m.id : m.name.trim();
  if (n.runes.length <= 5) return n;
  return String.fromCharCodes(n.split(RegExp(r'\s+')).first.runes.take(5));
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    tabActive.value = 'bible';
    WidgetsBinding.instance.addPostFrameCallback((_) => homeMounted.value = true);
    ModuleStore.instance.changes.addListener(_repair);
    WidgetsBinding.instance.addPostFrameCallback((_) => _repair());
  }

  @override
  void dispose() {
    ModuleStore.instance.changes.removeListener(_repair);
    Future.microtask(() => homeMounted.value = false);
    super.dispose();
  }

  // Перевод панели удалили или он недоступен — панель переходит на основной (или первый) перевод
  void _repair() {
    if (mounted) ref.read(panesProvider.notifier).repairModules();
  }

  // Escape снимает выделение стихов (на широком экране с клавиатурой)
  void _escape() {
    final sel = ref.read(selectionProvider);
    for (final e in sel.entries) {
      if (e.value.isNotEmpty) ref.read(selectionProvider.notifier).clear(e.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panes = ref.watch(panesProvider.select((l) => l.length));
    final mapPlace = ref.watch(mapPaneProvider);
    final pal = paletteOf(ref);
    final size = MediaQuery.sizeOf(context);
    final layout = ref.watch(settingsProvider.select((s) => s.get<String>('splitLayout')));
    // Расположение (useOrientation): рядом — на широком экране, друг над другом — на узком и вертикальном
    final columns = layout == 'columns' || (layout == 'auto' && size.width >= 720 && size.width > size.height * 0.9);
    final slots = <Widget>[for (var i = 0; i < panes; i++) _Pane(index: i)];
    // Карта места — во второй половине вместо второй панели чтения (та не теряется и вернётся после закрытия)
    final map = mapPlace != null && Hub.mapPaneBuilder != null;
    if (map) {
      if (slots.length > 1) slots.removeLast();
      slots.add(Hub.mapPaneBuilder!(context, ref, mapPlace));
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: pal.bg,
          // текст уходит под проигрыватель и вкладки, а не обрезается над ними; их высота приходит панелям
          // как MediaQuery.padding.bottom (стрелки глав и запас в конце главы встают над проигрывателем)
          extendBody: true,
          body: SafeArea(bottom: false, child: slots.length == 1 ? slots.first : _Split(columns: columns, children: slots)),
          bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
            if (Hub.audioBar != null) Hub.audioBar!(context, ref),
            // сами вкладки лежат поверх навигатора (TabBarOverlay); здесь — место под них, чтобы не закрывать чтение
            // (на любой ширине: на широком экране меню — та же капсула по центру)
            _FocusHide(down: true, child: SizedBox(height: tabBarHeight(context))),
          ]),
        ),
      ),
    );
  }
}

/// Режим чтения (focusMode): при прокрутке вниз шапка и нижние вкладки плавно уезжают, вверх — возвращаются
/// (BibleReader.jsx: reading-hidden). Пока открыто окно или выделен стих — на месте.
class _FocusHide extends ConsumerWidget {
  const _FocusHide({required this.child, this.down = false, this.pane});
  final Widget child;
  final bool down; // вкладки уезжают вниз, шапка — вверх
  final int? pane; // шапка этой панели (null — любое выделение)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusMode = ref.watch(settingsProvider.select((s) => s.get<bool>('focusMode')));
    final anim = ref.watch(settingsProvider.select((s) => s.get<bool>('animations')));
    final selecting = ref.watch(selectionProvider.select((m) => pane == null ? m.values.any((v) => v.isNotEmpty) : (m[pane]?.isNotEmpty ?? false)));
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    return ValueListenableBuilder<int>(
      valueListenable: sheetsOpen,
      child: child,
      builder: (_, open, child) => ValueListenableBuilder<bool>(
      valueListenable: focusHidden,
      child: child,
      builder: (_, hidden, child) {
        final hide = focusMode && hidden && !selecting && current && open == 0;
        final d = anim ? const Duration(milliseconds: 250) : Duration.zero;
        return ClipRect(
          child: AnimatedAlign(
            alignment: down ? Alignment.topCenter : Alignment.bottomCenter,
            heightFactor: hide ? 0 : 1,
            duration: d,
            curve: Curves.easeOut,
            child: AnimatedOpacity(opacity: hide ? 0 : 1, duration: d, child: IgnorePointer(ignoring: hide, child: child)),
          ),
        );
      },
      ),
    );
  }
}

/// Панели (SplitScreenReader.jsx): всегда поровну, между ними — лёгкая линия. Размер панелей не меняется
/// (перетаскивание разделителя убрано по решению владельца 04.11.2026; сохранённая splitRatio больше не используется)
class _Split extends ConsumerWidget {
  const _Split({required this.columns, required this.children});
  final bool columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final n = children.length;
    final cols = columns;
    const thick = 1.0;
    return LayoutBuilder(builder: (context, c) {
      final total = (cols ? c.maxWidth : c.maxHeight) - thick * (n - 1);
      Widget slot(Widget w, double extent) => SizedBox(width: cols ? extent : null, height: cols ? null : extent, child: w);
      // друг над другом: нижнюю панель снизу закрывают вкладки (и проигрыватель) — их высота прибавляется к ней
      // сверх доли, чтобы видимая часть у всех панелей была поровну
      final inset = cols ? 0.0 : math.min(MediaQuery.paddingOf(context).bottom, total / 2);
      final usable = total - inset;
      final kids = <Widget>[];
      for (var i = 0; i < n; i++) {
        // верхние панели (разделение по строкам) не доходят до проигрывателя — нижний запас нужен только последней
        final w = cols || i == n - 1 ? children[i] : MediaQuery.removePadding(context: context, removeBottom: true, child: children[i]);
        kids.add(slot(w, usable / n + (i == n - 1 ? inset : 0)));
        // стиль iPhone: непрозрачный системный серый — полупрозрачный разделитель iOS на чёрном почти не виден
        final line = iosStyleOf(ref) ? sysColor(CupertinoColors.systemGrey4, dark: pal.dark) : pal.line;
        if (i < n - 1) kids.add(cols ? SizedBox(width: thick, child: ColoredBox(color: line)) : SizedBox(height: thick, child: ColoredBox(color: line)));
      }
      return cols ? Row(children: kids) : Column(children: kids);
    });
  }
}

class _Pane extends ConsumerWidget {
  const _Pane({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final barHeight = ref.watch(settingsProvider.select((s) => s.d('barHeight')));
    final module = ref.watch(panesProvider.select((l) => index < l.length ? l[index].moduleId : null));
    final count = ref.watch(panesProvider.select((l) => l.length));
    final hist = ref.watch(panesProvider.select((l) => index < l.length ? (l[index].hIndex, l[index].history.length) : (0, 0)));
    if (module == null) return const SizedBox.shrink();
    final mod = ModuleStore.instance.get(module);
    final initial = ref.read(panesProvider)[index].ref;
    final selecting = ref.watch(selectionProvider.select((m) => m[index]?.isNotEmpty ?? false));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Узкая панель (две панели рядом на телефоне): кнопки и надписи теснее, на самой узкой — без стрелок ˅
    // (@container в styles.css: ≤ 470 px и ≤ 360 px)
    return LayoutBuilder(builder: (context, box) => _build(context, ref, box.maxWidth, pal, barHeight, module, count, hist, mod, initial, selecting, wide));
  }

  Widget _build(BuildContext context, WidgetRef ref, double paneW, Palette pal, double barHeight, String module, int count, (int, int) hist, InstalledModule? mod, VerseRef initial, bool selecting, bool wide) {
    final split = count > 1;
    final narrow = paneW <= 470, tiny = paneW <= 360;
    final ilBar = ref.watch(settingsProvider.select((s) => s.get<bool>('ilBar'))) != false; // панель подстрочника раскрыта
    final inter = mod?.features['interlinear'] == true;
    final fg = pal.barText;
    final chipBg = mix(fg, 0.14, pal.bar);
    final ios = iosStyleOf(ref); // стиль iPhone: значки Apple цвета акцента, как кнопки панели навигации iOS
    Widget tbIcon(IconData icon, String tip, VoidCallback? onTap, {bool dot = false}) => Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: SizedBox(
            width: narrow ? 36 : 40,
            height: 40,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: onTap, child: Tooltip(message: tip, child: Icon(ios ? iosIcon(icon) : icon, size: 22, color: ios ? pal.accent : fg))),
                ),
              ),
              if (dot) Positioned(top: 7, right: 6, child: IgnorePointer(child: _UpdateDot(ring: pal.bar))),
            ]),
          ),
        );
    return Column(children: [
      if (selecting && Hub.selectionBar != null)
        Hub.selectionBar!(context, ref, index)
      else
        _FocusHide(
          pane: index,
          child: Container(
            height: barHeight,
            // у подстрочника под шапкой — своя панель: тень переезжает под неё, между ними — еле заметная линия
            // под шапкой — лёгкая разделительная линия (как в веб-версии: 1 px цвета линий и мягкая тень)
            decoration: BoxDecoration(
              color: pal.bar,
              boxShadow: mod?.features['interlinear'] == true && ilBar ? null : [BoxShadow(color: pal.line, offset: const Offset(0, 1)), const BoxShadow(color: Color(0x0D000000), offset: Offset(0, 4), blurRadius: 14)],
            ),
            // стиль iPhone: капсула и значки — на общей линии iosEdge (у значка 22 в кнопке 40 — поле 9)
            padding: ios ? const EdgeInsets.only(left: iosEdge, right: iosEdge - 9) : const EdgeInsets.only(left: 8, right: 4),
            child: Row(children: [
              // Перевод и место — одна капсула: слева короткое имя перевода (мельче, приглушённо), тонкий разделитель,
              // справа место — полное название книги («Бытие 1:1»), длинное или не помещается — сокращение; у каждой
              // части своё нажатие: перевод → выбор перевода, место → «Перейти»
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final modLabel = shortName(mod);
                  final modSize = narrow ? 12.2 : 12.6, refSize = narrow ? 15.0 : 15.6;
                  final tp = TextPainter(text: TextSpan(text: modLabel, style: TextStyle(fontSize: modSize, fontWeight: FontWeight.w700, letterSpacing: .4)), textDirection: TextDirection.ltr, maxLines: 1, textScaler: MediaQuery.textScalerOf(context))..layout();
                  final modW = math.min(tp.width + 26, c.maxWidth * 0.4);
                  tp.dispose();
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<VerseRef>(
                      valueListenable: livePosition(index, initial),
                      builder: (_, r, _) => _BarCrumb(
                        bg: chipBg,
                        fg: fg,
                        module: modLabel,
                        moduleTip: t('Перевод: {name}. Сменить перевод', {'name': mod?.name ?? module}),
                        moduleSize: modSize,
                        moduleMaxWidth: modW,
                        place: _refLabel(context, r, c.maxWidth - modW - 1 - (inter && !ilBar ? 37 : 0), refSize, tiny),
                        // подстрочник: третья часть капсулы раскрывает панель «Показывать»; при раскрытии значок «уходит»
                        // в панель (съезжает вниз и гаснет, часть капсулы плавно сужается), раскрытую сворачивает ⌃ в панели
                        tools: inter ? (on: !ilBar, tip: t('Подстрочник'), onTap: () => ref.read(settingsProvider.notifier).set({'ilBar': true})) : null,
                        placeTip: t('{ref}. Выбрать место', {'ref': Books.instance.formatRef(r.book, r.chapter, r.verse, full: true)}),
                        placeSize: refSize,
                        chevron: !tiny,
                        onModule: () => _pickModule(context),
                        onPlace: () => openNavigator(context, index),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 4),
              // «Назад» — только когда есть куда: бледная неактивная стрелка — лишний шум в шапке
              if (hist.$1 > 0) tbIcon(LucideIcons.arrowLeft, t('Назад по истории'), () => ref.read(panesProvider.notifier).go(index, -1)),
              if (hist.$1 < hist.$2 - 1) tbIcon(LucideIcons.arrowRight, t('Вперёд по истории'), () => ref.read(panesProvider.notifier).go(index, 1)),
              // поиск по всей Библии — у каждой панели, когда их несколько (результаты открываются в этой панели);
              // панель одна — поиск только в меню (вкладка «Поиск»)
              if (split) tbIcon(LucideIcons.search, t('Поиск'), () => openSearch(context, index)),
              if (wide && index == 0)
                ValueListenableBuilder<bool>(
                  valueListenable: updateAvailable,
                  builder: (_, upd, _) => tbIcon(LucideIcons.ellipsisVertical, upd ? t('Ещё. Доступно обновление') : t('Ещё'), Hub.openMore == null ? null : () => Hub.openMore!(context, ref, index), dot: upd),
                ),
              // «+» — ещё одна панель под этой: у каждой, пока панелей меньше maxPanes
              if (split && count < maxPanes) tbIcon(LucideIcons.plus, t('Ещё одна панель'), () => ref.read(panesProvider.notifier).addPane(index)),
              if (index == 0 || split)
                // «×» закрывает свою панель: у первой — первую (вторая остаётся одна), у второй — вторую
                split
                    ? tbIcon(LucideIcons.x, count > 2 || index == 0 ? t('Закрыть эту панель') : t('Закрыть вторую панель'), () => ref.read(panesProvider.notifier).closePane(index))
                    : tbIcon(LucideIcons.columns2, t('Читать параллельно'), () => ref.read(panesProvider.notifier).toggleSplit()),
            ]),
          ),
        ),
      // Подстрочник — вторая панель под шапкой: какие строки слова показывать (перевод, оригинал, номер Стронга)
      // Режим плана: вместо читалки — лента отрывков дня (PlanView); ставит и снимает функция планов
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: ValueListenableBuilder<Map<int, ({String uid, int day})>>(
              valueListenable: planMode,
              builder: (context, m, _) => m[index] != null && Hub.planView != null ? Hub.planView!(context, ref, index) : _readerOf(index),
            ),
          ),
          // «Вернуться к проповеди» и подобное — под верхним меню (и под панелью подстрочника), поверх текста
          if (!selecting && Hub.underBar != null)
            Positioned(
              top: mod?.features['interlinear'] == true && ilBar ? 40 : 0,
              left: 0,
              right: 0,
              child: Hub.underBar!(context, ref, index) ?? const SizedBox.shrink(),
            ),
          // панель подстрочника — поверх текста (раскрытие и скрытие текст не двигают); полоска чтения — под ней
          if (mod?.features['interlinear'] == true && !selecting)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _FocusHide(pane: index, child: _SlideBar(open: ilBar, height: 40, child: _InterBar(pal: pal, onHide: () => ref.read(settingsProvider.notifier).set({'ilBar': false})))),
            ),
        ]),
      ),
    ]);
  }

  // Выбор перевода (ModulePicker.jsx)
  // Окно раскрывается до низа верхней панели этой панели чтения (плашки перевода и места остаются видны)
  void _pickModule(BuildContext context) {
    final mq = MediaQuery.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final barH = ProviderScope.containerOf(context, listen: false).read(settingsProvider).d('barHeight');
    final top = (box != null && box.hasSize ? box.localToGlobal(Offset.zero).dy : mq.padding.top) + barH;
    final avail = mq.size.height - mq.padding.top;
    final initial = ((mq.size.height - top - 5) / avail).clamp(0.4, 0.95).toDouble(); // до панели, зазор 5 px
    showAobSheet(context, initial: initial, builder: (c) => _ModulePicker(pane: index, outer: context), scripture: true);
  }
}

/// Красная точка «доступно обновление» (.update-dot): 9 px, кольцо цвета подложки
class _UpdateDot extends StatelessWidget {
  const _UpdateDot({required this.ring});
  final Color ring;
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: const Color(0xffe0533d), shape: BoxShape.circle, boxShadow: [BoxShadow(color: ring, spreadRadius: 2)]),
      );
}

/// Окно выбора перевода: книга, глава и стих сохраняются. У каждого перевода — звёздочка «сделать основным»
class _ModulePicker extends ConsumerStatefulWidget {
  const _ModulePicker({required this.pane, required this.outer});
  final int pane;
  final BuildContext outer;
  @override
  ConsumerState<_ModulePicker> createState() => _ModulePickerState();
}

/// Что в переводе (ModulePicker.jsx, KINDS): 'ot', 'nt', 'dc' — у установленного по его книгам, у не скачанного —
/// по полю scope каталога; и возможности перевода
String _bookKind(BookInfo b) => b.dc || b.testament == 'AP' ? 'dc' : b.testament == 'NT' ? 'nt' : 'ot';
Set<String> _scopeOf(InstalledModule m) => {for (final x in bookList(m.id)) _bookKind(Books.instance.meta('${x['id']}'))};
typedef _Kind = (String, String, bool Function(Set<String> scope, Map<String, dynamic> features));
final _kinds = <_Kind>[
  ('full', 'Вся Библия', (s, _) => s.contains('ot') && s.contains('nt')),
  ('ot', 'Ветхий Завет', (s, _) => s.contains('ot')),
  ('nt', 'Новый Завет', (s, _) => s.contains('nt')),
  ('dc', 'Неканон', (s, _) => s.contains('dc')),
  ('strongs', 'С номерами Стронга', (_, f) => f['strongs'] == true),
  ('il', 'Подстрочник', (_, f) => f['interlinear'] == true),
];

class _ModulePickerState extends ConsumerState<_ModulePicker> {
  String? _lang; // выбранный язык в выборке сверху; null — все
  String? _kind; // что в переводе; null — всё
  // каталог — для переводов, которых нет на устройстве; без сети этого раздела просто нет
  List<CatalogEntry>? _catalog;
  bool _catErr = false;
  final Map<String, double> _busy = {};

  @override
  void initState() {
    super.initState();
    loadCatalog().then((c) {
      if (mounted) setState(() => _catalog = c);
    }, onError: (_) {
      if (mounted) setState(() => _catErr = true);
    });
  }

  Future<void> _install(CatalogEntry c) async {
    setState(() => _busy[c.id] = 0);
    try {
      await ModuleStore.instance.install(c, onProgress: (p, _) {
        if (mounted) setState(() => _busy[c.id] = p);
      });
      Hub.toast(c.json['online'] != null ? t('{name} добавлен', {'name': c.name}) : t('{name} установлен', {'name': c.name}));
    } catch (e) {
      Hub.toast('${c.name}: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pane = widget.pane, outer = widget.outer;
    final pal = paletteOf(ref);
    final primary = ref.watch(settingsProvider.select((s) => s.get<String>('primaryModule')));
    final current = ref.watch(panesProvider.select((l) => pane < l.length ? l[pane].moduleId : ''));
    // Список обновляется, когда переводы ставятся и удаляются
    return ValueListenableBuilder<int>(
      valueListenable: ModuleStore.instance.changes,
      builder: (context, _, _) {
        // основной (избранный ★) — первым, остальные в прежнем порядке, подстрочники — всегда внизу
        final all = ModuleStore.instance.bibles.where((m) => m.features['helper'] != true).toList();
        final top = all.indexWhere((m) => m.id == primary);
        if (top > 0) all.insert(0, all.removeAt(top));
        final ordered = [...all.where((m) => m.features['interlinear'] != true), ...all.where((m) => m.features['interlinear'] == true)];
        // переводы каталога, которых нет на устройстве (и выключенных среди установленных тоже нет)
        final more = [
          for (final c in _catalog ?? const <CatalogEntry>[])
            if (c.type == 'bible' && !c.unavailable && c.features['helper'] != true && ModuleStore.instance.get(c.id) == null) c,
        ];
        // выборка по языкам — если переводы на разных языках: язык приложения, затем языки установленных,
        // затем остальные — по числу переводов в каталоге
        final cnt = <String, int>{};
        for (final c in more) {
          cnt[c.language] = (cnt[c.language] ?? 0) + 1;
        }
        final mine = <String>{for (final m in ordered) m.language}.toList();
        final rest = [for (final l in cnt.keys) if (!mine.contains(l)) l]..sort((a, b) => cnt[b]!.compareTo(cnt[a]!) != 0 ? cnt[b]!.compareTo(cnt[a]!) : a.compareTo(b));
        final langs = [...mine, ...rest]..sort((a, b) => a == currentLang ? -1 : b == currentLang ? 1 : 0);
        final lang = langs.contains(_lang) ? _lang : null;
        final byLang = lang == null ? ordered : [for (final m in ordered) if (m.language == lang) m];
        // без выбранного языка — не скачанные переводы только на своих языках (каталог — больше тысячи переводов)
        final moreByLang = lang == null ? [for (final c in more) if (mine.contains(c.language) || c.language == currentLang) c] : [for (final c in more) if (c.language == lang) c];
        // что в переводе: показываем только выборки, которые отбирают часть списка (вместе со скачиваемыми)
        final scopes = {for (final m in byLang) m.id: _scopeOf(m)};
        bool fitsM(_Kind k, InstalledModule m) => k.$3(scopes[m.id]!, m.features);
        bool fitsC(_Kind k, CatalogEntry c) => k.$3(c.scope, c.features);
        final pool = byLang.length + moreByLang.length;
        final kinds = [
          for (final k in _kinds)
            if (byLang.where((m) => fitsM(k, m)).length + moreByLang.where((c) => fitsC(k, c)).length case final n when n > 0 && n < pool) k,
        ];
        final kind = kinds.where((k) => k.$1 == _kind).firstOrNull;
        final list = kind == null ? byLang : byLang.where((m) => fitsM(kind, m)).toList();
        final moreList = kind == null ? moreByLang : moreByLang.where((c) => fitsC(kind, c)).toList();
        String langName(String code) {
          final n = langDisplayNames[currentLang]?[code] ?? langNameFor(code, currentLang) ?? code;
          return n.isEmpty ? code : '${n[0].toUpperCase()}${n.substring(1)}';
        }
        return AobSheet(
          title: t('Перевод'),
          subtitle: pane == 1 ? t('Вторая панель') : t('Основная панель'),
          scroll: false,
          // список — сразу под линией шапки, без пробела; строки без плашек, разделены тонкой линией;
          // подсветка нажатия и наведения и линии — от края до края окна
          padding: const EdgeInsets.only(bottom: 16),
          child: ListView(children: [
            if (kinds.isNotEmpty)
              Padding(
                // под рядом книг — 4 до ряда языков (если он есть)
                padding: EdgeInsets.fromLTRB(0, 12, 0, langs.length > 1 ? 4 : 10),
                child: SizedBox(
                  height: 34,
                  child: FadeRow(gap: 6, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                    AobChip(label: t('Все'), on: kind == null, onTap: () => setState(() => _kind = null)),
                    for (final k in kinds) AobChip(label: t(k.$2), on: kind?.$1 == k.$1, onTap: () => setState(() => _kind = k.$1)),
                  ]),
                ),
              ),
            if (langs.length > 1)
              Padding(
                padding: EdgeInsets.fromLTRB(0, kinds.isNotEmpty ? 0 : 12, 0, 10),
                child: SizedBox(
                  height: 34,
                  child: FadeRow(gap: 6, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                    ...langChips(context, pal, codes: langs, value: lang, allValue: null, allLabel: t('Все'), name: langName, max: math.max(8, mine.length + 4), onChanged: (v) => setState(() => _lang = v)),
                  ]),
                ),
              ),
            if (langs.length > 1 || kinds.isNotEmpty) Container(height: 1, color: pal.line),
            for (final (k, m) in list.indexed)
              InkWell(
                onTap: () {
                  ref.read(panesProvider.notifier).setModule(pane, m.id);
                  Navigator.pop(context);
                },
                // и подсветка, и линии — от края до края окна; отступы — у содержимого строки
                // открытый сейчас перевод — отмечен фоном (от края до края)
                child: Container(
                    decoration: BoxDecoration(
                      color: m.id == current ? mix(pal.accent, 0.09, pal.panel) : null,
                      border: k == list.length - 1 ? null : Border(bottom: BorderSide(color: pal.line)),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: m.id == current ? pal.accent : pal.text)),
                          const SizedBox(height: 2),
                          Text('${m.title}${m.features['strongs'] == true ? ' · ${t('номера Стронга')}' : ''}', style: TextStyle(fontSize: 12.75, color: pal.muted)),
                        ]),
                      ),
                      const SizedBox(width: 4),
                      if (primary != m.id)
                        IconBtn(icon: LucideIcons.star, subtle: true, tooltip: t('Сделать основным'), onTap: () => ref.read(settingsProvider.notifier).set({'primaryModule': m.id}))
                      else
                        Tooltip(message: t('Основной перевод'), child: SizedBox(width: 32, height: 32, child: Center(child: CustomPaint(size: const Size(16, 16), painter: _StarPainter(pal.accent))))),
                    ]),
                  ),
              ),
            // не скачанные переводы (.pick-more) — с теми же выборками; «Скачать» прямо в строке, скачанный перевод
            // встаёт в список выше
            if (_catalog == null && !_catErr)
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(t('Загружаю каталог…'), style: TextStyle(fontSize: 13.6, color: pal.muted)),
              ),
            // скачиваемые и (переводы API.Bible) читаемые по сети — двумя разделами; у вторых «Добавить»
            for (final (items, title, note) in [
              ([for (final c in moreList) if (c.json['online'] == null) c], t('Можно скачать'), null),
              ([for (final c in moreList) if (c.json['online'] != null) c], t('Можно читать по сети'), t('Эти переводы не скачиваются: главы приходят по сети (API.Bible), когда вы их открываете.')),
            ])
              if (items.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: title.toUpperCase()),
                      TextSpan(text: '  ${items.length}', style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0)),
                    ]),
                    style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: pal.muted),
                  ),
                ),
                if (note != null) Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 6), child: Text(note, style: TextStyle(fontSize: 12.75, height: 1.4, color: pal.muted))),
                for (final (k, c) in items.indexed)
                  Container(
                    decoration: BoxDecoration(border: k == items.length - 1 ? null : Border(bottom: BorderSide(color: pal.line))),
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (c.title != c.name) c.title,
                              if (c.features['strongs'] == true) t('номера Стронга'),
                              if (lang == null && langs.length > 1) langName(c.language),
                              if (c.size > 0) fmtSize(c.size),
                            ].join(' · '),
                            style: TextStyle(fontSize: 12.75, color: pal.muted),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      if (_busy[c.id] case final p?)
                        ModBusy(pal: pal, value: p)
                      else if (c.json['online'] != null)
                        ModPill(pal: pal, label: t('Добавить'), tip: t('Добавить {name}', {'name': c.name}), onTap: () => _install(c))
                      else
                        ModPill(pal: pal, label: t('Скачать'), tip: c.size > 0 ? '${t('Скачать')} · ${fmtSize(c.size)}' : null, onTap: () => _install(c)),
                    ]),
                  ),
              ],
            if (Hub.openLibraryTab != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AobButton(label: t('Другие переводы'), icon: LucideIcons.library, wide: true, onTap: () {
                  Navigator.pop(context);
                  Hub.openLibraryTab?.call(outer, 'catalog'); // сразу вкладка «Каталог»
                }),
              ),
          ]),
        );
      },
    );
  }
}

/// Закрашенная звезда (Star с fill="currentColor"): в наборе значков есть только контурная
class _StarPainter extends CustomPainter {
  _StarPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const pts = [(12.0, 2.0), (15.09, 8.26), (22.0, 9.27), (17.0, 14.14), (18.18, 21.02), (12.0, 17.77), (5.82, 21.02), (7.0, 14.14), (2.0, 9.27), (8.91, 8.26)];
    final k = size.width / 24;
    final path = Path()..moveTo(pts[0].$1 * k, pts[0].$2 * k);
    for (final p in pts.skip(1)) {
      path.lineTo(p.$1 * k, p.$2 * k);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2 * k..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

/// Подпись плашки места: полное название книги, если оно короткое (до 14 знаков) и помещается, иначе — сокращение
String _refLabel(BuildContext context, VerseRef r, double maxWidth, double fontSize, bool tiny) {
  final b = Books.instance;
  final name = b.meta(r.book).name;
  final full = '$name ${r.chapter}:${r.verse}';
  if (name.runes.length <= 14) {
    final tp = TextPainter(
      text: TextSpan(text: full, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: .15)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final fits = tp.width + (tiny ? 25 : 41) <= maxWidth; // 41 — поля плашки и стрелка
    tp.dispose();
    if (fits) return full;
  }
  return b.formatRef(r.book, r.chapter, r.verse);
}

/// Панель подстрочника — тонкая полоса цвета верхней панели под ней: «👁» и три флажка (перевод слова, оригинал,
/// номер Стронга). Включённый — галочка, ярко на лёгкой подложке; выключенный — пустой квадрат, бледно и зачёркнут;
/// последнюю видимую строку выключить нельзя
class _InterBar extends ConsumerWidget {
  const _InterBar({required this.pal, required this.onHide});
  final Palette pal;
  final VoidCallback onHide; // ⌃ справа — свернуть панель (раскрывается язычком под шапкой)
  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(builder: (context, box) => _build(context, ref, box.maxWidth <= 470));

  Widget _build(BuildContext context, WidgetRef ref, bool narrow) {
    final s = ref.watch(settingsProvider);
    final fg = pal.barText;
    final keys = [('ilGloss', LucideIcons.languages, t('Перевод')), ('ilOrig', LucideIcons.scrollText, t('Оригинал')), ('ilStrong', LucideIcons.hash, t('Стронг'))];
    final on = {for (final (k, _, _) in keys) k: s.get<bool>(k) != false};
    // один сегментированный переключатель «Перевод │ Оригинал │ Стронг» (несколько можно включить сразу):
    // включённая часть — с подложкой, заполненным кружком и яркой надписью; выключенная — пустой кружок, бледно
    Widget seg(String k, String label, bool first, bool last) {
      final v = on[k]!;
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: () {
            // все строки скрыть нельзя — остаётся хотя бы одна
            if (v && on.values.where((x) => x).length == 1) return;
            ref.read(settingsProvider.notifier).set({k: !v});
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.fastOutSlowIn,
            height: 30,
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            color: v ? fg.withValues(alpha: 0.13) : Colors.transparent,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                // свой кружок: галочка толще, чем у значка шрифта
                child: CustomPaint(key: ValueKey(v), size: const Size.square(15), painter: _CheckDot(on: v, color: v ? fg : fg.withValues(alpha: 0.45), mark: pal.bar)),
              ),
              const SizedBox(width: 6),
              Transform.translate(
                offset: const Offset(0, -1), // на 1 px выше — визуально ровно по середине плашки
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(fontSize: 12.8, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w600, color: v ? fg : fg.withValues(alpha: 0.5)),
                  child: Text(label),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      // еле заметная линия сверху — отделяет панель от шапки того же цвета
      decoration: BoxDecoration(
        color: pal.bar,
        border: Border(top: BorderSide(color: fg.withValues(alpha: 0.08))),
        boxShadow: [BoxShadow(color: mix(pal.line, 0.7, Colors.black26), offset: const Offset(0, 1))],
      ),
      // слева — как капсула шапки (8); стрелка ⌃ — точно под значком «параллельно» (у узкой панели он уже: 36 вместо 40)
      padding: EdgeInsets.fromLTRB(8, 0, narrow ? 3 : 5, 0),
      child: Row(children: [
        // «Показывать» и переключатель — читается фразой: видно, что строки можно снять; на узком экране подпись
        // уступает место переключателю
        if (MediaQuery.sizeOf(context).width >= 430) ...[
          Text(t('Показывать:'), style: TextStyle(fontSize: 12.5, height: 1.2, color: fg.withValues(alpha: 0.55))),
          const SizedBox(width: 8),
        ],
        // всё место до стрелки ⌃ (Flexible со Spacer делили его пополам — переключатель обрезался)
        // не помещается — прокручивается вбок, у обрезанного края — плавное затухание (FadeRow)
        Expanded(
          child: FadeRow(gap: 0, children: [
            Container(
              // без обводки: форму капсулы держит лёгкая подложка, как у капсулы шапки
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: fg.withValues(alpha: 0.07)),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (i, (k, _, label)) in keys.indexed) ...[
                  if (i > 0) Container(width: 1, height: 30, color: fg.withValues(alpha: 0.16)),
                  seg(k, label, i == 0, i == keys.length - 1),
                ],
              ]),
            ),
          ]),
        ),
        IconBtn(icon: LucideIcons.chevronUp, size: 18, color: fg.withValues(alpha: 0.7), tooltip: t('Свернуть'), onTap: onHide),
      ]),
    );
  }
}

/// Кружок-флажок панели подстрочника: включён — залитый круг с толстой галочкой (линия 2,2), выключен — кольцо
class _CheckDot extends CustomPainter {
  _CheckDot({required this.on, required this.color, required this.mark});
  final bool on;
  final Color color, mark;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    if (!on) {
      canvas.drawCircle(c, r - 0.9, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
      return;
    }
    canvas.drawCircle(c, r, Paint()..color = color);
    final k = size.width / 15;
    canvas.drawPath(
      Path()
        ..moveTo(4.3 * k, 7.8 * k)
        ..lineTo(6.6 * k, 10.1 * k)
        ..lineTo(10.9 * k, 5.4 * k),
      Paint()
        ..color = mark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckDot old) => old.on != on || old.color != color || old.mark != mark;
}

/// Панель под шапкой поверх текста: плавно въезжает и уезжает вверх (сдвиг готовой картинки — без перекладки главы)
class _SlideBar extends StatefulWidget {
  const _SlideBar({required this.open, required this.height, required this.child});
  final bool open;
  final double height;
  final Widget child;
  @override
  State<_SlideBar> createState() => _SlideBarState();
}

class _SlideBarState extends State<_SlideBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: widget.open ? 1 : 0);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.fastOutSlowIn));
  late bool _shown = widget.open;

  @override
  void didUpdateWidget(_SlideBar old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      setState(() => _shown = true);
      _c.forward();
    } else {
      _c.reverse().then((_) {
        if (mounted && !widget.open) setState(() => _shown = false);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shown
      ? SizedBox(height: widget.height, child: ClipRect(child: SlideTransition(position: _slide, child: RepaintBoundary(child: widget.child))))
      : const SizedBox(width: double.infinity);
}

/// Читалка панели — один и тот же экземпляр виджета: при изменении размера окна шапка перестраивается,
/// а глава только перекладывается по новой ширине (новый ReaderPane на каждый шаг пересобирал все видимые стихи)
final _readers = <int, Widget>{};
Widget _readerOf(int index) => _readers.putIfAbsent(index, () => ReaderPane(index: index));

/// Шапка панели: перевод и место — одна капсула высотой 30 из двух частей с тонким разделителем.
/// Перевод — мельче и приглушённо (как подпись), место — крупно и жирно, со стрелкой ˅; подсветка нажатия — у своей части
class _BarCrumb extends StatelessWidget {
  const _BarCrumb({
    required this.bg,
    required this.fg,
    required this.module,
    required this.moduleTip,
    required this.moduleSize,
    required this.moduleMaxWidth,
    required this.place,
    required this.placeTip,
    required this.placeSize,
    required this.chevron,
    required this.onModule,
    required this.onPlace,
    this.tools,
  });
  final ({bool on, String tip, VoidCallback onTap})? tools;
  final Color bg, fg;
  final String module, moduleTip, place, placeTip;
  final double moduleSize, moduleMaxWidth, placeSize;
  final bool chevron;
  final VoidCallback onModule, onPlace;

  @override
  Widget build(BuildContext context) {
    Widget part(String tip, VoidCallback onTap, EdgeInsets pad, Widget child) => Tooltip(
          message: tip,
          // по ширине содержимого (hug): Container с alignment растягивался бы на всё доступное место
          // капсула 30 px — компактно; зона нажатия — вся часть капсулы по ширине
          child: InkWell(onTap: onTap, child: Container(height: 30, padding: pad, child: Align(widthFactor: 1, child: child))),
        );
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: moduleMaxWidth),
          child: part(
            moduleTip,
            onModule,
            const EdgeInsets.only(left: 13, right: 10),
            // надписи — ровно по середине капсулы: запас строки поровну и на 1 px выше (как в кнопках)
            Transform.translate(offset: const Offset(0, -1), child: Text(module, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: moduleSize, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w700, letterSpacing: .6, color: fg.withValues(alpha: 0.78)))),
          ),
        ),
        Container(width: 1, height: 14, color: fg.withValues(alpha: 0.2)),
        Flexible(
          child: part(
            placeTip,
            onPlace,
            EdgeInsets.only(left: 10, right: chevron ? 9 : 13),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Transform.translate(offset: const Offset(0, -1), child: Text(place, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: placeSize, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w700, letterSpacing: .1, color: fg)))),
              // стрелка ˅ — на одной линии с поднятой надписью
              if (chevron) ...[const SizedBox(width: 4), Transform.translate(offset: const Offset(0, -0.5), child: Icon(ico(LucideIcons.chevronDown), size: 16, color: fg.withValues(alpha: 0.6)))],
            ]),
          ),
        ),
        if (tools != null)
          // on — значок виден; иначе часть капсулы сужается до нуля, а значок съезжает вниз и гаснет
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.fastOutSlowIn,
              width: tools!.on ? 37 : 0,
              // высота — по содержимому (30): без этого OverflowBox брал всю высоту шапки и раздувал капсулу
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 37,
                maxWidth: 37,
                fit: OverflowBoxFit.deferToChild,
                child: IgnorePointer(
                  ignoring: !tools!.on,
                  child: Row(children: [
                    Container(width: 1, height: 14, color: fg.withValues(alpha: 0.2)),
                    part(
                      tools!.tip,
                      tools!.onTap,
                      const EdgeInsets.only(left: 9, right: 11),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.fastOutSlowIn,
                        offset: tools!.on ? Offset.zero : const Offset(0, 1.1),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: tools!.on ? 1 : 0,
                          child: Icon(ico(LucideIcons.slidersHorizontal), size: 16, color: fg.withValues(alpha: 0.75)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Нижние вкладки — плавающая капсула (.tabbar): высота 64, отступы 12, скругление 32, полупрозрачная с размытием.
/// Подсвечена вкладка открытого окна; одна плашка переезжает к выбранному пункту. Пальцем можно вести по меню:
/// плашка идёт за пальцем, отпустили — открывается этот раздел.
class _TabBar extends ConsumerStatefulWidget {
  const _TabBar();
  @override
  ConsumerState<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends ConsumerState<_TabBar> {
  static const _ids = ['plans', 'search', 'bible', 'saved', 'more'];
  int? _hover; // плашка идёт за пальцем
  Route<dynamic>? _bound; // окно, открытое с вкладки
  // системный поиск iOS 26 в меню: окно поиска раскрывает и сворачивает поле, задаёт в нём текст
  final _search = CNTabBarSearchController();
  int _tabKey = 0;

  @override
  void initState() {
    super.initState();
    nativeSearchActivate = _search.activateSearch;
    // свернуть поле: пакет сам меню не перерисовывает — панель создаётся заново (уже свёрнутой)
    nativeSearchDeactivate = () {
      if (!mounted || !nativeSearchActive.value) return;
      nativeSearchActive.value = false;
      setState(() => _tabKey++);
    };
    nativeSearchSetText = (s) => _search.text = s;
  }

  @override
  void dispose() {
    nativeSearchActivate = nativeSearchDeactivate = null;
    nativeSearchSetText = null;
    _search.dispose();
    super.dispose();
  }

  // Вкладки лежат выше навигатора: окна открываем и закрываем через контекст самого навигатора
  BuildContext get _nav => Hub.navigatorKey.currentContext ?? context;

  void _call(PaneAction? a) => a == null ? Hub.toast(t('Скоро')) : a(_nav, ref, 0);

  void _run(String id) {
    switch (id) {
      case 'plans':
        _call(Hub.openPlans);
      case 'search':
        openSearch(_nav, 0);
      case 'saved':
        _call(Hub.openBookmarks);
      case 'more':
        _call(Hub.openMore);
    }
  }

  // «Библия» или повторное нажатие на открытую вкладку закрывает окно; остальные открывают своё окно поверх чтения
  void _open(String id) {
    final ios = ref.read(settingsProvider).get<bool>('iosStyle');
    // поверх может быть и страница (большой проигрыватель) — нажатие на вкладку закрывает и её
    final nav = Navigator.of(_nav);
    if (id == 'bible' || tabActive.value == id) {
      if (nav.canPop()) nav.popUntil((r) => r.isFirst);
      return closeAllSheets(_nav);
    }
    // другая вкладка: прежние окна закрываем, потом открываем раздел; в стиле iPhone — мгновенно, без анимаций
    // (как переключение вкладок в iOS: закрытие и въезд новой страницы одновременно накладывались)
    if (ios) {
      dropAllSheets(_nav);
    } else {
      if (nav.canPop()) nav.popUntil((r) => r.isFirst);
      if (sheetsOpen.value > 0 || isSheetRoute(topRoute(_nav))) closeAllSheets(_nav);
    }
    final before = topRoute(_nav);
    iosTabSwitch = ios;
    try {
      _run(id);
    } finally {
      iosTabSwitch = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = topRoute(_nav);
      if (after == null || after == before || !isSheetRoute(after)) return;
      _bound = after;
      tabActive.value = id;
      after.popped.whenComplete(() {
        if (identical(_bound, after)) {
          _bound = null;
          tabActive.value = 'bible';
        }
      });
    });
  }

  int _at(double x, double width) => ((x - 5) / ((width - 10) / _ids.length)).floor().clamp(0, _ids.length - 1);

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final labels = {'plans': t('Планы'), 'search': t('Поиск'), 'bible': t('Библия'), 'saved': t('Закладки'), 'more': t('Ещё')};
    final icons = {'plans': LucideIcons.calendarCheck, 'search': LucideIcons.search, 'bible': LucideIcons.bookOpen, 'saved': LucideIcons.heart, 'more': LucideIcons.menu};
    final bottom = MediaQuery.paddingOf(context).bottom;
    final anim = ref.watch(settingsProvider.select((s) => s.get<bool>('animations')));
    // iOS 26: системная панель вкладок (Liquid Glass) — значки SF Symbols, выбранная вкладка — цветом акцента.
    // Над окнами остаётся видимой, как и наша (autoHideOnModal: false)
    if (nativeGlass) {
      const ids = ['plans', 'bible', 'saved', 'more'];
      // высоту панель берёт свою (системную), снизу — только отступ под полосу «домой»
      return Padding(
        padding: const EdgeInsets.fromLTRB(iosEdge - _nativeTabSide, 0, iosEdge - _nativeTabSide, iosEdge - _nativeTabBottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ValueListenableBuilder<String>(
            valueListenable: tabActive,
            builder: (context, activeId, _) => CNTabBar(
              key: ValueKey(_tabKey),
              items: [
                CNTabBarItem(label: labels['plans'], icon: const CNSymbol('calendar')),
                CNTabBarItem(label: labels['bible'], icon: const CNSymbol('book'), activeIcon: const CNSymbol('book.fill')),
                CNTabBarItem(label: labels['saved'], icon: const CNSymbol('heart'), activeIcon: const CNSymbol('heart.fill')),
                CNTabBarItem(label: labels['more'], icon: const CNSymbol('line.3.horizontal')),
              ],
              // поиск — системная вкладка iOS 26: круглая кнопка справа, раскрывается в поле поиска
              searchItem: CNTabBarSearchItem(
                label: labels['search']!,
                placeholder: t('Слово, Ин 3:16 или G26'),
                onSearchChanged: (q) => nativeSearchQuery.value = q,
                onSearchSubmit: (q) {
                  nativeSearchQuery.value = q;
                  nativeSearchSubmits.value++;
                },
                onSearchActiveChanged: (on) {
                  nativeSearchActive.value = on;
                  if (on && tabActive.value != 'search') {
                    _open('search');
                  } else if (!on) {
                    nativeSearchPageClose?.call();
                  }
                },
              ),
              searchController: _search,
              currentIndex: ids.indexOf(activeId).clamp(0, ids.length - 1),
              tint: pal.accent,
              iconSize: 19,
              autoHideOnModal: false,
              autoHideOnPageTransition: false,
              onTap: (i) {
                _open(ids[i]);
                // окно не открылось (например, «Скоро») — выбранной остаётся прежняя вкладка
                setState(() {});
              },
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ValueListenableBuilder<String>(
            valueListenable: tabActive,
            builder: (context, activeId, _) => ValueListenableBuilder<bool>(
              valueListenable: updateAvailable,
              builder: (context, upd, _) {
                final shown = _hover ?? _ids.indexOf(activeId);
                return LayoutBuilder(builder: (context, c) {
                  final cellW = (c.maxWidth - 10) / _ids.length;
                  return GestureDetector(
                    onHorizontalDragStart: (d) => setState(() => _hover = _at(d.localPosition.dx, c.maxWidth)),
                    onHorizontalDragUpdate: (d) => setState(() => _hover = _at(d.localPosition.dx, c.maxWidth)),
                    onHorizontalDragEnd: (_) {
                      final i = _hover;
                      setState(() => _hover = null);
                      if (i != null && _ids[i] != activeId) _open(_ids[i]); // провели до своей же вкладки — ничего не закрываем
                    },
                    onHorizontalDragCancel: () => setState(() => _hover = null),
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: pal.tabbar, // сплошной, без просвечивания; цвет — свой у каждой темы
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: pal.tabbarText.withValues(alpha: 0.1)),
                        boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 6))],
                      ),
                      child: Stack(children: [
                        AnimatedPositioned(
                          duration: anim ? Duration(milliseconds: _hover != null ? 140 : 300) : Duration.zero,
                          curve: Curves.easeOutCubic,
                          left: 5 + cellW * shown,
                          top: 5,
                          bottom: 5,
                          width: cellW,
                          child: DecoratedBox(key: const ValueKey('tab-pill'), decoration: BoxDecoration(color: pal.tabbarText.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(26))),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Row(children: [
                            for (final id in _ids)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Semantics(
                                    button: true,
                                    selected: id == activeId,
                                    label: id == 'more' && upd ? t('Ещё. Доступно обновление') : labels[id],
                                    excludeSemantics: true,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      borderRadius: BorderRadius.circular(26),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _open(id),
                                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          SizedBox(
                                            height: 26,
                                            width: 54,
                                            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                                              Icon(iosStyleOf(ref) ? iosIcon(icons[id]!) : icons[id], size: 22, color: id == activeId ? pal.tabbarText : Color.lerp(pal.tabbar, pal.tabbarText, 0.64)),
                                              if (id == 'more' && upd) Positioned(top: 2, right: 12, child: _UpdateDot(ring: pal.tabbar)),
                                            ]),
                                          ),
                                          const SizedBox(height: 2), // зазор между значком и подписью
                                          // подпись помещается целиком: шрифт поменьше, длинная (другие языки) ужимается по ширине вкладки
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(labels[id]!, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10.5, height: 1.15, leadingDistribution: TextLeadingDistribution.even, fontWeight: id == activeId ? FontWeight.w800 : FontWeight.w600, color: id == activeId ? pal.tabbarText : Color.lerp(pal.tabbar, pal.tabbarText, 0.64))),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Нижние вкладки поверх навигатора (.tabbar поверх .sheet): остаются видимыми и нажимаемыми над открытыми окнами,
/// затемнение окон их не перекрывает. На любой ширине (на широком — по центру), когда главный экран на месте.
class TabBarOverlay extends StatelessWidget {
  const TabBarOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: tabBarSuppress,
      builder: (context, suppressed, _) => ValueListenableBuilder<bool>(
      valueListenable: nativeSearchActive,
      builder: (context, _, _) => ValueListenableBuilder<bool>(
      valueListenable: homeMounted,
      builder: (context, mounted, _) {
        // с клавиатурой вкладки прячутся (окно поднимается над ней); поверх — полноэкранная страница (проигрыватель)
        final kb = mq.viewInsets.bottom;
        // системный поиск iOS 26 раскрыт: меню (с полем поиска) не прячется под клавиатуру, а встаёт над ней
        final searching = nativeGlass && nativeSearchActive.value;
        final show = mounted && suppressed == 0 && (kb == 0 || searching);
        final inset = show ? tabBarHeight(context) : 0.0;
        if (tabBarInset.value != inset) WidgetsBinding.instance.addPostFrameCallback((_) => tabBarInset.value = inset);
        return Stack(fit: StackFit.expand, children: [
          child,
          if (show)
            Positioned(
              left: 0,
              right: 0,
              bottom: searching && kb > 0 ? kb - 12 : 0,
              // на широком экране капсула не растягивается: по центру, не шире 544 (как на большом телефоне)
              child: _FocusHide(
                down: true,
                // без затухания под вкладками — ни над главой, ни над окнами (просьба владельца, 04.11.2026)
                child: Center(heightFactor: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 544), child: const _TabBar())),
              ),
            ),
          // верхний слой (инструкция) — над вкладками; своё Overlay — для подсказок и полей внутри него
          ValueListenableBuilder<Widget?>(
            key: Hub.topLayerHost,
            valueListenable: Hub.topLayer,
            builder: (_, layer, _) => layer == null
                ? const Positioned(left: 0, top: 0, width: 0, height: 0, child: SizedBox.shrink())
                : Positioned.fill(child: Overlay(key: ObjectKey(layer), initialEntries: [OverlayEntry(builder: (_) => layer)])),
          ),
        ]);
      },
    ),
    ),
    );
  }
}
