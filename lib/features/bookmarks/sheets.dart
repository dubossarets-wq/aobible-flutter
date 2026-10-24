// Окна «Заметка» (NoteSheet.jsx) и «В подборку» (CollectSheet.jsx).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'marks.dart';
import 'ui.dart';

/// Заметка к стиху или к выделенным стихам (хранится у первого из них)
void showNoteSheet(BuildContext context, List<VerseRef> refs, String? moduleId) {
  final ref = ProviderScope.containerOf(context); // не WidgetRef: окно живёт дольше строки, из которой открыто
  final msg = ScaffoldMessenger.maybeOf(context);
  final pal = ref.read(settingsProvider).palette;
  final first = refs.first;
  final existing = ref.read(marksProvider).noteOf(first);
  final label = (existing?['label'] as String?)?.isNotEmpty == true ? existing!['label'] as String : selectionLabel(refs, full: true);
  final verse = moduleId == null ? '' : selectionText(moduleId, refs);
  final ctl = TextEditingController(text: (existing?['text'] as String?) ?? '');
  showSheet<void>(
    context,
    pal,
    title: existing != null ? t('Заметка') : t('Новая заметка'),
    subtitle: label,
    body: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (verse.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.accent, width: 3))),
          child: Text(verse, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, height: 1.35)),
        ),
      TextField(
        controller: ctl,
        autofocus: true,
        minLines: 5,
        maxLines: 10,
        keyboardType: TextInputType.multiline,
        style: TextStyle(color: pal.text),
        decoration: InputDecoration(hintText: t('Ваши мысли, вопросы, ссылки…'), border: const OutlineInputBorder()),
      ),
      if (existing != null)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('Создана {date}', {'date': fmtDate(existing['at'], year: true)}), style: TextStyle(fontSize: 12, color: pal.muted))),
    ]),
    footer: Builder(
      builder: (ctx) => Row(children: [
        if (existing != null)
          ConfirmButton(
            pal: pal,
            icon: Icons.delete_outline,
            label: t('Удалить'),
            confirmLabel: t('Удалить'),
            onConfirm: () {
              ref.read(marksProvider.notifier).setNote(first, '', '');
              toastOn(msg, t('Заметка удалена'));
              Navigator.pop(ctx);
            },
          ),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: pal.onAccent),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(t('Сохранить')),
          onPressed: () {
            ref.read(marksProvider.notifier).setNote(first, ctl.text, label);
            toastOn(msg, ctl.text.trim().isNotEmpty ? t('Заметка сохранена') : t('Заметка удалена'));
            Navigator.pop(ctx);
          },
        ),
      ]),
    ),
  ).whenComplete(ctl.dispose);
}

/// «В подборку»: добавить стихи в существующую подборку или создать новую
void showCollectSheet(BuildContext context, List<VerseRef> refs, String moduleId) {
  final ref = ProviderScope.containerOf(context);
  final msg = ScaffoldMessenger.maybeOf(context);
  final pal = ref.read(settingsProvider).palette;
  final items = <Json>[
    for (final r in refs) {'book': r.book, 'chapter': r.chapter, 'verse': r.verse, 'text': _cut(verseText(moduleId, r) ?? '', 200)},
  ];
  final ctl = TextEditingController();
  showSheet<void>(
    context,
    pal,
    title: t('В подборку'),
    subtitle: selectionLabel(refs, full: true),
    body: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final cols = ref.read(marksProvider).collections;
        void add(String? id, String? name) {
          ref.read(marksProvider.notifier).addToCollection(id, items, name, t('Подборка'));
          final shown = name ?? cols.firstWhere((c) => c['id'] == id, orElse: () => {'name': ''})['name'];
          toastOn(msg, t('Добавлено в подборку «{name}»', {'name': '$shown'}));
          Navigator.pop(ctx);
        }

        bool has(Json c) => refs.every((r) => (c['items'] as List).any((x) => itemKey(x as Map) == refKey(r)));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctl,
                style: TextStyle(color: pal.text),
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => v.trim().isNotEmpty ? add(null, v.trim()) : null,
                decoration: InputDecoration(hintText: t('Новая подборка: «К уроку», «Утешение»…'), border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: t('Создать подборку'),
              style: IconButton.styleFrom(backgroundColor: pal.accent, foregroundColor: pal.onAccent),
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: ctl.text.trim().isEmpty ? null : () => add(null, ctl.text.trim()),
            ),
          ]),
          for (final c in cols)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.folder_outlined, color: pal.accent),
              title: Text('${c['name']}', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
              trailing: has(c) ? Icon(Icons.check, size: 18, color: pal.muted) : Text(t('{n} ст.', {'n': '${(c['items'] as List).length}'}), style: TextStyle(color: pal.muted)),
              onTap: () => add('${c['id']}', null),
            ),
        ]);
      },
    ),
  ).whenComplete(ctl.dispose);
}

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
