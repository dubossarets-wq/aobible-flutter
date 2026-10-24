// Значки у стиха: параллельные места [⇅ n], иллюстрация, пометка комментария («Лопухин»).
// Как в ChapterView.jsx: после стиха, в порядке — параллельные места, иллюстрация, комментарии.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'commentary_sheet.dart';
import 'image_viewer.dart';
import 'study_data.dart';
import 'xrefs_sheet.dart';

VerseDecor? studyDecorator(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book) {
  if (item.kind != ItemKind.verse) return null;
  final cfg = ref.watch(settingsProvider.select((s) => (s.get<bool>('showXrefButtons'), s.get<bool>('showIllustrations'), s.j['bookMode'] == true, s.j['inlineCommentaries'], s.d('fontSize'))));
  final (showXref, showIllus, bookMode, inline, fs) = cfg;
  final key = item.chapter * 1000 + item.verse;
  final at = VerseRef(book, item.chapter, item.verse);
  final spans = <InlineSpan>[];
  final pal = ref.read(settingsProvider).palette;

  final n = showXref ? (StudyData.xrefCounts(moduleId, book)[key] ?? 0) : 0;
  if (n > 0) {
    spans.add(_btn(
      onTap: () => openXrefs(context, pane: pane, moduleId: moduleId, at: at),
      label: t('Параллельные места: {n}', {'n': '$n'}),
      child: Text('[⇅ $n]', style: TextStyle(fontSize: fs * 0.72, fontStyle: FontStyle.italic, color: pal.muted, height: 1)),
    ));
  }
  final ill = showIllus && !bookMode ? (StudyData.illustrationCounts(book)[key] ?? 0) : 0;
  if (ill > 0) {
    spans.add(_btn(
      onTap: () => openImageViewer(context, at: at, items: StudyData.illustrationsFor(at)),
      label: t('Иллюстрация к стиху'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_outlined, size: fs * 0.8, color: pal.accent),
          if (ill > 1) Text('2', style: TextStyle(fontSize: fs * 0.56, fontWeight: FontWeight.w600, color: pal.accent, height: 1)),
        ]),
      ),
    ));
  }
  if (!bookMode) {
    final list = StudyData.commentaryIndex(book)[key];
    if (list != null) {
      for (final (id, name) in list) {
        if (inline is List && !inline.contains(id)) continue;
        spans.add(_btn(
          onTap: () => openCommentary(context, pane: pane, at: at, moduleId: id),
          label: t('Комментарий: {name}', {'name': name}),
          child: Transform.translate(offset: Offset(0, -fs * 0.28), child: Text(name, style: TextStyle(fontSize: fs * 0.62, fontWeight: FontWeight.w700, color: pal.muted, height: 1))),
        ));
      }
    }
  }
  return spans.isEmpty ? null : VerseDecor(trailing: spans);
}

InlineSpan _btn({required VoidCallback onTap, required String label, required Widget child}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child)),
      ),
    );
