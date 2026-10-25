// Панель действий над выделенными стихами (SelectionBar.jsx): вместо шапки панели, пока есть выделение.
// ✓ · ссылка и число стихов · параллельно · цвет · любимые · заметка · закладка · ⋯ (подстрочник, в проповедь,
// в подборку, сравнить переводы, слушать, копировать, поделиться).
// hostContext/hostRef — от панели чтения: сама строка исчезает, как только выделение снято, а окна и
// функции из Hub должны жить дольше неё.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'marks.dart';
import 'sheets.dart';
import 'ui.dart';

Widget buildSelectionBar(BuildContext context, WidgetRef ref, int pane) => _SelectionBar(pane: pane, hostContext: context, hostRef: ref);

/// Оригиналы (еврейский и греческий текст) — для подстрочника; «параллельно» предлагаем только переводы
const _originals = {'oshb', 'byz-rp2018'};

class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.pane, required this.hostContext, required this.hostRef});
  final int pane;
  final BuildContext hostContext;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref); // только палитра: прочие настройки панель не перестраивают
    final sel = ref.watch(selectionProvider.select((m) => m[pane] ?? const <VerseRef>{}));
    final marks = ref.watch(marksProvider);
    final moduleId = ref.watch(panesProvider.select((l) => pane < l.length ? l[pane].moduleId : 'rst-plus'));
    if (sel.isEmpty) return const SizedBox(height: 54);
    final refs = sortedRefs(sel);
    final first = refs.first;
    final fav = refs.every(marks.isFavorite);
    final bm = marks.isBookmarked(first);
    final hasNote = marks.noteOf(first) != null;
    final hl = marks.highlights[refKey(first)] != null;
    final c = hostContext, r = hostRef;

    void done() => ref.read(selectionProvider.notifier).clear(pane);
    // Выделение снимаем кадром позже: окно (например, подстрочник) открывается в одной перерисовке с остальным
    void doneLater() => WidgetsBinding.instance.addPostFrameCallback((_) => hostContext.mounted ? r.read(selectionProvider.notifier).clear(pane) : null);

    void copy() {
      Clipboard.setData(ClipboardData(text: quoteText(moduleId, refs)));
      toast(c, refs.length > 1 ? t('Скопировано стихов: {n}', {'n': '${refs.length}'}) : t('Стих скопирован'));
      done();
    }

    Future<void> share() async {
      try {
        await SharePlus.instance.share(ShareParams(text: quoteText(moduleId, refs)));
        done();
      } catch (_) {
        Clipboard.setData(ClipboardData(text: quoteText(moduleId, refs)));
        if (c.mounted) toast(c, t('Поделиться нельзя — текст скопирован'));
      }
    }

    void toggleFav() {
      r.read(marksProvider.notifier).setFavorites([for (final x in refs) (x, selectionText(moduleId, [x]))], !fav);
      toast(c, fav ? t('Убрано из любимых стихов') : t('♥ Добавлено в любимые стихи'));
      done();
    }

    void toggleBm() {
      final was = bm;
      r.read(marksProvider.notifier).toggleBookmark(first, was ? '' : _cut(selectionText(moduleId, [first]), 160));
      toast(c, was ? t('Закладка удалена') : t('Закладка: {ref}', {'ref': Books.instance.formatRef(first.book, first.chapter, first.verse)}));
      done();
    }

    // .tb-icon: круглая кнопка; на панели шире 400 px — 44×44, уже — 36 (container query в styles.css)
    final wide = MediaQuery.sizeOf(context).width >= 400;
    final onColor = mix(pal.accent, 0.55, Colors.white); // .toolbar .tb-icon.on
    Widget tb(Widget Function(Color c) icon, String tip, VoidCallback? f, {bool on = false}) => Tooltip(
          message: tip,
          child: SizedBox(
            width: wide ? 44 : 36,
            height: 44,
            child: Material(type: MaterialType.transparency, shape: const CircleBorder(), clipBehavior: Clip.antiAlias, child: InkWell(onTap: f, child: Center(child: icon(on ? onColor : pal.barText)))),
          ),
        );
    Widget lucide(IconData i, double size, String tip, VoidCallback f, {bool on = false}) => tb((c) => Icon(i, size: size, color: c), tip, f, on: on);

    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(color: pal.bar, boxShadow: [BoxShadow(color: mix(pal.line, 0.7, const Color(0x40000000)), offset: const Offset(0, 1))]),
      child: Row(children: [
        lucide(LucideIcons.x, 24, t('Готово, снять выделение'), done),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            // Под подпись остаётся мало места (8 кнопок по 44 px): подпись и число сжимаются вместе, а не вылезают за край
            child: LayoutBuilder(
              builder: (context, box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.max(box.maxWidth - 40, 60)),
                    child: Text(selectionLabel(refs), maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(color: pal.barText, fontWeight: FontWeight.w500, fontSize: wide ? 16.8 : 15.2)),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: t('Выделено стихов: {n}', {'n': '${refs.length}'}),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(11)),
                      child: Text('${refs.length}', style: TextStyle(color: pal.onAccent, fontSize: 12.5, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        lucide(LucideIcons.languages, 22, t('Читать параллельно'), () {
          _parallel(c, r, pane, refs, moduleId);
          done();
        }),
        if (Hub.openCommentary != null)
          lucide(LucideIcons.messageSquareText, 21, t('Комментарии'), () {
            Hub.openCommentary!(c, r, pane, first);
            done();
          }),
        PopupMenuButton<String>(
          tooltip: t('Выделить цветом'),
          color: pal.panel,
          shape: _menuShape(pal),
          elevation: 12,
          shadowColor: const Color(0x38000000),
          menuPadding: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 112, maxWidth: 360), // ряд цветов шире стандартных 280 px
          position: PopupMenuPosition.under,
          onSelected: (id) {
            r.read(marksProvider.notifier).setHighlight(refs, id.isEmpty ? null : id);
            done();
          },
          itemBuilder: (_) => [_PaletteEntry(marks.hlLabels, marks.highlights[refKey(first)], pal)],
          child: tb((c) => Icon(LucideIcons.highlighter, size: 21, color: c), t('Выделить цветом'), null, on: hl),
        ),
        if (wide) // .tb-opt: на узкой панели (≤ 400 px) «любимые» остаются только в меню «⋯»
          tb((c) => fav ? FillIcon(path: lucideHeartPath, size: 21, color: c, stroke: true) : Icon(LucideIcons.heart, size: 21, color: c), fav ? t('Убрать из любимых') : t('В любимые'), toggleFav, on: fav),
        lucide(LucideIcons.notebookPen, 21, hasNote ? t('Открыть заметку') : t('Добавить заметку'), () {
          showNoteSheet(c, refs, moduleId);
          done();
        }, on: hasNote),
        lucide(bm ? LucideIcons.bookmarkCheck : LucideIcons.bookmark, 21, bm ? t('Убрать закладку') : t('Закладка: продолжить отсюда'), toggleBm, on: bm),
        PopupMenuButton<VoidCallback>(
          tooltip: t('Ещё действия'),
          color: pal.panel,
          shape: _menuShape(pal),
          elevation: 12,
          shadowColor: const Color(0x38000000),
          menuPadding: const EdgeInsets.all(6),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 260),
          position: PopupMenuPosition.under,
          onSelected: (f) {
            f();
            doneLater();
          },
          itemBuilder: (_) {
            // .menu-item: значок цвета акцента, подпись 15,7 px — MenuRow из kit
            PopupMenuItem<VoidCallback> item(IconData i, String text, VoidCallback f) => PopupMenuItem(value: f, padding: EdgeInsets.zero, height: 40, child: MenuRow(icon: i, label: text, onTap: null));
            return [
              if (Hub.openInterlinear != null) item(LucideIcons.wholeWord, t('Подстрочник'), () => Hub.openInterlinear!(c, r, first, moduleId)),
              if (Hub.openVerseGuide != null) item(LucideIcons.compass, t('Всё о стихе'), () => Hub.openVerseGuide!(c, r, pane, first, moduleId)),
              if (Hub.addToSermon != null) item(LucideIcons.scrollText, t('В проповедь'), () => Hub.addToSermon!(c, r, refs, moduleId)),
              item(LucideIcons.folderPlus, t('В подборку…'), () => showCollectSheet(c, refs, moduleId)),
              item(LucideIcons.heart, fav ? t('Убрать из любимых') : t('В любимые'), toggleFav),
              if (Hub.compareTranslations != null) item(LucideIcons.bookCopy, t('Сравнить переводы'), () => Hub.compareTranslations!(c, r, refs, moduleId)),
              if (refs.length == 1 && Hub.openXrefs != null) item(LucideIcons.link2, t('Параллельные места'), () => Hub.openXrefs!(c, r, pane, first)),
              if (Hub.listenFrom != null) item(LucideIcons.headphones, t('Слушать отсюда'), () => Hub.listenFrom!(c, r, pane, first)),
              item(LucideIcons.copy, t('Копировать'), copy),
              if (Hub.openVerseImage != null) item(LucideIcons.image, t('Картинка со стихом'), () => Hub.openVerseImage!(c, r, refs, moduleId)),
              item(LucideIcons.share2, t('Поделиться'), share),
            ];
          },
          child: tb((c) => Icon(LucideIcons.ellipsis, size: 22, color: c), t('Ещё действия'), null),
        ),
      ]),
    );
  }
}

/// .menu / .hl-palette: панель, рамка line, скругление, мягкая тень
ShapeBorder _menuShape(Palette pal) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: pal.line));

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Ряд цветных точек (.hl-palette): круги 32 px с рамкой 2, у выбранного — цвета текста; последний — «убрать» (ластик, пунктир)
class _PaletteEntry extends PopupMenuEntry<String> {
  const _PaletteEntry(this.labels, this.current, this.pal);
  final Map<String, String> labels;
  final String? current;
  final Palette pal;
  @override
  double get height => 52;
  @override
  bool represents(String? value) => false;
  @override
  State<_PaletteEntry> createState() => _PaletteEntryState();
}

class _PaletteEntryState extends State<_PaletteEntry> {
  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    String label(HlColor c) => widget.labels[c.id]?.trim().isNotEmpty == true ? widget.labels[c.id]!.trim() : t(c.name);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in hlColors)
          Tooltip(
            message: label(c),
            child: GestureDetector(
              onTap: () => Navigator.pop(context, c.id),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: c.color, shape: BoxShape.circle, border: Border.all(color: widget.current == c.id ? pal.text : Colors.transparent, width: 2)),
              ),
            ),
          ),
        Tooltip(
          message: t('Убрать выделение'),
          child: GestureDetector(
            onTap: () => Navigator.pop(context, ''),
            child: CustomPaint(
              painter: _DashedCircle(pal.muted),
              child: SizedBox(width: 32, height: 32, child: Icon(LucideIcons.eraser, size: 15, color: pal.muted)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// border: 1px dashed — пунктирный круг
class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = size.width / 2 - 0.5;
    const n = 24;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), i * 2 * 3.141592653589793 / n, 2 * 3.141592653589793 / n * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle o) => o.color != color;
}

/// «Читать параллельно»: один другой перевод — открываем вторую панель сразу;
/// несколько — выбор (или окно сравнения переводов из Hub, если оно есть)
void _parallel(BuildContext c, WidgetRef r, int pane, List<VerseRef> refs, String moduleId) {
  final others = [for (final m in ModuleStore.instance.bibles) if (m.id != moduleId && !_originals.contains(m.id)) m];
  void open(String id) {
    final n = r.read(panesProvider.notifier);
    if (r.read(panesProvider).length < 2) {
      n.toggleSplit(moduleId: id);
    } else {
      n.setModule(1, id);
    }
    n.navigate(1, refs.first);
  }

  if (others.length == 1) return open(others.first.id);
  if (Hub.compareTranslations != null) return Hub.compareTranslations!(c, r, refs, moduleId);
  showSheet<void>(
    c,
    title: t('Читать параллельно'),
    subtitle: selectionLabel(refs, full: true),
    body: (ctx) => Column(children: [
      for (final (i, m) in others.indexed)
        PrefRow(
          icon: LucideIcons.languages,
          title: m.name,
          sub: m.title,
          last: i == others.length - 1,
          onTap: () {
            Navigator.pop(ctx);
            open(m.id);
          },
        ),
    ]),
  );
}
