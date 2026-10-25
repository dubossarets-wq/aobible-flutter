// Строка ленты: заголовок главы, заголовок раздела, стих или абзац стихов (режимы «Сплошной» и «Как книга»).
// Размеры — как в веб-версии: 19 px, интервал 1.45, номер стиха 0,6 em над строкой, заголовок главы 2,1 em, раздела 0,8 em.
// Стих: нажатие на слово → Hub.onWordTap (словарь; ждёт паузу двойного касания, как в tapState.js), двойное касание →
// Hub.onVerseDoubleTap, номер Стронга → Hub.openStrong, долгое нажатие или нажатие на номер — выделение,
// отметки (закладки, цвета, заметки, пометки толкований…) — от функций через Hub.verseDecorators.
// Подложки (слово под выборкой, найденное слово, мигание стиха, любимые части, выбор части стиха) рисуются
// под текстом по границам строк — одной цельной плашкой, как partShape.js.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/markup.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import '../features/shell/colors.dart' show headingColor, strongColor;
import '../features/shell/fonts.dart' show readerTextStyle, textAlignOf;
import 'kit.dart';

/// Пауза двойного касания (DOUBLE_TAP_MS в tapState.js)
const kDoubleTapMs = 350;

/// Мигание стиха после перехода (@keyframes flash: 2,4 с)
const kFlashMs = 2400;

/// Цвет сердечка (--love)
const _love = Color(0xffd9475e);

/// Режимы «Сплошной» и «Как книга»: стихи идут абзацем
bool isContinuous(Settings s) => s.get<bool>('continuousVerses') || s.get<bool>('bookMode');

/// Отметка последнего перехода для стиха: мигание и подсветка найденного слова
class VerseMark {
  const VerseMark({required this.ref, this.query, this.fade = false, this.flash = false, this.stamp = 0});
  final VerseRef ref;
  final String? query; // слово из поиска (null — только мигание)
  final bool fade; // подсветка гаснет
  final bool flash;
  final int stamp;
}

/// Геометрия построенного блока стихов (абзац или стих): отступы в пикселях от верха блока.
/// Нужна, чтобы встать на стих внутри абзаца и вести вторую панель по стихам.
abstract class BlockHandle {
  double? verseTop(int verse);
  double? verseBottom(int verse);
  int? verseAtY(double y);
}

final _handles = <int, Map<int, BlockHandle>>{};

/// Блок строки row панели pane, если он сейчас построен
BlockHandle? blockHandle(int pane, int row) => _handles[pane]?[row];

// Двойное касание: два нажатия на один стих быстрее 350 мс
({String key, int at})? _lastTap;
bool _isDoubleTap(String key) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final hit = _lastTap != null && _lastTap!.key == key && now - _lastTap!.at < kDoubleTapMs;
  _lastTap = hit ? null : (key: key, at: now);
  return hit;
}

// Мигание показываем один раз на переход (блок может пересоздаться при прокрутке)
final _flashed = <int, int>{};

class VerseView extends ConsumerWidget {
  const VerseView({super.key, required this.item, required this.book, required this.settings, required this.pane, required this.moduleId, this.para, this.row = 0, this.mark});
  final ReaderItem item;
  final List<ReaderItem>? para; // абзац стихов (режимы «Сплошной» и «Как книга»)
  final int row; // номер строки списка (для BlockHandle)
  final VerseMark? mark;
  final String book;
  final Settings settings;
  final int pane;
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = settings.palette;
    final fs = settings.d('fontSize');
    final bookMode = settings.get<bool>('bookMode');
    switch (item.kind) {
      case ItemKind.chapter:
        // .book-title: 0,9 em, серый; .chapter-title: 2,1 em, 800, межстрочный 1,1, отступы .55em/.3em
        // «Как книга»: 0,7 от размера, по центру, отступы 1,4 / .6 em
        final cs = fs * settings.d('chapterTitleSize') * (bookMode ? 0.7 : 1);
        final title = Padding(
          padding: bookMode ? EdgeInsets.only(top: cs * 1.4, bottom: cs * 0.6) : EdgeInsets.only(top: cs * 0.55, bottom: cs * 0.3),
          child: SizedBox(
            width: double.infinity,
            child: Text(book == 'Ps' ? t('Псалом {n}', {'n': '${item.chapter}'}) : t('Глава {n}', {'n': '${item.chapter}'}),
                textAlign: bookMode ? TextAlign.center : TextAlign.start,
                style: readerTextStyle(settings, size: cs, weight: 800).copyWith(color: pal.text, height: 1.1, letterSpacing: -cs * 0.01)),
          ),
        );
        if (item.chapter != 1) return title;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: fs * 0.9 * 1.4),
            child: Text(Books.instance.meta(book).name, style: readerTextStyle(settings, size: fs * 0.9, weight: 600).copyWith(color: pal.muted)),
          ),
          title,
        ]);
      case ItemKind.heading:
        if (!settings.get<bool>('showHeadings')) return const SizedBox.shrink();
        // .section-title: 0,8 em, 650, цвет акцента (или свой), отступы 1.1em / .35em («Как книга» — сверху 1,4 em)
        final hs = fs * settings.d('headingSize');
        return Padding(
          padding: EdgeInsets.only(top: hs * (bookMode ? 1.4 : 1.1), bottom: hs * 0.35),
          child: SizedBox(
            width: double.infinity,
            child: Text(item.text, style: readerTextStyle(settings, size: hs, weight: 650).copyWith(color: headingColor(settings), height: 1.3, letterSpacing: hs * 0.01)),
          ),
        );
      case ItemKind.verse:
        return _Block(view: this);
    }
  }
}

// Стих внутри блока: где он в тексте абзаца
class _VR {
  _VR(this.item, this.start);
  final ReaderItem item;
  final int start;
  int end = 0;
  int numberStart = 0;
  int numberEnd = 0; // номер стиха и значки до текста
  final List<(int, int)> words = []; // по номерам слов: начало и конец в тексте абзаца
  final List<int> wordToken = [];
  final List<(int, int, String)> strongs = []; // номера Стронга: начало, конец, номер
  VerseRef ref(String book) => VerseRef(book, item.chapter, item.verse);
}

// Часть блока: стихи подряд до строки действий под стихом (строка действий разрывает абзац, как в вебе)
class _Seg {
  _Seg(this.key);
  final GlobalKey key;
  final List<_VR> vrs = [];
  TextSpan span = const TextSpan();
  List<Widget> after = const [];
  final List<_Plate> plates = [];
  Color? bg; // только для одного стиха: фон и выделение рамкой
  bool selected = false;
}

class _Block extends ConsumerStatefulWidget {
  const _Block({required this.view});
  final VerseView view;
  @override
  ConsumerState<_Block> createState() => _BlockState();
}

class _BlockState extends ConsumerState<_Block> with SingleTickerProviderStateMixin implements BlockHandle {
  final _keys = <GlobalKey>[];
  final _blockKey = GlobalKey();
  List<_Seg> _segs = [];
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: kFlashMs));
  int? _flashVerse;
  Timer? _wordTimer;

  VerseView get v => widget.view;
  List<ReaderItem> get _verses => v.para ?? [v.item];

  @override
  void initState() {
    super.initState();
    _register();
    _flash.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) setState(() => _flashVerse = null); // плашка мигания снимается
    });
    _maybeFlash();
  }

  @override
  void didUpdateWidget(_Block old) {
    super.didUpdateWidget(old);
    if (old.view.pane != v.pane || old.view.row != v.row) {
      _unregister(old.view.pane, old.view.row);
      _register();
    }
    _maybeFlash();
  }

  void _register() => (_handles[v.pane] ??= {})[v.row] = this;
  void _unregister(int pane, int row) {
    if (_handles[pane]?[row] == this) _handles[pane]!.remove(row);
  }

  @override
  void dispose() {
    _unregister(v.pane, v.row);
    _wordTimer?.cancel();
    _flash.dispose();
    super.dispose();
  }

  void _maybeFlash() {
    final m = v.mark;
    if (m == null || !m.flash || !v.settings.get<bool>('animations')) return;
    if (_flashed[v.pane] == m.stamp) return;
    if (DateTime.now().millisecondsSinceEpoch - m.stamp > kFlashMs) return;
    if (!_verses.any((it) => it.chapter == m.ref.chapter && it.verse == m.ref.verse)) return;
    _flashed[v.pane] = m.stamp;
    _flashVerse = m.ref.verse;
    _flash.forward(from: 0);
  }

  GlobalKey _key(int i) {
    while (_keys.length <= i) {
      _keys.add(GlobalKey());
    }
    return _keys[i];
  }

  // ---- геометрия (BlockHandle) ----
  RenderParagraph? _para(_Seg s) {
    final ro = s.key.currentContext?.findRenderObject();
    return ro is RenderParagraph && ro.hasSize ? ro : null;
  }

  double _segTop(_Seg s) {
    final block = _blockKey.currentContext?.findRenderObject();
    final ro = s.key.currentContext?.findRenderObject();
    if (block is! RenderBox || ro is! RenderBox) return 0;
    return ro.localToGlobal(Offset.zero, ancestor: block).dy;
  }

  (_Seg, _VR)? _find(int verse) {
    for (final s in _segs) {
      for (final r in s.vrs) {
        if (r.item.verse == verse) return (s, r);
      }
    }
    return null;
  }

  @override
  double? verseTop(int verse) {
    try {
      final f = _find(verse);
      final rp = f == null ? null : _para(f.$1);
      if (f == null || rp == null) return null;
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: f.$2.start, extentOffset: f.$2.start + 1));
      return _segTop(f.$1) + (boxes.isEmpty ? 0 : boxes.first.top);
    } catch (_) {
      return null;
    }
  }

  @override
  double? verseBottom(int verse) {
    try {
      final f = _find(verse);
      final rp = f == null ? null : _para(f.$1);
      if (f == null || rp == null) return null;
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: f.$2.end - 1, extentOffset: f.$2.end));
      return _segTop(f.$1) + (boxes.isEmpty ? rp.size.height : boxes.last.bottom);
    } catch (_) {
      return null;
    }
  }

  @override
  int? verseAtY(double y) {
    try {
      for (final s in _segs) {
        final rp = _para(s);
        if (rp == null) continue;
        final top = _segTop(s);
        if (y >= top + rp.size.height && s != _segs.last) continue;
        final pos = rp.getPositionForOffset(Offset(0, (y - top).clamp(0.0, rp.size.height))).offset;
        for (final r in s.vrs) {
          if (pos >= r.start && pos < r.end) return r.item.verse;
        }
        return s.vrs.last.item.verse;
      }
    } catch (_) {}
    return null;
  }

  // ---- рисование ----
  @override
  Widget build(BuildContext context) {
    ref.watch(decorVersionProvider);
    final verses = _verses;
    // Какие стихи блока выделены («0110»; пусто — ни одного): блок перестраивается только при смене своих стихов
    final selKey = ref.watch(selectionProvider.select((m) {
      final set = m[v.pane];
      if (set == null || set.isEmpty) return '';
      final k = [for (final it in verses) set.contains(VerseRef(v.book, it.chapter, it.verse)) ? '1' : '0'].join();
      return k.contains('1') ? k : '';
    }));
    final s = v.settings;
    final fs = s.d('fontSize');
    return ListenableBuilder(
      listenable: Listenable.merge([partSelection, activeWord]),
      builder: (context, _) {
        _segs = _assemble(context, selKey);
        final cont = isContinuous(s);
        final children = <Widget>[];
        for (final seg in _segs) {
          children.add(_segWidget(seg, cont, fs));
          children.addAll(seg.after);
        }
        final col = Column(key: _blockKey, crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _tap,
          onLongPressStart: _longPress,
          child: cont ? Padding(padding: EdgeInsets.only(bottom: fs * 0.2), child: col) : col,
        );
      },
    );
  }

  Widget _segWidget(_Seg seg, bool cont, double fs) {
    final s = v.settings;
    final pal = s.palette;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final align = s.get<String>('textAlign') == 'justify' ? TextAlign.justify : (rtl ? TextAlign.start : textAlignOf(s));
    final style = readerTextStyle(s).copyWith(color: pal.text, height: s.d('lineHeight'));
    final hl = v.mark?.query != null;
    Widget paint(double hlOpacity) => Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PlatePainter(seg.key, seg.plates, _flash, hlOpacity))));
    final text = Text.rich(key: seg.key, seg.span, textAlign: align, style: style);
    final stack = hl
        ? TweenAnimationBuilder<double>(
            tween: Tween(end: v.mark!.fade ? 0.0 : 1.0),
            duration: s.get<bool>('animations') ? const Duration(milliseconds: 700) : Duration.zero,
            builder: (context, o, _) => Stack(fit: StackFit.passthrough, children: [paint(o), text]),
          )
        : Stack(fit: StackFit.passthrough, children: [paint(1), text]);
    if (cont) return stack;
    return Container(
      margin: EdgeInsets.only(bottom: fs * s.d('verseSpacing')),
      decoration: BoxDecoration(
        color: seg.bg,
        border: seg.selected ? Border(left: BorderSide(color: pal.accent, width: 3)) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: seg.bg != null ? const EdgeInsets.symmetric(horizontal: 4) : EdgeInsets.zero,
      child: stack,
    );
  }

  int _len(InlineSpan span) => span is TextSpan ? (span.text?.length ?? 0) + (span.children?.fold<int>(0, (a, c) => a + _len(c)) ?? 0) : 1;

  // Разбираем стихи блока на части, строим текст и подложки
  List<_Seg> _assemble(BuildContext context, String selKey) {
    final s = v.settings;
    final pal = s.palette;
    final fs = s.d('fontSize');
    final book = s.get<bool>('bookMode');
    final cont = isContinuous(s);
    final numbers = s.get<bool>('showVerseNumbers') && !book;
    final strongsOn = s.get<bool>('showStrongs') && !book;
    final verses = _verses;
    final ps = partSelection.value;
    final aw = activeWord.value;
    final mark = v.mark;
    final segs = <_Seg>[];
    _Seg? seg;
    var ch = <InlineSpan>[];
    var at = 0;
    void add(InlineSpan sp) {
      ch.add(sp);
      at += _len(sp);
    }

    void open() {
      seg = _Seg(_key(segs.length));
      segs.add(seg!);
      ch = [];
      at = 0;
      // «Как книга»: красная строка (text-indent 1,4 em)
      if (book && cont) add(WidgetSpan(child: SizedBox(width: fs * 1.4)));
    }

    for (var k = 0; k < verses.length; k++) {
      final it = verses[k];
      final vref = VerseRef(v.book, it.chapter, it.verse);
      if (seg == null) open();
      final cur = seg!;
      final decors = [for (final d in Hub.verseDecorators) d(context, ref, v.pane, v.moduleId, it, v.book)].whereType<VerseDecor>().toList();
      final partOn = ps != null && ps.pane == v.pane && ps.ref == vref;
      final selected = (selKey.isNotEmpty && selKey[k] == '1') || partOn;
      final vr = _VR(it, at);
      cur.vrs.add(vr);
      if (!book) {
        for (final d in decors) {
          d.leading.forEach(add);
        }
      }
      vr.numberStart = at;
      if (numbers) {
        add(WidgetSpan(
          alignment: s.get<String>('verseNumPos') == 'inline' ? PlaceholderAlignment.middle : PlaceholderAlignment.top,
          child: Padding(
            padding: EdgeInsets.only(right: fs * 0.2),
            child: Text('${it.verse}', style: TextStyle(fontSize: fs * s.d('verseNumSize'), color: pal.verseNum, height: 1)),
          ),
        ));
      }
      if (!book) {
        for (final d in decors) {
          d.afterNumber.forEach(add);
        }
      }
      vr.numberEnd = at;
      final tokens = it.tokens;
      final words = it.words;
      var wp = 0;
      for (var i = 0; i < tokens.length; i++) {
        final tk = tokens[i];
        final start = at;
        add(TextSpan(text: tk.text, style: tk.italic ? const TextStyle(fontStyle: FontStyle.italic) : null));
        while (wp < words.length && words[wp].token == i) {
          vr.words.add((start + words[wp].start, start + words[wp].end));
          vr.wordToken.add(i);
          wp++;
        }
        if (strongsOn && tk.tagged) {
          for (final n in tk.strongs) {
            final a = at;
            add(_strong(n, fs));
            vr.strongs.add((a, at, n));
          }
        }
      }
      final textEnd = at;
      if (!book) {
        for (final d in decors) {
          d.trailing.forEach(add);
        }
      }
      if (cont) add(const TextSpan(text: ' '));
      vr.end = at;

      // Подложки этого стиха
      final bgColor = selected ? (cont ? mix(pal.accent, 0.16, pal.panel) : pal.line) : decors.map((d) => d.background).whereType<Color>().firstOrNull;
      if (cont) {
        if (bgColor != null) cur.plates.add(_Plate(vr.start, textEnd, bgColor, unify: true));
      } else {
        cur.bg = bgColor;
        cur.selected = selected;
      }
      (int, int)? range(int from, int to) {
        if (vr.words.isEmpty) return null;
        final a = from.clamp(0, vr.words.length - 1), z = to.clamp(0, vr.words.length - 1);
        return (vr.words[a < z ? a : z].$1, vr.words[a < z ? z : a].$2);
      }

      for (final d in decors) {
        for (final (a, b) in d.parts) {
          final r = range(a, b);
          if (r != null) cur.plates.add(_Plate(r.$1, r.$2, _love.withValues(alpha: 0.2), r: 6, inflate: 2, unify: true));
        }
      }
      final pf = partOn ? ps.from : null;
      final pt = partOn ? ps.to : null;
      if (pf != null) {
        final r = range(pf, pt ?? pf);
        if (r != null) cur.plates.add(_Plate(r.$1, r.$2, pal.accent.withValues(alpha: 0.24), r: 6, inflate: 2, unify: true));
      }
      if (mark != null && mark.query != null && mark.ref.chapter == it.chapter && mark.ref.verse == it.verse) {
        for (final wi in highlightWords(it, mark.query!)) {
          if (wi < vr.words.length) cur.plates.add(_Plate(vr.words[wi].$1, vr.words[wi].$2, pal.hl, kind: 2));
        }
      }
      if (aw != null && aw.pane == v.pane && aw.ref == vref && aw.token < vr.words.length) {
        final w = vr.words[aw.token];
        cur.plates.add(_Plate(w.$1, w.$2, pal.accent.withValues(alpha: 0.26), inflate: 2));
      }
      if (_flashVerse == it.verse && _flash.isAnimating) {
        cur.plates.add(_Plate(vr.start, textEnd, pal.hl, inflate: 4, unify: true, kind: 1));
      }

      // Под стихом: выбор части стиха (PartInline) вместо строки действий выделения
      final below = partOn ? <Widget>[_PartInline(pane: v.pane, ps: ps, item: it, book: v.book)] : decors.map((d) => d.below).whereType<Widget>().toList();
      if (below.isNotEmpty) {
        cur.after = [
          for (final w in below) Padding(padding: EdgeInsets.only(bottom: partOn ? 0 : fs * s.d('verseSpacing')), child: w),
        ];
        if (cont) {
          cur.span = TextSpan(children: ch);
          seg = null;
        }
      }
      if (!cont) cur.span = TextSpan(children: ch);
    }
    if (seg != null && cont) seg!.span = TextSpan(children: ch);
    return segs;
  }

  // Номера Стронга: размер, цвет и положение (над строкой / в строке / под строкой) — по настройкам
  InlineSpan _strong(String nums, double fs) {
    final s = v.settings;
    final style = TextStyle(fontSize: fs * s.d('strongSize'), color: strongColor(s), height: 1);
    final pos = s.get<String>('strongPos');
    if (pos == 'inline') return TextSpan(text: ' $nums', style: style);
    return WidgetSpan(
      alignment: pos == 'sub' ? PlaceholderAlignment.bottom : PlaceholderAlignment.top,
      child: Padding(padding: EdgeInsets.only(left: fs * 0.12), child: Text(nums, style: style)),
    );
  }

  // ---- нажатия ----
  void _longPress(LongPressStartDetails d) {
    final vr = _hit(d.globalPosition)?.$3;
    if (vr == null) return;
    HapticFeedback.selectionClick();
    activeWord.value = null;
    ref.read(selectionProvider.notifier).toggle(v.pane, vr.ref(v.book));
  }

  // Абзац и стих под пальцем: (часть, её текст, стих, место в тексте, точка в координатах текста)
  (_Seg, RenderParagraph, _VR, int, Offset)? _hit(Offset global) {
    _Seg? best;
    RenderParagraph? bestRp;
    var bestD = double.infinity;
    for (final s in _segs) {
      final rp = _para(s);
      if (rp == null) continue;
      final local = rp.globalToLocal(global);
      final dy = local.dy < 0 ? -local.dy : (local.dy > rp.size.height ? local.dy - rp.size.height : 0.0);
      if (dy < bestD) {
        bestD = dy;
        best = s;
        bestRp = rp;
      }
    }
    if (best == null || bestRp == null || best.vrs.isEmpty) return null;
    final local = bestRp.globalToLocal(global);
    final pos = bestRp.getPositionForOffset(local).offset;
    var vr = best.vrs.last;
    for (final r in best.vrs) {
      if (pos >= r.start && pos < r.end) {
        vr = r;
        break;
      }
    }
    return (best, bestRp, vr, pos, local);
  }

  bool _on(RenderParagraph rp, int a, int b, Offset local, double slack) {
    if (b <= a) return false;
    for (final box in rp.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b))) {
      if (box.toRect().inflate(slack).contains(local)) return true;
    }
    return false;
  }

  void _tap(TapUpDetails d) {
    final h = _hit(d.globalPosition);
    if (h == null) return;
    final (_, rp, vr, pos, local) = h;
    final s = v.settings;
    final vref = vr.ref(v.book);
    final sel = ref.read(selectionProvider.notifier);
    // Номер стиха — выделить стих
    if (s.get<bool>('showVerseNumbers') && !s.get<bool>('bookMode') && _on(rp, vr.numberStart, vr.numberEnd, local, 8)) {
      activeWord.value = null;
      sel.toggle(v.pane, vref);
      return;
    }
    // Слово под пальцем
    int? wi;
    for (var i = 0; i < vr.words.length; i++) {
      final (a, b) = vr.words[i];
      if (pos >= a - 1 && pos <= b + 1 && _on(rp, a, b, local, 2)) {
        wi = i;
        break;
      }
    }
    // Выбор части стиха: нажатия по словам этого стиха задают начало и конец
    final ps = partSelection.value;
    if (ps != null && ps.pane == v.pane && ps.ref == vref) {
      if (wi != null) {
        partSelection.value = ps.from == null || ps.to != null ? PartSelection(ps.pane, ps.ref, ps.moduleId, from: wi) : PartSelection(ps.pane, ps.ref, ps.moduleId, from: ps.from, to: wi);
      }
      return;
    }
    // Уже есть выделение — нажатие на стих добавляет или снимает его
    if (ref.read(selectionProvider)[v.pane]?.isNotEmpty ?? false) {
      activeWord.value = null;
      sel.toggle(v.pane, vref);
      return;
    }
    // Двойное касание стиха — в любимые (одиночное нажатие на слово ждёт эту паузу)
    if (Hub.onVerseDoubleTap != null && _isDoubleTap('${v.pane}|${vref.book}.${vref.chapter}.${vref.verse}')) {
      _wordTimer?.cancel();
      activeWord.value = null;
      Hub.onVerseDoubleTap!(context, ref, v.pane, vref, v.moduleId);
      return;
    }
    // Номер Стронга
    for (final (a, b, n) in vr.strongs) {
      if (_on(rp, a, b, local, 6)) {
        _wordTimer?.cancel();
        activeWord.value = null;
        Hub.openStrong?.call(context, ref, v.pane, vref, n);
        return;
      }
    }
    if (wi == null) {
      activeWord.value = null;
      return;
    }
    final word = wi;
    activeWord.value = (pane: v.pane, ref: vref, token: word);
    _wordTimer?.cancel();
    if (Hub.onVerseDoubleTap == null) {
      _fireWord(vr, word);
    } else {
      _wordTimer = Timer(const Duration(milliseconds: kDoubleTapMs), () => _fireWord(vr, word));
    }
  }

  void _fireWord(_VR first, int wi) {
    var vr = first;
    if (!mounted) return;
    final a = activeWord.value;
    if (a == null || a.pane != v.pane || a.token != wi || a.ref != vr.ref(v.book)) return;
    // Блок мог перестроиться (подсветка слова) — берём стих из актуальной раскладки
    _Seg? seg;
    for (final s in _segs) {
      for (final r in s.vrs) {
        if (r.item == vr.item) {
          seg = s;
          vr = r;
        }
      }
    }
    final rp = seg == null ? null : _para(seg);
    if (rp == null || wi >= vr.words.length) return;
    final tk = vr.item.tokens[vr.wordToken[wi]];
    final (from, to) = vr.words[wi];
    final w = vr.item.words[wi];
    final token = tk.tagged ? tk : Token(tk.text.substring(w.start, w.end), italic: tk.italic);
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to));
    final box = boxes.isNotEmpty ? boxes.first.toRect() : const Rect.fromLTWH(0, 0, 1, 1);
    final topLeft = rp.localToGlobal(box.topLeft);
    Hub.onWordTap?.call(context, ref, WordTap(pane: v.pane, moduleId: v.moduleId, ref: vr.ref(v.book), token: token, tokenIndex: vr.wordToken[wi], rect: topLeft & box.size, verseText: vr.item.text));
  }
}

// ---- подложки под текстом ----

class _Plate {
  const _Plate(this.a, this.b, this.color, {this.r = 3, this.inflate = 0, this.unify = false, this.kind = 0});
  final int a, b;
  final Color color;
  final double r;
  final double inflate;
  final bool unify; // одна цельная плашка по строкам (иначе — по куску на слово)
  final int kind; // 0 обычная, 1 мигание стиха, 2 найденное слово (гаснет)
}

// Мигание: первые 30 % времени — полный цвет, дальше плавно гаснет (@keyframes flash)
double _flashAlpha(double t) {
  if (t <= 0.3) return 1;
  final k = (t - 0.3) / 0.7;
  return 1 - Curves.easeOut.transform(k.clamp(0.0, 1.0));
}

class _PlatePainter extends CustomPainter {
  _PlatePainter(this.key, this.plates, this.flash, this.hl) : super(repaint: flash);
  final GlobalKey key;
  final List<_Plate> plates;
  final Animation<double> flash;
  final double hl;

  @override
  void paint(Canvas canvas, Size size) {
    if (plates.isEmpty) return;
    final rp = key.currentContext?.findRenderObject();
    if (rp is! RenderParagraph || !rp.hasSize) return;
    for (final p in plates) {
      var color = p.color;
      if (p.kind == 1) {
        if (!flash.isAnimating) continue;
        color = color.withValues(alpha: color.a * _flashAlpha(flash.value));
      } else if (p.kind == 2) {
        color = color.withValues(alpha: color.a * hl);
      }
      if (color.a <= 0) continue;
      List<TextBox> boxes;
      try {
        boxes = rp.getBoxesForSelection(TextSelection(baseOffset: p.a, extentOffset: p.b));
      } catch (_) {
        continue;
      }
      final paint = Paint()..color = color;
      if (!p.unify) {
        for (final b in boxes) {
          canvas.drawRRect(RRect.fromRectAndRadius(b.toRect().inflate(p.inflate), Radius.circular(p.r)), paint);
        }
        continue;
      }
      // Прямоугольники строк (несколько кусков одной строки — в один)
      final lines = <Rect>[];
      for (final b in boxes) {
        final r = b.toRect();
        if (r.width < 1 || r.height < 1) continue;
        final i = lines.indexWhere((l) => ((l.top + l.bottom) / 2 - (r.top + r.bottom) / 2).abs() < r.height / 2);
        if (i >= 0) {
          lines[i] = lines[i].expandToInclude(r);
        } else {
          lines.add(r);
        }
      }
      if (lines.isEmpty) continue;
      lines.sort((x, y) => x.top.compareTo(y.top));
      canvas.drawPath(_union(lines, p.r, p.inflate), paint);
    }
  }

  // Цельная плашка со скруглёнными углами (partShape.js): строки стыкуются посередине промежутка,
  // скругляются и выступающие углы, и внутренние — на стыке строк разной длины
  static Path _union(List<Rect> src, double r, double pad) {
    final ls = [
      for (final l in src) [l.left, l.top, l.right, l.bottom]
    ];
    for (var i = 1; i < ls.length; i++) {
      final y = (ls[i - 1][3] + ls[i][1]) / 2;
      ls[i - 1][3] = y;
      ls[i][1] = y;
    }
    ls.first[1] -= pad;
    ls.last[3] += pad;
    final path = Path();
    void fillet(double x, double y, Offset c) {
      final sq = Path()..addRect(Rect.fromLTWH(x, y, r, r));
      final hole = Path()..addOval(Rect.fromCircle(center: c, radius: r - 0.25));
      path.addPath(Path.combine(PathOperation.difference, sq, hole), Offset.zero);
    }

    for (var i = 0; i < ls.length; i++) {
      final l = ls[i];
      final prev = i > 0 ? ls[i - 1] : null;
      final next = i + 1 < ls.length ? ls[i + 1] : null;
      final left = l[0] - pad, right = l[2] + pad;
      final tl = prev == null || prev[0] - pad > left + 1 ? r : 0.0;
      final tr = prev == null || prev[2] + pad < right - 1 ? r : 0.0;
      final bl = next == null || next[0] - pad > left + 1 ? r : 0.0;
      final br = next == null || next[2] + pad < right - 1 ? r : 0.0;
      path.addRRect(RRect.fromLTRBAndCorners(left, l[1], right, l[3], topLeft: Radius.circular(tl), topRight: Radius.circular(tr), bottomRight: Radius.circular(br), bottomLeft: Radius.circular(bl)));
      if (next != null && next[0] - pad < left - r) fillet(left - r, l[3] - r, Offset(left - r, l[3] - r));
      if (next != null && next[2] + pad > right + r) fillet(right, l[3] - r, Offset(right + r, l[3] - r));
      if (prev != null && prev[0] - pad < left - r) fillet(left - r, l[1], Offset(left - r, l[1] + r));
      if (prev != null && prev[2] + pad > right + r) fillet(right, l[1], Offset(right + r, l[1] + r));
    }
    return path;
  }

  @override
  bool shouldRepaint(_PlatePainter old) => true;
}

// ---- «Часть стиха»: строка под стихом (PartInline в BibleReader.jsx) ----

class _PartInline extends ConsumerWidget {
  const _PartInline({required this.pane, required this.ps, required this.item, required this.book});
  final int pane;
  final PartSelection ps;
  final ReaderItem item;
  final String book;

  void _done(WidgetRef ref) {
    partSelection.value = null;
    ref.read(selectionProvider.notifier).clear(pane);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final from = ps.from;
    final lo = from == null ? 0 : (ps.to == null ? from : (from < ps.to! ? from : ps.to!));
    final hi = from == null ? 0 : (ps.to == null ? from : (from < ps.to! ? ps.to! : from));
    final text = from == null ? '' : partText(item.tokens, item.words, lo, hi);
    final ready = from != null && text.isNotEmpty;
    final at = VerseRef(book, item.chapter, item.verse);
    final label = '${Books.instance.meta(book).short} ${item.chapter}:${item.verse}';
    Widget btn({IconData? icon, String? text, bool primary = false, required VoidCallback? onTap, String? tooltip}) {
      final fg = primary ? pal.onAccent : pal.text;
      final child = Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: primary ? pal.accent : pal.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: primary ? pal.accent : pal.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) Icon(icon, size: 17, color: fg),
                if (icon != null && text != null) const SizedBox(width: 6),
                if (text != null) Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.7, fontWeight: FontWeight.w500, color: fg))),
              ]),
            ),
          ),
        ),
      );
      return tooltip == null ? child : Tooltip(message: tooltip, child: child);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3.2, bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(ready ? '«$text»' : t('Нажмите на первое и последнее слово.'), style: TextStyle(fontSize: 14.4, height: 1.4, fontStyle: FontStyle.italic, color: pal.muted)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: btn(
              icon: LucideIcons.scrollText,
              text: t('В проповедь'),
              primary: true,
              onTap: ready
                  ? () {
                      Hub.addFragmentToSermon?.call(context, ref, at, ps.moduleId, text);
                      _done(ref);
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          btn(
            icon: LucideIcons.heart,
            tooltip: t('В любимые'),
            onTap: ready
                ? () {
                    Hub.addFavoritePart?.call(context, ref, at, ps.moduleId, lo, hi, text);
                    _done(ref);
                  }
                : null,
          ),
          const SizedBox(width: 8),
          btn(
            icon: LucideIcons.copy,
            tooltip: t('Копировать'),
            onTap: ready
                ? () async {
                    final q = '"${text.replaceAll(RegExp(r'\s+'), ' ').trim()}" - $label';
                    await Clipboard.setData(ClipboardData(text: q));
                    Hub.toast(t('Часть стиха скопирована'));
                    _done(ref);
                  }
                : null,
          ),
          const SizedBox(width: 8),
          btn(text: t('Отмена'), onTap: () => partSelection.value = null),
        ]),
      ]),
    );
  }
}
