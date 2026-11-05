// Окна «Заметка» (NoteSheet.jsx) и «В подборку» (CollectSheet.jsx).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../shell/fonts.dart' show readerTextStyle;
import '../../ui/kit.dart';
import '../study/dictionary_sheet.dart' show openRefInOther;
import '../study/sheet.dart' show LinkedText, splitRefs;
import 'marks.dart';
import 'ui.dart';
import '../../ui/ios_style.dart';

/// Заметка к стиху или к выделенным стихам (хранится у первого из них)
/// pane — из какой панели открыли (ссылки в тексте заметки открываются в соседней); без него — панель с этим переводом
void showNoteSheet(BuildContext context, List<VerseRef> refs, String? moduleId, {int? pane}) {
  final ref = ProviderScope.containerOf(context); // не WidgetRef: окно живёт дольше строки, из которой открыто
  final msg = ScaffoldMessenger.maybeOf(context);
  final first = refs.first;
  final panes = ref.read(panesProvider);
  final fromPane = pane ?? (() {
    final i = panes.indexWhere((p) => p.moduleId == moduleId);
    return i < 0 ? 0 : i;
  })();
  final existing = ref.read(marksProvider).noteOf(first);
  final label = (existing?['label'] as String?)?.isNotEmpty == true ? existing!['label'] as String : selectionLabel(refs, full: true);
  final verse = moduleId == null ? '' : selectionText(moduleId, refs);
  final ctl = TextEditingController(text: (existing?['text'] as String?) ?? '');
  showSheet<void>(
    context,
    initial: 0.5,
    title: existing != null ? t('Заметка') : t('Новая заметка'),
    subtitle: label,
    body: (ctx) => Consumer(
      builder: (ctx, wref, _) {
        final pal = paletteOf(wref);
        final font = readerTextStyle(wref.watch(settingsProvider), size: 16.3, weight: 400); // --font-text
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (verse.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: (iosUiNow ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius * 0.6)) : BoxDecoration(color: mix(pal.accent, 0.06, pal.panel), border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius * 0.6))),
              child: Text(verse, style: font.copyWith(fontSize: 15, height: 1.5, color: pal.text)),
            ),
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 7,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            style: font.copyWith(height: 1.5, color: pal.text),
            decoration: InputDecoration(
              hintText: t('Ваши мысли, вопросы, ссылки…'),
              hintStyle: TextStyle(color: pal.muted),
              isDense: true,
              filled: true,
              fillColor: pal.bg,
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), borderSide: BorderSide(color: pal.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), borderSide: BorderSide(color: pal.accent)),
            ),
          ),
          // .note-preview: ссылки на стихи («Ин 3:16») в тексте заметки — кнопки; заметка при переходе сохраняется
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctl,
            builder: (_, v, _) => !splitRefs(v.text).any((x) => x.$2 != null)
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: CustomPaint(
                      foregroundPainter: _DashedRRect(pal.line, kRadius * 0.75),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(kRadius * 0.75)),
                        child: LinkedText(
                          text: v.text,
                          style: font.copyWith(height: 1.5, color: pal.text),
                          onOpen: (r) {
                            ref.read(marksProvider.notifier).setNote(first, ctl.text, label);
                            openRefInOther(ctx, wref, fromPane, r);
                          },
                        ),
                      ),
                    ),
                  ),
          ),
          if (existing != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('Создана {date}', {'date': fmtDate(existing['at'], year: true)}), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted))),
          _DisposeWith(ctl),
        ]);
      },
    ),
    // Wrap, а не Row: «Удалить → Удалить / Отмена» + «Сохранить» на узком экране или при крупном шрифте переносятся
    footer: (ctx) => Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
      if (existing != null)
        ConfirmButton(
          icon: LucideIcons.trash2,
          label: t('Удалить'),
          confirmLabel: t('Удалить'),
          onConfirm: () {
            ref.read(marksProvider.notifier).setNote(first, '', '');
            toastOn(msg, t('Заметка удалена'));
            Navigator.pop(ctx);
          },
        ),
      AobButton(
        kind: BtnKind.primary,
        icon: LucideIcons.save,
        label: t('Сохранить'),
        onTap: () {
          ref.read(marksProvider.notifier).setNote(first, ctl.text, label);
          toastOn(msg, ctl.text.trim().isNotEmpty ? t('Заметка сохранена') : t('Заметка удалена'));
          Navigator.pop(ctx);
        },
      ),
    ]),
  );
}

/// «В подборку»: добавить стихи в существующую подборку или создать новую
void showCollectSheet(BuildContext context, List<VerseRef> refs, String moduleId) {
  final ref = ProviderScope.containerOf(context);
  final msg = ScaffoldMessenger.maybeOf(context);
  final items = <Json>[
    for (final r in refs) {'book': r.book, 'chapter': r.chapter, 'verse': r.verse, 'text': _cut(verseText(moduleId, r) ?? '', 200)},
  ];
  final ctl = TextEditingController();
  showSheet<void>(
    context,
    initial: 0.5,
    title: t('В подборку'),
    subtitle: selectionLabel(refs, full: true),
    body: (ctx) => Consumer(
      builder: (ctx, wref, _) => StatefulBuilder(
        builder: (ctx, setState) {
          final pal = paletteOf(wref);
          final cols = ref.read(marksProvider).collections;
          void add(String? id, String? name) {
            ref.read(marksProvider.notifier).addToCollection(id, items, name, t('Подборка'));
            final shown = name ?? cols.firstWhere((c) => c['id'] == id, orElse: () => {'name': ''})['name'];
            toastOn(msg, t('Добавлено в подборку «{name}»', {'name': '$shown'}));
            Navigator.pop(ctx);
          }

          bool has(Json c) => refs.every((r) => (c['items'] as List).any((x) => itemKey(x as Map) == refKey(r)));
          final canCreate = ctl.text.trim().isNotEmpty;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: AobInput(
                    controller: ctl,
                    icon: null,
                    clearable: false,
                    hint: t('Новая подборка: «К уроку», «Утешение»…'),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) => v.trim().isNotEmpty ? add(null, v.trim()) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Opacity(
                  opacity: canCreate ? 1 : 0.4,
                  child: Tooltip(
                    message: t('Создать подборку'),
                    child: Material(
                      color: pal.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: pal.accent)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(onTap: canCreate ? () => add(null, ctl.text.trim()) : null, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: AIcon(ico(LucideIcons.folderPlus), size: 18, color: pal.onAccent))),
                    ),
                  ),
                ),
              ]),
            ),
            if (cols.isNotEmpty) const SizedBox(height: 12),
            // подборки — строками от края до края окна, отступ 20 — у содержимого
            for (final c in cols)
              bleed(InkWell(
                onTap: () => add('${c['id']}', null),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                  child: Row(children: [
                    AIcon(ico(LucideIcons.folder), size: 16, color: pal.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${c['name']}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text))),
                    // стих добавлен в подборку — вместо числа плавно проявляется галочка
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.fastOutSlowIn,
                      switchOutCurve: Curves.fastOutSlowIn,
                      transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: w)),
                      child: has(c) ? AIcon(ico(LucideIcons.check), key: const ValueKey('has'), size: 15, color: pal.muted) : Text(t('{n} ст.', {'n': '${(c['items'] as List).length}'}), key: const ValueKey('n'), style: TextStyle(fontSize: 13.1, color: pal.muted)),
                    ),
                  ]),
                ),
              )),
            _DisposeWith(ctl),
          ]);
        },
      ),
    ),
  );
}

/// border: 1px dashed — пунктирная рамка со скруглением
class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect o) => o.color != color || o.radius != radius;
}

/// Контроллер поля закрывается вместе с окном: Future showModalBottomSheet завершается в момент закрытия, а поле
/// ещё перерисовывается до конца анимации — dispose по whenComplete роняет «controller was used after being disposed».
/// Виджет ставится после поля: при удалении ветки поле освобождается раньше.
class _DisposeWith extends StatefulWidget {
  const _DisposeWith(this.ctl);
  final TextEditingController ctl;
  @override
  State<_DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<_DisposeWith> {
  @override
  void dispose() {
    widget.ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
