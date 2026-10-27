// Строка действий под выделенным стихом (.sel-inline в BibleReader.jsx → SelectionInline):
// карточка с «язычком» к стиху: «Слушать» (акцентная таблетка) · «В проповедь» · «Часть стиха» (один стих) · «Подстрочник».
// Читалка пока не умеет ставить виджет под стих: нужна точка VerseDecor.below (виджет под текстом стиха, пока он
// выделен) — см. отчёт. Как только она появится, verseDecor возвращает buildSelectionInline(...) последнему выделенному стиху.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import '../shell/tour_targets.dart' show tourKey;

/// onDone — снять выделение; onPart — начать выбор части стиха (если читалка это умеет, иначе кнопки нет)
Widget buildSelectionInline(BuildContext context, WidgetRef ref, {required int pane, required String moduleId, required List<VerseRef> refs, required VoidCallback onDone, VoidCallback? onPart}) {
  final pal = paletteOf(ref);
  final first = refs.first;
  final scale = MediaQuery.textScalerOf(context);

  // действия — одной капсулой: «Слушать» (круг цвета акцента) │ «В проповедь» │ «Часть стиха» │ «Подстрочник»;
  // у всех подписей один размер шрифта; значки — если помещаются
  final acts = <(IconData, String, VoidCallback, Key?)>[
    if (Hub.addToSermon != null)
      (LucideIcons.scrollText, t('В проповедь'), () {
        Hub.addToSermon!(context, ref, refs, moduleId);
        onDone();
      }, pane == 0 ? tourKey('sel-sermon') : null), // цель инструкции
    if (refs.length == 1 && onPart != null) (LucideIcons.scanText, t('Часть стиха'), onPart, null),
    if (Hub.openInterlinear != null)
      (LucideIcons.letterText, t('Подстрочник'), () {
        Hub.openInterlinear!(context, ref, first, moduleId);
        onDone();
      }, null),
  ];
  final listen = Hub.listenFrom != null;
  // мерить тем же шрифтом, каким рисуется подпись (шрифт темы), иначе расчёт ширины врёт
  final baseStyle = DefaultTextStyle.of(context).style;
  double textW(String s, double fs) {
    final tp = TextPainter(text: TextSpan(text: s, style: baseStyle.merge(TextStyle(fontSize: fs, fontWeight: FontWeight.w500))), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  // все действия одним списком: «Слушать» — первая, главная
  final all = <(IconData, String, VoidCallback, Key?)>[
    if (listen)
      (LucideIcons.headphones, t('Слушать'), () {
        Hub.listenFrom!(context, ref, pane, first);
        onDone();
      }, null),
    ...acts,
  ];

  return Padding(
    // margin: .2em 0 1em
    padding: const EdgeInsets.only(top: 2, bottom: 15),
    child: LayoutBuilder(builder: (context, box) {
      final n = all.length;
      // широко — одна строка «значок + подпись»; иначе ячейки поровну, значок над подписью.
      // «Слушать» — без подписи: квадратная ячейка, залитая акцентом; поля и скругление — как у остальных ячеек
      const rowFs = 13.8;
      final rowNeed = acts.fold<double>(0, (x, a) => x + textW(a.$2, rowFs) + 16 + 6 + 28) + (listen ? 44 : 0) + 8 + 2;
      final inRow = rowNeed <= box.maxWidth;
      final h = inRow ? 44.0 : 54.0;
      final listenW = listen ? h : 0.0;
      final cell = (box.maxWidth - 8 - 2 - listenW) / math.max(1, acts.length);
      final widest = acts.fold<double>(0, (x, a) => math.max(x, textW(a.$2, 12)));
      // у подписи не меньше 8 с каждой стороны ячейки
      final colFs = widest + 16 <= cell ? 12.0 : math.max(10.5, 12 * (cell - 16) / widest);
      final muted = Color.lerp(pal.text, pal.muted, 0.35)!;

      Widget cellOf(int k) {
        final (icon, text, onTap, key) = all[k];
        final main = listen && k == 0;
        if (main) {
          return SizedBox(
            width: listenW,
            child: Tooltip(
              message: text,
              child: Semantics(
                button: true,
                label: t('Слушать с этого стиха'),
                child: _Press(
                  onTap: onTap,
                  radius: inRow ? 10 : 12,
                  // Ink — заливка рисуется на Material, поэтому волна нажатия видна поверх неё
                  child: Ink(
                    height: h,
                    decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(inRow ? 10 : 12)),
                    child: Center(child: Icon(icon, size: 20, color: pal.onAccent)),
                  ),
                ),
              ),
            ),
          );
        }
        final Widget body;
        if (inRow) {
          final row = Row(mainAxisSize: MainAxisSize.min, children: [
            // у «Слушать» акцентная подложка только под значком
            main
                ? Container(width: 30, height: 28, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 16, color: pal.onAccent))
                : Icon(icon, size: 16, color: pal.text),
            const SizedBox(width: 6),
            Flexible(
              child: Transform.translate(
                offset: const Offset(0, -1),
                child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: rowFs, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: main ? FontWeight.w600 : FontWeight.w500, color: pal.text)),
              ),
            ),
          ]);
          // у «Слушать» слева поле как сверху и снизу у подложки значка: (44 − 28) / 2 = 8
          body = Padding(padding: EdgeInsets.only(left: main ? 8 : 10, right: 10), child: main ? Align(alignment: Alignment.centerLeft, child: row) : Center(child: row));
        } else {
          // подложка значка — во всю ширину ячейки с полем 4 сверху и по бокам (от края карточки 4 + 4 = 8 со всех
          // сторон); у «Слушать» она залита акцентом, скругление 9
          body = Column(children: [
            Container(
              width: double.infinity, // столбец центрирует детей — подложку растягиваем явно
              height: 30,
              margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              decoration: main ? BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(9)) : null,
              child: Icon(icon, size: 20, color: main ? pal.onAccent : pal.text),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: colFs, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: main ? FontWeight.w600 : FontWeight.w500, color: main ? pal.text : muted)),
            ),
          ]);
        }
        // скругление ячейки = скругление карточки − поле (4)
        final r = inRow ? 10.0 : 12.0;
        final cellBody = SizedBox(height: inRow ? 44 : 54, child: body);
        final semantics = Semantics(
            button: true,
            label: main ? t('Слушать с этого стиха') : null,
            child: _Press(
              key: key,
              onTap: onTap,
              radius: r,
              child: cellBody,
            ),
          );
        if (main && !inRow) return SizedBox(width: listenW, child: semantics);
        // в строку ширина — по длине подписи, в ячейках — поровну
        return Expanded(flex: inRow ? ((textW(text, rowFs) + 50) * 10).round() : 100, child: semantics);
      }

      // «язычок» над карточкой — у левого края, против полоски выделения стиха
      final shape = _CaretBorder(radius: inRow ? 14 : 16 /* = скругление ячейки + поле 4 */, caretX: 24, side: BorderSide(color: pal.line));
      final card = Material(
        color: pal.panel,
        shape: shape,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: pal.dark ? 0.5 : 0.22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // поля 4 со всех сторон: скругление ячейки (12) + поле (4) = скругление карточки (16)
          padding: const EdgeInsets.fromLTRB(4, _CaretBorder.caretH + 4, 4, 4),
          child: Row(children: [for (var k = 0; k < n; k++) cellOf(k)]),
        ),
      );
      // появление: выезжает из-под стиха на 6 и проявляется за 200 мс
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -6 * (1 - v)), child: child)),
        child: card,
      );
    }),
  );
}

/// Ячейка-кнопка: при нажатии слегка сжимается (0,96) и подсвечивается
class _Press extends StatefulWidget {
  const _Press({super.key, required this.onTap, required this.child, this.radius = 12});
  final VoidCallback onTap;
  final Widget child;
  final double radius;
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: InkWell(onTap: widget.onTap, borderRadius: BorderRadius.circular(widget.radius), child: widget.child),
        ),
      );
}

/// Скруглённый прямоугольник с «язычком» сверху (указывает на стих); рамка обводит всё одной линией
class _CaretBorder extends ShapeBorder {
  const _CaretBorder({required this.radius, required this.caretX, this.side = BorderSide.none});
  final double radius, caretX;
  final BorderSide side;
  static const caretH = 6.0, caretW = 14.0;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(top: caretH);

  Path _path(Rect r) {
    final body = Rect.fromLTRB(r.left, r.top + caretH, r.right, r.bottom);
    final rr = RRect.fromRectAndRadius(body, Radius.circular(radius));
    final x = r.left + caretX;
    // ровные стороны, чуть скруглённая вершина
    final caret = Path()
      ..moveTo(x - caretW / 2, body.top + 1)
      ..lineTo(x - 1.6, r.top + 1.2)
      ..quadraticBezierTo(x, r.top, x + 1.6, r.top + 1.2)
      ..lineTo(x + caretW / 2, body.top + 1)
      ..close();
    return Path.combine(PathOperation.union, Path()..addRRect(rr), caret);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => _CaretBorder(radius: radius * t, caretX: caretX * t, side: side.scale(t));
}
