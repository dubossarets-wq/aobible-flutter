// «Перейти» (BookNavigator.jsx, styles.css .bn-*): строка ссылки, недавние книги, Ветхий/Новый Завет,
// разделы с цветной точкой и плитками «сокращение + название», затем сетка глав.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bible.dart';
import '../core/books.dart';
import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/panes.dart';
import '../core/settings.dart';
import 'kit.dart';

Future<void> openNavigator(BuildContext context, int pane) => showAobSheet(context, builder: (_) => NavigatorSheet(pane: pane));

// Разделы Библии с цветами (src/core/bookCategories.js)
const _categories = <(String, int, List<String>)>[
  ('Пятикнижие', 0xffb07a2e, ['Gen', 'Exod', 'Lev', 'Num', 'Deut']),
  ('Исторические книги', 0xff6b8e4e, ['Josh', 'Judg', 'Ruth', '1Sam', '2Sam', '1Kgs', '2Kgs', '1Chr', '2Chr', 'Ezra', 'Neh', 'Esth']),
  ('Поэтические книги', 0xff3f7fa6, ['Job', 'Ps', 'Prov', 'Eccl', 'Song']),
  ('Большие пророки', 0xff8b4a7d, ['Isa', 'Jer', 'Lam', 'Ezek', 'Dan']),
  ('Малые пророки', 0xffb0688f, ['Hos', 'Joel', 'Amos', 'Obad', 'Jonah', 'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal']),
  ('Евангелия', 0xffc0533a, ['Matt', 'Mark', 'Luke', 'John']),
  ('Деяния и соборные послания', 0xff2f8f83, ['Acts', 'Jas', '1Pet', '2Pet', '1John', '2John', '3John', 'Jude']),
  ('Послания апостола Павла', 0xff4a68ad, ['Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col', '1Thess', '2Thess', '1Tim', '2Tim', 'Titus', 'Phlm', 'Heb']),
  ('Откровение', 0xff7a55a8, ['Rev']),
];
const _dc = ('Неканонические книги', 0xff8a8172);
const _other = ('Другие книги', 0xff8a8172);

(String, int) _categoryOf(String id) {
  for (final c in _categories) {
    if (c.$3.contains(id)) return (c.$1, c.$2);
  }
  return Books.instance.meta(id).testament == 'AP' ? _other : _dc;
}

class NavigatorSheet extends ConsumerStatefulWidget {
  const NavigatorSheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<NavigatorSheet> createState() => _NavigatorSheetState();
}

class _NavigatorSheetState extends ConsumerState<NavigatorSheet> {
  final _input = TextEditingController();
  String? _book; // выбрана книга — показываем главы
  late bool _nt;
  String? _error;

  @override
  void initState() {
    super.initState();
    final at = livePositions[widget.pane]?.value ?? ref.read(panesProvider)[widget.pane].ref;
    _nt = Books.instance.meta(at.book).testament == 'NT';
    _input.addListener(() => setState(() => _error = null));
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
    final pal = paletteOf(ref);
    final p = ref.read(panesProvider)[widget.pane];
    final at = livePositions[widget.pane]?.value ?? p.ref;
    final list = bookList(p.moduleId);
    final books = Books.instance;
    final module = ModuleStore.instance.get(p.moduleId);
    final fill = mix(pal.text, 0.055, pal.panel);
    final muted = mix(pal.muted, 0.8, pal.text);
    if (_book != null) return _chapters(pal, fill, list, at);
    // Недавние книги — из истории переходов панели, текущая первой
    final recent = <String>[at.book];
    for (final r in p.history.reversed) {
      if (!recent.contains(r.book)) recent.add(r.book);
    }
    final shown = list.where((b) => (books.meta(b['id'] as String).testament == 'NT') == _nt).toList();
    final groups = <(String, int), List<Map<String, dynamic>>>{};
    for (final b in shown) {
      groups.putIfAbsent(_categoryOf(b['id'] as String), () => []).add(b);
    }
    return AobSheet(
      title: t('Перейти'),
      subtitle: module?.title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Строка ссылки (.bn-search): высота 50, скругление 15, кнопка «→» залита акцентом, когда есть текст
        Container(
          height: 50,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            const SizedBox(width: 15),
            Icon(LucideIcons.search, size: 18, color: muted),
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontSize: 16, color: pal.text),
                decoration: InputDecoration(hintText: t('Книга или ссылка: Ин 3:16'), hintStyle: TextStyle(color: muted), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Material(
                color: _input.text.isEmpty ? Colors.transparent : pal.accent,
                shape: const CircleBorder(),
                child: InkWell(customBorder: const CircleBorder(), onTap: _submit, child: SizedBox(width: 44, height: 44, child: Icon(LucideIcons.arrowRight, size: 20, color: _input.text.isEmpty ? muted : pal.onAccent))),
              ),
            ),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 0), child: Text(_error!, style: const TextStyle(color: Color(0xffc93a3a), fontSize: 13))),
        const SizedBox(height: 16),
        if (recent.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(t('Недавние'), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: muted))),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final id in recent.take(8))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: id == at.book ? mix(pal.accent, 0.14, pal.panel) : fill,
                    shape: StadiumBorder(side: id == at.book ? BorderSide(color: pal.accent, width: 1.5) : BorderSide.none),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _book = id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(child: Text(books.meta(id).name, style: TextStyle(fontSize: 14.7, fontWeight: id == at.book ? FontWeight.w600 : FontWeight.w500, color: pal.text))),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        // Ветхий / Новый Завет (.bn-seg): дорожка, выбранный — «таблетка» цвета окна
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            for (final (nt, label) in [(false, t('Ветхий Завет')), (true, t('Новый Завет'))])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _nt = nt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _nt == nt ? (pal.dark ? mix(pal.text, 0.14, pal.panel) : pal.panel) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _nt == nt ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(label, style: TextStyle(fontSize: 14.7, fontWeight: _nt == nt ? FontWeight.w600 : FontWeight.w500, color: _nt == nt ? pal.text : muted)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 22),
        for (final g in groups.entries) ...[
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: Color(g.key.$2), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(t(g.key.$1), style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: muted)),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 108).floor().clamp(3, 8);
            final w = (c.maxWidth - (cols - 1) * 8) / cols;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in g.value)
                SizedBox(
                  width: w,
                  child: _BookCell(
                    short: books.meta(b['id'] as String).short.replaceAll(RegExp(r'\.$'), ''),
                    name: books.meta(b['id'] as String).name,
                    on: b['id'] == at.book,
                    fill: fill,
                    pal: pal,
                    onTap: () => setState(() => _book = b['id'] as String),
                  ),
                ),
            ]);
          }),
          const SizedBox(height: 22),
        ],
      ]),
    );
  }

  Widget _chapters(Palette pal, Color fill, List<Map<String, dynamic>> list, VerseRef at) {
    final b = list.firstWhere((x) => x['id'] == _book, orElse: () => list.first);
    final id = b['id'] as String;
    final n = b['chapters'] as int;
    return AobSheet(
      title: Books.instance.meta(id).name,
      subtitle: t(_categoryOf(id).$1),
      onBack: () => setState(() => _book = null),
      child: LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 60).floor().clamp(5, 12);
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var ch = 1; ch <= n; ch++)
            SizedBox(
              width: w,
              height: 52,
              child: Material(
                color: id == at.book && ch == at.chapter ? pal.accent : fill,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _go(VerseRef(id, ch, 1)),
                  child: Center(
                    child: Text('$ch', style: TextStyle(fontSize: 16.6, fontWeight: FontWeight.w600, color: id == at.book && ch == at.chapter ? pal.onAccent : pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Плитка книги (.book-cell): скругление 14, крупное сокращение, под ним название; текущая — с рамкой акцента
class _BookCell extends StatelessWidget {
  const _BookCell({required this.short, required this.name, required this.on, required this.fill, required this.pal, required this.onTap});
  final String short, name;
  final bool on;
  final Color fill;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: on ? mix(pal.accent, 0.14, pal.panel) : fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: on ? BorderSide(color: pal.accent, width: 1.5) : BorderSide.none),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(short, style: TextStyle(fontSize: 16.6, fontWeight: FontWeight.w700, height: 1.15, color: pal.text, letterSpacing: -0.17)),
              const SizedBox(height: 3),
              Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: 12.2, height: 1.25, color: on ? mix(pal.muted, 0.45, pal.text) : mix(pal.muted, 0.8, pal.text))),
            ]),
          ),
        ),
      );
}
