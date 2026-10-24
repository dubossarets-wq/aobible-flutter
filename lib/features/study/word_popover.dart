// Всплывающая выборка над словом (WordPopover.jsx): «H7887 · Стронг: иврит», «H7887 · Симфония RST+» …
// плюс пункты других функций (Hub.wordMenuItems — например «Карта»). Выбор пункта открывает статью.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../hub.dart';
import 'dictionary_sheet.dart';
import 'interlinear.dart';
import 'lexicon.dart';
import 'study_data.dart';

const _gap = 10.0;
const _bg = Color(0xFF3B3A3D);
const _fg = Color(0xFFF3F1EC);

/// Hub.onWordTap: нажатие на слово
Future<void> onWordTap(BuildContext context, WidgetRef ref, WordTap tap) async {
  await StudyData.ensure(); // обычно мгновенно: таблицы уже есть
  if (!context.mounted) return;
  final res = lookupWord(
    text: tap.token.text,
    strongs: tap.token.strongs,
    morph: tap.token.morph,
    book: tap.ref.book,
    chapter: tap.ref.chapter,
    verse: tap.ref.verse,
  );
  final hubItems = <WordMenuItem>[for (final f in Hub.wordMenuItems) ...f(context, ref, tap)];
  // Стабильная сортировка по order: пункты других функций с order < 100 — перед словарями, остальные — после
  final order = {for (final (i, x) in hubItems.indexed) x: i};
  hubItems.sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : order[a]!.compareTo(order[b]!));
  final anchor = tap.rect;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true, // касание вне выборки только закрывает её
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (dctx, a, s) => _Popover(
      anchor: anchor,
      res: res,
      before: [for (final x in hubItems) if (x.order < 100) x],
      after: [for (final x in hubItems) if (x.order >= 100) x],
      onChoose: (m, key) {
        Navigator.pop(dctx);
        final req = DictRequest(
          text: tap.token.text,
          strongs: tap.token.strongs,
          morph: tap.token.morph,
          ref: tap.ref,
          pane: tap.pane,
          preselect: (moduleId: m.id, key: key),
          wordIndex: _wordIndex(tap),
        );
        // Статья по номеру Стронга — на всю высоту, остальные словари — на половину экрана
        openDictionary(context, req, full: StudyData.dictKind(m) == 'strongs');
      },
      onItem: (x) {
        Navigator.pop(dctx);
        x.onTap();
      },
      onLibrary: Hub.openLibrary == null
          ? null
          : () {
              Navigator.pop(dctx);
              Hub.openLibrary!(context, ref, tap.pane);
            },
    ),
  );
}

/// Номер слова в стихе RST+ (как их считает подстрочник) — по нему находится слово оригинала и его форма
int? _wordIndex(WordTap tap) {
  if (!tap.token.tagged || tap.moduleId != interlinearRuModule()) return null;
  final toks = parseVerse(tap.verseText);
  if (tap.tokenIndex >= toks.length) return null;
  final words = RegExp(r"[\p{L}\p{M}]+(?:[-’'][\p{L}\p{M}]+)*", unicode: true);
  var n = 0;
  for (var i = 0; i < tap.tokenIndex; i++) {
    n += toks[i].tagged ? 1 : words.allMatches(toks[i].text).length;
  }
  return n;
}

class _Arrow {
  const _Arrow(this.x, this.below);
  final double x;
  final bool below;
}

class _Layout extends SingleChildLayoutDelegate {
  _Layout(this.anchor, this.arrow);
  final Rect anchor;
  final ValueNotifier<_Arrow> arrow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(minWidth: 210, maxWidth: math.min(340, c.maxWidth - 16), maxHeight: c.maxHeight - 16);

  @override
  Offset getPositionForChild(Size size, Size child) {
    // Под словом, а если внизу мало места — над ним; по горизонтали — в пределах экрана
    final below = anchor.bottom + _gap + child.height < size.height - 8 || anchor.top - _gap - child.height < 8;
    final left = math.max(8.0, math.min(size.width - child.width - 8, anchor.left + anchor.width / 2 - child.width / 2));
    final x = math.max(16.0, math.min(child.width - 16, anchor.left + anchor.width / 2 - left));
    arrow.value = _Arrow(x, below);
    return Offset(left, below ? anchor.bottom + _gap : anchor.top - _gap - child.height);
  }

  @override
  bool shouldRelayout(_Layout old) => old.anchor != anchor;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrow) : super(repaint: arrow);
  final ValueNotifier<_Arrow> arrow;
  @override
  void paint(Canvas canvas, Size size) {
    final a = arrow.value;
    canvas.save();
    canvas.translate(a.x, a.below ? -6 + 9 : size.height + 6 - 9);
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -9, 18, 18), const Radius.circular(3)), Paint()..color = _bg);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}

class _Popover extends StatefulWidget {
  const _Popover({required this.anchor, required this.res, required this.before, required this.after, required this.onChoose, required this.onItem, required this.onLibrary});
  final Rect anchor;
  final LookupResult res;
  final List<WordMenuItem> before;
  final List<WordMenuItem> after;
  final void Function(InstalledModule module, String key) onChoose;
  final void Function(WordMenuItem) onItem;
  final VoidCallback? onLibrary;
  @override
  State<_Popover> createState() => _PopoverState();
}

class _PopoverState extends State<_Popover> {
  final _arrow = ValueNotifier(const _Arrow(30, true));

  @override
  void dispose() {
    _arrow.dispose();
    super.dispose();
  }

  Widget _row(Widget child, VoidCallback? onTap, {bool first = false}) => InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: Color(0x1AFFFFFF)))),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final res = widget.res;
    final items = [
      for (final r in res.results)
        for (final f in r.found) (module: r.module, key: f.key, label: f.label),
    ];
    final rows = <Widget>[];
    var firstRow = true;
    void add(Widget w, VoidCallback? tap) {
      rows.add(_row(w, tap, first: firstRow));
      firstRow = false;
    }

    const base = TextStyle(fontSize: 16.3, color: _fg);
    Widget two(String a, String b, {FontWeight? w}) => Row(children: [
          Text(a, style: base.copyWith(fontWeight: w, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          Text('·', style: base.copyWith(color: _fg.withValues(alpha: 0.5))),
          const SizedBox(width: 8),
          Flexible(child: Text(b, maxLines: 1, overflow: TextOverflow.clip, style: base)),
        ]);

    for (final x in widget.before) {
      add(two(x.label, x.sub ?? '', w: FontWeight.w600), () => widget.onItem(x));
    }
    for (final it in items) {
      final isNum = it.key.startsWith('H') || it.key.startsWith('G');
      add(two(isNum ? it.key : (it.label.isEmpty ? it.key : it.label), it.module.name), () => widget.onChoose(it.module, it.key));
    }
    for (final x in widget.after) {
      add(two(x.label, x.sub ?? ''), () => widget.onItem(x));
    }
    if (items.isEmpty && widget.before.isEmpty && widget.after.isEmpty) {
      add(Text(t('Статей для «{word}» нет', {'word': res.word}), style: base.copyWith(fontSize: 14.7, color: _fg.withValues(alpha: 0.7))), null);
      if (widget.onLibrary != null) add(Text(t('Словари в библиотеке'), style: base), widget.onLibrary);
    }

    return CustomSingleChildLayout(
      delegate: _Layout(widget.anchor, _arrow),
      child: CustomPaint(
        painter: _ArrowPainter(_arrow),
        child: Material(
          color: _bg,
          elevation: 12,
          shadowColor: Colors.black87,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (res.mapping.mode == 'approx')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
                    child: Text(t('≈ приблизительно: перевод без номеров Стронга'), style: TextStyle(fontSize: 12.5, color: _fg.withValues(alpha: 0.7))),
                  ),
                ...rows,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
