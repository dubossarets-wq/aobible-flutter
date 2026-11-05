// Общие мелочи для окон закладок: уведомления, нижнее окно, дата, кнопка «Удалить → Удалить / Отмена»,
// строка списка со смахиванием (SwipeRow.jsx + .list-row), пустой список (Empty из ui.jsx), закрашенные значки.
// Окна — showAobSheet/AobSheet из kit.dart, кнопки — AobButton, значки — Lucide.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../ui/kit.dart';
import '../../ui/ios_style.dart';

void toast(BuildContext context, String text) => toastOn(context.mounted ? ScaffoldMessenger.maybeOf(context) : null, text);

/// То же, но с заранее взятым ScaffoldMessenger — когда окно переживает виджет, из которого открыто
void toastOn(ScaffoldMessengerState? m, String text) {
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// Уведомление с «Отменить» (удаление смахиванием или кнопкой — сразу, с возможностью вернуть)
void undoToast(BuildContext context, String text, VoidCallback undo) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5), action: SnackBarAction(label: t('Отменить'), onPressed: undo)));
}

String two(int n) => n < 10 ? '0$n' : '$n';

/// «24.10.2026 18:05» — цифрами, одинаково для всех языков
String fmtDate(Object? ms, {bool year = false}) {
  if (ms is! num) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return '${two(d.day)}.${two(d.month)}${year ? '.${d.year}' : ''} ${two(d.hour)}:${two(d.minute)}';
}

/// Нижнее окно (BottomSheet.jsx): заголовок, подзаголовок, прокручиваемое содержимое и (по желанию) нижняя
/// полоса с кнопками — .sheet-foot: линия сверху, поля 10/16.
Future<T?> showSheet<T>(BuildContext context, {required String title, String? subtitle, required Widget Function(BuildContext) body, Widget Function(BuildContext)? footer, double initial = 0.92}) {
  return showAobSheet<T>(
    context,
    initial: initial,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final pal = paletteOf(ref);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: AobSheet(
            title: title,
            subtitle: subtitle,
            scroll: false,
            padding: EdgeInsets.zero,
            child: Column(children: [
              Expanded(child: Builder(builder: (bc) => SingleChildScrollView(padding: footer != null ? const EdgeInsets.fromLTRB(16, 12, 16, 20) : padTabs(bc, const EdgeInsets.fromLTRB(16, 12, 16, 20)), child: body(ctx)))),
              if (footer != null)
                Builder(builder: (bc) => Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(bc).bottom),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                  child: footer(ctx),
                )),
            ]),
          ),
        );
      },
    ),
  );
}

/// ConfirmButton из ui.jsx: первое нажатие меняет кнопку на «красная подтверждающая + Отмена»
class ConfirmButton extends StatefulWidget {
  const ConfirmButton({super.key, required this.icon, required this.label, required this.confirmLabel, required this.onConfirm, this.small = false});
  final IconData icon;
  final String label, confirmLabel;
  final VoidCallback onConfirm;
  final bool small;
  @override
  State<ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<ConfirmButton> {
  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_armed) {
      return AobButton(
        icon: widget.icon,
        label: widget.label,
        small: widget.small,
        onTap: () {
          setState(() => _armed = true);
          _timer?.cancel();
          _timer = Timer(const Duration(seconds: 4), () => mounted ? setState(() => _armed = false) : null);
        },
      );
    }
    // Wrap: на узкой полосе или при крупном шрифте «Отмена» переходит на вторую строку, а не за край
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AobButton(label: widget.confirmLabel, kind: BtnKind.danger, small: widget.small, onTap: widget.onConfirm),
      AobButton(label: t('Отмена'), small: widget.small, onTap: () => setState(() => _armed = false)),
    ]);
  }
}

// --- Пустой список (Empty в ui.jsx): значок 28, заголовок, подпись --------------------------------------------

class EmptyState extends ConsumerWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ico(icon), size: iosUiNow ? 48 : 28, color: pal.muted),
          SizedBox(height: iosUiNow ? 14 : 8),
          Text(title, textAlign: TextAlign.center, style: iosUiNow ? TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text) : TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
          if (text != null) ...[
            SizedBox(height: iosUiNow ? 6 : 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 290), child: Text(text!, textAlign: TextAlign.center, style: TextStyle(fontSize: iosUiNow ? 17 : 14.4, height: iosUiNow ? 1.3 : 1.45, color: pal.muted))),
          ],
        ]),
      ),
    );
  }
}

// --- Строка списка со смахиванием (SwipeRow.jsx, .list-row, .list-main) ---------------------------------------

/// Строка: заголовок (значок + текст + дата), подпись до двух строк, справа — маленькие кнопки.
/// Смахивание влево открывает красную полосу «Удалить» (#d1342b), протянутое — удаляет, как full в веб-версии.
class AobListRow extends ConsumerWidget {
  const AobListRow({
    super.key,
    required this.id,
    required this.title,
    this.meta,
    this.metaRight = false,
    this.text,
    required this.onTap,
    required this.onDelete,
    required this.deleteLabel,
    this.actionText,
    this.extra = const [],
    this.first = false,
    this.last = false,
  });
  final bool first, last; // место в списке: в стиле iPhone строки складываются в карточку группы
  final Object id;
  final Widget title;
  final String? meta, text;
  final bool metaRight; // список подборок: число стихов прижато вправо (.list-meta без .stacked)
  final VoidCallback onTap, onDelete;
  final String deleteLabel;
  final String? actionText; // «Убрать» вместо «Удалить»
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final metaText = meta == null ? null : Text(meta!, style: TextStyle(fontSize: 13.1, fontWeight: FontWeight.w400, color: pal.muted));
    // строка — от края до края окна (bleed поверх полей 16), и подсветка, и линия, и красная полоса; отступ 20 — у содержимого.
    // Стиль iPhone: строка — часть карточки группы, удаление — смахиванием (без значка корзины в строке)
    final ios = iosStyleOf(ref);
    final row = Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: const Color(0xffd1342b), // один и тот же красный в любой теме — белая надпись читается
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 88,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ico(LucideIcons.trash2), size: 18, color: Colors.white),
            const SizedBox(height: 3),
            Text(actionText ?? t('Удалить'), maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ),
      child: Material(
        color: ios ? Colors.transparent : pal.panel,
        child: InkWell(
          onTap: onTap,
          child: Container(
          // справа 12: у кнопки 32 значок 16 — его край приходится на 20
          padding: ios ? const EdgeInsets.only(left: iosRowIconLeft, right: iosRowRight) : const EdgeInsets.only(left: 20, right: 12),
          decoration: ios ? null : BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, top: 11, bottom: 11),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: DefaultTextStyle.merge(style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text), child: title)),
                      if (metaText != null && !metaRight) Padding(padding: const EdgeInsets.only(left: 8), child: metaText),
                      if (metaText != null && metaRight) ...[const Spacer(), metaText],
                    ]),
                    if (text != null && text!.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 3), child: Text(text!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.1, height: 1.4, color: pal.muted))),
                  ]),
                ),
            ),
            ...extra,
            if (!ios) IconBtn(icon: LucideIcons.trash2, subtle: true, size: 16, tooltip: deleteLabel, onTap: onDelete),
          ]),
        ),
        ),
      ),
    );
    return ios ? IosCardItem(pal: pal, first: first, last: last, child: row) : bleed(row);
  }
}

// --- Закрашенные значки: в Lucide для Flutter нет «заливки», а в веб-версии сердце/папка закрашены -------------

/// Рисует контур на сетке 24×24, масштабируя до size: заливка цветом, по желанию — обводка (как у lucide fill="currentColor")
class FillIcon extends StatelessWidget {
  const FillIcon({super.key, required this.path, required this.size, required this.color, this.stroke = false});
  final Path Function() path;
  final double size;
  final Color color;
  final bool stroke;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _FillPainter(path(), color, stroke));
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.p, this.color, this.stroke);
  final Path p;
  final Color color;
  final bool stroke;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(p, Paint()..color = color);
    if (stroke) {
      canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_FillPainter o) => o.color != color || o.stroke != stroke;
}

/// Heart из Lucide (контур)
Path lucideHeartPath() => Path()
  ..moveTo(19, 14)
  ..cubicTo(20.49, 12.54, 22, 10.79, 22, 8.5)
  ..arcToPoint(const Offset(16.5, 3), radius: const Radius.circular(5.5), clockwise: false)
  ..cubicTo(14.74, 3, 13.5, 3.5, 12, 5)
  ..cubicTo(10.5, 3.5, 9.26, 3, 7.5, 3)
  ..arcToPoint(const Offset(2, 8.5), radius: const Radius.circular(5.5), clockwise: false)
  ..cubicTo(2, 10.8, 3.5, 12.55, 5, 14)
  ..lineTo(12, 21)
  ..close();

/// Сердечко у стиха (path из ChapterView.jsx)
Path verseHeartPath() => Path()
  ..moveTo(12, 21)
  ..cubicTo(12, 21, 4.4, 16.3, 2.3, 11.6)
  ..cubicTo(0.8, 8.3, 3, 4.4, 6.8, 4.4)
  ..cubicTo(9, 4.4, 10.5, 5.6, 12, 7.4)
  ..cubicTo(13.5, 5.6, 15, 4.4, 17.2, 4.4)
  ..cubicTo(21, 4.4, 23.2, 8.3, 21.7, 11.6)
  ..cubicTo(19.6, 16.3, 12, 21, 12, 21)
  ..close();

/// Папка у стиха «в подборке» (path из ChapterView.jsx)
Path verseFolderPath() => Path()
  ..moveTo(20, 20)
  ..arcToPoint(const Offset(22, 18), radius: const Radius.circular(2), clockwise: false)
  ..lineTo(22, 8)
  ..arcToPoint(const Offset(20, 6), radius: const Radius.circular(2), clockwise: false)
  ..lineTo(12.1, 6)
  ..arcToPoint(const Offset(10.41, 5.1), radius: const Radius.circular(2))
  ..lineTo(9.6, 3.9)
  ..arcToPoint(const Offset(7.93, 3), radius: const Radius.circular(2), clockwise: false)
  ..lineTo(4, 3)
  ..arcToPoint(const Offset(2, 5), radius: const Radius.circular(2), clockwise: false)
  ..lineTo(2, 18)
  ..arcToPoint(const Offset(4, 20), radius: const Radius.circular(2), clockwise: false)
  ..close();
