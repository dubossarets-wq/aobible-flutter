// Главный экран: одна или две панели чтения, у каждой — шапка (перевод, место, история, вторая панель),
// внизу на телефоне — плавающая капсула вкладок «Планы, Поиск, Библия, Закладки, Ещё».
// Вид — как в веб-версии (ReaderToolbar.jsx, TabBar.jsx, styles.css: .toolbar, .tb-module, .tb-ref, .tabbar).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panes = ref.watch(panesProvider.select((l) => l.length));
    final mapPlace = ref.watch(mapPaneProvider);
    final pal = paletteOf(ref);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final layout = ref.watch(settingsProvider.select((s) => s.get<String>('splitLayout')));
    final rows = layout == 'rows' || (layout == 'auto' && !wide);
    final children = [for (var i = 0; i < panes; i++) Expanded(child: _Pane(index: i))];
    // Карта места — во второй половине вместо второй панели чтения (та не теряется и вернётся после закрытия)
    final map = mapPlace != null && Hub.mapPaneBuilder != null;
    if (map) {
      if (children.length > 1) children.removeLast();
      children.add(Expanded(child: Hub.mapPaneBuilder!(context, ref, mapPlace)));
    }
    final count = children.length;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: count == 1
            ? const _Pane(index: 0)
            : rows
                ? Column(children: [children[0], Container(height: 1, color: pal.line), children[1]])
                : Row(children: [children[0], Container(width: 1, color: pal.line), children[1]]),
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (Hub.audioBar != null) Hub.audioBar!(context, ref),
        if (!wide) const _TabBar(),
      ]),
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
    final name = ModuleStore.instance.get(module)?.name ?? module;
    final initial = ref.read(panesProvider)[index].ref;
    final selecting = ref.watch(selectionProvider.select((m) => m[index]?.isNotEmpty ?? false));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final fg = pal.barText;
    final chipBg = mix(fg, 0.14, pal.bar);
    Widget tbIcon(IconData icon, String tip, VoidCallback? onTap) => Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: Tooltip(message: tip, child: Icon(icon, size: 22, color: fg))),
            ),
          ),
        );
    return Column(children: [
      if (selecting && Hub.selectionBar != null)
        Hub.selectionBar!(context, ref, index)
      else
        Container(
          height: barHeight,
          decoration: BoxDecoration(color: pal.bar, boxShadow: [BoxShadow(color: mix(pal.line, 0.7, Colors.black26), offset: const Offset(0, 1))]),
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: Row(children: [
            // Перевод: «RST+ ˅» — плашка
            _BarChip(label: name, bg: chipBg, fg: fg, fontSize: 15.2, weight: FontWeight.w800, maxWidthFactor: 0.38, onTap: () => _pickModule(context, ref)),
            const SizedBox(width: 2),
            // Место: «Быт. 1:1 ˅»
            // Место: полное название книги («Бытие 1:1», «От Иоанна 3:16»); длинное или не помещается — сокращение
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<VerseRef>(
                    valueListenable: livePosition(index, initial),
                    builder: (_, r, _) => _BarChip(label: _refLabel(context, r, c.maxWidth), bg: chipBg, fg: fg, fontSize: 17.9, weight: FontWeight.w700, onTap: () => openNavigator(context, index)),
                  ),
                ),
              ),
            ),
            tbIcon(LucideIcons.arrowLeft, t('Назад по истории'), hist.$1 > 0 ? () => ref.read(panesProvider.notifier).go(index, -1) : null),
            if (hist.$1 < hist.$2 - 1) tbIcon(LucideIcons.arrowRight, t('Вперёд по истории'), () => ref.read(panesProvider.notifier).go(index, 1)),
            if (wide && index == 0) tbIcon(LucideIcons.search, t('Поиск'), () => openSearch(context, index)),
            if (wide && index == 0) tbIcon(LucideIcons.ellipsisVertical, t('Ещё'), Hub.openMore == null ? null : () => Hub.openMore!(context, ref, index)),
            if (index == 0 || split)
              tbIcon(split && index == 1 ? LucideIcons.x : LucideIcons.columns2, split && index == 1 ? t('Закрыть вторую панель') : t('Читать параллельно'), () => ref.read(panesProvider.notifier).toggleSplit()),
          ]),
        ),
      Expanded(child: ReaderPane(index: index)),
    ]);
  }

  // Выбор перевода (ModulePicker.jsx): список установленных переводов, у текущего — галочка
  void _pickModule(BuildContext context, WidgetRef ref) {
    final current = ref.read(panesProvider)[index].moduleId;
    showAobSheet(
      context,
      initial: 0.6,
      builder: (c) => Consumer(builder: (c, ref, _) {
        final pal = paletteOf(ref);
        final list = ModuleStore.instance.bibles.where((m) => m.features['helper'] != true).toList();
        return AobSheet(
          title: t('Перевод'),
          scroll: false,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
          child: ListView(children: [
            for (final m in list)
              InkWell(
                borderRadius: BorderRadius.circular(kRadius * 0.6),
                onTap: () {
                  ref.read(panesProvider.notifier).setModule(index, m.id);
                  Navigator.pop(c);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    SizedBox(width: 64, child: Text(m.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: m.id == current ? pal.accent : pal.text))),
                    Expanded(child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.muted))),
                    if (m.id == current) Icon(LucideIcons.check, size: 18, color: pal.accent),
                  ]),
                ),
              ),
            if (Hub.openLibrary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: AobButton(label: t('Установить другие переводы'), icon: LucideIcons.library, wide: true, onTap: () {
                  Navigator.pop(c);
                  Hub.openLibrary!(context, ref, index);
                }),
              ),
          ]),
        );
      }),
    );
  }
}

/// Плашка в шапке (.toolbar .tb-module / .tb-ref): высота 40, «таблетка», стрелка ˅
/// Подпись плашки места: полное название книги, если оно короткое (до 14 знаков) и помещается, иначе — сокращение
String _refLabel(BuildContext context, VerseRef r, double maxWidth) {
  final b = Books.instance;
  final name = b.meta(r.book).name;
  final full = '$name ${r.chapter}:${r.verse}';
  if (name.runes.length <= 14) {
    final tp = TextPainter(
      text: TextSpan(text: full, style: const TextStyle(fontSize: 17.9, fontWeight: FontWeight.w700, letterSpacing: .15)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final fits = tp.width + 41 <= maxWidth; // 41 — поля плашки и стрелка
    tp.dispose();
    if (fits) return full;
  }
  return b.formatRef(r.book, r.chapter, r.verse);
}

class _BarChip extends StatelessWidget {
  const _BarChip({required this.label, required this.bg, required this.fg, required this.fontSize, required this.weight, required this.onTap, this.maxWidthFactor});
  final String label;
  final Color bg, fg;
  final double fontSize;
  final FontWeight weight;
  final VoidCallback onTap;
  final double? maxWidthFactor;
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
          padding: const EdgeInsets.only(left: 12, right: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: fontSize, fontWeight: weight, color: fg, letterSpacing: .15))),
            const SizedBox(width: 3),
            Icon(LucideIcons.chevronDown, size: 16, color: fg.withValues(alpha: 0.7)),
          ]),
        ),
      ),
    );
    if (maxWidthFactor == null) return chip;
    return ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * maxWidthFactor!), child: chip);
  }
}

/// Нижние вкладки — плавающая капсула (.tabbar): высота 64, отступы 12, скругление 32, полупрозрачная с размытием
class _TabBar extends ConsumerWidget {
  const _TabBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    void soon() => Hub.toast(t('Скоро'));
    void call(PaneAction? a) => a == null ? soon() : a(context, ref, 0);
    final tabs = [
      (LucideIcons.calendarCheck, t('Планы'), () => call(Hub.openPlans)),
      (LucideIcons.search, t('Поиск'), () => openSearch(context, 0)),
      (LucideIcons.bookOpen, t('Библия'), () {}),
      (LucideIcons.heart, t('Закладки'), () => call(Hub.openBookmarks)),
      (LucideIcons.menu, t('Ещё'), () => call(Hub.openMore)),
    ];
    const active = 2; // «Библия» — экран чтения; остальные вкладки открывают окна поверх
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: pal.panel.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: pal.text.withValues(alpha: 0.09)),
              boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Material(
                      color: i == active ? pal.text.withValues(alpha: 0.09) : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: tabs[i].$3,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(height: 26, child: Icon(tabs[i].$1, size: 22, color: i == active ? pal.text : pal.muted)),
                          const SizedBox(height: 2),
                          Text(tabs[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: i == active ? FontWeight.w800 : FontWeight.w600, color: i == active ? pal.text : pal.muted)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
