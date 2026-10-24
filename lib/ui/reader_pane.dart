// Панель чтения: вся книга одним ленивым списком (рисуются только видимые стихи).
// Переход к стиху — jumpTo по индексу; текущее место — по видимым элементам; синхронная прокрутка —
// вторая панель встаёт на тот же стих с той же долей прочитанного, в том же кадре.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import 'verse_view.dart';

class ReaderPane extends ConsumerStatefulWidget {
  const ReaderPane({super.key, required this.index});
  final int index;

  @override
  ConsumerState<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends ConsumerState<ReaderPane> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  BookText? _book;
  int _nav = -1;
  String? _module;
  int _initialIndex = 0;
  int _listKey = 0;
  bool _following = false; // прокрутку сейчас ставит синхронизация (не человек)

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    SyncHub.listeners[widget.index] = _follow;
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    if (SyncHub.listeners[widget.index] == _follow) SyncHub.listeners.remove(widget.index);
    super.dispose();
  }

  void _open(PaneState p) {
    final sameBook = _book != null && _book!.book == p.ref.book && _module == p.moduleId;
    if (!sameBook) {
      _book = loadBook(p.moduleId, p.ref.book);
      _module = p.moduleId;
      _initialIndex = _book!.indexOf(p.ref.chapter, p.ref.verse);
      _listKey++; // новая книга — новый список, сразу на нужном месте (без прокрутки после показа)
    } else if (_scroll.isAttached) {
      _scroll.jumpTo(index: _book!.indexOf(p.ref.chapter, p.ref.verse));
    }
    _nav = p.nav;
    livePosition(widget.index, p.ref).value = p.ref;
  }

  // Верхний видимый элемент → место панели (шапка, запоминание) и сигнал второй панели
  void _onPositions() {
    final book = _book;
    if (book == null) return;
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty) return;
    ItemPosition? top;
    for (final p in pos) {
      if (p.itemTrailingEdge > 0.0 && (top == null || p.index < top.index)) top = p;
    }
    if (top == null) return;
    final ref = book.refAt(top.index);
    livePosition(widget.index, ref).value = ref;
    ref_.remember(widget.index, ref);
    if (_following || SyncHub.driver != widget.index) return;
    if (!ref_.syncOn) return;
    final h = top.itemTrailingEdge - top.itemLeadingEdge;
    final frac = h > 0 ? (-top.itemLeadingEdge / h).clamp(0.0, 1.0) : 0.0;
    final it = book.items[top.index];
    SyncHub.emit(widget.index, VerseRef(book.book, it.chapter, it.verse), frac);
  }

  _RefHelper get ref_ => _RefHelper(ref);

  // Ведомая панель: тот же стих (или заголовок главы), та же доля его высоты
  void _follow(VerseRef at, double frac) {
    final book = _book;
    if (book == null || !_scroll.isAttached) return;
    if (book.book != at.book) {
      ref.read(panesProvider.notifier).navigate(widget.index, at);
      return;
    }
    final i = at.verse == 0 ? book.indexOf(at.chapter, 1) : book.indexOf(at.chapter, at.verse);
    double h = 0.05;
    for (final p in _positions.itemPositions.value) {
      if (p.index == i) h = p.itemTrailingEdge - p.itemLeadingEdge;
    }
    _following = true;
    _scroll.jumpTo(index: i, alignment: -frac * h);
    _following = false;
  }

  @override
  Widget build(BuildContext context) {
    // Следим только за переходами и сменой перевода: запоминание места при прокрутке панель не перерисовывает
    final sel = ref.watch(panesProvider.select((l) => widget.index < l.length ? (l[widget.index].moduleId, l[widget.index].nav) : null));
    final s = ref.watch(settingsProvider);
    if (sel == null) return const SizedBox.shrink();
    final p = ref.read(panesProvider)[widget.index];
    if (p.nav != _nav || p.moduleId != _module) _open(p);
    final book = _book!;
    final pal = s.palette;
    return Listener(
      onPointerDown: (_) => SyncHub.driver = widget.index,
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) SyncHub.driver = widget.index;
      },
      child: ColoredBox(
        color: pal.bg,
        child: ScrollablePositionedList.builder(
          key: ValueKey('${book.module}|${book.book}|$_listKey'),
          itemCount: book.items.length + 1,
          initialScrollIndex: _initialIndex,
          initialAlignment: 0.0,
          itemScrollController: _scroll,
          itemPositionsListener: _positions,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          itemBuilder: (context, i) {
            if (i == book.items.length) return SizedBox(height: MediaQuery.sizeOf(context).height * 0.45);
            return VerseView(item: book.items[i], book: book.book, settings: s);
          },
        ),
      ),
    );
  }
}

class _RefHelper {
  _RefHelper(this.r);
  final WidgetRef r;
  void remember(int i, VerseRef at) => r.read(panesProvider.notifier).remember(i, at);
  bool get syncOn => r.read(settingsProvider).get<bool>('syncScroll') && r.read(panesProvider).length > 1;
}
