// Жесты читалки и пункты меню «Ещё» этой функции: двойное касание стиха (ChapterView.jsx, tapState.js),
// «Часть стиха» (App.jsx addFavoritePart), «Закладка на это место» / «К последней закладке» (moreItems.jsx),
// автокопия данных при первом запуске новой версии (core/backup.js bootBackup).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart' show LucideIcons;
import '../hub.dart';
import '../shell/shell.dart' show appVersion, menuFlag;
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
  // Плавного затухания фона у читалки нет — гасим ступенями (каждые 160 мс), глазу это тот же ease-out
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

// --- меню «Ещё» ---

/// Меню не знает, из какой панели открыто: берём ту, которой человек касался последней
int _pane(WidgetRef ref) {
  final n = ref.read(panesProvider).length;
  return SyncHub.driver < n ? SyncHub.driver : 0;
}

VerseRef _here(WidgetRef ref, int pane) => livePositions[pane]?.value ?? ref.read(panesProvider)[pane].ref;

bool _marked(WidgetRef ref) {
  final marks = ref.watch(marksProvider);
  final panes = ref.watch(panesProvider);
  if (panes.isEmpty) return false;
  return marks.isBookmarked(_here(ref, _pane(ref)));
}

void _toggleBookmark(BuildContext context, WidgetRef ref, int pane) {
  final panes = ref.read(panesProvider);
  final p = pane < panes.length ? pane : 0;
  final at = _here(ref, p);
  final marks = ref.read(marksProvider);
  final was = marks.isBookmarked(at);
  final text = was ? '' : (verseText(panes[p].moduleId, at) ?? '');
  ref.read(marksProvider.notifier).toggleBookmark(at, text.length <= 160 ? text : text.substring(0, 160));
  Hub.toast(was ? t('Закладка удалена') : t('Закладка: {ref}', {'ref': Books.instance.formatRef(at.book, at.chapter, at.verse)}));
}

List<MoreItem> moreItems() => [
      MoreItem(id: 'bookmark-here', icon: LucideIcons.bookmark, label: t('Закладка на это место'), order: 1, visible: (ref) => !_marked(ref), run: _toggleBookmark),
      MoreItem(id: 'bookmark-off', icon: LucideIcons.bookmarkCheck, label: t('Убрать закладку'), order: 1, visible: _marked, run: _toggleBookmark),
      MoreItem(
        id: 'bookmark-last',
        icon: LucideIcons.circlePlay,
        label: t('К последней закладке'),
        order: 2,
        visible: (ref) => menuFlag(ref.watch(settingsProvider), 'lastBookmark') && ref.watch(marksProvider.select((m) => m.bookmarks.isNotEmpty)),
        run: (context, ref, pane) {
          // Самая новая закладка — первая в списке
          final last = refOf(ref.read(marksProvider).bookmarks.first);
          if (last != null) ref.read(panesProvider.notifier).navigate(pane < ref.read(panesProvider).length ? pane : 0, last);
        },
      ),
    ];

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
