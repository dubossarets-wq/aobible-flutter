// Главный экран: одна или две панели чтения, у каждой — шапка (перевод, место, вторая панель),
// внизу на телефоне — вкладки «Планы, Поиск, Библия, Закладки, Ещё» (как в веб-версии).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import 'navigator_sheet.dart';
import 'reader_pane.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panes = ref.watch(panesProvider.select((l) => l.length));
    final s = ref.watch(settingsProvider);
    final pal = s.palette;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final layout = s.get<String>('splitLayout');
    final rows = layout == 'rows' || (layout == 'auto' && !wide);
    final children = [for (var i = 0; i < panes; i++) Expanded(child: _Pane(index: i))];
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: panes == 1
            ? const _Pane(index: 0)
            : rows
                ? Column(children: [children[0], Container(height: 1, color: pal.line), children[1]])
                : Row(children: [children[0], Container(width: 1, color: pal.line), children[1]]),
      ),
      bottomNavigationBar: wide ? null : _TabBar(pal: pal),
    );
  }
}

class _Pane extends ConsumerWidget {
  const _Pane({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    final module = ref.watch(panesProvider.select((l) => index < l.length ? l[index].moduleId : null));
    final split = ref.watch(panesProvider.select((l) => l.length > 1));
    if (module == null) return const SizedBox.shrink();
    final name = ModuleStore.instance.get(module)?.name ?? module;
    final initial = ref.read(panesProvider)[index].ref;
    return Column(children: [
      Container(
        height: 54,
        color: pal.bar,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          _Chip(label: name, pal: pal, onTap: () => _pickModule(context, ref)),
          const SizedBox(width: 6),
          ValueListenableBuilder<VerseRef>(
            valueListenable: livePosition(index, initial),
            builder: (_, r, __) => _Chip(label: Books.instance.formatRef(r.book, r.chapter, r.verse), pal: pal, onTap: () => openNavigator(context, index)),
          ),
          const Spacer(),
          if (index == 0 && MediaQuery.sizeOf(context).width >= 900)
            IconButton(icon: Icon(Icons.search, color: pal.barText), onPressed: () => openSearch(context, index)),
          if (index == 0 || split)
            IconButton(
              tooltip: split ? t('Закрыть вторую панель') : t('Читать параллельно'),
              icon: Icon(split && index == 1 ? Icons.close : Icons.vertical_split_outlined, color: pal.barText),
              onPressed: () => ref.read(panesProvider.notifier).toggleSplit(),
            ),
        ]),
      ),
      Expanded(child: ReaderPane(index: index)),
    ]);
  }

  void _pickModule(BuildContext context, WidgetRef ref) {
    final pal = ref.read(settingsProvider).palette;
    showModalBottomSheet(
      context: context,
      builder: (_) => Material(
        color: pal.panel,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 12), children: [
          for (final m in ModuleStore.instance.bibles)
            ListTile(
              title: Text(m.name, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              subtitle: Text(m.title, style: TextStyle(color: pal.muted)),
              onTap: () {
                ref.read(panesProvider.notifier).setModule(index, m.id);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.pal, required this.onTap});
  final String label;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: pal.barText.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: pal.barText)),
              Icon(Icons.expand_more, size: 18, color: pal.barText.withValues(alpha: 0.7)),
            ]),
          ),
        ),
      );
}

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.pal});
  final Palette pal;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void soon() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Скоро'))));
    return NavigationBar(
      backgroundColor: pal.panel,
      selectedIndex: 2,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) {
        if (i == 1) openSearch(context, 0);
        if (i == 0 || i == 3 || i == 4) soon();
      },
      destinations: [
        NavigationDestination(icon: const Icon(Icons.event_available_outlined), label: t('Планы')),
        NavigationDestination(icon: const Icon(Icons.search), label: t('Поиск')),
        NavigationDestination(icon: const Icon(Icons.menu_book_outlined), label: t('Библия')),
        NavigationDestination(icon: const Icon(Icons.favorite_border), label: t('Закладки')),
        NavigationDestination(icon: const Icon(Icons.menu), label: t('Ещё')),
      ],
    );
  }
}
