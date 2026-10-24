// Оформление (AppearanceSettings.jsx): сверху живой образец текста, под ним тема, размер, вид текста;
// ниже подразделы — шрифт, номера и заголовки, цвета, кнопки и панели; внизу — сброс. Всё применяется сразу.
// Не перенесено: фон-картинка и комментарии (нужны хранилище картинок и модули толкований — другие функции).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'colors.dart';
import 'fonts.dart';
import 'sheet.dart';

Future<void> openAppearance(BuildContext context, {String? block}) => showAppSheet(context, (_) => AppearanceSheet(block: block));

// Готовые цвета для акцента, верхней панели, номеров Стронга и заголовков
const _accents = <(String, String)>[
  ('#8c5e28', 'Коричневый'), ('#b4412f', 'Красный'), ('#c2410c', 'Оранжевый'), ('#a16207', 'Горчичный'), ('#3f7a4a', 'Зелёный'),
  ('#0f766e', 'Бирюзовый'), ('#2563eb', 'Синий'), ('#4f46e5', 'Индиго'), ('#7c3aed', 'Фиолетовый'), ('#be185d', 'Малиновый'),
];
const _bars = <(String, String)>[
  ('#38363a', 'Графит'), ('#0c0c0d', 'Чёрный'), ('#4a3d2f', 'Коричневый'), ('#1e3a5f', 'Тёмно-синий'),
  ('#14532d', 'Тёмно-зелёный'), ('#5b2333', 'Бордовый'), ('#ffffff', 'Белый'), ('#f3f1ec', 'Светлый'),
];

// Всё, что относится к оформлению: «Сбросить оформление» возвращает только это
const _lookKeys = [
  'theme', 'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'verseSpacing', 'textWidth', 'textAlign', 'showVerseNumbers', 'chapterTitleSize',
  'showStrongs', 'showHeadings', 'showXrefButtons', 'showIllustrations', 'continuousVerses', 'bookMode', 'colorOverrides', 'strongSize', 'strongPos',
  'verseNumSize', 'verseNumPos', 'headingSize', 'uiFontSize', 'barHeight', 'animations', 'focusMode', 'splitLayout', 'commentaryFontSize',
];

// Понятные значения вместо чисел
String Function(double) _words(double lo, double hi, String a, String b, String c) => (v) => t(v < lo ? a : v <= hi ? b : c);
String Function(double) _sizeW(double lo, double hi) => _words(lo, hi, 'мелкий', 'обычный', 'крупный');
final _lhW = _words(1.32, 1.62, 'плотный', 'обычный', 'свободный');
String _gapW(double v) => v < 0.05 ? t('нет') : _words(0.35, 0.85, 'маленькое', 'обычное', 'большое')(v);
final _widthW = _words(36, 56, 'узкая', 'обычная', 'широкая');
final _barW = _words(50, 58, 'низкая', 'обычная', 'высокая');
const _weights = {300: 'тонкий', 400: 'обычный', 500: 'средний', 600: 'полужирный', 700: 'жирный'};
const _pos = {'sup': 'Над строкой', 'inline': 'В строке', 'sub': 'Под строкой'};

String textView(Settings s) => s.get<bool>('bookMode') ? 'book' : s.get<bool>('continuousVerses') ? 'flow' : 'verses';

// --- Образец текста ----------------------------------------------------------------------------------------------

/// Образец: Быт 1:1–2 с заголовком, как в веб-версии; в первом стихе номер Стронга — {номер} сразу после слова.
/// short — только первый стих; noText — без стихов (кнопки и панели); live — номера и заголовки видны всегда
class Sample extends StatelessWidget {
  const Sample({super.key, required this.s, this.bar = false, this.head = false, this.sn = false, this.ui = false, this.short = false, this.noText = false, this.live = false});
  final Settings s;
  final bool bar, head, sn, ui, short, noText, live;

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(s);
    final fs = s.d('fontSize');
    final view = textView(s);
    final showNum = (live || s.get<bool>('showVerseNumbers')) && view != 'book';
    final strongs = live || s.get<bool>('showStrongs');
    final base = readerTextStyle(s).copyWith(color: pal.text, height: s.d('lineHeight'));

    InlineSpan num(int n) => WidgetSpan(
          alignment: s.get<String>('verseNumPos') == 'inline' ? PlaceholderAlignment.middle : PlaceholderAlignment.top,
          child: Padding(padding: EdgeInsets.only(right: fs * 0.2), child: Text('$n', style: TextStyle(fontSize: fs * s.d('verseNumSize'), color: pal.verseNum, height: 1))),
        );
    List<InlineSpan> v1() {
      final parts = t('В начале{7225} сотворил{1254} Бог{430} небо{8064} и{853} землю.{776}').split(RegExp(r'\{(\d+)\}'));
      // split без групп теряет номера — берём их отдельно
      final nums = RegExp(r'\{(\d+)\}').allMatches(t('В начале{7225} сотворил{1254} Бог{430} небо{8064} и{853} землю.{776}')).map((m) => m.group(1)!).toList();
      final pos = s.get<String>('strongPos');
      final out = <InlineSpan>[];
      for (var i = 0; i < parts.length; i++) {
        out.add(TextSpan(text: parts[i]));
        if (i < nums.length && strongs && (sn || s.get<bool>('showStrongs'))) {
          out.add(WidgetSpan(
            alignment: pos == 'inline' ? PlaceholderAlignment.baseline : pos == 'sub' ? PlaceholderAlignment.bottom : PlaceholderAlignment.top,
            baseline: TextBaseline.alphabetic,
            child: Text(nums[i], style: TextStyle(fontSize: fs * s.d('strongSize'), color: strongColor(s), height: 1)),
          ));
        }
      }
      return out;
    }

    final v2 = TextSpan(text: t('Земля же была безвидна и пуста, и тьма над бездною, и Дух Божий носился над водою.'));
    Widget para(List<InlineSpan> spans, {double bottom = 0}) => Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Text.rich(TextSpan(children: spans), style: base, textAlign: view == 'book' ? TextAlign.justify : textAlignOf(s)),
        );
    final gap = fs * s.d('verseSpacing');
    final verses = <Widget>[
      if (!noText)
        if (view == 'verses' || short) ...[
          para([if (showNum) num(1), ...v1()], bottom: short ? 0 : gap),
          if (!short) para([if (showNum) num(2), v2]),
        ] else
          para([if (showNum) num(1), ...v1(), const TextSpan(text: ' '), if (showNum) num(2), v2]),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (bar)
          Container(
            height: 40,
            color: pal.bar,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: pal.barText.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)), child: Text('RST+', style: TextStyle(color: pal.barText, fontWeight: FontWeight.w700, fontSize: 13))),
              const SizedBox(width: 8),
              Text('${t('Быт')} 1:1', style: TextStyle(color: pal.barText, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (head && !noText && (live || s.get<bool>('showHeadings')))
              Padding(padding: EdgeInsets.only(bottom: fs * 0.4), child: Text(t('Сотворение неба и земли'), style: readerTextStyle(s, size: fs * s.d('headingSize'), weight: 700).copyWith(color: headingColor(s), height: 1.3))),
            ...verses,
            if (ui)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(10)), child: Text(t('Кнопка'), style: TextStyle(color: pal.onAccent, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Окно или карточка'), style: TextStyle(color: pal.text)),
                        Text(t('бледный текст'), style: TextStyle(color: pal.muted, fontSize: 13)),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// --- Окно ---------------------------------------------------------------------------------------------------------

class AppearanceSheet extends ConsumerStatefulWidget {
  const AppearanceSheet({super.key, this.block});
  final String? block;
  @override
  ConsumerState<AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends ConsumerState<AppearanceSheet> {
  late String? _block = widget.block;
  String? _live; // какой цвет сейчас выбирают в палитре — образец вверху показывает, где он виден

  static const _blocks = <(String, IconData, String)>[
    ('font', Icons.text_fields, 'Шрифт'),
    ('nums', Icons.tag, 'Номера и заголовки'),
    ('colors', Icons.palette_outlined, 'Цвета'),
    ('ui', Icons.web_asset_outlined, 'Кнопки и панели'),
  ];

  void set(Map<String, dynamic> p) => ref.read(settingsProvider.notifier).set(p);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final cur = _blocks.where((b) => b.$1 == _block).firstOrNull;
    final title = cur != null ? t(cur.$3) : t('Оформление');
    final children = switch (_block) {
      'font' => _font(s),
      'nums' => _nums(s),
      'colors' => _colors(s),
      'ui' => _ui(s),
      _ => _main(s, pal),
    };
    return AppSheet(
      title: title,
      full: true,
      onBack: cur != null ? () => setState(() => _block = null) : null,
      // образец закреплён вверху: при прокрутке настроек остаётся на виду
      fixed: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: _block == 'ui'
            ? Sample(s: s, bar: true, ui: true, noText: true)
            : _block == 'colors'
                ? Sample(s: s, bar: true, head: true, sn: true, ui: true, short: true, live: true)
                : _live != null
                    ? Sample(s: s, live: true, bar: _live == 'bar' || _live == 'barText', head: _live == 'heading', sn: _live == 'strong', short: true)
                    : ConstrainedBox(constraints: const BoxConstraints(maxHeight: 190), child: SingleChildScrollView(child: Sample(s: s, head: true))),
      ),
      children: children,
    );
  }

  List<Widget> _main(Settings s, Palette pal) {
    final nums = [if (s.get<bool>('showVerseNumbers')) t('Номера стихов'), if (s.get<bool>('showStrongs')) t('Номера Стронга'), if (s.get<bool>('showHeadings')) t('Заголовки разделов')];
    final over = overridesOf(s);
    final subs = {
      'font': t(fontOf(s).label),
      'nums': nums.isEmpty ? t('выкл') : nums.join(', '),
      'colors': over.isEmpty ? t('Как в теме') : t('Свои цвета: {n}', {'n': '${over.length}'}),
      'ui': [if (s.get<bool>('focusMode')) t('Режим чтения'), t('Кнопки в тексте, меню, верхняя панель')].join(' · '),
    };
    return [
      _label(t('Тема'), pal),
      SizedBox(
        height: 92,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in themes.entries) _ThemeTile(id: e.key, p: e.value, on: s.get<String>('theme') == e.key, onTap: () => set({'theme': e.key})),
        ]),
      ),
      RangeRow(label: t('Размер текста'), big: true, value: s.d('fontSize'), min: 13, max: 40, step: 1, onChanged: (v) => set({'fontSize': v}), word: (v) => '${v.round()} px'),
      _label(t('Вид текста'), pal),
      Row(children: [
        for (final k in const ['verses', 'flow', 'book'])
          Expanded(
            child: _ViewTile(
              kind: k,
              name: t(const {'verses': 'По стихам', 'flow': 'Сплошной', 'book': 'Как книга'}[k]!),
              on: textView(s) == k,
              onTap: () => set({'bookMode': k == 'book', 'continuousVerses': k == 'flow'}),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      for (final b in _blocks) PrefRow(icon: b.$2, title: t(b.$3), sub: subs[b.$1], onTap: () => setState(() => _block = b.$1)),
      const SizedBox(height: 8),
      Center(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(t('Сбросить оформление')),
          onPressed: () async {
            if (!await confirm(context, t('Сбросить оформление'), t('Да, сбросить'))) return;
            set({for (final k in _lookKeys) k: Settings.defaults[k]});
            if (mounted) toast(context, t('Оформление сброшено'));
          },
        ),
      ),
    ];
  }

  Widget _label(String text, Palette pal) => Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)));

  List<Widget> _font(Settings s) {
    final pal = effectivePalette(s);
    final w = s.d('fontWeight').round();
    return [
      for (final e in fontDefs.entries)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => set({'fontFamily': e.key}),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('В начале было Слово'), style: readerTextStyle(s, size: 20, font: e.value, weight: 400).copyWith(color: pal.text)),
                  Text(t(e.value.label), style: TextStyle(fontSize: 13, color: pal.muted)),
                ]),
              ),
              if (s.get<String>('fontFamily') == e.key) Icon(Icons.check, color: pal.accent),
            ]),
          ),
        ),
      Card2(children: [
        SegRow<int>(
          label: t('Толщина'),
          valueText: t(_weights[w] ?? 'обычный'),
          value: _weights.containsKey(w) ? w : 400,
          options: [for (final k in _weights.keys) (k, t('Аа'), null)],
          labelStyle: (k) => TextStyle(fontWeight: weightOf(k.toDouble())),
          onChanged: (v) => set({'fontWeight': v}),
        ),
        RangeRow(label: t('Межстрочный интервал'), value: s.d('lineHeight'), min: 1.1, max: 2.2, step: 0.05, onChanged: (v) => set({'lineHeight': v}), word: _lhW),
        RangeRow(label: t('Расстояние между стихами'), value: s.d('verseSpacing'), min: 0, max: 1.6, step: 0.05, onChanged: (v) => set({'verseSpacing': v}), word: _gapW),
        RangeRow(label: t('Ширина текста'), hint: t('Заметно на широком экране'), value: s.d('textWidth'), min: 24, max: 80, step: 1, onChanged: (v) => set({'textWidth': v}), word: _widthW),
        SegRow<String>(
          label: t('Выравнивание'),
          value: s.get<String>('textAlign'),
          options: [('left', t('По левому краю'), Icons.format_align_left), ('justify', t('По ширине'), Icons.format_align_justify)],
          onChanged: (v) => set({'textAlign': v}),
        ),
      ]),
    ];
  }

  List<Widget> _nums(Settings s) {
    final pal = effectivePalette(s);
    final over = overridesOf(s);
    Widget mini(List<InlineSpan> spans) => Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 6), child: Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: pal.muted)));
    final plain = t('В начале{7225} сотворил{1254} Бог{430} небо{8064} и{853} землю.{776}').replaceAll(RegExp(r'\{\d+\}'), '');
    return [
      Card2(children: [
        SwitchRow(label: t('Номера стихов'), value: s.get<bool>('showVerseNumbers'), onChanged: (v) => set({'showVerseNumbers': v})),
        mini([if (s.get<bool>('showVerseNumbers')) TextSpan(text: '1 ', style: TextStyle(color: pal.verseNum, fontSize: 11)), TextSpan(text: plain)]),
        if (s.get<bool>('showVerseNumbers')) ...[
          RangeRow(label: t('Размер'), value: s.d('verseNumSize'), min: 0.4, max: 1.2, step: 0.05, onChanged: (v) => set({'verseNumSize': v}), word: _sizeW(0.52, 0.8)),
          SegRow<String>(label: t('Положение'), value: s.get<String>('verseNumPos'), options: [for (final k in const ['sup', 'inline']) (k, t(_pos[k]!), null)], onChanged: (v) => set({'verseNumPos': v})),
        ],
      ]),
      Card2(children: [
        SwitchRow(label: t('Номера Стронга'), hint: t('Только в переводах с номерами Стронга, например RST+'), value: s.get<bool>('showStrongs'), onChanged: (v) => set({'showStrongs': v})),
        if (s.get<bool>('showStrongs')) ...[
          RangeRow(label: t('Размер'), value: s.d('strongSize'), min: 0.35, max: 1, step: 0.05, onChanged: (v) => set({'strongSize': v}), word: _sizeW(0.45, 0.7)),
          SegRow<String>(label: t('Положение'), value: s.get<String>('strongPos'), options: [for (final k in const ['sup', 'inline', 'sub']) (k, t(_pos[k]!), null)], onChanged: (v) => set({'strongPos': v})),
          _ColorPick(label: t('Цвет'), s: s, colorKey: 'strong', list: _accents, onChanged: (v) => _setColor('strong', v), onReset: () => _resetColors(['strong']), changed: over['strong'] != null),
        ],
      ]),
      Card2(children: [
        SwitchRow(label: t('Заголовки разделов'), value: s.get<bool>('showHeadings'), onChanged: (v) => set({'showHeadings': v})),
        if (s.get<bool>('showHeadings')) ...[
          RangeRow(label: t('Размер'), value: s.d('headingSize'), min: 0.6, max: 1.4, step: 0.05, onChanged: (v) => set({'headingSize': v}), word: _sizeW(0.72, 1)),
          _ColorPick(label: t('Цвет'), s: s, colorKey: 'heading', list: _accents, onChanged: (v) => _setColor('heading', v), onReset: () => _resetColors(['heading']), changed: over['heading'] != null),
        ],
      ]),
      Card2(title: t('Заголовки глав'), children: [
        RangeRow(label: t('Размер'), value: s.d('chapterTitleSize'), min: 1.1, max: 3.2, step: 0.1, onChanged: (v) => set({'chapterTitleSize': v}), word: _sizeW(1.7, 2.5)),
      ]),
    ];
  }

  void _setColor(String k, Color c) => set({'colorOverrides': {...overridesOf(ref.read(settingsProvider)), k: toHex(c)}});
  void _resetColors(List<String> keys) => set({'colorOverrides': {for (final e in overridesOf(ref.read(settingsProvider)).entries) if (!keys.contains(e.key)) e.key: e.value}});

  List<Widget> _colors(Settings s) {
    final over = overridesOf(s);
    return [
      _ColorPick(label: t('Акцент интерфейса'), s: s, colorKey: 'accent', list: _accents, onChanged: (v) => _setColor('accent', v), onReset: () => _resetColors(['accent']), changed: over['accent'] != null),
      _ColorPick(
        label: t('Верхняя панель'),
        s: s,
        colorKey: 'bar',
        list: _bars,
        // надписи на панели подбираются к её цвету сами
        onChanged: (c) => set({'colorOverrides': {...over, 'bar': toHex(c), 'barText': isLight(c) ? '#1d1c1a' : '#f3f1ec'}}),
        onReset: () => _resetColors(['bar', 'barText']),
        changed: over['bar'] != null,
      ),
      Card2(title: t('Тонкая настройка цветов'), children: [
        for (final k in colorKeys.where((k) => k.$1 != 'strong' && k.$1 != 'heading'))
          _ColorLine(label: t(k.$2), color: colorFor(s, k.$1), changed: over[k.$1] != null, onPick: (c) => _setColor(k.$1, c), onReset: () => _resetColors([k.$1])),
      ]),
      if (over.isNotEmpty)
        Center(child: OutlinedButton.icon(icon: const Icon(Icons.restart_alt, size: 18), label: Text(t('Все цвета — как в теме')), onPressed: () => set({'colorOverrides': <String, dynamic>{}}))),
    ];
  }

  List<Widget> _ui(Settings s) => [
        Card2(title: t('В тексте'), children: [
          SwitchRow(label: t('Кнопки параллельных мест'), hint: t('Число после стиха — сколько у него параллельных мест'), value: s.get<bool>('showXrefButtons'), onChanged: (v) => set({'showXrefButtons': v})),
          SwitchRow(label: t('Значки иллюстраций у стихов'), value: s.get<bool>('showIllustrations'), onChanged: (v) => set({'showIllustrations': v})),
          SwitchRow(label: t('Режим чтения'), hint: t('Без кнопок в тексте, панель прячется при прокрутке'), value: s.get<bool>('focusMode'), onChanged: (v) => set({'focusMode': v})),
        ]),
        Card2(title: t('Меню и панели'), children: [
          RangeRow(label: t('Шрифт меню и окон'), big: true, value: s.d('uiFontSize'), min: 13, max: 20, step: 1, onChanged: (v) => set({'uiFontSize': v}), word: _sizeW(14, 16)),
          RangeRow(label: t('Высота верхней панели'), value: s.d('barHeight'), min: 44, max: 72, step: 2, onChanged: (v) => set({'barHeight': v}), word: _barW),
          SwitchRow(label: t('Анимации'), value: s.get<bool>('animations'), onChanged: (v) => set({'animations': v})),
        ]),
        Card2(children: [
          SegRow<String>(
            label: t('Разделённый экран'),
            value: s.get<String>('splitLayout'),
            options: [('auto', t('Авто'), null), ('columns', t('Рядом'), Icons.view_column_outlined), ('rows', t('Друг над другом'), Icons.view_agenda_outlined)],
            onChanged: (v) => set({'splitLayout': v}),
          ),
        ]),
      ];
}

// --- Мелкие части ---------------------------------------------------------------------------------------------------

/// Кружок темы: её страница, полоска верхней панели, буквы цветом текста и точка цвета акцента
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.id, required this.p, required this.on, required this.onTap});
  final String id;
  final Palette p;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        margin: const EdgeInsets.only(right: 6),
        child: Column(children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? ring : Colors.transparent, width: 2.5)),
            child: ClipOval(
              child: Container(
                decoration: BoxDecoration(color: p.bg, shape: BoxShape.circle, border: Border.all(color: p.line)),
                child: Stack(alignment: Alignment.center, children: [
                  Positioned(top: 0, left: 0, right: 0, height: 13, child: ColoredBox(color: p.bar)),
                  Text(t('Аа'), style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 17)),
                  Positioned(bottom: 6, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(t(p.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// Схема вида текста: строки; «n» — номер стиха, «i» — красная строка
class _ViewTile extends StatelessWidget {
  const _ViewTile({required this.kind, required this.name, required this.on, required this.onTap});
  final String kind, name;
  final bool on;
  final VoidCallback onTap;

  static const _pics = <String, List<Object>>{
    'verses': [[0.4, 'n'], [0.58], 'gap', [0.4, 'n'], [1.0], [0.34], 'gap', [0.4, 'n']],
    'flow': [[0.4, 'n'], [1.0], [0.38], [1.0], [0.72], [0.56]],
    'book': [[0.3, 'i'], [1.0], [1.0], [1.0], [0.48], [0.3, 'i']],
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = cs.onSurface.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: BoxDecoration(border: Border.all(color: on ? cs.primary : cs.outlineVariant, width: on ? 2 : 1), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          SizedBox(
            height: 54,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final row in _pics[kind]!)
                if (row == 'gap')
                  const SizedBox(height: 4)
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      if ((row as List).length > 1) Container(width: 6, height: 3, margin: const EdgeInsets.only(right: 3), color: cs.primary),
                      Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: (row.first as double).clamp(0.1, 1.0), child: Container(height: 3, color: line))),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// Выбор цвета кружками: первый — цвет темы, дальше готовые, последний — свой (палитра)
class _ColorPick extends StatelessWidget {
  const _ColorPick({required this.label, required this.s, required this.colorKey, required this.list, required this.onChanged, required this.onReset, required this.changed});
  final String label, colorKey;
  final Settings s;
  final List<(String, String)> list;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final cur = colorFor(s, colorKey);
    final base = colorKey == 'heading' || colorKey == 'strong' ? baseColorFor(s, 'accent') : baseColorFor(s, colorKey);
    Widget dot(Color c, bool on, {String? tip, VoidCallback? onTap, Widget? child}) => Tooltip(
          message: tip ?? '',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: on ? Theme.of(context).colorScheme.primary : Colors.black26, width: on ? 3 : 1)),
              child: on ? Icon(Icons.check, size: 18, color: isLight(c) ? const Color(0xFF1d1c1a) : Colors.white) : child,
            ),
          ),
        );
    final curHex = toHex(cur);
    final custom = changed && !list.any((e) => e.$1 == curHex);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          dot(base, !changed, tip: t('Как в теме'), onTap: onReset),
          for (final e in list) dot(parseHex(e.$1)!, changed && curHex == e.$1, tip: t(e.$2), onTap: () => onChanged(parseHex(e.$1)!)),
          dot(custom ? cur : Colors.transparent, custom, tip: t('Свой цвет'), child: const Icon(Icons.colorize, size: 18), onTap: () async {
            final c = await pickColor(context, cur);
            if (c != null) onChanged(c);
          }),
        ]),
      ]),
    );
  }
}

/// Строка тонкой настройки: название, «вернуть цвет темы», кружок с выбором своего цвета
class _ColorLine extends StatelessWidget {
  const _ColorLine({required this.label, required this.color, required this.changed, required this.onPick, required this.onReset});
  final String label;
  final Color color;
  final bool changed;
  final ValueChanged<Color> onPick;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: changed ? 1 : 0.8,
        child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(label, style: const TextStyle(fontSize: 15)))),
          IconButton(icon: const Icon(Icons.restart_alt, size: 20), tooltip: t('Вернуть цвет темы'), onPressed: changed ? onReset : null),
          GestureDetector(
            onTap: () async {
              final c = await pickColor(context, color);
              if (c != null) onPick(c);
            },
            child: Container(width: 34, height: 34, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black26))),
          ),
        ]),
      );
}

/// Выбор своего цвета: оттенок, насыщенность, яркость
Future<Color?> pickColor(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (c) {
      var hsv = HSVColor.fromColor(initial);
      return StatefulBuilder(builder: (c, setS) {
        final color = hsv.toColor();
        return AlertDialog(
          title: Text(t('Свой цвет')),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26))),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(toHex(color))),
              Slider(
                value: hsv.hue,
                max: 359.9,
                onChanged: (v) => setS(() => hsv = hsv.withHue(v)),
                activeColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
              ),
              Slider(value: hsv.saturation, onChanged: (v) => setS(() => hsv = hsv.withSaturation(v))),
              Slider(value: hsv.value, onChanged: (v) => setS(() => hsv = hsv.withValue(v))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Отмена'))),
            FilledButton(onPressed: () => Navigator.pop(c, color), child: Text(t('Готово'))),
          ],
        );
      });
    },
  );
}
