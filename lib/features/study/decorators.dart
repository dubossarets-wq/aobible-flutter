// Значки у стиха: параллельные места [⇅ n], иллюстрация; комментарии — названиями после стиха («Лопухин»; нажатие
// раскрывает текст под стихом) или прежней меткой («Лопухин», открывает окно комментариев).
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
  final cfg = ref.watch(settingsProvider.select((s) => (s.get<bool>('showXrefButtons') && s.j['focusMode'] != true, s.get<bool>('showIllustrations'), s.j['bookMode'] == true, s.j['inlineCommentaries'], s.d('fontSize'), s.get<String>('commentView'))));
  final (showXref, showIllus, bookMode, inline, fs, view) = cfg; // в режиме чтения [⇅ n] скрыты, как в веб-версии
  Widget? below;
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
      final shown = [
        for (final (id, name) in list)
          if (!(inline is List && !inline.contains(id)) && !(lang != null && (ModuleStore.instance.get(id)?.language ?? lang) != lang)) (id, name),
      ];
      if (view != 'tag' && shown.isNotEmpty) {
        // почти незаметный значок-облачко после текста стиха (число — если источников несколько); нажатие раскрывает
        // текст под стихом, повторное — сворачивает. Введение к книге или главе — одна из вкладок у первого стиха
        final ids = {for (final (id, _) in shown) id};
        final entries = <CommentEntry>[];
        for (final r in StudyData.commentaryFor(at)) {
          if (!ids.contains(r.module.id)) continue;
          for (final intr in [true, false]) {
            final items = [for (final e in r.items) if (_isIntro(e.title) == intr) e];
            if (items.isEmpty) continue;
            entries.add((
              id: r.module.id,
              short: intr ? items.first.title : r.module.name, // после стиха: «Лопухин», у введения — «Введение в книгу»
              name: r.module.title.isNotEmpty ? r.module.title : r.module.name, // название книги: «Толковая Библия Лопухина»
              label: intr ? items.first.title : null,
              text: items.map((e) => e.text).join('\n\n'),
              onOpen: () => openCommentary(context, pane: pane, at: at, moduleId: r.module.id),
            ));
          }
        }
        if (entries.isNotEmpty) {
          // после стиха — короткие названия источников мелким приглушённым текстом; раскрытый — цветом акцента
          final myKey = '$pane|$book.${item.chapter}.${item.verse}';
          final cur = openComment.value;
          final isOpen = cur != null && cur.key == myKey && !cur.closing;
          final f = fs * 0.68;
          for (var i = 0; i < entries.length; i++) {
            final on = isOpen && cur.sel == i;
            spans.add(_btn(
              onTap: () => openComment.value = on ? (key: myKey, sel: i, closing: true) : (key: myKey, sel: i, closing: false),
              label: t('Комментарий: {name}', {'name': entries[i].name}),
              margin: f * (i == 0 ? 0.35 : 0.5),
              child: Text(entries[i].short, style: TextStyle(fontSize: f, height: 1, fontWeight: FontWeight.w600, color: on ? pal.accent : pal.muted.withValues(alpha: 0.8))),
            ));
          }
          if (cur != null && cur.key == myKey) below = CommentPanel(key: ValueKey(myKey), myKey: myKey, entries: entries);
        }
      }
      for (final (id, name) in view == 'tag' ? shown : const <(String, String)>[]) {
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
  return spans.isEmpty && below == null ? null : VerseDecor(trailing: spans, below: below);
}

// «Введение в книгу», «Введение к главе», «Introduction» — статьи, которые при сборке модуля поставлены к первому стиху
bool _isIntro(String title) => title.startsWith('Введение') || title == 'Introduction';

InlineSpan _btn({required VoidCallback onTap, required String label, required Widget child, required double margin}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Padding(padding: EdgeInsets.only(left: margin), child: child)),
      ),
    );

typedef CommentEntry = ({String id, String short, String name, String? label, String text, VoidCallback onOpen});

/// Раскрытый комментарий под стихом (.vc-panel в веб-версии): заголовок — название книги, текст с линией акцента слева.
/// Какой из комментариев стиха — openComment.sel (его выбирают названием после стиха). Плавно раскрывается при появлении;
/// нажатие на текст или повторно на название — плавно сворачивается. Долгое нажатие — окно комментариев (там ссылки)
class CommentPanel extends ConsumerStatefulWidget {
  const CommentPanel({super.key, required this.myKey, required this.entries});
  final String myKey;
  final List<CommentEntry> entries;
  @override
  ConsumerState<CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends ConsumerState<CommentPanel> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  late final _a = CurvedAnimation(parent: _c, curve: Curves.fastOutSlowIn);
  late int _sel = openComment.value?.sel ?? 0;

  @override
  void initState() {
    super.initState();
    openComment.addListener(_onOpen);
  }

  @override
  void dispose() {
    openComment.removeListener(_onOpen);
    _c.dispose();
    super.dispose();
  }

  void _onOpen() {
    final cur = openComment.value;
    if (cur == null || cur.key != widget.myKey) return;
    if (!cur.closing) {
      // выбрали другое название у того же стиха — сменить текст (а если сворачивался — раскрыть снова)
      if (cur.sel != _sel) setState(() => _sel = cur.sel);
      if (_c.status == AnimationStatus.reverse || _c.status == AnimationStatus.dismissed) _c.forward();
      return;
    }
    if (_c.status == AnimationStatus.reverse) return;
    // сворачивание: доигрываем анимацию, потом снимаем признак — панель уходит из читалки
    _c.reverse().whenComplete(() {
      final now = openComment.value;
      if (now != null && now.key == widget.myKey && now.closing) openComment.value = null;
    });
  }

  void _close() => openComment.value = (key: widget.myKey, sel: _sel, closing: true);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = s.palette;
    final fs = s.d('commentaryFontSize');
    final e = widget.entries[_sel.clamp(0, widget.entries.length - 1)];
    return SizeTransition(
      sizeFactor: _a,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _a,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          onLongPress: e.onOpen,
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.accent, width: 3))),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topCenter,
              child: Column(key: ValueKey(_sel), crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(e.label == null ? e.name : '${e.label} · ${e.name}', style: TextStyle(fontSize: 12.8, height: 1.3, fontWeight: FontWeight.w700, color: pal.accent)),
                ),
                Text(e.text, style: TextStyle(fontSize: fs, height: 1.6, color: pal.text.withValues(alpha: 0.86))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
