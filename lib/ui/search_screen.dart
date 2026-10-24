// Поиск по переводу: индекс FTS5 в базе модуля — результат по всей Библии за доли секунды.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/panes.dart';
import '../core/settings.dart';

Future<void> openSearch(BuildContext context, int pane) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: SearchSheet(pane: pane)),
    );

class SearchSheet extends ConsumerStatefulWidget {
  const SearchSheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<SearchSheet> {
  final _q = TextEditingController(text: prefs.getString('searchQuery') ?? '');
  List<SearchHit>? _hits;
  int _ms = 0;

  void _run() {
    final q = _q.text.trim();
    prefs.setString('searchQuery', q);
    final sw = Stopwatch()..start();
    final hits = q.isEmpty ? <SearchHit>[] : search(ref.read(panesProvider)[widget.pane].moduleId, q);
    setState(() {
      _hits = hits;
      _ms = sw.elapsedMilliseconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final words = _q.text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
    final hits = _hits;
    return Material(
      color: pal.panel,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text(t('Поиск'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: t('Слова или ссылка'),
              filled: true,
              fillColor: pal.bg,
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _run),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (hits != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(t('Найдено: {n}', {'n': '${hits.length}'}) + '  ·  $_ms мс', style: TextStyle(color: pal.muted))),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: hits?.length ?? 0,
            separatorBuilder: (_, __) => Divider(color: pal.line, height: 1),
            itemBuilder: (context, i) {
              final h = hits![i];
              return InkWell(
                onTap: () {
                  ref.read(panesProvider.notifier).navigate(widget.pane, h.ref);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse), style: TextStyle(fontWeight: FontWeight.w700, color: pal.accent)),
                    const SizedBox(height: 2),
                    Text.rich(_highlight(h.snippet, words, pal), style: TextStyle(color: pal.text, height: 1.4, fontSize: 15)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  // Найденные слова (с любым окончанием) — подсветкой
  TextSpan _highlight(String text, List<String> words, Palette pal) {
    if (words.isEmpty) return TextSpan(text: text);
    final re = RegExp('(?<![\\p{L}\\p{N}])(${words.map(RegExp.escape).join('|')})[\\p{L}\\p{N}]*', unicode: true, caseSensitive: false);
    final out = <TextSpan>[];
    var pos = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > pos) out.add(TextSpan(text: text.substring(pos, m.start)));
      out.add(TextSpan(text: m.group(0), style: TextStyle(backgroundColor: pal.hl)));
      pos = m.end;
    }
    if (pos < text.length) out.add(TextSpan(text: text.substring(pos)));
    return TextSpan(children: out);
  }
}
