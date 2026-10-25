// ignore_for_file: use_build_context_synchronously
// Оболочка: меню «Ещё», настройки, оформление, библиотека модулей, стартовые модули, «О приложении»,
// «Что нового», приветствие, инструкция, письмо о проблеме. Подключение — register() (строка в features.dart).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'library_sheet.dart';
import 'more_sheet.dart';
import 'news_data.dart';
import 'news_sheet.dart';
import 'plural.dart';
import 'prefs_sheet.dart';
import 'report.dart';
import 'sheet.dart';
import 'starter.dart';
import 'welcome_sheet.dart';

export 'about_sheet.dart' show openAbout, appVersion;
export 'appearance_sheet.dart' show openAppearance;
export 'background.dart' show ReaderBackground, UserBg, bgStamp;
export 'colors.dart' show effectivePalette, paletteWith, headingColor, strongColor;
export 'fonts.dart' show readerTextStyle, textAlignOf, menuFlag;
export 'help_sheet.dart' show openHelp;
export 'library_sheet.dart' show openLibrary;
export 'news_sheet.dart' show openNews;
export 'prefs_sheet.dart' show audioSettingsExtras, openPrefs;
export 'tour.dart' show startTour, stopTour, tourActive;
export 'tour_targets.dart' show tourKey, tourResolvers;

bool _started = false;

void register() {
  // register() вызывается заново при смене языка (Hub.reset) — запускать нужно один раз
  if (!_started) {
    _started = true;
    installErrorLog();
    prepareFirstRun(news.first.id); // самый первый запуск: основной перевод на языке интерфейса, приветствие
    unawaited(loadPlurals());
    // Задания запуска не ждут друг друга: доустановка модулей может идти долго
    Hub.afterStart.add((ref) async {
      unawaited(_showStartup());
      unawaited(installStarterModules(ref));
      unawaited(_playUpdateNotice());
    });
  }
  Hub.openMore = openMore;
  Hub.openSettings = (c, r, p) => openPrefs(c);
  Hub.openLibrary = (c, r, p) => openLibrary(c);
  Hub.openLibraryTab = (c, tab) => openLibrary(c, tab: tab);
}

/// Приветствие новому человеку, «Что нового» — после обновления. Когда приложение готово (есть перевод) и не открыто другое окно.
Future<void> _showStartup() async {
  final store = ModuleStore.instance;
  for (var i = 0; store.bibles.isEmpty; i++) {
    if (i > 1200) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  for (var i = 0; i < 20; i++) {
    final ctx = appContext();
    if (ctx != null && !Navigator.of(ctx).canPop()) {
      if (prefs.getBool('welcomePending') == true) {
        markNewsSeen();
        await openWelcome(ctx);
      } else {
        final items = pendingNews();
        if (items.isNotEmpty) await openNews(ctx, items: items);
      }
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// Приложение из Google Play: о новой версии сообщаем один раз (по данным самого Google Play)
Future<void> _playUpdateNotice() async {
  if (!Platform.isAndroid) return;
  await Future<void>.delayed(const Duration(seconds: 6));
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability != UpdateAvailability.updateAvailable || prefs.getInt('playUpdateNotified') == info.availableVersionCode) return;
    await prefs.setInt('playUpdateNotified', info.availableVersionCode ?? 0);
    Hub.toast(t('Вышла новая версия приложения'), actionLabel: t('Обновить'), action: () => InAppUpdate.performImmediateUpdate());
  } catch (_) {
    // нет Google Play или сети — не страшно
  }
}
