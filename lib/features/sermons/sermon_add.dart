// «Добавить в проповедь» (SermonAddSheet.jsx): выбор проповеди или новая проповедь; выделенные стихи добавляются сами.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../plans/loc.dart';
import '../shell/tour_targets.dart' show tourKey;
import '../plans/ui_kit.dart';
import '../plans/verse_text.dart';
import 'sermon_store.dart';
import 'sermons_sheet.dart';

class SermonAddSheet extends ConsumerStatefulWidget {
  const SermonAddSheet({super.key, required this.pane, required this.refs, required this.moduleId, this.fragment});
  final int pane;
  final List<VerseRef> refs;
  final String moduleId;
  final String? fragment; // часть стиха (выбранные слова) вместо всего стиха
  @override
  ConsumerState<SermonAddSheet> createState() => _SermonAddSheetState();
}

class _SermonAddSheetState extends ConsumerState<SermonAddSheet> {
  final _title = TextEditingController();
  ({String id, String title})? _done;
  late final List<String> _texts;

  late final String _label = selectionLabel(widget.refs, full: true) + (widget.fragment != null ? ' ${t('(часть)')}' : '');

  @override
  void initState() {
    super.initState();
    ensureDict();
    _texts = widget.fragment != null ? [widget.fragment!] : [for (final r in widget.refs) verseText(widget.moduleId, r) ?? ''];
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _add(String id, String name) {
    ref.read(sermonsProvider.notifier).addVerses(
          id,
          [for (final (i, r) in widget.refs.indexed) VerseItem(r.book, r.chapter, r.verse, i < _texts.length ? _texts[i] : '', part: widget.fragment != null)],
          widget.moduleId,
        );
    setState(() => _done = (id: id, title: name));
  }

  void _createAndAdd() {
    final name = _title.text.trim().isEmpty ? t('Новая проповедь') : _title.text.trim();
    _add(ref.read(sermonsProvider.notifier).create(name), name);
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final sermons = ref.watch(sermonsProvider);
    final done = _done;
    if (done != null) {
      final parts = t('{ref} — в проповеди «{title}».', {'ref': '\u0000', 'title': done.title}).split('\u0000');
      // .sermon-done: галочка по центру свободного места, надпись и кнопки — внизу окна
      return AobSheet(
        title: t('Добавлено'),
        scroll: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(key: tourKey('sermon-done'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(shape: BoxShape.circle, color: mix(kOk, 0.14, pal.panel), boxShadow: [BoxShadow(color: mix(kOk, 0.06, Colors.transparent), spreadRadius: 6)]),
                child: const Icon(LucideIcons.check, size: 34, color: kOk),
              ),
            ),
          ),
          Text.rich(
            TextSpan(children: [TextSpan(text: parts.first), TextSpan(text: _label, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: parts.length > 1 ? parts.last : '')]),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16.3, color: pal.text, height: 1.45),
          ),
          const SizedBox(height: 20),
          AobButton(
            kind: BtnKind.primary,
            wide: true,
            icon: LucideIcons.scrollText,
            label: t('Открыть проповедь'),
            onTap: () {
              final nav = Navigator.of(context);
              final ctx = nav.context;
              nav.pop();
              showPage(ctx, (_) => SermonsSheet(pane: widget.pane, open: done.id), page: true);
            },
          ),
          const SizedBox(height: 8),
          AobButton(wide: true, label: t('Читать дальше'), onTap: () => Navigator.of(context).pop()),
        ]),
      );
    }
    return AobSheet(
      title: t('Добавить в проповедь'),
      subtitle: _label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // .sermon-new: подпись и «поле + Создать», промежуток 6
        Column(key: tourKey('sermon-new'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sermons.isNotEmpty ? t('Новая проповедь') : t('Назовите проповедь'), style: TextStyle(fontWeight: FontWeight.w500, color: pal.text)),
          const SizedBox(height: 6),
          // IntrinsicHeight: окно прокручивается, высота не ограничена — stretch тянется до высоты поля
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: PlainInput(controller: _title, autofocus: sermons.isEmpty, hint: t('Например: Благодать Божья'), onSubmitted: (_) => _createAndAdd())),
              const SizedBox(width: 8),
              AobButton(kind: BtnKind.primary, icon: LucideIcons.plus, label: t('Создать'), onTap: _createAndAdd),
            ]),
          ),
        ]),
        if (sermons.isNotEmpty) ...[
          const SizedBox(height: 20), // margin-bottom 8 + промежуток 12
          GroupTitle(t('Или выберите проповедь')),
          const SizedBox(height: 2),
          for (final s in sermons) SermonRow(pal: pal, sermon: s, shortDate: true, trailing: Icon(LucideIcons.plus, size: 18, color: pal.accent), onTap: () => _add('${s['id']}', '${s['title']}')),
        ],
      ]),
    );
  }
}
