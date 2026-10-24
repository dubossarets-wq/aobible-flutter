// Вкладка «Закладки и заметки» (BookmarksManager.jsx): закладки «продолжить отсюда», любимые стихи, заметки,
// выделения, подборки. Удаление — смахиванием влево или кнопкой, сразу, с «Отменить» в уведомлении.
// Вкладки «История» здесь нет: в приложении на Flutter история переходов по панелям пока не ведётся.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import 'marks.dart';
import 'sheets.dart';
import 'ui.dart';

void openBookmarksPage(BuildContext context, WidgetRef ref, int pane) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookmarksPage(pane: pane)));
}

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key, required this.pane});
  final int pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    final m = ref.watch(marksProvider);
    final tabs = [
      (t('Закладки'), m.bookmarks.length),
      (t('Любимые стихи'), m.favorites.length),
      (t('Заметки'), m.notes.length),
      (t('Выделения'), m.highlights.length),
      (t('Подборки'), m.collections.length),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bar,
          foregroundColor: pal.barText,
          title: Text(t('Закладки и заметки')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: pal.barText,
            unselectedLabelColor: pal.barText.withValues(alpha: 0.65),
            indicatorColor: pal.barText,
            tabs: [
              for (final (l, n) in tabs) Tab(child: Row(children: [Text(l), const SizedBox(width: 6), Text('$n', style: const TextStyle(fontSize: 12))])),
            ],
          ),
        ),
        body: TabBarView(children: [
          _BookmarksTab(pane: pane),
          _FavoritesTab(pane: pane),
          _NotesTab(pane: pane),
          _HighlightsTab(pane: pane),
          _CollectionsTab(pane: pane),
        ]),
      ),
    );
  }
}

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

/// Строка списка, которую можно смахнуть влево
class _Row extends StatelessWidget {
  const _Row({required this.id, required this.pal, required this.title, this.meta, this.text, required this.onTap, required this.onDelete, required this.deleteLabel, this.extra = const []});
  final Object id;
  final Palette pal;
  final Widget title;
  final String? meta, text;
  final VoidCallback onTap, onDelete;
  final String deleteLabel;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey(id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          color: Colors.red.shade600,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.delete_outline, color: Colors.white), const SizedBox(width: 6), Text(t('Удалить'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
        ),
        child: Material(
          color: pal.bg,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: title), if (meta != null) Text(meta!, style: TextStyle(fontSize: 12, color: pal.muted))]),
                    if (text != null && text!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(text!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, height: 1.3))),
                  ]),
                ),
                ...extra,
                IconButton(tooltip: deleteLabel, icon: Icon(Icons.delete_outline, size: 20, color: pal.muted), onPressed: onDelete),
              ]),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.title, this.hint, this.pal);
  final IconData icon;
  final String title, hint;
  final Palette pal;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: pal.muted),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 4),
            Text(hint, textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
          ]),
        ),
      );
}

Widget _titleRow(Palette pal, IconData icon, Color color, String text) => Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
    ]);

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab({required this.pane});
  final int pane;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    final n = ref.read(marksProvider.notifier);
    final list = ref.watch(marksProvider.select((m) => m.bookmarks));
    final panes = ref.read(panesProvider);
    final cur = livePositions[pane]?.value ?? panes[pane < panes.length ? pane : 0].ref;
    void drop(Json b) {
      final i = list.indexOf(b);
      n.update((m) => m.copyWith(bookmarks: [for (final x in m.bookmarks) if (x != b) x]));
      undoToast(context, t('Закладка удалена'), () => n.update((m) => m.copyWith(bookmarks: putBack(m.bookmarks, i, b))));
    }

    return ListView(children: [
      InkWell(
        onTap: () => _open(context, ref, pane, cur),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.play_circle_outline, size: 28, color: pal.accent),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Продолжить чтение'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              Text('${Books.instance.meta(cur.book).name} ${cur.chapter}:${cur.verse}', style: TextStyle(color: pal.muted)),
            ]),
          ]),
        ),
      ),
      if (list.isEmpty)
        SizedBox(height: 260, child: _Empty(Icons.bookmark_border, t('Закладок пока нет'), t('Зажмите стих и нажмите «Закладка».'), pal))
      else
        for (final b in list)
          _Row(
            id: 'b${itemKey(b)}${b['at']}',
            pal: pal,
            title: _titleRow(pal, Icons.bookmark, pal.accent, _full(b)),
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
    final pal = ref.watch(settingsProvider).palette;
    final n = ref.read(marksProvider.notifier);
    final list = ref.watch(marksProvider.select((m) => m.favorites));
    if (list.isEmpty) return _Empty(Icons.favorite_border, t('Любимых стихов пока нет'), t('Дважды нажмите на стих — он станет любимым.'), pal);
    void drop(Json f) {
      final i = list.indexOf(f);
      n.update((m) => m.copyWith(favorites: [for (final x in m.favorites) if (x != f) x]));
      undoToast(context, t('Убрано из любимых стихов'), () => n.update((m) => m.copyWith(favorites: putBack(m.favorites, i, f, (x) => itemKey(x) == itemKey(f)))));
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        return _Row(
          id: 'f${itemKey(f)}',
          pal: pal,
          title: _titleRow(pal, Icons.favorite, loveColor, _full(f)),
          text: f['text'] as String?,
          deleteLabel: t('Убрать из любимых'),
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
  static String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е');

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final store = ref.read(marksProvider.notifier);
    final notes = ref.watch(marksProvider.select((m) => m.notes));
    final all = <(VerseRef, Json)>[
      for (final e in notes.entries)
        if (parseKey(e.key) != null) (parseKey(e.key)!, e.value as Json),
    ]..sort((a, b) => ((b.$2['updated'] ?? b.$2['at'] ?? 0) as num).compareTo((a.$2['updated'] ?? a.$2['at'] ?? 0) as num));
    if (all.isEmpty) return _Empty(Icons.edit_note, t('Заметок пока нет'), t('Зажмите стих и нажмите «Заметка».'), pal);
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

    return Column(children: [
      if (all.length > 3)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            style: TextStyle(color: pal.text),
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Поиск по заметкам'), isDense: true, border: const OutlineInputBorder()),
          ),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: shown.length,
          itemBuilder: (_, i) {
            final n = shown[i];
            final label = (n.$2['label'] as String?)?.isNotEmpty == true ? n.$2['label'] as String : Books.instance.formatRef(n.$1.book, n.$1.chapter, n.$1.verse, full: true);
            return _Row(
              id: 'n${refKey(n.$1)}',
              pal: pal,
              title: _titleRow(pal, Icons.edit_note, pal.accent, label),
              meta: fmtDate(n.$2['updated'] ?? n.$2['at']),
              text: n.$2['text'] as String?,
              deleteLabel: t('Удалить заметку'),
              onTap: () => _open(context, ref, widget.pane, n.$1),
              onDelete: () => drop(n),
              extra: [IconButton(tooltip: t('Изменить заметку'), icon: Icon(Icons.edit_outlined, size: 20, color: pal.muted), onPressed: () => showNoteSheet(context, [n.$1], _moduleOf(ref, widget.pane)))],
            );
          },
        ),
      ),
    ]);
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
    final pal = ref.watch(settingsProvider).palette;
    final store = ref.read(marksProvider.notifier);
    final m = ref.watch(marksProvider);
    if (m.highlights.isEmpty) return _Empty(Icons.border_color_outlined, t('Выделений пока нет'), t('Зажмите стих и нажмите маркер.'), pal);
    final counts = <String, int>{};
    for (final c in m.highlights.values) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final list = [
      for (final e in m.highlights.entries)
        if (parseKey(e.key) != null && (_color == 'all' || e.value == _color)) (parseKey(e.key)!, e.value),
    ]..sort((a, b) => byBible(a.$1, b.$1));
    final module = _moduleOf(ref, widget.pane);
    String label(HlColor c) => m.hlLabels[c.id]?.trim().isNotEmpty == true ? m.hlLabels[c.id]!.trim() : t(c.name);

    void unmark((VerseRef, String) x) {
      store.setHighlight([x.$1], null);
      undoToast(context, t('Выделение убрано'), () => store.setHighlight([x.$1], x.$2));
    }

    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          ChoiceChip(label: Text(t('Все')), selected: _color == 'all', onSelected: (_) => setState(() => _color = 'all')),
          for (final c in hlColors)
            if (counts[c.id] != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 7),
                  label: Text('${label(c)} ${counts[c.id]}'),
                  selected: _color == c.id,
                  onSelected: (_) => setState(() => _color = c.id),
                ),
              ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final x = list[i];
            final r = x.$1;
            return _Row(
              id: 'h${refKey(r)}',
              pal: pal,
              title: Row(children: [
                CircleAvatar(backgroundColor: hlColor(x.$2)?.color ?? pal.line, radius: 7),
                const SizedBox(width: 6),
                Flexible(child: Text(Books.instance.formatRef(r.book, r.chapter, r.verse, full: true), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
              ]),
              text: i < 200 ? verseText(module, r) : null,
              deleteLabel: t('Убрать выделение'),
              onTap: () => _open(context, ref, widget.pane, r),
              onDelete: () => unmark(x),
            );
          },
        ),
      ),
    ]);
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
    final pal = ref.watch(settingsProvider).palette;
    final cols = ref.watch(marksProvider.select((m) => m.collections));
    final n = ref.read(marksProvider.notifier);
    if (cols.isEmpty) return _Empty(Icons.folder_outlined, t('Подборок пока нет'), t('Зажмите стих → «⋯» → «В подборку…».'), pal);
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
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            TextButton.icon(onPressed: () => setState(() => _cur = null), icon: const Icon(Icons.chevron_left, size: 18), label: Text(t('Все подборки'))),
            Expanded(child: Text('${c['name']} · ${items.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final x = items[i];
              return _Row(
                id: 'ci${c['id']}${itemKey(x)}',
                pal: pal,
                title: Text(_full(x), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                text: x['text'] as String?,
                deleteLabel: t('Убрать из подборки'),
                onTap: () => _open(context, ref, widget.pane, refOf(x)!),
                onDelete: () => dropItem(c, x),
              );
            },
          ),
        ),
      ]);
    }
    return ListView.builder(
      itemCount: cols.length,
      itemBuilder: (_, i) {
        final x = cols[i];
        return _Row(
          id: 'c${x['id']}',
          pal: pal,
          title: _titleRow(pal, Icons.folder_outlined, pal.accent, '${x['name']}'),
          meta: t('{n} ст.', {'n': '${(x['items'] as List).length}'}),
          deleteLabel: t('Удалить подборку'),
          onTap: () => setState(() => _cur = '${x['id']}'),
          onDelete: () => dropCollection(x),
        );
      },
    );
  }
}
