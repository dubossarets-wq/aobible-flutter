// Режим «Страницы» (readingStyle = 'pages'): глава разбита на страницы по высоте экрана и листается вбок, как книга.
// Глава строится целиком (Column строк читалки), страница — окно в неё: сдвиг вверх на начало страницы и обрезка по
// концу. Границы страниц — по низу строк текста (RenderParagraph) и строк читалки, чтобы строка не резалась пополам;
// строка, которая не помещается целиком, уходит на следующую. За последней страницей (или перед первой) потянули
// дальше — соседняя глава (onEdge). Изменилась высота главы (выделили стих, сменился шрифт) — страницы пересчитываются,
// чтение остаётся на том же стихе.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

class PagedChapter extends StatefulWidget {
  const PagedChapter({
    super.key,
    required this.column,
    required this.margin,
    required this.bottom,
    required this.startVerse,
    required this.verseTops,
    required this.onPage,
    required this.onEdge,
    required this.counterColor,
    this.locked = false,
  });

  /// Вся глава: Column, по строке читалки в ребёнке (строится для каждой страницы заново)
  final Widget Function() column;
  final double margin;

  /// Сколько оставить снизу (кнопки глав и меню)
  final double bottom;

  /// С какого стиха открыть; 9999 — последняя страница (пришли назад из следующей главы)
  final int startVerse;

  /// Верх каждого стиха в главе по верхам строк читалки
  final List<(double, int)> Function(List<double> rowTops) verseTops;
  final void Function(int verse, int page, int total) onPage;
  final void Function(int dir) onEdge;
  final Color counterColor;

  /// Идёт щипок (размер шрифта) — не листать
  final bool locked;

  @override
  State<PagedChapter> createState() => _PagedChapterState();
}

class _PagedChapterState extends State<PagedChapter> {
  List<double>? _tops; // начало каждой страницы в главе
  List<(double, int)> _verses = const [];
  double _total = 0;
  String _measuredFor = '';
  String _want = '';
  bool _measureQueued = false;
  PageController? _ctl;
  int _page = 0;
  int _topVerse = 0;
  double _pageH = 0;
  double _over = 0;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  // Глава разложилась (в любой из страниц — раскладка у всех одна): нужно ли пересчитать страницы
  void _laid(RenderBox root) {
    if (_measureQueued) return;
    if (_measuredFor == _want && (root.size.height - _total).abs() < 0.5) return;
    _measureQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure(root);
    });
  }

  void _measure(RenderBox root) {
    if (!root.attached || !root.hasSize || _pageH <= 40) return;
    final total = root.size.height;
    final cands = <double>{};
    final rowTops = <double>[];
    final flex = root is RenderProxyBox ? root.child : null;
    if (flex is RenderFlex) {
      var c = flex.firstChild;
      while (c != null) {
        final pd = c.parentData as FlexParentData;
        rowTops.add(pd.offset.dy);
        cands
          ..add(pd.offset.dy)
          ..add(pd.offset.dy + c.size.height);
        c = pd.nextSibling;
      }
    }
    // строки текста: низ каждой — возможная граница; граница внутри строки (номер стиха, значок) не годится
    final lines = <(double, double)>[];
    void visit(RenderObject o) {
      if (o is RenderParagraph && o.hasSize && o.attached) {
        final len = o.text.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).length;
        if (len > 0) {
          final m = o.getTransformTo(root);
          for (final b in o.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len))) {
            final top = MatrixUtils.transformPoint(m, Offset(0, b.top)).dy;
            final bottom = MatrixUtils.transformPoint(m, Offset(0, b.bottom)).dy;
            lines.add((top, bottom));
            cands.add(bottom);
          }
        }
      }
      o.visitChildren(visit);
    }

    visit(root);
    final sorted = [
      for (final y in cands)
        if (!lines.any((l) => l.$1 < y - 1 && l.$2 > y + 1)) y,
    ]..sort();
    final tops = <double>[0];
    var t = 0.0;
    while (t + _pageH < total - 1 && tops.length < 400) {
      final limit = t + _pageH;
      double? best;
      for (final y in sorted) {
        if (y > limit) break;
        if (y > t + 1) best = y;
      }
      t = best ?? limit;
      tops.add(t);
    }
    final verses = widget.verseTops(rowTops);
    final first = _tops == null;
    // куда встать: первый раз — на стих из панели, при пересчёте — на тот, что был вверху страницы
    final want = first ? widget.startVerse : _topVerse;
    var page = 0;
    if (want >= 9999) {
      page = tops.length - 1;
    } else if (want > 0) {
      final y = verses.where((v) => v.$2 == want).firstOrNull?.$1;
      if (y != null) {
        for (var k = 0; k < tops.length; k++) {
          if (tops[k] <= y + 1) page = k;
        }
      }
    }
    setState(() {
      _tops = tops;
      _verses = verses;
      _total = total;
      _measuredFor = _want;
      _page = page;
      if (_ctl == null) {
        _ctl = PageController(initialPage: page);
      } else if (_ctl!.hasClients) {
        _ctl!.jumpToPage(page);
      }
    });
    _report(page);
  }

  // Стих вверху страницы: тот, что идёт на её начале
  void _report(int k) {
    final tops = _tops;
    if (tops == null || k >= tops.length) return;
    var verse = _verses.isEmpty ? 1 : _verses.first.$2;
    for (final v in _verses) {
      if (v.$1 <= tops[k] + 2) verse = v.$2;
    }
    _topVerse = verse;
    widget.onPage(verse, k + 1, tops.length);
  }

  Widget _copy(int k, double width) {
    final tops = _tops;
    final top = tops == null ? 0.0 : tops[k];
    final end = tops != null && k + 1 < tops.length ? tops[k + 1] : top + _pageH;
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.margin, 6, widget.margin, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: SizedBox(
            height: end - top,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(offset: Offset(0, -top), child: _Report(onLayout: _laid, child: widget.column())),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _pageH = box.maxHeight - 6 - widget.bottom;
      _want = '${box.maxWidth.round()}x${_pageH.round()}';
      final tops = _tops;
      if (tops == null || _ctl == null) {
        // первая раскладка: глава строится невидимой, по ней считаются страницы
        return Opacity(opacity: 0, child: IgnorePointer(child: _copy(0, box.maxWidth)));
      }
      return Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification) _over = 0;
            if (n is OverscrollNotification && n.dragDetails != null) _over += n.overscroll;
            if (n is ScrollEndNotification) {
              final o = _over;
              _over = 0;
              if (o < -40 && _page == 0) widget.onEdge(-1);
              if (o > 40 && _page == tops.length - 1) widget.onEdge(1);
            }
            return false;
          },
          child: PageView.builder(
            controller: _ctl,
            physics: widget.locked ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
            itemCount: tops.length,
            onPageChanged: (k) {
              _page = k;
              _report(k);
            },
            itemBuilder: (_, k) => _copy(k, box.maxWidth),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottom - 22,
          child: IgnorePointer(child: Text('${_page + 1} / ${tops.length}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: widget.counterColor))),
        ),
      ]);
    });
  }
}

/// Сообщает о каждой раскладке главы (во время раскладки — ничего не меняет, только запоминает)
class _Report extends SingleChildRenderObjectWidget {
  const _Report({required this.onLayout, super.child});
  final void Function(RenderBox) onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReport(onLayout);
  @override
  void updateRenderObject(BuildContext context, _RenderReport r) => r.onLayout = onLayout;
}

class _RenderReport extends RenderProxyBox {
  _RenderReport(this.onLayout);
  void Function(RenderBox) onLayout;
  @override
  void performLayout() {
    super.performLayout();
    onLayout(this);
  }
}
