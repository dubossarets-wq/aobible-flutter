// Настройки (PrefsSheet.jsx): короткий список крупных строк, каждая открывает своё окно или страницу:
// язык, инструкция, оформление, меню «Ещё», аудио, библиотека модулей, мои данные, что нового, обновления, о приложении.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
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

/// Флаг-эмодзи из кода страны
String flagEmoji(String cc) => cc.toUpperCase().codeUnits.map((c) => String.fromCharCode(0x1F1E6 + c - 65)).join();

/// Круглый флажок (Flag.jsx, .flag): середина флага, обрезка кругом, тонкая обводка. В веб-версии флаги нарисованы
/// своими упрощёнными картинками (Windows не рисует эмодзи-флаги); здесь — эмодзи-флаг системы, обрезанный кругом.
class Flag extends ConsumerWidget {
  const Flag(this.code, {super.key, this.size = 30});
  final String code;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = paletteOf(ref).dark;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      foregroundDecoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dark ? const Color(0x38FFFFFF) : const Color(0x2E000000))),
      child: FittedBox(fit: BoxFit.cover, child: Text(flagEmoji(code), style: const TextStyle(fontSize: 100, height: 1))),
    );
  }
}

// Название языка на языке интерфейса (второй строкой в списке языков): в русском интерфейсе — по-русски
const _ruNames = <String, String>{
  'uk': 'Украинский', 'ro': 'Румынский', 'en': 'Английский', 'es': 'Испанский', 'pt': 'Португальский', 'fr': 'Французский', 'de': 'Немецкий',
  'it': 'Итальянский', 'pl': 'Польский', 'be': 'Белорусский', 'bg': 'Болгарский', 'sr': 'Сербский', 'cs': 'Чешский', 'ka': 'Грузинский',
  'hy': 'Армянский', 'ko': 'Корейский', 'zh': 'Китайский', 'ja': 'Японский', 'id': 'Индонезийский', 'hi': 'Хинди', 'sw': 'Суахили',
};

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
        // .lang-list: флаг 30, название и ниже название на языке интерфейса, галочка у выбранного
        body = [
          Column(children: [
            for (var i = 0; i < langs.length; i++)
              _LangRow(
                l: langs[i],
                local: langs[i].code == currentLang || currentLang != 'ru' ? '' : (_ruNames[langs[i].code] ?? ''),
                on: langs[i].code == currentLang,
                last: i == langs.length - 1,
                onTap: () async {
                  await changeLanguage(ref, langs[i].code);
                  if (mounted) setState(() => _page = null);
                },
              ),
          ]),
        ];
      case 'menu':
        body = [
          Text(t('Отметьте, что показывать в разделе «Ещё» на нижней панели. Остальное всегда есть здесь, в настройках.'), style: TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted)),
          for (final m in _menuItems)
            SwitchField(
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
          SwitchField(
            label: t('ИИ-диктор, когда нет записи'),
            hint: t('Если живой записи нет, главу прочитает синтезированный голос'),
            value: s.get<bool>('ttsFallback'),
            onChanged: (v) => ref.read(settingsProvider.notifier).set({'ttsFallback': v}),
          ),
          for (final b in audioSettingsExtras) b(context, ref),
        ];
      default:
        final rows = <Widget Function(bool last)>[
          // «Language» по-английски — чтобы найти строку, даже если случайно выбран незнакомый язык
          (last) => PrefRow(
                icon: LucideIcons.globe,
                // .pref-row-flag: квадрат 38 с флажком 24 внутри
                leading: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: mix(pal.accent, 0.12, pal.bg), borderRadius: BorderRadius.circular(11)),
                  child: Flag(lang.flag, size: 24),
                ),
                title: t('Язык'),
                sub: lang.name + (currentLang == 'ru' || currentLang == 'en' ? '' : ' · Language'),
                onTap: () => setState(() => _page = 'lang'),
                last: last,
              ),
          (last) => PrefRow(icon: LucideIcons.bookOpenCheck, title: t('Инструкция'), sub: t('Пошаговые подсказки'), onTap: () => openHelp(context), last: last),
          (last) => PrefRow(icon: LucideIcons.palette, title: t('Оформление'), sub: t('Тема, шрифт, размер букв'), onTap: () => openAppearance(context), last: last),
          (last) => PrefRow(icon: LucideIcons.ellipsisVertical, title: t('Меню «Ещё»'), sub: t('Что показывать в разделе «Ещё»'), onTap: () => setState(() => _page = 'menu'), last: last),
          (last) => PrefRow(icon: LucideIcons.headphones, title: t('Аудио'), sub: t('ИИ-диктор, книги без интернета'), onTap: () => setState(() => _page = 'audio'), last: last),
          (last) => PrefRow(icon: LucideIcons.library, title: t('Библиотека модулей'), sub: t('Переводы, словари, аудиокниги'), onTap: () => openLibrary(context), last: last),
          if (myData != null) (last) => PrefRow(icon: LucideIcons.hardDrive, title: t('Мои данные'), sub: t('Сохранить и перенести на новый телефон'), onTap: () => myData.run(widget.opener, ref, 0), last: last),
          (last) => PrefRow(icon: LucideIcons.sparkles, title: t('Что нового'), sub: t('Последнее обновление'), onTap: () => openNews(context), last: last),
          if (Platform.isAndroid)
            (last) => PrefRow(
                  icon: LucideIcons.refreshCw,
                  title: _available ? t('Обновить приложение') : t('Проверить обновления'),
                  sub: _available ? t('Нажмите, чтобы обновить') : t('AO Bible · версия {v}', {'v': appVersion}),
                  onTap: _checking ? null : _check,
                  last: last,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_checking)
                      const Spin()
                    else ...[
                      if (_available)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          // .badge-new
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xffe0533d), borderRadius: BorderRadius.circular(99)),
                            child: Text(t('новая'), style: const TextStyle(color: Colors.white, fontSize: 11.8, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      Icon(LucideIcons.chevronRight, size: 18, color: pal.muted),
                    ],
                  ]),
                ),
          (last) => PrefRow(icon: LucideIcons.info, title: t('О приложении'), sub: t('Переводы, словари, авторы'), onTap: () => openAbout(context), last: last),
        ];
        body = [Column(children: [for (var i = 0; i < rows.length; i++) rows[i](i == rows.length - 1)])];
    }
    return AppSheet(title: title, onBack: _page == null ? null : () => setState(() => _page = null), children: body);
  }
}

/// Строка выбора языка (.lang-row)
class _LangRow extends ConsumerWidget {
  const _LangRow({required this.l, required this.local, required this.on, required this.last, required this.onTap});
  final Lang l;
  final String local;
  final bool on, last;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(color: on ? pal.accent.withValues(alpha: 0.08) : null, border: last ? null : Border(bottom: BorderSide(color: pal.line))),
        child: Row(children: [
          Flag(l.flag, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: TextStyle(fontSize: 16.6, fontWeight: FontWeight.w600, color: pal.text)),
              if (local.isNotEmpty && local.toLowerCase() != l.name.toLowerCase()) Padding(padding: const EdgeInsets.only(top: 1), child: Text(local, style: TextStyle(fontSize: 13.4, color: pal.muted))),
            ]),
          ),
          if (on) Icon(LucideIcons.check, size: 20, color: pal.accent),
        ]),
      ),
    );
  }
}
