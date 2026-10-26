// «Что нового» (NewsSheet.jsx, src/core/whatsNew.js): после обновления один раз — список изменений простым языком.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'colors.dart';
import 'intl_data.dart';
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

/// 2026-10-24 → «24 октября» на языке интерфейса (как toLocaleDateString(locale, {day, month: 'long'}) в веб-версии)
String fmtNewsDate(String id) {
  final p = id.split('-');
  if (p.length < 3) return id;
  final day = int.tryParse(p[2].replaceAll(RegExp(r'\D'), '')), month = int.tryParse(p[1]);
  final tpl = monthDayTemplates[currentLang] ?? monthDayTemplates['ru']!;
  if (day == null || month == null || month < 1 || month > 12) return id;
  return tpl[month - 1].replaceFirst('{d}', '$day');
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
      gap: 14, // .news
      children: [
        // .news-list: маркеры цвета акцента, отступ 1.2em, текст 16 с интервалом 1.5, зазор между пунктами 10
        for (final n in list)
          Column(children: [
            for (final (i, text) in n.items.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 19, child: Padding(padding: const EdgeInsets.only(top: 9, left: 2), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle)))),
                  Expanded(child: Text(t(text), style: TextStyle(fontSize: 16, height: 1.5, color: pal.text))),
                ]),
              ),
          ]),
        // .news-ok: во всю ширину, чуть выше обычной кнопки
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: AobButton(kind: BtnKind.primary, wide: true, label: t('Понятно'), onTap: () => Navigator.of(context).maybePop()),
        ),
      ],
    );
  }
}
