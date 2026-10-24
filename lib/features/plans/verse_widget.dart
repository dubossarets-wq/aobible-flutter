// Виджет «Стих дня» на главный экран Android (src/core/widget.js, native: android/.../app/aobible/VerseWidget.kt).
// Приложение раз в день передаёт ему стихи на 30 дней вперёд — виджет сам берёт стих на сегодняшнюю дату, даже если
// приложение долго не открывали. Текст — из установленного перевода (без сети).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'plan_logic.dart';
import 'verse_card.dart';
import 'verse_list.dart';
import 'verse_text.dart';

const _days = 30;

/// Стихи на 30 дней вперёд: [{d: «2026-10-24», text, ref}]
List<Map<String, String>> widgetItems(List<InstalledModule> mods, DateTime from) {
  final items = <Map<String, String>>[];
  for (var k = 0; k < _days; k++) {
    final date = DateTime(from.year, from.month, from.day + k);
    final ref = parseKey(verseOfDayKey(date));
    String? text;
    for (final m in mods) {
      text = verseText(m.id, ref)?.trim();
      if (text != null && text.isNotEmpty) break;
    }
    if (text == null || text.isEmpty) continue;
    items.add({'d': localDate(date), 'text': text, 'ref': Books.instance.formatRef(ref.book, ref.chapter, ref.verse)});
  }
  return items;
}

/// Передать виджету стихи (раз в день для одного и того же перевода)
Future<void> updateWidget(String? paneModule, String primary) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final mods = verseModules(paneModule, primary);
    if (mods.isEmpty) return;
    final stamp = '${localDate()}|${mods.first.id}|$currentLang';
    if (prefs.getString('widgetDay') == stamp) return; // уже передавали сегодня
    final items = widgetItems(mods, DateTime.now());
    if (items.isEmpty) return;
    await HomeWidget.saveWidgetData<String>('items', jsonEncode(items));
    await HomeWidget.saveWidgetData<String>('title', t('Стих дня'));
    await HomeWidget.updateWidget(qualifiedAndroidName: 'app.aobible.VerseWidget');
    await prefs.setString('widgetDay', stamp);
  } catch (e) {
    debugPrint('Виджет: $e'); // старая сборка без виджета и т. п. — ничего не делаем
  }
}
