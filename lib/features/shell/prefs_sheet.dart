// Настройки (PrefsSheet.jsx): короткий список крупных строк, каждая открывает своё окно или страницу:
// язык, инструкция, оформление, меню «Ещё», аудио, библиотека модулей, мои данные, что нового, обновления, о приложении.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'about_sheet.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'fonts.dart';
import 'help_sheet.dart';
import 'library_sheet.dart';
import 'news_sheet.dart';
import 'plural.dart';
import 'sheet.dart';

/// Куда другие функции добавляют свои блоки на страницу «Аудио» (например, «Книги без интернета» —
/// функция аудио): `audioSettingsExtras.add((context, ref) => …)` в своей register().
final List<Widget Function(BuildContext context, WidgetRef ref)> audioSettingsExtras = [];

Future<void> openPrefs(BuildContext context) => showAppSheet(context, (_) => PrefsSheet(opener: context));

/// Круглый флаг из кода страны (эмодзи)
String flagEmoji(String cc) => cc.toUpperCase().codeUnits.map((c) => String.fromCharCode(0x1F1E6 + c - 65)).join();

// Что показывать в меню «Ещё» (остальное — в «Настройках»)
const _menuItems = <(String, String, String?)>[
  ('help', 'Инструкция', null),
  ('lastBookmark', '«К последней закладке»', null),
  ('sermons', 'Проповеди', null),
  ('plans', 'Планы чтения', null),
  ('listen', '«Слушать с этого места»', null),
  ('maps', 'Карты', null),
  ('focus', 'Режим чтения', 'Без кнопок в тексте, панель прячется при прокрутке'),
  ('book', '«Как книга»', null),
  ('split', 'Синхронная прокрутка и расположение панелей', 'Только при разделённом экране'),
];

/// Сменить язык интерфейса сразу, без перезапуска: словарь, названия книг, формы чисел — и перерисовка приложения
Future<void> changeLanguage(WidgetRef ref, String code) async {
  await setLang(code);
  await loadPlurals();
  // Приложение перерисовывается по настройкам: служебная отметка заставляет перестроить всё, что от них зависит
  ref.read(settingsProvider.notifier).set({'langTick': DateTime.now().millisecondsSinceEpoch});
}

class PrefsSheet extends ConsumerStatefulWidget {
  const PrefsSheet({super.key, required this.opener});
  final BuildContext opener;
  @override
  ConsumerState<PrefsSheet> createState() => _PrefsSheetState();
}

class _PrefsSheetState extends ConsumerState<PrefsSheet> {
  String? _page;
  bool _checking = false;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      // Тихая проверка: если Google Play знает о новой версии, строка покажет «новая»
      InAppUpdate.checkForUpdate().then((i) {
        if (mounted) setState(() => _available = i.updateAvailability == UpdateAvailability.updateAvailable);
      }, onError: (_) {});
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final i = await InAppUpdate.checkForUpdate();
      final avail = i.updateAvailability == UpdateAvailability.updateAvailable;
      if (mounted) setState(() => _available = avail);
      if (avail) {
        await InAppUpdate.performImmediateUpdate();
      } else if (mounted) {
        toast(context, t('У вас последняя версия'));
      }
    } catch (e) {
      if (mounted) toast(context, t('Не удалось проверить: {error}', {'error': '$e'.replaceAll('PlatformException', '').trim()}));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final lang = langs.firstWhere((l) => l.code == currentLang, orElse: () => langs.first);
    final title = switch (_page) { 'lang' => t('Язык'), 'menu' => t('Меню «Ещё»'), 'audio' => t('Аудио'), _ => t('Настройки') };
    final myData = Hub.moreItems.where((m) => m.id == 'mydata').firstOrNull;

    List<Widget> body;
    switch (_page) {
      case 'lang':
        body = [
          for (final l in langs)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await changeLanguage(ref, l.code);
                if (mounted) setState(() => _page = null);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: l.code == currentLang ? BoxDecoration(color: pal.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)) : null,
                child: Row(children: [
                  Text(flagEmoji(l.flag), style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  if (l.code == currentLang) Icon(Icons.check, color: pal.accent),
                ]),
              ),
            ),
        ];
      case 'menu':
        body = [
          Padding(padding: const EdgeInsets.all(6), child: Text(t('Отметьте, что показывать в разделе «Ещё» на нижней панели. Остальное всегда есть здесь, в настройках.'), style: TextStyle(color: pal.muted))),
          for (final m in _menuItems)
            SwitchRow(
              label: t(m.$2),
              hint: m.$3 == null ? null : t(m.$3!),
              value: menuFlag(s, m.$1),
              onChanged: (v) => ref.read(settingsProvider.notifier).set({
                'menu': {...((s.j['menu'] as Map?) ?? Settings.defaults['menu'] as Map).cast<String, dynamic>(), m.$1: v},
              }),
            ),
        ];
      case 'audio':
        body = [
          SwitchRow(
            label: t('ИИ-диктор, когда нет записи'),
            hint: t('Если живой записи нет, главу прочитает синтезированный голос'),
            value: s.get<bool>('ttsFallback'),
            onChanged: (v) => ref.read(settingsProvider.notifier).set({'ttsFallback': v}),
          ),
          for (final b in audioSettingsExtras) b(context, ref),
        ];
      default:
        body = [
          // «Language» по-английски — чтобы найти строку, даже если случайно выбран незнакомый язык
          PrefRow(
            icon: null,
            leading: Text(flagEmoji(lang.flag), style: const TextStyle(fontSize: 24)),
            title: t('Язык'),
            sub: lang.name + (currentLang == 'ru' || currentLang == 'en' ? '' : ' · Language'),
            onTap: () => setState(() => _page = 'lang'),
          ),
          PrefRow(icon: Icons.menu_book_outlined, title: t('Инструкция'), sub: t('Пошаговые подсказки'), onTap: () => openHelp(context)),
          PrefRow(icon: Icons.palette_outlined, title: t('Оформление'), sub: t('Тема, шрифт, размер букв'), onTap: () => openAppearance(context)),
          PrefRow(icon: Icons.more_vert, title: t('Меню «Ещё»'), sub: t('Что показывать в разделе «Ещё»'), onTap: () => setState(() => _page = 'menu')),
          PrefRow(icon: Icons.headphones_outlined, title: t('Аудио'), sub: t('ИИ-диктор, книги без интернета'), onTap: () => setState(() => _page = 'audio')),
          PrefRow(icon: Icons.local_library_outlined, title: t('Библиотека модулей'), sub: t('Переводы, словари, аудиокниги'), onTap: () => openLibrary(context)),
          if (myData != null) PrefRow(icon: Icons.storage_outlined, title: t('Мои данные'), sub: t('Сохранить и перенести на новый телефон'), onTap: () => myData.run(widget.opener, ref, 0)),
          PrefRow(icon: Icons.auto_awesome_outlined, title: t('Что нового'), sub: t('Последнее обновление'), onTap: () => openNews(context)),
          if (Platform.isAndroid)
            PrefRow(
              icon: Icons.refresh,
              title: _available ? t('Обновить приложение') : t('Проверить обновления'),
              sub: _available ? t('Нажмите, чтобы обновить') : t('AO Bible · версия {v}', {'v': appVersion}),
              onTap: _checking ? null : _check,
              chevron: !_checking,
              extra: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : _available
                      ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(99)), child: Text(t('новая'), style: TextStyle(color: pal.onAccent, fontSize: 12, fontWeight: FontWeight.w700)))
                      : null,
            ),
          PrefRow(icon: Icons.info_outline, title: t('О приложении'), sub: t('Переводы, словари, авторы'), onTap: () => openAbout(context)),
        ];
    }
    return AppSheet(title: title, full: true, onBack: _page == null ? null : () => setState(() => _page = null), children: body);
  }
}
