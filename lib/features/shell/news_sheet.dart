// «Что нового» (NewsSheet.jsx, src/core/whatsNew.js): после обновления один раз — список изменений простым языком.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'colors.dart';
import 'news_data.dart';
import 'sheet.dart';

const _key = 'newsSeen';

/// Что показать при запуске: записи новее просмотренной. Первый запуск приложения — ничего (человеку всё ново,
/// отметку ставит prepareFirstRun). Пользовался раньше, но «Что нового» ещё не видел — последняя запись.
List<NewsEntry> pendingNews() {
  final seen = prefs.getString(_key);
  if (seen == null) return news.take(1).toList();
  return news.where((n) => n.id.compareTo(seen) > 0).toList();
}

void markNewsSeen() => prefs.setString(_key, news.first.id);

/// 2026-10-24 → 24.10.2026
String fmtNewsDate(String id) {
  final p = id.split('-');
  return p.length < 3 ? id : '${p[2].replaceAll(RegExp(r'\D'), '').padLeft(2, '0')}.${p[1]}.${p[0]}';
}

Future<void> openNews(BuildContext context, {List<NewsEntry>? items}) {
  markNewsSeen();
  return showAppSheet(context, (_) => NewsSheet(items: items));
}

class NewsSheet extends ConsumerWidget {
  const NewsSheet({super.key, this.items});
  final List<NewsEntry>? items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = items?.isNotEmpty == true ? items! : news.take(1).toList();
    final pal = effectivePalette(ref.watch(settingsProvider));
    return AppSheet(
      title: t('Что нового'),
      subtitle: t('Обновление от {date}', {'date': fmtNewsDate(list.first.id)}),
      children: [
        for (final n in list)
          for (final text in n.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 8, right: 10), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle))),
                Expanded(child: Text(t(text), style: const TextStyle(fontSize: 16, height: 1.4))),
              ]),
            ),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(t('Понятно'))),
      ],
    );
  }
}
