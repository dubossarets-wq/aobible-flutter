// Планы чтения (PlansSheet.jsx): «Стих дня», активные планы с кольцом прогресса и кнопкой «Читать», напоминание,
// сколько прочитано (кольцо «доля Библии», дни подряд, неделя), готовые планы с обложками и свой план.
// Размеры и цвета — по styles.css (.plan-card, .read-hero, .plan-tile, .custom-plan…).
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
import 'plan_store.dart';
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

  @override
  void initState() {
    super.initState();
    ensureDict();
    fetchPlanIndex().then((i) => mounted ? setState(() => _index = i) : null, onError: (e) => mounted ? setState(() => _err = '$e'.replaceFirst('Exception: ', '')) : null);
  }

  @override
  void dispose() {
    _daysCtl.dispose();
    super.dispose();
  }

  void _go(VerseRef r) {
    Navigator.of(context).pop();
    ref.read(panesProvider.notifier).navigate(widget.pane, r);
  }

  void _read(Plan plan, int day, int at) {
    final rs = readingsOf(plan);
    if (day < rs.length && at < rs[day].length) _go(readingTarget(rs[day][at]));
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
    toast(context, t('План «{name}» начат — нажмите «Читать»', {'name': t('${plan['name']}')}));
  }

  Future<void> _start(PlanMeta m) async {
    setState(() => _busy = m.id);
    try {
      final p = await fetchPlan(m.file);
      _add({'planId': p['id'], 'name': p['name'], 'readings': p['readings'], 'calendar': p['calendar'] == true});
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _startCustom() async {
    final n = _days.clamp(7, 730);
    setState(() => _busy = 'custom');
    try {
      final scope = planScopes.firstWhere((s) => s.id == _scope);
      await Future<void>.delayed(const Duration(milliseconds: 30)); // дать перерисоваться индикатору
      final readings = makeCustomPlan(scope.books(), n);
      if (readings.isEmpty) throw Exception(t('Не удалось составить план'));
      // Глав меньше, чем дней (Евангелия за 730 дней) — дней столько, сколько глав
      _add({'planId': 'custom', 'name': t('{scope} за {n} дн.', {'scope': t(scope.label), 'n': '${readings.length}'}), 'readings': readings});
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
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
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
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line), color: pal.bg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t(m.name), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                const SizedBox(height: 6),
                Text('${t('{n} дн.', {'n': '${m.days}'})}${m.short != null ? ' · ${t(m.short!)}' : ''}', style: TextStyle(color: pal.muted, fontSize: 13.1)),
                if (m.description != null) Padding(padding: const EdgeInsets.fromLTRB(0, 8, 0, 6), child: Text(t(m.description!), style: TextStyle(color: pal.muted, fontSize: 13.1, height: 1.4))),
                const SizedBox(height: 6),
                _busy == m.id ? BusyButton(label: t('Начать')) : AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.plus, label: t('Начать'), onTap: _busy != null ? null : () => _start(m)),
              ]),
            ),
        const SizedBox(height: 18), // gap 12 + margin-top 6 у .custom-plan
        _customPlan(pal, days),
      ]),
    );
  }

  // Свой план — отдельной карточкой: что читать, за сколько дней, начать (.custom-plan)
  Widget _customPlan(Palette pal, int days) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.line), color: pal.panel),
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
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(t('Главы делятся на дни поровну по числу стихов.'), style: TextStyle(fontSize: 13.4, color: pal.muted, height: 1.35))),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text(t('Что читать'), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: pal.muted)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, s) in planScopes.indexed)
                SizedBox(
                  width: i == 0 ? c.maxWidth : w,
                  child: Material(
                    color: _scope == s.id ? mix(pal.accent, 0.12, pal.bg) : pal.bg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _scope == s.id ? pal.accent : pal.line, width: _scope == s.id ? 2 : 1)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _scope = s.id),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        alignment: Alignment.center,
                        child: Text(t(s.label), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.7, fontWeight: FontWeight.w600, color: _scope == s.id ? pal.accent : pal.text)),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
          const SizedBox(height: 12),
          Text(t('За сколько дней'), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: pal.muted)),
          const SizedBox(height: 10),
          Row(children: [
            _Step(pal: pal, icon: LucideIcons.minus, tip: t('Уменьшить'), onTap: () => _setDays(days - 1)),
            const SizedBox(width: 8),
            Expanded(
              child: PlainInput(
                controller: _daysCtl,
                height: 44,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17.6, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()]),
                onChanged: (v) => setState(() => _days = int.tryParse(v) ?? 90),
                onSubmitted: (_) => _setDays(_days),
              ),
            ),
            const SizedBox(width: 8),
            _Step(pal: pal, icon: LucideIcons.plus, tip: t('Увеличить'), onTap: () => _setDays(days + 1)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in [7, 14, 30, 90, 180, 365]) _Preset(pal: pal, label: t('{n} дн.', {'n': '$n'}), on: days == n, onTap: () => _setDays(n)),
          ]),
          const SizedBox(height: 14),
          _busy == 'custom' ? BusyButton(label: t('Начать на {n} дн.', {'n': '$days'})) : AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.plus, label: t('Начать на {n} дн.', {'n': '$days'}), onTap: _busy != null ? null : _startCustom),
        ]),
      );
}

/// .cp-presets .chip: плашка выше обычной (min-height 36, отступы 6/14)
class _Preset extends StatelessWidget {
  const _Preset({required this.pal, required this.label, required this.on, required this.onTap});
  final Palette pal;
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: on ? pal.accent : pal.bg,
        shape: StadiumBorder(side: BorderSide(color: on ? pal.accent : pal.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 13.8, color: on ? pal.onAccent : pal.text)),
          ),
        ),
      );
}

/// .cp-step: квадрат 44×44 со значком 18
class _Step extends StatelessWidget {
  const _Step({required this.pal, required this.icon, required this.tip, required this.onTap});
  final Palette pal;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: pal.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Tooltip(message: tip, child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 18, color: pal.text)))),
      );
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
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
            boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
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
        // outline: 3px solid accent; outline-offset: 2px
        if (on) Positioned(left: -5, top: -5, right: -5, bottom: -5, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: pal.accent, width: 3))))),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line), color: pal.bg),
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
                AobButton(small: true, kind: isDone ? BtnKind.primary : BtnKind.normal, icon: LucideIcons.check, label: isDone ? t('Прочитано') : t('Отметить'), onTap: () => _toggle(day)),
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

/// Напоминание о чтении: каждый день в выбранное время — что читать сегодня (.reminder-card)
class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.pal});
  final Palette pal;
  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  Reminder _r = getReminder();

  Future<void> _apply({bool? on, String? time}) async {
    final ok = await setReminder(on: on, time: time);
    if (!mounted) return;
    if (!ok) return toast(context, t('Уведомления запрещены — разрешите их в настройках телефона'));
    setState(() => _r = getReminder());
    if (on == true) toast(context, t('Напомню в {time}', {'time': _r.time}));
  }

  Future<void> _pickTime() async {
    final p = _r.time.split(':').map(int.parse).toList();
    final got = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p[0], minute: p[1]),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    if (got != null) _apply(time: '${got.hour.toString().padLeft(2, '0')}:${got.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line), color: pal.bg),
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
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: HintBtn(t('Каждый день в это время — уведомление с отрывками на сегодня'))),
                ]), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text)),
              ),
              const SizedBox(width: 12),
              AobSwitch(value: _r.on, onChanged: (v) => _apply(on: v)),
            ]),
          ),
        ),
        if (_r.on)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Row(children: [
              Text(t('Время'), style: TextStyle(fontSize: 15, color: pal.muted)),
              const Spacer(),
              // .reminder-time input
              Material(
                color: pal.panel,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: pal.line)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _pickTime,
                  child: Container(constraints: const BoxConstraints(minHeight: 40), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), alignment: Alignment.center, child: Text(_r.time, style: TextStyle(fontSize: 15, color: pal.text))),
                ),
              ),
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius + 6),
        border: Border.all(color: mix(pal.accent, 0.22, pal.line)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [mix(pal.accent, 0.16, pal.bg), mix(pal.accent, 0.04, pal.bg)]),
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
