// Проповеди (SermonsSheet.jsx): список со смахиванием и «Отменить», редактор (стихи и свой текст по порядку; зажать блок —
// перетащить) и «Кафедра» — крупный текст проповеди для чтения на служении, экран при этом не гаснет.
// Размеры и цвета — по styles.css (.sermon-*, .pulpit-*).
import 'dart:async';
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
import '../shell/fonts.dart' show readerTextStyle;
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
    final pal = paletteOf(ref);
    final sermons = ref.watch(sermonsProvider);
    final sermon = sermons.where((s) => s['id'] == _openId).firstOrNull;
    final moduleId = _moduleId;

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
      onBack: canBack ? () => setState(() => _openId = null) : null,
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
              onAddVerse: (at) => setState(() {
                _insertAt = at;
                _scrollTo = null;
                _adding = true;
              }),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
              // .ref-form: поле и кнопка «Создать» в одну строку, промежуток 8
              // IntrinsicHeight: в списке высота не ограничена — stretch тянется до высоты поля
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: PlainInput(controller: _title, hint: t('Название новой проповеди'), onSubmitted: (_) => _create())),
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
                    Icon(LucideIcons.scrollText, size: 28, color: pal.muted),
                    const SizedBox(height: 8),
                    Text(t('Проповедей пока нет'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(t('Создайте проповедь и добавляйте стихи прямо при чтении: зажмите стих → «В проповедь».'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, color: pal.muted, height: 1.45)),
                    ),
                  ]),
                )
              else
                for (final s in sermons)
                  Dismissible(
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
                          const Icon(LucideIcons.trash2, size: 18, color: Colors.white),
                          const SizedBox(height: 3),
                          Text(t('Удалить'), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                    child: SermonRow(pal: pal, sermon: s, onTap: () => setState(() => _openId = '${s['id']}')),
                  ),
            ]),
    );
  }
}

/// Строка проповеди в списке (.sermon-pick-row): значок, название, число мест Писания, дата
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
    return Material(
      color: pal.panel,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            Icon(LucideIcons.scrollText, size: 18, color: pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sermon['title']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 13.1, color: pal.muted)),
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
    _keys.removeWhere((id, _) => !blocks.any((b) => b['id'] == id)); // ключи удалённых блоков не копим
    return ReorderableListView.builder(
      scrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      buildDefaultDragHandles: false, // тянуть — зажав сам блок (как в веб-версии)
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (a, b) => _store.moveBlock(_id, a, b),
      // .sermon-item.dragging: тень 0 14 34, фон панели
      proxyDecorator: (child, i, anim) => Material(
        color: Colors.transparent,
        child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), color: pal.panel, boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 34, offset: Offset(0, 14))]), child: child),
      ),
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // .sermon-head: название (линия снизу) и две кнопки; промежуток 8
        _TitleField(pal: pal, controller: _title, onChanged: (v) => _store.rename(_id, v)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: AobButton(wide: true, kind: BtnKind.primary, icon: LucideIcons.presentation, label: t('Кафедра'), onTap: blocks.isEmpty ? null : _pulpit)),
          const SizedBox(width: 8),
          Expanded(child: AobButton(wide: true, icon: LucideIcons.share2, label: t('Поделиться'), onTap: blocks.isEmpty ? null : _share)),
        ]),
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
          Padding(padding: const EdgeInsets.only(bottom: 12), child: _Inserter(pal: pal, onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: -1)), onVerse: () => widget.onAddVerse(0))),
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
        // .sermon-foot: подпись слева, «удалить проповедь» справа
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(child: Text('${tx('{n} место Писания|{n} места Писания|{n} мест Писания', {'n': verses})} · ${t('сохраняется само')}', style: TextStyle(fontSize: 13.1, color: pal.muted))),
            const SizedBox(width: 10),
            ConfirmIcon(
              linkText: t('удалить проповедь'),
              confirmText: t('Удалить проповедь?'),
              onConfirm: () {
                _store.delete(_id);
                widget.onBackToList();
              },
            ),
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
                onFreshDone: () => _fresh == id ? setState(() => _fresh = null) : null,
                onGo: (v) => _goVerse(b, v),
                onDropVerse: (v) => _dropVerse(b, v),
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
            _Inserter(pal: pal, onText: () => setState(() => _fresh = _store.addTextBlock(_id, after: i)), onVerse: () => widget.onAddVerse(i + 1)),
          ]),
        );
      },
    );
  }
}

/// .sermon-title-input: 1,35rem, жирный, только линия снизу (при вводе — цвета акцента)
class _TitleField extends StatelessWidget {
  const _TitleField({required this.pal, required this.controller, required this.onChanged});
  final Palette pal;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 21.6, fontWeight: FontWeight.w700, color: pal.text),
        decoration: InputDecoration(
          hintText: t('Название проповеди'),
          hintStyle: TextStyle(color: pal.muted),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: pal.line)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: pal.accent)),
        ),
      );
}

/// .sermon-insert: компактная строка между блоками — добавить текст или стих именно сюда; за кнопками — пунктирная линия
class _Inserter extends StatelessWidget {
  const _Inserter({required this.pal, required this.onText, required this.onVerse});
  final Palette pal;
  final VoidCallback onText, onVerse;

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, String tip, VoidCallback f) => Tooltip(
          message: tip,
          child: Material(
            color: pal.bg,
            shape: StadiumBorder(side: BorderSide(color: pal.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: f,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.plus, size: 14, color: pal.accent),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 13.4, fontWeight: FontWeight.w600, color: pal.muted)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(alignment: Alignment.center, children: [
        Positioned(left: 14, right: 14, child: DashedLine(color: pal.line)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn(t('Текст'), t('Добавить текст'), onText), const SizedBox(width: 8), btn(t('Стих'), t('Добавить стих'), onVerse)]),
      ]),
    );
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
    final verseStyle = readerTextStyle(ref.watch(settingsProvider), size: 16.8, weight: 400).copyWith(height: 1.5, color: pal.text); // .sermon-verse-text: --font-text
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (verse) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onGo(v0),
            child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(blockRef(block), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.2, color: pal.accent))),
          ),
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
        ] else
          _TextBlock(pal: pal, sermonId: sermonId, block: block, fresh: fresh, onDone: onFreshDone),
        // .sermon-block-tools: пунктир сверху, «ручка» перетаскивания слева, корзина справа
        const SizedBox(height: 8),
        DashedLine(color: pal.line),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Tooltip(message: t('Зажмите, чтобы перетащить'), child: SizedBox(width: 22, height: 30, child: Align(alignment: Alignment.centerLeft, child: Icon(LucideIcons.gripVertical, size: 17, color: pal.muted)))),
            const Spacer(),
            Transform.translate(
              offset: const Offset(6, 0), // margin-right: -6px
              child: ConfirmIcon(icon: LucideIcons.trash2, size: 16, confirmText: t('Удалить'), tooltip: verse ? t('Удалить стих из проповеди') : t('Удалить текст'), onConfirm: () => store.removeBlock(sermonId, '${block['id']}')),
            ),
          ]),
        ),
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
    final style = TextStyle(fontSize: 16, height: 1.5, color: pal.text);
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
        style: style,
        decoration: InputDecoration(hintText: t('Мысль, пояснение, пример…'), hintStyle: TextStyle(color: pal.muted), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 2)),
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
        child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: style)),
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
            Icon(LucideIcons.type, size: 18, color: pal.muted),
            const SizedBox(width: 6),
            IconBtn(icon: LucideIcons.plus, size: 20, tooltip: t('Крупнее'), onTap: () => _setSize(_size + 2)),
            const SizedBox(width: 6),
            Expanded(child: Text('${s['title']}', maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
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
          ]),
        ),
      ];
    }
    final text = '${b['text']}'.trim();
    return text.isEmpty ? [] : [Padding(padding: EdgeInsets.symmetric(vertical: _size), child: Text(text, style: lh))];
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
        return InkWell(
          onTap: () => _addOne(h),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Tooltip(message: has ? t('Уже в проповеди') : t('Добавить в проповедь'), child: Icon(has ? LucideIcons.check : LucideIcons.plus, size: 20, color: has ? kOkSoft : pal.muted)),
            ]),
          ),
        );
      },
    );
  }
}
