// Словарная статья на всю высоту (DictionaryBottomSheet.jsx): слово → список словарей, где есть статья → статья
// выбранного словаря. Статья Стронга: лемма, транслитерация, произношение, значение, происхождение со ссылками
// на другие номера, грамматическая форма слова в этом стихе, «Как переведено», «Все места».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'concordance_sheet.dart';
import 'interlinear.dart';
import 'lexicon.dart';
import 'morph.dart';
import 'sheet.dart';
import 'study_data.dart';

/// Слово оригинала, которому соответствует нажатое слово (из подстрочника)
class OrigInfo {
  const OrigInfo({required this.orig, this.morph, this.num});
  final String orig;
  final String? morph;
  final String? num;
}

class DictRequest {
  const DictRequest({
    required this.text,
    required this.strongs,
    required this.morph,
    required this.ref,
    required this.pane,
    this.preselect,
    this.autoOpen = false,
    this.origWord,
    this.wordIndex,
    this.fromInterlinear = false,
  });
  final String text;
  final List<String> strongs;
  final List<String> morph;
  final VerseRef ref;
  final int pane;
  final ({String moduleId, String key})? preselect; // словарь и статья, выбранные в выборке над словом
  final bool autoOpen; // сразу статья первого словаря Стронга (нажали на номер или слово подстрочника)
  final OrigInfo? origWord;
  final int? wordIndex; // номер слова в стихе RST+ (для формы слова по подстрочнику)
  final bool fromInterlinear; // открыто из подстрочника: «Назад» возвращает к нему
}

/// Открыть окно статьи: Стронг — на всю высоту, остальные словари — на половину экрана
Future<void> openDictionary(BuildContext context, DictRequest req, {bool full = false}) =>
    showSheet(context, DictionarySheet(req: req), size: full ? SheetSize.full : SheetSize.half);

/// Открыть место во второй панели (из первой) или в самой панели (из второй) и закрыть окна
void openRefInOther(BuildContext context, WidgetRef ref, int pane, VerseRef to) {
  final n = ref.read(panesProvider.notifier);
  if (pane == 0) {
    if (ref.read(panesProvider).length < 2) n.toggleSplit();
    n.navigate(1, to);
  } else {
    n.navigate(pane, to);
  }
  closeAllSheets(context);
}

class _StrongView {
  _StrongView(this.num, this.results);
  final String num;
  final List<ModResult> results;
}

class DictionarySheet extends ConsumerStatefulWidget {
  const DictionarySheet({super.key, required this.req});
  final DictRequest req;
  @override
  ConsumerState<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends ConsumerState<DictionarySheet> {
  late final LookupResult _res;
  String? _selected;
  final _stack = <_StrongView>[]; // переходы по ссылкам Стронга внутри статьи
  int _entryIdx = 0;
  OrigInfo? _orig;

  DictRequest get req => widget.req;

  @override
  void initState() {
    super.initState();
    _res = lookupWord(text: req.text, strongs: req.strongs, morph: req.morph, book: req.ref.book, chapter: req.ref.chapter, verse: req.ref.verse);
    final pre = req.preselect;
    _selected = pre?.moduleId;
    if (pre != null) {
      final found = _res.results.where((x) => x.module.id == pre.moduleId).firstOrNull?.found;
      if (found != null) _entryIdx = found.indexWhere((f) => f.key == pre.key).clamp(0, 1 << 20);
    } else if (req.autoOpen) {
      final first = _res.results.where((x) => StudyData.dictKind(x.module) == 'strongs').firstOrNull;
      if (first != null) _selected = first.module.id;
    }
    // Из подстрочника по оригиналу слово оригинала известно сразу; из чтения — по порядку слова в стихе
    if (req.origWord != null) {
      _orig = req.origWord;
    } else if (req.wordIndex != null) {
      final ws = ruInterlinear(req.ref);
      final w = ws != null && req.wordIndex! < ws.length ? ws[req.wordIndex!] : null;
      if (w != null && w.orig.isNotEmpty) _orig = OrigInfo(orig: w.orig, morph: w.origMorph, num: w.num);
    }
  }

  void _openStrong(String num) {
    final results = lookupStrong(num);
    if (results.isNotEmpty) {
      setState(() {
        _stack.add(_StrongView(num, results));
        _entryIdx = 0;
      });
    }
  }

  void _openRef(VerseRef r) => openRefInOther(context, ref, req.pane, r);

  void _openAll(String num, String? lemma) => openConcordance(context, num: num, lemma: lemma, onOpen: _openRef);

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final top = _stack.isEmpty ? null : _stack.last;
    final results = top?.results ?? _res.results;
    final mapping = top != null ? Mapping('exact', [top.num]) : _res.mapping;
    final current = results.where((r) => r.module.id == _selected).firstOrNull ?? (top != null ? results.first : null);

    // «Назад»: по ссылкам Стронга — к прошлой статье; из подстрочника — к нему; иначе из статьи — к списку словарей
    VoidCallback? back;
    if (top != null) {
      back = () => setState(() => _stack.removeLast());
    } else if (req.fromInterlinear) {
      back = () => Navigator.pop(context);
    } else if (_selected != null) {
      back = () => setState(() => _selected = null);
    }

    final children = <Widget>[];
    if (top == null) {
      if (mapping.mode == 'exact') {
        children.add(Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _OkBadge(t('Точная привязка')),
          for (final s in mapping.strongs) StrongChip(s),
        ]));
      } else if (mapping.mode == 'approx') {
        children.add(WarnBox(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${t('В переводе нет номеров Стронга. Примерные варианты по симфонии RST+:')} '),
            for (final s in mapping.strongs) WidgetSpan(child: StrongChip('$s · ${(mapping.weights[s]! * 100).round()}%')),
          ])),
        ));
      } else if (_res.results.isEmpty) {
        children.add(WarnBox(child: Text(t('Не нашли это слово в оригинале.'))));
      }
    }

    if (current == null && top == null) {
      if (_res.results.isEmpty) {
        children.add(Empty(
          icon: LucideIcons.bookText,
          title: t('Статей не найдено'),
          child: Column(children: [
            if (_res.dictionaryCount == 0) Text(t('Нет включённых словарей.')),
            if (Hub.openLibrary != null)
              LinkButton(t('Открыть библиотеку'), () {
                closeAllSheets(context);
                Hub.openLibrary!(context, ref, req.pane);
              }),
          ]),
        ));
      } else {
        // .dict-list: строки через 8 px (а не через 12, как блоки окна)
        children.add(Column(children: [
          for (final (i, r) in _res.results.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _DictRow(
              result: r,
              onTap: () => setState(() {
                _selected = r.module.id;
                _entryIdx = 0;
              }),
            ),
          ],
        ]));
      }
    }

    if (current != null) {
      if (top == null && results.length > 1) {
        children.add(TabsRow(
          labels: [for (final r in results) r.module.name],
          index: results.indexWhere((r) => r.module.id == current.module.id),
          onTap: (i) => setState(() {
            _selected = results[i].module.id;
            _entryIdx = 0;
          }),
        ));
      }
      if (current.found.length > 1) {
        children.add(TabsRow(
          sub: true,
          labels: [for (final f in current.found) '${f.key}${f.entry['lemma'] != null ? ' ${f.entry['lemma']}' : ''}'],
          index: _entryIdx.clamp(0, current.found.length - 1),
          onTap: (i) => setState(() => _entryIdx = i),
        ));
      }
      final f = current.found[_entryIdx.clamp(0, current.found.length - 1)];
      if (StudyData.dictKind(current.module) == 'strongs') {
        children.add(StrongEntry(
          key: ValueKey('${current.module.id}|${f.key}'),
          num: f.key,
          entry: f.entry,
          module: current.module,
          mapping: top != null ? null : mapping,
          orig: top != null ? null : _orig,
          onOpenStrong: _openStrong,
          onOpenRef: _openRef,
          onOpenAll: () => _openAll(f.key, f.entry['lemma'] as String?),
        ));
      } else {
        children.addAll(_wordEntry(pal, current, f));
      }
    }

    return SheetScaffold(
      title: top != null ? t('Статья {num}', {'num': top.num}) : t('Слово: {word}', {'word': req.text}),
      subtitle: fmtRef(req.ref),
      onBack: back,
      body: SheetList(children: children),
    );
  }

  List<Widget> _wordEntry(Palette pal, ModResult current, Found f) {
    final e = f.entry;
    final refs = (e['refs'] as List?)?.cast<String>() ?? const [];
    return [
      Text((e['word'] ?? f.key).toString(), style: const TextStyle(fontSize: 22.4, fontWeight: FontWeight.w700)),
      if (f.match == 'stem') WarnBox(icon: false, child: Text(t('Найдено по основе «{word}» — возможно, это другое слово.', {'word': req.text}))),
      if (f.match == 'root') WarnBox(icon: false, child: Text(t('Найдено по корню «{word}».', {'word': req.text}))),
      if (e['original'] != null) Text(e['original'].toString(), style: const TextStyle(fontSize: 36.8, height: 1.25)),
      LinkedText(text: (e['text'] ?? e['definition'] ?? '').toString(), onOpen: _openRef, style: const TextStyle(height: 1.55)),
      if (refs.isNotEmpty)
        ChipWrap([
          for (final r in refs)
            if (parseOsisRef(r) case final p?) AobChip(label: fmtOsis(p), icon: LucideIcons.link2, onTap: () => _openRef(p.start)),
        ]),
      SourceNote('${current.module.name} · ${current.module.meta['license'] ?? ''}'),
    ];
  }
}

/// .badge.ok: цвет --ok (в тёмных темах светлее), фон — 15% этого цвета
class _OkBadge extends ConsumerWidget {
  const _OkBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ok = paletteOf(ref).dark ? const Color(0xFF7CC68A) : const Color(0xFF2F6339);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: ok.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: ok)),
    );
  }
}

/// Номер Стронга плашкой
class StrongChip extends ConsumerWidget {
  const StrongChip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: tint(pal.accent, pal.panel, 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12.7, color: pal.accent, fontFamily: 'monospace')),
    );
  }
}

class _DictRow extends ConsumerWidget {
  const _DictRow({required this.result, required this.onTap});
  final ModResult result;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final r = result;
    final kind = StudyData.dictKind(r.module) == 'strongs' ? t('по номерам Стронга') : t('по словам');
    final desc = '${r.found.map((f) => f.label.isEmpty ? f.key : f.label).join(' · ')}${r.found.any((f) => f.match == 'stem') ? ' · ${t('по основе слова')}' : ''}';
    return Material(
      color: pal.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(LucideIcons.bookText, size: 20, color: pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.module.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(desc, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(color: pal.muted, fontSize: 14.1)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(r.found.length > 1 ? t('{n} статьи', {'n': '${r.found.length}'}) : kind, style: TextStyle(color: pal.muted, fontSize: 12.8)),
          ]),
        ),
      ),
    );
  }
}

/// Статья словаря по номерам Стронга
class StrongEntry extends ConsumerWidget {
  const StrongEntry({super.key, required this.num, required this.entry, required this.module, required this.mapping, required this.orig, required this.onOpenStrong, required this.onOpenRef, required this.onOpenAll});
  final String num;
  final Map<String, dynamic> entry;
  final dynamic module; // InstalledModule
  final Mapping? mapping;
  final OrigInfo? orig;
  final void Function(String) onOpenStrong;
  final OpenRef onOpenRef;
  final VoidCallback onOpenAll;

  // «от H24 (אָבִיב)» → кликабельные номера Стронга
  Widget _strongLinks(String text, TextStyle? style) {
    final parts = <(String, VoidCallback?)>[];
    var last = 0;
    for (final m in RegExp(r'[HG]\d+').allMatches(text)) {
      if (m.start > last) parts.add((text.substring(last, m.start), null));
      final n = m.group(0)!;
      parts.add((n, () => onOpenStrong(n)));
      last = m.end;
    }
    if (last < text.length) parts.add((text.substring(last), null));
    return LinkSpans(parts: parts, style: style);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final isHeb = num.startsWith('H');
    // orig — слово в оригинале стиха (из подстрочника): точная форма с лицом, числом и падежом
    final exact = orig != null && orig!.num == num.replaceFirstMapped(RegExp(r'^([HG])0*'), (m) => m.group(1)!) ? orig : null;
    final morph = exact != null ? const <String>[] : (mapping?.mode == 'exact' ? mapping!.morph : const <String>[]);
    final dir = isHeb ? TextDirection.rtl : TextDirection.ltr;
    final lemma = entry['lemma'] as String?;
    final facts = <(String, Widget)>[
      (t('Номер Стронга'), Text(num, style: const TextStyle(fontWeight: FontWeight.w500, fontFamily: 'monospace', fontSize: 13.5))),
      if (entry['xlit'] != null) (t('Транслитерация'), Text('${entry['xlit']}', style: const TextStyle(fontWeight: FontWeight.w500))),
      if (entry['pron'] != null) (t('Произношение'), Text('${entry['pron']}', style: const TextStyle(fontWeight: FontWeight.w500))),
      (t('Язык'), Text(isHeb ? t('иврит / арамейский (ВЗ)') : t('греческий (НЗ)'), style: const TextStyle(fontWeight: FontWeight.w500))),
      if (exact != null)
        (
          t('В этом стихе'),
          Text.rich(TextSpan(children: [
            WidgetSpan(child: Directionality(textDirection: dir, child: Text(exact.orig, style: const TextStyle(fontWeight: FontWeight.w500)))),
            if (exact.morph != null && describeMorph(exact.morph!) != null) TextSpan(text: ' — ${describeMorph(exact.morph!)}'),
          ])),
        ),
      for (final m in morph)
        (
          t('Грамматическая форма'),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${describeMorph(m) ?? t('без расшифровки')} ', style: const TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: '($m)', style: TextStyle(color: pal.muted, fontFamily: 'monospace', fontSize: 13.5)),
          ])),
        ),
    ];
    final renderings = (entry['renderings'] as List?)?.cast<List>();
    final refs = (entry['refs'] as List?)?.cast<String>();
    final bodyStyle = const TextStyle(height: 1.55);
    Widget section(String title, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [H4(title), child]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lemma != null && lemma.isNotEmpty)
        Align(
          alignment: isHeb ? Alignment.centerRight : Alignment.centerLeft,
          child: Directionality(textDirection: dir, child: Text(lemma, style: TextStyle(fontSize: 36.8, height: 1.25, color: pal.text))),
        ),
      const SizedBox(height: 12),
      _Facts(facts),
      if (entry['definition'] != null) ...[const SizedBox(height: 12), section(t('Значение'), _strongLinks('${entry['definition']}', bodyStyle))],
      if (entry['derivation'] != null) ...[const SizedBox(height: 12), section(t('Происхождение'), _strongLinks('${entry['derivation']}', bodyStyle))],
      if (entry['kjv'] != null) ...[const SizedBox(height: 12), section(t('Переводы в KJV'), Text('${entry['kjv']}', style: bodyStyle))],
      if (renderings != null && renderings.isNotEmpty) ...[
        const SizedBox(height: 12),
        section(
          t('Как переведено в синодальном тексте · {n} употр.', {'n': '${entry['count']}'}),
          Column(children: [
            for (final r in renderings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(flex: 4, child: Text('${r[0]}', maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 14.7))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(builder: (context, box) {
                      final w = ((r[1] as int) / (renderings.first[1] as int) * 100).clamp(4, 100) / 100;
                      return Stack(children: [
                        Container(height: 6, decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3))),
                        Container(height: 6, width: box.maxWidth * w, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(3))),
                      ]);
                    }),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 36, child: Text('${r[1]}', textAlign: TextAlign.right, style: TextStyle(color: pal.muted, fontSize: 13.6))),
                ]),
              ),
          ]),
        ),
      ],
      if (entry['text'] != null) ...[const SizedBox(height: 12), Text('${entry['text']}', style: bodyStyle)],
      if (refs != null && refs.isNotEmpty) ...[
        const SizedBox(height: 12),
        section(
          renderings != null ? t('Где встречается') : t('Связанные стихи'),
          ChipWrap([
            for (final r in refs)
              if (parseOsisRef(r) case final p?) Chip2(fmtOsis(p), onTap: () => onOpenRef(p.start)),
          ]),
        ),
      ],
      // Места употребления — после вариантов перевода
      const SizedBox(height: 12),
      WordStatsBlock(num: num, onOpenRef: onOpenRef, onOpenAll: onOpenAll),
      const SizedBox(height: 12),
      SourceNote('${module.name}${module.language == 'en' ? ' · ${t('на английском')}' : ''} · ${module.meta['license'] ?? ''}'),
    ]);
  }
}

class _Facts extends ConsumerWidget {
  const _Facts(this.items);
  final List<(String, Widget)> items;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
      child: LayoutBuilder(builder: (context, box) {
        final cols = ((box.maxWidth + 16) / (170 + 16)).floor().clamp(1, 4);
        final w = (box.maxWidth - 16 * (cols - 1)) / cols;
        return Wrap(spacing: 16, runSpacing: 10, children: [
          for (final (label, value) in items)
            SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 13.1, color: pal.muted)),
                const SizedBox(height: 2),
                value,
              ]),
            ),
        ]);
      }),
    );
  }
}

/// Блок статистики слова в статье Стронга: число употреблений, книги (полосы), все места
class WordStatsBlock extends ConsumerStatefulWidget {
  const WordStatsBlock({super.key, required this.num, required this.onOpenRef, required this.onOpenAll});
  final String num;
  final OpenRef onOpenRef;
  final VoidCallback onOpenAll;
  @override
  ConsumerState<WordStatsBlock> createState() => _WordStatsBlockState();
}

class _WordStatsBlockState extends ConsumerState<WordStatsBlock> {
  WordStats? _st;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    loadStats(widget.num).then((r) {
      if (mounted) {
        setState(() {
          _st = r;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    if (!_loaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Spinner(size: 16, color: pal.muted),
          const SizedBox(width: 10),
          Text(t('Считаю…'), style: TextStyle(color: pal.muted, fontSize: 14)),
        ]),
      );
    }
    final st = _st;
    if (st == null || st.total == 0) return const SizedBox.shrink();
    final max = st.byBook.map((b) => b.$2).reduce((a, b) => a > b ? a : b);
    final order = {for (final (i, b) in st.byBook.indexed) b.$1: i};
    final top = ([...st.byBook]..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : order[a.$1]!.compareTo(order[b.$1]!))).take(10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      H4(t('Употребление в {module}: {total} раз в {verses} стихах, {books} книгах', {'module': st.module, 'total': '${st.total}', 'verses': '${st.verses}', 'books': '${st.byBook.length}'}), icon: LucideIcons.chartColumn),
      for (final b in top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            SizedBox(width: 56, child: Text(Books.instance.meta(b.$1).short.replaceAll(RegExp(r'\.$'), ''), maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(color: pal.muted, fontSize: 13.6))),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final w = (b.$2 / max * 100).clamp(3, 100) / 100;
                return Stack(children: [
                  Container(height: 8, decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4))),
                  Container(height: 8, width: box.maxWidth * w, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(4))),
                ]);
              }),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 36, child: Text('${b.$2}', textAlign: TextAlign.right, style: TextStyle(color: pal.muted, fontSize: 13.6))),
          ]),
        ),
      if (st.byBook.length > top.length) Padding(padding: const EdgeInsets.only(top: 4), child: Text(t('И ещё в {n} книгах.', {'n': '${st.byBook.length - top.length}'}), style: TextStyle(color: pal.muted, fontSize: 13.6))),
      const SizedBox(height: 8),
      ChipWrap([for (final r in st.refs.take(24)) Chip2(fmtRef(r.$1), onTap: () => widget.onOpenRef(r.$1))]),
      const SizedBox(height: 8),
      BigButton(t('Все места ({n})', {'n': '${st.verses}'}), onTap: widget.onOpenAll),
    ]);
  }
}
