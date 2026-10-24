// О приложении (About.jsx, src/core/licenses.js): что это, авторы и лицензии всех модулей каталога, программы и
// шрифты, политика конфиденциальности, контакты. Лицензии CC BY / BY-SA / BY-NC требуют указывать авторов —
// здесь они все в одном месте.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'colors.dart';
import 'library_sheet.dart' show moduleSections;
import 'sheet.dart';

/// Версия приложения (совпадает с version в pubspec.yaml; правится вместе с ним)
const appVersion = '1.0.0';
const supportEmail = 'dubossarets@gmail.com';
const telegramUrl = 'https://t.me/bystreetsky';

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

  @override
  void initState() {
    super.initState();
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
    Widget p(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text, style: const TextStyle(fontSize: 15.5, height: 1.45)));
    final body = switch (_tab) {
      'licenses' => _licenses(pal, p),
      'privacy' => _privacy(pal, p),
      _ => [
          p(t('AO Bible — бесплатное приложение для чтения и изучения Библии, без рекламы и регистрации: переводы, подстрочник с ивритом и греческим, словари Стронга на русском, параллельные места, иллюстрации, живое чтение, проповеди и планы чтения.')),
          p(t('Приложение некоммерческое: часть материалов (подстрочник А. Винокурова, записи чтения на иврите и греческом) используется с разрешения авторов или по лицензиям, которые разрешают только бесплатное распространение.')),
          p(t('Всё хранится на вашем устройстве; скачанные модули работают без интернета.')),
          const SizedBox(height: 6),
          PrefRow(icon: Icons.mail_outline, title: supportEmail, onTap: () => openLink('mailto:$supportEmail')),
          PrefRow(icon: Icons.send_outlined, title: 'Telegram', sub: telegramUrl, onTap: () => openLink(telegramUrl)),
        ],
    };
    return AppSheet(
      title: t('О приложении'),
      subtitle: t('AO Bible · версия {v}', {'v': appVersion}),
      full: true,
      fixed: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'about', label: Text(t('О приложении'), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: 'licenses', label: Text(t('Лицензии и авторы'), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: 'privacy', label: Text(t('Конфиденциальность'), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ),
      ),
      children: body,
    );
  }

  List<Widget> _licenses(Palette pal, Widget Function(String) p) {
    final cat = _cat;
    if (cat == null) {
      return [Padding(padding: const EdgeInsets.all(24), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text(t('Загрузка…'))])))];
    }
    // Нет сети — хотя бы установленные модули
    final items = cat.isNotEmpty ? cat.map((c) => c.json).toList() : ModuleStore.instance.installed.map((m) => m.meta).toList();
    return [
      p(t('Тексты, словари, записи и иллюстрации взяты из свободных источников (общественное достояние и открытые лицензии) или используются с разрешения авторов. У каждой иллюстрации автор и лицензия указаны под картинкой.')),
      for (final sec in moduleSections)
        if (items.any((m) => (m['type'] ?? 'bible') == sec.$1)) ...[
          Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 4), child: Text(t(sec.$2), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          for (final m in items.where((m) => (m['type'] ?? 'bible') == sec.$1))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${m['name'] ?? m['id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((m['title'] ?? '') != '') TextSpan(text: ' — ${m['title']}'),
                ])),
                if (m['author'] != null) Text(t('Авторы: {author}.', {'author': '${m['author']}'}), style: TextStyle(color: pal.muted, fontSize: 14)),
                if (m['license'] != null)
                  _line([
                    Text('${t('Лицензия:')} ', style: TextStyle(color: pal.muted, fontSize: 14)),
                    licenseUrl('${m['license']}') != null ? _link('${m['license']}', licenseUrl('${m['license']}')!, pal) : Text('${m['license']}', style: TextStyle(color: pal.muted, fontSize: 14)),
                  ]),
                for (final x in _extra[m['id']] ?? const <String>[]) x.startsWith('http') ? _line([_link(x, x, pal)]) : Text(x, style: TextStyle(color: pal.muted, fontSize: 14)),
                if (m['source'] != null)
                  _line([
                    Text('${t('Источник:')} ', style: TextStyle(color: pal.muted, fontSize: 14)),
                    RegExp(r'^https?://\S+$').hasMatch('${m['source']}') ? _link('${m['source']}', '${m['source']}', pal) : Text('${m['source']}', style: TextStyle(color: pal.muted, fontSize: 14)),
                  ]),
              ]),
            ),
        ],
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 4), child: Text(t('Программы и службы'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      for (final x in _thirdParty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${x.$2} · ${x.$3}', style: TextStyle(color: pal.muted, fontSize: 14)),
            _line([_link(x.$4.replaceFirst('https://', ''), x.$4, pal)]),
          ]),
        ),
    ];
  }

  List<Widget> _privacy(Palette pal, Widget Function(String) p) {
    Widget li(String text) => Padding(padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, height: 1.4)))]));
    return [
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('Коротко: приложение ничего о вас не собирает.'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
      li(t('Нет регистрации, рекламы, счётчиков посещений и аналитики. Мы не получаем ваши данные и никому их не передаём.')),
      li(t('Закладки, заметки, выделения, проповеди, планы чтения и настройки хранятся только на вашем устройстве (в памяти браузера). Их можно сохранить в файл: Настройки → «Мои данные».')),
      li(t('Чтобы показать текст и материалы, приложение загружает файлы с нескольких сайтов. Как и при открытии любого сайта, эти сайты видят адрес вашего подключения (IP) и тип браузера:')),
      for (final x in [
        t('GitHub Pages — само приложение и модули (переводы, словари).'),
        t('archive.org — записи чтения Библии.'),
        t('Wikimedia Commons — иллюстрации к стихам.'),
        t('Google Fonts — шрифты для иврита и греческого.'),
        t('OpenFreeMap, EOX и jsDelivr — карты (только когда вы открываете карту).'),
      ])
        Padding(padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2), child: Text('– $x', style: TextStyle(fontSize: 14.5, color: pal.muted))),
      p(t('Мы не управляем этими сайтами; у каждого из них своя политика конфиденциальности.')),
      p(t('Доступ к микрофону, камере, контактам и местоположению приложению не нужен и не запрашивается.')),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          Text(t('Вопросы и предложения:')),
          _link(supportEmail, 'mailto:$supportEmail', pal),
          const Text('·'),
          _link('Telegram', telegramUrl, pal),
        ]),
      ),
    ];
  }
}
