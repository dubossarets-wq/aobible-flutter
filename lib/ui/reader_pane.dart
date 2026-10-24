// Панель чтения: вся книга одним ленивым списком (рисуются только видимые стихи).
// Переход к стиху — jumpTo по индексу; текущее место — по видимым элементам; синхронная прокрутка —
// вторая панель встаёт на тот же стих с той же долей прочитанного, в том же кадре.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/panes.dart';
import '../core/i18n.dart';
import '../core/settings.dart';
import '../features/hub.dart';
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
      if (p.index >= book.items.length) continue;
      final it = book.items[p.index];
      chapters.add(it.chapter);
      final next = p.index + 1 < book.items.length ? book.items[p.index + 1] : null;
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
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
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
    final books = bookList(book.module);
    final bi = books.indexWhere((b) => b['id'] == book.book);
    final prevBook = bi > 0 ? books[bi - 1]['id'] as String : null;
    final nextBook = bi >= 0 && bi < books.length - 1 ? books[bi + 1]['id'] as String : null;
    return Listener(
      onPointerDown: (_) => SyncHub.driver = widget.index,
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) SyncHub.driver = widget.index;
      },
      child: GestureDetector(
        // Свайп влево/вправо — следующая/предыдущая глава (как в веб-версии)
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 450) _chapter(v < 0 ? 1 : -1);
        },
        child: Stack(children: [
          ColoredBox(
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
            if (i == book.items.length) {
              // Конец книги: переход к следующей и запас снизу, чтобы последний стих вставал к верхнему краю
              return Padding(
                padding: EdgeInsets.only(top: 16, bottom: MediaQuery.sizeOf(context).height * 0.45),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: nextBook == null
                      ? Text(t('Конец книги'), style: TextStyle(color: pal.muted))
                      : _BookJump(label: t('Следующая книга: {name}', {'name': Books.instance.meta(nextBook).name}), trailing: true, pal: pal, onTap: () => _goBook(nextBook, 1)),
                ),
              );
            }
            final item = book.items[i];
            // Ширина строки — не больше textWidth em (на планшете и компьютере текст не растягивается во всю ширину)
            final row = Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: s.d('textWidth') * s.d('fontSize')),
                child: SizedBox(width: double.infinity, child: VerseView(item: item, book: book.book, settings: s, pane: widget.index, moduleId: book.module)),
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
        ),
      ),
          // Соседняя глава — круглые стрелки внизу (по центру — «Слушать», если есть аудио)
          Positioned(left: 14, bottom: 16, child: _RoundButton(icon: Icons.chevron_left, pal: pal, onTap: () => _chapter(-1))),
          Positioned(right: 14, bottom: 16, child: _RoundButton(icon: Icons.chevron_right, pal: pal, onTap: () => _chapter(1))),
          if (Hub.listenFab != null)
            Positioned(left: 0, right: 0, bottom: 16, child: Center(child: Hub.listenFab!(context, ref, widget.index)))
          else if (Hub.listenFrom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: _RoundButton(
                  icon: Icons.headphones_outlined,
                  pal: pal,
                  onTap: () => Hub.listenFrom!(context, ref, widget.index, livePositions[widget.index]?.value ?? p.ref),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  void _chapter(int dir) {
    final book = _book;
    if (book == null) return;
    final at = livePositions[widget.index]?.value ?? ref.read(panesProvider)[widget.index].ref;
    final c = at.chapter + dir;
    if (c >= 1 && c <= book.chapterCount) {
      ref.read(panesProvider.notifier).navigate(widget.index, VerseRef(book.book, c, 1));
      return;
    }
    // За краем книги — соседняя книга
    final books = bookList(book.module);
    final bi = books.indexWhere((b) => b['id'] == book.book);
    final nb = bi + dir;
    if (nb < 0 || nb >= books.length) return;
    _goBook(books[nb]['id'] as String, dir > 0 ? 1 : (books[nb]['chapters'] as int? ?? 1));
  }

  void _goBook(String id, int chapter) => ref.read(panesProvider.notifier).navigate(widget.index, VerseRef(id, chapter, 1));
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
        icon: Icon(trailing ? Icons.chevron_right : Icons.chevron_left, size: 18),
        iconAlignment: trailing ? IconAlignment.end : IconAlignment.start,
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: pal.text, backgroundColor: pal.panel, side: BorderSide(color: pal.line), shape: const StadiumBorder()),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.pal, required this.onTap});
  final IconData icon;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: pal.panel.withValues(alpha: 0.92),
        shape: CircleBorder(side: BorderSide(color: pal.line)),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: pal.accent))),
      );
}

class _RefHelper {
  _RefHelper(this.r);
  final WidgetRef r;
  void remember(int i, VerseRef at) => r.read(panesProvider.notifier).remember(i, at);
  bool get syncOn => r.read(settingsProvider).get<bool>('syncScroll') && r.read(panesProvider).length > 1;
}
