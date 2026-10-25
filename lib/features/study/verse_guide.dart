// «Всё о стихе» (VerseGuide.jsx): на одном экране — ваши пометки, слова оригинала, комментарии,
// параллельные места, места на карте. Стили — .guide-* / .gw-* из styles.css.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../../ui/kit.dart';
import '../bookmarks/marks.dart' show hlColor, hlColors, marksProvider, refKey;
import '../bookmarks/sheets.dart' as bm show showNoteSheet;
import '../maps/map_screen.dart' show openPlaceMap;
import '../maps/places_data.dart' show Place, PlaceStore;
import 'commentary_sheet.dart';
import 'dictionary_sheet.dart';
import 'interlinear.dart';
import 'lexicon.dart';
import 'sheet.dart';
import 'study_data.dart';

Future<void> openVerseGuide(BuildContext context, WidgetRef ref, int pane, VerseRef at, String moduleId) =>
    showSheet(context, VerseGuideSheet(pane: pane, at: at, moduleId: moduleId), size: SheetSize.tall);

class _Word {
  _Word(this.token, this.num, this.lemma, this.xlit, this.def);
  final Token token;
  final String num;
  final String? lemma, xlit, def;
}

class _Data {
  _Data(this.text, this.words, this.comm, this.xrefs, this.places, this.tagged);
  final String text;
  final List<_Word> words;
  final List<({InstalledModule module, List<({String key, OsisRef ref, String title, String text})> items})> comm;
  final List<({String osis, OsisRef ref, String text})> xrefs;
  final List<Place> places;
  final String? tagged;
}

class VerseGuideSheet extends ConsumerStatefulWidget {
  const VerseGuideSheet({super.key, required this.pane, required this.at, required this.moduleId});
  final int pane;
  final VerseRef at;
  final String moduleId;
  @override
  ConsumerState<VerseGuideSheet> createState() => _VerseGuideSheetState();
}

class _VerseGuideSheetState extends ConsumerState<VerseGuideSheet> {
  _Data? _d;

  @override
  void initState() {
    super.initState();
    Future(() async {
      await StudyData.ensure();
      final d = _load();
      if (mounted) setState(() => _d = d);
    });
  }

  _Data _load() {
    final at = widget.at;
    final text = plainOf(StudyData.verse(widget.moduleId, at) ?? '');
    // Слова оригинала — из перевода со Стронгом (RST+)
    final tagged = ModuleStore.instance.bibles.where((m) => m.features['strongs'] == true && m.language == 'ru').firstOrNull;
    final raw = tagged == null ? null : StudyData.verse(tagged.id, at);
    final words = <_Word>[];
    for (final tk in raw == null ? const <Token>[] : parseVerse(raw)) {
      if (!tk.tagged) continue;
      final num = tk.strongs.first;
      if (words.any((w) => w.num == num)) continue;
      final res = lookupStrong(num);
      final lex = res.where((r) => r.module.id.startsWith('strongs-')).firstOrNull ?? res.firstOrNull;
      final e = lex?.found.firstOrNull?.entry;
      final rend = e?['renderings'];
      words.add(_Word(tk, num, e?['lemma'] as String?, e?['xlit'] as String?, (e?['definition'] as String?) ?? (rend is List && rend.isNotEmpty ? '${(rend.first as List).first}' : null)));
    }
    final xrefs = <({String osis, OsisRef ref, String text})>[];
    for (final x in StudyData.refsForVerse(widget.moduleId, at).take(8)) {
      final (parts, _) = StudyData.textForRef(widget.moduleId, x.ref, maxVerses: 1);
      xrefs.add((osis: x.osis, ref: x.ref, text: parts.map((p) => p.text).join(' ')));
    }
    List<Place> places;
    try {
      places = PlaceStore.inVerse(at);
    } catch (_) {
      places = const [];
    }
    final seen = <String>{};
    return _Data(text, words, StudyData.commentaryFor(at), xrefs, [for (final p in places) if (seen.add(p.id)) p], tagged?.name);
  }

  void _go(VerseRef r) => openRefInOther(context, ref, widget.pane, r);

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final at = widget.at;
    final key = refKey(at);
    final marks = ref.watch(marksProvider);
    final d = _d;
    final children = <Widget>[];
    if (d == null) {
      children.add(Loading(t('Загрузка…')));
    } else {
      children.add(QuoteBox(d.text));
      final note = marks.notes[key] as Map?;
      final hl = marks.highlights[key];
      final cols = [
        for (final c in marks.collections)
          if ((c['items'] as List).any((x) => x['book'] == at.book && x['chapter'] == at.chapter && x['verse'] == at.verse)) '${c['name']}',
      ];
      if (note != null || hl != null || cols.isNotEmpty) {
        final c = hlColor(hl);
        final label = c == null ? '' : (marks.hlLabels[c.id]?.trim().isNotEmpty == true ? marks.hlLabels[c.id]!.trim() : t(c.name));
        children.add(_Sec(LucideIcons.notebookPen, t('Ваши пометки'), [
          if (hl != null)
            Row(children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: c?.color ?? hlColors.first.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(label)),
            ]),
          if (note != null) _Card(onTap: () => bm.showNoteSheet(context, [at], widget.moduleId), child: Text('${note['text'] ?? ''}')),
          if (cols.isNotEmpty) Text(t('В подборках: {names}', {'names': cols.join(', ')}), style: TextStyle(color: pal.muted, fontSize: 12.9)),
        ]));
      }
      if (d.words.isNotEmpty) {
        children.add(_Sec(LucideIcons.languages, t('Слова оригинала · по {module}', {'module': d.tagged ?? ''}), [
          LayoutBuilder(builder: (context, box) {
            // grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap 6
            final n = ((box.maxWidth + 6) / 156).floor().clamp(1, 8);
            final w = (box.maxWidth - 6 * (n - 1)) / n;
            return Wrap(spacing: 6, runSpacing: 6, children: [for (final x in d.words) SizedBox(width: w, child: _WordCard(x, () => _openWord(x)))]);
          }),
        ]));
      }
      if (d.comm.isNotEmpty) {
        children.add(_Sec(LucideIcons.messageSquareText, t('Комментарии'), [
          for (final c in d.comm)
            _Card(
              onTap: () => openCommentary(context, pane: widget.pane, at: at, moduleId: c.module.id),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: c.module.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ${_cut(c.items.firstOrNull?.text ?? '')}'),
              ])),
            ),
        ]));
      }
      if (d.xrefs.isNotEmpty) {
        children.add(_Sec(LucideIcons.link2, t('Параллельные места'), [
          for (final x in d.xrefs)
            _Card(
              onTap: () => _go(x.ref.start),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: fmtOsis(x.ref), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ${x.text}'),
              ])),
            ),
        ]));
      }
      if (d.places.isNotEmpty) {
        children.add(_Sec(LucideIcons.mapPin, t('Места на карте'), [
          ChipWrap([
            for (final p in d.places)
              AobChip(label: p.name, icon: LucideIcons.mapPin, onTap: () {
                closeAllSheets(context);
                openPlaceMap(context, p);
              }),
          ]),
        ]));
      }
    }
    return SheetScaffold(title: t('Всё о стихе · {ref}', {'ref': fmtRef(at)}), body: SheetList(children: children));
  }

  static String _cut(String s) => s.length > 220 ? '${s.substring(0, 220)}…' : s;

  void _openWord(_Word w) {
    final req = DictRequest(text: w.token.text, strongs: w.token.strongs, morph: w.token.morph, ref: widget.at, pane: widget.pane);
    showSheet(context, DictionarySheet(req: req), size: SheetSize.normal);
  }
}

/// .guide-sec: заголовок с значком 13 px и строки через 6 px
class _Sec extends ConsumerWidget {
  const _Sec(this.icon, this.title, this.children);
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: H4(title, icon: icon)),
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 6), c],
      ]);
}

/// .guide-card
class _Card extends ConsumerWidget {
  const _Card({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Material(
      color: pal.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Align(alignment: Alignment.centerLeft, child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 15.2, height: 1.45), child: child)),
        ),
      ),
    );
  }
}

/// .guide-word: русское слово, слово оригинала, «номер · чтение · значение»
class _WordCard extends ConsumerWidget {
  const _WordCard(this.w, this.onTap);
  final _Word w;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final heb = w.num.startsWith('H');
    final meta = '${w.num}${w.xlit != null ? ' · ${w.xlit}' : ''}${w.def != null ? ' · ${w.def}' : ''}';
    return Material(
      color: pal.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.token.text, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (w.lemma != null)
              SizedBox(
                width: double.infinity,
                child: Directionality(
                  textDirection: heb ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(w.lemma!, textAlign: heb ? TextAlign.right : TextAlign.left, style: TextStyle(fontFamily: heb ? 'Noto Serif Hebrew' : null, fontSize: 18.4)),
                ),
              ),
            Text(meta, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 12, color: pal.muted)),
          ]),
        ),
      ),
    );
  }
}
