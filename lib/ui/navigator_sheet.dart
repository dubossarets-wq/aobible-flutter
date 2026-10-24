// «Перейти»: строка ссылки («Ин 3:16») и сетка книг → сетка глав. Как окно выбора места в веб-версии.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/panes.dart';
import '../core/settings.dart';

Future<void> openNavigator(BuildContext context, int pane) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: NavigatorSheet(pane: pane)),
    );

class NavigatorSheet extends ConsumerStatefulWidget {
  const NavigatorSheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<NavigatorSheet> createState() => _NavigatorSheetState();
}

class _NavigatorSheetState extends ConsumerState<NavigatorSheet> {
  final _input = TextEditingController();
  String? _book; // выбрана книга — показываем главы
  bool _nt = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final at = livePositions[widget.pane]?.value;
    if (at != null) _nt = Books.instance.meta(at.book).testament == 'NT';
  }

  void _go(VerseRef r) {
    ref.read(panesProvider.notifier).navigate(widget.pane, r);
    Navigator.pop(context);
  }

  void _submit() {
    final r = Books.instance.parseHuman(_input.text);
    if (r == null) return setState(() => _error = t('Не понял ссылку. Пример: Ин 3:16'));
    _go(r);
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final p = ref.read(panesProvider)[widget.pane];
    final list = bookList(p.moduleId);
    final books = Books.instance;
    final selected = _book == null ? null : list.firstWhere((b) => b['id'] == _book, orElse: () => list.first);
    return Material(
      color: pal.panel,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            if (selected != null) IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _book = null)),
            Expanded(child: Text(selected != null ? books.meta(selected['id'] as String).name : t('Перейти'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        if (selected == null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _input,
              autofocus: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: t('Книга или ссылка: Ин 3:16'),
                errorText: _error,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: pal.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(t('Ветхий Завет'))), ButtonSegment(value: true, label: Text(t('Новый Завет')))],
              selected: {_nt},
              onSelectionChanged: (v) => setState(() => _nt = v.first),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                for (final b in list.where((b) => (books.meta(b['id'] as String).testament == 'NT') == _nt))
                  _Cell(
                    title: books.meta(b['id'] as String).short.replaceAll(RegExp(r'\.$'), ''),
                    sub: books.meta(b['id'] as String).name,
                    pal: pal,
                    onTap: () => setState(() => _book = b['id'] as String),
                  ),
              ],
            ),
          ),
        ] else
          Expanded(
            child: GridView.count(
              crossAxisCount: 6,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var c = 1; c <= (selected['chapters'] as int); c++)
                  _Cell(title: '$c', pal: pal, onTap: () => _go(VerseRef(_book!, c, 1))),
              ],
            ),
          ),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.title, this.sub, required this.pal, required this.onTap});
  final String title;
  final String? sub;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: pal.bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: pal.text)),
              if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: pal.muted)),
            ]),
          ),
        ),
      );
}
