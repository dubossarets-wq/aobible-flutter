// Панель действий над выделенными стихами (SelectionBar.jsx): вместо шапки панели, пока есть выделение.
// ✓ · ссылка и число стихов · параллельно · цвет · любимые · заметка · закладка · ⋯ (подстрочник, в проповедь,
// в подборку, сравнить переводы, слушать, копировать, поделиться).
// hostContext/hostRef — от панели чтения: сама строка исчезает, как только выделение снято, а окна и
// функции из Hub должны жить дольше неё.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
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
    final pal = ref.watch(settingsProvider).palette;
    final sel = ref.watch(selectionProvider.select((m) => m[pane] ?? const <VerseRef>{}));
    final marks = ref.watch(marksProvider);
    final moduleId = ref.watch(panesProvider.select((l) => pane < l.length ? l[pane].moduleId : 'rst-plus'));
    if (sel.isEmpty) return const SizedBox(height: 54);
    final refs = sortedRefs(sel);
    final first = refs.first;
    final narrow = MediaQuery.sizeOf(context).width < 430;
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

    Widget icon(IconData i, String tip, VoidCallback f, {bool on = false}) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(color: on ? pal.barText.withValues(alpha: 0.2) : null, shape: BoxShape.circle),
          child: IconButton(tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(i, color: pal.barText, size: 22), onPressed: f),
        );

    return Container(
      height: 54,
      color: pal.bar,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        icon(Icons.close, t('Готово, снять выделение'), done),
        Expanded(
          child: Row(children: [
            Flexible(child: Text(selectionLabel(refs), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.barText, fontWeight: FontWeight.w800, fontSize: 16))),
            const SizedBox(width: 6),
            Semantics(
              label: t('Выделено стихов: {n}', {'n': '${refs.length}'}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: pal.barText.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                child: Text('${refs.length}', style: TextStyle(color: pal.barText, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        icon(Icons.translate, t('Читать параллельно'), () {
          _parallel(c, r, pane, refs, moduleId);
          done();
        }),
        PopupMenuButton<String>(
          tooltip: t('Выделить цветом'),
          color: pal.panel,
          position: PopupMenuPosition.under,
          onSelected: (id) {
            r.read(marksProvider.notifier).setHighlight(refs, id.isEmpty ? null : id);
            done();
          },
          itemBuilder: (_) => [_PaletteEntry(marks.hlLabels, marks.highlights[refKey(first)], pal)],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: hl ? pal.barText.withValues(alpha: 0.2) : null, shape: BoxShape.circle),
            child: Icon(Icons.border_color_outlined, color: pal.barText, size: 21),
          ),
        ),
        if (!narrow) icon(fav ? Icons.favorite : Icons.favorite_border, fav ? t('Убрать из любимых') : t('В любимые'), toggleFav, on: fav),
        icon(Icons.edit_note, hasNote ? t('Открыть заметку') : t('Добавить заметку'), () {
          showNoteSheet(c, refs, moduleId);
          done();
        }, on: hasNote),
        icon(bm ? Icons.bookmark : Icons.bookmark_border, bm ? t('Убрать закладку') : t('Закладка: продолжить отсюда'), toggleBm, on: bm),
        PopupMenuButton<VoidCallback>(
          tooltip: t('Ещё действия'),
          color: pal.panel,
          icon: Icon(Icons.more_horiz, color: pal.barText),
          onSelected: (f) {
            f();
            doneLater();
          },
          itemBuilder: (_) {
            PopupMenuItem<VoidCallback> item(IconData i, String text, VoidCallback f) => PopupMenuItem(
                  value: f,
                  child: Row(children: [Icon(i, size: 20, color: pal.text), const SizedBox(width: 12), Flexible(child: Text(text, style: TextStyle(color: pal.text)))]),
                );
            return [
              if (Hub.openInterlinear != null) item(Icons.translate_outlined, t('Подстрочник'), () => Hub.openInterlinear!(c, r, first, moduleId)),
              if (Hub.addToSermon != null) item(Icons.record_voice_over_outlined, t('В проповедь'), () => Hub.addToSermon!(c, r, refs, moduleId)),
              item(Icons.create_new_folder_outlined, t('В подборку…'), () => showCollectSheet(c, refs, moduleId)),
              if (narrow) item(fav ? Icons.favorite : Icons.favorite_border, fav ? t('Убрать из любимых') : t('В любимые'), toggleFav),
              if (Hub.compareTranslations != null) item(Icons.library_books_outlined, t('Сравнить переводы'), () => Hub.compareTranslations!(c, r, refs, moduleId)),
              if (Hub.listenFrom != null) item(Icons.headphones_outlined, t('Слушать отсюда'), () => Hub.listenFrom!(c, r, pane, first)),
              item(Icons.copy_outlined, t('Копировать'), copy),
              item(Icons.share_outlined, t('Поделиться'), share),
            ];
          },
        ),
      ]),
    );
  }
}

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Ряд цветных точек в меню + «убрать выделение»
class _PaletteEntry extends PopupMenuEntry<String> {
  const _PaletteEntry(this.labels, this.current, this.pal);
  final Map<String, String> labels;
  final String? current;
  final Palette pal;
  @override
  double get height => 56;
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
    return SizedBox(
      height: 56,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 12),
        for (final c in hlColors)
          Tooltip(
            message: label(c),
            child: GestureDetector(
              onTap: () => Navigator.pop(context, c.id),
              child: Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: c.color, shape: BoxShape.circle, border: Border.all(color: widget.current == c.id ? pal.text : Colors.transparent, width: 2.5)),
              ),
            ),
          ),
        Tooltip(
          message: t('Убрать выделение'),
          child: GestureDetector(
            onTap: () => Navigator.pop(context, ''),
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.muted)),
              child: Icon(Icons.cleaning_services_outlined, size: 16, color: pal.muted),
            ),
          ),
        ),
      ]),
    );
  }
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
  final pal = r.read(settingsProvider).palette;
  showSheet<void>(
    c,
    pal,
    title: t('Читать параллельно'),
    subtitle: selectionLabel(refs, full: true),
    body: (ctx) => Column(children: [
      for (final m in others)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(m.name, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
          subtitle: Text(m.title, style: TextStyle(color: pal.muted)),
          onTap: () {
            Navigator.pop(ctx);
            open(m.id);
          },
        ),
    ]),
  );
}
