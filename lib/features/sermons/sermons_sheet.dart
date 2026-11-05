// Проповеди (SermonsSheet.jsx): список со смахиванием и «Отменить», редактор (стихи и свой текст по порядку; зажать блок —
// перетащить) и «Кафедра» — крупный текст проповеди для чтения на служении, экран при этом не гаснет.
// Размеры и цвета — по styles.css (.sermon-*, .pulpit-*).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderObject;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/ios_style.dart';
import '../../ui/part_plate.dart';
import '../hub.dart';
import '../shell/fonts.dart' show readerTextStyle;
import '../plans/loc.dart';
import '../plans/ui_kit.dart';
import '../plans/verse_text.dart';
import 'screen_on.dart';
import 'sermon_pdf.dart';
import 'sermon_store.dart';

/// Свой текст с **жирным** и *курсивом*
List<InlineSpan> fmtSpans(String text) => [
      for (final p in fmtParts(text))
        TextSpan(text: p.t, style: p.b ? const TextStyle(fontWeight: FontWeight.w700) : p.i ? const TextStyle(fontStyle: FontStyle.italic) : null),
    ];

/// «1 место», «2 места», «5 мест»
String places(int n) => tx('{n} место|{n} места|{n} мест', {'n': n});

String _fmtDate(String d) {
  final x = DateTime.tryParse(d);
  return x == null ? '' : fmtDay(x, full: true, year: true);
}

class SermonsSheet extends ConsumerStatefulWidget {
  const SermonsSheet({super.key, required this.pane, this.open});
  final int pane;
  final String? open; // открыть сразу эту проповедь
  @override
  ConsumerState<SermonsSheet> createState() => _SermonsSheetState();
}

class _SermonsSheetState extends ConsumerState<SermonsSheet> {
  String? _openId;
  bool _adding = false; // поиск стихов для проповеди
  int? _insertAt; // куда вставлять найденные стихи (null — в конец)
  String? _scrollTo; // только что добавленный блок
  final _title = TextEditingController();
  final _q = TextEditingController(); // поиск по проповедям
  String _sort = 'recent'; // недавние / по алфавиту

  // История правок открытой проповеди (на время открытого окна, до 50 шагов): снимки проповеди целиком
  final _undo = <String>[];
  final _redo = <String>[];
  String? _hId, _hCur, _hKey;
  DateTime? _hAt;

  String _snap(Sermon s) => jsonEncode({...s}..remove('updatedAt'));

  void _ensureHist(Sermon? s) {
    if (s == null || _hId == '${s['id']}') return;
    _hId = '${s['id']}';
    _hCur = _snap(s);
    _hKey = null;
    _undo.clear();
    _redo.clear();
  }

  /// Правка одного поля: набор текста в одном блоке или в названии — склеивается в один шаг (пауза ~800 мс)
  String? _kind(String oldS, String newS) {
    final a = jsonDecode(oldS) as Map<String, dynamic>, b = jsonDecode(newS) as Map<String, dynamic>;
    final keys = {...a.keys, ...b.keys}.where((k) => jsonEncode(a[k]) != jsonEncode(b[k])).toList();
    if (keys.length == 1 && keys.first == 'title') return 'title';
    if (keys.length == 1 && keys.first == 'blocks') {
      final x = (a['blocks'] as List), y = (b['blocks'] as List);
      if (x.length != y.length) return null;
      String? hit;
      for (var i = 0; i < x.length; i++) {
        if (jsonEncode(x[i]) == jsonEncode(y[i])) continue;
        final p = x[i] as Map, q = y[i] as Map;
        final diff = {...p.keys, ...q.keys}.where((k) => jsonEncode(p[k]) != jsonEncode(q[k])).toList();
        if (hit != null || diff.length != 1 || diff.first != 'text' || q['type'] == 'verse') return null;
        hit = 'b:${q['id']}';
      }
      return hit;
    }
    return null;
  }

  void _track(List<Sermon> list) {
    final s = list.where((x) => x['id'] == _openId).firstOrNull;
    if (s == null) return;
    _ensureHist(s);
    final snap = _snap(s);
    if (snap == _hCur) return;
    final now = DateTime.now();
    final key = _kind(_hCur!, snap);
    final merge = key != null && key == _hKey && _hAt != null && now.difference(_hAt!) < const Duration(milliseconds: 800);
    if (!merge) {
      _undo.add(_hCur!);
      if (_undo.length > 50) _undo.removeAt(0);
      _redo.clear();
    }
    _hKey = key;
    _hAt = now;
    _hCur = snap;
    if (mounted) setState(() {});
  }

  void _step(bool back) {
    final from = back ? _undo : _redo, to = back ? _redo : _undo;
    if (from.isEmpty || _hCur == null) return;
    to.add(_hCur!);
    final snap = from.removeLast();
    _hCur = snap;
    _hKey = null;
    final cur = ref.read(sermonsProvider.notifier).byId(_hId);
    ref.read(sermonsProvider.notifier).replace({...(jsonDecode(snap) as Map<String, dynamic>), 'updatedAt': cur?['updatedAt'] ?? 0});
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _openId = widget.open;
    ensureDict();
    if (prefs.getString('sermonSort') == '"alpha"') _sort = 'alpha';
  }

  @override
  void dispose() {
    _title.dispose();
    _q.dispose();
    super.dispose();
  }

  // Список: поиск (название, подзаголовок, серия, текст), сортировка; серии — под общими заголовками, без серии — в конце
  List<Widget> _list(Palette pal, List<Sermon> sermons) {
    final needle = _q.text.trim().toLowerCase();
    bool hit(Sermon s) =>
        needle.isEmpty ||
        ['${s['title']}', '${s['subtitle'] ?? ''}', '${s['series'] ?? ''}', for (final b in blocksOf(s)) isVerse(b) ? '${blockRefFull(b)} ${b['text']}' : '${b['text']}']
            .any((x) => x.toLowerCase().contains(needle));
    final list = sermons.where(hit).toList()
      ..sort((a, b) => _sort == 'alpha' ? '${a['title']}'.toLowerCase().compareTo('${b['title']}'.toLowerCase()) : ((b['updatedAt'] ?? 0) as num).compareTo((a['updatedAt'] ?? 0) as num));
    if (list.isEmpty) return [Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(t('Ничего не найдено'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)))];
    String ser(Sermon s) => '${s['series'] ?? ''}'.trim();
    final names = {for (final s in list) ser(s)}.where((x) => x.isNotEmpty).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final groups = names.isEmpty
        ? [(null, list)]
        : [for (final n in names) (n, [for (final s in list) if (ser(s) == n) s]), (t('Без серии'), [for (final s in list) if (ser(s).isEmpty) s])];
    return [
      for (final (name, items) in groups)
        if (items.isNotEmpty) ...[
          if (name != null)
            // .sermon-group: заголовок серии
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Row(children: [
                Icon(ico(LucideIcons.layers), size: 14, color: pal.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(name.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: pal.muted))),
              ]),
            ),
          for (final (i, s) in items.indexed) _row(pal, s, first: i == 0, last: i == items.length - 1),
        ],
    ];
  }

  // стиль iPhone: строки — частями карточки группы
  Widget _row(Palette pal, Sermon s, {bool first = false, bool last = false}) => iosUiNow
      // стиль iPhone: смахивание как в iOS 26 — капсула «Удалить» с подписью
      ? IosCardItem(
          pal: pal,
          first: first,
          last: last,
          indent: iosRowTextLeft - 12,
          child: IosSwipe(
            pal: pal,
            actions: [IosSwipeAction(icon: CupertinoIcons.trash, label: t('Удалить'), color: sysColor(CupertinoColors.systemRed, dark: pal.dark), onTap: () => _remove(s), destructive: true)],
            child: SermonRow(pal: pal, sermon: s, inCard: true, onTap: () => setState(() => _openId = '${s['id']}')),
          ),
        )
      : bleed(Dismissible(
        key: ValueKey('${s['id']}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _remove(s),
        // .swipe-act: красная полоса с «корзиной» и подписью
        background: Container(
          color: const Color(0xFFD1342B),
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 88,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ico(LucideIcons.trash2), size: 18, color: Colors.white),
              const SizedBox(height: 3),
              Text(t('Удалить'), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        child: SermonRow(pal: pal, sermon: s, inCard: iosUiNow, onTap: () => setState(() => _openId = '${s['id']}')),
      ));

  String? get _moduleId {
    final panes = ref.read(panesProvider);
    final id = widget.pane < panes.length ? panes[widget.pane].moduleId : null;
    final store = ModuleStore.instance;
    return (id != null && store.get(id) != null && store.get(id)!.type == 'bible') ? id : store.bibles.firstOrNull?.id;
  }

  void _create() {
    final id = ref.read(sermonsProvider.notifier).create(_title.text);
    _title.clear();
    FocusScope.of(context).unfocus();
    setState(() => _openId = id);
  }

  // Удалить проповедь смахиванием — сразу, но с «Отменить»
  void _remove(Sermon s) {
    final list = ref.read(sermonsProvider);
    final i = list.indexWhere((x) => x['id'] == s['id']);
    ref.read(sermonsProvider.notifier).delete('${s['id']}');
    showUndo(context, t('Проповедь «{title}» удалена', {'title': '${s['title']}'}), () => ref.read(sermonsProvider.notifier).restore(s, i));
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final sermons = ref.watch(sermonsProvider);
    final sermon = sermons.where((s) => s['id'] == _openId).firstOrNull;
    final moduleId = _moduleId;
    _ensureHist(sermon);
    ref.listen(sermonsProvider, (_, list) => _track(list));

    if (sermon != null && _adding) {
      return AobSheet(
        title: t('Добавить стих'),
        subtitle: '${sermon['title']}',
        onBack: () => setState(() => _adding = false),
        scroll: false,
        padding: EdgeInsets.zero,
        child: VersePicker(
          pal: pal,
          sermonId: '${sermon['id']}',
          moduleId: moduleId,
          insertAt: _insertAt,
          onInsertAt: (v) => _insertAt = v,
          onDone: (firstId) => setState(() {
            _adding = false;
            _scrollTo = firstId;
          }),
        ),
      );
    }

    final canBack = sermon != null && !(widget.open != null && _openId == widget.open);
    return AobSheet(
      title: sermon != null ? t('Проповедь') : t('Проповеди'),
      // в открытой проповеди вместо названия — размер текста «− 100% +» (стихи, переводы, свой текст)
      titleWidget: sermon != null ? _SermonZoom(pal: pal) : null,
      onBack: canBack ? () => setState(() => _openId = null) : null,
      actions: sermon == null
          ? const []
          : [
              // «Печать и PDF»: файл PDF проповеди — в окно «Поделиться» (печать, сохранить, отправить)
              IconBtn(
                icon: LucideIcons.printer,
                tooltip: t('Печать и PDF'),
                color: blocksOf(sermon).isEmpty ? pal.muted.withValues(alpha: 0.4) : null,
                onTap: blocksOf(sermon).isEmpty ? null : () => shareSermonPdf(sermon),
              ),
              // «Поделиться» — значком слева от «Отменить» / «Повторить»
              IconBtn(
                icon: LucideIcons.share2,
                tooltip: t('Поделиться'),
                color: blocksOf(sermon).isEmpty ? pal.muted.withValues(alpha: 0.4) : null,
                onTap: blocksOf(sermon).isEmpty ? null : () => SharePlus.instance.share(ShareParams(text: sermonText(sermon), title: '${sermon['title']}')),
              ),
              IconBtn(icon: LucideIcons.undo2, tooltip: t('Отменить'), color: _undo.isEmpty ? pal.muted.withValues(alpha: 0.4) : null, onTap: _undo.isEmpty ? null : () => _step(true)),
              IconBtn(icon: LucideIcons.redo2, tooltip: t('Повторить'), color: _redo.isEmpty ? pal.muted.withValues(alpha: 0.4) : null, onTap: _redo.isEmpty ? null : () => _step(false)),
            ],
      scroll: false,
      padding: EdgeInsets.zero,
      child: sermon != null
          ? _Editor(
              key: ValueKey(sermon['id']),
              pal: pal,
              sermon: sermon,
              pane: widget.pane,
              moduleId: moduleId,
              scrollTo: _scrollTo,
              onBackToList: () => setState(() => _openId = null),
              onOpen: (id) => setState(() => _openId = id),
              onAddVerse: (at) => setState(() {
                _insertAt = at;
                _scrollTo = null;
                _adding = true;
              }),
            )
          : Builder(builder: (bc) => ListView(padding: padTabs(bc, const EdgeInsets.fromLTRB(16, 12, 16, 20)), children: [
              // .ref-form: поле и кнопка «Создать» в одну строку, промежуток 8
              // IntrinsicHeight: в списке высота не ограничена — stretch тянется до высоты поля
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: PlainInput(controller: _title, hint: t('Новая проповедь'), onSubmitted: (_) => _create())),
                  const SizedBox(width: 8),
                  AobButton(kind: BtnKind.primary, icon: LucideIcons.plus, label: t('Создать'), onTap: _create),
                ]),
              ),
              const SizedBox(height: 12),
              if (sermons.isEmpty)
                // .empty
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                  child: Column(children: [
                    Icon(ico(LucideIcons.scrollText), size: 28, color: pal.muted),
                    const SizedBox(height: 8),
                    Text(t('Проповедей пока нет'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(t('Создайте проповедь и добавляйте стихи прямо при чтении: зажмите стих → «В проповедь».'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, color: pal.muted, height: 1.45)),
                    ),
                  ]),
                )
              else ...[
                // поиск по проповедям и сортировка
                AobInput(controller: _q, hint: t('Поиск по проповедям'), height: 44, onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                Segmented<String>(
                  value: _sort,
                  options: [('recent', t('Недавние')), ('alpha', t('По алфавиту'))],
                  onChanged: (v) {
                    setState(() => _sort = v);
                    prefs.setString('sermonSort', jsonEncode(v));
                  },
                ),
                const SizedBox(height: 4),
                // строки — от края до края окна (и красная полоса удаления тоже), как списки в настройках
                ..._list(pal, sermons),
              ],
            ])),
    );
  }
}

/// Строка проповеди в списке (.sermon-pick-row): значок, название, число мест Писания, дата
class SermonRow extends StatelessWidget {
  const SermonRow({super.key, required this.pal, required this.sermon, required this.onTap, this.trailing, this.enabled = true, this.shortDate = false, this.inCard = false});
  final bool inCard; // строка в карточке группы iOS: без своей заливки и линии
  final Palette pal;
  final Sermon sermon;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool enabled, shortDate;

  @override
  Widget build(BuildContext context) {
    final verses = blocksOf(sermon).where(isVerse).length;
    final date = _fmtDate('${sermon['date'] ?? ''}');
    final upd = DateTime.fromMillisecondsSinceEpoch(((sermon['updatedAt'] ?? 0) as num).toInt());
    final sub = '${places(verses)}${date.isNotEmpty ? ' · $date' : shortDate ? '' : ' · ${t('изменена {date}', {'date': fmtDay(upd)})}'}';
    return Material(
      color: inCard ? Colors.transparent : pal.panel,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          // строка стоит от края до края окна (bleed у списка) — отступы у содержимого
          padding: inCard ? const EdgeInsets.fromLTRB(iosRowIconLeft, 11, iosRowRight, 11) : const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: inCard ? null : BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            Icon(ico(LucideIcons.scrollText), size: 18, color: pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sermon['title']}', style: iosUiNow ? TextStyle(fontSize: 17, color: pal.text) : TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: iosUiNow ? 15 : 13.1, color: pal.muted)),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

// --- Редактор ------------------------------------------------------------------------------------------

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.pal, required this.sermon, required this.pane, required this.moduleId, required this.onBackToList, required this.onOpen, required this.onAddVerse, this.scrollTo});
  final Palette pal;
  final Sermon sermon;
  final int pane;
  final String? moduleId;
  final String? scrollTo;
  final VoidCallback onBackToList;
  final ValueChanged<String> onOpen; // открыть другую проповедь (копию)
  final void Function(int? at) onAddVerse;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  String? _fresh; // только что добавленный текстовый блок — сразу в него курсор
  late final _title = TextEditingController(text: '${widget.sermon['title']}');
  late final _subtitle = TextEditingController(text: '${widget.sermon['subtitle'] ?? ''}');
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  String? _flash;

  String get _id => '${widget.sermon['id']}';

  @override
  void initState() {
    super.initState();
    _fill();
    if (widget.scrollTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return; // окно могли закрыть до первого кадра
        final c = _keys[widget.scrollTo]?.currentContext;
        if (c != null) Scrollable.ensureVisible(c, alignment: 0.4);
        setState(() => _flash = widget.scrollTo);
        Future.delayed(const Duration(milliseconds: 1400), () => mounted ? setState(() => _flash = null) : null);
      });
    }
  }

  @override
  void didUpdateWidget(_Editor old) {
    super.didUpdateWidget(old);
    _fill();
  }

  // Старые проповеди: диапазон стихов — одной строкой; разбиваем по стихам (текст не меняется)
  void _fill() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(sermonsProvider.notifier).fillVerseTexts(_id, widget.moduleId);
      });

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  SermonsNotifier get _store => ref.read(sermonsProvider.notifier);

  // Нажатие на стих — к этому стиху в Библии
  void _goVerse(Block b, int verse) {
    closeToReader(context); // сразу в Библию
    ref.read(panesProvider.notifier).navigate(widget.pane, VerseRef(b['book'] as String, b['chapter'] as int, verse));
    sermonReturn.value = (pane: widget.pane, id: _id); // под верхним меню — «Вернуться к проповеди»
  }

  // Убрать стих (из диапазона — только его; диапазон делится на части) — с «Отменить»
  void _dropVerse(Block b, int verse) {
    final before = blocksOf(widget.sermon);
    final one = b['to'] == null || b['to'] == b['verse'] || verseTexts(b) == null;
    _store.removeVerse(_id, '${b['id']}', verse);
    showUndo(context, t('Убрано: {ref}', {'ref': one ? blockRef(b) : blockRef({...b, 'verse': verse, 'to': null})}), () => _store.restoreBlocks(_id, before));
  }


  void _pulpit() => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => Pulpit(sermon: widget.sermon)));

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    // Свежая версия проповеди из хранилища (редактор живёт, пока открыт)
    final sermon = ref.watch(sermonsProvider).where((s) => s['id'] == widget.sermon['id']).firstOrNull ?? widget.sermon;
    final blocks = blocksOf(sermon);
    final verses = blocks.where(isVerse).length;
    if (_title.text != '${sermon['title']}') _title.text = '${sermon['title']}'; // «Отменить»/«Повторить» меняют название
    if (_subtitle.text != '${sermon['subtitle'] ?? ''}') _subtitle.text = '${sermon['subtitle'] ?? ''}';
    _keys.removeWhere((id, _) => !blocks.any((b) => b['id'] == id)); // ключи удалённых блоков не копим
    // тексты подключённых переводов дописываются, когда их ещё нет
    if (blocks.any((b) => isVerse(b) && altsOf(b).any((a) => ((a['t'] as List?)?.length ?? 0) != ((b['to'] ?? b['verse']) as int) - (b['verse'] as int) + 1))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted
          ? _store.fillAltTexts(_id, (m, r, il) => il ? verseRaw(m, r) : verseText(m, r), (m) => ModuleStore.instance.get(m)?.features['interlinear'] == true)
          : null);
    }
    // размер текста («− 100% +» в шапке) поменяли — блоки перерисовываются с новым размером
    return ValueListenableBuilder<double>(
      valueListenable: sermonZoom,
      builder: (context, _, _) => ReorderableListView.builder(
        scrollController: _scroll,
        padding: padTabs(context, const EdgeInsets.fromLTRB(16, 12, 16, 20)),
        buildDefaultDragHandles: false, // тянуть — зажав сам блок (как в веб-версии)
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorderItem: (a, b) => _store.moveBlock(_id, a, b),
        // .sermon-item.dragging: тень 0 14 34, фон панели
        // Поднимается только карточка блока (без полос «+ Текст / + Стих»), тень — по её скруглённой рамке
        proxyDecorator: (child, i, anim) => i >= blocks.length
            ? child
            : Material(
                color: Colors.transparent,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 34, offset: Offset(0, 14))]),
                      child: _BlockCard(pal: pal, block: blocks[i], sermonId: _id, fresh: false, onFreshDone: () {}, onGo: (_) {}, onDropVerse: (_) {}),
                    ),
                  ),
                ),
              ),
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // .sermon-head: название (линия снизу) и две кнопки; промежуток 8
          _TitleField(pal: pal, controller: _title, onChanged: (v) => _store.rename(_id, v)),
          // подзаголовок (описание) — необязательный, растёт по тексту
          TextField(
            controller: _subtitle,
            onChanged: (v) => _store.setSubtitle(_id, v),
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 15.7, height: 1.45, color: pal.muted),
            decoration: InputDecoration(
              hintText: t('Подзаголовок или описание'),
              hintStyle: TextStyle(color: pal.muted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 12), // сверху — отступ от названия
            ),
          ),
          // название и подзаголовок — одна группа: под ней тонкая линия, ниже — серия и кнопка «Кафедра»
          Container(height: 1, color: pal.line),
          _SeriesField(
            pal: pal,
            value: '${sermon['series'] ?? ''}',
            all: {for (final x in ref.watch(sermonsProvider)) '${x['series'] ?? ''}'.trim()}.where((x) => x.isNotEmpty).toList()..sort(),
            onChanged: (v) => _store.setSeries(_id, v),
          ),
          const SizedBox(height: 8),
          AobButton(wide: true, kind: BtnKind.primary, icon: LucideIcons.presentation, label: t('Кафедра'), onTap: blocks.isEmpty ? null : _pulpit),
          const SizedBox(height: 20), // margin-bottom 8 + промежуток 12
          if (blocks.isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: mix(pal.accent, 0.08, pal.bg), borderRadius: BorderRadius.circular(kRadius)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${t('Как добавить стих:')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: t('зажмите стих в Библии и нажмите «В проповедь» — или найдите его кнопкой «Стих» ниже.')),
                ]), style: TextStyle(fontSize: 14.7, color: pal.text, height: 1.5)),
                const SizedBox(height: 6),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${t('Свой текст')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: t('— кнопка «Текст». Чтобы переставить блок, зажмите его и тяните.')),
                ]), style: TextStyle(fontSize: 14.7, color: pal.text, height: 1.5)),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Inserter(
                pal: pal,
                onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: -1)),
                onVerse: () => widget.onAddVerse(0),
                onNote: () => setState(() => _fresh = _store.addTextBlock(_id, after: -1, type: 'note')),
              ),
            ),
        ]),
        footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (blocks.isEmpty)
            // .sermon-add: две кнопки в строку на всю ширину
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: AobButton(wide: true, icon: LucideIcons.plus, label: t('Текст'), onTap: () => setState(() => _fresh = _store.addTextBlock(_id)))),
                const SizedBox(width: 8),
                Expanded(child: AobButton(wide: true, icon: LucideIcons.search, label: t('Стих'), onTap: () => widget.onAddVerse(null))),
              ]),
            ),
          // «Сделать копию» и «Удалить проповедь» (с подтверждением) — неброскими кнопками по центру
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: pal.muted, textStyle: const TextStyle(fontSize: 14.4, fontWeight: FontWeight.w500)),
                icon: Icon(ico(LucideIcons.copyPlus), size: 16),
                label: Text(t('Сделать копию')),
                onPressed: () {
                  final id = _store.duplicate(_id);
                  if (id != null) widget.onOpen(id);
                },
              ),
              _WideDelete(onConfirm: () {
                _store.delete(_id);
                widget.onBackToList();
              }),
            ]),
          ),
        ]),
        itemCount: blocks.length,
        itemBuilder: (_, i) {
          final b = blocks[i];
          final id = '${b['id']}';
          return ReorderableDelayedDragStartListener(
            key: ValueKey(id),
            index: i,
            child: Column(key: _keys.putIfAbsent(id, GlobalKey.new), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // .sermon-block.just-added: рамка-«вспышка» цвета акцента, гаснет за 1,4 с
              Stack(clipBehavior: Clip.none, children: [
                _BlockCard(
                  pal: pal,
                  block: b,
                  fresh: _fresh == id,
                  sermonId: _id,
                  altDefault: [for (final a in (sermon['altDefault'] as List? ?? const [])) (a as Map).cast<String, dynamic>()],
                  onUp: i > 0 ? () => _store.moveBlock(_id, i, i - 1) : null,
                  onDown: i < blocks.length - 1 ? () => _store.moveBlock(_id, i, i + 1) : null,
                  onFreshDone: () => _fresh == id ? setState(() => _fresh = null) : null,
                  onGo: (v) => _goVerse(b, v),
                  onDropVerse: (v) => _dropVerse(b, v),
                  // слово подстрочника — статья Стронга поверх проповеди («назад» — обратно в проповедь)
                  onStrong: (v, n) => Hub.openStrong?.call(context, ref, widget.pane, VerseRef(b['book'] as String, b['chapter'] as int, v), n, closeToParent: true),
                ),
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 600),
                      opacity: _flash == id ? 1 : 0,
                      child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius + 5), border: Border.all(color: mix(pal.accent, 0.4, Colors.transparent), width: 3))),
                    ),
                  ),
                ),
              ]),
              _Inserter(
                pal: pal,
                onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: i)),
                onVerse: () => widget.onAddVerse(i + 1),
                onNote: () => setState(() => _fresh = _store.addTextBlock(_id, after: i, type: 'note')),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// .sermon-title-input: 1,35rem, жирный, только линия снизу (при вводе — цвета акцента)
/// «Удалить проповедь» внизу редактора: неброская красная кнопка по центру; первое нажатие просит подтвердить (3 секунды)
class _WideDelete extends StatefulWidget {
  const _WideDelete({required this.onConfirm});
  final VoidCallback onConfirm;
  @override
  State<_WideDelete> createState() => _WideDeleteState();
}

class _WideDeleteState extends State<_WideDelete> {
  bool _ask = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: const Color(0xffc93a3a), textStyle: const TextStyle(fontSize: 14.4, fontWeight: FontWeight.w500)),
          icon: Icon(ico(LucideIcons.trash2), size: 16),
          label: Text(_ask ? t('Удалить проповедь?') : t('Удалить проповедь')),
          onPressed: () {
          if (_ask) {
            _timer?.cancel();
            widget.onConfirm();
            return;
          }
          setState(() => _ask = true);
          _timer = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _ask = false) : null);
        },
        ),
      );
}

/// Серия (необязательно): значок и поле без рамки; при вводе — уже заданные серии чипами
class _SeriesField extends StatefulWidget {
  const _SeriesField({required this.pal, required this.value, required this.all, required this.onChanged});
  final Palette pal;
  final String value;
  final List<String> all;
  final ValueChanged<String> onChanged;
  @override
  State<_SeriesField> createState() => _SeriesFieldState();
}

class _SeriesFieldState extends State<_SeriesField> {
  late final _ctl = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String v) {
    _ctl.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    widget.onChanged(v);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    if (_ctl.text != widget.value && !_focus.hasFocus) _ctl.text = widget.value; // «Отменить»/«Повторить»
    final cur = _ctl.text.trim().toLowerCase();
    final opts = [for (final x in widget.all) if (x.toLowerCase() != cur && x.toLowerCase().contains(cur)) x];
    return TextFieldTapRegion(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ico(LucideIcons.layers), size: 15, color: pal.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 14.4, color: pal.text),
              decoration: InputDecoration(
                hintText: t('Серия (необязательно)'),
                hintStyle: TextStyle(color: pal.muted.withValues(alpha: 0.7)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ]),
        Reveal(
          open: _focus.hasFocus && opts.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(left: 23, bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final x in opts) AobChip(label: x, icon: LucideIcons.layers, compact: true, onTap: () => _set(x))]),
          ),
        ),
      ]),
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({required this.pal, required this.controller, required this.onChanged});
  final Palette pal;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 23, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: pal.text),
        decoration: InputDecoration(
          hintText: t('Название проповеди'),
          hintStyle: TextStyle(color: pal.muted),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
          // линия цвета акцента — только при вводе
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: pal.accent)),
        ),
      );
}

/// .sermon-insert: компактная строка между блоками — добавить текст или стих именно сюда; за кнопками — пунктирная линия
class _Inserter extends StatelessWidget {
  const _Inserter({required this.pal, required this.onText, required this.onVerse, required this.onNote});
  final Palette pal;
  final VoidCallback onText, onVerse, onNote;

  @override
  Widget build(BuildContext context) {
    final ios = iosPal(pal); // стиль iPhone: капсулы без обводки, надпись цвета акцента
    Widget btn(String label, String tip, VoidCallback f) => Tooltip(
          message: tip,
          child: Material(
            color: ios ? iosCard(pal) : pal.bg,
            shape: StadiumBorder(side: ios ? BorderSide.none : BorderSide(color: pal.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: f,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ico(LucideIcons.plus), size: 14, color: pal.accent),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: ios ? 14 : 13.4, fontWeight: FontWeight.w600, color: ios ? pal.accent : pal.muted)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(alignment: Alignment.center, children: [
        Positioned(left: 14, right: 14, child: DashedLine(color: pal.line)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(t('Текст'), t('Добавить текст'), onText),
          const SizedBox(width: 8),
          btn(t('Стих'), t('Добавить стих'), onVerse),
          const SizedBox(width: 8),
          btn(t('Заметка'), t('Заметка для себя'), onNote),
        ]),
      ]),
    );
  }
}

/// Мягкая капсула нижней строки карточки (в одном стиле с «⠿ ↑ ↓»): значок и подпись; без подписи — круглая
class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.pal, required this.icon, required this.onTap, this.label, this.tooltip, this.on = false});
  final Palette pal;
  final IconData icon;
  final VoidCallback onTap;
  final String? label, tooltip;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: on ? pal.accent.withValues(alpha: 0.16) : pal.text.withValues(alpha: 0.06),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 30,
          width: label == null ? 30 : null,
          child: Padding(
            padding: label == null ? EdgeInsets.zero : const EdgeInsets.only(left: 9, right: 11),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ico(icon), size: 15, color: on ? pal.accent : pal.muted),
              if (label != null) ...[
                const SizedBox(width: 5),
                Transform.translate(offset: const Offset(0, -0.5), child: Text(label!, style: TextStyle(fontSize: 13.1, fontWeight: FontWeight.w500, color: pal.text))),
              ],
            ]),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Перестановка блока: «ручка» ⠿ (зажать и тянуть) и стрелки ↑ ↓ — одной капсулой; у крайних блоков лишняя стрелка бледная
class _Reorder extends StatelessWidget {
  const _Reorder({required this.pal, this.onUp, this.onDown});
  final Palette pal;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String tip, VoidCallback? f) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: f,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 30, height: 30, child: Icon(ico(icon), size: 16, color: f == null ? pal.muted.withValues(alpha: 0.35) : pal.text)),
          ),
        );
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(color: pal.text.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(15)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(message: t('Зажмите, чтобы перетащить'), child: Icon(ico(LucideIcons.gripVertical), size: 16, color: pal.muted)),
        Container(width: 1, height: 16, margin: const EdgeInsets.symmetric(horizontal: 4), color: pal.line),
        arrow(LucideIcons.arrowUp, t('Переместить выше'), onUp),
        arrow(LucideIcons.arrowDown, t('Переместить ниже'), onDown),
      ]),
    );
  }
}

class _BlockCard extends ConsumerStatefulWidget {
  const _BlockCard({required this.pal, required this.block, required this.sermonId, required this.fresh, required this.onFreshDone, required this.onGo, required this.onDropVerse, this.onUp, this.onDown, this.onStrong, this.altDefault = const []});
  final void Function(int verse, String strongNum)? onStrong; // нажали слово подстрочника
  final VoidCallback? onUp, onDown; // переставить на одно место выше / ниже (у крайних блоков — null)
  final List<Map<String, dynamic>> altDefault; // переводы, которые сами подключаются к новым стихам проповеди
  final Palette pal;
  final Block block;
  final String sermonId;
  final bool fresh;
  final VoidCallback onFreshDone;
  final void Function(int verse) onGo;
  final void Function(int verse) onDropVerse;

  @override
  ConsumerState<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<_BlockCard> {
  bool _altOpen = false; // раскрыт выбор переводов
  bool _picking = false; // режим «Часть стиха»: слова полного текста нажимаются
  int? _from, _to;
  String _full = '';
  List<Word> _words = const [];
  final _textKey = GlobalKey();

  Palette get pal => widget.pal;
  Block get block => widget.block;

  /// Полный текст стиха из модуля, в котором он добавлен (как при добавлении)
  String? _fullText() {
    final mid = block['moduleId'];
    if (mid is! String || !isVerse(block)) return null;
    return verseText(mid, VerseRef(block['book'] as String, block['chapter'] as int, block['verse'] as int));
  }

  void _start() {
    final full = _fullText();
    if (full == null || full.trim().isEmpty) return;
    _full = full;
    _words = wordsOf([Token(full)]);
    setState(() {
      _picking = true;
      _from = _to = null;
    });
  }

  void _tap(int i) => setState(() {
        if (_from == null || _to != null) {
          _from = i;
          _to = null;
        } else {
          _to = i;
        }
      });

  (int, int)? get _range => _from == null ? null : (_to == null ? (_from!, _from!) : (_from! < _to! ? (_from!, _to!) : (_to!, _from!)));

  /// Слово под точкой нажатия: по позиции символа в абзаце (без распознавателей в TextSpan — они терялись при перестройке)
  void _tapAt(Offset global) {
    RenderParagraph? para;
    void find(RenderObject o) {
      if (para != null) return;
      if (o is RenderParagraph) {
        para = o;
        return;
      }
      o.visitChildren(find);
    }

    final ro = _textKey.currentContext?.findRenderObject();
    if (ro != null) find(ro);
    final pr = para;
    if (pr == null) return;
    final off = pr.getPositionForOffset(pr.globalToLocal(global)).offset;
    int? best;
    var bestD = 1 << 30;
    for (final (i, w) in _words.indexed) {
      final d = off < w.start ? w.start - off : (off > w.end ? off - w.end : 0);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != null && bestD <= 1) _tap(best);
  }

  Widget _pickText(TextStyle style) {
    final r = _range;
    // цельная плашка под текстом, как выбор части стиха в читалке (акцент 24 %)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _tapAt(d.globalPosition),
      child: Stack(children: [
        if (r != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: PartPlate(_textKey, _words[r.$1].start, _words[r.$2].end, pal.accent.withValues(alpha: 0.24))))),
        Text(_full, key: _textKey, style: style),
      ]),
    );
  }

  void _done() {
    final r = _range;
    if (r == null) return;
    final text = partText([Token(_full)], _words, r.$1, r.$2);
    if (text.isEmpty) return;
    ref.read(sermonsProvider.notifier).setPart(widget.sermonId, '${block['id']}', text, true);
    setState(() => _picking = false);
  }

  @override
  Widget build(BuildContext context) {
    final sermonId = widget.sermonId, fresh = widget.fresh, onFreshDone = widget.onFreshDone, onGo = widget.onGo, onDropVerse = widget.onDropVerse;
    final store = ref.read(sermonsProvider.notifier);
    final verse = isVerse(block);
    final note = block['type'] == 'note';
    final isPart = block['part'] == true;
    final canPick = verse && block['to'] == null && !_picking && _fullText() != null;
    final texts = verse ? verseTexts(block) : null;
    final group = texts != null && texts.length > 1;
    final v0 = (block['verse'] ?? 0) as int;
    // Старый диапазон, который не удалось разбить, — одним абзацем, как раньше
    final lines = texts != null ? [for (final (k, x) in texts.indexed) (v: v0 + k, text: x)] : verse ? [(v: v0, text: '${block['text']}')] : <({int v, String text})>[];
    final z = sermonZoom.value; // размер текста проповеди («− 100% +» в шапке)
    final verseStyle = readerTextStyle(ref.watch(settingsProvider), size: 16.8 * z, weight: 400).copyWith(height: 1.5, color: pal.text); // .sermon-verse-text: --font-text
    final alts = altsOf(block);
    final mainMod = '${block['moduleId'] ?? ''}';
    final trash = ConfirmIcon(icon: LucideIcons.trash2, size: 16, confirmText: t('Удалить'), tooltip: verse ? t('Удалить стих из проповеди') : t('Удалить текст'), onConfirm: () => store.removeBlock(sermonId, '${block['id']}'));
    String nameOf(String mid) => ModuleStore.instance.get(mid)?.name ?? mid;
    // стих — с полосой цвета акцента слева: места Писания видно при прокрутке
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: Stack(children: [
      Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      // лёгкий фон, как у карточек планов; заметка для себя — ещё приглушённее
      decoration: BoxDecoration(
        color: note ? mix(pal.muted, 0.07, sermonCardBg(pal)) : sermonCardBg(pal),
        borderRadius: BorderRadius.circular(iosPal(pal) ? 12 : kRadius),
        border: iosPal(pal) ? null : Border.all(color: pal.line), // стиль iPhone: карточка без обводки, как группа строк iOS
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (verse) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onGo(v0),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: blockRef(block)),
                    // рядом со ссылкой — перевод
                    if (mainMod.isNotEmpty) TextSpan(text: ' · ${nameOf(mainMod)}', style: TextStyle(fontWeight: FontWeight.w500, color: pal.muted)),
                  ]), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.2, color: pal.accent)),
                ),
              ),
            ),
            // корзина — в правом верхнем углу карточки
            Transform.translate(offset: const Offset(6, -6), child: trash),
          ]),
          // «Часть стиха»: полный текст для выбора слов и обычные строки сменяют друг друга плавно
          Reveal(
            open: _picking,
            child: Padding(
              padding: const EdgeInsets.only(top: 1, bottom: 1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _pickText(verseStyle),
                Reveal(open: _range == null, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('Нажмите на первое и последнее слово.'), style: TextStyle(fontSize: 14.4, height: 1.4, fontStyle: FontStyle.italic, color: pal.muted)))),
              ]),
            ),
          ),
          Reveal(
            open: !_picking,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (k, l) in lines.indexed)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onGo(l.v),
                      child: Padding(
                        padding: EdgeInsets.only(top: group && k > 0 ? 6 : 1, bottom: 1),
                        child: Text.rich(TextSpan(children: [
                          if (group) WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: const EdgeInsets.only(right: 5), child: Text('${l.v}', style: TextStyle(fontSize: 10.8, color: pal.accent, fontWeight: FontWeight.w700)))),
                          TextSpan(text: l.text),
                        ]), style: verseStyle),
                      ),
                    ),
                  ),
                  if (group) Padding(padding: EdgeInsets.only(top: k > 0 ? 4 : 0), child: ConfirmIcon(icon: LucideIcons.x, size: 15, confirmText: t('Убрать'), tooltip: t('Убрать стих'), onConfirm: () => onDropVerse(l.v))),
                ]),
              // подключённые переводы — под основным текстом (стиха в переводе нет — прочерк); новый плавно
              // раскрывается и проявляется, убранный — плавно сворачивается (AnimatedSize)
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final a in alts)
                _FadeIn(
                  key: ValueKey('alt-${a['m']}'),
                  child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line.withValues(alpha: 0.8)))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // название перевода и «×» — убрать этот перевод у стиха
                    Row(children: [
                      Expanded(child: Text('${a['n']}', style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: pal.muted))),
                      // сразу, без вопроса — с «Отменить»
                      IconBtn(
                        icon: LucideIcons.x,
                        subtle: true,
                        size: 15,
                        tooltip: '${t('Убрать')}: ${a['n']}',
                        onTap: () {
                          final before = [for (final x in alts) {'m': x['m'], 'n': x['n']}];
                          store.setBlockAlts(sermonId, '${block['id']}', [for (final x in before) if (x['m'] != a['m']) x]);
                          showUndo(context, t('Убрано: {ref}', {'ref': '${a['n']}'}), () => store.setBlockAlts(sermonId, '${block['id']}', before));
                        },
                      ),
                    ]),
                    Builder(builder: (_) {
                      final at = [for (final x in (a['t'] as List? ?? const [])) '$x'];
                      // слово подстрочника с номером Стронга — к статье
                      if (a['il'] == true && at.any((x) => x.isNotEmpty)) {
                        return IlWords(pal: pal, texts: at, size: 15.7 * z, onWord: widget.onStrong == null ? null : (k, n) => widget.onStrong!((block['verse'] as int) + k, n));
                      }
                      final text = at.isEmpty ? '…' : at.every((x) => x.isEmpty) ? '—' : at.join(' ');
                      return Text(text, style: verseStyle.copyWith(fontSize: 15.7 * z, color: pal.text.withValues(alpha: 0.85)));
                    }),
                  ]),
                ),
                ),
                ]),
              ),
            ]),
          ),
          // выбор переводов: Библии на устройстве; основной — отмечен и не снимается
          Reveal(
            open: _altOpen,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  // только переводы, где этот стих есть (уже подключённый — чтобы его можно было снять);
                  // первым — основной перевод стиха, за ним подключённые, потом остальные
                  for (final m in [
                    ...ModuleStore.instance.installed.where((m) =>
                        m.type == 'bible' &&
                        m.features['helper'] != true &&
                        (m.id == mainMod || alts.any((a) => a['m'] == m.id) || (verseText(m.id, VerseRef(block['book'] as String, block['chapter'] as int, v0)) ?? '').isNotEmpty)),
                  ]..sort((x, y) => (x.id == mainMod ? 0 : alts.any((a) => a['m'] == x.id) ? 1 : 2).compareTo(y.id == mainMod ? 0 : alts.any((a) => a['m'] == y.id) ? 1 : 2)))
                    AobChip(
                      label: m.name,
                      on: m.id == mainMod || alts.any((a) => a['m'] == m.id),
                      onTap: m.id == mainMod
                          ? null
                          : () => store.setBlockAlts(
                                sermonId,
                                '${block['id']}',
                                alts.any((a) => a['m'] == m.id)
                                    ? [for (final a in alts) if (a['m'] != m.id) {'m': a['m'], 'n': a['n']}]
                                    : [for (final a in alts) {'m': a['m'], 'n': a['n']}, {'m': m.id, 'n': m.name}],
                              ),
                    ),
                ]),
                const SizedBox(height: 4),
                // выбранные здесь переводы — и ко всем новым стихам проповеди (когда подключён хоть один)
                if (alts.isNotEmpty)
                SwitchRow(
                  label: t('Подключать к новым стихам'),
                  value: alts.isNotEmpty && widget.altDefault.map((a) => a['m']).join(',') == alts.map((a) => a['m']).join(','),
                  onChanged: (on) => store.setAltDefault(sermonId, on ? [for (final a in alts) {'m': a['m'], 'n': a['n']}] : []),
                ),
              ]),
            ),
          ),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (note)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(children: [
                      Icon(ico(LucideIcons.stickyNote), size: 13, color: pal.muted),
                      const SizedBox(width: 4),
                      Text(t('Заметка для себя'), style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w600, color: pal.muted)),
                    ]),
                  ),
                _TextBlock(pal: pal, sermonId: sermonId, block: block, fresh: fresh, onDone: onFreshDone, note: note),
              ]),
            ),
            Transform.translate(offset: const Offset(6, -6), child: trash),
          ]),
        // .sermon-block-tools: пунктир сверху, слева — перестановка (⠿ ↑ ↓), корзина справа
        const SizedBox(height: 8),
        DashedLine(color: pal.line),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            _Reorder(pal: pal, onUp: widget.onUp, onDown: widget.onDown),
            const SizedBox(width: 8),
            if (verse && !_picking) ...[
              _ToolPill(pal: pal, icon: LucideIcons.languages, tooltip: t('Переводы'), on: _altOpen || alts.isNotEmpty, onTap: () => setState(() => _altOpen = !_altOpen)),
              const SizedBox(width: 6),
            ],
            Expanded(
              // одна кнопка по ситуации: у полного стиха — «Часть стиха», у части — «Весь стих»
              child: canPick
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: isPart
                          ? _ToolPill(pal: pal, icon: LucideIcons.textQuote, label: t('Весь стих'), onTap: () => store.setPart(sermonId, '${block['id']}', _fullText()!, false))
                          : _ToolPill(pal: pal, icon: LucideIcons.scanText, label: t('Часть стиха'), onTap: _start),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_picking) ...[
              AobButton(label: t('Отмена'), small: true, onTap: () => setState(() => _picking = false)),
              const SizedBox(width: 8),
              AobButton(label: t('Готово'), small: true, kind: BtnKind.primary, onTap: _range == null ? null : _done),
            ],
          ]),
        ),
      ]),
      ),
      if (verse) Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: pal.accent)),
      ]),
    );
  }
}

/// Размер текста проповеди (стихи, переводы, свой текст): 0,8–1,6, запоминается на устройстве (prefs «sermonZoom»)
final sermonZoom = ValueNotifier<double>(((prefs.get('sermonZoom') as num?) ?? 1).toDouble().clamp(0.8, 1.6));

/// «− 100% +» в шапке проповеди: шаг 10 %, нажатие на проценты — снова 100 % (.sermon-zoom веб-версии)
class _SermonZoom extends StatelessWidget {
  const _SermonZoom({required this.pal});
  final Palette pal;
  void _set(double v) {
    sermonZoom.value = (v.clamp(0.8, 1.6) * 10).roundToDouble() / 10;
    prefs.setDouble('sermonZoom', sermonZoom.value);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: sermonZoom,
        builder: (_, z, _) => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: pal.text.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconBtn(icon: LucideIcons.minus, size: 18, tooltip: t('Мельче'), color: z <= 0.8 ? pal.muted.withValues(alpha: 0.4) : null, onTap: z <= 0.8 ? null : () => _set(z - 0.1)),
            Tooltip(
              message: t('Размер текста'),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _set(1),
                child: SizedBox(width: 48, height: 34, child: Center(child: Text('${(z * 100).round()}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])))),
              ),
            ),
            IconBtn(icon: LucideIcons.plus, size: 18, tooltip: t('Крупнее'), color: z >= 1.6 ? pal.muted.withValues(alpha: 0.4) : null, onTap: z >= 1.6 ? null : () => _set(z + 0.1)),
          ]),
        ),
      );
}

/// Плавное проявление при появлении (новый перевод у стиха): прозрачность 0 → 1 за 280 мс
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        builder: (_, v, c) => Opacity(opacity: v, child: c),
        child: child,
      );
}

/// Подстрочник у стиха: слова столбиками — сверху оригинал, под ним перевод; иврит — справа налево
class IlWords extends StatelessWidget {
  const IlWords({super.key, required this.pal, required this.texts, required this.size, this.onWord});
  final Palette pal;
  final List<String> texts;
  final double size;
  final void Function(int verseIndex, String strongNum)? onWord; // слово с номером Стронга — кнопка (k — стих в блоке)
  static final _word = RegExp(r'\{([^|}]*)\|([^|}]*)(?:\|([^|}]*))?(?:\|([^}]*))?\}');

  @override
  Widget build(BuildContext context) {
    final words = [
      for (final (k, x) in texts.indexed)
        for (final m in _word.allMatches(x)) (g: m.group(1) == '·' ? '' : m.group(1) ?? '', o: m.group(4) ?? '', s: m.group(2) ?? '', k: k),
    ];
    final rtl = words.any((w) => RegExp(r'[\u0590-\u05FF]').hasMatch(w.o));
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        for (final w in words)
          Builder(builder: (_) {
            final col = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.o.isEmpty ? ' ' : w.o, style: TextStyle(fontSize: size * (rtl ? 1.12 : 1.02), height: 1.3, color: pal.text, fontFamily: rtl ? 'Noto Serif Hebrew' : null)),
              Text(w.g.isEmpty ? ' ' : w.g, textDirection: TextDirection.ltr, style: TextStyle(fontSize: size * 0.76, height: 1.3, color: pal.muted)),
            ]);
            if (w.s.isEmpty || onWord == null) return col;
            return Tooltip(
              message: w.s,
              child: InkWell(borderRadius: BorderRadius.circular(6), onTap: () => onWord!(w.k, w.s), child: col),
            );
          }),
      ]),
    );
  }
}

/// Свой текст: готовый абзац — просто текст (его можно зажать и перетащить, как стих), нажатие — правка.
/// Пустой (только что добавленный) — сразу поле ввода.
class _TextBlock extends ConsumerStatefulWidget {
  const _TextBlock({required this.pal, required this.sermonId, required this.block, required this.fresh, required this.onDone, this.note = false});
  final Palette pal;
  final String sermonId;
  final Block block;
  final bool fresh, note; // note — заметка для себя
  final VoidCallback onDone;
  @override
  ConsumerState<_TextBlock> createState() => _TextBlockState();
}

class _TextBlockState extends ConsumerState<_TextBlock> {
  bool _edit = false;
  late final _ctl = TextEditingController(text: '${widget.block['text']}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) {
        setState(() => _edit = false);
        widget.onDone();
        // пустой свой текст исчезает сам, когда из него ушли
        if (_ctl.text.trim().isEmpty) ref.read(sermonsProvider.notifier).removeBlock(widget.sermonId, '${widget.block['id']}');
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // «Жирный» / «Курсив»: обернуть выделенное (или поставить пару отметок под курсор); поле остаётся в фокусе
  void _wrap(String mark) {
    final v = _ctl.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, '$mark${v.text.substring(sel.start, sel.end)}$mark');
    _ctl.value = TextEditingValue(text: text, selection: TextSelection(baseOffset: sel.start + mark.length, extentOffset: sel.end + mark.length));
    ref.read(sermonsProvider.notifier).updateBlock(widget.sermonId, '${widget.block['id']}', {'text': text});
    _focus.requestFocus();
  }

  Widget _fmtBtn(IconData icon, String tip, String mark) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => _wrap(mark),
          child: Container(
            width: 30,
            height: 26,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: widget.pal.text.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
            child: Icon(ico(icon), size: 15, color: widget.pal.text),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final text = '${widget.block['text']}';
    if (_ctl.text != text) _ctl.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)); // «Отменить»/«Повторить»
    final editing = _edit || widget.fresh || text.trim().isEmpty;
    final z = sermonZoom.value; // размер текста проповеди («− 100% +» в шапке)
    final style = widget.note
        ? TextStyle(fontSize: 14.7 * z, height: 1.45, fontStyle: FontStyle.italic, color: pal.text.withValues(alpha: 0.75))
        : TextStyle(fontSize: 16 * z, height: 1.5, color: pal.text);
    if (editing) {
      // кнопки оформления — в одной «области» с полем: нажатие по ним не снимает фокус
      return TextFieldTapRegion(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [_fmtBtn(LucideIcons.bold, t('Жирный'), '**'), _fmtBtn(LucideIcons.italic, t('Курсив'), '*')]),
          ),
          TextField(
        controller: _ctl,
        focusNode: _focus,
        autofocus: widget.fresh || _edit,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (v) => ref.read(sermonsProvider.notifier).updateBlock(widget.sermonId, '${widget.block['id']}', {'text': v}),
        style: style,
        decoration: InputDecoration(
          hintText: widget.note ? t('Подсказка себе: пауза, вопрос залу…') : t('Мысль, пояснение, пример…'),
          hintStyle: TextStyle(color: pal.muted),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.only(top: 2),
        ),
      ),
        ]),
      );
    }
    return Semantics(
      button: true,
      label: t('Изменить текст'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
          setState(() => _edit = true);
        },
        child: Padding(padding: const EdgeInsets.only(top: 2), child: Text.rich(TextSpan(children: fmtSpans(text)), style: style)),
      ),
    );
  }
}

// --- Кафедра -------------------------------------------------------------------------------------------

/// «Кафедра»: проповедь крупно, во весь экран, экран не гаснет. Размер букв — кнопками или двумя пальцами.
class Pulpit extends ConsumerStatefulWidget {
  const Pulpit({super.key, required this.sermon});
  final Sermon sermon;
  @override
  ConsumerState<Pulpit> createState() => _PulpitState();
}

class _PulpitState extends ConsumerState<Pulpit> {
  double _size = 26;
  // таймер проповеди: идёт с открытия «Кафедры», нажатие — пауза / продолжить
  final _clock = Stopwatch()..start();
  Timer? _tick;
  final _pts = <int, Offset>{};
  double _d0 = 0, _s0 = 26;

  @override
  void initState() {
    super.initState();
    try {
      final raw = prefs.getString('pulpitSize');
      if (raw != null) _size = (jsonDecode(raw) as num).toDouble().clamp(18, 60).toDouble();
    } catch (_) {}
    keepScreenOn(true);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    keepScreenOn(false);
    super.dispose();
  }

  void _setSize(double v) {
    setState(() => _size = v.clamp(18, 60).roundToDouble());
    prefs.setString('pulpitSize', jsonEncode(_size.round()));
  }

  double _dist() {
    final p = _pts.values.toList();
    return (p[0] - p[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final s = ref.watch(sermonsProvider).where((x) => x['id'] == widget.sermon['id']).firstOrNull ?? widget.sermon;
    final date = _fmtDate('${s['date'] ?? ''}');
    final width = MediaQuery.sizeOf(context).width;
    // .pulpit-body: боковые поля max(20, (100% − 46em) / 2)
    final side = ((width - 46 * _size) / 2).clamp(20.0, double.infinity).toDouble();
    final bottom = MediaQuery.paddingOf(context).bottom + MediaQuery.sizeOf(context).height * 0.4;
    final items = <Widget>[
      // h1: 1.5em, по центру
      Padding(padding: EdgeInsets.only(bottom: _size * 0.9), child: Text('${s['title']}', textAlign: TextAlign.center, style: TextStyle(fontSize: _size * 1.5, fontWeight: FontWeight.w700, height: 1.2, color: pal.text))),
      if ('${s['subtitle'] ?? ''}'.trim().isNotEmpty)
        Padding(padding: EdgeInsets.only(bottom: _size * 0.8), child: Text('${s['subtitle']}'.trim(), textAlign: TextAlign.center, style: TextStyle(fontSize: _size * 0.78, height: 1.4, color: pal.muted))),
      if (date.isNotEmpty) Padding(padding: EdgeInsets.only(bottom: _size * 0.84), child: Text(date, textAlign: TextAlign.center, style: TextStyle(fontSize: _size * 0.7, color: pal.muted))),
      for (final b in blocksOf(s)) ..._block(pal, b),
      // .pulpit-end
      Padding(padding: EdgeInsets.only(top: _size * 0.8 * 2), child: Center(child: Text(t('Аминь'), style: TextStyle(fontSize: _size * 0.8, color: pal.muted)))),
    ];
    return Scaffold(
      backgroundColor: pal.bg,
      body: Column(children: [
        // .pulpit-bar: панель, линия снизу; «мельче», значок «Aa», «крупнее», название по центру, закрыть
        Container(
          padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 6, 10, 6),
          decoration: BoxDecoration(color: pal.panel, border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            IconBtn(icon: LucideIcons.minus, size: 20, tooltip: t('Мельче'), onTap: () => _setSize(_size - 2)),
            const SizedBox(width: 6),
            Icon(ico(LucideIcons.type), size: 18, color: pal.muted),
            const SizedBox(width: 6),
            IconBtn(icon: LucideIcons.plus, size: 20, tooltip: t('Крупнее'), onTap: () => _setSize(_size + 2)),
            const SizedBox(width: 6),
            Expanded(child: Text('${s['title']}', maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
            const SizedBox(width: 6),
            // таймер проповеди: нажатие — пауза / продолжить
            Builder(builder: (_) {
              final sec = _clock.elapsed.inSeconds;
              final clock = '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
              return Tooltip(
                message: _clock.isRunning ? t('Пауза') : t('Продолжить'),
                child: Semantics(
                  label: '${t('Время проповеди')}: $clock',
                  button: true,
                  child: Material(
                    color: pal.text.withValues(alpha: 0.07),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _clock.isRunning ? _clock.stop() : _clock.start()),
                      child: Container(
                        height: 32,
                        constraints: const BoxConstraints(minWidth: 56),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(clock, style: TextStyle(fontSize: 14.4, fontWeight: FontWeight.w600, color: _clock.isRunning ? pal.text : pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 6),
            IconBtn(icon: LucideIcons.x, size: 22, tooltip: t('Закрыть кафедру'), onTap: () => Navigator.of(context).pop()),
          ]),
        ),
        Expanded(
          child: Listener(
            onPointerDown: (e) {
              _pts[e.pointer] = e.position;
              if (_pts.length == 2) {
                _d0 = _dist();
                _s0 = _size;
                setState(() {});
              }
            },
            onPointerMove: (e) {
              if (!_pts.containsKey(e.pointer)) return;
              _pts[e.pointer] = e.position;
              if (_pts.length == 2 && _d0 > 0) _setSize(_s0 * (_dist() / _d0));
            },
            onPointerUp: (e) {
              _pts.remove(e.pointer);
              if (_pts.length < 2) setState(() {});
            },
            onPointerCancel: (e) {
              _pts.remove(e.pointer);
              if (_pts.length < 2) setState(() {});
            },
            // Лениво: при щипке перестраивается только видимое, а не вся проповедь
            child: ListView.builder(
              physics: _pts.length >= 2 ? const NeverScrollableScrollPhysics() : null,
              padding: EdgeInsets.fromLTRB(side, 24, side, bottom),
              itemCount: items.length,
              itemBuilder: (_, i) => items[i],
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _block(Palette pal, Block b) {
    final lh = readerTextStyle(ref.read(settingsProvider), size: _size, weight: 400).copyWith(height: 1.55, color: pal.text); // .pulpit-body: --font-text
    if (isVerse(b)) {
      final tx = verseTexts(b) ?? ['${b['text']}'];
      // .pulpit-verse: отступы 1.1em сверху и снизу; cite — название места акцентом, .78em
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: _size * 1.1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: EdgeInsets.only(bottom: _size * 0.15), child: Text(blockRefFull(b), style: TextStyle(fontSize: _size * 0.78, fontWeight: FontWeight.w700, height: 1.55, color: pal.accent))),
            if (tx.length > 1)
              for (final (i, x) in tx.indexed)
                Padding(
                  padding: EdgeInsets.only(bottom: i < tx.length - 1 ? _size * 0.35 : 0),
                  child: Text.rich(TextSpan(children: [
                    WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: EdgeInsets.only(right: _size * 0.25), child: Opacity(opacity: 0.7, child: Text('${(b['verse'] as int) + i}', style: TextStyle(fontSize: _size * 0.55, fontWeight: FontWeight.w700, color: pal.text))))),
                    TextSpan(text: x),
                  ]), style: lh),
                )
            else
              Text(tx.first, style: lh),
            // подключённые переводы
            for (final a in altsOf(b))
              if ((a['t'] as List? ?? const []).any((x) => '$x'.isNotEmpty))
                Padding(
                  padding: EdgeInsets.only(top: _size * 0.6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['n']}', style: TextStyle(fontSize: _size * 0.6, fontWeight: FontWeight.w700, color: pal.muted)),
                    if (a['il'] == true)
                      IlWords(pal: pal, texts: [for (final x in a['t'] as List) '$x'], size: _size * 0.88)
                    else
                      Text((a['t'] as List).join(' '), style: lh.copyWith(fontSize: _size * 0.88, color: pal.text.withValues(alpha: 0.85))),
                  ]),
                ),
          ]),
        ),
      ];
    }
    final text = '${b['text']}'.trim();
    if (text.isEmpty) return [];
    // .pulpit-note: заметка для себя — мелко, курсивом, с пунктиром слева
    if (b['type'] == 'note') {
      return [
        Container(
          margin: EdgeInsets.symmetric(vertical: _size * 0.6),
          padding: EdgeInsets.only(left: _size * 0.5),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.muted.withValues(alpha: 0.6), width: 2))),
          child: Text.rich(TextSpan(children: fmtSpans(text)), style: TextStyle(fontSize: _size * 0.7, height: 1.45, fontStyle: FontStyle.italic, color: pal.muted)),
        ),
      ];
    }
    return [Padding(padding: EdgeInsets.symmetric(vertical: _size), child: Text.rich(TextSpan(children: fmtSpans(text)), style: lh))];
  }
}


// --- Поиск стихов для проповеди --------------------------------------------------------------------------

/// Выбор стихов для проповеди (SearchPanel в режиме pick): ссылка («Ин 3:16-18», «Пс 22») добавляет все стихи сразу,
/// слова и фразы ищутся по тексту перевода тем же поиском, что и вкладка «Поиск» (часть слова, «целые слова», область).
/// Область и «целые слова» общие с основным поиском (те же ключи searchScope, searchWhole).
class VersePicker extends ConsumerStatefulWidget {
  const VersePicker({super.key, required this.pal, required this.sermonId, required this.moduleId, required this.insertAt, required this.onInsertAt, required this.onDone});
  final Palette pal;
  final String sermonId;
  final String? moduleId;
  final int? insertAt;
  final void Function(int? at) onInsertAt;
  final void Function(String? firstBlockId) onDone; // вернуться к проповеди
  @override
  ConsumerState<VersePicker> createState() => _VersePickerState();
}

T _pref<T>(String key, T def) {
  try {
    final v = prefs.getString(key);
    return v == null ? def : jsonDecode(v) as T;
  } catch (_) {
    return def;
  }
}

class _VersePickerState extends ConsumerState<VersePicker> {
  static const _page = 200;
  final _q = TextEditingController();
  List<SearchHit>? _hits;
  late int? _at = widget.insertAt;
  String _scope = _pref('searchScope', 'all');
  bool _whole = _pref('searchWhole', false);
  int _shown = _page;
  bool _busy = false;
  int _seq = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  bool _has(VerseRef r) {
    final s = ref.read(sermonsProvider).where((x) => x['id'] == widget.sermonId).firstOrNull;
    if (s == null) return false;
    return blocksOf(s).any((b) => isVerse(b) && b['part'] != true && b['book'] == r.book && b['chapter'] == r.chapter && r.verse >= (b['verse'] as int) && r.verse <= ((b['to'] ?? b['verse']) as int));
  }

  String get _curBook => ref.read(panesProvider).firstOrNull?.ref.book ?? 'Gen';

  Set<String>? _books() {
    if (_scope == 'all') return null;
    if (_scope == 'book') return {_curBook};
    return {for (final b in Books.instance.all) if (b.testament == _scope) b.id};
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final mid = widget.moduleId;
    final q = _q.text.trim();
    final seq = ++_seq;
    if (mid == null || q.length < 2 || parseRange(q) != null) {
      setState(() {
        _hits = null;
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    List<SearchHit> found;
    try {
      found = await searchText(mid, q, books: _books(), wholeWord: _whole);
    } catch (_) {
      found = const [];
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _hits = found;
      _shown = _page;
      _busy = false;
    });
  }

  void _option(String key, Object v, VoidCallback apply) {
    setState(apply);
    prefs.setString(key, jsonEncode(v));
    _schedule();
  }

  void _addOne(SearchHit h) {
    final mid = widget.moduleId!;
    final text = verseText(mid, h.ref) ?? h.snippet.replaceAll(RegExp(r'[\[\]]'), '');
    final ids = ref.read(sermonsProvider.notifier).addVerses(widget.sermonId, [VerseItem(h.ref.book, h.ref.chapter, h.ref.verse, text)], mid, at: _at);
    if (_at != null) {
      _at = _at! + ids.length; // следующий найденный — после этого
      widget.onInsertAt(_at);
    }
    toast(context, t('Добавлено в проповедь: {ref}', {'ref': Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse)}));
    setState(() {});
  }

  // Ссылка «Ин 3:16-18» — все стихи вместе (каждый своим абзацем), и обратно к проповеди
  void _addRef() {
    final q = _q.text;
    final items = widget.moduleId == null ? null : versesForRef(widget.moduleId!, q);
    if (items == null || items.isEmpty) return toast(context, t('Такого места нет в выбранном переводе.'));
    final ids = ref.read(sermonsProvider.notifier).addVerses(widget.sermonId, items, widget.moduleId!, at: _at);
    toast(context, t('Добавлено в проповедь: {ref}', {'ref': refRangeLabel(q, parseRange(q)!)}));
    widget.onDone(ids.isEmpty ? null : ids.first);
  }

  // Найденные слова выделены, как в поиске
  Widget _snippet(SearchHit h, RegExp? re, Palette pal) {
    final text = h.snippet.replaceAll(RegExp(r'[\[\]]'), '');
    final style = TextStyle(color: pal.text, height: 1.4);
    if (re == null) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: style);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.end == m.start) continue;
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: TextStyle(backgroundColor: pal.hl)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: spans), maxLines: 3, overflow: TextOverflow.ellipsis, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final range = parseRange(_q.text);
    final hits = _hits;
    final re = _q.text.trim().isEmpty ? null : queryRegex(_q.text.trim(), wholeWord: _whole);
    final count = hits == null ? 0 : (hits.length < _shown ? hits.length : _shown);
    final book = Books.instance.meta(_curBook).short;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: 1 + count + (hits != null && hits.length > _shown ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AobInput(
                controller: _q,
                autofocus: true,
                hint: t('Слово, фраза или ссылка'),
                onChanged: (_) {
                  setState(() {});
                  _schedule();
                },
                onSubmitted: (v) => range != null ? _addRef() : _search(),
              ),
              const SizedBox(height: 12),
              Segmented<String>(
                options: [('all', t('Вся Библия')), ('OT', t('ВЗ')), ('NT', t('НЗ')), ('book', book)],
                value: _scope,
                onChanged: (v) => _option('searchScope', v, () => _scope = v),
              ),
              const SizedBox(height: 12),
              SwitchRow(label: t('Только целые слова'), hint: t('Иначе «свет» найдёт и «светильник»'), value: _whole, onChanged: (v) => _option('searchWhole', v, () => _whole = v)),
              if (range != null) ...[
                const SizedBox(height: 8),
                AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.plus, label: t('Добавить в проповедь: {ref}', {'ref': refRangeLabel(_q.text, range)}), onTap: _addRef),
              ],
              if (hits != null || _busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    if (_busy) ...[const Spinner(size: 14), const SizedBox(width: 6)],
                    Expanded(
                      child: Text(
                        t('Найдено: {n}', {'n': '${hits?.length ?? 0}'}) + (!_busy && (hits?.isEmpty ?? false) ? ' — ${t('попробуйте другую форму слова или отключите «целые слова».')}' : ''),
                        style: TextStyle(fontSize: 14, color: pal.muted),
                      ),
                    ),
                  ]),
                ),
            ]),
          );
        }
        if (i == count + 1) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: AobButton(label: t('Показать ещё ({n})', {'n': '${hits!.length - _shown}'}), wide: true, onTap: () => setState(() => _shown += _page)),
          );
        }
        final h = hits![i - 1];
        final has = _has(h.ref);
        // строка уже от края до края списка (у списка нет полей), отступ 20 — у содержимого, как в остальных окнах
        return InkWell(
          onTap: () => _addOne(h),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse), style: TextStyle(fontWeight: FontWeight.w700, color: pal.accent)),
                  const SizedBox(height: 2),
                  _snippet(h, re, pal),
                ]),
              ),
              const SizedBox(width: 12),
              // добавили — плюс плавно сменяется галочкой
              Tooltip(
                message: has ? t('Уже в проповеди') : t('Добавить в проповедь'),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.fastOutSlowIn,
                  switchOutCurve: Curves.fastOutSlowIn,
                  transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: w)),
                  child: Icon(has ? LucideIcons.check : LucideIcons.plus, key: ValueKey(has), size: 20, color: has ? kOkSoft : pal.muted),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Фон блока проповеди — лёгкий, как у карточек планов.
Color sermonCardBg(Palette pal) => iosPal(pal) ? iosCard(pal) : mix(pal.text, 0.04, pal.panel);
