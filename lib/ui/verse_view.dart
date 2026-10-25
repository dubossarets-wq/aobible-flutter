// Строка ленты: заголовок главы, заголовок раздела или стих (размеры — как в веб-версии: 19 px, интервал 1.45,
// номер стиха 0,6 em над строкой, заголовок главы 2,1 em, раздела 0,8 em).
// Стих: нажатие на слово → Hub.onWordTap (словарь), долгое нажатие или нажатие на номер — выделение,
// отметки (закладки, цвета, заметки, пометки толкований…) — от функций через Hub.verseDecorators.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/markup.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import '../features/shell/colors.dart' show headingColor, strongColor;
import '../features/shell/fonts.dart' show readerTextStyle, textAlignOf;

class VerseView extends ConsumerWidget {
  const VerseView({super.key, required this.item, required this.book, required this.settings, required this.pane, required this.moduleId});
  final ReaderItem item;
  final String book;
  final Settings settings;
  final int pane;
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = settings.palette;
    final fs = settings.d('fontSize');
    switch (item.kind) {
      case ItemKind.chapter:
        // .book-title: 0,9 em, серый; .chapter-title: 2,1 em, 800, межстрочный 1,1, отступы .55em/.3em
        final cs = fs * settings.d('chapterTitleSize');
        final title = Padding(
          padding: EdgeInsets.only(top: cs * 0.55, bottom: cs * 0.3),
          child: Text(book == 'Ps' ? t('Псалом {n}', {'n': '${item.chapter}'}) : t('Глава {n}', {'n': '${item.chapter}'}),
              style: readerTextStyle(settings, size: cs, weight: 800).copyWith(color: pal.text, height: 1.1, letterSpacing: -cs * 0.01)),
        );
        if (item.chapter != 1) return title;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: fs * 0.9 * 1.4),
            child: Text(Books.instance.meta(book).name, style: readerTextStyle(settings, size: fs * 0.9, weight: 600).copyWith(color: pal.muted)),
          ),
          title,
        ]);
      case ItemKind.heading:
        if (!settings.get<bool>('showHeadings')) return const SizedBox.shrink();
        // .section-title: 0,8 em, 650, цвет акцента (или свой), отступы 1.1em / .35em
        final hs = fs * settings.d('headingSize');
        return Padding(
          padding: EdgeInsets.only(top: hs * 1.1, bottom: hs * 0.35),
          child: Text(item.text, style: readerTextStyle(settings, size: hs, weight: 650).copyWith(color: headingColor(settings), height: 1.3, letterSpacing: hs * 0.01)),
        );
      case ItemKind.verse:
        return _Verse(view: this);
    }
  }
}

class _Verse extends ConsumerStatefulWidget {
  const _Verse({required this.view});
  final VerseView view;
  @override
  ConsumerState<_Verse> createState() => _VerseState();
}

class _VerseState extends ConsumerState<_Verse> {
  final _key = GlobalKey();
  // Где в тексте абзаца начинается каждое слово-фрагмент: [начало, конец, номер фрагмента]
  final List<(int, int, int)> _ranges = [];
  int _numberEnd = 0;

  VerseView get v => widget.view;
  VerseRef get _ref => VerseRef(v.book, v.item.chapter, v.item.verse);

  @override
  Widget build(BuildContext context) {
    ref.watch(decorVersionProvider);
    final selected = ref.watch(selectionProvider.select((m) => m[v.pane]?.contains(_ref) ?? false));
    final s = v.settings;
    final pal = s.palette;
    final fs = s.d('fontSize');
    final decors = [for (final d in Hub.verseDecorators) d(context, ref, v.pane, v.moduleId, v.item, v.book)].whereType<VerseDecor>().toList();
    final bg = selected ? pal.line : decors.map((d) => d.background).whereType<Color>().firstOrNull;
    final below = decors.map((d) => d.below).whereType<Widget>().toList();
    final verse = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _tap,
      onLongPress: () => ref.read(selectionProvider.notifier).toggle(v.pane, _ref),
      child: Container(
        margin: EdgeInsets.only(bottom: fs * s.d('verseSpacing')),
        decoration: BoxDecoration(
          color: bg,
          border: selected ? Border(left: BorderSide(color: pal.accent, width: 3)) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: bg != null ? const EdgeInsets.symmetric(horizontal: 4) : EdgeInsets.zero,
        child: Text.rich(key: _key, _spans(pal, fs, decors), textAlign: textAlignOf(s), style: readerTextStyle(s).copyWith(color: pal.text, height: s.d('lineHeight'))),
      ),
    );
    if (below.isEmpty) return verse;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      verse,
      for (final w in below) Padding(padding: EdgeInsets.only(bottom: fs * s.d('verseSpacing')), child: w),
    ]);
  }

  int _len(InlineSpan span) => span is TextSpan ? (span.text?.length ?? 0) + (span.children?.fold<int>(0, (a, c) => a + _len(c)) ?? 0) : 1;

  TextSpan _spans(Palette pal, double fs, List<VerseDecor> decors) {
    final s = v.settings;
    final children = <InlineSpan>[];
    var at = 0;
    void add(InlineSpan span) {
      children.add(span);
      at += _len(span);
    }

    for (final d in decors) {
      d.leading.forEach(add);
    }
    if (s.get<bool>('showVerseNumbers')) {
      add(WidgetSpan(
        alignment: s.get<String>('verseNumPos') == 'inline' ? PlaceholderAlignment.middle : PlaceholderAlignment.top,
        child: Padding(
          padding: EdgeInsets.only(right: fs * 0.2),
          child: Text('${v.item.verse}', style: TextStyle(fontSize: fs * s.d('verseNumSize'), color: pal.verseNum, height: 1)),
        ),
      ));
    }
    for (final d in decors) {
      d.afterNumber.forEach(add);
    }
    _numberEnd = at;
    _ranges.clear();
    final strongs = s.get<bool>('showStrongs');
    final tokens = v.item.tokens;
    for (var i = 0; i < tokens.length; i++) {
      final tk = tokens[i];
      final start = at;
      add(TextSpan(text: tk.text, style: tk.italic ? const TextStyle(fontStyle: FontStyle.italic) : null));
      _ranges.add((start, at, i));
      if (strongs && tk.tagged) add(_strong(tk.strongs.join(' '), fs));
    }
    for (final d in decors) {
      d.trailing.forEach(add);
    }
    return TextSpan(children: children);
  }

  // Номера Стронга: размер, цвет и положение (над строкой / в строке / под строкой) — по настройкам
  InlineSpan _strong(String nums, double fs) {
    final s = v.settings;
    final style = TextStyle(fontSize: fs * s.d('strongSize'), color: strongColor(s), height: 1);
    final pos = s.get<String>('strongPos');
    if (pos == 'inline') return TextSpan(text: ' $nums', style: style);
    return WidgetSpan(
      alignment: pos == 'sub' ? PlaceholderAlignment.bottom : PlaceholderAlignment.top,
      child: Padding(padding: EdgeInsets.only(left: fs * 0.12), child: Text(nums, style: style)),
    );
  }

  static final _word = RegExp(r'[\p{L}\p{N}\-]+', unicode: true);

  void _tap(TapUpDetails d) {
    final ro = _key.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return;
    final local = ro.globalToLocal(d.globalPosition);
    final pos = ro.getPositionForOffset(local).offset;
    if (pos <= _numberEnd && v.settings.get<bool>('showVerseNumbers')) {
      ref.read(selectionProvider.notifier).toggle(v.pane, _ref); // номер стиха — выделить стих
      return;
    }
    // Уже есть выделение — нажатие на стих добавляет или снимает его
    if (ref.read(selectionProvider)[v.pane]?.isNotEmpty ?? false) {
      ref.read(selectionProvider.notifier).toggle(v.pane, _ref);
      return;
    }
    for (final (start, end, i) in _ranges) {
      if (pos < start || pos >= end) continue;
      final tk = v.item.tokens[i];
      var token = tk;
      var from = start, to = end;
      if (!tk.tagged) {
        // Неразмеченный фрагмент — берём слово под пальцем
        final m = _word.allMatches(tk.text).where((m) => start + m.start <= pos && pos < start + m.end).firstOrNull;
        if (m == null) return;
        token = Token(m.group(0)!, italic: tk.italic);
        from = start + m.start;
        to = start + m.end;
      }
      final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to));
      final box = boxes.isNotEmpty ? boxes.first.toRect() : Rect.fromLTWH(local.dx, local.dy, 1, 1);
      final topLeft = ro.localToGlobal(box.topLeft);
      Hub.onWordTap?.call(context, ref, WordTap(pane: v.pane, moduleId: v.moduleId, ref: _ref, token: token, tokenIndex: i, rect: topLeft & box.size, verseText: v.item.text));
      return;
    }
  }
}
