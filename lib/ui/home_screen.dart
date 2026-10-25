// Главный экран: одна или две панели чтения, у каждой — шапка (перевод, место, история, вторая панель),
// внизу на телефоне — плавающая капсула вкладок «Планы, Поиск, Библия, Закладки, Ещё».
// Вид — как в веб-версии (ReaderToolbar.jsx, TabBar.jsx, SplitScreenReader.jsx, ModulePicker.jsx, styles.css).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import 'kit.dart';
import 'navigator_sheet.dart';
import 'reader_pane.dart';
import 'search_screen.dart';

/// Какая нижняя вкладка сейчас открыта: plans, search, bible, saved, more (activeTab в TabBar.jsx)
final tabActive = ValueNotifier<String>('bible');

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
    final wide = size.width >= 900;
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
          body: SafeArea(bottom: false, child: slots.length == 1 ? slots.first : _Split(columns: columns, first: slots[0], second: slots[1])),
          bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
            if (Hub.audioBar != null) Hub.audioBar!(context, ref),
            // сами вкладки лежат поверх навигатора (TabBarOverlay); здесь — место под них, чтобы не закрывать чтение
            if (!wide) _FocusHide(down: true, child: SizedBox(height: tabBarHeight(context))),
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
    final thick = cols ? 18.0 : 22.0;
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
      final kids = [slot(widget.first, first), divider, slot(widget.second, total - first)];
      return cols ? Row(children: kids) : Column(children: kids);
    });
  }
}

/// Разделитель (.divider): цвета верхней панели, «ручка» посередине; тянется пальцем и мышью, стрелки двигают на 5 %
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

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final cols = widget.columns;
    final grip = Container(
      width: cols ? 12 : 72,
      height: cols ? 72 : 12,
      decoration: BoxDecoration(color: _on ? pal.accent : pal.barText.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
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
            onHorizontalDragUpdate: cols ? (d) => widget.onDrag(d.delta.dx) : null,
            onHorizontalDragEnd: cols ? (_) => widget.onEnd() : null,
            onHorizontalDragCancel: cols ? widget.onEnd : null,
            onVerticalDragUpdate: cols ? null : (d) => widget.onDrag(d.delta.dy),
            onVerticalDragEnd: cols ? null : (_) => widget.onEnd(),
            onVerticalDragCancel: cols ? null : widget.onEnd,
            child: Container(width: cols ? widget.thick : null, height: cols ? null : widget.thick, color: pal.bar, alignment: Alignment.center, child: grip),
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
            decoration: BoxDecoration(color: pal.bar, boxShadow: [BoxShadow(color: mix(pal.line, 0.7, Colors.black26), offset: const Offset(0, 1))]),
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(children: [
              // Перевод: короткое имя «RST+ ˅» — плашка
              _BarChip(label: shortName(mod), tip: t('Перевод: {name}. Сменить перевод', {'name': mod?.name ?? module}), bg: chipBg, fg: fg, fontSize: narrow ? 14.1 : 15.2, weight: FontWeight.w800, maxWidth: paneW * 0.38, chevron: !tiny, onTap: () => _pickModule(context)),
              const SizedBox(width: 2),
              // Место: полное название книги («Бытие 1:1», «От Иоанна 3:16»); длинное или не помещается — сокращение
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<VerseRef>(
                      valueListenable: livePosition(index, initial),
                      builder: (_, r, _) => _BarChip(
                        label: _refLabel(context, r, c.maxWidth, narrow ? 16.3 : 17.9, tiny),
                        tip: t('{ref}. Выбрать место', {'ref': Books.instance.formatRef(r.book, r.chapter, r.verse, full: true)}),
                        bg: chipBg,
                        fg: fg,
                        fontSize: narrow ? 16.3 : 17.9,
                        weight: FontWeight.w700,
                        chevron: !tiny,
                        onTap: () => openNavigator(context, index),
                      ),
                    ),
                  ),
                ),
              ),
              tbIcon(LucideIcons.arrowLeft, t('Назад по истории'), hist.$1 > 0 ? () => ref.read(panesProvider.notifier).go(index, -1) : null),
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
      // Режим плана: вместо читалки — лента отрывков дня (PlanView); ставит и снимает функция планов
      Expanded(
        child: ValueListenableBuilder<Map<int, ({String uid, int day})>>(
          valueListenable: planMode,
          builder: (context, m, _) => m[index] != null && Hub.planView != null ? Hub.planView!(context, ref, index) : ReaderPane(index: index),
        ),
      ),
    ]);
  }

  // Выбор перевода (ModulePicker.jsx)
  void _pickModule(BuildContext context) {
    showAobSheet(context, initial: 0.6, builder: (c) => _ModulePicker(pane: index, outer: context));
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
class _ModulePicker extends ConsumerWidget {
  const _ModulePicker({required this.pane, required this.outer});
  final int pane;
  final BuildContext outer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final primary = ref.watch(settingsProvider.select((s) => s.get<String>('primaryModule')));
    final current = ref.watch(panesProvider.select((l) => pane < l.length ? l[pane].moduleId : ''));
    // Список обновляется, когда переводы ставятся и удаляются
    return ValueListenableBuilder<int>(
      valueListenable: ModuleStore.instance.changes,
      builder: (context, _, _) {
        final list = ModuleStore.instance.bibles.where((m) => m.features['helper'] != true).toList();
        return AobSheet(
          title: t('Перевод'),
          subtitle: pane == 1 ? t('Вторая панель') : t('Основная панель'),
          scroll: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ListView(children: [
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: Material(
                      color: m.id == current ? mix(pal.accent, 0.08, pal.bg) : pal.bg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: m.id == current ? pal.accent : pal.line)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          ref.read(panesProvider.notifier).setModule(pane, m.id);
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                                const SizedBox(height: 2),
                                Text('${m.title}${m.features['strongs'] == true ? ' · ${t('номера Стронга')}' : ''}', style: TextStyle(fontSize: 12.75, color: pal.muted)),
                              ]),
                            ),
                            if (m.id == current) Icon(LucideIcons.check, size: 18, color: pal.accent),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (primary != m.id)
                    IconBtn(icon: LucideIcons.star, subtle: true, tooltip: t('Сделать основным'), onTap: () => ref.read(settingsProvider.notifier).set({'primaryModule': m.id}))
                  else
                    Tooltip(message: t('Основной перевод'), child: SizedBox(width: 32, height: 32, child: Center(child: CustomPaint(size: const Size(16, 16), painter: _StarPainter(pal.accent))))),
                ]),
              ),
            if (Hub.openLibraryTab != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
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

/// Плашка в шапке (.toolbar .tb-module / .tb-ref): высота 40, «таблетка», стрелка ˅
class _BarChip extends StatelessWidget {
  const _BarChip({required this.label, required this.bg, required this.fg, required this.fontSize, required this.weight, required this.onTap, this.maxWidth, this.tip, this.chevron = true});
  final String label;
  final Color bg, fg;
  final double fontSize;
  final FontWeight weight;
  final VoidCallback onTap;
  final double? maxWidth;
  final String? tip;
  final bool chevron;
  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // без alignment: Container с выравниванием растягивается на всю доступную ширину
          height: 40,
          padding: EdgeInsets.only(left: 12, right: chevron ? 10 : 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: fontSize, fontWeight: weight, color: fg, letterSpacing: .15))),
            if (chevron) ...[const SizedBox(width: 3), Icon(LucideIcons.chevronDown, size: 16, color: fg.withValues(alpha: 0.7))],
          ]),
        ),
      ),
    );
    final w = tip == null ? chip : Tooltip(message: tip!, child: chip);
    if (maxWidth == null) return w;
    return ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: w);
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
                        color: pal.panel.withValues(alpha: 0.8),
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
                                          const SizedBox(height: 2),
                                          Text(labels[id]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: id == activeId ? FontWeight.w800 : FontWeight.w600, color: id == activeId ? pal.text : pal.muted)),
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
/// затемнение окон их не перекрывает. Только на узком экране, когда главный экран на месте.
class TabBarOverlay extends StatelessWidget {
  const TabBarOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: homeMounted,
      builder: (context, mounted, _) {
        // с клавиатурой вкладки прячутся (окно поднимается над ней)
        final show = mounted && mq.size.width < 900 && mq.viewInsets.bottom == 0;
        final inset = show ? tabBarHeight(context) : 0.0;
        if (tabBarInset.value != inset) WidgetsBinding.instance.addPostFrameCallback((_) => tabBarInset.value = inset);
        return Stack(fit: StackFit.expand, children: [
          child,
          if (show) const Positioned(left: 0, right: 0, bottom: 0, child: _FocusHide(down: true, child: _TabBar())),
        ]);
      },
    );
  }
}
