// Отметки у стихов (ChapterView.jsx, классы vmark): фон цвета выделения, закладка, сердце любимого
// (у «любимой части» — полупрозрачное), значок подборки и жёлтый значок заметки.
// Вызывается для каждого видимого стиха, поэтому берёт готовые флаги из Marks.flags (O(1)).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'gestures.dart' show favPulse;
import 'marks.dart';
import 'sel_inline.dart';
import 'sheets.dart';
import 'ui.dart';
import '../../ui/ios_style.dart';

VerseDecor? verseDecor(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book) {
  if (item.kind != ItemKind.verse) return null;
  // Строка действий — под последним выделенным стихом (SelectionInline в BibleReader.jsx)
  Widget? below;
  // следим за тем, какой стих выделен последним и сколько их: сняли выделение с соседнего — строка под оставшимся
  // стихом перестраивается (при одном стихе появляется «Часть стиха»)
  ref.watch(selectionProvider.select((m) {
    final v = m[pane];
    if (v == null || v.isEmpty) return (null, 0);
    return (refKey(sortedRefs(v).last), v.length);
  }));
  final sel = ref.read(selectionProvider)[pane];
  if (sel != null && sel.isNotEmpty) {
    final refs = sortedRefs(sel);
    final me = VerseRef(book, item.chapter, item.verse);
    if (refKey(refs.last) == refKey(me)) {
      below = buildSelectionInline(context, ref,
          pane: pane,
          moduleId: moduleId,
          refs: refs,
          onDone: () => ref.read(selectionProvider.notifier).clear(pane),
          // «Часть стиха»: выбор слов ведёт читалка (partSelection), выделение стиха снимаем
          onPart: () {
            partSelection.value = PartSelection(pane, refs.first, moduleId);
            ref.read(selectionProvider.notifier).clear(pane);
          });
    }
  }
  final marks = ref.read(marksProvider);
  final key = '$book.${item.chapter}.${item.verse}';
  final fl = marks.flags[key];
  // Вспышка у стиха, ставшего любимым (.fav-pulse)
  final pulse = favPulse[key];
  final part = marks.favParts[key];
  final parts = part == null ? const <(int, int)>[] : [part];
  if (fl == null || fl.isEmpty) {
    return below == null && pulse == null ? null : VerseDecor(below: below, background: pulse == null ? null : loveColor.withValues(alpha: pulse));
  }
  final s = ref.read(settingsProvider);
  final pal = s.palette;
  final fs = s.d('fontSize');
  final hl = hlColor(RegExp(r'[1-6]').firstMatch(fl)?.group(0));

  // Фон: цвет выделения (45 % и 42 % прозрачности — как в веб-версии), иначе лёгкий розовый у любимого стиха
  Color? bg = hl != null
      // в тёмных темах жёлтый — 36 %: на 45 % светлый текст терял контраст (ниже 4.5 по WCAG)
      ? hl.color.withValues(alpha: hl.id == '1' ? (pal.dark ? 0.36 : 0.45) : hl.id == '6' ? 0.45 : 0.42)
      : fl.contains('f')
          ? loveColor.withValues(alpha: 0.09)
          : null;

  if (pulse != null) bg = bg == null ? loveColor.withValues(alpha: pulse) : Color.alphaBlend(loveColor.withValues(alpha: pulse), bg);

  InlineSpan mark(Widget w) => WidgetSpan(alignment: PlaceholderAlignment.middle, child: w);
  // Закладка, сердце, подборка — между номером стиха и текстом (как в веб-версии), заметка — после текста
  final afterNumber = <InlineSpan>[];
  final trailing = <InlineSpan>[];
  if (fl.contains('b')) {
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(
        label: t('Закладка'),
        // .vmark.bm: ленточка 0.42em × 0.62em с вырезом внизу
        child: ClipPath(clipper: const _RibbonClip(), child: Container(width: fs * 0.42, height: fs * 0.62, color: pal.accent)),
      ),
    )));
  }
  if (fl.contains('f') || fl.contains('p')) {
    final part = fl.contains('p');
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(label: part ? t('Любимая часть стиха') : t('Любимый стих'), child: FillIcon(path: verseHeartPath, size: fs * 0.62, color: loveColor.withValues(alpha: part ? 0.75 : 1))),
    )));
  }
  if (fl.contains('c')) {
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(label: t('Стих в подборке'), child: FillIcon(path: verseFolderPath, size: fs * 0.6, color: pal.accent)),
    )));
  }
  if (fl.contains('n')) {
    final r = VerseRef(book, item.chapter, item.verse);
    trailing.add(mark(Padding(
      padding: EdgeInsets.only(left: fs * 0.3),
      child: GestureDetector(
        onTap: () => showNoteSheet(context, [r], moduleId, pane: pane),
        child: Tooltip(
          message: t('Заметка'),
          child: Container(
            width: fs * 1.25,
            height: fs * 1.05,
            decoration: BoxDecoration(color: const Color(0xfff3e27a), borderRadius: BorderRadius.circular(4)),
            child: Icon(ico(LucideIcons.penLine), size: fs * 0.62, color: const Color(0xff6b5a10)),
          ),
        ),
      ),
    )));
  }
  return VerseDecor(background: bg, afterNumber: afterNumber, trailing: trailing, below: below, parts: parts);
}

/// Ленточка закладки: clip-path polygon(0 0, 100% 0, 100% 100%, 50% 74%, 0 100%)
class _RibbonClip extends CustomClipper<Path> {
  const _RibbonClip();
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width * 0.5, s.height * 0.74)
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(_RibbonClip old) => false;
}
