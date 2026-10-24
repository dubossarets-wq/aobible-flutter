// Общие мелочи для окон закладок: уведомления, нижнее окно, дата, кнопка «нажмите ещё раз».
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';

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

/// Нижнее окно в цветах темы: заголовок, подзаголовок, содержимое, кнопки внизу
Future<T?> showSheet<T>(BuildContext context, Palette pal, {required String title, String? subtitle, required Widget Function(BuildContext) body, Widget? footer}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: pal.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(color: pal.muted))),
          const SizedBox(height: 12),
          body(ctx),
          if (footer != null) ...[const SizedBox(height: 12), footer],
        ]),
      ),
    ),
  );
}

/// Кнопка, которой нужно нажать дважды: первое нажатие меняет подпись («Удалить» → «Удалить?»)
class ConfirmButton extends StatefulWidget {
  const ConfirmButton({super.key, required this.icon, required this.label, required this.confirmLabel, required this.onConfirm, required this.pal});
  final IconData icon;
  final String label, confirmLabel;
  final VoidCallback onConfirm;
  final Palette pal;
  @override
  State<ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<ConfirmButton> {
  bool _armed = false;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: _armed ? Colors.red : widget.pal.text, side: BorderSide(color: _armed ? Colors.red : widget.pal.line)),
        icon: Icon(widget.icon, size: 18),
        label: Text(_armed ? widget.confirmLabel : widget.label),
        onPressed: () {
          if (_armed) {
            widget.onConfirm();
          } else {
            setState(() => _armed = true);
            Future.delayed(const Duration(seconds: 4), () => mounted ? setState(() => _armed = false) : null);
          }
        },
      );
}
