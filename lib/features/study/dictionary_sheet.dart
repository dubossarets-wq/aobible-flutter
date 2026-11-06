// Словарная статья на всю высоту (DictionaryBottomSheet.jsx): слово → список словарей, где есть статья → статья
// выбранного словаря. Статья Стронга: лемма, транслитерация, произношение, значение, происхождение со ссылками
// на другие номера, грамматическая форма слова в этом стихе, «Как переведено», «Все места».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart' show InstalledModule, ModuleStore;
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
import '../../ui/ios_style.dart';

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
    this.closeToParent = false,
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
  final bool closeToParent; // «×» — обратно в окно, откуда открыли (статья из проповеди), а не закрыть всё
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

/// Параллельное место — в новой панели сразу под той, откуда его открыли (openBelow в App.jsx). Панелей уже maxPanes (шесть) —
/// в панели под ней, у нижней — в ней самой (вернуться — «назад»)
void openRefBelow(BuildContext context, WidgetRef ref, int pane, VerseRef to) {
  final n = ref.read(panesProvider.notifier);
  final count = ref.read(panesProvider).length;
  if (count < maxPanes) {
    n.addPane(pane, to);
  } else {
    n.navigate(pane + 1 < count ? pane + 1 : pane, to);
  }
  closeAllSheets(context);
}

/// Подсказка над списком мест: куда откроется
String belowHint(int pane, int count) => count < maxPanes
    ? t('Место откроется в новой панели под этой.')
    : pane + 1 < count
        ? t('Место откроется в панели ниже.')
        : t('Место откроется здесь; вернуться — кнопкой «назад».');

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
    } else if (req.strongs.isNotEmpty && RegExp(r'[Ͱ-Ͽἀ-῿֐-׿]').hasMatch(req.text)) {
      // Нажали слово греческого или еврейского текста (LXX, Textus Receptus…): оно само и есть слово стиха —
      // в статье видно, что εἶπεν — форма словарного ἔπω
      _orig = OrigInfo(
        orig: req.text.replaceFirst(RegExp(r'[.,;:·!?»«“”()\[\]]+$'), ''),
        morph: req.morph.isEmpty ? null : req.morph.first,
        num: req.strongs.first.replaceFirstMapped(RegExp(r'^([HGhg])0*'), (m) => m.group(1)!.toUpperCase()),
      );
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
      if (mapping.mode == 'approx') {
        children.add(WarnBox(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${t('В переводе нет номеров Стронга. Примерные варианты по симфонии RST+:')} '),
            for (final s in mapping.strongs) WidgetSpan(child: StrongChip('$s · ${(mapping.weights[s]! * 100).round()}%')),
          ])),
        ));
      } else if (mapping.mode != 'exact' && _res.results.isEmpty) {
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
      onClose: req.closeToParent ? () => Navigator.pop(context) : null,
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
      color: iosUiNow ? iosCardAt(pal, IosElevated.of(context)) : pal.bg,
      shape: iosUiNow ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(iosRadius)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            AIcon(ico(LucideIcons.bookText), size: 20, color: pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.module.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(desc, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(color: pal.muted, fontSize: 14.1)),
              ]),
            ),
            const SizedBox(width: 12),
            // не шире 120 px и в две строки: при крупном шрифте подпись не выталкивает название словаря за край
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(r.found.length > 1 ? t('{n} статьи', {'n': '${r.found.length}'}) : kind, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12.8)),
            ),
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
    // как переведено в синодальном тексте — из Симфонии RST+, если у самого словаря этого нет
    final sym = module.id == symphonyId || entry['renderings'] != null ? null : StudyData.dictGet(symphonyId, num);
    final renderings = ((entry['renderings'] ?? sym?['renderings']) as List?)?.cast<List>();
    final refs = (entry['refs'] as List?)?.cast<String>();
    final lex = module.id == symphonyId ? const <(InstalledModule, Map<String, dynamic>)>[] : lexiconEntries(num);
    const bodyStyle = TextStyle(height: 1.55);
    const gap = SizedBox(height: 22);
    Widget section(String title, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SecTitle(title), child]);
    // строка шапки «В этом стихе …» / «Грамматическая форма …»
    Widget here(String label, InlineSpan value, {bool first = false}) => Container(
          margin: EdgeInsets.only(top: first ? 6 : 0),
          padding: EdgeInsets.only(top: first ? 10 : 6),
          decoration: first ? BoxDecoration(border: Border(top: BorderSide(color: pal.accent.withValues(alpha: 0.16)))) : null,
          // подпись — своей строкой, значение — под ней (как у разделов статьи)
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: pal.muted, fontSize: 13.1)),
            const SizedBox(height: 1),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 15.2, height: 1.45), children: [value])),
          ]),
        );
    final dot = TextSpan(text: '  ·  ', style: TextStyle(color: pal.muted.withValues(alpha: 0.6)));
    final meta = <InlineSpan>[
      if (entry['xlit'] != null) TextSpan(text: '${entry['xlit']}', style: TextStyle(fontStyle: FontStyle.italic, color: pal.text)),
      if (entry['pron'] != null && entry['pron'] != entry['xlit']) TextSpan(text: '${entry['pron']}'),
      TextSpan(text: num, style: TextStyle(color: pal.accent, fontFamily: 'monospace', fontSize: 13.6)),
      TextSpan(text: isHeb ? t('иврит / арамейский (ВЗ)') : t('греческий (НЗ)')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Шапка: слово оригинала крупно, под ним одной строкой — транслитерация, номер, язык; ниже — форма в этом стихе
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: iosUiNow ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius)) : BoxDecoration(color: tint(pal.accent, pal.panel, 0.07), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (lemma != null && lemma.isNotEmpty) ...[
            Align(
              alignment: isHeb ? Alignment.centerRight : Alignment.centerLeft,
              child: Directionality(textDirection: dir, child: Text(lemma, style: TextStyle(fontFamily: isHeb ? 'Noto Serif Hebrew' : null, fontSize: 40, height: 1.1, color: pal.text))),
            ),
            const SizedBox(height: 4),
          ],
          Text.rich(TextSpan(style: TextStyle(color: pal.muted, fontSize: 14.4, height: 1.4), children: [
            for (final (i, s) in meta.indexed) ...[if (i > 0) dot, s],
          ])),
          if (exact != null)
            here(
              t('В этом стихе'),
              TextSpan(children: [
                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: Directionality(textDirection: dir, child: Text(exact.orig, style: const TextStyle(fontSize: 15.2)))),
                if (exact.morph != null && describeMorph(exact.morph!) != null) TextSpan(text: ' — ${describeMorph(exact.morph!)}'),
              ]),
              first: true,
            ),
          for (final (i, m) in morph.indexed)
            here(
              t('Грамматическая форма'),
              TextSpan(children: [
                TextSpan(text: '${describeMorph(m) ?? t('без расшифровки')} '),
                TextSpan(text: '($m)', style: TextStyle(color: pal.muted, fontFamily: 'monospace', fontSize: 13.5)),
              ]),
              first: i == 0,
            ),
        ]),
      ),
      if (entry['definition'] != null) ...[gap, section(t('Значение'), _strongLinks('${entry['definition']}', const TextStyle(height: 1.55, fontSize: 17)))],
      if (entry['derivation'] != null) ...[gap, section(t('Происхождение'), _strongLinks('${entry['derivation']}', bodyStyle))],
      // толковый словарь (Дворецкий) — разделом в статье Стронга; в симфонии не повторяем
      for (final (m, e) in lex) ...[gap, LexSection(name: m.name, text: '${e['text']}')],
      if (renderings != null && renderings.isNotEmpty) ...[gap, section(t('В Синодальном переводе'), Renderings(renderings))],
      if (entry['text'] != null) ...[gap, Text('${entry['text']}', style: bodyStyle)],
      if (refs != null && refs.isNotEmpty) ...[
        gap,
        section(
          renderings != null ? t('Где встречается') : t('Связанные стихи'),
          ChipWrap([
            for (final r in refs)
              if (parseOsisRef(r) case final p?) Chip2(fmtOsis(p), onTap: () => onOpenRef(p.start)),
          ]),
        ),
      ],
      // Места употребления — после вариантов перевода
      gap,
      WordStatsBlock(num: num, onOpenRef: onOpenRef, onOpenAll: onOpenAll),
      gap,
      SourceNote([
        '${module.name} · ${module.meta['license'] ?? ''}',
        if (sym != null && renderings != null) '${ModuleStore.instance.get(symphonyId)?.name ?? 'Симфония RST+'} · ${ModuleStore.instance.get(symphonyId)?.meta['license'] ?? ''}',
        for (final (m, _) in lex) '${m.name}: ${m.meta['author'] ?? ''}${(m.meta['license'] ?? '') != '' ? ' · ${m.meta['license']}' : ''}',
      ].join('\n')),
    ]);
  }
}

/// Подпись раздела статьи Стронга: мелко, прописными, с разрядкой (.strong-entry h4)
class SecTitle extends ConsumerWidget {
  const SecTitle(this.text, {super.key, this.extra});
  final String text;
  final String? extra;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final ios = iosUiNow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(TextSpan(style: ios ? TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: pal.muted) : TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: pal.muted), children: [
        TextSpan(text: ios ? text : text.toUpperCase()),
        if (extra != null) TextSpan(text: ' · $extra', style: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0)),
      ])),
    );
  }
}

/// Кнопка-ссылка «Развернуть» / «Ещё 14» (.se-more)
class _MoreLink extends ConsumerWidget {
  const _MoreLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label, style: TextStyle(color: pal.accent, fontWeight: FontWeight.w600, fontSize: 14.4))),
      ),
    );
  }
}

/// Статья толкового словаря (Дворецкий) — длинная, с цитатами: сначала несколько строк, по нажатию — целиком
class LexSection extends StatefulWidget {
  const LexSection({super.key, required this.name, required this.text});
  final String name;
  final String text;
  @override
  State<LexSection> createState() => _LexSectionState();
}

class _LexSectionState extends State<LexSection> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 420;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SecTitle(widget.name),
      Text(widget.text, maxLines: long && !_open ? 7 : null, overflow: long && !_open ? TextOverflow.ellipsis : null, style: const TextStyle(height: 1.55)),
      if (long) _MoreLink(_open ? t('Свернуть') : t('Развернуть'), () => setState(() => _open = !_open)),
    ]);
  }
}

/// Полосы: слово (или книга) — доля — число (.renderings, .stat-bars)
class _Bars extends ConsumerWidget {
  const _Bars(this.rows, {this.labelWidth});
  final List<(String, int)> rows;
  final double? labelWidth; // книги — узкой колонкой 56 px, слова — 40 % ширины
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final max = rows.map((r) => r.$2).fold(1, (a, b) => a > b ? a : b);
    final books = labelWidth != null;
    final label = TextStyle(fontSize: books ? 13.6 : 14.7, color: books ? pal.muted : null);
    return Column(children: [
      for (final (name, n) in rows)
        Padding(
          padding: EdgeInsets.symmetric(vertical: books ? 1.5 : 2),
          child: Row(children: [
            if (books) SizedBox(width: labelWidth, child: Text(name, maxLines: 1, overflow: TextOverflow.clip, style: label)) else Expanded(flex: 4, child: Text(name, maxLines: 1, overflow: TextOverflow.clip, style: label)),
            const SizedBox(width: 10),
            Expanded(
              flex: books ? 1 : 6,
              child: LayoutBuilder(builder: (context, box) {
                final w = (n / max * 100).clamp(3, 100) / 100;
                return Stack(children: [
                  Container(height: 6, decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3))),
                  Container(height: 6, width: box.maxWidth * w, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(3))),
                ]);
              }),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 36, child: Text('$n', textAlign: TextAlign.right, style: TextStyle(color: pal.muted, fontSize: 13.6))),
          ]),
        ),
    ]);
  }
}

/// Как переведено в Синодальном: вариантов бывает за двадцать — сначала самые частые, остальные по кнопке
class Renderings extends StatefulWidget {
  const Renderings(this.rows, {super.key});
  final List<List> rows;
  @override
  State<Renderings> createState() => _RenderingsState();
}

class _RenderingsState extends State<Renderings> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in widget.rows) ('${r[0]}', r[1] as int)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Bars(_all ? rows : rows.take(6).toList()),
      if (!_all && rows.length > 6) _MoreLink(t('Ещё {n}', {'n': '${rows.length - 6}'}), () => setState(() => _all = true)),
    ]);
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
    final order = {for (final (i, b) in st.byBook.indexed) b.$1: i};
    final top = ([...st.byBook]..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : order[a.$1]!.compareTo(order[b.$1]!))).take(6).toList();
    final books = st.byBook.length;
    // три числа плитками: употреблений, стихов, книг
    Widget tile(int n, String word) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: iosUiNow ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius * 0.7)) : BoxDecoration(color: tint(pal.muted, pal.panel, 0.08), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n', style: TextStyle(fontSize: 20.8, fontWeight: FontWeight.w700, height: 1.2, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(word, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.8, color: pal.muted)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SecTitle(t('Где встречается'), extra: st.module),
      const SizedBox(height: 2),
      Row(children: [
        tile(st.total, tn('употребление|употребления|употреблений', st.total)),
        const SizedBox(width: 8),
        tile(st.verses, tn('стих|стиха|стихов', st.verses)),
        const SizedBox(width: 8),
        tile(books, tn('книга|книги|книг', books)),
      ]),
      // по книгам — только когда книг больше одной: одна полоса ничего не сравнивает
      if (books > 1) ...[
        const SizedBox(height: 10),
        _Bars([for (final b in top) (Books.instance.meta(b.$1).short.replaceAll(RegExp(r'\.$'), ''), b.$2)], labelWidth: 56),
      ],
      if (books > top.length) Padding(padding: const EdgeInsets.only(top: 4), child: Text(t('И ещё в {n} книгах.', {'n': '${books - top.length}'}), style: TextStyle(color: pal.muted, fontSize: 13.6))),
      const SizedBox(height: 10),
      ChipWrap([for (final r in st.refs.take(8)) Chip2(fmtRef(r.$1), onTap: () => widget.onOpenRef(r.$1))]),
      const SizedBox(height: 10),
      BigButton(t('Все места ({n})', {'n': '${st.verses}'}), onTap: widget.onOpenAll),
    ]);
  }
}
