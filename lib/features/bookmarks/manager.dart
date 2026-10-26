// Вкладка «Закладки и заметки» (BookmarksManager.jsx): закладки «продолжить отсюда», любимые стихи, заметки,
// выделения, подборки. Удаление — смахиванием влево или кнопкой, сразу, с «Отменить» в уведомлении.
// «История» — переходы этой панели (←/→ в шапке), последний сверху.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../ui/kit.dart';
import 'marks.dart';
import 'sheets.dart';
import 'ui.dart';

void openBookmarksPage(BuildContext context, WidgetRef ref, int pane) {
  showAobSheet<void>(context, builder: (_) => BookmarksPage(pane: pane), tab: 'saved'); // BookmarksManager.jsx: BottomSheet initial={2}
}

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key, required this.pane});
  final int pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Только числа на вкладках: правка текста заметки или цвета не перестраивает всё окно
    final (nb, nf, nn, nh, nc) = ref.watch(marksProvider.select((m) => (m.bookmarks.length, m.favorites.length, m.notes.length, m.highlights.length, m.collections.length)));
    final nHist = ref.watch(panesProvider.select((l) => l.isEmpty ? 0 : l[pane < l.length ? pane : 0].history.length));
    final tabs = [
      (t('Закладки'), nb),
      (t('Любимые стихи'), nf),
      (t('Заметки'), nn),
      (t('Выделения'), nh),
      (t('Подборки'), nc),
      (t('История'), nHist),
    ];
    // Свой ScaffoldMessenger/Scaffold: уведомление «Отменить» должно быть видно поверх окна, а не под ним
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DefaultTabController(
          length: tabs.length,
          child: AobSheet(
            title: t('Закладки и заметки'),
            scroll: false,
            padding: EdgeInsets.zero,
            child: Column(children: [
              _TabsBar(tabs: tabs),
              Expanded(
                child: TabBarView(children: [
                  _BookmarksTab(pane: pane),
                  _FavoritesTab(pane: pane),
                  _NotesTab(pane: pane),
                  _HighlightsTab(pane: pane),
                  _CollectionsTab(pane: pane),
                  _HistoryTab(pane: pane),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// .tabs: общие вкладки из kit.dart (на всю ширину, число — мельче); выбор — по TabController (и свайпом по содержимому)
class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.tabs});
  final List<(String, int)> tabs;
  @override
  Widget build(BuildContext context) {
    final c = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: c.animation!,
      builder: (_, _) => AobTabs<int>(
        tabs: [for (final (i, (label, n)) in tabs.indexed) (i, label, n)],
        value: c.animation!.value.round(),
        onChanged: c.animateTo,
      ),
    );
  }
}

/// Содержимое вкладки: поля 12/16, между блоками 12 (.sheet-body)
const _bodyPad = EdgeInsets.fromLTRB(16, 12, 16, 20);

/// Перейти к стиху в панели и закрыть вкладку
void _open(BuildContext context, WidgetRef ref, int pane, VerseRef r) {
  final n = ref.read(panesProvider).length;
  ref.read(panesProvider.notifier).navigate(pane < n ? pane : 0, r);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

String _moduleOf(WidgetRef ref, int pane) {
  final l = ref.read(panesProvider);
  return l[pane < l.length ? pane : 0].moduleId;
}

String _full(Map x) => Books.instance.formatRef('${x['book']}', (x['chapter'] as num).toInt(), (x['verse'] as num).toInt(), full: true);

/// Значок + название в заголовке строки (.list-title: значок 14, промежуток 6)
Widget _titleRow(IconData icon, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);

Widget _swatch(Color c) => Container(width: 14, height: 14, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab({required this.pane});
  final int pane;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final n = ref.read(marksProvider.notifier);
    final list = ref.watch(marksProvider.select((m) => m.bookmarks));
    final panes = ref.read(panesProvider);
    final cur = livePositions[pane]?.value ?? panes[pane < panes.length ? pane : 0].ref;
    void drop(Json b) {
      final i = list.indexOf(b);
      n.update((m) => m.copyWith(bookmarks: [for (final x in m.bookmarks) if (x != b) x]));
      undoToast(context, t('Закладка удалена'), () => n.update((m) => m.copyWith(bookmarks: putBack(m.bookmarks, i, b))));
    }

    return ListView(padding: padTabs(context, _bodyPad), children: [
      // .continue-card
      Material(
        color: mix(pal.accent, 0.07, pal.bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: mix(pal.accent, 0.45, pal.line))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context, ref, pane, cur),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(LucideIcons.circlePlay, size: 26, color: pal.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Продолжить чтение'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                  const SizedBox(height: 2),
                  Text('${Books.instance.meta(cur.book).name} ${cur.chapter}:${cur.verse}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: pal.muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        EmptyState(icon: LucideIcons.bookmark, title: t('Закладок пока нет'), text: t('Зажмите стих и нажмите «Закладка».'))
      else
        for (final b in list)
          AobListRow(
            id: 'b${itemKey(b)}${b['at']}',
            title: _titleRow(LucideIcons.bookmark, pal.accent, _full(b)),
            meta: fmtDate(b['at']),
            text: b['text'] as String?,
            deleteLabel: t('Удалить закладку'),
            onTap: () => _open(context, ref, pane, refOf(b)!),
            onDelete: () => drop(b),
          ),
    ]);
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab({required this.pane});
  final int pane;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(marksProvider.notifier);
    final list = ref.watch(marksProvider.select((m) => m.favorites));
    if (list.isEmpty) return ListView(padding: padTabs(context, _bodyPad), children: [EmptyState(icon: LucideIcons.heart, title: t('Любимых стихов пока нет'), text: t('Дважды нажмите на стих — он станет любимым.'))]);
    void drop(Json f) {
      final i = list.indexOf(f);
      n.update((m) => m.copyWith(favorites: [for (final x in m.favorites) if (x != f) x]));
      undoToast(context, t('Убрано из любимых стихов'), () => n.update((m) => m.copyWith(favorites: putBack(m.favorites, i, f, (x) => itemKey(x) == itemKey(f)))));
    }

    return ListView.builder(
      padding: padTabs(context, _bodyPad),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        return AobListRow(
          id: 'f${itemKey(f)}',
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            FillIcon(path: lucideHeartPath, size: 14, color: loveColor, stroke: true),
            const SizedBox(width: 6),
            Flexible(child: Text(_full(f), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          text: f['text'] as String?,
          deleteLabel: t('Убрать из любимых'),
          actionText: t('Убрать'),
          onTap: () => _open(context, ref, pane, refOf(f)!),
          onDelete: () => drop(f),
        );
      },
    );
  }
}

class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab({required this.pane});
  final int pane;
  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  String _q = '';
  final _ctl = TextEditingController();
  static String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final store = ref.read(marksProvider.notifier);
    final notes = ref.watch(marksProvider.select((m) => m.notes));
    final all = <(VerseRef, Json)>[
      for (final e in notes.entries)
        if (parseKey(e.key) != null) (parseKey(e.key)!, e.value as Json),
    ]..sort((a, b) => ((b.$2['updated'] ?? b.$2['at'] ?? 0) as num).compareTo((a.$2['updated'] ?? a.$2['at'] ?? 0) as num));
    if (all.isEmpty) return ListView(padding: padTabs(context, _bodyPad), children: [EmptyState(icon: LucideIcons.notebookPen, title: t('Заметок пока нет'), text: t('Зажмите стих и нажмите «Заметка».'))]);
    final q = _norm(_q.trim());
    final shown = q.isEmpty
        ? all
        : [
            for (final n in all)
              if (_norm('${n.$2['text']} ${n.$2['label']} ${Books.instance.formatRef(n.$1.book, n.$1.chapter, n.$1.verse, full: true)}').contains(q)) n,
          ];

    void drop((VerseRef, Json) x) {
      final key = refKey(x.$1);
      final saved = x.$2;
      store.update((m) => m.copyWith(notes: {...m.notes}..remove(key)));
      undoToast(context, t('Заметка удалена'), () => store.update((m) => m.notes.containsKey(key) ? m : m.copyWith(notes: {...m.notes, key: saved})));
    }

    final searching = all.length > 3;
    return ListView.builder(
      padding: padTabs(context, _bodyPad),
      itemCount: shown.length + (searching ? 1 : 0),
      itemBuilder: (_, k) {
        if (searching && k == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AobInput(controller: _ctl, hint: t('Поиск по заметкам'), onChanged: (v) => setState(() => _q = v)),
          );
        }
        final n = shown[searching ? k - 1 : k];
        final label = (n.$2['label'] as String?)?.isNotEmpty == true ? n.$2['label'] as String : Books.instance.formatRef(n.$1.book, n.$1.chapter, n.$1.verse, full: true);
        return AobListRow(
          id: 'n${refKey(n.$1)}',
          title: _titleRow(LucideIcons.notebookPen, pal.accent, label),
          meta: fmtDate(n.$2['updated'] ?? n.$2['at']),
          text: n.$2['text'] as String?,
          deleteLabel: t('Удалить заметку'),
          onTap: () => _open(context, ref, widget.pane, n.$1),
          onDelete: () => drop(n),
          extra: [IconBtn(icon: LucideIcons.notebookPen, subtle: true, size: 16, tooltip: t('Изменить заметку'), onTap: () => showNoteSheet(context, [n.$1], _moduleOf(ref, widget.pane), pane: widget.pane))],
        );
      },
    );
  }
}

class _HighlightsTab extends ConsumerStatefulWidget {
  const _HighlightsTab({required this.pane});
  final int pane;
  @override
  ConsumerState<_HighlightsTab> createState() => _HighlightsTabState();
}

class _HighlightsTabState extends ConsumerState<_HighlightsTab> {
  String _color = 'all';

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final store = ref.read(marksProvider.notifier);
    final (highlights, hlLabels) = ref.watch(marksProvider.select((m) => (m.highlights, m.hlLabels)));
    if (highlights.isEmpty) return ListView(padding: padTabs(context, _bodyPad), children: [EmptyState(icon: LucideIcons.highlighter, title: t('Выделений пока нет'), text: t('Зажмите стих и нажмите маркер.'))]);
    final counts = <String, int>{};
    for (final c in highlights.values) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final list = [
      for (final e in highlights.entries)
        if (parseKey(e.key) != null && (_color == 'all' || e.value == _color)) (parseKey(e.key)!, e.value),
    ]..sort((a, b) => byBible(a.$1, b.$1));
    final module = _moduleOf(ref, widget.pane);
    String label(HlColor c) => hlLabels[c.id]?.trim().isNotEmpty == true ? hlLabels[c.id]!.trim() : t(c.name);

    void unmark((VerseRef, String) x) {
      store.setHighlight([x.$1], null);
      undoToast(context, t('Выделение убрано'), () => store.setHighlight([x.$1], x.$2));
    }

    return Column(children: [
      // .filter-chips: одна строка, прокручивается вбок, поля 16
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(children: [
          AobChip(label: t('Все'), on: _color == 'all', onTap: () => setState(() => _color = 'all')),
          for (final c in hlColors)
            if (counts[c.id] != null) ...[
              const SizedBox(width: 6),
              _ColorChip(color: c.color, label: label(c), count: counts[c.id]!, on: _color == c.id, onTap: () => setState(() => _color = c.id)),
            ],
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: padTabs(context, _bodyPad),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final x = list[i];
            final r = x.$1;
            return AobListRow(
              id: 'h${refKey(r)}',
              title: Row(mainAxisSize: MainAxisSize.min, children: [
                _swatch(hlColor(x.$2)?.color ?? pal.line),
                const SizedBox(width: 6),
                Flexible(child: Text(Books.instance.formatRef(r.book, r.chapter, r.verse, full: true), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              text: i < 200 ? verseText(module, r) : null,
              deleteLabel: t('Убрать выделение'),
              actionText: t('Убрать'),
              onTap: () => _open(context, ref, widget.pane, r),
              onDelete: () => unmark(x),
            );
          },
        ),
      ),
    ]);
  }
}

/// .chip с цветным кружком (.hl-swatch) перед названием — AobChip такого не умеет
class _ColorChip extends ConsumerWidget {
  const _ColorChip({required this.color, required this.label, required this.count, required this.on, required this.onTap});
  final Color color;
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    // выбор — плавно: фон, рамка и надпись перетекают в цвет акцента
    return TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.fastOutSlowIn,
      builder: (context, v, _) {
        final fg = Color.lerp(pal.text, pal.onAccent, v)!;
        return Material(
          animationDuration: Duration.zero,
          color: Color.lerp(pal.bg, pal.accent, v),
          shape: StadiumBorder(side: BorderSide(color: Color.lerp(pal.line, pal.accent, v)!)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _swatch(color),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 13.8, color: fg)),
                const SizedBox(width: 5),
                Text('$count', style: TextStyle(fontSize: 11, color: Color.lerp(pal.muted, fg.withValues(alpha: 0.8), v))),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _CollectionsTab extends ConsumerStatefulWidget {
  const _CollectionsTab({required this.pane});
  final int pane;
  @override
  ConsumerState<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends ConsumerState<_CollectionsTab> {
  String? _cur;

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final cols = ref.watch(marksProvider.select((m) => m.collections));
    final n = ref.read(marksProvider.notifier);
    if (cols.isEmpty) return ListView(padding: padTabs(context, _bodyPad), children: [EmptyState(icon: LucideIcons.folder, title: t('Подборок пока нет'), text: t('Зажмите стих → «⋯» → «В подборку…».'))]);
    final c = cols.where((x) => x['id'] == _cur).firstOrNull;

    void dropItem(Json c, Json x) {
      final items = (c['items'] as List).cast<Json>();
      final i = items.indexOf(x);
      void set(List<Json> Function(List<Json>) f) => n.update((m) => m.copyWith(collections: [for (final y in m.collections) y['id'] == c['id'] ? {...y, 'items': f((y['items'] as List).cast<Json>())} : y]));
      set((l) => [for (final it in l) if (it != x) it]);
      undoToast(context, t('Убрано из подборки'), () => set((l) => putBack(l, i, x)));
    }

    void dropCollection(Json x) {
      final i = cols.indexOf(x);
      n.update((m) => m.copyWith(collections: [for (final y in m.collections) if (y['id'] != x['id']) y]));
      undoToast(context, t('Подборка «{name}» удалена', {'name': '${x['name']}'}), () => n.update((m) => m.copyWith(collections: putBack(m.collections, i, x, (y) => y['id'] == x['id']))));
    }

    if (c != null) {
      final items = [...(c['items'] as List).cast<Json>()]..sort((a, b) => byBible(refOf(a)!, refOf(b)!));
      return ListView(padding: padTabs(context, _bodyPad), children: [
        Align(alignment: Alignment.centerLeft, child: AobButton(small: true, icon: LucideIcons.chevronLeft, label: t('Все подборки'), onTap: () => setState(() => _cur = null))),
        const SizedBox(height: 12),
        GroupTitle('${c['name']} · ${items.length}'),
        for (final x in items)
          AobListRow(
            id: 'ci${c['id']}${itemKey(x)}',
            title: Text(_full(x), maxLines: 1, overflow: TextOverflow.ellipsis),
            text: x['text'] as String?,
            deleteLabel: t('Убрать из подборки'),
            actionText: t('Убрать'),
            onTap: () => _open(context, ref, widget.pane, refOf(x)!),
            onDelete: () => dropItem(c, x),
          ),
      ]);
    }
    return ListView.builder(
      padding: padTabs(context, _bodyPad),
      itemCount: cols.length,
      itemBuilder: (_, i) {
        final x = cols[i];
        return AobListRow(
          id: 'c${x['id']}',
          title: _titleRow(LucideIcons.folder, pal.accent, '${x['name']}'),
          meta: t('{n} ст.', {'n': '${(x['items'] as List).length}'}),
          metaRight: true,
          deleteLabel: t('Удалить подборку'),
          onTap: () => setState(() => _cur = '${x['id']}'),
          onDelete: () => dropCollection(x),
        );
      },
    );
  }
}

/// История переходов панели (BookmarksManager.jsx, tab === 'history'): новые сверху, текущее место — «сейчас»
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.pane});
  final int pane;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final p = ref.watch(panesProvider.select((l) => l[pane < l.length ? pane : 0]));
    final i0 = pane < ref.read(panesProvider).length ? pane : 0;
    final items = [for (var i = p.history.length - 1; i >= 0; i--) (p.history[i], i)];
    return ListView.builder(
      padding: padTabs(context, _bodyPad),
      itemCount: items.length,
      itemBuilder: (_, k) {
        final (r, i) = items[k];
        final cur = i == p.hIndex;
        // строка — от края до края окна, отступ 20 — у содержимого
        return bleed(InkWell(
            // «go» на нужное число шагов от текущего места: окно закрывается, панель переходит
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              ref.read(panesProvider.notifier).go(i0, i - p.hIndex);
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
              child: Row(children: [
                Icon(LucideIcons.history, size: 16, color: cur ? pal.accent : pal.text),
                const SizedBox(width: 10),
                Expanded(child: Text(_full({'book': r.book, 'chapter': r.chapter, 'verse': r.verse}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: cur ? FontWeight.w600 : FontWeight.w500, color: cur ? pal.accent : pal.text))),
                if (cur) Text(t('сейчас'), style: TextStyle(fontSize: 13.1, color: pal.muted)),
              ]),
            ),
        ));
      },
    );
  }
}
