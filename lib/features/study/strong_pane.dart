// Стронг — параллельным окном на половину экрана (StrongPanel.jsx): текст остаётся рядом и листается.
// Вверху — строка окна: какие словари показывать, номер (у слова с несколькими номерами — каждый), «Где встречается»,
// назад / вперёд по просмотренным статьям, закрыть. Ниже — слово оригинала и статьи всех словарей Стронга подряд
// (русский Стронг первым), варианты перевода в синодальном тексте и места употребления.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'concordance_sheet.dart';
import 'dictionary_sheet.dart' show OrigInfo, WordStatsBlock;
import 'interlinear.dart';
import 'lexicon.dart';
import 'morph.dart';
import 'sheet.dart';
import 'study_data.dart';

/// Что открыть в окне Стронга: номер (и все номера слова), стих и слово в нём — для формы слова в этом стихе
class StrongReq {
  StrongReq({required this.pane, required this.num, List<String>? nums, this.ref, this.wordIndex, this.origWord, this.morph = const []})
      : nums = nums ?? [num],
        id = DateTime.now().microsecondsSinceEpoch;
  final int pane;
  final String num;
  final List<String> nums;
  final VerseRef? ref;
  final int? wordIndex;
  final OrigInfo? origWord;
  final List<String> morph;
  final int id;
  StrongReq withNum(String n) => StrongReq(pane: pane, num: n, nums: nums, ref: ref, wordIndex: wordIndex, origWord: origWord, morph: morph);
}

String _norm(String n) => n.replaceFirstMapped(RegExp(r'^([HG])0*', caseSensitive: false), (m) => m.group(1)!.toUpperCase());

/// Открыть (или сменить) статью в окне Стронга
void openStrongPane(StrongReq r) => Hub.strongPane.value = r;

class StrongPane extends ConsumerStatefulWidget {
  const StrongPane({super.key});
  @override
  ConsumerState<StrongPane> createState() => _StrongPaneState();
}

class _StrongPaneState extends ConsumerState<StrongPane> {
  final _hist = <StrongReq>[];
  int _idx = -1;
  List<String> _hidden = [];
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    try {
      _hidden = [for (final x in jsonDecode(prefs.getString('strongHidden') ?? '[]') as List) '$x'];
    } catch (_) {}
    Hub.strongPane.addListener(_push);
    _push();
  }

  @override
  void dispose() {
    Hub.strongPane.removeListener(_push);
    _scroll.dispose();
    super.dispose();
  }

  // Новое слово из выборки — в историю (вперёд — отбрасывается)
  void _push() {
    final r = Hub.strongPane.value;
    if (r is! StrongReq || (_idx >= 0 && _hist[_idx].id == r.id)) return;
    setState(() {
      _hist.removeRange(_idx + 1, _hist.length);
      _hist.add(r);
      if (_hist.length > 50) _hist.removeAt(0);
      _idx = _hist.length - 1;
    });
    _top();
  }

  void _top() => WidgetsBinding.instance.addPostFrameCallback((_) => _scroll.hasClients ? _scroll.jumpTo(0) : null);

  void _go(int d) {
    setState(() => _idx = (_idx + d).clamp(0, _hist.length - 1));
    _top();
  }

  // Ссылка на другой номер внутри статьи («от G2596») — новая статья в этом же окне
  void _openNum(String num) {
    final cur = _hist[_idx];
    setState(() {
      _hist.removeRange(_idx + 1, _hist.length);
      _hist.add(StrongReq(pane: cur.pane, num: num));
      _idx = _hist.length - 1;
    });
    _top();
  }

  void _toggle(String id) {
    setState(() => _hidden.contains(id) ? _hidden.remove(id) : _hidden.add(id));
    prefs.setString('strongHidden', jsonEncode(_hidden));
  }

  // Стих из статьи — в окне текста рядом, Стронг остаётся
  void _openRef(VerseRef r) => ref.read(panesProvider.notifier).navigate(_hist[_idx].pane, r);

  // «от H24 (אָבִיב)» → кликабельные номера Стронга
  Widget _links(String text, TextStyle style) {
    final parts = <(String, VoidCallback?)>[];
    var last = 0;
    for (final m in RegExp(r'[HG]\d+').allMatches(text)) {
      if (m.start > last) parts.add((text.substring(last, m.start), null));
      final n = m.group(0)!;
      parts.add((n, () => _openNum(n)));
      last = m.end;
    }
    if (last < text.length) parts.add((text.substring(last), null));
    return LinkSpans(parts: parts, style: style);
  }

  Widget _barBtn(Palette pal, IconData icon, String tip, VoidCallback? onTap, {double size = 20}) => IconBtn(icon: icon, size: size, tooltip: tip, color: onTap == null ? pal.barText.withValues(alpha: 0.35) : pal.barText, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    if (_idx < 0) return const SizedBox.shrink();
    final cur = _hist[_idx];
    final res = lookupStrong(cur.num);
    final all = [for (final m in ModuleStore.instance.installed) if (m.type == 'dictionary' && StudyData.dictKind(m) == 'strongs') m];
    final shown = [for (final r in res) if (!_hidden.contains(r.module.id)) r];
    final head = res.map((r) => r.found.first.entry).where((e) => (e['lemma'] ?? '').toString().isNotEmpty).firstOrNull ?? const <String, dynamic>{};
    final isHeb = cur.num.startsWith('H');
    final dir = isHeb ? TextDirection.rtl : TextDirection.ltr;
    // слово оригинала в этом стихе: из подстрочника (по номеру слова) или переданное
    OrigInfo? orig = cur.origWord;
    if (orig == null && cur.wordIndex != null && cur.ref != null) {
      final ws = ruInterlinear(cur.ref!);
      final w = ws != null && cur.wordIndex! < ws.length ? ws[cur.wordIndex!] : null;
      if (w != null && w.orig.isNotEmpty) orig = OrigInfo(orig: w.orig, morph: w.origMorph, num: w.num);
    }
    final exact = orig != null && orig.num != null && _norm(orig.num!) == _norm(cur.num) ? orig : null;
    final morph = exact == null ? cur.morph : const <String>[];
    final body = TextStyle(fontSize: 15.5, height: 1.55, color: pal.text);
    final muted = TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted);
    final lemma = '${head['lemma'] ?? ''}';

    final bar = Container(
      height: 48,
      decoration: BoxDecoration(color: pal.bar, border: Border(bottom: BorderSide(color: pal.line))),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        // какие словари показывать
        PopupMenuButton<String>(
          tooltip: t('Словари'),
          onSelected: _toggle,
          itemBuilder: (_) => [
            for (final m in all) CheckedPopupMenuItem(value: m.id, checked: !_hidden.contains(m.id), child: Text(m.name)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.library, size: 18, color: pal.barText),
              const SizedBox(width: 6),
              Text(t('Словари'), style: TextStyle(fontSize: 14.4, fontWeight: FontWeight.w600, color: pal.barText)),
            ]),
          ),
        ),
        // номера слова — всё свободное место строки (листаются, если их много)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final n in cur.nums)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _hist[_idx] = cur.withNum(n)),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: n == cur.num ? pal.barText : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: n == cur.num ? pal.barText : pal.barText.withValues(alpha: 0.28)),
                      ),
                      child: Text(n, style: TextStyle(fontSize: 13.6, fontWeight: FontWeight.w700, color: n == cur.num ? pal.bar : pal.barText, fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        _barBtn(pal, LucideIcons.search, t('Где встречается'), () => openConcordance(context, num: cur.num, lemma: lemma.isEmpty ? null : lemma, onOpen: _openRef), size: 19),
        _barBtn(pal, LucideIcons.chevronLeft, t('Назад'), _idx > 0 ? () => _go(-1) : null, size: 22),
        _barBtn(pal, LucideIcons.chevronRight, t('Вперёд'), _idx < _hist.length - 1 ? () => _go(1) : null, size: 22),
        _barBtn(pal, LucideIcons.x, t('Закрыть'), () => Hub.strongPane.value = null),
      ]),
    );

    Widget section(ModResult r) {
      final e = r.found.first.entry;
      final renderings = (e['renderings'] as List?)?.cast<List>();
      final refs = (e['refs'] as List?)?.cast<String>();
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // .sp-dict: название словаря
          Text(r.module.name.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: pal.accent)),
          if (e['definition'] != null) ...[const SizedBox(height: 6), _links('${e['definition']}', body)],
          if (e['derivation'] != null) ...[const SizedBox(height: 6), _links('${t('Происхождение')}: ${e['derivation']}', muted)],
          if (e['kjv'] != null) ...[const SizedBox(height: 6), Text('KJV: ${e['kjv']}', style: muted)],
          if (e['text'] != null) ...[const SizedBox(height: 6), Text('${e['text']}', style: body)],
          if (renderings != null && renderings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(t('Как переведено в синодальном тексте · {n} употр.', {'n': '${e['count']}'}), style: muted),
            const SizedBox(height: 4),
            for (final x in renderings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(flex: 4, child: Text('${x[0]}', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 14.7, color: pal.text))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(builder: (context, box) {
                      final w = ((x[1] as int) / (renderings.first[1] as int) * 100).clamp(4, 100) / 100;
                      return Stack(children: [
                        Container(height: 6, decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3))),
                        Container(height: 6, width: box.maxWidth * w, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(3))),
                      ]);
                    }),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 36, child: Text('${x[1]}', textAlign: TextAlign.right, style: TextStyle(color: pal.muted, fontSize: 13.6))),
                ]),
              ),
          ],
          if (refs != null && refs.isNotEmpty && renderings == null) ...[
            const SizedBox(height: 6),
            ChipWrap([
              for (final x in refs)
                if (parseOsisRef(x) case final p?) Chip2(fmtOsis(p), onTap: () => _openRef(p.start)),
            ]),
          ],
          const SizedBox(height: 6),
          SourceNote('${r.module.meta['license'] ?? ''}'),
        ]),
      );
    }

    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: pal.bg,
      child: Column(children: [
        bar,
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(16, 14, 16, bottom + 20),
            children: [
              if (lemma.isNotEmpty)
                Align(
                  alignment: isHeb ? Alignment.centerRight : Alignment.centerLeft,
                  child: Directionality(textDirection: dir, child: Text(lemma, style: TextStyle(fontFamily: isHeb ? 'Noto Serif Hebrew' : null, fontSize: 32, height: 1.25, color: pal.text))),
                ),
              const SizedBox(height: 4),
              Text([if (head['xlit'] != null) '${head['xlit']}', if (head['pron'] != null) '[${head['pron']}]', isHeb ? t('иврит / арамейский (ВЗ)') : t('греческий (НЗ)')].join(' · '), style: muted),
              if (exact != null) ...[
                const SizedBox(height: 6),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${t('В этом стихе')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  WidgetSpan(child: Directionality(textDirection: dir, child: Text(exact.orig, style: TextStyle(fontSize: 15.5, color: pal.text)))),
                  if (exact.morph != null && describeMorph(exact.morph!) != null) TextSpan(text: ' — ${describeMorph(exact.morph!)}'),
                ]), style: TextStyle(fontSize: 15.2, color: pal.text)),
              ],
              for (final m in morph) ...[
                const SizedBox(height: 6),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${t('Грамматическая форма')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '${describeMorph(m) ?? t('без расшифровки')} '),
                  TextSpan(text: '($m)', style: TextStyle(color: pal.muted, fontFamily: 'monospace', fontSize: 13.5)),
                ]), style: TextStyle(fontSize: 15.2, color: pal.text)),
              ],
              for (final r in shown) section(r),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(res.isEmpty ? t('Статей не найдено') : t('Все словари скрыты — выберите их в «Словари».'), style: muted)),
              const SizedBox(height: 14),
              WordStatsBlock(num: cur.num, onOpenRef: _openRef, onOpenAll: () => openConcordance(context, num: cur.num, lemma: lemma.isEmpty ? null : lemma, onOpen: _openRef)),
            ],
          ),
        ),
      ]),
    );
  }
}
