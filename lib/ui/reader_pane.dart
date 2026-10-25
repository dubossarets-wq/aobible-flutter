// Панель чтения: вся книга одним ленивым списком (рисуются только видимые стихи).
// Переход к стиху — jumpTo по индексу; текущее место — по видимым элементам; синхронная прокрутка —
// вторая панель встаёт на тот же стих с той же долей прочитанного, в том же кадре.
// Режимы «Сплошной» и «Как книга» — стихи идут абзацами: строка списка — абзац, а место внутри абзаца
// узнаём у самого блока (BlockHandle). Здесь же: свайп главы, щипок размера шрифта, режим чтения,
// полоса прогресса книги, подсветка найденного слова и мигание стиха после перехода.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/i18n.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import 'kit.dart';
import 'verse_view.dart';

/// Подсветка найденного слова держится столько после перехода (HL_MS в ChapterView.jsx)
const kHighlightMs = 8000;
const _fontMin = 13, _fontMax = 40; // FONT_MIN / FONT_MAX в usePinchFont.js

// Строка списка: заголовок главы, заголовок раздела, стих или абзац стихов
class _Row {
  _Row(this.start, this.end, this.para);
  final int start; // первый элемент книги
  int end; // за последним
  final bool para;
  List<ReaderItem> verses = const [];
}

class ReaderPane extends ConsumerStatefulWidget {
  const ReaderPane({super.key, required this.index});
  final int index;

  @override
  ConsumerState<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends ConsumerState<ReaderPane> with SingleTickerProviderStateMixin {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  BookText? _book;
  int _nav = -1;
  String? _module;
  int _initialIndex = 0;
  int _listKey = 0;
  bool _following = false; // прокрутку сейчас ставит синхронизация (не человек)
  double _vh = 800; // высота окна чтения

  // Строки списка и соответствие «элемент книги → строка»
  List<_Row> _rows = [];
  List<int> _rowOf = [];
  List<int> _verseOrd = []; // сколько стихов книги до элемента включительно (полоса прогресса)
  String? _rowsKey;
  final _rowFrac = <int, double>{}; // доля высоты окна, которую занимала строка в последний раз

  // Пометки последнего перехода: найденное слово и мигание стиха
  int _markStamp = 0;
  VerseRef? _mkRef;
  String? _mkQuery;
  bool _mkFlash = false;
  bool _hlFade = false;
  Timer? _hlFadeTimer, _hlEndTimer;

  // Щипок двумя пальцами — размер шрифта
  final _pointers = <int, Offset>{};
  bool _pinching = false;
  int? _pinchFs;
  double _pinchD0 = 1;
  double _pinchFs0 = 19;
  final _badge = ValueNotifier<String?>(null);
  Timer? _badgeTimer;

  // Свайп главы: текст идёт за пальцем
  ({double x, double y, int t, int dir})? _sw;
  final _drag = ValueNotifier<(double, double)>((0, 1)); // сдвиг и прозрачность текста
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  double _backFrom = 0;

  // Режим чтения: направление прокрутки
  double _dirAcc = 0;

  // Учёт прочитанного (как в веб-версии): глава засчитана, если видна до последнего стиха и на ней провели
  // не меньше max(8, min(120, стихов × 2,5)) секунд; раз в секунду, только пока приложение на экране
  Timer? _dwellTimer;
  final _dwell = <int, int>{}; // глава → секунд на экране
  final _done = <String>{}; // «книга.глава» — уже засчитано в этом сеансе

  void _tickDwell() {
    final book = _book;
    if (book == null || !mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final pos = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1).toList();
    if (pos.isEmpty) return;
    final chapters = <int>{};
    final lastVisible = <int>{};
    for (final p in pos) {
      if (p.index >= _rows.length) continue;
      final row = _rows[p.index];
      for (var i = row.start; i < row.end; i++) {
        chapters.add(book.items[i].chapter);
      }
      final it = book.items[row.end - 1];
      final next = row.end < book.items.length ? book.items[row.end] : null;
      if (it.kind == ItemKind.verse && (next == null || next.chapter != it.chapter) && p.itemTrailingEdge <= 1.02) lastVisible.add(it.chapter);
    }
    for (final c in chapters) {
      final secs = _dwell[c] = (_dwell[c] ?? 0) + 1;
      final key = '${book.book}.$c';
      if (!lastVisible.contains(c) || _done.contains(key)) continue;
      final n = book.items.where((x) => x.kind == ItemKind.verse && x.chapter == c).length;
      if (secs >= math.max(8, math.min(120, n * 2.5))) {
        _done.add(key);
        Hub.onChapterRead?.call(context, ref, book.book, c);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    SyncHub.listeners[widget.index] = _follow;
    _dwellTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickDwell());
    _back.addListener(() {
      final k = 1 - Curves.easeOut.transform(_back.value);
      _drag.value = (_backFrom * k, 1 - math.min(0.35, (_backFrom * k).abs() / 315));
    });
    partSelection.addListener(_onPartChange);
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _hlFadeTimer?.cancel();
    _hlEndTimer?.cancel();
    _badgeTimer?.cancel();
    _back.dispose();
    partSelection.removeListener(_onPartChange);
    _positions.itemPositions.removeListener(_onPositions);
    if (SyncHub.listeners[widget.index] == _follow) SyncHub.listeners.remove(widget.index);
    // Панель закрыта: выбор части стиха и скрытые панели режима чтения не должны остаться
    final idx = widget.index;
    Future.microtask(() {
      final ps = partSelection.value;
      if (ps != null && ps.pane == idx) partSelection.value = null;
      if (idx == 0 && focusHidden.value) focusHidden.value = false;
    });
    super.dispose();
  }

  void _onPartChange() {
    if (mounted) setState(() {}); // жесты (свайп, щипок) на время выбора части стиха не работают
  }

  // ---- строки списка ----
  void _buildRows(bool cont, bool showHeadings) {
    final b = _book!;
    final rows = <_Row>[];
    final rowOf = List<int>.filled(b.items.length, 0);
    final ord = List<int>.filled(b.items.length, 0);
    var n = 0;
    for (var i = 0; i < b.items.length; i++) {
      final it = b.items[i];
      if (it.kind == ItemKind.verse) n++;
      ord[i] = n;
      if (!cont) {
        rowOf[i] = rows.length;
        rows.add(_Row(i, i + 1, false));
        continue;
      }
      switch (it.kind) {
        case ItemKind.chapter:
          rowOf[i] = rows.length;
          rows.add(_Row(i, i + 1, false));
        case ItemKind.heading:
          rowOf[i] = rows.length;
          if (showHeadings) rows.add(_Row(i, i + 1, false));
        case ItemKind.verse:
          final last = rows.isEmpty ? null : rows.last;
          if (last != null && last.para && b.items[last.end - 1].chapter == it.chapter) {
            last.end = i + 1;
            rowOf[i] = rows.length - 1;
          } else {
            rowOf[i] = rows.length;
            rows.add(_Row(i, i + 1, true));
          }
      }
    }
    for (final r in rows) {
      if (r.para) r.verses = [for (var i = r.start; i < r.end; i++) if (b.items[i].kind == ItemKind.verse) b.items[i]];
    }
    // Заголовок раздела без строки (скрыт) указывает на следующую строку — не дальше последней
    for (var i = 0; i < rowOf.length; i++) {
      if (rowOf[i] >= rows.length) rowOf[i] = rows.length - 1;
    }
    _rows = rows;
    _rowOf = rowOf;
    _verseOrd = ord;
    _rowsKey = '$cont|$showHeadings';
    _rowFrac.clear();
  }

  int _itemOf(VerseRef r) => _book!.indexOf(r.chapter, r.verse);

  void _open(PaneState p, bool cont, bool showHeadings) {
    final sameBook = _book != null && _book!.book == p.ref.book && _module == p.moduleId;
    if (!sameBook) {
      _book = loadBook(p.moduleId, p.ref.book);
      _module = p.moduleId;
      _buildRows(cont, showHeadings);
      _initialIndex = _rowOf[_itemOf(p.ref)];
      _listKey++; // новая книга — новый список, сразу на нужном месте (без прокрутки после показа)
      _alignAfterFrame(p.ref);
    } else if (_scroll.isAttached) {
      _scroll.jumpTo(index: _rowOf[_itemOf(p.ref)]);
      _alignAfterFrame(p.ref);
    }
    _nav = p.nav;
    _takeMark(p);
    // Переход или смена перевода отменяет выбор части стиха (в веб-версии он сбрасывается вместе с выделением)
    final idx = widget.index;
    Future.microtask(() {
      final ps = partSelection.value;
      if (ps != null && ps.pane == idx) partSelection.value = null;
    });
    livePosition(widget.index, p.ref).value = p.ref;
  }

  // Режим «Сплошной» / «Как книга» или показ заголовков поменялись — строки другие, встаём на то же место
  void _ensureRows(bool cont, bool showHeadings) {
    if (_rowsKey == '$cont|$showHeadings') return;
    final at = livePositions[widget.index]?.value ?? ref.read(panesProvider)[widget.index].ref;
    _buildRows(cont, showHeadings);
    _initialIndex = _rowOf[_itemOf(at)];
    _listKey++;
    _alignAfterFrame(at);
  }

  // Стих внутри абзаца: после показа строки узнаём его высоту и ставим стих к верхнему краю
  void _alignAfterFrame(VerseRef at) {
    if (at.verse <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _book == null || !_scroll.isAttached) return;
      final r = _rowOf[_itemOf(at)];
      if (r >= _rows.length || !_rows[r].para) return;
      final top = blockHandle(widget.index, r)?.verseTop(at.verse);
      if (top != null && top > 1) {
        _following = true;
        _scroll.jumpTo(index: r, alignment: -top / _vh);
        _following = false;
      }
    });
  }

  // ---- пометки перехода ----
  void _takeMark(PaneState p) {
    _hlFadeTimer?.cancel();
    _hlEndTimer?.cancel();
    _mkRef = null;
    _mkQuery = null;
    _mkFlash = false;
    _hlFade = false;
    final m = readerMarks.value[widget.index];
    if (m == null || m.stamp == _markStamp) return;
    _markStamp = m.stamp;
    final age = DateTime.now().millisecondsSinceEpoch - m.stamp;
    _mkRef = m.ref;
    _mkFlash = m.flash;
    if (m.highlight != null && m.highlight!.trim().isNotEmpty && age < kHighlightMs) {
      _mkQuery = m.highlight;
      // Слово гаснет за 0,8 с до конца, потом отметка снимается
      _hlFadeTimer = Timer(Duration(milliseconds: math.max(0, kHighlightMs - 800 - age)), () {
        if (mounted) setState(() => _hlFade = true);
      });
      _hlEndTimer = Timer(Duration(milliseconds: math.max(0, kHighlightMs - age)), () {
        if (mounted) setState(() => _mkQuery = null);
      });
    }
  }

  // Касание текста сразу гасит подсветку слова
  void _dropHighlight() {
    if (_mkQuery == null || _hlFade) return;
    setState(() => _hlFade = true);
    _hlEndTimer?.cancel();
    _hlEndTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _mkQuery = null);
    });
  }

  VerseMark? _markFor(int row) {
    final r = _mkRef;
    if (r == null || (!_mkFlash && _mkQuery == null)) return null;
    var i = _book!.indexOf(r.chapter, r.verse);
    while (i < _book!.items.length && _book!.items[i].kind != ItemKind.verse) {
      i++;
    }
    if (i >= _book!.items.length || _book!.items[i].chapter != r.chapter) return null;
    if (_rowOf[i] != row) return null;
    return VerseMark(ref: r, query: _mkQuery, fade: _hlFade, flash: _mkFlash, stamp: _markStamp);
  }

  // ---- место чтения ----
  // Верхний видимый элемент → место панели (шапка, запоминание) и сигнал второй панели
  void _onPositions() {
    final book = _book;
    if (book == null || _rows.isEmpty) return;
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty) return;
    for (final p in pos) {
      if (p.index < _rows.length) _rowFrac[p.index] = p.itemTrailingEdge - p.itemLeadingEdge;
    }
    ItemPosition? top;
    for (final p in pos) {
      if (p.itemTrailingEdge > 0.0 && (top == null || p.index < top.index)) top = p;
    }
    if (top == null) return;
    final r = math.min(top.index, _rows.length - 1);
    final row = _rows[r];
    final h = top.itemTrailingEdge - top.itemLeadingEdge;
    var frac = h > 0 ? (-top.itemLeadingEdge / h).clamp(0.0, 1.0) : 0.0;
    final VerseRef at, emitAt;
    if (row.para) {
      // Внутри абзаца: стих у верхнего края и доля его высоты
      final y = math.max(0.0, -top.itemLeadingEdge * _vh);
      final handle = blockHandle(widget.index, r);
      final verse = handle?.verseAtY(y) ?? _verseByChars(row, frac).verse;
      final item = row.verses.firstWhere((x) => x.verse == verse, orElse: () => row.verses.first);
      at = emitAt = VerseRef(book.book, item.chapter, item.verse);
      final vt = handle?.verseTop(verse), vb = handle?.verseBottom(verse);
      frac = vt != null && vb != null && vb > vt ? ((y - vt) / (vb - vt)).clamp(0.0, 1.0) : 0.0;
    } else {
      at = book.refAt(row.start);
      final it = book.items[row.start];
      emitAt = VerseRef(book.book, it.chapter, it.verse);
    }
    _remember(at);
    if (_following || SyncHub.driver != widget.index) return;
    if (!ref_.syncOn) return;
    SyncHub.emit(widget.index, emitAt, frac);
  }

  void _remember(VerseRef at) {
    livePosition(widget.index, at).value = at;
    ref_.remember(widget.index, at);
  }

  // Стих абзаца по доле его высоты (по числу знаков), пока блок ещё не построен
  ReaderItem _verseByChars(_Row row, double frac) {
    final total = row.verses.fold<int>(0, (a, x) => a + x.text.length);
    var acc = 0.0;
    for (final x in row.verses) {
      acc += x.text.length;
      if (acc / math.max(1, total) >= frac) return x;
    }
    return row.verses.last;
  }

  _RefHelper get ref_ => _RefHelper(ref);

  // Ведомая панель: тот же стих (или заголовок главы), та же доля его высоты
  void _follow(VerseRef at, double frac) {
    final book = _book;
    if (book == null || !_scroll.isAttached) return;
    if (book.book != at.book) {
      ref.read(panesProvider.notifier).navigate(widget.index, at, flash: false);
      return;
    }
    final i = at.verse == 0 ? book.indexOf(at.chapter, 1) : book.indexOf(at.chapter, at.verse);
    final r = _rowOf[i];
    final row = _rows[r];
    double alignment;
    if (!row.para) {
      final h = _rowFrac[r] ?? 0.05;
      alignment = -frac * h;
    } else {
      final handle = blockHandle(widget.index, r);
      final vt = handle?.verseTop(at.verse), vb = handle?.verseBottom(at.verse);
      if (vt != null && vb != null) {
        alignment = -(vt + frac * (vb - vt)) / _vh;
      } else {
        // Блок не построен: примерно, по числу знаков абзаца
        final total = row.verses.fold<int>(0, (a, x) => a + x.text.length);
        var before = 0;
        var len = 1;
        for (final x in row.verses) {
          if (x.verse == at.verse) {
            len = x.text.length;
            break;
          }
          before += x.text.length;
        }
        alignment = -((before + frac * len) / math.max(1, total)) * (_rowFrac[r] ?? 0);
      }
    }
    _following = true;
    _scroll.jumpTo(index: r, alignment: alignment);
    _following = false;
  }

  // ---- жесты ----
  bool get _animations => ref.read(settingsProvider).get<bool>('animations');

  bool _busy() {
    if (ModalRoute.of(context)?.isCurrent == false) return true; // открыто окно
    if (ref.read(selectionProvider)[widget.index]?.isNotEmpty ?? false) return true;
    return partSelection.value != null;
  }

  void _down(PointerDownEvent e) {
    SyncHub.driver = widget.index;
    _dropHighlight();
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _resetDrag(false);
      _sw = null;
      _pinchStart();
    } else if (_pointers.length == 1) {
      final w = MediaQuery.sizeOf(context).width;
      final edge = e.position.dx < 24 || e.position.dx > w - 24; // у края — системные жесты телефона
      _sw = _busy() || edge ? null : (x: e.position.dx, y: e.position.dy, t: DateTime.now().millisecondsSinceEpoch, dir: 0);
      _back.stop();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pinching) {
      _pinchMove();
      return;
    }
    final s = _sw;
    if (s == null) return;
    if (_pointers.length > 1) {
      _resetDrag(false);
      _sw = null;
      return;
    }
    final dx = e.position.dx - s.x, dy = e.position.dy - s.y;
    var dir = s.dir;
    if (dir == 0) {
      if (dx.abs() < 12 && dy.abs() < 12) return;
      dir = dx.abs() > dy.abs() * 1.6 ? 1 : -1; // -1 — прокрутка, не трогаем
      _sw = (x: s.x, y: s.y, t: s.t, dir: dir);
    }
    if (dir != 1) return;
    final can = _target(dx < 0 ? 1 : -1) != null;
    final shift = dx * (can ? 0.35 : 0.12);
    _drag.value = (shift, 1 - math.min(0.35, dx.abs() / 900));
  }

  void _up(PointerEvent e) {
    final cancelled = e is PointerCancelEvent;
    final wasPinch = _pinching;
    _pointers.remove(e.pointer);
    if (wasPinch) {
      if (_pointers.length < 2) _pinchEnd();
      _sw = null;
      return;
    }
    final s = _sw;
    if (s == null || _pointers.isNotEmpty) return;
    _sw = null;
    if (s.dir != 1 || cancelled) {
      _resetDrag(true);
      return;
    }
    final dx = e.position.dx - s.x;
    final fast = DateTime.now().millisecondsSinceEpoch - s.t < 600;
    final dir = dx < 0 ? 1 : -1;
    if (_target(dir) != null && (dx.abs() > 110 || (fast && dx.abs() > 60))) {
      _resetDrag(false);
      _chapter(dir);
    } else {
      _resetDrag(true);
    }
  }

  void _resetDrag(bool animate) {
    if (_drag.value.$1 == 0) return;
    if (animate && _animations) {
      _backFrom = _drag.value.$1;
      _back.forward(from: 0);
    } else {
      _drag.value = (0, 1);
    }
  }

  // Соседняя глава в сторону dir (через границу книги — первая или последняя глава соседней); null — дальше некуда
  VerseRef? _target(int dir) {
    final book = _book;
    if (book == null) return null;
    final at = livePositions[widget.index]?.value ?? ref.read(panesProvider)[widget.index].ref;
    final c = at.chapter + dir;
    if (c >= 1 && c <= book.chapterCount) return VerseRef(book.book, c, 1);
    final books = bookList(book.module);
    final bi = books.indexWhere((b) => b['id'] == book.book);
    final nb = bi + dir;
    if (bi < 0 || nb < 0 || nb >= books.length) return null;
    return VerseRef(books[nb]['id'] as String, dir > 0 ? 1 : (books[nb]['chapters'] as int? ?? 1), 1);
  }

  // Щипок: размер шрифта сразу на экране, в настройки — когда пальцы подняты
  void _pinchStart() {
    final pts = _pointers.values.take(2).toList();
    _pinchD0 = math.max(1, (pts[0] - pts[1]).distance);
    _pinchFs0 = (_pinchFs ?? ref.read(settingsProvider).d('fontSize')).toDouble();
    _pinching = true;
    _pinchFs = _pinchFs0.round();
    _showBadge('${_pinchFs!} px');
    setState(() {});
  }

  void _pinchMove() {
    if (_pointers.length < 2) return;
    final pts = _pointers.values.take(2).toList();
    final fs = (_pinchFs0 * (pts[0] - pts[1]).distance / _pinchD0).clamp(_fontMin.toDouble(), _fontMax.toDouble()).round();
    if (fs == _pinchFs) return;
    _pinchFs = fs;
    _showBadge('$fs px');
    setState(() {});
  }

  void _pinchEnd() {
    final fs = _pinchFs;
    _pinching = false;
    if (fs != null && fs != ref.read(settingsProvider).d('fontSize').round()) ref.read(settingsProvider.notifier).set({'fontSize': fs.toDouble()});
    _pinchFs = null;
    _badge.value = null;
    _badgeTimer?.cancel();
    setState(() {});
  }

  void _showBadge(String text) {
    _badge.value = text;
    _badgeTimer?.cancel();
    _badgeTimer = Timer(const Duration(milliseconds: 1800), () => _badge.value = null); // конец жеста мог потеряться
  }

  // Режим чтения: прокрутка вниз прячет панели, вверх — возвращает (по первой панели чтения)
  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification || n.metrics.axis != Axis.vertical || widget.index != 0) return false;
    if (!ref.read(settingsProvider).get<bool>('focusMode') || _pinching) return false;
    final d = n.scrollDelta ?? 0;
    if (d == 0) return false;
    _dirAcc = (_dirAcc > 0) == (d > 0) ? _dirAcc + d : d;
    if (_dirAcc.abs() > 24) {
      final down = _dirAcc > 0;
      _dirAcc = 0;
      // Положение элементов обновится в этом кадре — решаем после него: у самого верха панели не прячем
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final vis = _positions.itemPositions.value.where((x) => x.itemTrailingEdge > 0).toList()..sort((x, y) => x.index.compareTo(y.index));
        final atTop = vis.isEmpty || (vis.first.index == 0 && vis.first.itemLeadingEdge > -80 / _vh);
        final hide = down && !atTop;
        if (focusHidden.value != hide) focusHidden.value = hide;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Следим только за переходами и сменой перевода: запоминание места при прокрутке панель не перерисовывает
    final sel = ref.watch(panesProvider.select((l) => widget.index < l.length ? (l[widget.index].moduleId, l[widget.index].nav) : null));
    var s = ref.watch(settingsProvider);
    if (sel == null) return const SizedBox.shrink();
    final cont = isContinuous(s);
    final showH = s.get<bool>('showHeadings');
    final p = ref.read(panesProvider)[widget.index];
    if (p.nav != _nav || p.moduleId != _module) _open(p, cont, showH);
    _ensureRows(cont, showH);
    // Выбрано что-то или режим чтения выключен — панели на месте
    ref.listen(selectionProvider, (a, b) {
      if (widget.index == 0 && (b[0]?.isNotEmpty ?? false) && focusHidden.value) focusHidden.value = false;
      // Выбрали другой стих — выбор части прежнего стиха отменяется (как в веб-версии)
      final ps = partSelection.value;
      if (ps != null && ps.pane == widget.index && (b[widget.index]?.isNotEmpty ?? false)) partSelection.value = null;
    });
    if (widget.index == 0 && !s.get<bool>('focusMode') && focusHidden.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusHidden.value) focusHidden.value = false;
      });
    }
    if (_pinchFs != null) s = s.copyWith({'fontSize': _pinchFs!.toDouble()});
    final book = _book!;
    final pal = s.palette;
    final books = bookList(book.module);
    final bi = books.indexWhere((b) => b['id'] == book.book);
    final prevBook = bi > 0 ? books[bi - 1]['id'] as String : null;
    final nextBook = bi >= 0 && bi < books.length - 1 ? books[bi + 1]['id'] as String : null;
    final mod = ModuleStore.instance.get(book.module);
    final rtl = mod?.language == 'he';

    final list = ScrollablePositionedList.builder(
      key: ValueKey('${book.module}|${book.book}|$_listKey'),
      itemCount: _rows.length + 1,
      initialScrollIndex: _initialIndex,
      initialAlignment: 0.0,
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      physics: _pinching ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      itemBuilder: (context, i) {
        if (i == _rows.length) {
          // Конец книги: переход к следующей и запас снизу, чтобы последний стих вставал к верхнему краю
          return Padding(
            padding: EdgeInsets.only(top: 16, bottom: MediaQuery.sizeOf(context).height * 0.45),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: nextBook == null
                  ? Text(t('Конец книги'), style: TextStyle(color: pal.muted))
                  : _BookJump(label: t('Следующая книга: {name}', {'name': Books.instance.meta(nextBook).name}), trailing: true, pal: pal, onTap: () => _goBook(nextBook, 1)),
            ),
          );
        }
        final r = _rows[i];
        // Ширина строки — не больше textWidth em (на планшете и компьютере текст не растягивается во всю ширину)
        final row = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: s.d('textWidth') * s.d('fontSize')),
            child: SizedBox(
              width: double.infinity,
              child: VerseView(item: book.items[r.start], para: r.para ? r.verses : null, row: i, mark: _markFor(i), book: book.book, settings: s, pane: widget.index, moduleId: book.module),
            ),
          ),
        );
        if (i == 0 && prevBook != null) {
          final lastChapter = (books[bi - 1]['chapters'] as int?) ?? 1;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 12), child: _BookJump(label: Books.instance.meta(prevBook).name, pal: pal, onTap: () => _goBook(prevBook, lastChapter))),
            row,
          ]);
        }
        return row;
      },
    );

    return LayoutBuilder(builder: (context, cons) {
      _vh = cons.maxHeight.isFinite && cons.maxHeight > 0 ? cons.maxHeight : _vh;
      return Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) SyncHub.driver = widget.index;
        },
        child: Stack(children: [
          ColoredBox(
            color: pal.bg,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : Directionality.of(context),
                child: ValueListenableBuilder<(double, double)>(
                  valueListenable: _drag,
                  child: list,
                  // Всегда в одной обёртке: иначе список пересоздавался бы и терял место при каждом свайпе
                  builder: (context, d, child) => Opacity(opacity: d.$2, child: Transform.translate(offset: Offset(d.$1, 0), child: child)),
                ),
              ),
            ),
          ),
          // Полоса прогресса чтения книги — тонкая полоска вверху панели
          Positioned(left: 0, right: 0, top: 0, child: _Progress(pal: pal, pane: widget.index, initial: p.ref, name: Books.instance.meta(book.book).name, pct: _bookPct)),
          // Соседняя глава — круглые стрелки внизу (по центру — «Слушать», если есть аудио)
          Positioned(left: 14, bottom: 16, child: RoundFab(icon: LucideIcons.chevronLeft, tooltip: t('Предыдущая глава'), onTap: () => _chapter(-1))),
          Positioned(right: 14, bottom: 16, child: RoundFab(icon: LucideIcons.chevronRight, tooltip: t('Следующая глава'), onTap: () => _chapter(1))),
          if (Hub.listenFab != null)
            Positioned(left: 0, right: 0, bottom: 16, child: Center(child: Hub.listenFab!(context, ref, widget.index)))
          else if (Hub.listenFrom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: RoundFab(
                  icon: LucideIcons.headphones,
                  tooltip: t('Слушать'),
                  onTap: () => Hub.listenFrom!(context, ref, widget.index, livePositions[widget.index]?.value ?? p.ref),
                ),
              ),
            ),
          // Плашка с размером шрифта во время щипка (.pinch-badge)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<String?>(
                valueListenable: _badge,
                builder: (context, text, _) => Align(
                  alignment: const Alignment(0, -0.16),
                  child: AnimatedOpacity(
                    opacity: text == null ? 0 : 1,
                    duration: Duration(milliseconds: _animations ? 400 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(color: pal.bar.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(14)),
                      child: Text(text ?? '', style: TextStyle(fontSize: 18.4, fontWeight: FontWeight.w700, color: pal.barText)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }

  // Доля стихов книги до места — полоса прогресса (ReadingProgress в BibleReader.jsx)
  double _bookPct(VerseRef at) {
    final b = _book;
    if (b == null || _verseOrd.isEmpty) return 0;
    final total = _verseOrd.last;
    if (total <= 0) return 0;
    return (_verseOrd[b.indexOf(at.chapter, at.verse).clamp(0, _verseOrd.length - 1)] / total).clamp(0.0, 1.0);
  }

  void _chapter(int dir) {
    final to = _target(dir);
    if (to == null) return;
    ref.read(panesProvider.notifier).navigate(widget.index, to, flash: false);
  }

  void _goBook(String id, int chapter) => ref.read(panesProvider.notifier).navigate(widget.index, VerseRef(id, chapter, 1), flash: false);
}

class _Progress extends StatelessWidget {
  const _Progress({required this.pal, required this.pane, required this.initial, required this.name, required this.pct});
  final Palette pal;
  final int pane;
  final VerseRef initial;
  final String name;
  final double Function(VerseRef) pct;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VerseRef>(
        valueListenable: livePosition(pane, initial),
        builder: (context, at, _) {
          final f = pct(at);
          final label = t('Прочитано книги «{book}»: {pct}%', {'book': name, 'pct': '${(f * 100).round()}'});
          return Semantics(
            label: label,
            value: '${(f * 100).round()}',
            child: SizedBox(
              height: 3,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: mix(pal.accent, 0.16, pal.bg))),
                Positioned.fill(
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 300),
                    alignment: Alignment.centerLeft,
                    widthFactor: f,
                    child: DecoratedBox(decoration: BoxDecoration(color: pal.accent, borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)))),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

class _BookJump extends StatelessWidget {
  const _BookJump({required this.label, required this.pal, required this.onTap, this.trailing = false});
  final String label;
  final Palette pal;
  final VoidCallback onTap;
  final bool trailing;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(trailing ? LucideIcons.chevronRight : LucideIcons.chevronLeft, size: 18),
        iconAlignment: trailing ? IconAlignment.end : IconAlignment.start,
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: pal.text, backgroundColor: pal.panel, side: BorderSide(color: pal.line), shape: const StadiumBorder()),
      );
}

class _RefHelper {
  _RefHelper(this.r);
  final WidgetRef r;
  void remember(int i, VerseRef at) => r.read(panesProvider.notifier).remember(i, at);
  bool get syncOn => r.read(settingsProvider).get<bool>('syncScroll') && r.read(panesProvider).length > 1;
}
