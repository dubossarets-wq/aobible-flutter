// Отметки у стихов (ChapterView.jsx, классы vmark): фон цвета выделения, закладка, сердце любимого
// (у «любимой части» — полупрозрачное), значок подборки и жёлтый значок заметки.
// Вызывается для каждого видимого стиха, поэтому берёт готовые флаги из Marks.flags (O(1)).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'marks.dart';
import 'sheets.dart';

VerseDecor? verseDecor(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book) {
  if (item.kind != ItemKind.verse) return null;
  final fl = ref.read(marksProvider).flags['$book.${item.chapter}.${item.verse}'];
  if (fl == null || fl.isEmpty) return null;
  final s = ref.read(settingsProvider);
  final pal = s.palette;
  final fs = s.d('fontSize');
  final hl = hlColor(RegExp(r'[1-6]').firstMatch(fl)?.group(0));

  // Фон: цвет выделения (45 % и 42 % прозрачности — как в веб-версии), иначе лёгкий розовый у любимого стиха
  final Color? bg = hl != null
      ? hl.color.withValues(alpha: hl.id == '1' || hl.id == '6' ? 0.45 : 0.42)
      : fl.contains('f')
          ? loveColor.withValues(alpha: 0.09)
          : null;

  InlineSpan mark(Widget w) => WidgetSpan(alignment: PlaceholderAlignment.middle, child: w);
  // Закладка, сердце, подборка — между номером стиха и текстом (как в веб-версии), заметка — после текста
  final afterNumber = <InlineSpan>[];
  final trailing = <InlineSpan>[];
  if (fl.contains('b')) {
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(label: t('Закладка'), child: Icon(Icons.bookmark, size: fs * 0.8, color: pal.accent)),
    )));
  }
  if (fl.contains('f') || fl.contains('p')) {
    final part = fl.contains('p');
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(label: part ? t('Любимая часть стиха') : t('Любимый стих'), child: Icon(Icons.favorite, size: fs * 0.7, color: loveColor.withValues(alpha: part ? 0.75 : 1))),
    )));
  }
  if (fl.contains('c')) {
    afterNumber.add(mark(Padding(
      padding: EdgeInsets.only(right: fs * 0.25),
      child: Semantics(label: t('Стих в подборке'), child: Icon(Icons.folder, size: fs * 0.7, color: pal.accent)),
    )));
  }
  if (fl.contains('n')) {
    final r = VerseRef(book, item.chapter, item.verse);
    trailing.add(mark(Padding(
      padding: EdgeInsets.only(left: fs * 0.3),
      child: GestureDetector(
        onTap: () => showNoteSheet(context, [r], moduleId),
        child: Tooltip(
          message: t('Заметка'),
          child: Container(
            width: fs * 1.25,
            height: fs * 1.05,
            decoration: BoxDecoration(color: const Color(0xfff3e27a), borderRadius: BorderRadius.circular(4)),
            child: Icon(Icons.edit, size: fs * 0.62, color: const Color(0xff6b5a10)),
          ),
        ),
      ),
    )));
  }
  return VerseDecor(background: bg, afterNumber: afterNumber, trailing: trailing);
}
