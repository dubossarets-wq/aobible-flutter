// Строка ленты: заголовок главы, заголовок раздела или стих (размеры — как в веб-версии: 19 px, интервал 1.45,
// номер стиха 0,6 em над строкой, заголовок главы 2,1 em, раздела 0,8 em).
import 'package:flutter/material.dart';

import '../core/bible.dart';
import '../core/i18n.dart';
import '../core/settings.dart';

class VerseView extends StatelessWidget {
  const VerseView({super.key, required this.item, required this.book, required this.settings});
  final ReaderItem item;
  final String book;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final pal = settings.palette;
    final fs = settings.d('fontSize');
    switch (item.kind) {
      case ItemKind.chapter:
        return Padding(
          padding: EdgeInsets.only(top: fs * 1.2, bottom: fs * 0.5),
          child: Text(t('Глава {n}', {'n': '${item.chapter}'}), style: TextStyle(fontSize: fs * settings.d('chapterTitleSize'), fontWeight: FontWeight.w800, color: pal.text, height: 1.15)),
        );
      case ItemKind.heading:
        if (!settings.get<bool>('showHeadings')) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: fs * 0.5, bottom: fs * 0.4),
          child: Text(item.text, style: TextStyle(fontSize: fs * settings.d('headingSize'), fontWeight: FontWeight.w700, color: pal.text, height: 1.3)),
        );
      case ItemKind.verse:
        return Padding(
          padding: EdgeInsets.only(bottom: fs * settings.d('verseSpacing')),
          child: Text.rich(_spans(pal, fs), style: TextStyle(fontSize: fs, height: settings.d('lineHeight'), color: pal.text)),
        );
    }
  }

  TextSpan _spans(Palette pal, double fs) {
    final children = <InlineSpan>[];
    if (settings.get<bool>('showVerseNumbers')) {
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Padding(
          padding: EdgeInsets.only(right: fs * 0.2),
          child: Text('${item.verse}', style: TextStyle(fontSize: fs * settings.d('verseNumSize'), color: pal.verseNum, height: 1)),
        ),
      ));
    }
    final strongs = settings.get<bool>('showStrongs');
    for (final tk in item.tokens) {
      children.add(TextSpan(text: tk.text, style: tk.italic ? const TextStyle(fontStyle: FontStyle.italic) : null));
      if (strongs && tk.tagged) {
        children.add(TextSpan(text: ' ${tk.strongs.join(' ')}', style: TextStyle(fontSize: fs * 0.5, color: pal.accent)));
      }
    }
    return TextSpan(children: children);
  }
}
