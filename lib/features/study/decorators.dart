// Значки у стиха: параллельные места [⇅ n], иллюстрация, пометка комментария («Лопухин»).
// Как в ChapterView.jsx: после стиха, в порядке — параллельные места, иллюстрация, комментарии.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart' show ModuleStore;
import '../../core/settings.dart';
import '../../ui/kit.dart' show LucideIcons;
import '../hub.dart';
import 'commentary_sheet.dart';
import 'image_viewer.dart';
import 'study_data.dart';
import 'xrefs_sheet.dart';

VerseDecor? studyDecorator(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book) {
  if (item.kind != ItemKind.verse) return null;
  final cfg = ref.watch(settingsProvider.select((s) => (s.get<bool>('showXrefButtons') && s.j['focusMode'] != true, s.get<bool>('showIllustrations'), s.j['bookMode'] == true, s.j['inlineCommentaries'], s.d('fontSize'))));
  final (showXref, showIllus, bookMode, inline, fs) = cfg; // в режиме чтения [⇅ n] скрыты, как в веб-версии
  final key = item.chapter * 1000 + item.verse;
  final at = VerseRef(book, item.chapter, item.verse);
  final spans = <InlineSpan>[];
  final pal = ref.read(settingsProvider).palette;

  // Отступы — в долях размера шрифта стиха, как em в .xr / .il / .cm (styles.css); размеры самих значков — от своего font-size
  final n = showXref ? (StudyData.xrefCounts(moduleId, book)[key] ?? 0) : 0;
  if (n > 0) {
    // .xr: курсив .72em, цвет muted, margin-left .2em, padding .1em .25em
    final f = fs * 0.72;
    spans.add(_btn(
      onTap: () => openXrefs(context, pane: pane, moduleId: moduleId, at: at),
      label: t('Параллельные места: {n}', {'n': '$n'}),
      margin: f * 0.2,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: f * 0.25, vertical: f * 0.1),
        child: Text('[⇅ $n]', style: TextStyle(fontSize: f, fontStyle: FontStyle.italic, color: pal.muted, height: 1)),
      ),
    ));
  }
  final ill = showIllus && !bookMode ? (StudyData.illustrationCounts(book)[key] ?? 0) : 0;
  if (ill > 0) {
    // .il: .62em, padding 0 .25em, высота 1.15em, скругление 5, фон accent 13%, значок 1.45em, цифра .9em
    final f = fs * 0.62;
    spans.add(_btn(
      onTap: () => openImageViewer(context, at: at, items: StudyData.illustrationsFor(at)),
      label: t('Иллюстрация к стиху'),
      margin: f * 0.3,
      child: Container(
        height: f * 1.15,
        padding: EdgeInsets.symmetric(horizontal: f * 0.25),
        decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.image, size: f * 1.45, color: pal.accent),
          if (ill > 1) Padding(padding: const EdgeInsets.only(left: 1), child: Text('2', style: TextStyle(fontSize: f * 0.9, fontWeight: FontWeight.w600, color: pal.accent, height: 1))),
        ]),
      ),
    ));
  }
  if (!bookMode) {
    final list = StudyData.commentaryIndex(book)[key];
    if (list != null) {
      // у стиха — только комментарии на языке этого перевода (у синодального — русские, у KJV — английские)
      final lang = ModuleStore.instance.get(moduleId)?.language;
      for (final (id, name) in list) {
        if (inline is List && !inline.contains(id)) continue;
        if (lang != null && (ModuleStore.instance.get(id)?.language ?? lang) != lang) continue;
        // .cm: .62em, жирный, muted, padding 0 .2em, margin-left .25em, приподнят на .45em
        final f = fs * 0.62;
        spans.add(_btn(
          onTap: () => openCommentary(context, pane: pane, at: at, moduleId: id),
          label: t('Комментарий: {name}', {'name': name}),
          margin: f * 0.25,
          child: Transform.translate(
            offset: Offset(0, -f * 0.45),
            child: Padding(padding: EdgeInsets.symmetric(horizontal: f * 0.2), child: Text(name, style: TextStyle(fontSize: f, fontWeight: FontWeight.w700, color: pal.muted, height: 1))),
          ),
        ));
      }
    }
  }
  return spans.isEmpty ? null : VerseDecor(trailing: spans);
}

InlineSpan _btn({required VoidCallback onTap, required String label, required Widget child, required double margin}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Padding(padding: EdgeInsets.only(left: margin), child: child)),
      ),
    );
