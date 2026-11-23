// Поиск слова или части стиха внутри одной книги или главы — в окне «Перейти» (порт ScopedSearchResults, iPhone).
// Под полем — те же настройки, что на странице поиска (общие): целые слова, порядок слов, все модули.
// Пустое поле — показывается [idle] (сетка глав или стихов).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/rtl.dart';
import '../core/settings.dart';
import '../features/shell/fonts.dart' show readerTextStyle;
import '../features/study/study_data.dart' show fmtRef;
import 'ios_style.dart';
import 'kit.dart';
import 'search_screen.dart' show shortName;

const _originals = ['oshb', 'byz-rp2018'];

T searchOpt<T>(String key, T def) {
  try {
    final v = prefs.getString(key);
    return v == null ? def : jsonDecode(v) as T;
  } catch (_) {
    return def;
  }
}

/// Другие переводы, в которых можно искать (оригиналы и подстрочники — нет)
List<InstalledModule> searchOthers(String moduleId) =>
    ModuleStore.instance.bibles.where((m) => m.features['helper'] != true && m.id != moduleId && !_originals.contains(m.id)).toList();

/// Записать настройку поиска (общую для основного поиска, поиска в книге и «Перейти»)
void saveSearchOpt(String key, bool v) => prefs.setString(key, jsonEncode(v));

class ScopedSearch extends ConsumerStatefulWidget {
  const ScopedSearch({super.key, required this.moduleId, required this.book, this.chapter, required this.hint, required this.idle, required this.onPick, this.bottomPad = 20});

  /// Перевод открытой панели; книга; глава (null — вся книга)
  final String moduleId;
  final String book;
  final int? chapter;
  final String hint;

  /// Что показывать, пока поле пусто
  final Widget idle;
  final void Function(VerseRef at) onPick;
  final double bottomPad;

  @override
  ConsumerState<ScopedSearch> createState() => _ScopedSearchState();
}

class _ScopedSearchState extends ConsumerState<ScopedSearch> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _whole = searchOpt('searchWhole', false);
  bool _ordered = searchOpt('searchOrdered', false);
  bool _allMods = searchOpt('searchAllModules', false);
  List<(SearchHit, String)>? _hits;
  List<SearchSuggestion> _near = const [];
  String _ran = '';
  bool _busy = false;
  int _gen = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _input.addListener(_changed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  InstalledModule? get _module => ModuleStore.instance.get(widget.moduleId);

  List<InstalledModule> get _others => ModuleStore.instance.bibles
      .where((m) => m.features['helper'] != true && m.id != widget.moduleId && !_originals.contains(m.id))
      .toList();

  bool get _canAll => _others.isNotEmpty;

  /// Переводы для поиска: открытый — или все (открытый первым, затем того же языка)
  List<InstalledModule> get _targets {
    final m = _module;
    if (m == null) return const [];
    if (!_allMods || !_canAll) return [m];
    final rest = _others..sort((a, b) => (a.language == m.language ? 0 : 1) - (b.language == m.language ? 0 : 1));
    return [m, ...rest];
  }

  void _changed() {
    setState(() {});
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_input.text.trim().length < 2) {
      _gen++;
      setState(() {
        _hits = null;
        _near = const [];
        _busy = false;
      });
      return;
    }
    _timer = Timer(const Duration(milliseconds: 250), _run);
  }

  void _setOption(String key, bool v, VoidCallback apply) {
    setState(apply);
    prefs.setString(key, jsonEncode(v));
    _schedule();
  }

  Future<void> _run() async {
    final q = _input.text.trim();
    if (q.length < 2) return;
    final gen = ++_gen;
    final list = _targets;
    final books = {widget.book};
    setState(() {
      _busy = true;
      _ran = q;
    });
    final out = <(SearchHit, String)>[];
    for (final m in list) {
      List<SearchHit> found;
      try {
        found = await searchText(m.id, q, books: books, wholeWord: _whole, ordered: _ordered);
      } catch (_) {
        continue; // перевод недоступен — ищем в остальных
      }
      if (!mounted || gen != _gen) return;
      for (final h in found) {
        if (widget.chapter != null && h.ref.chapter != widget.chapter) continue;
        out.add((h, m.id));
      }
    }
    // несколько переводов: места по порядку, у одного места — переводы подряд (сортировка устойчивая по порядку переводов)
    if (list.length > 1) {
      final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
      out.sort((a, b) {
        final c = a.$1.ref.chapter - b.$1.ref.chapter;
        if (c != 0) return c;
        final v = a.$1.ref.verse - b.$1.ref.verse;
        return v != 0 ? v : order[a.$2]! - order[b.$2]!;
      });
    }
    List<SearchSuggestion> near = const [];
    if (out.isEmpty) {
      try {
        near = await suggestSearch([for (final m in list) (m.id, books)], q, wholeWord: _whole, ordered: _ordered);
      } catch (_) {
        near = const [];
      }
      if (widget.chapter != null) {
        // подсказка годится, только если у неё есть результаты в этой главе
        final ok = <SearchSuggestion>[];
        for (final s in near) {
          var n = 0;
          for (final m in list) {
            try {
              n += (await searchText(m.id, s.query, books: books, wholeWord: _whole, ordered: _ordered)).where((h) => h.ref.chapter == widget.chapter).length;
            } catch (_) {
              continue;
            }
          }
          if (n > 0) ok.add((query: s.query, count: n));
        }
        near = ok;
      }
      if (!mounted || gen != _gen) return;
    }
    if (!mounted || gen != _gen) return;
    setState(() {
      _hits = out;
      _near = near;
      _busy = false;
    });
  }

  TextSpan _highlight(String text, RegExp? re, Palette pal) {
    if (re == null) return TextSpan(text: text);
    final out = <TextSpan>[];
    var pos = 0;
    for (final m in re.allMatches(text)) {
      if (m.end == m.start) break;
      if (m.start > pos) out.add(TextSpan(text: text.substring(pos, m.start)));
      out.add(TextSpan(text: m.group(0), style: TextStyle(backgroundColor: pal.hl)));
      pos = m.end;
    }
    if (pos < text.length) out.add(TextSpan(text: text.substring(pos)));
    return TextSpan(children: out);
  }

  void _setQuery(String q) => _input.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final pal = settings.palette;
    final muted = mix(pal.muted, 0.8, pal.text);
    final fill = mix(pal.text, 0.055, pal.panel);
    final q = _input.text.trim();
    final searching = q.length >= 2;
    final hits = _hits;
    final multi = _targets.length > 1;
    final re = _ran.isEmpty ? null : QueryMatcher(_ran, wholeWord: _whole).highlight;
    final textStyle = readerTextStyle(settings, size: 16).copyWith(color: pal.text, height: 1.5);

    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 46,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(iosUiNow ? 23 : 14)),
      child: Row(children: [
        const SizedBox(width: 14),
        AIcon(ico(LucideIcons.search), size: 18, color: muted),
        Expanded(
          child: BareField(
            controller: _input,
            focusNode: _focus,
            autofocus: false,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onSubmitted: (_) => _run(),
            hint: widget.hint,
            style: TextStyle(fontSize: 16, height: 1.25, color: pal.text),
            hintColor: muted,
            cursorColor: pal.accent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
        if (_input.text.isNotEmpty)
          SizedBox(width: 44, height: 44, child: IconButton(padding: EdgeInsets.zero, tooltip: t('Очистить'), onPressed: _input.clear, icon: AIcon(ico(LucideIcons.x), size: 18, color: muted))),
      ]),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, widget.bottomPad),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field,
        const SizedBox(height: 14),
        if (!searching)
          widget.idle
        else ...[
          // те же настройки, что на странице поиска
          SwitchRow(label: t('Только целые слова'), value: _whole, onChanged: (v) => _setOption('searchWhole', v, () => _whole = v)),
          SwitchRow(label: t('Слова в заданном порядке'), value: _ordered, onChanged: (v) => _setOption('searchOrdered', v, () => _ordered = v)),
          if (_canAll) SwitchRow(label: t('Во всех модулях'), value: _allMods, onChanged: (v) => _setOption('searchAllModules', v, () => _allMods = v)),
          const SizedBox(height: 12),
          if (hits == null || _busy && hits.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 18), child: Center(child: Spinner(size: 22, color: pal.muted)))
          else if (hits.isEmpty) ...[
            Text(t('Ничего не найдено.'), style: TextStyle(fontSize: 14, color: pal.muted)),
            if (_near.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(t('Возможно, вы искали'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: muted)),
              for (final s in _near)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _setQuery(s.query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                    child: Row(children: [
                      AIcon(ico(LucideIcons.search), size: 16, color: pal.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.query, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: pal.accent))),
                      Text('${s.count}', style: TextStyle(fontSize: 14, color: pal.muted)),
                    ]),
                  ),
                ),
            ],
          ] else ...[
            Text(t('Найдено: {n}', {'n': '${hits.length}'}), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.muted)),
            const SizedBox(height: 6),
            for (final (h, mid) in hits.take(100))
              InkWell(
                onTap: () => widget.onPick(h.ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(fmtRef(h.ref), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.accent)),
                      if (multi && ModuleStore.instance.get(mid) != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
                          child: Text(shortName(ModuleStore.instance.get(mid)!), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: pal.muted)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text.rich(_highlight(h.snippet, re, pal), style: textStyle, textDirection: textDirOf(h.snippet)),
                  ]),
                ),
              ),
          ],
        ],
      ]),
    );
  }
}
