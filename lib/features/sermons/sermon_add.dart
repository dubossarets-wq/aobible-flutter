// «Добавить в проповедь» (SermonAddSheet.jsx): выбор проповеди или новая проповедь; выделенные стихи добавляются сами.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../plans/loc.dart';
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
    final pal = ref.watch(settingsProvider).palette;
    final sermons = ref.watch(sermonsProvider);
    final done = _done;
    if (done != null) {
      final parts = t('{ref} — в проповеди «{title}».', {'ref': '\u0000', 'title': done.title}).split('\u0000');
      return PageFrame(
        pal: pal,
        title: t('Добавлено'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Center(child: Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3AA66B).withValues(alpha: 0.16)), child: const Icon(Icons.check, size: 38, color: Color(0xFF3AA66B))))),
            Text.rich(
              TextSpan(children: [TextSpan(text: parts.first), TextSpan(text: _label, style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: parts.length > 1 ? parts.last : '')]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: pal.text, height: 1.4),
            ),
            const SizedBox(height: 18),
            Pill(
              pal: pal,
              primary: true,
              expand: true,
              icon: Icons.article_outlined,
              label: t('Открыть проповедь'),
              onTap: () {
                final nav = Navigator.of(context);
                final ctx = nav.context;
                nav.pop();
                showPage(ctx, (_) => SermonsSheet(pane: widget.pane, open: done.id));
              },
            ),
            const SizedBox(height: 8),
            Pill(pal: pal, expand: true, label: t('Читать дальше'), onTap: () => Navigator.of(context).pop()),
          ]),
        ),
      );
    }
    return PageFrame(
      pal: pal,
      title: t('Добавить в проповедь'),
      subtitle: _label,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(sermons.isNotEmpty ? t('Новая проповедь') : t('Назовите проповедь'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.muted)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _title,
              autofocus: sermons.isEmpty,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createAndAdd(),
              style: TextStyle(color: pal.text),
              decoration: InputDecoration(hintText: t('Например: Благодать Божья'), filled: true, fillColor: pal.bg, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: pal.line))),
            ),
          ),
          const SizedBox(width: 8),
          Pill(pal: pal, primary: true, icon: Icons.add, label: t('Создать'), onTap: _createAndAdd),
        ]),
        if (sermons.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(t('Или выберите проповедь'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text)),
          const SizedBox(height: 10),
          for (final s in sermons) SermonRow(pal: pal, sermon: s, shortDate: true, trailing: Icon(Icons.add, color: pal.muted), onTap: () => _add('${s['id']}', '${s['title']}')),
        ],
      ]),
    );
  }
}
