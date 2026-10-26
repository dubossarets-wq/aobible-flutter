// Всплывающая выборка над словом (WordPopover.jsx): «H7887 · Стронг: иврит», «H7887 · Симфония RST+» …
// плюс пункты других функций (Hub.wordMenuItems — например «Карта»). Выбор пункта открывает статью.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import '../shell/tour_targets.dart' show tourKey;
import 'dictionary_sheet.dart';
import 'interlinear.dart';
import 'lexicon.dart';
import 'study_data.dart';

const _gap = 10.0; // GAP из WordPopover.jsx

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

  // Слово подсвечено (.w.active), пока открыта выборка и статья, открытая из неё. Касание слова при открытой
  // выборке попадает на подложку и только закрывает её (markClosedOnWord) — выборка заново не открывается.
  // номер слова подсветки ставит читалка при нажатии (номер слова в стихе, а не tokenIndex) — здесь только снимаем
  final mine = activeWord.value;
  Future<void>? following; // статья, открытая выбором пункта
  try {
    await _showPopover(context, ref, tap, res, hubItems, anchor, (f) => following = f);
    if (following != null) await following;
  } finally {
    if (mine != null && activeWord.value == mine) activeWord.value = null;
  }
}

Future<void> _showPopover(BuildContext context, WidgetRef ref, WordTap tap, LookupResult res, List<WordMenuItem> hubItems, Rect anchor, void Function(Future<void>) follow) async {
  // снизу экран закрывают вкладки и проигрыватель (у читалки это MediaQuery.padding.bottom) — туда выборку не ставим
  final bottomInset = math.max(MediaQuery.paddingOf(context).bottom, tabBarInset.value);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true, // касание вне выборки только закрывает её
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (dctx, a, s) => _Popover(
      anchor: anchor,
      bottomInset: bottomInset,
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
        follow(openDictionary(context, req, full: StudyData.dictKind(m) == 'strongs'));
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
  _Layout(this.anchor, this.arrow, this.bottomInset);
  final Rect anchor;
  final double bottomInset;
  final ValueNotifier<_Arrow> arrow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(minWidth: 230, maxWidth: math.min(340, c.maxWidth - 16), maxHeight: c.maxHeight - 16);

  @override
  Offset getPositionForChild(Size size, Size child) {
    // Под словом, а если внизу мало места (низ закрывают вкладки и проигрыватель) — над ним; по горизонтали — в пределах экрана
    final below = anchor.bottom + _gap + child.height < size.height - 8 - bottomInset || anchor.top - _gap - child.height < 8;
    final left = math.max(8.0, math.min(size.width - child.width - 8, anchor.left + anchor.width / 2 - child.width / 2));
    final x = math.max(16.0, math.min(child.width - 16, anchor.left + anchor.width / 2 - left));
    arrow.value = _Arrow(x, below);
    return Offset(left, below ? anchor.bottom + _gap : anchor.top - _gap - child.height);
  }

  @override
  bool shouldRelayout(_Layout old) => old.anchor != anchor || old.bottomInset != bottomInset;
}

/// Стрелочка к слову (.word-pop::before): квадрат 14×14 со скруглением 2, повёрнутый на 45°, цвета панели;
/// рамка 1 px только по двум сторонам, торчащим наружу. Рисуется поверх карточки — закрывает её рамку в этом месте.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrow, this.fill, this.line) : super(repaint: arrow);
  final ValueNotifier<_Arrow> arrow;
  final Color fill;
  final Color line;
  @override
  void paint(Canvas canvas, Size size) {
    final a = arrow.value;
    canvas.save();
    canvas.translate(a.x, a.below ? 0 : size.height);
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-7, -7, 14, 14), const Radius.circular(2)), Paint()..color = fill);
    final edge = Path();
    if (a.below) {
      edge..moveTo(-7, 7)..lineTo(-7, -7)..lineTo(7, -7); // левая и верхняя стороны
    } else {
      edge..moveTo(7, -7)..lineTo(7, 7)..lineTo(-7, 7); // правая и нижняя
    }
    canvas.drawPath(edge, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 1..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.fill != fill || old.line != line;
}

class _Popover extends ConsumerStatefulWidget {
  const _Popover({required this.anchor, this.bottomInset = 0, required this.res, required this.before, required this.after, required this.onChoose, required this.onItem, required this.onLibrary});
  final Rect anchor;
  final double bottomInset; // высота вкладок и проигрывателя снизу
  final LookupResult res;
  final List<WordMenuItem> before;
  final List<WordMenuItem> after;
  final void Function(InstalledModule module, String key) onChoose;
  final void Function(WordMenuItem) onItem;
  final VoidCallback? onLibrary;
  @override
  ConsumerState<_Popover> createState() => _PopoverState();
}

class _PopoverState extends ConsumerState<_Popover> {
  final _arrow = ValueNotifier(const _Arrow(30, true));

  @override
  void dispose() {
    _arrow.dispose();
    super.dispose();
  }

  /// .wp-item: как пункт меню — отступы 11/10/11/12, скругление 0.6·radius, подсветка нажатия accent 12%
  Widget _item(Palette pal, List<Widget> children, VoidCallback? onTap, {Key? key}) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      child: Row(children: children),
    );
    return Material(
      key: key,
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(kRadius * 0.6),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              highlightColor: pal.accent.withValues(alpha: 0.12),
              splashColor: pal.accent.withValues(alpha: 0.08),
              hoverColor: pal.accent.withValues(alpha: 0.08),
              child: row,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final res = widget.res;
    // сначала — статьи по номеру Стронга (G2423, H7225), ниже — остальные словари (по слову); внутри — прежний порядок
    final all = [
      for (final r in res.results)
        for (final f in r.found) (module: r.module, key: f.key, label: f.label),
    ];
    final strong = RegExp(r'^[GH]\d');
    final items = [...all.where((x) => strong.hasMatch(x.key)), ...all.where((x) => !strong.hasMatch(x.key))];
    final rows = <Widget>[];
    const base = TextStyle(fontSize: 16); // font-size: 1rem
    final go = Icon(LucideIcons.chevronRight, size: 16, color: pal.muted);
    final tabular = base.copyWith(color: pal.text, fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 0.16);

    // Пункты других функций («Название · Карта»): значок места, название, «·», подпись, стрелка
    Widget place(WordMenuItem x) => _item(pal, [
          Icon(LucideIcons.mapPin, size: 17, color: pal.accent),
          const SizedBox(width: 10),
          Text(x.label, style: tabular.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('·', style: base.copyWith(color: pal.muted)),
          const SizedBox(width: 10),
          Expanded(child: Text(x.sub ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: base.copyWith(color: pal.text))),
          const SizedBox(width: 10),
          go,
        ], () => widget.onItem(x));

    for (final x in widget.before) {
      rows.add(place(x));
    }
    for (final (i, it) in items.indexed) {
      final isNum = RegExp(r'^[HG]\d').hasMatch(it.key);
      rows.add(_item(pal, [
        if (isNum)
          // .wp-key.wp-num: плашка с номером Стронга
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: mix(pal.accent, 0.12, pal.bg), borderRadius: BorderRadius.circular(7)),
            child: Text(it.key, style: tabular.copyWith(fontSize: 14.08, fontWeight: FontWeight.w700, color: accentOnTint(pal))),
          )
        else
          Text(it.label.isEmpty ? it.key : it.label, style: tabular.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(child: Text(it.module.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: base.copyWith(color: pal.text))),
        const SizedBox(width: 10),
        go,
      ], () => widget.onChoose(it.module, it.key), key: i == 0 ? tourKey('word-pop-item') : null)); // цель инструкции
    }
    for (final x in widget.after) {
      rows.add(place(x));
    }
    if (items.isEmpty && widget.before.isEmpty && widget.after.isEmpty) {
      rows.add(_item(pal, [Expanded(child: Text(t('Статей для «{word}» нет', {'word': res.word}), style: base.copyWith(fontSize: 14.72, color: pal.muted)))], null));
      if (widget.onLibrary != null) rows.add(_item(pal, [Expanded(child: Text(t('Словари в библиотеке'), style: base.copyWith(color: pal.text)))], widget.onLibrary));
    }

    return CustomSingleChildLayout(
      delegate: _Layout(widget.anchor, _arrow, widget.bottomInset),
      child: CustomPaint(
        foregroundPainter: _ArrowPainter(_arrow, pal.panel, pal.line),
        child: DecoratedBox(
          key: tourKey('word-pop'), // цель инструкции: сама выборка, а не весь экран
          decoration: BoxDecoration(
            color: pal.panel,
            border: Border.all(color: pal.line),
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: const [
              BoxShadow(color: Color(0x29000000), blurRadius: 38, offset: Offset(0, 14)),
              BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // .wp-note
                if (res.mapping.mode == 'approx')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(t('≈ приблизительно: перевод без номеров Стронга'), style: TextStyle(fontSize: 12.48, color: pal.muted)),
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
