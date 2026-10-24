// Проповеди (SermonsSheet.jsx): список со смахиванием и «Отменить», редактор (стихи и свой текст по порядку; зажать блок —
// перетащить) и «Кафедра» — крупный текст проповеди для чтения на служении, экран при этом не гаснет.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../plans/loc.dart';
import '../plans/ui_kit.dart';
import '../plans/verse_text.dart';
import 'screen_on.dart';
import 'sermon_store.dart';

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

  @override
  void initState() {
    super.initState();
    _openId = widget.open;
    ensureDict();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

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
    final pal = ref.watch(settingsProvider).palette;
    final sermons = ref.watch(sermonsProvider);
    final sermon = sermons.where((s) => s['id'] == _openId).firstOrNull;
    final moduleId = _moduleId;

    if (sermon != null && _adding) {
      return PageFrame(
        pal: pal,
        title: t('Добавить стих'),
        subtitle: '${sermon['title']}',
        onBack: () => setState(() => _adding = false),
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
    return PageFrame(
      pal: pal,
      title: sermon != null ? t('Проповедь') : t('Проповеди'),
      onBack: canBack ? () => setState(() => _openId = null) : null,
      child: sermon != null
          ? _Editor(
              key: ValueKey(sermon['id']),
              pal: pal,
              sermon: sermon,
              pane: widget.pane,
              moduleId: moduleId,
              scrollTo: _scrollTo,
              onBackToList: () => setState(() => _openId = null),
              onAddVerse: (at) => setState(() {
                _insertAt = at;
                _scrollTo = null;
                _adding = true;
              }),
            )
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    style: TextStyle(color: pal.text),
                    decoration: InputDecoration(hintText: t('Название новой проповеди'), filled: true, fillColor: pal.bg, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: pal.line))),
                  ),
                ),
                const SizedBox(width: 8),
                Pill(pal: pal, primary: true, icon: Icons.add, label: t('Создать'), onTap: _create),
              ]),
              const SizedBox(height: 16),
              if (sermons.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(children: [
                    Icon(Icons.article_outlined, size: 44, color: pal.muted),
                    const SizedBox(height: 10),
                    Text(t('Проповедей пока нет'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
                    const SizedBox(height: 6),
                    Text(t('Создайте проповедь и добавляйте стихи прямо при чтении: зажмите стих → «В проповедь».'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted, height: 1.4)),
                  ]),
                )
              else
                for (final s in sermons)
                  Dismissible(
                    key: ValueKey('${s['id']}'),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _remove(s),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(color: const Color(0xFFD64545), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    child: SermonRow(pal: pal, sermon: s, onTap: () => setState(() => _openId = '${s['id']}')),
                  ),
            ]),
    );
  }
}

/// Строка проповеди в списке: название, число мест Писания, дата
class SermonRow extends StatelessWidget {
  const SermonRow({super.key, required this.pal, required this.sermon, required this.onTap, this.trailing, this.enabled = true, this.shortDate = false});
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(Icons.article_outlined, size: 20, color: pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sermon['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                Text(sub, style: TextStyle(fontSize: 12.5, color: pal.muted)),
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
  const _Editor({super.key, required this.pal, required this.sermon, required this.pane, required this.moduleId, required this.onBackToList, required this.onAddVerse, this.scrollTo});
  final Palette pal;
  final Sermon sermon;
  final int pane;
  final String? moduleId;
  final String? scrollTo;
  final VoidCallback onBackToList;
  final void Function(int? at) onAddVerse;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  String? _fresh; // только что добавленный текстовый блок — сразу в него курсор
  late final _title = TextEditingController(text: '${widget.sermon['title']}');
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
    _scroll.dispose();
    super.dispose();
  }

  SermonsNotifier get _store => ref.read(sermonsProvider.notifier);

  // Нажатие на стих — к этому стиху в Библии
  void _goVerse(Block b, int verse) {
    Navigator.of(context).pop();
    ref.read(panesProvider.notifier).navigate(widget.pane, VerseRef(b['book'] as String, b['chapter'] as int, verse));
  }

  // Убрать стих (из диапазона — только его; диапазон делится на части) — с «Отменить»
  void _dropVerse(Block b, int verse) {
    final before = blocksOf(widget.sermon);
    final one = b['to'] == null || b['to'] == b['verse'] || verseTexts(b) == null;
    _store.removeVerse(_id, '${b['id']}', verse);
    showUndo(context, t('Убрано: {ref}', {'ref': one ? blockRef(b) : blockRef({...b, 'verse': verse, 'to': null})}), () => _store.restoreBlocks(_id, before));
  }

  Future<void> _share() => SharePlus.instance.share(ShareParams(text: sermonText(widget.sermon), title: '${widget.sermon['title']}'));

  void _pulpit() => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => Pulpit(sermon: widget.sermon)));

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    // Свежая версия проповеди из хранилища (редактор живёт, пока открыт)
    final sermon = ref.watch(sermonsProvider).where((s) => s['id'] == widget.sermon['id']).firstOrNull ?? widget.sermon;
    final blocks = blocksOf(sermon);
    final verses = blocks.where(isVerse).length;
    return ReorderableListView.builder(
      scrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      buildDefaultDragHandles: false, // тянуть — зажав сам блок (как в веб-версии)
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (a, b) => _store.moveBlock(_id, a, b),
      proxyDecorator: (child, i, anim) => Material(color: Colors.transparent, elevation: 6, borderRadius: BorderRadius.circular(14), child: child),
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _title,
          onChanged: (v) => _store.rename(_id, v),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.text),
          decoration: InputDecoration(hintText: t('Название проповеди'), border: InputBorder.none, isDense: true),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Pill(pal: pal, primary: true, icon: Icons.slideshow, label: t('Кафедра'), onTap: blocks.isEmpty ? null : _pulpit)),
          const SizedBox(width: 8),
          Expanded(child: Pill(pal: pal, icon: Icons.share_outlined, label: t('Поделиться'), onTap: blocks.isEmpty ? null : _share)),
        ]),
        const SizedBox(height: 12),
        if (blocks.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: mix(pal.bg, pal.accent, 0.08), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${t('Как добавить стих:')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: t('зажмите стих в Библии и нажмите «В проповедь» — или найдите его кнопкой «Стих» ниже.')),
              ]), style: TextStyle(color: pal.text, height: 1.4)),
              const SizedBox(height: 8),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${t('Свой текст')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: t('— кнопка «Текст». Чтобы переставить блок, зажмите его и тяните.')),
              ]), style: TextStyle(color: pal.text, height: 1.4)),
            ]),
          )
        else
          _Inserter(pal: pal, onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: -1)), onVerse: () => widget.onAddVerse(0)),
      ]),
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Expanded(child: Pill(pal: pal, icon: Icons.add, label: t('Текст'), onTap: () => setState(() => _fresh = _store.addTextBlock(_id)))),
              const SizedBox(width: 8),
              Expanded(child: Pill(pal: pal, icon: Icons.search, label: t('Стих'), onTap: () => widget.onAddVerse(null))),
            ]),
          ),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text('${tx('{n} место Писания|{n} места Писания|{n} мест Писания', {'n': verses})} · ${t('сохраняется само')}', style: TextStyle(fontSize: 12.5, color: pal.muted)),
          ConfirmIcon(
            pal: pal,
            linkText: t('удалить проповедь'),
            confirmText: t('Удалить проповедь?'),
            onConfirm: () {
              _store.delete(_id);
              widget.onBackToList();
            },
          ),
        ]),
      ]),
      itemCount: blocks.length,
      itemBuilder: (_, i) {
        final b = blocks[i];
        final id = '${b['id']}';
        return ReorderableDelayedDragStartListener(
          key: ValueKey(id),
          index: i,
          child: Column(key: _keys.putIfAbsent(id, GlobalKey.new), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: _flash == id ? pal.hl.withValues(alpha: 0.6) : Colors.transparent),
                child: _BlockCard(
                  pal: pal,
                  block: b,
                  fresh: _fresh == id,
                  sermonId: _id,
                  onFreshDone: () => _fresh == id ? setState(() => _fresh = null) : null,
                  onGo: (v) => _goVerse(b, v),
                  onDropVerse: (v) => _dropVerse(b, v),
                ),
              ),
            ),
            _Inserter(pal: pal, onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: i)), onVerse: () => widget.onAddVerse(i + 1)),
          ]),
        );
      },
    );
  }
}

/// Компактная строка между блоками: добавить текст или стих именно сюда
class _Inserter extends StatelessWidget {
  const _Inserter({required this.pal, required this.onText, required this.onVerse});
  final Palette pal;
  final VoidCallback onText, onVerse;

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, String tip, VoidCallback f) => TextButton.icon(
          onPressed: f,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: pal.muted, padding: const EdgeInsets.symmetric(horizontal: 10)),
          icon: const Icon(Icons.add, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 13)),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn(t('Текст'), t('Добавить текст'), onText), btn(t('Стих'), t('Добавить стих'), onVerse)]);
  }
}

class _BlockCard extends ConsumerWidget {
  const _BlockCard({required this.pal, required this.block, required this.sermonId, required this.fresh, required this.onFreshDone, required this.onGo, required this.onDropVerse});
  final Palette pal;
  final Block block;
  final String sermonId;
  final bool fresh;
  final VoidCallback onFreshDone;
  final void Function(int verse) onGo;
  final void Function(int verse) onDropVerse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(sermonsProvider.notifier);
    final verse = isVerse(block);
    final texts = verse ? verseTexts(block) : null;
    final group = texts != null && texts.length > 1;
    final v0 = (block['verse'] ?? 0) as int;
    // Старый диапазон, который не удалось разбить, — одним абзацем, как раньше
    final lines = texts != null ? [for (final (k, x) in texts.indexed) (v: v0 + k, text: x)] : verse ? [(v: v0, text: '${block['text']}')] : <({int v, String text})>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
      decoration: BoxDecoration(color: verse ? mix(pal.bg, pal.accent, 0.05) : pal.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (verse) ...[
          GestureDetector(
            onTap: () => onGo(v0),
            child: Padding(padding: const EdgeInsets.only(bottom: 4, right: 8), child: Text(blockRef(block), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: pal.accent))),
          ),
          for (final l in lines)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onGo(l.v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(TextSpan(children: [
                      if (group) WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: const EdgeInsets.only(right: 4), child: Text('${l.v}', style: TextStyle(fontSize: 10.5, color: pal.verseNum, fontWeight: FontWeight.w700)))),
                      TextSpan(text: l.text),
                    ]), style: TextStyle(fontSize: 16.5, height: 1.4, color: pal.text)),
                  ),
                ),
              ),
              if (group) ConfirmIcon(pal: pal, icon: Icons.close, size: 16, confirmText: t('Убрать'), tooltip: t('Убрать стих'), onConfirm: () => onDropVerse(l.v)),
            ]),
        ] else
          _TextBlock(pal: pal, sermonId: sermonId, block: block, fresh: fresh, onDone: onFreshDone),
        Row(children: [
          Tooltip(message: t('Зажмите, чтобы перетащить'), child: Icon(Icons.drag_indicator, size: 18, color: pal.muted.withValues(alpha: 0.6))),
          const Spacer(),
          ConfirmIcon(pal: pal, icon: Icons.delete_outline, size: 18, confirmText: t('Удалить'), tooltip: verse ? t('Удалить стих из проповеди') : t('Удалить текст'), onConfirm: () => store.removeBlock(sermonId, '${block['id']}')),
        ]),
      ]),
    );
  }
}

/// Свой текст: готовый абзац — просто текст (его можно зажать и перетащить, как стих), нажатие — правка.
/// Пустой (только что добавленный) — сразу поле ввода.
class _TextBlock extends ConsumerStatefulWidget {
  const _TextBlock({required this.pal, required this.sermonId, required this.block, required this.fresh, required this.onDone});
  final Palette pal;
  final String sermonId;
  final Block block;
  final bool fresh;
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
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final text = '${widget.block['text']}';
    final editing = _edit || widget.fresh || text.trim().isEmpty;
    if (editing) {
      return TextField(
        controller: _ctl,
        focusNode: _focus,
        autofocus: widget.fresh || _edit,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (v) => ref.read(sermonsProvider.notifier).updateBlock(widget.sermonId, '${widget.block['id']}', {'text': v}),
        style: TextStyle(fontSize: 16.5, height: 1.4, color: pal.text),
        decoration: InputDecoration(hintText: t('Мысль, пояснение, пример…'), border: InputBorder.none, isDense: true),
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
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text, style: TextStyle(fontSize: 16.5, height: 1.4, color: pal.text))),
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
  }

  @override
  void dispose() {
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
    final pal = ref.watch(settingsProvider).palette;
    final s = ref.watch(sermonsProvider).where((x) => x['id'] == widget.sermon['id']).firstOrNull ?? widget.sermon;
    final date = _fmtDate('${s['date'] ?? ''}');
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bar,
        foregroundColor: pal.barText,
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        title: Row(children: [
          IconButton(tooltip: t('Мельче'), icon: const Icon(Icons.remove), onPressed: () => _setSize(_size - 2)),
          const Icon(Icons.text_fields, size: 18),
          IconButton(tooltip: t('Крупнее'), icon: const Icon(Icons.add), onPressed: () => _setSize(_size + 2)),
          Expanded(child: Text('${s['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        actions: [IconButton(tooltip: t('Закрыть кафедру'), icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())],
      ),
      body: Listener(
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
        child: ListView(
          physics: _pts.length >= 2 ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 80),
          children: [
            Text('${s['title']}', style: TextStyle(fontSize: _size * 1.25, fontWeight: FontWeight.w800, height: 1.25, color: pal.text)),
            if (date.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(date, style: TextStyle(fontSize: _size * 0.6, color: pal.muted))),
            const SizedBox(height: 14),
            for (final b in blocksOf(s)) ..._block(pal, b),
            Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Text(t('Аминь'), style: TextStyle(fontSize: _size, fontStyle: FontStyle.italic, color: pal.muted)))),
          ],
        ),
      ),
    );
  }

  List<Widget> _block(Palette pal, Block b) {
    if (isVerse(b)) {
      final tx = verseTexts(b) ?? ['${b['text']}'];
      return [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.accent, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(blockRefFull(b), style: TextStyle(fontSize: _size * 0.62, fontWeight: FontWeight.w800, color: pal.accent)),
            const SizedBox(height: 4),
            if (tx.length > 1)
              for (final (i, x) in tx.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(children: [
                    WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: const EdgeInsets.only(right: 4), child: Text('${(b['verse'] as int) + i}', style: TextStyle(fontSize: _size * 0.5, color: pal.verseNum, fontWeight: FontWeight.w700)))),
                    TextSpan(text: x),
                  ]), style: TextStyle(fontSize: _size, height: 1.4, color: pal.text)),
                )
            else
              Text(tx.first, style: TextStyle(fontSize: _size, height: 1.4, color: pal.text)),
          ]),
        ),
      ];
    }
    final text = '${b['text']}'.trim();
    return text.isEmpty ? [] : [Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text, style: TextStyle(fontSize: _size, height: 1.45, color: pal.text)))];
  }
}

// --- Поиск стихов для проповеди --------------------------------------------------------------------------

/// Выбор стихов для проповеди: ссылка («Ин 3:16-18», «Пс 22») добавляет все стихи сразу, слова ищутся по всему переводу.
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

class _VersePickerState extends ConsumerState<VersePicker> {
  final _q = TextEditingController();
  List<SearchHit> _hits = const [];
  late int? _at = widget.insertAt;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _has(VerseRef r) {
    final s = ref.read(sermonsProvider).where((x) => x['id'] == widget.sermonId).firstOrNull;
    if (s == null) return false;
    return blocksOf(s).any((b) => isVerse(b) && b['part'] != true && b['book'] == r.book && b['chapter'] == r.chapter && r.verse >= (b['verse'] as int) && r.verse <= ((b['to'] ?? b['verse']) as int));
  }

  void _search(String q) {
    final mid = widget.moduleId;
    if (mid == null || q.trim().length < 2 || parseRange(q) != null) return setState(() => _hits = const []);
    setState(() => _hits = search(mid, q, limit: 150));
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

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final range = parseRange(_q.text);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _search,
          onSubmitted: (v) => range != null ? _addRef() : _search(v),
          style: TextStyle(color: pal.text),
          decoration: InputDecoration(
            hintText: t('Слово, фраза или ссылка'),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: pal.bg,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: pal.line)),
          ),
        ),
      ),
      if (range != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Pill(pal: pal, primary: true, expand: true, icon: Icons.add, label: t('Добавить в проповедь: {ref}', {'ref': refRangeLabel(_q.text, range)}), onTap: _addRef),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: _hits.length,
          itemBuilder: (_, i) {
            final h = _hits[i];
            final has = _has(h.ref);
            return ListTile(
              dense: true,
              title: Text(Books.instance.formatRef(h.ref.book, h.ref.chapter, h.ref.verse), style: TextStyle(fontWeight: FontWeight.w800, color: pal.accent)),
              subtitle: Text(h.snippet.replaceAll(RegExp(r'[\[\]]'), ''), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text)),
              trailing: Icon(has ? Icons.check_circle : Icons.add_circle_outline, color: has ? const Color(0xFF3AA66B) : pal.muted),
              onTap: () => _addOne(h),
            );
          },
        ),
      ),
    ]);
  }
}
