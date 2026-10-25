// Страница «план на день» (PlanView.jsx): все отрывки дня одной лентой по порядку, закреплённая строка плана,
// автоотметка отрывка (дочитан до конца и проведено minSeconds), в конце отрывка — «Дальше по плану» и «Читать дальше — вне плана».
// Текст стихов рисует та же строка стиха, что и в читалке (VerseView): слова, выделение, закладки — всё работает так же.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/verse_view.dart';
import '../hub.dart';
import '../shell/fonts.dart' show readerTextStyle;
import 'plan_logic.dart';
import 'plan_mode.dart';
import 'plan_store.dart';
import 'reminders.dart';
import 'ui_kit.dart';

/// Подпись отрывка: «Быт 1», «Пс 9:1–21», «Пс 119–120»; full — с полным названием книги
String planReadingLabel(String r, String module, {bool full = false}) {
  if (!full) return readingLabel(r);
  final p = r.split('.');
  final name = _bookName(module, p[0]);
  if (p.length > 2 && p[2].isNotEmpty) return '$name ${p[1]}:${p[2].replaceAll('-', '–')}';
  return '$name ${(p.length > 1 && p[1].isNotEmpty ? p[1] : '1').replaceAll('-', '–')}';
}

String _bookName(String module, String id) {
  for (final b in bookList(module)) {
    if (b['id'] == id && (b['name'] as String?)?.isNotEmpty == true) return b['name'] as String;
  }
  return Books.instance.meta(id).name;
}

/// Что идёт сразу после отрывка в Библии (для «Читать дальше — вне плана»)
({VerseRef ref, String label})? planNextAfter(String r, String module) {
  final u = readingUnits(r).last;
  final bt = _book(module, u.book);
  if (bt == null) return null;
  final len = bt.items.where((x) => x.kind == ItemKind.verse && x.chapter == u.chapter).length;
  if (u.to != null && u.to! < len) return (ref: VerseRef(u.book, u.chapter, u.to! + 1), label: '${_bookName(module, u.book)} ${u.chapter}:${u.to! + 1}');
  if (u.chapter < bt.chapterCount) return (ref: VerseRef(u.book, u.chapter + 1, 1), label: '${_bookName(module, u.book)} ${u.chapter + 1}');
  final books = bookList(module);
  final i = books.indexWhere((b) => b['id'] == u.book);
  if (i < 0 || i + 1 >= books.length) return null;
  final nb = books[i + 1]['id'] as String;
  return (ref: VerseRef(nb, 1, 1), label: '${_bookName(module, nb)} 1');
}

BookText? _book(String module, String book) {
  try {
    if (!bookList(module).any((b) => b['id'] == book)) return null;
    final bt = loadBook(module, book);
    return bt.items.isEmpty ? null : bt;
  } catch (_) {
    return null;
  }
}

enum _K { intro, head, chap, verse, note, end }

class _E {
  const _E(this.k, this.r, {this.item, this.book = '', this.key, this.text = ''});
  final _K k;
  final int r; // номер отрывка дня
  final ReaderItem? item;
  final String book;
  final String? key; // отрывок (unit.key) — по нему отметки
  final String text;
}

/// Что рисует Hub.planView: страницу плана панели (перевод — из панели; сменился — страница строится заново)
class PlanHost extends ConsumerWidget {
  const PlanHost({super.key, required this.pane});
  final int pane;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = ref.watch(panesProvider.select((l) => pane < l.length ? l[pane].moduleId : ''));
    return ValueListenableBuilder(
      valueListenable: planMode,
      builder: (context, modes, _) {
        final mode = modes[pane];
        if (mode == null || module.isEmpty) return const SizedBox.shrink();
        return PlanView(key: ValueKey('${mode.uid}|${mode.day}|$module|${planOpenStamp[pane] ?? 0}'), pane: pane, uid: mode.uid, day: mode.day, module: module);
      },
    );
  }
}

class PlanView extends ConsumerStatefulWidget {
  const PlanView({super.key, required this.pane, required this.uid, required this.day, required this.module});
  final int pane, day;
  final String uid, module;
  @override
  ConsumerState<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<PlanView> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _chipsCtl = ScrollController();
  final _chipKeys = <int, GlobalKey>{};
  List<_E> _es = [];
  final _heads = <int, int>{}; // отрывок → индекс его заголовка
  final _lastVerse = <String, int>{}; // unit.key → индекс последнего стиха
  final _verseCount = <String, int>{};
  final _whole = <String, ({String book, int chapter})>{};
  final _track = <String, ({int t, bool end})>{};
  List<String> _readings = [];
  int _initial = 0;
  int _cur = 0;
  Timer? _timer;
  late final String _moduleName;

  @override
  void initState() {
    super.initState();
    _moduleName = ModuleStore.instance.get(widget.module)?.name ?? widget.module;
    _build();
    _positions.itemPositions.addListener(_onPositions);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positions.itemPositions.removeListener(_onPositions);
    _chipsCtl.dispose();
    super.dispose();
  }

  Plan? get _plan => ref.read(plansProvider).where((p) => p['uid'] == widget.uid).firstOrNull;

  void _build() {
    final plan = _plan;
    final all = plan == null ? <List<String>>[] : readingsOf(plan);
    final rs = widget.day >= 0 && widget.day < all.length ? all[widget.day] : <String>[];
    _readings = rs;
    _es = [const _E(_K.intro, 0)];
    for (var i = 0; i < rs.length; i++) {
      _heads[i] = _es.length;
      _es.add(_E(_K.head, i));
      final units = readingUnits(rs[i]);
      for (final u in units) {
        final bt = _book(widget.module, u.book);
        if (bt == null) {
          _es.add(_E(_K.note, i, book: u.book));
          continue;
        }
        final items = [
          for (final it in bt.items)
            if (it.kind != ItemKind.chapter && it.chapter == u.chapter && it.verse >= u.from && (u.to == null || it.verse <= u.to!)) it,
        ];
        if (items.where((x) => x.kind == ItemKind.verse).isEmpty) continue;
        if (units.length > 1) {
          _es.add(_E(_K.chap, i, book: u.book, key: u.key, text: u.book == 'Ps' ? t('Псалом {n}', {'n': '${u.chapter}'}) : t('Глава {n}', {'n': '${u.chapter}'})));
        }
        for (final it in items) {
          _es.add(_E(_K.verse, i, item: it, book: u.book, key: u.key));
          if (it.kind == ItemKind.verse) _lastVerse[u.key] = _es.length - 1;
        }
        _verseCount[u.key] = items.where((x) => x.kind == ItemKind.verse).length;
        if (u.to == null) _whole[u.key] = (book: u.book, chapter: u.chapter);
      }
      _es.add(_E(_K.end, i));
    }
    // Куда прокрутить: открытый день или «К плану» — к отрывку или стиху; иначе — к последнему месту чтения
    final st = planStart.remove(widget.pane);
    if (st?.at != null) {
      _initial = st!.at! > 0 ? (_heads[st.at!] ?? 0) : 0;
    } else {
      final target = st?.ref ?? livePositions[widget.pane]?.value ?? ref.read(panesProvider)[widget.pane].ref;
      final k = _es.indexWhere((e) => e.item != null && e.item!.kind == ItemKind.verse && e.book == target.book && e.item!.chapter == target.chapter && e.item!.verse == target.verse);
      _initial = k < 0 ? 0 : k;
    }
  }

  void _onPositions() {
    final pos = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0).toList();
    if (pos.isEmpty) return;
    final top = pos.reduce((a, b) => a.index < b.index ? a : b);
    final e = _es[math.min(top.index, _es.length - 1)];
    if (e.r != _cur && mounted) {
      setState(() => _cur = e.r);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _chipKeys[_cur]?.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 250));
      });
    }
    for (var k = top.index; k < math.min(_es.length, top.index + 40); k++) {
      final x = _es[k];
      if (x.item != null && x.item!.kind == ItemKind.verse) {
        final r = VerseRef(x.book, x.item!.chapter, x.item!.verse);
        livePosition(widget.pane, r).value = r;
        ref.read(panesProvider.notifier).remember(widget.pane, r);
        break;
      }
    }
  }

  // Автоотметки: раз в секунду добавляем время каждому видимому отрывку и смотрим, дочитан ли он до конца
  void _tick() {
    if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return; // открыто окно — не считаем
    final plan = _plan;
    if (plan == null) return;
    final pos = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1).toList();
    if (pos.isEmpty) return;
    final seen = <String>{};
    for (final p in pos) {
      final k = p.index < _es.length ? _es[p.index].key : null;
      if (k != null) seen.add(k);
    }
    final hits = <String>[];
    for (final key in seen) {
      if (unitDone(plan, widget.day, key)) continue;
      final cur = _track[key] ?? (t: 0, end: false);
      var end = cur.end;
      final li = _lastVerse[key];
      if (li != null && pos.any((p) => p.index == li && p.itemTrailingEdge <= 1.02)) end = true;
      final tt = cur.t + 1;
      _track[key] = (t: tt, end: end);
      if (end && tt >= minSeconds(_verseCount[key] ?? 1)) hits.add(key);
    }
    if (hits.isEmpty) return;
    for (final key in hits) {
      final w = _whole[key];
      if (w != null) {
        logChapter(w.book, w.chapter);
        ref.read(plansProvider.notifier).creditChapter(w.book, w.chapter);
      }
    }
    final finished = ref.read(plansProvider.notifier).markUnits(widget.uid, widget.day, hits);
    scheduleReminders();
    if (finished) {
      Hub.toast(t('План на сегодня выполнен 🎉'));
    } else {
      final np = _plan;
      final r = _readings.where((x) => readingUnits(x).any((u) => u.key == hits.first)).firstOrNull;
      if (np != null && r != null && readingDone(np, widget.day, r)) Hub.toast(t('✓ Прочитано: {ref}', {'ref': readingLabel(r)}));
    }
  }

  void _markReading(String r) {
    for (final u in readingUnits(r)) {
      if (u.to == null) logChapter(u.book, u.chapter);
    }
    final finished = ref.read(plansProvider.notifier).markUnits(widget.uid, widget.day, [for (final u in readingUnits(r)) u.key]);
    scheduleReminders();
    if (finished) Hub.toast(t('План на сегодня выполнен 🎉'));
  }

  void _toReading(int i) {
    if (!_scroll.isAttached) return;
    final anim = ref.read(settingsProvider).get<bool>('animations');
    final idx = i == 0 ? 0 : (_heads[i] ?? 0);
    if (anim) {
      _scroll.scrollTo(index: idx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _scroll.jumpTo(index: idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = s.palette;
    final plan = ref.watch(plansProvider.select((l) => l.where((p) => p['uid'] == widget.uid).firstOrNull));
    if (plan == null || _readings.isEmpty) {
      return ColoredBox(
        color: pal.bg,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('Этот план удалён или в нём нет такого дня.'), style: TextStyle(color: pal.muted)),
              AobButton(small: true, label: t('Обычное чтение'), onTap: () => exitPlan(widget.pane)),
            ]),
          ),
        ),
      );
    }
    final n = _readings.length;
    final flags = [for (final r in _readings) readingDone(plan, widget.day, r)];
    final doneCount = flags.where((x) => x).length;
    final firstLeft = flags.indexWhere((x) => !x);
    final fs = s.d('fontSize');
    return ColoredBox(
      color: pal.bg,
      child: Column(children: [
        _Strip(pane: widget.pane, day: widget.day, n: n, doneCount: doneCount, readings: _readings, flags: flags, cur: _cur, chips: _chipsCtl, keys: _chipKeys, onChip: _toReading),
        Expanded(
          child: ScrollablePositionedList.builder(
            key: ValueKey('${widget.uid}|${widget.day}|${widget.module}'),
            itemCount: _es.length,
            initialScrollIndex: _initial,
            itemScrollController: _scroll,
            itemPositionsListener: _positions,
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 76),
            itemBuilder: (context, i) {
              final e = _es[i];
              final Widget w = switch (e.k) {
                _K.intro => _intro(pal, plan, n),
                _K.head => _head(pal, e.r, flags[e.r]),
                _K.chap => Padding(
                    padding: EdgeInsets.only(top: fs * 0.8),
                    child: Text(e.text, style: readerTextStyle(s, size: fs * s.d('chapterTitleSize') * 0.55, weight: 800).copyWith(color: pal.muted, height: 1.1)),
                  ),
                _K.verse => VerseView(item: e.item!, book: e.book, settings: s, pane: widget.pane, moduleId: widget.module),
                _K.note => Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line)),
                    child: Text(t('В переводе {module} нет книги «{book}». Выберите другой перевод вверху.', {'module': _moduleName, 'book': Books.instance.meta(e.book).name}), style: TextStyle(color: pal.muted, fontSize: 14.4)),
                  ),
                _K.end => _end(pal, plan, e.r, flags, firstLeft),
              };
              return Center(
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: s.d('textWidth') * fs), child: SizedBox(width: double.infinity, child: w)),
              );
            },
          ),
        ),
      ]),
    );
  }

  TextStyle _ui(Palette pal, double size, {FontWeight? weight, Color? color}) => TextStyle(fontSize: size, fontWeight: weight, color: color ?? pal.text);

  Widget _intro(Palette pal, Plan plan, int n) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('${plan['name']}'), style: _ui(pal, 16.8, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${t('День {n} из {total}', {'n': '${widget.day + 1}', 'total': '${readingsOf(plan).length}'})} · ${tn('{n} отрывок|{n} отрывка|{n} отрывков', n)}', style: _ui(pal, 13.8, color: pal.muted)),
          const SizedBox(height: 8),
          Text(t('Читайте подряд — отрывок отметится сам.'), style: _ui(pal, 13.4, color: pal.muted).copyWith(height: 1.45)),
        ]),
      );

  Widget _head(Palette pal, int r, bool done) => Padding(
        padding: EdgeInsets.only(top: r == 0 ? 10 : 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r > 0) CustomPaint(painter: _Dashed(pal.line, 2), size: const Size(double.infinity, 2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 2, children: [
              Text(planReadingLabel(_readings[r], widget.module, full: true), style: _ui(pal, 23.2, weight: FontWeight.w700)),
              if (done)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(LucideIcons.check, size: 14, color: kOk),
                  const SizedBox(width: 4),
                  Text(t('Прочитано'), style: _ui(pal, 12.8, weight: FontWeight.w600, color: kOk)),
                ]),
            ]),
          ),
        ]),
      );

  Widget _end(Palette pal, Plan plan, int i, List<bool> flags, int firstLeft) {
    final n = _readings.length;
    final allDone = !flags.contains(false);
    final r = _readings[i];
    // Следующая глава и так в плане этого дня — кнопку «вне плана» не показываем
    final nx = planNextAfter(r, widget.module);
    final inPlan = nx != null && _readings.any((x) => readingUnits(x).any((u) => u.book == nx.ref.book && u.chapter == nx.ref.chapter && u.from == nx.ref.verse));
    final next = inPlan ? null : nx;
    final totalDays = readingsOf(plan).length;
    const gap = SizedBox(height: 10);
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 26),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (flags[i])
          Row(children: [
            const Icon(LucideIcons.check, size: 16, color: kOk),
            const SizedBox(width: 6),
            Flexible(child: Text(t('{ref} — прочитано', {'ref': readingLabel(r)}), style: _ui(pal, 14.7, weight: FontWeight.w600, color: kOk))),
          ])
        else
          Align(alignment: Alignment.centerLeft, child: _Btn(label: t('Отметить прочитанным'), icon: LucideIcons.check, kind: _BK.subtle, expand: false, onTap: () => _markReading(r))),
        gap,
        if (i < n - 1)
          _Btn(label: t('Дальше: {ref}', {'ref': readingLabel(_readings[i + 1])}), trailing: LucideIcons.chevronDown, kind: _BK.primary, onTap: () => _toReading(i + 1))
        else if (allDone)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(LucideIcons.partyPopper, size: 22, color: kOk),
              const SizedBox(width: 10),
              Expanded(child: Text(t('План на сегодня выполнен'), style: _ui(pal, 16, weight: FontWeight.w700).copyWith(height: 1.3))),
              const SizedBox(width: 10),
              _Btn(label: t('Готово'), kind: _BK.primary, onTap: () => exitPlan(widget.pane), expand: false),
            ]),
            if (widget.day < totalDays - 1) ...[
              gap,
              _Btn(label: t('Читать день {n}', {'n': '${widget.day + 2}'}), trailing: LucideIcons.chevronRight, kind: _BK.plain, onTap: () => openPlanDay(widget.pane, widget.uid, widget.day + 1)),
            ],
          ])
        else
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(t('Осталось:'), style: _ui(pal, 14.2, color: pal.muted)),
            for (var j = 0; j < n; j++)
              if (!flags[j]) AobChip(label: readingLabel(_readings[j]), onTap: () => _toReading(j)),
          ]),
        if (next != null) ...[
          gap,
          _OffPlan(
            main: t('Читать дальше: {ref}', {'ref': next.label}),
            sub: t('не входит в план'),
            onTap: () {
              planReturnAt[widget.pane] = i < n - 1 ? i + 1 : (firstLeft >= 0 ? firstLeft : i);
              ref.read(panesProvider.notifier).navigate(widget.pane, next.ref, flash: false);
            },
          ),
        ],
      ]),
    );
  }
}

/// Закреплённая строка плана (.plan-strip): «День N · done/n», отрывки-вкладки, выход из плана
class _Strip extends ConsumerWidget {
  const _Strip({required this.pane, required this.day, required this.n, required this.doneCount, required this.readings, required this.flags, required this.cur, required this.chips, required this.keys, required this.onChip});
  final int pane, day, n, doneCount, cur;
  final List<String> readings;
  final List<bool> flags;
  final ScrollController chips;
  final Map<int, GlobalKey> keys;
  final void Function(int) onChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Semantics(
      label: t('Отрывки плана на день'),
      child: Container(
        height: 42,
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(color: pal.bg.withValues(alpha: 0.97), border: Border(bottom: BorderSide(color: pal.line))),
        child: Row(children: [
          Text('${t('День {n}', {'n': '${day + 1}'})} · $doneCount/$n', style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700, color: pal.muted)),
          const SizedBox(width: 6),
          Expanded(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.06, 0.94, 1]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                controller: chips,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  for (var i = 0; i < n; i++)
                    InkWell(
                      key: keys.putIfAbsent(i, GlobalKey.new),
                      onTap: () => onChip(i),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        alignment: Alignment.center,
                        child: Stack(alignment: Alignment.bottomCenter, children: [
                          Center(
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (flags[i]) ...[Icon(LucideIcons.check, size: 12, color: pal.accent), const SizedBox(width: 4)],
                              Text(readingLabel(readings[i]), style: TextStyle(fontSize: 14.1, fontWeight: cur == i ? FontWeight.w700 : FontWeight.w500, color: flags[i] ? pal.muted : pal.text)),
                            ]),
                          ),
                          if (cur == i) Container(height: 2.5, color: pal.accent),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          IconBtn(icon: LucideIcons.x, subtle: true, size: 17, tooltip: t('Выйти из плана'), onTap: () => exitPlan(pane)),
        ]),
      ),
    );
  }
}

enum _BK { primary, subtle, plain }

class _Btn extends ConsumerWidget {
  const _Btn({required this.label, required this.onTap, this.icon, this.trailing, this.kind = _BK.plain, this.expand = true});
  final String label;
  final VoidCallback onTap;
  final IconData? icon, trailing;
  final _BK kind;
  final bool expand;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final (bg, fg, border) = switch (kind) {
      _BK.primary => (pal.accent, pal.onAccent, pal.accent),
      _BK.subtle => (Colors.transparent, pal.muted, pal.line),
      _BK.plain => (Colors.transparent, pal.text, pal.line),
    };
    final small = kind == _BK.subtle;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: small ? 6 : (kind == _BK.primary && expand ? 11 : 9)),
          child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
            Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: small ? 13.8 : 15, fontWeight: kind == _BK.plain ? FontWeight.w500 : FontWeight.w600, color: fg))),
            if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 17, color: fg)],
          ]),
        ),
      ),
    );
  }
}

class _OffPlan extends ConsumerWidget {
  const _OffPlan({required this.main, required this.sub, required this.onTap});
  final String main, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return CustomPaint(
      foregroundPainter: _DashedBox(pal.line, kRadius * 0.8),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius * 0.8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(main, style: TextStyle(fontSize: 14.4, fontWeight: FontWeight.w600, color: pal.text))),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 15, color: pal.text),
            ]),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 12.2, color: pal.muted)),
          ]),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  _Dashed(this.color, this.w);
  final Color color;
  final double w;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = w;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, w / 2), Offset(math.min(x + 4, size.width), w / 2), p);
    }
  }

  @override
  bool shouldRepaint(_Dashed o) => o.color != color;
}

class _DashedBox extends CustomPainter {
  _DashedBox(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox o) => o.color != color;
}
