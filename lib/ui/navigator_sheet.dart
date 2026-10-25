// «Перейти» (BookNavigator.jsx, styles.css .bn-*): одно поле — ссылка («Ин 3:16», Enter) или первые буквы книги
// («кор», «1 ин») — список сразу сужается; недавние книги, Ветхий / Новый Завет / Апокрифы (свайп по окну тоже
// переключает), разделы с цветной точкой и плитками «сокращение + название», затем главы и стихи.
// Шаги сменяют друг друга сдвигом: вперёд — справа, назад — слева.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import 'kit.dart';

Future<void> openNavigator(BuildContext context, int pane) => showAobSheet(context, builder: (_) => NavigatorSheet(pane: pane));

// Разделы Библии с цветами (src/core/bookCategories.js); «Неканонические» стоят после малых пророков
const _categories = <(String, int, List<String>)>[
  ('Пятикнижие', 0xffb07a2e, ['Gen', 'Exod', 'Lev', 'Num', 'Deut']),
  ('Исторические книги', 0xff6b8e4e, ['Josh', 'Judg', 'Ruth', '1Sam', '2Sam', '1Kgs', '2Kgs', '1Chr', '2Chr', 'Ezra', 'Neh', 'Esth']),
  ('Поэтические книги', 0xff3f7fa6, ['Job', 'Ps', 'Prov', 'Eccl', 'Song']),
  ('Большие пророки', 0xff8b4a7d, ['Isa', 'Jer', 'Lam', 'Ezek', 'Dan']),
  ('Малые пророки', 0xffb0688f, ['Hos', 'Joel', 'Amos', 'Obad', 'Jonah', 'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal']),
  ('Неканонические книги', 0xff8a8172, []),
  ('Евангелия', 0xffc0533a, ['Matt', 'Mark', 'Luke', 'John']),
  ('Деяния и соборные послания', 0xff2f8f83, ['Acts', 'Jas', '1Pet', '2Pet', '1John', '2John', '3John', 'Jude']),
  ('Послания апостола Павла', 0xff4a68ad, ['Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col', '1Thess', '2Thess', '1Tim', '2Tim', 'Titus', 'Phlm', 'Heb']),
  ('Откровение', 0xff7a55a8, ['Rev']),
];
const _otherCat = ('Другие книги', 0xff8a8172, <String>[]);

/// Книги с пометкой dc в справочнике (неканонические): в списке — со звёздочкой «*»
const _dcIds = {'PrMan', '1Esd', 'Tob', 'Jdt', 'Wis', 'Sir', 'EpJer', 'Bar', '1Macc', '2Macc', '3Macc', '2Esd'};

(String, int, List<String>) _categoryOf(String id) {
  if (_dcIds.contains(id)) return _categories[5];
  for (final c in _categories) {
    if (c.$3.contains(id)) return c;
  }
  return _otherCat;
}

const _testaments = <(String, String)>[('OT', 'Ветхий Завет'), ('NT', 'Новый Завет'), ('AP', 'Апокрифы')];

// Сравнение без регистра, точек, пробелов и дефисов; «ё» = «е»: «1 кор» ≈ «1Кор.»
String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[\s.\-–]'), '');
List<String> _words(String s) => s.toLowerCase().replaceAll('ё', 'е').split(RegExp(r'[\s.\-–]+')).where((w) => w.length > 1).toList();
// Только буквы (можно с номером книги впереди: «1 кор») — ищем книгу; цифры после букв — это уже ссылка
bool _isBookQuery(String q) => q.trim().isNotEmpty && RegExp(r'^\s*[1-4]?\s*([^\d\s:.,][^\d:,]*)?$').hasMatch(q);

/// Книга модуля: id, название и сокращение (на языке интерфейса), число глав
class _Book {
  _Book(this.id, this.name, this.short, this.chapters, this.testament);
  final String id, name, short, testament;
  final int chapters;
}

/// Сколько стихов в каждой главе (индекс 0 — глава 1); нет данных — пусто
List<int> _verseCounts(String moduleId, String book) {
  try {
    final rows = ModuleStore.instance.db(moduleId).select('SELECT chapter, MAX(verse) AS n FROM verses WHERE book = ? GROUP BY chapter', [book]);
    final m = {for (final r in rows) r['chapter'] as int: r['n'] as int};
    if (m.isEmpty) return const [];
    final last = m.keys.reduce((a, b) => a > b ? a : b);
    return [for (var c = 1; c <= last; c++) m[c] ?? 0];
  } catch (_) {
    return const [];
  }
}

class NavigatorSheet extends ConsumerStatefulWidget {
  const NavigatorSheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<NavigatorSheet> createState() => _NavigatorSheetState();
}

class _NavigatorSheetState extends ConsumerState<NavigatorSheet> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _listCtl = ScrollController();
  final _counts = <String, List<int>>{};
  String? _book; // выбрана книга — показываем главы
  int? _chapter; // выбрана глава — показываем стихи
  late String _tab;
  late String _moduleId;
  String _err = '';
  bool _forward = true; // куда едут шаги: вперёд — справа
  double _listOffset = 0; // где был список книг — туда же вернёмся «назад»

  @override
  void initState() {
    super.initState();
    final p = ref.read(panesProvider)[widget.pane];
    _moduleId = p.moduleId;
    final at = livePositions[widget.pane]?.value ?? p.ref;
    final cur = Books.instance.meta(at.book).testament;
    final groups = _groups();
    _tab = groups.contains(cur) ? cur : (groups.isEmpty ? 'OT' : groups.first);
    _input.addListener(() => setState(() => _err = ''));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  List<_Book> _books() {
    final b = Books.instance;
    return [
      for (final x in bookList(_moduleId))
        () {
          final id = x['id'] as String;
          final m = b.meta(id, name: x['name'] as String?, short: x['short'] as String?);
          return _Book(id, m.name, m.short, (x['chapters'] as num?)?.toInt() ?? 0, m.testament);
        }(),
    ];
  }

  List<String> _groups() {
    final all = _books();
    return [for (final tt in _testaments) if (all.any((x) => x.testament == tt.$1)) tt.$1];
  }

  List<int> _verses(String book) => _counts.putIfAbsent(book, () => _verseCounts(_moduleId, book));

  void _go(VerseRef r) {
    ref.read(panesProvider.notifier).navigate(widget.pane, r);
    Navigator.pop(context);
  }

  double get _offset => _listCtl.positions.isEmpty ? 0 : _listCtl.positions.last.pixels;

  void _openBook(_Book b) {
    if (_book == null) _listOffset = _offset;
    setState(() {
      _forward = true;
      _book = b.id;
      _chapter = b.chapters == 1 ? 1 : null; // в книге одна глава — сразу стихи
      _err = '';
    });
  }

  void _openChapter(int n) => setState(() {
        _forward = true;
        _chapter = n;
      });

  void _back() {
    final single = (_books().where((b) => b.id == _book).firstOrNull?.chapters ?? 0) == 1;
    final toList = _chapter == null || single;
    setState(() {
      _forward = false;
      if (toList) _book = null;
      _chapter = null;
    });
    if (toList) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _listCtl.positions.length == 1) _listCtl.jumpTo(_listOffset.clamp(0, _listCtl.position.maxScrollExtent));
      });
    }
  }

  void _pickTab(String id) {
    if (id == _tab) return;
    final groups = _groups();
    setState(() {
      _forward = groups.indexOf(id) > groups.indexOf(_tab);
      _tab = id;
    });
    // Переключатель «прилип» к верху — новый список показываем с начала, а не с середины
    if (_listCtl.positions.length == 1 && _listCtl.offset > 0) _listCtl.jumpTo(0);
  }

  List<_Book> _match(List<_Book> books, String q) {
    final k = _norm(q);
    if (k.isEmpty) return const [];
    final alias = Books.instance.findBookId(q);
    bool hit(_Book b) => b.id == alias || _norm(b.short).startsWith(k) || _norm(b.name).startsWith(k) || _words(b.name).any((w) => w.startsWith(k));
    final list = books.where(hit).toList();
    // Точное сокращение («мф», «ин») — первым
    return alias != null ? [...list.where((b) => b.id == alias), ...list.where((b) => b.id != alias)] : list;
  }

  int _lastVerse(String book, int chapter) {
    final counts = _verses(book);
    final n = chapter >= 1 && chapter <= counts.length ? counts[chapter - 1] : 0;
    return n < 1 ? 1 : n;
  }

  /// Ссылка уже понятна — куда приведёт Enter
  ({VerseRef ref, String label})? _refHit(List<_Book> books, String q) {
    if (_isBookQuery(q) || q.trim().isEmpty) return null;
    final r = Books.instance.parseHuman(q);
    final b = r == null ? null : books.where((x) => x.id == r.book).firstOrNull;
    if (r == null || b == null || r.chapter < 1 || r.chapter > b.chapters) return null;
    final verse = r.verse.clamp(1, _lastVerse(b.id, r.chapter));
    return (ref: VerseRef(b.id, r.chapter, verse), label: '${b.name} ${r.chapter}:$verse');
  }

  void _submit() {
    final books = _books();
    final q = _input.text;
    final r = Books.instance.parseHuman(q);
    if (r == null) {
      // Только название книги («Ин», «бытие») — открываем её главы
      if (_isBookQuery(q)) {
        final id = Books.instance.findBookId(q);
        final matches = _match(books, q);
        final only = books.where((b) => b.id == id).firstOrNull ?? (matches.length == 1 ? matches.first : null);
        if (only != null) return _openBook(only);
      }
      return setState(() => _err = t('Не понял ссылку. Пример: Ин 3:16'));
    }
    final b = books.where((x) => x.id == r.book).firstOrNull;
    final name = ModuleStore.instance.get(_moduleId)?.name ?? _moduleId;
    if (b == null) return setState(() => _err = t('В переводе {module} нет этой книги.', {'module': name}));
    if (r.chapter < 1 || r.chapter > b.chapters) return setState(() => _err = t('В книге «{book}» {n} глав.', {'book': b.name, 'n': '${b.chapters}'}));
    _go(VerseRef(b.id, r.chapter, r.verse.clamp(1, _lastVerse(b.id, r.chapter))));
  }

  void _clear() {
    _input.clear();
    _focus.requestFocus();
  }

  Widget _slide(Widget child, Animation<double> anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(position: Tween<Offset>(begin: Offset(_forward ? 0.12 : -0.12, 0), end: Offset.zero).animate(anim), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final p = ref.read(panesProvider)[widget.pane];
    final at = livePositions[widget.pane]?.value ?? p.ref;
    final books = _books();
    final module = ModuleStore.instance.get(_moduleId);
    final fill = mix(pal.text, 0.055, pal.panel);
    final muted = mix(pal.muted, 0.8, pal.text);
    final selBook = _book == null ? null : books.where((b) => b.id == _book).firstOrNull;
    final single = selBook?.chapters == 1;
    final title = selBook == null ? t('Перейти') : (_chapter != null && !single ? '${selBook.name} $_chapter' : selBook.name);
    final Widget step;
    if (selBook == null) {
      step = _list(pal, fill, muted, books, p, at);
    } else if (_chapter == null) {
      step = _chapters(pal, fill, selBook, at);
    } else {
      step = _verseStep(pal, fill, selBook, _chapter!, at);
    }
    // Свайп по окну влево-вправо переключает Ветхий / Новый Завет / Апокрифы
    final groups = _groups();
    return AobSheet(
      title: title,
      subtitle: selBook != null ? t(_categoryOf(selBook.id).$1) : (module?.title ?? module?.name),
      onBack: selBook != null ? _back : null,
      scroll: false,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: selBook != null || groups.length < 2
            ? null
            : (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 250) return;
                final i = groups.indexOf(_tab) + (v < 0 ? 1 : -1);
                if (i >= 0 && i < groups.length) _pickTab(groups[i]);
              },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => _slide(child, anim),
          child: KeyedSubtree(key: ValueKey('$_book|$_chapter'), child: step),
        ),
      ),
    );
  }

  // --- Шаг 1: поле, недавние, разделы -----------------------------------------------------------------

  Widget _list(Palette pal, Color fill, Color muted, List<_Book> books, PaneState p, VerseRef at) {
    final q = _input.text;
    final bookMode = _isBookQuery(q);
    final matches = bookMode ? _match(books, q) : const <_Book>[];
    final hit = _refHit(books, q);
    final groups = _groups();
    final group = groups.contains(_tab) ? _tab : (groups.isEmpty ? 'OT' : groups.first);
    // Недавние книги — из истории переходов панели, текущая первой
    final ids = <String>[at.book];
    for (final r in p.history.reversed) {
      if (ids.length >= 8) break;
      if (!ids.contains(r.book)) ids.add(r.book);
    }
    final recent = [for (final id in ids) ?books.where((x) => x.id == id).firstOrNull];
    final focused = _focus.hasFocus;
    final desktop = const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);
    final bottomPad = 20 + MediaQuery.paddingOf(context).bottom;

    final top = <Widget>[
      // Строка ссылки (.bn-search): высота 50, скругление 15; в фокусе — рамка акцента и кольцо
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 50,
        decoration: BoxDecoration(
          color: focused ? pal.panel : fill,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: focused ? pal.accent : Colors.transparent),
          boxShadow: focused ? [BoxShadow(color: pal.accent.withValues(alpha: 0.2), spreadRadius: 3)] : null,
        ),
        child: Row(children: [
          const SizedBox(width: 14),
          Icon(LucideIcons.search, size: 18, color: muted),
          Expanded(
            child: Focus(
              // Escape в заполненном поле сначала стирает его, второй — закрывает окно
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && _input.text.isNotEmpty) {
                  _input.clear();
                  setState(() => _err = '');
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _input,
                focusNode: _focus,
                autofocus: desktop, // на компьютере сразу можно печатать «Ин 3:16» (на телефоне клавиатура не выскакивает сама)
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontSize: 16, color: pal.text),
                decoration: InputDecoration(
                  hintText: t('Книга или ссылка: Ин 3:16'),
                  hintStyle: TextStyle(color: muted, overflow: TextOverflow.fade),
                  hintMaxLines: 1,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
          if (q.isNotEmpty)
            SizedBox(width: 44, height: 44, child: IconButton(padding: EdgeInsets.zero, tooltip: t('Очистить'), onPressed: _clear, icon: Icon(LucideIcons.x, size: 18, color: muted))),
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Tooltip(
              message: t('Перейти'),
              child: Material(
                color: q.isEmpty ? Colors.transparent : pal.accent,
                shape: const CircleBorder(),
                child: InkWell(customBorder: const CircleBorder(), onTap: _submit, child: SizedBox(width: 44, height: 44, child: Icon(LucideIcons.arrowRight, size: 18, color: q.isEmpty ? muted : pal.onAccent))),
              ),
            ),
          ),
        ]),
      ),
      if (_err.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(_err, style: const TextStyle(color: Color(0xffc93a3a), fontSize: 13))),
      if (hit != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Material(
            color: mix(pal.accent, 0.08, pal.panel),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: mix(pal.accent, 0.4, pal.line))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _go(hit.ref),
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(LucideIcons.cornerDownLeft, size: 18, color: pal.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t('Перейти: {ref}', {'ref': hit.label}), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text))),
                ]),
              ),
            ),
          ),
        ),
      if (bookMode && matches.isEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: Text(t('Ничего не найдено.'), style: TextStyle(color: muted)))),
      if (bookMode && matches.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: _grid(pal, fill, matches, at)),
      if (!bookMode && q.trim().isEmpty && recent.isNotEmpty) ...[
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(t('Недавние'), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: muted))),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(vertical: 2), children: [
            for (final b in recent)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: b.id == at.book ? mix(pal.accent, 0.14, pal.panel) : fill,
                  shape: StadiumBorder(side: b.id == at.book ? BorderSide(color: pal.accent, width: 1.5) : BorderSide.none),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openBook(b),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      child: Text(b.name, style: TextStyle(fontSize: 14.7, fontWeight: b.id == at.book ? FontWeight.w600 : FontWeight.w500, color: pal.text)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ],
    ];

    final showBooks = !bookMode && q.trim().isEmpty;
    final shown = books.where((b) => b.testament == group).toList();
    // Разделы по порядку «Пятикнижие … Откровение», внутри — в порядке перевода
    final byCat = <(String, int, List<String>), List<_Book>>{};
    for (final b in shown) {
      byCat.putIfAbsent(_categoryOf(b.id), () => []).add(b);
    }
    final panel = KeyedSubtree(
      key: ValueKey('tab-$group'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in [..._categories, _otherCat])
          if (byCat.containsKey(c)) ...[
            const SizedBox(height: 22),
            Row(children: [
              const SizedBox(width: 2),
              Container(width: 7, height: 7, decoration: BoxDecoration(color: Color(c.$2), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(t(c.$1), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: muted))),
            ]),
            const SizedBox(height: 10),
            _grid(pal, fill, byCat[c]!, at),
          ],
      ]),
    );

    return CustomScrollView(
      controller: _listCtl,
      slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), sliver: SliverList.list(children: top)),
        if (showBooks && groups.length > 1)
          SliverPersistentHeader(pinned: true, delegate: _SegHeader(bg: pal.panel, child: _Seg(groups: groups, tab: group, fill: fill, muted: muted, pal: pal, onPick: _pickTab))),
        if (showBooks)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => _slide(child, anim),
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
                child: panel,
              ),
            ),
          )
        else
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
      ],
    );
  }

  Widget _grid(Palette pal, Color fill, List<_Book> list, VerseRef at) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 108).floor().clamp(3, 8);
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final b in list)
            SizedBox(
              width: w,
              child: _BookCell(
                short: b.short.replaceAll(RegExp(r'\.$'), ''),
                name: b.name,
                dc: _dcIds.contains(b.id),
                on: b.id == at.book,
                fill: fill,
                pal: pal,
                onTap: () => _openBook(b),
              ),
            ),
        ]);
      });

  // --- Шаги 2 и 3: главы и стихи (сетка номеров) ---------------------------------------------------------

  Widget _numGrid(Palette pal, Color fill, int n, bool Function(int) on, void Function(int) tap) => LayoutBuilder(builder: (context, c) {
        final minW = MediaQuery.sizeOf(context).width >= 820 ? 56.0 : 52.0;
        final cols = ((c.maxWidth + 8) / (minW + 8)).floor().clamp(1, 20);
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 1; i <= n; i++)
            SizedBox(
              width: w,
              height: 52,
              child: Material(
                color: on(i) ? pal.accent : fill,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => tap(i),
                  child: Center(child: Text('$i', style: TextStyle(fontSize: 16.6, fontWeight: FontWeight.w600, color: on(i) ? pal.onAccent : pal.text, fontFeatures: const [FontFeature.tabularFigures()]))),
                ),
              ),
            ),
        ]);
      });

  Widget _chapters(Palette pal, Color fill, _Book b, VerseRef at) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + MediaQuery.paddingOf(context).bottom),
        child: _numGrid(pal, fill, b.chapters, (n) => at.book == b.id && at.chapter == n, _openChapter),
      );

  Widget _verseStep(Palette pal, Color fill, _Book b, int ch, VerseRef at) {
    final counts = _verses(b.id);
    final n = ch <= counts.length ? counts[ch - 1] : 0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: mix(pal.accent, 0.13, pal.panel),
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _go(VerseRef(b.id, ch, 1)),
            child: SizedBox(
              height: 52,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.bookOpen, size: 19, color: pal.accent),
                const SizedBox(width: 10),
                Text(t('С начала главы'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _numGrid(pal, fill, n, (v) => at.book == b.id && at.chapter == ch && at.verse == v, (v) => _go(VerseRef(b.id, ch, v))),
      ]),
    );
  }
}

/// Закреплённый переключатель Ветхий / Новый Завет / Апокрифы: при прокрутке остаётся сверху (.bn-seg-wrap)
class _SegHeader extends SliverPersistentHeaderDelegate {
  _SegHeader({required this.bg, required this.child});
  final Color bg;
  final Widget child;
  @override
  double get minExtent => 68;
  @override
  double get maxExtent => 68;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: bg, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), alignment: Alignment.center, child: child);
  @override
  bool shouldRebuild(_SegHeader old) => true;
}

/// Дорожка с «таблеткой»: выбранный раздел — плашка цвета окна, переезжает к новому
class _Seg extends StatelessWidget {
  const _Seg({required this.groups, required this.tab, required this.fill, required this.muted, required this.pal, required this.onPick});
  final List<String> groups;
  final String tab;
  final Color fill, muted;
  final Palette pal;
  final void Function(String) onPick;
  @override
  Widget build(BuildContext context) {
    final i = groups.indexOf(tab);
    final label = {for (final x in _testaments) x.$1: x.$2};
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(15)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / groups.length;
        return SizedBox(
          height: 44,
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: w * i,
              top: 0,
              bottom: 0,
              width: w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pal.dark ? mix(pal.text, 0.14, pal.panel) : pal.panel,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
              ),
            ),
            Row(children: [
              for (final g in groups)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: g == tab,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPick(g),
                      child: Center(child: Text(t(label[g]!), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.7, fontWeight: g == tab ? FontWeight.w600 : FontWeight.w500, color: g == tab ? pal.text : muted))),
                    ),
                  ),
                ),
            ]),
          ]),
        );
      }),
    );
  }
}

/// Плитка книги (.book-cell): скругление 14, крупное сокращение (у неканонических — «*»), под ним название; текущая — с рамкой акцента
class _BookCell extends StatelessWidget {
  const _BookCell({required this.short, required this.name, required this.on, required this.fill, required this.pal, required this.onTap, this.dc = false});
  final String short, name;
  final bool on, dc;
  final Color fill;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: on ? mix(pal.accent, 0.14, pal.panel) : fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: on ? BorderSide(color: pal.accent, width: 1.5) : BorderSide.none),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(short, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 16.6, fontWeight: FontWeight.w700, height: 1.15, color: pal.text, letterSpacing: -0.17))),
                if (dc) Transform.translate(offset: const Offset(1, -4), child: Text('*', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.accent))),
              ]),
              const SizedBox(height: 3),
              Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: 12.2, height: 1.25, color: on ? mix(pal.muted, 0.45, pal.text) : mix(pal.muted, 0.8, pal.text))),
            ]),
          ),
        ),
      );
}
