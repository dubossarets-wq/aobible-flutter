// Функция «Проповеди»: список и редактор (пункт «Проповеди» в «Ещё»), «Кафедра», добавление выделенных стихов (Hub.addToSermon),
// части стиха (Hub.addFragmentToSermon) и значок «стих есть в проповеди» у стиха (ChapterView.jsx: vmark sermon-mark).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import '../plans/ui_kit.dart';
import '../shell/fonts.dart' show menuFlag;
import 'sermon_add.dart';
import 'sermon_store.dart';
import 'sermons_sheet.dart';
import '../../ui/ios_style.dart';

void register() {
  Hub.addToSermon = (context, ref, refs, moduleId) => showPage(context, (_) => SermonAddSheet(pane: 0, refs: refs, moduleId: moduleId), height: 0.7);
  // «Часть стиха» → «В проповедь»: в проповедь уходят выбранные слова, а не весь стих
  Hub.addFragmentToSermon = (context, ref, at, moduleId, fragment) =>
      showPage(context, (_) => SermonAddSheet(pane: 0, refs: [at], moduleId: moduleId, fragment: fragment), height: 0.7);
  // Пункт меню «Ещё» — по флагу «Проповеди» (Настройки → «Меню ⋮»)
  Hub.moreItems.add(MoreItem(
    id: 'sermons',
    icon: LucideIcons.scrollText,
    label: t('Проповеди'),
    order: 20,
    visible: (ref) => menuFlag(ref.watch(settingsProvider), 'sermons'),
    run: (context, ref, pane) => showPage(context, (_) => SermonsSheet(pane: pane), page: true, tab: 'more'),
  ));
  Hub.verseDecorators.add(_decor);
  // из проповеди перешли по стиху в Библию — под верхним меню «Вернуться к проповеди»
  Hub.underBar = (context, ref, pane) => _SermonReturn(pane: pane);
  Hub.afterStart.add(_watchSermons);
}

// Отметки «стих в проповеди»: «книга.глава» → номера стихов; пересчитываются, только когда проповеди изменились
List<Sermon>? _indexFor;
Map<String, Set<int>> _index = const {};

Map<String, Set<int>> _marks(List<Sermon> sermons) {
  if (identical(sermons, _indexFor)) return _index;
  final m = <String, Set<int>>{};
  for (final s in sermons) {
    for (final b in blocksOf(s)) {
      if (!isVerse(b)) continue;
      final set = m.putIfAbsent('${b['book']}.${b['chapter']}', () => {});
      for (var v = b['verse'] as int; v <= ((b['to'] ?? b['verse']) as int); v++) {
        set.add(v);
      }
    }
  }
  _indexFor = sermons;
  return _index = m;
}

VerseDecor? _decor(BuildContext context, WidgetRef ref, int pane, String moduleId, ReaderItem item, String book) {
  if (item.kind != ItemKind.verse) return null;
  final sermons = ref.read(sermonsProvider);
  if (sermons.isEmpty) return null;
  if (!(_marks(sermons)['$book.${item.chapter}']?.contains(item.verse) ?? false)) return null;
  final s = ref.read(settingsProvider);
  if (s.get<bool>('bookMode')) return null; // «Как книга» — без значков
  final pal = s.palette;
  final fs = s.d('fontSize');
  final at = VerseRef(book, item.chapter, item.verse);
  // .sermon-mark: плашка 1.05em с лёгким цветом акцента и значком «свиток» внутри
  return VerseDecor(afterNumber: [
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(right: fs * 0.25),
        child: Semantics(
          button: true,
          label: t('Стих есть в проповеди. Открыть проповедь'),
          child: Tooltip(
            message: t('Открыть проповедь'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final open = sermonWith(ref.read(sermonsProvider), at)?['id'] as String?;
                showPage(context, (_) => SermonsSheet(pane: pane, open: open), page: true);
              },
              child: Container(
                width: fs * 1.05,
                height: fs * 1.05,
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
                child: AIcon(ico(LucideIcons.scrollText), size: fs * 0.72, color: pal.accent),
              ),
            ),
          ),
        ),
      ),
    ),
  ]);
}

// Проповеди изменились — стихи в видимой части перерисовываются (значки появляются и исчезают сразу)
ProviderContainer? _watched;
Future<void> _watchSermons(WidgetRef ref) async {
  final c = ProviderScope.containerOf(ref.context, listen: false);
  if (identical(_watched, c)) return;
  _watched = c;
  c.listen(sermonsProvider, (_, _) => c.read(decorVersionProvider.notifier).bump());
}

/// «Вернуться к проповеди «…»» — подменю под верхним меню (как панель подстрочника: цвет верхней панели, во всю
/// ширину); нажатие открывает проповедь, крестик — закрывает подменю
class _SermonReturn extends ConsumerWidget {
  const _SermonReturn({required this.pane});
  final int pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    final fg = pal.barText;
    return ValueListenableBuilder<({int pane, String id})?>(
      valueListenable: sermonReturn,
      builder: (context, v, _) {
        final s = v == null || v.pane != pane ? null : ref.watch(sermonsProvider).where((x) => x['id'] == v.id).firstOrNull;
        // въезжает сверху из-под меню и уезжает обратно
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.fastOutSlowIn,
          switchOutCurve: Curves.fastOutSlowIn,
          transitionBuilder: (c, a) => ClipRect(child: SlideTransition(position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(a), child: c)),
          child: s == null
              ? const SizedBox(key: ValueKey('none'), width: double.infinity)
              : Container(
                  key: ValueKey(s['id']),
                  height: 40,
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  decoration: BoxDecoration(
                    color: pal.bar,
                    border: Border(top: BorderSide(color: fg.withValues(alpha: 0.08))),
                    boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            sermonReturn.value = null;
                            showPage(context, (_) => SermonsSheet(pane: pane, open: '${s['id']}'), page: true);
                          },
                          child: SizedBox(
                            height: 32,
                            child: Row(children: [
                              const SizedBox(width: 8),
                              AIcon(ico(LucideIcons.arrowLeft), size: 16, color: fg),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Transform.translate(
                                  offset: const Offset(0, -1),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: '${t('Вернуться к проповеди')} '),
                                      TextSpan(text: '«${s['title']}»', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.6, color: fg),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    IconBtn(icon: LucideIcons.x, size: 16, color: fg.withValues(alpha: 0.8), tooltip: t('Закрыть'), onTap: () => sermonReturn.value = null),
                  ]),
                ),
        );
      },
    );
  }
}
