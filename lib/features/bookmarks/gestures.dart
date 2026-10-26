// Жесты читалки и пункты меню «Ещё» этой функции: двойное касание стиха (ChapterView.jsx, tapState.js),
// «Часть стиха» (App.jsx addFavoritePart), «Закладка на это место» / «К последней закладке» (moreItems.jsx),
// автокопия данных при первом запуске новой версии (core/backup.js bootBackup).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import '../shell/shell.dart' show appVersion;
import 'marks.dart';
import 'userdata.dart';

// --- двойное касание: в любимые / из любимых, сердечко вспыхивает (.verse.fav-pulse: 0,8 с, love 30 % → 0) ---

/// «Книга.глава.стих» → текущая сила вспышки (0..0,3); читает decor.dart
final favPulse = <String, double>{};
final _pulseTimers = <String, Timer>{};
const _pulseSteps = 5;

void _pulse(WidgetRef ref, VerseRef at) {
  final k = refKey(at);
  _pulseTimers[k]?.cancel();
  final bump = ref.read(decorVersionProvider.notifier);
  var step = 0;
  favPulse[k] = 0.3;
  bump.bump();
  // Гасим ступенями (каждые 160 мс); verse_view перетекает цвет между ступенями за 170 мс — выходит плавный ease-out
  _pulseTimers[k] = Timer.periodic(const Duration(milliseconds: 160), (tm) {
    step++;
    if (step >= _pulseSteps) {
      tm.cancel();
      _pulseTimers.remove(k);
      favPulse.remove(k);
    } else {
      favPulse[k] = 0.3 * (1 - step / _pulseSteps) * (1 - step / _pulseSteps);
    }
    try {
      bump.bump();
    } catch (_) {
      tm.cancel(); // приложение уже закрыто
    }
  });
}

/// Hub.onVerseDoubleTap
void onVerseDoubleTap(BuildContext context, WidgetRef ref, int pane, VerseRef at, String moduleId) {
  final fav = ref.read(marksProvider).isFavorite(at);
  activeWord.value = null; // как в веб-версии: выборку и подсветку слова снимаем
  if (fav) {
    ref.read(marksProvider.notifier).setFavorite(at, '', false);
    Hub.toast(t('Убрано из любимых стихов'));
  } else {
    ref.read(marksProvider.notifier).setFavorite(at, verseText(moduleId, at) ?? '', true);
    Hub.toast(t('♥ Добавлено в любимые стихи'));
  }
  _pulse(ref, at);
}

/// Hub.addFavoritePart: слова from..to (text — только эти слова, как в списке «Любимые стихи»)
void addFavoritePart(BuildContext context, WidgetRef ref, VerseRef at, String moduleId, int from, int to, String text) {
  ref.read(marksProvider.notifier).setFavoritePart(at, text, from < to ? from : to, from < to ? to : from);
  Hub.toast(t('♥ Часть стиха — в любимых'));
}

// --- автокопия данных при первом запуске новой версии ---

/// Hub.afterStart: если версия сменилась — копия данных, какими их оставила прежняя (потом её можно вернуть в «Мои данные»)
Future<void> bootBackup(WidgetRef ref) async {
  try {
    final last = prefs.getString('lastBuild');
    if (last != null && last.isNotEmpty && last != appVersion) snapshot('до обновления с версии $last');
    if (last != appVersion) prefs.setString('lastBuild', appVersion);
  } catch (_) {
    // без хранилища нечего сохранять
  }
}
