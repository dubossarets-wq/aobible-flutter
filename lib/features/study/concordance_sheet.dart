// «Все места» слова оригинала (ConcordanceSheet.jsx, WordStats.jsx): стихи с этим номером Стронга, текст
// с выделенным словом, выбор по варианту перевода, «Показать ещё». Нажатие на место открывает его.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'interlinear.dart';
import 'sheet.dart';
import 'study_data.dart';

const _page = 40;

bool strongsSame(String s, String num) => s.replaceFirstMapped(RegExp(r'^([HG])0*'), (m) => m.group(1)!) == num.replaceFirstMapped(RegExp(r'^([HG])0*'), (m) => m.group(1)!);

/// Считает статистику после показа окна (первый раз — до сотни миллисекунд), результат запоминается
Future<WordStats?> loadStats(String num) => Future(() => StudyData.strongStats(num));

/// Открыть окно «Все места»; [onOpen] — нажатие на место
Future<void> openConcordance(BuildContext context, {required String num, String? lemma, required OpenRef onOpen}) =>
    showSheet(context, ConcordanceSheet(num: num, lemma: lemma, onOpen: onOpen), size: SheetSize.full);

class ConcordanceSheet extends ConsumerStatefulWidget {
  const ConcordanceSheet({super.key, required this.num, this.lemma, required this.onOpen});
  final String num;
  final String? lemma;
  final OpenRef onOpen;
  @override
  ConsumerState<ConcordanceSheet> createState() => _ConcordanceSheetState();
}

class _ConcordanceSheetState extends ConsumerState<ConcordanceSheet> {
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
    final st = _st;
    return SheetScaffold(
      title: '${t('Все места')} · ${widget.num}${widget.lemma != null && widget.lemma!.isNotEmpty ? ' ${widget.lemma}' : ''}',
      subtitle: st != null && st.total > 0 ? '${tn('{n} раз|{n} раза|{n} раз', st.total)} ${tn('в {n} стихе|в {n} стихах|в {n} стихах', st.verses)} · ${st.module}' : null,
      onBack: () => Navigator.pop(context),
      body: !_loaded
          ? SheetList(children: [Loading(t('Ищу все места…'))])
          : StrongPlaces(num: widget.num, stats: st, onOpen: widget.onOpen),
    );
  }
}

/// Места слова оригинала: выбор по варианту перевода, стихи с выделенным словом, «Показать ещё».
/// [filter] — какие места показывать (часть Библии в поиске)
class StrongPlaces extends ConsumerStatefulWidget {
  const StrongPlaces({super.key, required this.num, required this.stats, required this.onOpen, this.filter});
  final String num;
  final WordStats? stats;
  final OpenRef onOpen;
  final bool Function(VerseRef)? filter;
  @override
  ConsumerState<StrongPlaces> createState() => _StrongPlacesState();
}

class _StrongPlacesState extends ConsumerState<StrongPlaces> {
  String? _word;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final st = widget.stats;
    if (st == null || st.total == 0) return SheetList(children: [Text(t('В переводе со Стронгом этого слова нет.'), style: TextStyle(color: pal.muted))]);
    final all = [for (final r in st.refs) if (widget.filter == null || widget.filter!(r.$1)) r];
    if (all.isEmpty) return SheetList(children: [Text(t('В этой части Библии мест нет.'), style: TextStyle(color: pal.muted))]);
    final list = [for (final r in all) if (_word == null || r.$2.contains(_word)) r];
    final counts = <String, int>{};
    for (final r in all) {
      for (final w in r.$2.toSet()) {
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    final order = {for (final (i, e) in counts.entries.indexed) e.key: i};
    final renderings = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : order[a.key]!.compareTo(order[b.key]!));
    final shown = list.take(_shown).toList();
    final more = list.length > _shown;
    final bottom = MediaQuery.of(context).padding.bottom;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottom),
      itemCount: 1 + shown.length + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChipWrap([
              Chip2(t('Все'), on: _word == null, count: all.length, onTap: () => setState(() {
                    _word = null;
                    _shown = _page;
                  })),
              for (final e in renderings.take(14))
                Chip2(e.key, on: _word == e.key, count: e.value, onTap: () => setState(() {
                      _word = e.key;
                      _shown = _page;
                    })),
            ]),
          );
        }
        if (i == shown.length + 1) {
          return Padding(padding: const EdgeInsets.only(top: 12), child: BigButton(t('Показать ещё ({n})', {'n': '${list.length - _shown}'}), onTap: () => setState(() => _shown += _page)));
        }
        final r = shown[i - 1].$1;
        return _Row(r: r, num: widget.num, moduleId: st.moduleId, onOpen: widget.onOpen);
      },
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.r, required this.num, required this.moduleId, required this.onOpen});
  final VerseRef r;
  final String num;
  final String moduleId;
  final OpenRef onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final raw = StudyData.verse(moduleId, r) ?? '';
    return InkWell(
      onTap: () => onOpen(r),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtRef(r), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.6, color: pal.accent)),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(children: [
              for (final tk in tokenize(raw))
                if (tk.isWord && tk.strongs.any((s) => strongsSame(s, num)))
                  TextSpan(text: tk.text, style: TextStyle(backgroundColor: pal.accent.withValues(alpha: 0.22)))
                else
                  TextSpan(text: tk.text),
            ]),
            style: const TextStyle(fontSize: 16, height: 1.45),
          ),
        ]),
      ),
    );
  }
}
