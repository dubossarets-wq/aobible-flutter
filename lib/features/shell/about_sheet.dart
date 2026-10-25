// О приложении (About.jsx, src/core/licenses.js): что это, авторы и лицензии всех модулей каталога, программы и
// шрифты, политика конфиденциальности, контакты. Лицензии CC BY / BY-SA / BY-NC требуют указывать авторов —
// здесь они все в одном месте.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../plans/net_cache.dart' show siteJson;
import 'colors.dart';
import 'library_sheet.dart' show moduleSections;
import 'sheet.dart';

/// Версия приложения (совпадает с version в pubspec.yaml; правится вместе с ним)
const appVersion = '1.0.0';
const supportEmail = 'dubossarets@gmail.com';
const telegramUrl = 'https://t.me/bystreetsky';

// Логотип Telegram (самолётик в круге), одним цветом — контур из Simple Icons (CC0)
const _telegramLogo =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>';

Future<void> openAbout(BuildContext context, {String tab = 'about'}) => showAppSheet(context, (_) => AboutSheet(tab: tab));

Future<void> openLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

// --- Ссылки на тексты лицензий (CC BY и BY-SA требуют давать ссылку на лицензию, GPL — на её текст) ---------------------

String? licenseUrl(String? text) {
  final s = text ?? '';
  if (RegExp(r'CC0|Public Domain Dedication', caseSensitive: false).hasMatch(s)) return 'https://creativecommons.org/publicdomain/zero/1.0/';
  final m = RegExp(r'CC[ -]BY(-NC)?(-SA|-ND)?(?:[ -](\d\.\d))?(?:\s*(US))?', caseSensitive: false).firstMatch(s);
  if (m != null) {
    final kind = ['by', if (m.group(1) != null) 'nc', if (m.group(2) != null) m.group(2)!.substring(1)].join('-').toLowerCase();
    return 'https://creativecommons.org/licenses/$kind/${m.group(3) ?? '4.0'}/${m.group(4) != null ? 'us/' : ''}';
  }
  if (RegExp(r'GPL[- ]?3', caseSensitive: false).hasMatch(s)) return 'https://www.gnu.org/licenses/gpl-3.0.html';
  if (RegExp('ODbL', caseSensitive: false).hasMatch(s)) return 'https://opendatacommons.org/licenses/odbl/1-0/';
  if (RegExp('Open Font License|OFL', caseSensitive: false).hasMatch(s)) return 'https://openfontlicense.org';
  if (RegExp(r'MPL[- ]?2', caseSensitive: false).hasMatch(s)) return 'https://www.mozilla.org/MPL/2.0/';
  return null;
}

// Дополнительные строки атрибуции, которых требуют правообладатели отдельных модулей
const _biblica = 'The original work by Biblica, Inc. is available for free at www.biblica.com and open.bible.';
const _extra = <String, List<String>>{
  'ukr-nup': [_biblica], 'nbv-pt': [_biblica], 'slowo-zycia': [_biblica], 'ccb': [_biblica], 'swh-neno': [_biblica], 'bible-maps': [_biblica],
  'audio-grc-phemister': ['© 2001 Marilyn Phemister'],
  'lxx-swete': ['https://github.com/eliranwong/LXX-Swete-1930'],
};

// Сторонние программы, шрифты и службы, которые использует само приложение
const _thirdParty = <(String, String, String, String)>[
  ('Flutter', 'Google', 'BSD-3-Clause', 'https://flutter.dev'),
  ('Riverpod', 'Remi Rousselet', 'MIT', 'https://riverpod.dev'),
  ('SQLite / sqlite3.dart', 'SQLite Consortium; Simon Binder', 'Public Domain / MIT', 'https://sqlite.org'),
  ('just_audio, audio_service', 'Ryan Heise', 'MIT', 'https://pub.dev/packages/just_audio'),
  ('MapLibre GL', 'MapLibre contributors', 'BSD-3-Clause', 'https://maplibre.org'),
  ('OpenFreeMap / OpenStreetMap', '© OpenStreetMap contributors', 'ODbL', 'https://openfreemap.org'),
  ('Sentinel-2 cloudless 2016 (EOX)', 'EOX IT Services GmbH; contains modified Copernicus Sentinel data 2016', 'CC BY 4.0', 'https://s2maps.eu'),
  ('PT Serif, PT Sans', 'ParaType', 'SIL Open Font License 1.1', 'https://fonts.google.com/specimen/PT+Serif'),
  ('Literata', 'TypeTogether', 'SIL Open Font License 1.1', 'https://fonts.google.com/specimen/Literata'),
  ('Noto Serif, Noto Serif Hebrew', 'Google', 'SIL Open Font License 1.1', 'https://fonts.google.com/noto'),
  ('Lora', 'Cyreal', 'SIL Open Font License 1.1', 'https://fonts.google.com/specimen/Lora'),
  ('IBM Plex Sans', 'IBM', 'SIL Open Font License 1.1', 'https://fonts.google.com/specimen/IBM+Plex+Sans'),
  // разметка записей по словам при сборке; в само приложение модель не входит
  ('Torchaudio MMS_FA (forced alignment)', 'Meta AI', 'CC BY-NC 4.0', 'https://pytorch.org/audio'),
];

class AboutSheet extends ConsumerStatefulWidget {
  const AboutSheet({super.key, this.tab = 'about'});
  final String tab;
  @override
  ConsumerState<AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends ConsumerState<AboutSheet> {
  late String _tab = widget.tab;
  List<CatalogEntry>? _cat;
  List<Map<String, dynamic>> _photos = []; // фото стиха дня, планов и картинок со стихом

  @override
  void initState() {
    super.initState();
    siteJson('images/verse-bg/index.json').then((j) {
      final l = ((j?['images'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) setState(() => _photos = l);
    }, onError: (_) {});
    ModuleStore.instance.catalog().then((c) {
      if (mounted) setState(() => _cat = c.where((m) => !m.unavailable).toList());
    }, onError: (_) {
      if (mounted) setState(() => _cat = []);
    });
  }

  Widget _link(String text, String url, Palette pal) => InkWell(onTap: () => openLink(url), child: Text(text, style: TextStyle(color: pal.accent, decoration: TextDecoration.underline, fontSize: 14)));

  Widget _line(List<Widget> parts) => Padding(padding: const EdgeInsets.only(top: 2), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts));
  @override

  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final body = switch (_tab) {
      'licenses' => _licenses(pal),
      'privacy' => _privacy(pal),
      _ => _about(pal),
    };
    return AppSheet(
      title: t('О приложении'),
      subtitle: t('AO Bible · версия {v}', {'v': appVersion}),
      gap: 12,
      // вкладки закреплены над текстом, линия — от края до края
      fixed: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: AobTabs<String>(
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          tabs: [('about', t('О приложении'), null), ('licenses', t('Лицензии и авторы'), null), ('privacy', t('Конфиденциальность'), null)],
        ),
      ),
      children: [
        // .prose: интервал 1.55, абзацы без промежутков
        DefaultTextStyle.merge(style: const TextStyle(height: 1.55), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)),
      ],
    );
  }

  Widget _p(String text) => Text(text);

  /// Заголовок группы в тексте (.prose h4)
  Widget _h4(String text, Palette pal) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(text, style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted)));

  /// Пункт маркированного списка (.lic-list li): чёрная точка слева, отступ 18, зазор 8
  Widget _li(List<Widget> parts, {double gap = 8}) => Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(width: 18, child: Padding(padding: EdgeInsets.only(left: 4, top: 1), child: Text('•'))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts)),
        ]),
      );

  List<Widget> _about(Palette pal) => [
        _p(t('AO Bible — бесплатное приложение для чтения и изучения Библии, без рекламы и регистрации: переводы, подстрочник с ивритом и греческим, словари Стронга на русском, параллельные места, иллюстрации, живое чтение, проповеди и планы чтения.')),
        _p(t('Приложение некоммерческое: часть материалов (подстрочник А. Винокурова, записи чтения на иврите и греческом) используется с разрешения авторов или по лицензиям, которые разрешают только бесплатное распространение.')),
        _p(t('Всё хранится на вашем устройстве; скачанные модули работают без интернета.')),
        const SizedBox(height: 24),
        PrefRow(icon: LucideIcons.mail, title: supportEmail, onTap: () => openLink('mailto:$supportEmail')),
        PrefRow(
          icon: LucideIcons.send,
          title: 'Telegram',
          sub: telegramUrl,
          onTap: () => openLink(telegramUrl),
          last: true,
          leading: SizedBox(width: 38, height: 38, child: Center(child: SvgPicture.string(_telegramLogo, width: 30, height: 30, colorFilter: ColorFilter.mode(pal.text, BlendMode.srcIn)))),
        ),
      ];

  List<Widget> _licenses(Palette pal) {
    final cat = _cat;
    if (cat == null) return [Loading(t('Загрузка…'))];
    // Нет сети — хотя бы установленные модули
    final items = cat.isNotEmpty ? cat.map((c) => c.json).toList() : ModuleStore.instance.installed.map((m) => m.meta).toList();
    final small = TextStyle(color: pal.muted, fontSize: 13.2, height: 1.55);
    return [
      _p(t('Тексты, словари, записи и иллюстрации взяты из свободных источников (общественное достояние и открытые лицензии) или используются с разрешения авторов. У каждой иллюстрации автор и лицензия указаны под картинкой.')),
      for (final sec in moduleSections)
        if (items.any((m) => (m['type'] ?? 'bible') == sec.$1)) ...[
          _h4(t(sec.$2), pal),
          for (final m in items.where((m) => (m['type'] ?? 'bible') == sec.$1))
            _li([
              Text.rich(TextSpan(children: [
                TextSpan(text: '${m['name'] ?? m['id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((m['title'] ?? '') != '') TextSpan(text: ' — ${m['title']}'),
              ])),
              if (m['author'] != null) Text(t('Авторы: {author}.', {'author': '${m['author']}'}), style: small),
              if (m['license'] != null)
                _line([
                  Text('${t('Лицензия:')} ', style: small),
                  licenseUrl('${m['license']}') != null ? _link('${m['license']}', licenseUrl('${m['license']}')!, pal) : Text('${m['license']}', style: small),
                ]),
              for (final x in _extra[m['id']] ?? const <String>[]) x.startsWith('http') ? _line([_link(x, x, pal)]) : Text(x, style: small),
              if (m['source'] != null)
                _line([
                  Text('${t('Источник:')} ', style: small),
                  RegExp(r'^https?://\S+$').hasMatch('${m['source']}') ? _link('${m['source']}', '${m['source']}', pal) : Text('${m['source']}', style: small),
                ]),
            ]),
        ],
      if (_photos.isNotEmpty) ...[
        _h4(t('Фотографии'), pal),
        for (final p in _photos)
          _li([
            Text(t('${p['title'] ?? p['id']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            _line([
              Text(p['author'] != null ? '${p['author']} · ' : '', style: small),
              if (p['license'] != null) (licenseUrl('${p['license']}') != null ? _link('${p['license']}', licenseUrl('${p['license']}')!, pal) : Text('${p['license']}', style: small)),
            ]),
            if (p['source'] != null) _line([Text('${t('Источник:')} ', style: small), _link('${p['source']}'.replaceFirst('https://', ''), '${p['source']}', pal)]),
          ]),
      ],
      _h4(t('Программы и службы'), pal),
      for (final x in _thirdParty)
        _li([
          Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
          _line([Text('${x.$2} · ${x.$3} · ', style: small), _link(x.$4.replaceFirst('https://', ''), x.$4, pal)]),
        ]),
    ];
  }

  List<Widget> _privacy(Palette pal) {
    return [
      Padding(padding: const EdgeInsets.only(bottom: 0), child: Text(t('Коротко: приложение ничего о вас не собирает.'), style: const TextStyle(fontWeight: FontWeight.w700))),
      const SizedBox(height: 6),
      for (final x in [
        t('Нет регистрации, рекламы, счётчиков посещений и аналитики. Мы не получаем ваши данные и никому их не передаём.'),
        t('Закладки, заметки, выделения, проповеди, планы чтения и настройки хранятся только на вашем устройстве (в памяти браузера). Их можно сохранить в файл: Настройки → «Мои данные».'),
        t('Чтобы показать текст и материалы, приложение загружает файлы с нескольких сайтов. Как и при открытии любого сайта, эти сайты видят адрес вашего подключения (IP) и тип браузера:'),
      ])
        _li([Text(x)], gap: 6),
      const SizedBox(height: 2),
      for (final x in [
        t('GitHub Pages — само приложение и модули (переводы, словари).'),
        t('archive.org — записи чтения Библии.'),
        t('Wikimedia Commons — иллюстрации к стихам.'),
        t('Google Fonts — шрифты для иврита и греческого.'),
        t('OpenFreeMap, EOX и jsDelivr — карты (только когда вы открываете карту).'),
      ])
        _li([Text(x)]),
      const SizedBox(height: 4),
      _p(t('Мы не управляем этими сайтами; у каждого из них своя политика конфиденциальности.')),
      _p(t('Доступ к микрофону, камере, контактам и местоположению приложению не нужен и не запрашивается.')),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${t('Вопросы и предложения:')} '),
        _link(supportEmail, 'mailto:$supportEmail', pal),
        const Text(' · '),
        _link('Telegram', telegramUrl, pal),
      ]),
    ];
  }
}
