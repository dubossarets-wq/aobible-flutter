// Планы чтения (PlansSheet.jsx): «Стих дня», активные планы с кольцом прогресса и кнопкой «Читать», напоминание,
// сколько прочитано (кольцо «доля Библии», дни подряд, неделя), готовые планы с обложками и свой план.
// Размеры и цвета — по styles.css (.plan-card, .read-hero, .plan-tile, .custom-plan…).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import 'loc.dart';
import 'net_cache.dart';
import 'plan_logic.dart';
import 'plan_mode.dart';
import 'plan_store.dart';
import '../shell/intl_data.dart' show monthDayTemplates;
import 'reminders.dart';
import 'ui_kit.dart';
import 'verse_card.dart';

// Обложки планов: фото (из фонов для картинок со стихом), значок и цвет; свой план и неизвестные — по умолчанию
class _Look {
  const _Look(this.icon, this.c1, this.c2, this.photo);
  final IconData icon;
  final Color? c1, c2; // null — цвет темы
  final String photo;
}

const _looks = <String, _Look>{
  'mcheyne': _Look(LucideIcons.library, Color(0xFF7B61D6), Color(0xFFA98BF0), '10'),
  'bible-year': _Look(LucideIcons.calendarDays, Color(0xFF2F7FC8), Color(0xFF5BB7E8), '06'),
  'nt-90': _Look(LucideIcons.sunrise, Color(0xFFE07A2F), Color(0xFFF3B75C), '01'),
  'ps-prov-31': _Look(LucideIcons.music, Color(0xFF26936F), Color(0xFF5FC99C), '07'),
  'gospels-30': _Look(LucideIcons.feather, Color(0xFFC2477A), Color(0xFFEC85A8), '02'),
};
const _defaultLook = _Look(LucideIcons.sparkles, null, null, '08');
_Look _look(String? id) => _looks[id] ?? _defaultLook;
String _coverPath(String? id) => 'images/verse-bg/${_look(id).photo}.jpg';

const _bibleChapters = 1189;

class PlansSheet extends ConsumerStatefulWidget {
  const PlansSheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends ConsumerState<PlansSheet> {
  List<PlanMeta>? _index;
  String? _err;
  String? _busy;
  String _scope = 'nt';
  int _days = 90;
  String? _pick;
  late final _daysCtl = TextEditingController(text: '$_days');
  final _detailKey = GlobalKey();
  // Свой план: режим, свои книги и разделы запоминаются (ключи веб-версии, JSON как в localStorage)
  String _mode = 'seq';
  List<String> _own = [];
  Map<String, int> _streams = {'ot': 1, 'nt': 1, 'ps': 1};
  int _parDays = 0; // сколько дней выйдет у параллельного плана
  String _parMode = 'perday'; // «Глав в день» или «За срок»
  int _periodDays = 90;
  late final _periodCtl = TextEditingController(text: '$_periodDays');

  List<String> get _ownOrdered => [for (final b in Books.instance.all) if (_own.contains(b.id)) b.id];

  void _loadCustom() {
    try {
      final m = prefs.getString('customPlanMode');
      if (m != null) _mode = jsonDecode(m) == 'par' ? 'par' : 'seq';
      final o = prefs.getString('customPlanBooks');
      if (o != null) _own = [for (final x in jsonDecode(o) as List) '$x'];
      final pm = prefs.getString('customPlanParMode');
      if (pm != null) _parMode = jsonDecode(pm) == 'period' ? 'period' : 'perday';
      final pd = prefs.getString('customPlanParDays');
      if (pd != null) _periodDays = ((jsonDecode(pd) as num).toInt()).clamp(7, 730);
      _periodCtl.text = '$_periodDays';
      final s = prefs.getString('customPlanStreams');
      if (s != null) _streams = {for (final e in (jsonDecode(s) as Map).entries) '${e.key}': ((e.value as num).toInt()).clamp(1, 10)};
    } catch (_) {}
    _recalc();
  }

  void _recalc() => _parDays = _mode == 'par' && _parMode == 'perday' ? parallelDays(streamList(_streams, _ownOrdered), chapterList) : 0;

  void _setMode(String m) => setState(() {
        _mode = m;
        prefs.setString('customPlanMode', jsonEncode(m));
        _recalc();
      });

  void _setParMode(String m) => setState(() {
        _parMode = m;
        prefs.setString('customPlanParMode', jsonEncode(m));
        _recalc();
      });

  void _setPeriod(int v) => setState(() {
        _periodDays = v.clamp(7, 730);
        _periodCtl.text = '$_periodDays';
        prefs.setString('customPlanParDays', jsonEncode(_periodDays));
      });

  void _setStreams(Map<String, int> s) => setState(() {
        _streams = s;
        prefs.setString('customPlanStreams', jsonEncode(s));
        _recalc();
      });

  void _toggleBook(String id) => setState(() {
        _own = _own.contains(id) ? [for (final x in _own) if (x != id) x] : [..._own, id];
        prefs.setString('customPlanBooks', jsonEncode(_own));
        _recalc();
      });


  @override
  void initState() {
    super.initState();
    ensureDict();
    _loadCustom();
    fetchPlanIndex().then((i) => mounted ? setState(() => _index = i) : null, onError: (e) => mounted ? setState(() => _err = '$e'.replaceFirst('Exception: ', '')) : null);
  }

  @override
  void dispose() {
    _daysCtl.dispose();
    _periodCtl.dispose();
    super.dispose();
  }

  void _go(VerseRef r) {
    closeToReader(context); // сразу в Библию, а не в окно под планами
    ref.read(panesProvider.notifier).navigate(widget.pane, r);
  }

  void _read(Plan plan, int day, int at) {
    // Весь день плана одной страницей, с прокруткой к нужному отрывку (openPlanDay в веб-версии)
    final rs = readingsOf(plan);
    if (day >= rs.length || at >= rs[day].length) return;
    Navigator.of(context).pop();
    openPlanDay(widget.pane, '${plan['uid']}', day, at: at);
  }

  void _add(Plan plan) {
    final cal = plan['calendar'] == true;
    ref.read(plansProvider.notifier).add({
      ...plan,
      'uid': DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      'start': localDate(),
      'done': <String, dynamic>{},
      if (cal) 'year': DateTime.now().year,
    });
    scheduleReminders();
    final started = t('План «{name}» начат — нажмите «Читать»', {'name': t('${plan['name']}')});
    // без напоминания планы чаще бросают — сразу предлагаем включить
    if (remindersSupported && !getReminder().on) {
      final pal = paletteOf(ref);
      ScaffoldMessenger.of(context).showSnackBar(aobSnackBar(pal, started, actionLabel: t('Напоминать о чтении'), action: () async {
        final ok = await setReminder(on: true);
        if (!mounted) return;
        setState(() {});
        toast(context, ok ? t('Напомню в {time}', {'time': getReminder().time}) : t('Уведомления запрещены — разрешите их в настройках телефона'));
      }));
    } else {
      toast(context, started);
    }
  }

  Future<void> _start(PlanMeta m) async {
    setState(() => _busy = m.id);
    try {
      final p = await fetchPlan(m.file);
      if ((p['readings'] as List?)?.isEmpty ?? true) throw Exception(t('План не загрузился')); // пустой план окно не покажет
      _add({'planId': p['id'], 'name': p['name'], 'readings': p['readings'], 'calendar': p['calendar'] == true});
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // «Исаия, Деяния» или «Исаия, Деяния и ещё 3»
  String _ownLabel() {
    final names = [for (final id in _ownOrdered) Books.instance.meta(id).name];
    return names.length > 2 ? t('{books} и ещё {n}', {'books': names.take(2).join(', '), 'n': '${names.length - 2}'}) : names.join(', ');
  }

  Future<void> _startCustom() async {
    final n = _days.clamp(7, 730);
    setState(() => _busy = 'custom');
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30)); // дать перерисоваться индикатору
      if (_mode == 'par') {
        final list = streamList(_streams, _ownOrdered);
        final period = _parMode == 'period' ? _periodDays.clamp(7, 730) : null;
        final readings = makeParallelPlan(list, chapterList, period: period);
        if (readings.isEmpty) throw Exception(t('Выберите книги'));
        final names = [for (final x in list) x.key == 'own' ? _ownLabel() : t(planStreams.firstWhere((s) => s.key == x.key).short)].join(' + ');
        _add({'planId': 'custom', 'name': period != null ? t('{scope} за {n} дн.', {'scope': names, 'n': '${readings.length}'}) : t('{list} параллельно', {'list': names}), 'readings': readings});
        return;
      }
      final books = _scope == 'own' ? _ownOrdered : planScopes.firstWhere((s) => s.id == _scope).books();
      if (books.isEmpty) throw Exception(t('Выберите книги'));
      final readings = makeCustomPlan(books, n);
      if (readings.isEmpty) throw Exception(t('Не удалось составить план'));
      // Глав меньше, чем дней (Евангелия за 730 дней) — дней столько, сколько глав
      final label = _scope == 'own' ? _ownLabel() : t(planScopes.firstWhere((s) => s.id == _scope).label);
      _add({'planId': 'custom', 'name': t('{scope} за {n} дн.', {'scope': label, 'n': '${readings.length}'}), 'readings': readings});
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _setDays(int v) => setState(() {
        _days = v.clamp(7, 730);
        _daysCtl.text = '$_days';
      });

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final plans = ref.watch(plansProvider);
    final days = _days.clamp(7, 730);
    // .sheet-body: колонка с промежутком 12 между блоками
    const gap = SizedBox(height: 12);
    return AobSheet(
      title: t('Планы чтения'),
      scroll: false,
      padding: EdgeInsets.zero,
      child: Builder(builder: (bc) => ListView(padding: padTabs(bc, const EdgeInsets.fromLTRB(16, 12, 16, 20)), children: [
        VerseOfDayCard(pane: widget.pane, onRead: _go),
        gap,
        for (final p in plans) ...[
          _ActivePlan(
            key: ValueKey(p['uid']),
            pal: pal,
            plan: p,
            onRead: _read,
            onChange: (np) {
              ref.read(plansProvider.notifier).replace(np);
              scheduleReminders();
            },
            onRemove: () {
              ref.read(plansProvider.notifier).remove('${p['uid']}');
              scheduleReminders();
            },
          ),
          gap,
        ],
        if (remindersSupported && plans.isNotEmpty) ...[_ReminderCard(pal: pal), gap],
        _ReadHero(pal: pal, open: (key) {
          final c = key.split('.');
          _go(VerseRef(c[0], int.tryParse(c[1]) ?? 1, 1));
        }),
        gap,
        // .nav-group: заголовок h4 и содержимое с промежутком 8
        GroupTitle(plans.isNotEmpty ? t('Ещё планы') : t('Выберите план')),
        const SizedBox(height: 2),
        if (_err != null) Text(_err!, style: TextStyle(color: dangerOf(pal), fontSize: 13.6, height: 1.4)),
        if (_index == null && _err == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Spinner(color: pal.muted, size: 16),
              const SizedBox(width: 10),
              Text(t('Загружаю планы…'), style: TextStyle(color: pal.muted, fontSize: 13.6)),
            ]),
          ),
        if (_index != null)
          LayoutBuilder(builder: (_, c) {
            // repeat(auto-fill, minmax(150px, 1fr)), промежуток 12
            final cols = math.max(1, ((c.maxWidth + 12) / 162).floor());
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero, // без него сетка берёт снизу поле под нижнее меню — лишний пустой отступ
              clipBehavior: Clip.none,
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 8 / 5, // вдвое ниже, чем 4:5 в веб-версии — по просьбе владельца
              children: [
                for (final m in _index!)
                  _PlanTile(
                    pal: pal,
                    m: m,
                    on: _pick == m.id,
                    onPick: () {
                      setState(() => _pick = _pick == m.id ? null : m.id);
                      Future.delayed(const Duration(milliseconds: 80), () {
                        final c = _detailKey.currentContext;
                        if (mounted && c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.6);
                      });
                    },
                  ),
              ],
            );
          }),
        if (_index != null)
          for (final m in _index!.where((m) => m.id == _pick))
            Container(
              key: _detailKey,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: pal.bg), // скругление — как у «Своего плана»
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t(m.name), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                const SizedBox(height: 6),
                Text('${t('{n} дн.', {'n': '${m.days}'})}${m.short != null ? ' · ${t(m.short!)}' : ''}', style: TextStyle(color: pal.muted, fontSize: 13.1)),
                if (m.description != null) Padding(padding: const EdgeInsets.fromLTRB(0, 8, 0, 6), child: Text(t(m.description!), style: TextStyle(color: pal.muted, fontSize: 13.1, height: 1.4))),
                const SizedBox(height: 6),
                _busy == m.id ? BusyButton(label: t('Начать')) : AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.plus, label: t('Начать'), onTap: _busy != null ? null : () => _start(m)),
              ]),
            ),
        gap, // между блоками везде 12
        _customPlan(pal, days),
      ])),
    );
  }

  // Свой план — отдельной карточкой: режим, что читать, за сколько дней, начать (.custom-plan)
  Widget _customPlan(Palette pal, int days) {
    final par = _mode == 'par';
    final needOwn = (par ? _streams.containsKey('own') : _scope == 'own') && _own.isEmpty;
    final period = par && _parMode == 'period';
    // срок и дата окончания — в строке нагрузки над кнопкой
    final startLabel = par && !period && _parDays == 0 ? t('Выберите книги') : t('Начать');
    final off = _busy != null || needOwn || (par && !period && _parDays == 0);
    return Container(
      padding: const EdgeInsets.all(16),
      // лёгкая подложка цвета акцента — карточка отделяется от окна
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: cardFill(pal)), // чистая нейтральная подложка — белые плитки на ней видны
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: mix(pal.accent, 0.14, pal.panel)),
            child: Icon(LucideIcons.calendarPlus, size: 22, color: pal.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Свой план'), style: TextStyle(fontSize: 16.8, fontWeight: FontWeight.w700, height: 1.25, color: pal.text)),
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(par ? t('Каждый день — немного из разных частей Библии') : t('Читаете книги по порядку, понемногу каждый день'), style: TextStyle(fontSize: 13.4, color: pal.muted, height: 1.35))),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Segmented<String>(value: _mode, onChanged: _setMode, options: [('seq', t('Последовательно')), ('par', t('Параллельно'))]),
        const SizedBox(height: 10),
        // «Последовательно» ↔ «Параллельно»: одно сворачивается, другое раскрывается
        Reveal(open: par, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _parallelBody(pal))),
        Reveal(open: !par, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _seqBody(pal, days))),
        const SizedBox(height: 14),
        _busy == 'custom' ? BusyButton(label: startLabel) : AobButton(kind: BtnKind.primary, wide: true, icon: Icons.play_arrow_rounded, label: startLabel, onTap: off ? null : _startCustom),
      ]),
    );
  }

  Widget _label(Palette pal, String s) => Text(s, style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: pal.muted));

  // «Последовательно»: раздел или свои книги за N дней
  List<Widget> _seqBody(Palette pal, int days) => [
        _label(pal, t('Что читать')),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - 8) / 2;
          final items = [for (final s in planScopes) (s.id, s.label), ('own', 'Свои книги')];
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, s) in items.indexed)
              SizedBox(
                width: i == 0 || s.$1 == 'own' ? c.maxWidth : w, // «Вся Библия» и «Свои книги» — на всю ширину
                // выбранный вариант — рамка, фон и надпись перетекают плавно
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _scope == s.$1 ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.fastOutSlowIn,
                  builder: (context, v, _) => Material(
                    animationDuration: Duration.zero,
                    color: Color.lerp(pal.panel, mix(pal.accent, 0.12, pal.panel), v), // на подложке карточки — белые
                    // очень лёгкая обводка — плашка чуть чётче на подложке
                    // без рамки у невыбранных: белые плитки на подложке и так видны — меньше линий, спокойнее
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Color.lerp(plateEdge(pal), pal.accent, v)!, width: 1.5)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _scope = s.$1),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        alignment: Alignment.center,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          // у каждого раздела свой значок (как у готовых планов): Библия — книга, Ветхий — свиток,
                          // Новый — книга с крестом, Евангелия — крест, Псалтирь — нота, свои книги — список с отметками (выборка)
                          _scopeIcon(s.$1, 17, Color.lerp(pal.muted, accentOnTint(pal), v)!),
                          const SizedBox(width: 7),
                          Flexible(child: Text(t(s.$2), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.7, fontWeight: FontWeight.w600, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: Color.lerp(pal.text, accentOnTint(pal), v)))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        }),
        // свои книги раскрываются и сворачиваются плавно
        Reveal(open: _scope == 'own', child: Padding(padding: const EdgeInsets.only(top: 10), child: _BookPicker(pal: pal, value: _own, onToggle: _toggleBook))),
        const SizedBox(height: 12),
        ..._daysBlock(pal, days, _daysCtl, _setDays, (v) => setState(() => _days = int.tryParse(v) ?? 90), _seqBooks),
      ];

  // «За сколько дней»: число с «−»/«+» и быстрые значения — общий для «Последовательно» и «Параллельно → За срок»
  List<Widget> _daysBlock(Palette pal, int days, TextEditingController ctl, void Function(int) set, void Function(String) changed, List<String> books) => [
        _label(pal, t('За сколько дней')),
        const SizedBox(height: 10),
        _DaysStepper(pal: pal, days: days, ctl: ctl, set: set, changed: changed),
        const SizedBox(height: 8),
        // во что выльется выбор: «≈ 13 гл. в день · до 24 января»
        _LoadLine(pal: pal, books: books, days: days),
        const SizedBox(height: 10),
        // сроки словами — два ряда по три, точное число — кнопками «− / +» выше
        for (final (r, row) in const [
          [(7, 'Неделя'), (14, '2 недели'), (30, 'Месяц')],
          [(90, '3 месяца'), (180, 'Полгода'), (365, 'Год')],
        ].indexed) ...[
          if (r > 0) const SizedBox(height: 6),
          Row(children: [
            for (final (i, (n, label)) in row.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _Preset(pal: pal, label: t(label), on: days == n, center: true, onTap: () => set(n))),
            ],
          ]),
        ],
      ];

  List<String> get _seqBooks => _scope == 'own' ? _ownOrdered : planScopes.firstWhere((s) => s.id == _scope).books();
  List<String> get _parBooks => [for (final x in streamList(_streams, _ownOrdered)) ...x.books];

  // «Параллельно»: разделы с галочкой и числом глав в день (.cp-streams)
  List<Widget> _parallelBody(Palette pal) => [
        Segmented<String>(value: _parMode, onChanged: _setParMode, options: [('perday', t('Глав в день')), ('period', t('За срок'))]),
        const SizedBox(height: 10),
        _label(pal, _parMode == 'period' ? t('Разделы') : t('Разделы и глав в день')),
        const SizedBox(height: 10),
        for (final s in planStreams) ...[
          _StreamRow(
            pal: pal,
            label: t(s.label),
            per: _streams[s.key],
            steps: _parMode != 'period',
            onToggle: () => _setStreams(_streams.containsKey(s.key) ? {for (final e in _streams.entries) if (e.key != s.key) e.key: e.value} : {..._streams, s.key: 1}),
            onPer: (d) => _setStreams({..._streams, s.key: ((_streams[s.key] ?? 1) + d).clamp(1, 10)}),
          ),
          const SizedBox(height: 8),
        ],
        Reveal(open: _streams.containsKey('own'), child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _BookPicker(pal: pal, value: _own, onToggle: _toggleBook))),
        // «За срок» ↔ «Глав в день»: срок и пояснение сменяют друг друга плавно
        Reveal(open: _parMode == 'period', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _daysBlock(pal, _periodDays, _periodCtl, _setPeriod, (v) => setState(() => _periodDays = int.tryParse(v) ?? 90), _parBooks))),
        Reveal(
          open: _parMode != 'period',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // как выглядит обычный день — меняется с каждым нажатием
            if (_streams.isNotEmpty)
              Builder(builder: (context) {
                final first = firstDayText(streamList(_streams, _ownOrdered), chapterList);
                return first.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(t('Первый день: {list}', {'list': first}), style: TextStyle(fontSize: 13.6, height: 1.4, fontWeight: FontWeight.w600, color: pal.text)),
                      );
              }),
            Text(t('Псалтирь и Притчи читаются по кругу, остальные разделы — один раз. Чтобы все разделы закончились в один день, выберите «{mode}».', {'mode': t('За срок')}), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted)),
          ]),
        ),
      ];
}

/// .cp-presets .chip: плашка выше обычной (min-height 36, отступы 6/14)
class _Preset extends StatelessWidget {
  const _Preset({required this.pal, required this.label, required this.on, required this.onTap, this.center = false});
  final Palette pal;
  final String label;
  final bool on;
  final bool center; // в ряду равной ширины — надпись по центру
  final VoidCallback onTap;
  @override
  // выбор — плавно: фон, рамка и надпись перетекают в цвет акцента
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: on ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.fastOutSlowIn,
        builder: (context, v, _) => Material(
          animationDuration: Duration.zero,
          color: Color.lerp(pal.panel, pal.accent, v),
          shape: StadiumBorder(side: BorderSide(color: Color.lerp(plateEdge(pal), pal.accent, v)!)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            // без alignment у Container: с ним плашка растягивалась на всю ширину
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: EdgeInsets.symmetric(horizontal: center ? 4 : 14, vertical: 8),
              alignment: center ? Alignment.center : null,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.8, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: Color.lerp(pal.text, pal.onAccent, v))),
            ),
          ),
        ),
      );
}

/// .cp-step: квадрат 44×44 со значком 18 (small — 34×34, скругление 10); выключенный — прозрачность 0,4
class _Step extends StatelessWidget {
  const _Step({required this.pal, required this.icon, required this.tip, required this.onTap, this.size = 44, this.radius = 12, this.iconSize = 18});
  final Palette pal;
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final double size, radius, iconSize;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: pal.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: pal.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Tooltip(message: tip, child: SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: pal.text)))),
        ),
      );
}

const _scopeIcons = {
  'all': LucideIcons.bookOpen,
  'ot': LucideIcons.scroll,
  'ps': LucideIcons.music,
  'own': LucideIcons.listChecks,
};

// Новый Завет — книга с крестом (рядом со свитком Ветхого Завета);
// Евангелия — латинский крест: жизнь, смерть и воскресение Христа
Widget _scopeIcon(String id, double size, Color color) => id == 'nt' || id == 'gospels'
    ? CustomPaint(size: Size.square(size), painter: _LineIcon(id, color))
    : Icon(_scopeIcons[id] ?? LucideIcons.bookOpen, size: size, color: color);

/// Свои значки в манере Lucide: сетка 24, линия 2, скруглённые концы и углы
class _LineIcon extends CustomPainter {
  _LineIcon(this.id, this.color);
  final String id;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (id == 'nt') {
      // книга с крестом на обложке (рядом со свитком Ветхого Завета — христианское Писание)
      canvas.drawPath(
        Path()
          ..moveTo(4, 19.5)
          ..lineTo(4, 4.5)
          ..arcToPoint(const Offset(6.5, 2), radius: const Radius.circular(2.5))
          ..lineTo(19, 2)
          ..arcToPoint(const Offset(20, 3), radius: const Radius.circular(1))
          ..lineTo(20, 21)
          ..arcToPoint(const Offset(19, 22), radius: const Radius.circular(1))
          ..lineTo(6.5, 22)
          ..arcToPoint(const Offset(6.5, 17), radius: const Radius.circular(2.5))
          ..lineTo(20, 17),
        p,
      );
      canvas.drawLine(const Offset(12, 6), const Offset(12, 13), p);
      canvas.drawLine(const Offset(9.5, 8.5), const Offset(14.5, 8.5), p);
    } else {
      // латинский крест контуром (с объёмом, как соседние значки): длинный нижний конец
      canvas.drawPath(
        Path()..addPolygon(const [
          Offset(10, 2), Offset(14, 2), Offset(14, 7), Offset(19, 7), Offset(19, 11), Offset(14, 11), //
          Offset(14, 22), Offset(10, 22), Offset(10, 11), Offset(5, 11), Offset(5, 7), Offset(10, 7),
        ], true),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_LineIcon old) => old.color != color || old.id != id;
}

/// Очень лёгкая обводка плашек на подложке карточки
Color plateEdge(Palette pal) => mix(pal.text, 0.09, pal.panel);

/// Дата окончания плана из N дней, начатого сегодня: «24 января» (другой год — с годом)
String planEndText(int days) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day + (days < 1 ? 1 : days) - 1);
  final tpl = monthDayTemplates[currentLang];
  final s = tpl == null ? fmtDay(end, full: true) : tpl[end.month - 1].replaceFirst('{d}', '${end.day}');
  return end.year != now.year ? '$s ${end.year}' : s;
}

/// Нагрузка: «≈ 13 гл. в день · до 24 января»; больше часа чтения в день (~8 с на стих) — цветом предупреждения
class _LoadLine extends StatelessWidget {
  const _LoadLine({required this.pal, required this.books, required this.days});
  final Palette pal;
  final List<String> books;
  final int days;
  @override
  Widget build(BuildContext context) {
    final ch = chapterList(books);
    if (ch.isEmpty || days <= 0) return const SizedBox.shrink();
    final d = math.min(days, ch.length); // глав меньше, чем дней, — дней столько, сколько глав
    final verses = ch.fold<int>(0, (a, c) => a + c.n);
    final per = (ch.length / d).round().clamp(1, 1 << 20);
    final minutes = (verses / d * 8 / 60).round().clamp(1, 1 << 20); // ~8 секунд на стих
    final heavy = minutes > 60;
    // по центру, под капсулой с числом дней
    return Text(
      '≈ ${t('{n} гл. в день', {'n': '$per'})} · ${t('до {date}', {'date': planEndText(d)})}',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13.1, height: 1.35, fontWeight: FontWeight.w600, color: heavy ? dangerOf(pal) : pal.muted),
    );
  }
}

/// Число дней: одна капсула «− | 90 дней | +» — кнопки по краям, тонкие разделители, посередине крупное
/// число (его можно вписать) и подпись в нужной форме
class _DaysStepper extends StatelessWidget {
  const _DaysStepper({required this.pal, required this.days, required this.ctl, required this.set, required this.changed});
  final Palette pal;
  final int days;
  final TextEditingController ctl;
  final void Function(int) set;
  final void Function(String) changed;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: onTap == null ? 0.35 : 1, child: Icon(icon, size: 20, color: pal.accent)),
            ),
          ),
        );
    final divider = Container(width: 1, height: 28, color: pal.line);
    return Container(
      height: 56,
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: plateEdge(pal))),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(children: [
          btn(LucideIcons.minus, t('Уменьшить'), days <= 1 ? null : () => set(days - 1)),
          divider,
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                cursorColor: pal.accent,
                style: TextStyle(fontSize: 20, height: 1.1, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()]),
                decoration: const InputDecoration.collapsed(hintText: ''),
                onChanged: changed,
                onSubmitted: (_) => set(int.tryParse(ctl.text) ?? 90),
              ),
              const SizedBox(height: 1),
              Text(tn('день|дня|дней', days), style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w600, color: pal.muted)),
            ]),
          ),
          divider,
          btn(LucideIcons.plus, t('Увеличить'), () => set(days + 1)),
        ]),
      ),
    );
  }
}

/// Готовый план — вертикальная обложка с фотографией и названием (.plan-tile)
class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.pal, required this.m, required this.on, required this.onPick});
  final Palette pal;
  final PlanMeta m;
  final bool on;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l = _look(m.id);
    final c1 = l.c1 ?? pal.accent, c2 = l.c2 ?? mix(pal.accent, 0.6, Colors.white);
    return GestureDetector(
      onTap: onPick,
      child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
        // тень — у рамки, а градиент — слоем под фото внутри одной обрезки: иначе по скруглённому краю видна кайма
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(fit: StackFit.expand, children: [
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]))),
            SiteImage(_coverPath(m.id)),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(0, -0.2), end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB8000000)]))),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0x73000000), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(l.icon, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(t('{n} дн.', {'n': '${m.days}'}), style: const TextStyle(color: Colors.white, fontSize: 11.8, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(t(m.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.3, height: 1.2, shadows: [Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))])),
            ),
          ]),
          ),
        ),
        // outline: 3px solid accent; outline-offset: 2px
        if (on) Positioned(left: -5, top: -5, right: -5, bottom: -5, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(23), border: Border.all(color: pal.accent, width: 3))))),
      ]),
    );
  }
}

class _ActivePlan extends StatefulWidget {
  const _ActivePlan({super.key, required this.pal, required this.plan, required this.onRead, required this.onChange, required this.onRemove});
  final Palette pal;
  final Plan plan;
  final void Function(Plan plan, int day, int at) onRead;
  final void Function(Plan) onChange;
  final VoidCallback onRemove;

  @override
  State<_ActivePlan> createState() => _ActivePlanState();
}

class _ActivePlanState extends State<_ActivePlan> {
  late int _day;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    final n = readingsOf(p).length;
    // Показываем день, с которого читать: прочитали вперёд — первый непрочитанный после сегодняшнего
    var d = planToday(p);
    while (d < n - 1 && dayDone(p, d)) {
      d++;
    }
    _day = d;
  }

  void _toggle(int i) {
    final p = widget.plan;
    final done = Map<String, dynamic>.from((p['done'] as Map?) ?? const {});
    final parts = Map<String, dynamic>.from((p['parts'] as Map?) ?? const {});
    if (done['$i'] != null) {
      done.remove('$i');
      parts.remove('$i'); // снимаем и отметки отрывков — иначе день уже не закроется сам
    } else {
      done['$i'] = DateTime.now().millisecondsSinceEpoch;
    }
    widget.onChange({...p, 'done': done, 'parts': parts});
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final p = widget.plan;
    final all = readingsOf(p);
    final total = all.length;
    // Повреждённый план без дней (из старой копии данных) — только название и «удалить», иначе clamp(0, -1) роняет окно
    if (total == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: pal.bg),
        child: Row(children: [
          Expanded(child: Text(t('${p['name']}'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
          ConfirmIcon(icon: LucideIcons.trash2, size: 15, confirmText: t('Удалить'), tooltip: t('Удалить план'), onConfirm: widget.onRemove),
        ]),
      );
    }
    final today = planToday(p);
    final day = _day.clamp(0, total - 1);
    final doneCount = ((p['done'] as Map?) ?? const {}).length;
    final behind = behindDays(p);
    final rs = all[day];
    final flags = [for (final r in rs) readingDone(p, day, r)];
    final partDone = flags.where((f) => f).length;
    final isDone = dayDone(p, day);
    final firstLeft = flags.indexWhere((f) => !f);
    final l = _look('${p['planId']}');
    final cv = l.c1 ?? pal.accent;
    final pct = total == 0 ? 0.0 : doneCount / total;
    // .plan-card: колонка с промежутком 8, отступы 12/14; баннер вылезает за отступы (margin -12 -14 4)
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: pal.bg),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 84, child: SiteImage(_coverPath('${p['planId']}'), fallback: Container(color: cv.withValues(alpha: 0.3)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Ring(value: pct, size: 48, stroke: 5, color: cv, track: pal.muted.withValues(alpha: 0.18), child: Text('${(pct * 100).round()}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.05, color: pal.text))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('${p['name']}'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                  const SizedBox(height: 2),
                  Text(t('{done} из {total} дн.', {'done': '$doneCount', 'total': '$total'}), style: TextStyle(fontSize: 13.1, color: pal.muted)),
                ]),
              ),
              ConfirmIcon(icon: LucideIcons.trash2, size: 15, confirmText: t('Удалить'), tooltip: t('Удалить план'), onConfirm: widget.onRemove),
            ]),
            if (behind.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(t('Пропущено дней: {n}', {'n': '${behind.length}'}), style: const TextStyle(fontSize: 13.1, color: Color(0xFFB5642A))),
                  if (day != behind.first) GestureDetector(onTap: () => setState(() => _day = behind.first), child: Text(t('к первому пропущенному'), style: TextStyle(fontSize: 13.1, color: pal.accent, decoration: TextDecoration.underline, decorationColor: pal.accent))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                IconBtn(icon: LucideIcons.chevronLeft, subtle: true, size: 18, tooltip: t('Предыдущий день'), onTap: day == 0 ? null : () => setState(() => _day = day - 1)),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(children: [
                    Text('${t('День {n}', {'n': '${day + 1}'})}${day == today ? ' · ${t('сегодня')}' : ''}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, fontWeight: FontWeight.w600, color: pal.text)),
                    Text(isDone ? t('прочитано') : t('{done} из {total} отрывков', {'done': '$partDone', 'total': '${rs.length}'}), style: TextStyle(fontSize: 12.2, color: pal.muted)),
                  ]),
                ),
                const SizedBox(width: 4),
                IconBtn(icon: LucideIcons.chevronRight, subtle: true, size: 18, tooltip: t('Следующий день'), onTap: day >= total - 1 ? null : () => setState(() => _day = day + 1)),
                const SizedBox(width: 4),
                Tooltip(
                  message: isDone ? t('Снять отметку дня') : t('Отметить весь день прочитанным'),
                  child: AobButton(small: true, kind: isDone ? BtnKind.primary : BtnKind.normal, icon: LucideIcons.check, label: isDone ? t('Прочитано') : t('Отметить'), onTap: () => _toggle(day)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (i, r) in rs.indexed) ChipBtn(label: readingLabel(r), done: flags[i], onTap: () => widget.onRead(p, day, i)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AobButton(
                wide: true,
                kind: isDone ? BtnKind.normal : BtnKind.primary,
                icon: LucideIcons.bookOpen,
                label: isDone ? t('Перечитать') : partDone > 0 ? t('Продолжить чтение') : t('Читать'),
                onTap: () => widget.onRead(p, day, isDone || firstLeft < 0 ? 0 : firstLeft),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Напоминания о чтении (.reminder-card): сколько угодно — каждое в своё время или промежутком (с … до … каждые N мин/ч),
/// в выбранные дни недели; уведомление — что читать сегодня
class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.pal});
  final Palette pal;
  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> with WidgetsBindingObserver {
  Reminder _r = getReminder();
  bool _exact = true; // разрешено ли «Будильники и напоминания»

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // проверяем и после возврата из настроек телефона
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await exactAllowed();
    if (!mounted) return;
    if (ok && !_exact) scheduleReminders(); // разрешили — расписание заново, уже точное
    setState(() => _exact = ok);
  }

  Future<void> _apply({bool? on, List<ReminderItem>? list}) async {
    final ok = await setReminder(on: on, list: list);
    if (!mounted) return;
    if (!ok) return toast(context, t('Уведомления запрещены — разрешите их в настройках телефона'));
    setState(() => _r = getReminder());
    if (on == true) toast(context, _r.list.length == 1 && _r.list.first.every == 0 ? t('Напомню в {time}', {'time': _r.time}) : t('Напоминания включены'));
  }

  void _set(ReminderItem x) => _apply(list: [for (final y in _r.list) y.id == x.id ? x : y]);

  // новое — через час после последнего
  void _add() {
    final last = _r.list.isEmpty ? null : _r.list.last;
    final p = (last == null ? '07:00' : last.every > 0 ? last.until : last.time).split(':').map((s) => int.tryParse(s) ?? 0).toList();
    final h = (p[0] + (last == null ? 0 : 1)).clamp(0, 23);
    _apply(list: [..._r.list, ReminderItem.fresh('${'$h'.padLeft(2, '0')}:${'${p.length > 1 ? p[1] : 0}'.padLeft(2, '0')}')]);
  }

  Future<void> _pickTime(String cur, ValueChanged<String> done) async {
    final p = cur.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    final got = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p[0], minute: p.length > 1 ? p[1] : 0),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    if (got != null) done('${got.hour.toString().padLeft(2, '0')}:${got.minute.toString().padLeft(2, '0')}');
  }

  // .rem-line input[type=time]
  Widget _timeBtn(String value, String tip, ValueChanged<String> done) {
    final pal = widget.pal;
    return Tooltip(
      message: tip,
      child: Material(
        color: pal.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: pal.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pickTime(value, done),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(value, style: TextStyle(fontSize: 15, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              Icon(LucideIcons.clock, size: 15, color: pal.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _item(ReminderItem x) {
    final pal = widget.pal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _timeBtn(x.time, x.every > 0 ? t('С') : t('Время'), (v) => _set(x.copyWith(time: v))),
          // промежуток: «с 8:00 до 20:00 каждые 2 ч»
          if (x.every > 0) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: pal.muted))),
            _timeBtn(x.until, t('До'), (v) => _set(x.copyWith(until: v))),
          ],
          const Spacer(),
          if (_r.list.length > 1) IconBtn(icon: LucideIcons.x, size: 17, tooltip: t('Удалить напоминание'), onTap: () => _apply(list: [for (final y in _r.list) if (y.id != x.id) y])),
        ]),
        const SizedBox(height: 8),
        // повтор — по ширине подписи
        PopupMenuButton<int>(
          tooltip: t('Повтор'),
          initialValue: x.every,
          onSelected: (n) => _set(x.copyWith(every: n)),
          itemBuilder: (_) => [for (final n in reminderRepeats) PopupMenuItem(value: n, child: Text(repeatLabel(n)))],
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(repeatLabel(x.every), style: TextStyle(fontSize: 14.4, color: pal.text)),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronDown, size: 16, color: pal.muted),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // дни недели ровным рядом: ничего не выбрано — каждый день
        Semantics(
          label: t('Дни недели'),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var d = 1; d <= 7; d++)
              Builder(builder: (_) {
                final on = x.days.isEmpty || x.days.contains(d);
                return GestureDetector(
                  onTap: () {
                    final cur = x.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : x.days;
                    final days = on ? [for (final y in cur) if (y != d) y] : ([...cur, d]..sort());
                    if (days.isNotEmpty) _set(x.copyWith(days: days.length == 7 ? const [] : days));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: on ? pal.accent : Colors.transparent, border: Border.all(color: on ? pal.accent : pal.line)),
                    child: Text(weekdayLetter(d).toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? pal.onAccent : pal.muted)),
                  ),
                );
              }),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: cardFill(pal)),
      child: Column(children: [
        // .switch-field: подпись с «!» (пояснение по нажатию) и переключатель, отступ 2
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _apply(on: !_r.on),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: t('Напоминать о чтении')),
                  const WidgetSpan(child: SizedBox(width: 2)),
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: HintBtn(t('Уведомление с отрывками на сегодня — сколько угодно напоминаний, в любое время или промежутком'))),
                ]), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text)),
              ),
              const SizedBox(width: 12),
              AobSwitch(value: _r.on, onChanged: (v) => _apply(on: v)),
            ]),
          ),
        ),
        // список — под включённым переключателем, раскрывается плавно
        Reveal(
          open: _r.on,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // .rem-exact: без «Будильники и напоминания» Android откладывает уведомления
              if (!_exact)
                Container(
                  margin: const EdgeInsets.only(top: 2, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: mix(pal.accent, 0.12, pal.panel), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(child: Text(t('Чтобы напоминания приходили вовремя, разрешите приложению «Будильники и напоминания».'), style: TextStyle(fontSize: 14.4, height: 1.4, color: pal.text))),
                    const SizedBox(width: 10),
                    AobButton(label: t('Разрешить'), small: true, kind: BtnKind.primary, onTap: () => askExact().then((_) => _check())),
                  ]),
                ),
              // .rem-tip
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t('Не приходят уведомления? На Xiaomi, Huawei и других телефонах разрешите приложению автозапуск и работу в фоне без ограничений.'), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted)),
              ),
              for (final x in _r.list) _item(x),
              const SizedBox(height: 2),
              // .rem-add
              Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.line)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _add,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.plus, size: 16, color: pal.accent),
                      const SizedBox(width: 6),
                      Text(t('Добавить напоминание'), style: TextStyle(fontSize: 14.7, fontWeight: FontWeight.w600, color: pal.accent)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Сколько прочитано — по дочитанным до конца главам: кольцо «доля Библии», серия дней, столбики за неделю (.read-hero)
class _ReadHero extends StatefulWidget {
  const _ReadHero({required this.pal, required this.open});
  final Palette pal;
  final void Function(String key) open;
  @override
  State<_ReadHero> createState() => _ReadHeroState();
}

class _ReadHeroState extends State<_ReadHero> {
  bool _more = false;
  late final ReadStats _st = readStats();

  String _chLabel(String key) {
    final c = key.split('.');
    return '${Books.instance.meta(c[0]).short.replaceFirst(RegExp(r'\.$'), '')} ${c.length > 1 ? c[1] : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final st = _st;
    final maxN = math.max(1, st.days7.fold<int>(0, (a, d) => math.max(a, d.n)));
    final pct = st.total / _bibleChapters * 100;
    final streakOn = st.streak > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius + 6),
        // чистая нейтральная подложка (смесь с коричневым акцентом выглядела грязной)
        border: Border.all(color: pal.line),
        color: mix(pal.text, 0.04, pal.panel),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Ring(
            value: st.total / _bibleChapters,
            size: 84,
            stroke: 8,
            color: pal.accent,
            track: pal.muted.withValues(alpha: 0.18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${pct > 0 && pct < 1 ? '<1' : pct.round()}%', style: TextStyle(fontSize: 18.4, fontWeight: FontWeight.w700, height: 1.05, color: pal.text)),
              Text(t('Библии'), style: TextStyle(fontSize: 10.9, fontWeight: FontWeight.w500, height: 1.05, color: pal.muted)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(LucideIcons.flame, size: 18, color: streakOn ? const Color(0xFFF07C22) : pal.muted),
                const SizedBox(width: 6),
                Text('${st.streak}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: pal.text)),
                const SizedBox(width: 6),
                Flexible(child: Text(tx('день подряд|дня подряд|дней подряд', {'n': st.streak}), style: TextStyle(fontSize: 16, color: pal.muted))),
              ]),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${t('Сегодня: {n} гл.', {'n': '${st.today}'})} · ${t('Глав Библии: {n} из {total}', {'n': '${st.total}', 'total': '$_bibleChapters'})} '),
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: HintBtn(t('Глава засчитывается, когда дочитана до конца — по плану или просто так. Столбики — главы за каждый день, с повторами; «Глав Библии» — сколько разных глав прочитано хоть раз.'))),
                ]),
                style: TextStyle(fontSize: 13.1, color: pal.muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Semantics(
          label: t('За 7 дней: {n} гл.', {'n': '${st.week}'}),
          child: SizedBox(
            height: 76,
            child: Row(children: [
              for (final d in st.days7)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Expanded(
                        child: LayoutBuilder(builder: (_, c) {
                          final f = d.n > 0 ? math.max(0.12, d.n / maxN) : 0.04;
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: math.min(26, c.maxWidth),
                              height: c.maxHeight * f,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: d.n > 0 ? null : pal.muted.withValues(alpha: 0.22),
                                gradient: d.n > 0 ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [mix(pal.accent, 0.65, Colors.white), pal.accent]) : null,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Text(weekdayLetter(DateTime.parse('${d.day}T12:00:00').weekday), style: TextStyle(fontSize: 12.2, color: pal.muted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        if (st.recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in st.recent.take(_more ? 30 : 3)) ChipBtn(label: _chLabel(x.key), sub: fmtDay(DateTime.parse('${x.day}T12:00:00')), onTap: () => widget.open(x.key)),
            if (st.recent.length > 3 && !_more) ChipBtn(label: t('ещё…'), onTap: () => setState(() => _more = true)),
          ]),
        ],
      ]),
    );
  }
}

/// .cp-stream: строка раздела — галочка, название и «− N гл. в день +»
class _StreamRow extends StatelessWidget {
  const _StreamRow({required this.pal, required this.label, required this.per, required this.onToggle, required this.onPer, this.steps = true});
  final Palette pal;
  final String label;
  final bool steps; // false («За срок») — шаги «− n гл. в день +» скрыты, галочка остаётся
  final int? per; // null — раздел выключен
  final VoidCallback onToggle;
  final void Function(int delta) onPer;

  @override
  Widget build(BuildContext context) {
    final on = per != null;
    const dur = Duration(milliseconds: 240);
    // включение раздела — плавно: рамка и фон перетекают, галочка проявляется, шаги «− n гл. в день +» выезжают
    return AnimatedContainer(
      duration: dur,
      curve: Curves.fastOutSlowIn,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? mix(pal.accent, 0.55, pal.line) : plateEdge(pal)), // у выключенных — очень лёгкая обводка
        color: on ? mix(pal.accent, 0.07, pal.panel) : pal.panel,
      ),
      child: Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                AnimatedContainer(
                  duration: dur,
                  curve: Curves.fastOutSlowIn,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: on ? pal.accent : pal.accent.withValues(alpha: 0), border: Border.all(color: on ? pal.accent : mix(pal.muted, 0.6, Colors.transparent), width: 1.5)),
                  child: AnimatedOpacity(
                    duration: dur,
                    opacity: on ? 1 : 0,
                    child: AnimatedScale(duration: dur, curve: Curves.fastOutSlowIn, scale: on ? 1 : 0.6, child: Icon(LucideIcons.check, size: 14, color: pal.onAccent)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: TextStyle(fontSize: 15.2, fontWeight: FontWeight.w600, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: pal.text))),
              ]),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: dur,
          switchInCurve: Curves.fastOutSlowIn,
          switchOutCurve: Curves.fastOutSlowIn,
          // выезжают справа: ширина от 0 и прозрачность
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ClipRect(child: AnimatedBuilder(animation: a, child: child, builder: (_, c) => Align(alignment: Alignment.centerRight, widthFactor: a.value, child: c))),
          ),
          child: on && steps
              ? Row(key: const ValueKey('steps'), mainAxisSize: MainAxisSize.min, children: [
                  _Step(pal: pal, icon: LucideIcons.minus, tip: t('Уменьшить'), size: 34, radius: 10, iconSize: 16, onTap: per! <= 1 ? null : () => onPer(-1)),
                  const SizedBox(width: 6),
                  Text(t('{n} гл. в день', {'n': '$per'}), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(width: 6),
                  _Step(pal: pal, icon: LucideIcons.plus, tip: t('Увеличить'), size: 34, radius: 10, iconSize: 16, onTap: per! >= 10 ? null : () => onPer(1)),
                ])
              : const SizedBox(key: ValueKey('no-steps'), height: 34),
        ),
      ]),
    );
  }
}

/// Свои книги для плана: сетка коротких названий по Заветам, нажатие — выбрать или убрать (.cp-books)
class _BookPicker extends StatelessWidget {
  const _BookPicker({required this.pal, required this.value, required this.onToggle});
  final Palette pal;
  final List<String> value;
  final void Function(String id) onToggle;

  @override
  Widget build(BuildContext context) {
    final inPlan = planBookIds(); // неканонические — только если они есть в переводе плана
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, g) in [('OT', 'Ветхий Завет'), ('NT', 'Новый Завет')].indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t(g.$2), style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: pal.muted))),
          LayoutBuilder(builder: (_, c) {
            // repeat(auto-fill, minmax(54px, 1fr)), промежуток 6
            final cols = math.max(1, ((c.maxWidth + 6) / 60).floor());
            final w = (c.maxWidth - 6 * (cols - 1)) / cols;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in Books.instance.all.where((b) => b.testament == g.$1 && (inPlan.isEmpty || inPlan.contains(b.id))))
                SizedBox(
                  width: w,
                  child: Tooltip(
                    message: Books.instance.meta(b.id).name,
                    child: Material(
                      color: value.contains(b.id) ? pal.accent : pal.panel,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: value.contains(b.id) ? pal.accent : plateEdge(pal))),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onToggle(b.id),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 38),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                          alignment: Alignment.center,
                          child: Text(Books.instance.meta(b.id).short.replaceFirst(RegExp(r'\.$'), ''), maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: TextAlign.center,
                              // запас строки — поровну сверху и снизу: название ровно по середине плашки
                              style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: value.contains(b.id) ? pal.onAccent : pal.text)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ],
        if (value.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(t('Выбрано книг: {n}', {'n': '${value.length}'}), style: TextStyle(fontSize: 13.1, color: pal.muted))),
      ]);
  }
}
