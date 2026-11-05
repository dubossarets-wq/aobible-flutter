// Планы чтения (PlansSheet.jsx): «Стих дня», активные планы с кольцом прогресса и кнопкой «Читать», напоминание,
// сколько прочитано (кольцо «доля Библии», дни подряд, неделя), готовые планы с обложками и свой план.
// Размеры и цвета — по styles.css (.plan-card, .read-hero, .plan-tile, .custom-plan…).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPicker;
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

// Обложки планов: фото (из фонов для картинок со стихом), значок и цвет; свой план и неизвестные — по умолчанию.
// Значок — тот же, что у раздела в «Своём плане» (что читаем): вся Библия, Новый Завет, Евангелия, Псалмы
class _Look {
  const _Look(this.scope, this.c1, this.c2, this.photo);
  final String? scope; // null — «искры» (план без раздела)
  final Color? c1, c2; // null — цвет темы
  final String photo;
}

const _looks = <String, _Look>{
  'mcheyne': _Look('all', Color(0xFF7B61D6), Color(0xFFA98BF0), '10'),
  'bible-year': _Look('all', Color(0xFF2F7FC8), Color(0xFF5BB7E8), '06'),
  'nt-90': _Look('nt', Color(0xFFE07A2F), Color(0xFFF3B75C), '01'),
  'ps-prov-31': _Look('ps', Color(0xFF26936F), Color(0xFF5FC99C), '07'),
  'gospels-30': _Look('gospels', Color(0xFFC2477A), Color(0xFFEC85A8), '02'),
};
const _defaultLook = _Look(null, null, null, '08');
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
  final _newKey = GlobalKey(); // метка перед карточкой только что начатого плана
  final _list = ScrollController();
  String? _newUid;
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
    _list.dispose();
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
    final uid = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    // новый план — первым в списке: прокручиваем окно, чтобы его карточка встала вверху
    setState(() => _newUid = uid);
    // список строится только около видимой части: из сетки планов внизу карточка нового плана наверху ещё
    // не построена — тогда сначала едем к началу окна, а там встаём ровно на неё
    void show() {
      final c = _newKey.currentContext;
      if (!mounted) return;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      } else if (_list.hasClients) {
        _list.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic).then((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
              final c = _newKey.currentContext;
              if (mounted && c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
            }));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => show());
    ref.read(plansProvider.notifier).add({
      ...plan,
      'uid': uid,
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
      child: Builder(builder: (bc) => ListView(controller: _list, padding: padTabs(bc, const EdgeInsets.fromLTRB(16, 12, 16, 20)), children: [
        VerseOfDayCard(pane: widget.pane, onRead: _go),
        gap,
        for (final p in plans) ...[
          if (p['uid'] == _newUid) SizedBox(key: _newKey, height: 0),
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
        // настройка видна везде (и на компьютере — её можно задать заранее); уведомления приходят только на телефоне
        if (plans.isNotEmpty) ...[_ReminderCard(pal: pal), gap],
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
        // «Ещё планы» — карточкой-списком (.plan-rows): строка — фото-миниатюра со значком раздела, название, о чём
        // план и сколько дней; нажатие раскрывает строку на месте: описание, «до …» и «Начать»
        if (_index != null)
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: cardFill(pal)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, m) in _index!.indexed)
                _PlanRow(
                  pal: pal,
                  m: m,
                  first: i == 0,
                  open: _pick == m.id,
                  running: plans.any((p) => p['planId'] == m.id),
                  busy: _busy,
                  onToggle: () => setState(() => _pick = _pick == m.id ? null : m.id),
                  onStart: () => _start(m),
                ),
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

/// Готовый план — строкой (.plan-row): фото-миниатюра со значком раздела, название, о чём план, сколько дней
/// (идёт — помечен); нажатие раскрывает строку на месте: описание, до какого числа (если начать сегодня) и «Начать»
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.pal, required this.m, required this.first, required this.open, required this.running, required this.busy, required this.onToggle, required this.onStart});
  final Palette pal;
  final PlanMeta m;
  final bool first, open, running;
  final String? busy;
  final VoidCallback onToggle, onStart;

  @override
  Widget build(BuildContext context) {
    final l = _look(m.id);
    final c1 = l.c1 ?? pal.accent, c2 = l.c2 ?? mix(pal.accent, 0.6, Colors.white);
    final ok = okOf(pal);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(color: open ? pal.panel : Colors.transparent, border: first ? null : Border(top: BorderSide(color: pal.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                // миниатюра: градиент цвета плана, фото, лёгкое затемнение и значок раздела
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 4))]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(fit: StackFit.expand, children: [
                      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]))),
                      SiteImage(_coverPath(m.id)),
                      const ColoredBox(color: Color(0x47000000)),
                      Center(child: l.scope == null ? const Icon(LucideIcons.sparkles, size: 18, color: Colors.white) : _scopeIcon(l.scope!, 18, Colors.white)),
                    ]),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(m.name), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25, color: pal.text)),
                    if (m.short != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(t(m.short!), style: TextStyle(fontSize: 13.4, height: 1.3, color: pal.muted))),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(t('{n} дн.', {'n': '${m.days}'}), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                      if (running) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(color: ok.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                          child: Text(t('идёт'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ok)),
                        ),
                      ],
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 220), child: Icon(LucideIcons.chevronDown, size: 18, color: pal.muted)),
              ]),
            ),
          ),
        ),
        Reveal(
          open: open,
          child: Padding(
            // описание и «Начать» — на всю ширину карточки (от края миниатюры)
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (m.description != null) Text(t(m.description!), style: TextStyle(color: pal.muted, fontSize: 13.8, height: 1.45)),
              const SizedBox(height: 10),
              Text(t('до {date}', {'date': planEndText(m.days)}), style: TextStyle(fontSize: 13.1, fontWeight: FontWeight.w600, color: pal.text)),
              const SizedBox(height: 10),
              busy == m.id ? BusyButton(label: t('Начать')) : AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.plus, label: t('Начать'), onTap: busy != null ? null : onStart),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Отрывок с полным названием книги: «От Матфея 5», «Псалтирь 9:1–21»
String _fullLabel(String r) {
  final p = r.split('.');
  final name = Books.instance.meta(p[0]).name;
  if (p.length > 2 && p[2].isNotEmpty) return '$name ${p[1]}:${p[2].replaceAll('-', '–')}';
  return '$name ${(p.length > 1 && p[1].isNotEmpty ? p[1] : '1').replaceAll('-', '–')}';
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
  int? _openDay; // день, у которого раскрыты все отрывки (больше пяти)
  static const _partsMax = 5; // отрывков дня в списке — не больше пяти, остальные — за строкой «Ещё N»

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

  /// Кружок дня в ленте (.pd): прочитанный — как обычный, только приглушён; пропущенный — оранжевый, сегодняшний —
  /// в кольце акцента, выбранный — тёмный
  Widget _dayDot(Palette pal, Plan p, int i, int day, int today, List<int> behind) {
    final done = dayDone(p, i), on = i == day, missed = behind.contains(i);
    final late = lateOf(pal);
    final fg = on ? pal.panel : missed ? late : pal.text;
    final fill = on ? pal.text : missed ? mix(late, 0.13, pal.panel) : pal.panel;
    final ring = on || missed ? null : i == today ? Border.all(color: pal.accent, width: 2) : Border.all(color: pal.line);
    return Semantics(
      button: true,
      selected: on,
      label: '${t('День {n}', {'n': '${i + 1}'})}${i == today ? ', ${t('сегодня')}' : ''}${done ? ', ${t('прочитано')}' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _day = i),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 40),
            child: AspectRatio(
              aspectRatio: 1,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: done && !on ? 0.42 : 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: ring),
                  child: Text('${i + 1}', style: TextStyle(fontSize: 13.4, fontWeight: FontWeight.w600, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Кружок у отрывка: отметить прочитанным или снять отметку. Отмечены все отрывки — день закрывается сам;
  /// сняли отметку в закрытом дне — день открывается, остальные отрывки остаются отмеченными
  void _togglePart(int day, int i) {
    final p = widget.plan;
    final rs = readingsOf(p)[day];
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = [for (final u in readingUnits(rs[i])) u.key];
    final all = [for (final r in rs) for (final u in readingUnits(r)) u.key];
    final done = Map<String, dynamic>.from((p['done'] as Map?) ?? const {});
    final parts = Map<String, dynamic>.from((p['parts'] as Map?) ?? const {});
    final have = dayDone(p, day) ? {for (final k in all) k: done['$day']} : Map<String, dynamic>.from((parts['$day'] as Map?) ?? const {});
    if (readingDone(p, day, rs[i])) {
      for (final k in keys) {
        have.remove(k);
      }
    } else {
      for (final k in keys) {
        have[k] = now;
      }
    }
    if (all.every(have.containsKey)) {
      done['$day'] ??= now;
    } else {
      done.remove('$day');
    }
    parts['$day'] = have;
    widget.onChange({...p, 'done': done, 'parts': parts});
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
        // без своего нижнего отступа: промежуток между блоками окна — общий, 12
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
    // .plan-card: обложка-фото с названием и прогрессом поверх, под ней тонкая полоса прогресса; ниже — день
    // со стрелками, отрывки дня и две кнопки рядом: «Читать» (главная) и «Отметить»
    return Container(
      // без своего нижнего отступа: промежуток между блоками окна — общий, 12
      // фон — как у остальных блоков окна
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: cardFill(pal)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 104,
          child: Stack(fit: StackFit.expand, children: [
            SiteImage(_coverPath('${p['planId']}'), fallback: Container(color: cv.withValues(alpha: 0.3))),
            // затемнение к низу — белые надписи читаются на любом фото
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xA6000000)], stops: [0.25, 1]))),
            Positioned(
              left: 14,
              right: 52,
              bottom: 10,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('${p['name']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2, color: Colors.white, shadows: [Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))])),
                const SizedBox(height: 2),
                Text('${t('{done} из {total} дн.', {'done': '$doneCount', 'total': '$total'})} · ${(pct * 100).round()}%', style: const TextStyle(fontSize: 13.1, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF))),
              ]),
            ),
            // «удалить» — светлой «таблеткой» в углу обложки
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(color: pal.panel.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(999)),
                child: ConfirmIcon(icon: LucideIcons.trash2, size: 15, confirmText: t('Удалить'), tooltip: t('Удалить план'), onConfirm: widget.onRemove),
              ),
            ),
          ]),
        ),
        // полоса прогресса плана
        SizedBox(
          height: 4,
          child: Stack(children: [
            Container(color: pal.muted.withValues(alpha: 0.16)),
            FractionallySizedBox(widthFactor: pct.clamp(0.0, 1.0), child: Container(color: cv)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // лента дней вокруг выбранного: прочитанный — с галочкой, пропущенный — оранжевый, сегодняшний — в кольце
            Semantics(
              label: t('Дни плана'),
              child: Row(children: [
                IconBtn(icon: LucideIcons.chevronLeft, subtle: true, size: 18, tooltip: t('Предыдущий день'), onTap: day == 0 ? null : () => setState(() => _day = day - 1)),
                for (var k = 0; k < math.min(7, total); k++)
                  Expanded(child: _dayDot(pal, p, math.max(0, math.min(day - 3, total - 7)) + k, day, today, behind)),
                IconBtn(icon: LucideIcons.chevronRight, subtle: true, size: 18, tooltip: t('Следующий день'), onTap: day >= total - 1 ? null : () => setState(() => _day = day + 1)),
              ]),
            ),
            const SizedBox(height: 12),
            // выбранный день: название слева, сколько прочитано — справа
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: t('День {n}', {'n': '${day + 1}'})),
                      if (day == today) TextSpan(text: ' · ${t('сегодня')}') else if (behind.contains(day)) TextSpan(text: ' · ${t('пропущен')}', style: TextStyle(color: lateOf(pal))),
                    ]),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text),
                  ),
                ),
                Text(isDone ? t('прочитано') : t('{done} из {total} отрывков', {'done': '$partDone', 'total': '${rs.length}'}), style: TextStyle(fontSize: 13.1, fontWeight: isDone ? FontWeight.w600 : FontWeight.w400, color: isDone ? okOf(pal) : pal.muted)),
              ]),
            ),
            // пропущенные дни — тихой строкой, а не плашкой: точка, сколько, справа «Догнать ›» (к первому пропущенному)
            if (behind.isNotEmpty && day != behind.first)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _day = behind.first),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: lateOf(pal))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t('Пропущено дней: {n}', {'n': '${behind.length}'}), style: TextStyle(fontSize: 13.4, color: pal.muted))),
                    Text(t('Догнать'), style: TextStyle(fontSize: 13.4, fontWeight: FontWeight.w600, color: pal.accent)),
                    Icon(LucideIcons.chevronRight, size: 15, color: pal.accent),
                  ]),
                ),
              ),
            SizedBox(height: behind.isNotEmpty && day != behind.first ? 4 : 10),
            // отрывки дня — белым списком с полными названиями (.plan-list): кружок — отметка «прочитано» (прочитанный
            // отрывок слегка приглушён), название — открыть отрывок; больше пяти — остальные за строкой «Ещё N»
            Container(
              decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, r) in rs.indexed)
                  if (i < _partsMax || rs.length <= _partsMax || _openDay == day)
                    Container(
                      decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: pal.line))),
                      child: Row(children: [
                        Semantics(
                          button: true,
                          checked: flags[i],
                          label: '${flags[i] ? t('Снять отметку') : t('Отметить прочитанным')}: ${_fullLabel(r)}',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: () => _togglePart(day, i),
                            child: SizedBox(
                              width: 48,
                              height: 46,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 22,
                                  height: 22,
                                  margin: const EdgeInsets.only(left: 4),
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: flags[i] ? okOf(pal) : Colors.transparent, border: flags[i] ? null : Border.all(color: pal.muted.withValues(alpha: 0.55), width: 1.5)),
                                  child: flags[i] ? Icon(LucideIcons.check, size: 13, color: pal.dark ? pal.panel : Colors.white) : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => widget.onRead(p, day, i),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: flags[i] ? 0.7 : 1,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 46),
                                padding: const EdgeInsets.fromLTRB(2, 8, 10, 8),
                                child: Row(children: [
                                  Expanded(child: Text(_fullLabel(r), style: TextStyle(fontSize: 15.2, fontWeight: flags[i] ? FontWeight.w500 : FontWeight.w600, color: flags[i] ? pal.muted : pal.text))),
                                  Icon(LucideIcons.chevronRight, size: 17, color: pal.muted),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                if (rs.length > _partsMax)
                  InkWell(
                    onTap: () => setState(() => _openDay = _openDay == day ? null : day),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_openDay == day ? t('Свернуть') : t('Ещё {n}', {'n': '${rs.length - _partsMax}'}), style: TextStyle(fontSize: 14.1, fontWeight: FontWeight.w600, color: pal.accent)),
                        const SizedBox(width: 4),
                        AnimatedRotation(turns: _openDay == day ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(LucideIcons.chevronDown, size: 16, color: pal.accent)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AobButton(
                  wide: true,
                  kind: isDone ? BtnKind.normal : BtnKind.primary,
                  icon: LucideIcons.bookOpen,
                  label: isDone ? t('Перечитать') : partDone > 0 ? t('Продолжить чтение') : t('Читать'),
                  onTap: () => widget.onRead(p, day, isDone || firstLeft < 0 ? 0 : firstLeft),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isDone ? t('Снять отметку дня') : t('Отметить весь день прочитанным'),
                child: AobButton(kind: isDone ? BtnKind.primary : BtnKind.normal, icon: LucideIcons.check, label: isDone ? t('Прочитано') : t('Отметить'), onTap: () => _toggle(day)),
              ),
            ]),
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
  String? _wheel; // открытые колёсики времени: «id:time» или «id:until» (одни на всё окно)
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
  // новое — через час после последнего; будильник (alarm) звонит громко, пока не выключат
  void _add({bool alarm = false}) {
    final last = _r.list.isEmpty ? null : _r.list.last;
    final p = (last == null ? '07:00' : last.every > 0 ? last.until : last.time).split(':').map((s) => int.tryParse(s) ?? 0).toList();
    final h = (p[0] + (last == null ? 0 : 1)).clamp(0, 23);
    _apply(list: [..._r.list, ReminderItem.fresh('${'$h'.padLeft(2, '0')}:${'${p.length > 1 ? p[1] : 0}'.padLeft(2, '0')}', alarm: alarm)]);
  }

  // время крупно, как в будильнике iPhone; нажатие — колёсики прямо в карточке (.rem-time)
  Widget _timeBtn(ReminderItem x, String k, String tip) {
    final pal = widget.pal;
    final on = _wheel == '${x.id}:$k';
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _wheel = on ? null : '${x.id}:$k'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w400, letterSpacing: -0.3, color: on ? pal.accent : pal.text, fontFeatures: const [FontFeature.tabularFigures()]),
            child: Text(k == 'until' ? x.until : x.time),
          ),
        ),
      ),
    );
  }

  Widget _item(ReminderItem x) {
    final pal = widget.pal;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _timeBtn(x, 'time', x.every > 0 ? t('С') : t('Время')),
          // промежуток: «с 8:00 до 20:00 каждые 2 ч»
          if (x.every > 0) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('–', style: TextStyle(color: pal.muted, fontSize: 24))),
            _timeBtn(x, 'until', t('До')),
          ],
          const SizedBox(width: 8),
          // напоминание или будильник — нажатие переключает
          Tooltip(
            message: x.alarm ? t('Будильник: звонит, пока не выключите') : t('Напоминание: тихое уведомление'),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _set(x.copyWith(alarm: !x.alarm)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: x.alarm ? mix(pal.accent, 0.15, pal.panel) : pal.text.withValues(alpha: 0.06)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(x.alarm ? LucideIcons.alarmClock : LucideIcons.bell, size: 14, color: x.alarm ? pal.accent : pal.muted),
                  const SizedBox(width: 4),
                  Text(x.alarm ? t('Будильник') : t('Напоминание'), style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: x.alarm ? pal.accent : pal.muted)),
                ]),
              ),
            ),
          ),
          const Spacer(),
          if (_r.list.length > 1) IconBtn(icon: LucideIcons.x, size: 17, tooltip: t('Удалить напоминание'), onTap: () => _apply(list: [for (final y in _r.list) if (y.id != x.id) y])),
        ]),
        for (final k in const ['time', 'until'])
          Reveal(
            open: _wheel == '${x.id}:$k',
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TimeWheel(key: ValueKey('${x.id}:$k'), pal: pal, value: k == 'until' ? x.until : x.time, onChanged: (v) => _set(k == 'until' ? x.copyWith(until: v) : x.copyWith(time: v))),
            ),
          ),
        const SizedBox(height: 10),
        // «Повтор» строкой: подпись слева, выбор справа (.rem-row)
        Container(
          padding: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
          child: PopupMenuButton<int>(
            tooltip: t('Повтор'),
            initialValue: x.every,
            onSelected: (n) => _set(x.copyWith(every: n)),
            itemBuilder: (_) => [for (final n in reminderRepeats) PopupMenuItem(value: n, child: Text(repeatLabel(n)))],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(children: [
                Text(t('Повтор'), style: TextStyle(fontSize: 15.2, color: pal.text)),
                const Spacer(),
                Text(repeatLabel(x.every), style: TextStyle(fontSize: 15.2, color: pal.muted)),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown, size: 16, color: pal.muted),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // дни недели «Пн Вт Ср…» таблетками: ничего не выбрано — каждый день
        Semantics(
          label: t('Дни недели'),
          child: Row(children: [
            for (var d = 1; d <= 7; d++) ...[
              if (d > 1) const SizedBox(width: 5),
              Expanded(
                child: Builder(builder: (_) {
                  final on = x.days.isEmpty || x.days.contains(d);
                  return GestureDetector(
                    onTap: () {
                      final cur = x.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : x.days;
                      final days = on ? [for (final y in cur) if (y != d) y] : ([...cur, d]..sort());
                      if (days.isNotEmpty) _set(x.copyWith(days: days.length == 7 ? const [] : days));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), color: on ? mix(pal.accent, 0.15, pal.panel) : pal.text.withValues(alpha: 0.06)),
                      child: Text(weekdayShort(d), maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 12.8, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? pal.accent : pal.muted)),
                    ),
                  );
                }),
              ),
            ],
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
                  // «Не приходят уведомления?» — тоже в пояснении за «!», а не текстом в блоке
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: HintBtn('${t('Уведомление с отрывками на сегодня — сколько угодно напоминаний, в любое время или промежутком')}\n\n${t('Не приходят уведомления?')} ${t('На Xiaomi, Huawei и других телефонах разрешите приложению автозапуск и работу в фоне без ограничений.')}'),
                  ),
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
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // .rem-exact: без «Будильники и напоминания» Android откладывает уведомления
              if (!_exact)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: mix(pal.accent, 0.12, pal.panel), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(child: Text(t('Чтобы напоминания приходили вовремя, разрешите приложению «Будильники и напоминания».'), style: TextStyle(fontSize: 14.4, height: 1.4, color: pal.text))),
                    const SizedBox(width: 10),
                    AobButton(label: t('Разрешить'), small: true, kind: BtnKind.primary, onTap: () => askExact().then((_) => _check())),
                  ]),
                ),
              for (final (i, x) in _r.list.indexed) ...[if (i > 0) const SizedBox(height: 8), _item(x)],
              const SizedBox(height: 4),
              // .rem-add: «+ Напоминание» и «+ Будильник» ссылками цвета акцента
              Wrap(spacing: 16, children: [
                for (final alarm in const [false, true])
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _add(alarm: alarm),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(alarm ? LucideIcons.alarmClockPlus : LucideIcons.plus, size: 17, color: pal.accent),
                        const SizedBox(width: 6),
                        Text(alarm ? t('Добавить будильник') : t('Добавить напоминание'), style: TextStyle(fontSize: 15.2, fontWeight: FontWeight.w600, color: pal.accent)),
                      ]),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Выбор времени колёсиками, как в будильнике iPhone: часы и минуты крутятся по кругу, выбранное — в полосе
/// посередине (.tw веб-версии). Новое время сохраняется, когда колёсико остановилось
class TimeWheel extends StatefulWidget {
  const TimeWheel({super.key, required this.pal, required this.value, required this.onChanged});
  final Palette pal;
  final String value; // «ЧЧ:ММ»
  final ValueChanged<String> onChanged;
  @override
  State<TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<TimeWheel> {
  late final List<int> _p = [for (final s in widget.value.split(':')) int.tryParse(s) ?? 0];
  late final _h = FixedExtentScrollController(initialItem: _p[0]);
  late final _m = FixedExtentScrollController(initialItem: _p.length > 1 ? _p[1] : 0);
  Timer? _commit;

  @override
  void dispose() {
    // повернули и сразу закрыли — время всё равно сохраняется
    if (_commit?.isActive ?? false) {
      _commit!.cancel();
      _save();
    }
    _h.dispose();
    _m.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  void _save() => widget.onChanged('${_two(_h.selectedItem % 24)}:${_two(_m.selectedItem % 60)}');
  void _changed(int _) {
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 450), _save);
  }

  Widget _col(FixedExtentScrollController c, int n, String label) {
    final pal = widget.pal;
    return SizedBox(
      width: 76,
      child: Semantics(
        label: label,
        child: CupertinoPicker(
          scrollController: c,
          itemExtent: 36,
          looping: true, // по кругу: после 23 — снова 00
          squeeze: 1.1,
          diameterRatio: 1.4,
          // полоса выбора — общая на обе колонки (ниже), у колонки своей нет
          selectionOverlay: const SizedBox.shrink(),
          onSelectedItemChanged: _changed,
          children: [for (var i = 0; i < n; i++) Center(child: Text(_two(i), style: TextStyle(fontSize: 22.4, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return SizedBox(
      height: 180,
      child: Stack(alignment: Alignment.center, children: [
        Container(height: 36, decoration: BoxDecoration(color: pal.text.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10))),
        // строки к краям плавно тают (а не обрываются у края колёсика)
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            stops: [0, 0.36, 0.64, 1],
          ).createShader(r),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _col(_h, 24, t('Часы')),
            Text(':', style: TextStyle(fontSize: 22.4, fontWeight: FontWeight.w500, color: pal.text)),
            _col(_m, 60, t('Минуты')),
          ]),
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
      // без своего нижнего отступа: промежуток между блоками окна — общий, 12
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
