// Поиск слов и фраз по переводу панели (или по всем установленным переводам) — как SearchPanel.jsx в веб-версии.
// Ссылка вида «Ин 3:16» показывает карточку перехода, номер Стронга (G26, H7225) — карточку слова со всеми местами.
// Окно помнит последний поиск: запрос, настройки и история — в prefs (JSON, ключи веб-версии), результаты и
// прокрутка — в памяти до перезапуска.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import '../features/shell/fonts.dart' show readerTextStyle;
import 'kit.dart';

const _page = 200;
const _originals = ['oshb', 'byz-rp2018'];

/// Номер Стронга в строке поиска: G26, H7225, «Г26», «Н7225»/«Е7225» (еврейский) или просто 3056 (оба Завета)
List<String>? strongQuery(String q) {
  final m = RegExp(r'^\s*([HGhgНнГгЕе]?)\s*0*(\d{1,4})\s*$').firstMatch(q);
  if (m == null || int.parse(m.group(2)!) == 0) return null;
  final l = m.group(1)!.toUpperCase();
  final n = int.parse(m.group(2)!);
  final pre = l == 'G' || l == 'Г' ? ['G'] : l.isNotEmpty ? ['H'] : ['H', 'G'];
  return [for (final x in pre) '$x$n'];
}

/// Короткое имя модуля для метки у результата (moduleShort.js)
String shortName(InstalledModule m) {
  final n = m.name.trim();
  return n.runes.length <= 6 ? n : String.fromCharCodes(n.split(RegExp(r'\s+')).first.runes.take(6));
}

// Настройки поиска — JSON-строки, как в localStorage веб-версии (перенос из старого приложения их подхватывает)
T _load<T>(String key, T def) {
  try {
    final v = prefs.getString(key);
    return v == null ? def : jsonDecode(v) as T;
  } catch (_) {
    return def;
  }
}

void _save(String key, Object value) => prefs.setString(key, jsonEncode(value));

String _savedQuery() {
  final v = prefs.getString('searchQuery') ?? '';
  // старый формат — JSON-строка
  if (v.startsWith('"')) {
    try {
      return jsonDecode(v) as String;
    } catch (_) {}
  }
  return v;
}

/// Последний законченный поиск: при повторном открытии — те же результаты и та же прокрутка
class _Memo {
  _Memo(this.key);
  final String key;
  final List<SearchHit> hits = [];
  final List<String> mods = []; // перевод каждого результата
  int shown = _page;
  double scroll = 0;
}

_Memo? _memo;

Future<void> openSearch(BuildContext context, int pane, {String? query, String? scope}) =>
    showAobSheet(context, builder: (_) => SearchSheet(pane: pane, query: query, scope: scope), tab: 'search');

class SearchSheet extends ConsumerStatefulWidget {
  const SearchSheet({super.key, required this.pane, this.query, this.scope});
  final int pane;
  final String? query; // явный запрос при открытии (например, из словаря) важнее сохранённого
  final String? scope;
  @override
  ConsumerState<SearchSheet> createState() => _SearchSheetState();
}

class _RefHit {
  _RefHit(this.ref, this.text);
  final VerseRef ref;
  final String? text;
}

class _SearchSheetState extends ConsumerState<SearchSheet> {
  late final _q = TextEditingController(text: widget.query ?? _savedQuery());
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String _scope = _load('searchScope', 'all');
  bool _whole = _load('searchWhole', false);
  bool _allMods = _load('searchAllModules', false);
  bool _withOrig = _load('searchOriginals', false);
  List<String> _history = _load<List>('searchHistory', const []).whereType<String>().toList();

  List<SearchHit>? _hits;
  List<String> _hitMods = const [];
  int _shown = _page;
  String _ran = '';
  String? _shownKey; // условия, чьи результаты сейчас на экране
  ({double p, String label})? _progress;
  _RefHit? _refHit;
  List<String>? _strongHit;
  int _gen = 0; // поколение поиска: результат устаревшего не показываем
  Future<void>? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.query != null && ['all', 'OT', 'NT', 'book'].contains(widget.scope)) _scope = widget.scope!;
    _focus.addListener(() => setState(() {}));
    final restored = _memo != null && _memo!.key == _keyOf(_q.text.trim()) ? _memo : null;
    if (restored != null) {
      _hits = restored.hits;
      _hitMods = restored.mods;
      _shown = restored.shown;
      _ran = _q.text.trim();
      _shownKey = restored.key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(restored.scroll.clamp(0, _scroll.position.maxScrollExtent));
      });
    } else {
      _schedule();
    }
    _scroll.addListener(() {
      if (_memo != null && _memo!.key == _shownKey) _memo!.scroll = _scroll.offset;
    });
    // На телефоне при восстановленных результатах клавиатуру не открываем — она закрыла бы список
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted && restored == null) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _gen++;
    final q = _q.text.trim();
    prefs.setString('searchQuery', _q.text);
    // Запрос, по которому что-то нашлось, — в историю, даже если результат не открывали
    if (q.length > 1 && (_memo?.hits.isNotEmpty ?? false)) {
      _save('searchHistory', [q, ..._load<List>('searchHistory', const []).where((x) => x != q)].take(15).toList());
    }
    _q.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  PaneState get _pane => ref.read(panesProvider)[widget.pane];
  List<InstalledModule> get _bibles => ModuleStore.instance.bibles.where((m) => m.features['helper'] != true).toList();
  InstalledModule? get _module => ModuleStore.instance.get(_pane.moduleId) ?? (_bibles.isEmpty ? null : _bibles.first);

  // Переключатель «Во всех модулях» виден, только когда кроме открытого есть ещё хотя бы один перевод (не оригинал)
  bool get _canAll {
    final m = _module;
    return m != null && _bibles.any((b) => b.id != m.id && !_originals.contains(b.id));
  }

  bool get _hasOrig => _bibles.any((b) => _originals.contains(b.id));

  /// «Во всех модулях»: открытый перевод первым, затем переводы того же языка, затем остальные
  List<InstalledModule> get _targets {
    final m = _module;
    if (m == null) return const [];
    if (!_allMods || !_canAll) return [m];
    final rest = _bibles.where((b) => b.id != m.id && (_withOrig || !_originals.contains(b.id))).toList();
    int same(InstalledModule b) => b.language == m.language ? 0 : 1;
    rest.sort((a, b) => same(a) - same(b));
    return [m, ...rest];
  }

  String _keyOf(String q) => jsonEncode([q, _scope, _scope == 'book' ? _pane.ref.book : '', _whole, _targets.map((m) => m.id).join(',')]);

  /// Книги перевода в выбранной части Библии (null — все)
  Set<String>? _books(String moduleId) {
    if (_scope == 'all') return null;
    if (_scope == 'book') return {_pane.ref.book};
    return {
      for (final b in bookList(moduleId))
        if (Books.instance.meta(b['id'] as String).testament == _scope) b['id'] as String,
    };
  }

  bool Function(VerseRef r)? get _strongFilter => switch (_scope) {
        'all' => null,
        'book' => (r) => r.book == _pane.ref.book,
        _ => (r) => Books.instance.meta(r.book).testament == _scope,
      };

  // Поиск по мере ввода: короткая пауза после нажатия клавиши, прежний поиск отменяется
  void _schedule() {
    final q = _q.text.trim();
    final t0 = Future<void>.delayed(Duration(milliseconds: q.length < 4 ? 350 : 220));
    _timer = t0;
    t0.then((_) {
      if (mounted && identical(_timer, t0)) _update();
    });
  }

  void _stop() {
    _gen++;
    _shownKey = null;
    _hits = null;
    _progress = null;
    _ran = '';
  }

  void _update() {
    final q = _q.text.trim();
    final key = _keyOf(q);
    if (key == _shownKey) return; // эти результаты уже на экране
    final sq = strongQuery(q);
    if (sq != null) {
      setState(() {
        _stop();
        _refHit = null;
        _strongHit = sq;
      });
      return;
    }
    _strongHit = null;
    // Ссылка («Ин 3 6», «Быт 1:1») вместо поиска показывает карточку перехода с текстом стиха
    final m = _module;
    final r = RegExp(r'\d').hasMatch(q) ? Books.instance.parseHuman(q) : null;
    if (r != null && m != null && bookList(m.id).any((b) => b['id'] == r.book)) {
      setState(() {
        _stop();
        _refHit = _RefHit(r, verseAt(m.id, r));
      });
      return;
    }
    _refHit = null;
    if (q.length < 2) return setState(_stop);
    // Вернулись к последнему законченному поиску — без повторного перебора
    if (_memo != null && _memo!.key == key) {
      setState(() {
        _gen++;
        _shownKey = key;
        _progress = null;
        _ran = q;
        _shown = _memo!.shown;
        _hits = _memo!.hits;
        _hitMods = _memo!.mods;
      });
      return;
    }
    _run(q, key);
  }

  Future<void> _run(String q, String key) async {
    final gen = ++_gen;
    final list = _targets;
    final memo = _Memo(key);
    setState(() {
      _shownKey = key;
      _hits = memo.hits;
      _hitMods = memo.mods;
      _shown = _page;
      _ran = q;
      _progress = (p: 0, label: t('Поиск…'));
    });
    // Переводы — по одному, каждый в отдельном потоке: результаты идут в порядке Библии, интерфейс не замирает
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (list.length > 1) setState(() => _progress = (p: i / list.length, label: shortName(m)));
      List<SearchHit> found;
      try {
        found = await searchText(m.id, q, books: _books(m.id), wholeWord: _whole);
      } catch (_) {
        continue; // перевод недоступен — ищем в остальных
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        memo.hits.addAll(found);
        memo.mods.addAll(List.filled(found.length, m.id));
      });
    }
    if (!mounted || gen != _gen) return;
    _memo = memo;
    setState(() => _progress = null);
  }

  void _remember(String q) {
    if (q.isEmpty) return;
    setState(() => _history = [q, ..._history.where((x) => x != q)].take(15).toList());
    _save('searchHistory', _history);
  }

  void _setQuery(String q) {
    _q.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    setState(() {});
    _schedule();
  }

  // Крестик в поле: стирает запрос и результаты, курсор остаётся в поле
  void _clear() {
    _memo = null;
    _q.clear();
    setState(() {
      _stop();
      _refHit = null;
      _strongHit = null;
    });
    _focus.requestFocus();
  }

  void _goRef(VerseRef r) {
    _remember(_q.text.trim());
    Navigator.pop(context);
    ref.read(panesProvider.notifier).navigate(widget.pane, r);
  }

  void _submit() {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    if (_refHit != null) return _goRef(_refHit!.ref);
    _remember(q);
    _focus.unfocus();
  }

  // Место из другого перевода открывается в этом переводе
  void _open(SearchHit h, String moduleId) {
    _remember(_ran);
    Navigator.pop(context);
    final n = ref.read(panesProvider.notifier);
    if (moduleId != _pane.moduleId && ModuleStore.instance.get(moduleId) != null) n.setModule(widget.pane, moduleId);
    n.navigate(widget.pane, h.ref, highlight: _ran.isEmpty ? null : _ran);
  }

  Future<void> _copy(SearchHit h) async {
    final label = Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse);
    await Clipboard.setData(ClipboardData(text: '"${h.snippet.replaceAll(RegExp(r'\s+'), ' ').trim()}" - $label'));
    Hub.toast(t('Стих скопирован'));
  }

  // Убрать запрос из истории — с «Отменить»
  void _forget(String h) {
    final i = _history.indexOf(h);
    setState(() => _history = _history.where((x) => x != h).toList());
    _save('searchHistory', _history);
    Hub.toast(t('Убрано из истории'), actionLabel: t('Отменить'), action: () {
      if (!mounted || _history.contains(h)) return;
      setState(() => _history = [..._history.take(i), h, ..._history.skip(i)]);
      _save('searchHistory', _history);
    });
  }

  void _setOption(String key, Object v, VoidCallback apply) {
    setState(apply);
    _save(key, v);
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final pal = settings.palette;
    final m = _module;
    final targets = _targets;
    final multi = targets.length > 1;
    final hits = _hits;
    final re = _ran.isEmpty ? null : queryRegex(_ran, wholeWord: _whole);
    final textStyle = readerTextStyle(settings, size: 16).copyWith(color: pal.text, height: 1.5);
    const gap = SizedBox(height: 12);

    final top = <Widget>[
      _form(pal),
      gap,
      Segmented<String>(
        options: [('all', t('Вся Библия')), ('OT', t('ВЗ')), ('NT', t('НЗ')), ('book', Books.instance.meta(_pane.ref.book).short)],
        value: _scope,
        onChanged: (v) => _setOption('searchScope', v, () => _scope = v),
      ),
      gap,
      SwitchRow(
        label: t('Только целые слова'),
        hint: t('Иначе «свет» найдёт и «светильник»'),
        value: _whole,
        onChanged: (v) => _setOption('searchWhole', v, () => _whole = v),
      ),
      if (_canAll)
        SwitchRow(
          label: t('Во всех модулях'),
          hint: t('Искать во всех установленных переводах. У каждого места — метка перевода.'),
          value: _allMods,
          onChanged: (v) => _setOption('searchAllModules', v, () => _allMods = v),
        ),
      if (_canAll && _allMods && _hasOrig)
        SwitchRow(
          label: t('И в оригиналах'),
          hint: t('Еврейский и греческий текст — для поиска слов на иврите и греческом.'),
          value: _withOrig,
          onChanged: (v) => _setOption('searchOriginals', v, () => _withOrig = v),
        ),
      if (_refHit != null) ...[gap, _refCard(pal, textStyle, m)],
      if (_strongHit != null && Hub.strongSearchCard != null)
        for (final num in _strongHit!) ...[
          gap,
          Hub.strongSearchCard!(context, ref, widget.pane, num, _strongFilter, _goRef, () => _remember(_q.text.trim())),
        ],
      if (_progress != null) ...[gap, AobProgress(value: _progress!.p, label: _progress!.label)],
      if (hits == null && _refHit == null && _strongHit == null && _history.isNotEmpty) ...[gap, ..._historyList(pal)],
      if (hits != null) ...[
        gap,
        Row(children: [
          if (_progress != null) ...[const Spinner(size: 14), const SizedBox(width: 6)],
          Expanded(
            child: Text(
              t('Найдено: {n}', {'n': '${hits.length}'}) +
                  (_progress == null && hits.isEmpty ? ' — ${t('попробуйте другую форму слова или отключите «целые слова».')}' : ''),
              style: TextStyle(fontSize: 14, color: pal.muted),
            ),
          ),
        ]),
      ],
    ];

    final count = hits == null ? 0 : (hits.length < _shown ? hits.length : _shown);
    final more = hits != null && hits.length > _shown;
    return AobSheet(
      title: t('Поиск'),
      subtitle: m == null ? null : (multi ? '${t('Во всех модулях')} · ${targets.length}' : '${m.name} · ${m.title}'),
      scroll: false,
      padding: EdgeInsets.zero,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + MediaQuery.paddingOf(context).bottom),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: 1 + count + (more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: top);
          if (i == count + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AobButton(
                label: t('Показать ещё ({n})', {'n': '${hits!.length - _shown}'}),
                wide: true,
                onTap: () {
                  setState(() => _shown += _page);
                  if (_memo != null && _memo!.key == _shownKey) _memo!.shown = _shown;
                },
              ),
            );
          }
          final mod = multi ? ModuleStore.instance.get(_hitMods[i - 1]) : null;
          return _resultRow(pal, textStyle, hits![i - 1], mod, re);
        },
      ),
    );
  }

  // Поле запроса с крестиком и тёмная квадратная кнопка «Найти» (.search-form)
  Widget _form(Palette pal) {
    final focused = _focus.hasFocus;
    return Row(children: [
      Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 46,
          decoration: BoxDecoration(
            color: pal.bg,
            borderRadius: BorderRadius.circular(kRadius * 0.75),
            border: Border.all(color: focused ? pal.accent : pal.line),
            boxShadow: focused ? [BoxShadow(color: pal.accent.withValues(alpha: 0.22), spreadRadius: 3)] : null,
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  setState(() {});
                  _schedule();
                },
                onSubmitted: (_) => _submit(),
                cursorColor: pal.accent,
                style: TextStyle(fontSize: 16, height: 1.25, color: pal.text),
                // поле — ровно одна строка, по центру рамки (Row центрирует по высоте): отступы сверху и снизу
                // на разных шрифтах уводили текст вверх
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: t('Слово, Ин 3:16 или G26'),
                  hintStyle: TextStyle(color: pal.muted, height: 1.25),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                ),
              ),
            ),
            if (_q.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: IconBtn(icon: LucideIcons.x, subtle: true, size: 18, tooltip: t('Очистить'), onTap: _clear),
              ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: t('Найти'),
        child: Material(
          color: pal.accent,
          borderRadius: BorderRadius.circular(kRadius * 0.75),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: _submit, child: SizedBox(width: 46, height: 46, child: Icon(LucideIcons.search, size: 18, color: pal.onAccent))),
        ),
      ),
    ]);
  }

  // Карточка перехода по ссылке (.ref-hit)
  Widget _refCard(Palette pal, TextStyle textStyle, InstalledModule? m) {
    final r = _refHit!;
    final b = Books.instance.meta(r.ref.book);
    return Material(
      color: mix(pal.accent, 0.07, pal.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: mix(pal.accent, 0.45, pal.line))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _goRef(r.ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(LucideIcons.cornerDownLeft, size: 15, color: pal.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(t('Перейти: {ref}', {'ref': '${b.name} ${r.ref.chapter}:${r.ref.verse}'}), style: TextStyle(fontWeight: FontWeight.w700, color: pal.accent)),
              ),
            ]),
            const SizedBox(height: 4),
            r.text != null
                ? Text(r.text!, style: textStyle)
                : Text(t('В переводе {module} нет такого стиха.', {'module': m?.name ?? ''}), style: TextStyle(color: pal.muted)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _historyList(Palette pal) => [
        GroupTitle(t('Недавние')),
        for (final h in _history)
          Dismissible(
            key: ValueKey('sh-$h'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: const Color(0xffd1342b),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 18),
              child: const Icon(LucideIcons.trash2, size: 18, color: Colors.white),
            ),
            onDismissed: (_) => _forget(h),
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
              child: Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _setQuery(h);
                      _remember(h);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      child: Row(children: [
                        Icon(LucideIcons.clock, size: 16, color: pal.muted),
                        const SizedBox(width: 12),
                        Expanded(child: Text(h, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 15, color: pal.text))),
                      ]),
                    ),
                  ),
                ),
                IconBtn(icon: LucideIcons.x, subtle: true, size: 16, tooltip: t('Убрать из истории'), onTap: () => _forget(h)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AobButton(
              block: true,
              label: t('Очистить историю'),
              small: true,
              onTap: () {
                setState(() => _history = []);
                _save('searchHistory', <String>[]);
              },
            ),
          ),
        ),
      ];

  // Строка результата (.result-row): ссылка, метка перевода, текст с подсветкой, справа «Копировать»
  Widget _resultRow(Palette pal, TextStyle textStyle, SearchHit h, InstalledModule? mod, RegExp? re) {
    final label = Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse);
    return Stack(children: [
      InkWell(
        onTap: () => _open(h, mod?.id ?? _pane.moduleId),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(4, 11, 44, 11),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(label, style: TextStyle(fontSize: 14.7, fontWeight: FontWeight.w700, color: pal.accent))),
              if (mod != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(6)),
                  child: Text(shortName(mod), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, height: 1.2, color: pal.muted)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text.rich(_highlight(h.snippet, re, pal), style: textStyle),
          ]),
        ),
      ),
      Positioned(top: 5, right: 0, child: IconBtn(icon: LucideIcons.copy, subtle: true, size: 16, tooltip: t('Копировать'), onTap: () => _copy(h))),
    ]);
  }

  // Найденное — подсветкой (mark): ровно то, что совпало с запросом
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
}
