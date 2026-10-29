// Главный экран: одна или две панели чтения, у каждой — шапка (перевод, место, история, вторая панель),
// внизу на телефоне — плавающая капсула вкладок «Планы, Поиск, Библия, Закладки, Ещё».
// Вид — как в веб-версии (ReaderToolbar.jsx, TabBar.jsx, SplitScreenReader.jsx, ModulePicker.jsx, styles.css).
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'kit.dart';
import 'navigator_sheet.dart';
import 'reader_pane.dart';
import 'search_screen.dart';

export 'kit.dart' show tabActive; // переехал в kit.dart (его подсвечивают и окна функций)


/// Главный экран на месте (не первая загрузка) — только тогда показываются нижние вкладки
final homeMounted = ValueNotifier<bool>(false);

/// Высота вкладок: 4 + капсула 64 + 12 + системный отступ снизу
double tabBarHeight(BuildContext context) => 80 + MediaQuery.paddingOf(context).bottom;

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
          body: SafeArea(bottom: false, child: slots.length == 1 ? slots.first : _Split(columns: columns, first: slots[0], second: slots[1])),
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

/// Две панели с разделителем (SplitScreenReader.jsx): разделитель перетаскивается, доля помнится в splitRatio
class _Split extends ConsumerStatefulWidget {
  const _Split({required this.columns, required this.first, required this.second});
  final bool columns;
  final Widget first, second;
  @override
  ConsumerState<_Split> createState() => _SplitState();
}

class _SplitState extends ConsumerState<_Split> {
  double? _drag; // доля во время перетаскивания

  double _clamp(double v) => v.clamp(0.2, 0.8);

  void _save(double v) => ref.read(settingsProvider.notifier).set({'splitRatio': _clamp(v)});

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final saved = ref.watch(settingsProvider.select((s) => s.d('splitRatio')));
    final ratio = _clamp(_drag ?? saved);
    final cols = widget.columns;
    final thick = cols ? 12.0 : 16.0;
    return LayoutBuilder(builder: (context, c) {
      final total = (cols ? c.maxWidth : c.maxHeight) - thick;
      final first = total * ratio;
      Widget slot(Widget w, double extent) => SizedBox(width: cols ? extent : null, height: cols ? null : extent, child: w);
      final divider = _Divider(
        columns: cols,
        thick: thick,
        pal: pal,
        ratio: ratio,
        onDrag: (delta) => setState(() => _drag = _clamp((_drag ?? saved) + delta / total)),
        onEnd: () {
          if (_drag != null) _save(_drag!);
          setState(() => _drag = null);
        },
        onStep: (d) => _save(ratio + d),
      );
      // верхняя панель (разделение по строкам) не доходит до проигрывателя — нижний запас ей не нужен
      // текст верхней панели к ручке растворяется, а не режется (разделитель цвета страницы)
      final top = cols
          ? widget.first
          : Stack(children: [
              Positioned.fill(child: MediaQuery.removePadding(context: context, removeBottom: true, child: widget.first)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 22,
                child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pal.bg.withValues(alpha: 0), pal.bg])))),
              ),
            ]);
      final kids = [slot(top, first), divider, slot(widget.second, total - first)];
      return cols ? Row(children: kids) : Column(children: kids);
    });
  }
}

/// Разделитель (.divider): фон страницы, тёмная «ручка» посередине; тянется пальцем и мышью, стрелки двигают на 5 %
class _Divider extends StatefulWidget {
  const _Divider({required this.columns, required this.thick, required this.pal, required this.ratio, required this.onDrag, required this.onEnd, required this.onStep});
  final bool columns;
  final double thick, ratio;
  final Palette pal;
  final void Function(double delta) onDrag;
  final VoidCallback onEnd;
  final void Function(double d) onStep;
  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _on = false; // наведён или в фокусе — ручка цвета акцента
  bool _drag = false; // тянется

  void _end() {
    if (mounted) setState(() => _drag = false);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final cols = widget.columns;
    // короткая ручка, как у системных шторок; наведён, в фокусе или тянется — вытягивается и цвета акцента
    final on = _on || _drag;
    final grip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: cols ? 5 : (on ? 56 : 36),
      height: cols ? (on ? 56 : 36) : 5,
      decoration: BoxDecoration(color: on ? pal.accent : pal.text.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
    );
    return Semantics(
      label: t('Изменить размер панелей'),
      value: '${(widget.ratio * 100).round()}',
      child: Focus(
        onFocusChange: (f) => setState(() => _on = f),
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          final d = k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp
              ? -0.05
              : k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown
                  ? 0.05
                  : null;
          if (d == null) return KeyEventResult.ignored;
          widget.onStep(d);
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: cols ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _on = true),
          onExit: (_) => setState(() => _on = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: cols ? (_) => setState(() => _drag = true) : null,
            onHorizontalDragUpdate: cols ? (d) => widget.onDrag(d.delta.dx) : null,
            onHorizontalDragEnd: cols ? (_) => _end() : null,
            onHorizontalDragCancel: cols ? _end : null,
            onVerticalDragStart: cols ? null : (_) => setState(() => _drag = true),
            onVerticalDragUpdate: cols ? null : (d) => widget.onDrag(d.delta.dy),
            onVerticalDragEnd: cols ? null : (_) => _end(),
            onVerticalDragCancel: cols ? null : _end,
            // без полосы цвета панели: фон страницы, видна только тёмная ручка
            child: Container(width: cols ? widget.thick : null, height: cols ? null : widget.thick, color: pal.bg, alignment: Alignment.center, child: grip),
          ),
        ),
      ),
    );
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
    final split = ref.watch(panesProvider.select((l) => l.length > 1));
    final hist = ref.watch(panesProvider.select((l) => index < l.length ? (l[index].hIndex, l[index].history.length) : (0, 0)));
    if (module == null) return const SizedBox.shrink();
    final mod = ModuleStore.instance.get(module);
    final initial = ref.read(panesProvider)[index].ref;
    final selecting = ref.watch(selectionProvider.select((m) => m[index]?.isNotEmpty ?? false));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Узкая панель (две панели рядом на телефоне): кнопки и надписи теснее, на самой узкой — без стрелок ˅
    // (@container в styles.css: ≤ 470 px и ≤ 360 px)
    return LayoutBuilder(builder: (context, box) => _build(context, ref, box.maxWidth, pal, barHeight, module, split, hist, mod, initial, selecting, wide));
  }

  Widget _build(BuildContext context, WidgetRef ref, double paneW, Palette pal, double barHeight, String module, bool split, (int, int) hist, InstalledModule? mod, VerseRef initial, bool selecting, bool wide) {
    final narrow = paneW <= 470, tiny = paneW <= 360;
    final ilBar = ref.watch(settingsProvider.select((s) => s.get<bool>('ilBar'))) != false; // панель подстрочника раскрыта
    final inter = mod?.features['interlinear'] == true;
    final fg = pal.barText;
    final chipBg = mix(fg, 0.14, pal.bar);
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
                  child: InkWell(onTap: onTap, child: Tooltip(message: tip, child: Icon(icon, size: 22, color: fg))),
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
            decoration: BoxDecoration(color: pal.bar, boxShadow: mod?.features['interlinear'] == true && ilBar ? null : [BoxShadow(color: mix(pal.line, 0.7, Colors.black26), offset: const Offset(0, 1))]),
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(children: [
              // Перевод и место — одна капсула: слева короткое имя перевода (мельче, приглушённо), тонкий разделитель,
              // справа место — полное название книги («Бытие 1:1»), длинное или не помещается — сокращение; у каждой
              // части своё нажатие: перевод → выбор перевода, место → «Перейти»
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final modLabel = shortName(mod);
                  final modSize = narrow ? 12.9 : 13.6, refSize = narrow ? 15.6 : 16.6;
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
              if (wide && index == 0) tbIcon(LucideIcons.search, t('Поиск'), () => openSearch(context, index)),
              if (wide && index == 0)
                ValueListenableBuilder<bool>(
                  valueListenable: updateAvailable,
                  builder: (_, upd, _) => tbIcon(LucideIcons.ellipsisVertical, upd ? t('Ещё. Доступно обновление') : t('Ещё'), Hub.openMore == null ? null : () => Hub.openMore!(context, ref, index), dot: upd),
                ),
              if (index == 0 || split)
                tbIcon(split && index == 1 ? LucideIcons.x : LucideIcons.columns2, split && index == 1 ? t('Закрыть вторую панель') : t('Читать параллельно'), () => ref.read(panesProvider.notifier).toggleSplit()),
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
    showAobSheet(context, initial: initial, builder: (c) => _ModulePicker(pane: index, outer: context));
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

/// Что в переводе (ModulePicker.jsx, KINDS): по его книгам и возможностям
bool _hasBooks(InstalledModule m, bool Function(BookInfo b) test) => bookList(m.id).any((x) => test(Books.instance.meta('${x['id']}')));
final _kinds = <(String, String, bool Function(InstalledModule))>[
  ('full', 'Вся Библия', (m) => _hasBooks(m, (b) => b.testament == 'OT' && !b.dc) && _hasBooks(m, (b) => b.testament == 'NT')),
  ('ot', 'Ветхий Завет', (m) => _hasBooks(m, (b) => b.testament == 'OT' && !b.dc)),
  ('nt', 'Новый Завет', (m) => _hasBooks(m, (b) => b.testament == 'NT')),
  ('dc', 'Неканон', (m) => _hasBooks(m, (b) => b.dc || b.testament == 'AP')),
  ('strongs', 'С номерами Стронга', (m) => m.features['strongs'] == true),
  ('il', 'Подстрочник', (m) => m.features['interlinear'] == true),
];

class _ModulePickerState extends ConsumerState<_ModulePicker> {
  String? _lang; // выбранный язык в выборке сверху; null — все
  String? _kind; // что в переводе; null — всё

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
        // выборка по языкам — если переводы на разных языках; язык приложения — первым
        final langs = <String>{for (final m in ordered) m.language}.toList()..sort((a, b) => a == currentLang ? -1 : b == currentLang ? 1 : 0);
        final lang = langs.contains(_lang) ? _lang : null;
        final byLang = lang == null ? ordered : [for (final m in ordered) if (m.language == lang) m];
        // что в переводе: показываем только выборки, которые отбирают часть списка
        final kinds = [
          for (final k in _kinds)
            if (byLang.where(k.$3).length case final n when n > 0 && n < byLang.length) k,
        ];
        final kind = kinds.where((k) => k.$1 == _kind).firstOrNull;
        final list = kind == null ? byLang : byLang.where(kind.$3).toList();
        String langName(String code) {
          final n = langDisplayNames[currentLang]?[code] ?? code;
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
                    AobChip(label: t('Все'), on: lang == null, onTap: () => setState(() => _lang = null)),
                    for (final l in langs) AobChip(label: langName(l), on: lang == l, onTap: () => setState(() => _lang = l)),
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

/// Шапка панели: перевод и место — одна капсула высотой 36 из двух частей с тонким разделителем.
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
          // высота 36 — компактно, но удобно нажимать (вся ширина части — зона нажатия)
          child: InkWell(onTap: onTap, child: Container(height: 36, padding: pad, child: Align(widthFactor: 1, child: child))),
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
            const EdgeInsets.only(left: 14, right: 11),
            // надписи — ровно по середине капсулы: запас строки поровну и на 1 px выше (как в кнопках)
            Transform.translate(offset: const Offset(0, -1), child: Text(module, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: moduleSize, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w700, letterSpacing: .4, color: fg.withValues(alpha: 0.78)))),
          ),
        ),
        Container(width: 1, height: 18, color: fg.withValues(alpha: 0.2)),
        Flexible(
          child: part(
            placeTip,
            onPlace,
            EdgeInsets.only(left: 11, right: chevron ? 10 : 14),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Transform.translate(offset: const Offset(0, -1), child: Text(place, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: placeSize, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w700, letterSpacing: .1, color: fg)))),
              // стрелка ˅ — на одной линии с поднятой надписью
              if (chevron) ...[const SizedBox(width: 4), Transform.translate(offset: const Offset(0, -0.5), child: Icon(LucideIcons.chevronDown, size: 16, color: fg.withValues(alpha: 0.6)))],
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
              // высота — по содержимому (36): без этого OverflowBox брал всю высоту шапки и раздувал капсулу
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 37,
                maxWidth: 37,
                fit: OverflowBoxFit.deferToChild,
                child: IgnorePointer(
                  ignoring: !tools!.on,
                  child: Row(children: [
                    Container(width: 1, height: 18, color: fg.withValues(alpha: 0.2)),
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
                          child: Icon(LucideIcons.slidersHorizontal, size: 16, color: fg.withValues(alpha: 0.75)),
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
    // поверх может быть и страница (большой проигрыватель) — нажатие на вкладку закрывает и её
    final nav = Navigator.of(_nav);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
    if (id == 'bible' || tabActive.value == id) return closeAllSheets(_nav);
    // нажали вкладку при открытых окнах: сперва закрываем их все, потом открываем раздел
    if (sheetsOpen.value > 0 || topRoute(_nav) is PopupRoute) closeAllSheets(_nav);
    final before = topRoute(_nav);
    _run(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = topRoute(_nav);
      if (after == before || after is! PopupRoute) return;
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
                        color: pal.panel, // сплошной белый (на светлых темах), без просвечивания
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: pal.text.withValues(alpha: 0.09)),
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
                          child: DecoratedBox(key: const ValueKey('tab-pill'), decoration: BoxDecoration(color: pal.text.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(26))),
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
                                              Icon(icons[id], size: 22, color: id == activeId ? pal.text : pal.muted),
                                              if (id == 'more' && upd) Positioned(top: 2, right: 12, child: _UpdateDot(ring: pal.panel)),
                                            ]),
                                          ),
                                          const SizedBox(height: 2), // зазор между значком и подписью
                                          // подпись помещается целиком: шрифт поменьше, длинная (другие языки) ужимается по ширине вкладки
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(labels[id]!, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10.5, height: 1.15, leadingDistribution: TextLeadingDistribution.even, fontWeight: id == activeId ? FontWeight.w800 : FontWeight.w600, color: id == activeId ? pal.text : pal.muted)),
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
/// Затухание под вкладками: от верха капсулы (прозрачно) до её середины — цвет того, что под ней
/// (открытое окно — panel, иначе фон страницы), ниже — сплошной цвет
class _TabFade extends ConsumerWidget {
  const _TabFade();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: sheetsOpen,
        builder: (context, open, _) {
          // над главой затухание делает сама читалка (маской текста — виден настоящий фон страницы);
          // здесь — только над открытым окном, цветом окна
          if (open == 0) return const SizedBox.shrink();
          final c = pal.panel;
          // капсула — 64 px с отступом 4 сверху (_TabBar)
          return LayoutBuilder(builder: (context, box) {
            final h = box.maxHeight <= 0 ? 1.0 : box.maxHeight;
            return DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [(4 / h).clamp(0.0, 1.0), (36 / h).clamp(0.0, 1.0)], colors: [c.withValues(alpha: 0), c])),
            );
          });
        },
      ),
    );
  }
}

class TabBarOverlay extends StatelessWidget {
  const TabBarOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: tabBarSuppress,
      builder: (context, suppressed, _) => ValueListenableBuilder<bool>(
      valueListenable: homeMounted,
      builder: (context, mounted, _) {
        // с клавиатурой вкладки прячутся (окно поднимается над ней); поверх — полноэкранная страница (проигрыватель)
        final show = mounted && suppressed == 0 && mq.viewInsets.bottom == 0;
        final inset = show ? tabBarHeight(context) : 0.0;
        if (tabBarInset.value != inset) WidgetsBinding.instance.addPostFrameCallback((_) => tabBarInset.value = inset);
        return Stack(fit: StackFit.expand, children: [
          child,
          if (show)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // под вкладками всё (глава, окно, список) плавно гаснет с их середины, чтобы не торчало снизу
              // на широком экране капсула не растягивается: по центру, не шире 544 (как на большом телефоне)
              child: _FocusHide(
                down: true,
                child: Stack(children: [
                  const Positioned.fill(child: _TabFade()),
                  Center(heightFactor: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 544), child: const _TabBar())),
                ]),
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
    );
  }
}
