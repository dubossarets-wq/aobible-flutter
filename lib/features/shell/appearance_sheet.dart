// Оформление (AppearanceSettings.jsx): сверху живой образец текста, под ним тема, размер, вид текста;
// ниже подразделы — шрифт, номера и заголовки, цвета, кнопки и панели; внизу — сброс. Всё применяется сразу.
// Подразделы «Фон» (картинка под текстом) и «Комментарии» (размер текста, какие видны после стиха) — тоже здесь.
import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import '../bookmarks/marks.dart' show hlColors, marksProvider;
import '../plans/net_cache.dart' show SiteImage;
import 'background.dart';
import 'colors.dart';
import 'fonts.dart';
import 'intl_data.dart' show langDisplayNames;
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
  'theme', 'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'verseSpacing', 'textWidth', 'textMargin', 'textAlign', 'showVerseNumbers', 'chapterTitleSize',
  'showStrongs', 'showHeadings', 'showXrefButtons', 'showIllustrations', 'continuousVerses', 'bookMode', 'colorOverrides', 'strongSize', 'strongPos',
  'verseNumPos', 'headingSize', 'uiFontSize', 'barHeight', 'animations', 'focusMode', 'splitLayout', 'commentaryFontSize',
  'bgImage', 'bgPhoto', 'bgVeil', 'bgBlur', 'inlineCommentaries',
];

// У этих ключей в Settings.defaults записи нет (фон по умолчанию выключен): при сбросе кладём значения веб-версии
const _lookDefaults = <String, dynamic>{'bgImage': 0, 'bgPhoto': null, 'bgVeil': 72, 'bgBlur': 0, 'inlineCommentaries': null};

/// Выбор своей картинки: байты файла или null. По умолчанию — окно выбора файла; тесты подменяют
Future<Uint8List?> Function() pickBgImage = () async {
  final f = await FilePicker.pickFile(type: FileType.image);
  return f == null ? null : await f.readAsBytes();
};

/// Включённые комментарии (для подраздела «Комментарии»); хранилище модулей может быть ещё не готово
List<InstalledModule> installedCommentaries() {
  try {
    return ModuleStore.instance.installed.where((m) => m.type == 'commentary').toList();
  } catch (_) {
    return const [];
  }
}

// Понятные значения вместо чисел
String Function(double) _words(double lo, double hi, String a, String b, String c) => (v) => t(v < lo ? a : v <= hi ? b : c);
String Function(double) _sizeW(double lo, double hi) => _words(lo, hi, 'мелкий', 'обычный', 'крупный');
final _lhW = _words(1.32, 1.62, 'плотный', 'обычный', 'свободный');
String _gapW(double v) => v < 0.05 ? t('нет') : _words(0.35, 0.85, 'маленькое', 'обычное', 'большое')(v);
final _widthW = _words(36, 56, 'узкая', 'обычная', 'широкая');
final _barW = _words(50, 58, 'низкая', 'обычная', 'высокая');
const _weights = {300: 'тонкий', 400: 'обычный', 500: 'средний', 600: 'полужирный', 700: 'жирный'};
const _pos = {'sup': 'Над строкой', 'inline': 'В строке', 'sub': 'Под строкой'};

String _blurW(double v) => v == 0 ? t('нет') : _words(7, 13, 'лёгкое', 'среднее', 'сильное')(v);

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
    // .preview-card: рамка line, скругление 12, фон страницы; .pv-bar 46 (в закреплённом образце), .pv-body 10 16 12
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: s.get<bool>('iosStyle')
          ? iosShape(pal.bg, BorderRadius.circular(iosRadius), side: BorderSide(color: pal.line, width: 0.5))
          : BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (bar)
          Container(
            height: 46,
            color: pal.bar,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: mix(pal.barText, 0.14, pal.bar), borderRadius: BorderRadius.circular(99)), child: Text('RST+', style: TextStyle(color: pal.barText, fontWeight: FontWeight.w700, fontSize: 12.75))),
              const SizedBox(width: 8),
              Text('${Books.instance.meta('Gen').short} 1:1', style: TextStyle(color: pal.barText, fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          ),
        Padding(
          // поля по бокам — как в читалке (Оформление → «Поля по бокам»)
          padding: EdgeInsets.fromLTRB(s.d('textMargin') >= 0 ? s.d('textMargin') : (s.get<bool>('iosStyle') ? 20 : 16), 10, s.d('textMargin') >= 0 ? s.d('textMargin') : (s.get<bool>('iosStyle') ? 20 : 16), 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (head && !noText && (live || s.get<bool>('showHeadings')))
              Padding(padding: EdgeInsets.only(bottom: fs * 0.4), child: Text(t('Сотворение неба и земли'), style: readerTextStyle(s, size: fs * s.d('headingSize'), weight: 650).copyWith(color: headingColor(s), height: 1.3))),
            ...verses,
            if (ui)
              Padding(
                padding: EdgeInsets.only(top: noText ? 0 : 6),
                child: Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(kRadius)), child: Text(t('Кнопка'), style: TextStyle(color: pal.onAccent, fontWeight: FontWeight.w600, fontSize: 15))),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Окно или карточка'), style: TextStyle(color: pal.text, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(t('бледный текст'), style: TextStyle(color: pal.muted, fontSize: 12.75)),
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
    ('font', LucideIcons.type, 'Шрифт'),
    ('nums', LucideIcons.hash, 'Номера и заголовки'),
    ('bg', LucideIcons.image, 'Фон'),
    ('colors', LucideIcons.palette, 'Цвета'),
    ('ui', LucideIcons.panelTop, 'Кнопки и панели'),
    ('comments', LucideIcons.messageSquareText, 'Комментарии'),
  ];

  // «Комментарии» показываем, только когда есть установленные комментарии
  List<(String, IconData, String)> get _shown => [for (final b in _blocks) if (b.$1 != 'comments' || installedCommentaries().isNotEmpty) b];

  void set(Map<String, dynamic> p) => ref.read(settingsProvider.notifier).set(p);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final cur = _blocks.where((b) => b.$1 == _block).firstOrNull;
    final commentaries = installedCommentaries();
    final title = cur != null ? t(cur.$3) : t('Оформление');
    final children = switch (_block) {
      'font' => _font(s),
      'nums' => _nums(s),
      'bg' => _bg(s),
      'colors' => _colors(s),
      'ui' => _ui(s),
      'comments' => _comments(s, commentaries),
      _ => _main(s, pal),
    };
    return AppSheet(
      title: title,
      onBack: cur != null ? () => setState(() => _block = null) : null,
      gap: 18, // .ap-screen: зазор между блоками 18
      // образец закреплён вверху: при прокрутке настроек остаётся на виду
      fixed: _block == 'comments'
          ? null
          : SheetFixed(
        bottom: 10,
        child: _block == 'bg'
            ? _BgPreview(s: s)
            : _block == 'ui'
            ? Sample(s: s, bar: true, ui: true, noText: true)
            : _block == 'colors'
                ? Sample(s: s, bar: true, head: true, sn: true, ui: true, short: true, live: true)
                : _live != null
                    ? Sample(s: s, live: true, bar: _live == 'bar' || _live == 'barText', head: _live == 'heading', sn: _live == 'strong', short: true)
                    // образец обрезан по высоте 180 — по той же скруглённой рамке (иначе низ срезан прямо, без углов и линии)
                    : Container(
                        foregroundDecoration: iosStyleOf(ref)
                            ? ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(iosRadius), side: BorderSide(color: effectivePalette(s).line, width: 0.5)))
                            : BoxDecoration(border: Border.all(color: effectivePalette(s).line), borderRadius: BorderRadius.circular(kRadius)),
                        child: iosStyleOf(ref)
                            ? ClipRSuperellipse(
                                borderRadius: BorderRadius.circular(iosRadius),
                                child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180), child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Sample(s: s, head: true))),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(kRadius),
                                child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180), child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Sample(s: s, head: true))),
                              ),
                      ),
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
      'bg': bgStamp(s) != 0 ? t('С картинкой') : t('Без фона'),
      'comments': _commentsSub(s),
    };
    return [
      _field(t('Тема'), pal, 6, [
        // .theme-strip: поля -16 (до краёв окна) и отступ 12; плитки 66, зазор 2
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: 92,
            child: OverflowBox(
              minWidth: c.maxWidth + 32,
              maxWidth: c.maxWidth + 32,
              // все плитки строятся сразу (их немного): ряд прокручивается, а не создаётся по мере прокрутки
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
                // порядок: Системная, Светлая, Тёмная, Тёплая, Сепия, затем остальные
                for (final id in ['auto', 'light', 'dark', 'warm', 'sepia', for (final k in themes.keys) if (!['light', 'dark', 'warm', 'sepia'].contains(k)) k])
                  id == 'auto'
                      // «Системная»: половина светлой темы, половина тёмной
                      ? _ThemeTile(id: 'auto', p: themes['light']!, dark: themes['dark'], ring: pal.accent, text: pal.text, on: s.get<String>('theme') == 'auto', onTap: () => set({'theme': 'auto'}))
                      : _ThemeTile(id: id, p: themes[id]!, ring: pal.accent, text: pal.text, on: s.get<String>('theme') == id, onTap: () => set({'theme': id})),
              ])),
            ),
          ),
        ),
      ]),
      RangeRow(label: t('Размер текста'), big: true, value: s.d('fontSize'), min: 13, max: 40, step: 1, onChanged: (v) => set({'fontSize': v}), word: (v) => '${v.round()} px'),
      // поля текста по бокам экрана (по умолчанию — 20 в стиле iPhone, иначе 16)
      RangeRow(
        label: t('Поля по бокам'),
        value: s.d('textMargin') >= 0 ? s.d('textMargin') : (s.get<bool>('iosStyle') ? 20 : 16),
        min: 0,
        max: 48,
        step: 2,
        onChanged: (v) => set({'textMargin': v}),
        word: (v) => '${v.round()} px',
      ),
      _field(t('Вид текста'), pal, 8, [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, k) in const ['verses', 'flow', 'book'].indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _ViewTile(
                kind: k,
                name: t(const {'verses': 'По стихам', 'flow': 'Сплошной', 'book': 'Как книга'}[k]!),
                on: textView(s) == k,
                onTap: () => set({'bookMode': k == 'book', 'continuousVerses': k == 'flow'}),
              ),
            ),
          ],
        ]),
      ]),
      // стиль iPhone: разделы — одной карточкой, «Сбросить оформление» — отдельной строкой, как «Выключить»
      if (iosStyleOf(ref)) ...[
        for (final (i, b) in _shown.indexed) PrefRow(icon: b.$2, title: t(b.$3), sub: subs[b.$1], onTap: () => setState(() => _block = b.$1), last: i == _shown.length - 1),
        const IosBreak(),
        IosActionRow(
          title: t('Сбросить оформление'),
          onTap: () => iosConfirm(context, action: t('Да, сбросить'), onConfirm: () {
            set({for (final k in _lookKeys) k: Settings.defaults.containsKey(k) ? Settings.defaults[k] : _lookDefaults[k]});
            UserBg.clear();
            toast(context, t('Оформление сброшено'));
          }),
        ),
      ] else ...[
      // .ap-list: линия сверху, строки не ниже 60; линия — от края до края окна, как у самих строк
      Column(children: [
        bleed(Container(height: 1, color: pal.line)),
        for (final (i, b) in _shown.indexed) PrefRow(icon: b.$2, title: t(b.$3), sub: subs[b.$1], onTap: () => setState(() => _block = b.$1), last: i == _shown.length - 1),
      ]),
      Center(
        child: ConfirmButton(
          block: true,
          icon: LucideIcons.rotateCcw,
          label: t('Сбросить оформление'),
          confirmText: t('Да, сбросить'),
          onConfirm: () {
            set({for (final k in _lookKeys) k: Settings.defaults.containsKey(k) ? Settings.defaults[k] : _lookDefaults[k]});
            UserBg.clear();
            toast(context, t('Оформление сброшено'));
          },
        ),
      ),
      ],
    ];
  }

  /// .field: подпись и под ней содержимое
  // стиль iPhone: подпись — системным заголовком группы (прописными, серым, на линии текста строк)
  Widget _field(String text, Palette pal, double gap, List<Widget> body) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (iosStyleOf(ref)) Padding(padding: const EdgeInsets.only(left: iosHeaderLeft), child: GroupTitle(text)) else Text(text, style: fieldLabel(pal, bold: true)),
        SizedBox(height: iosStyleOf(ref) ? 4 : gap),
        ...body,
      ]);

  List<Widget> _font(Settings s) {
    final pal = effectivePalette(s);
    final w = s.d('fontWeight').round();
    final defs = fontDefs.entries.toList();
    return [
      // .font-list: рамка со скруглением, строки не ниже 62, выбранная — с лёгкой заливкой акцента
      Container(
        clipBehavior: Clip.antiAlias,
        // стиль iPhone: карточка группы (системная заливка и скругление, без рамки)
        decoration: iosUiNow
            ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius))
            : BoxDecoration(border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
        child: Column(children: [
          for (final (i, e) in defs.indexed) ...[
            InkWell(
              onTap: () => set({'fontFamily': e.key}),
              // выбранный шрифт: подложка проявляется плавно
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.fastOutSlowIn,
                constraints: const BoxConstraints(minHeight: 62),
                padding: iosUiNow ? const EdgeInsets.fromLTRB(iosRowIconLeft, 9, iosRowRight, 9) : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: iosUiNow
                    ? null
                    : BoxDecoration(
                        color: pal.accent.withValues(alpha: s.get<String>('fontFamily') == e.key ? 0.09 : 0),
                        border: i == defs.length - 1 ? null : Border(bottom: BorderSide(color: pal.line)),
                      ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('В начале было Слово'), maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: readerTextStyle(s, size: 20.8, font: e.value, weight: 400).copyWith(color: pal.text, height: 1.3)),
                      Text(t(e.value.label), style: TextStyle(fontSize: 13.1, color: s.get<String>('fontFamily') == e.key ? pal.text : pal.muted)),
                    ]),
                  ),
                  // галочка выбранного шрифта проявляется плавно
                  SizedBox(
                    width: 22,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: s.get<String>('fontFamily') == e.key ? 1 : 0,
                      child: AnimatedScale(duration: const Duration(milliseconds: 240), curve: Curves.fastOutSlowIn, scale: s.get<String>('fontFamily') == e.key ? 1 : 0.6, child: Icon(ico(LucideIcons.check), size: 20, color: pal.accent)),
                    ),
                  ),
                ]),
              ),
            ),
            // стиль iPhone: линия между строками — от начала текста, тонкая
            if (iosUiNow && i < defs.length - 1) Padding(padding: const EdgeInsets.only(left: iosRowIconLeft), child: Container(height: 0.5, color: pal.line)),
          ],
        ]),
      ),
      Card2(children: [
        SegRow<int>(
          label: t('Толщина'),
          valueText: t(_weights[w] ?? 'обычный'),
          value: _weights.containsKey(w) ? w : 400,
          options: [for (final k in _weights.keys) (k, t('Аа'), null)],
          labelStyle: (k) => TextStyle(fontWeight: weightOf(k.toDouble()), fontSize: 17.3),
          onChanged: (v) => set({'fontWeight': v}),
        ),
        RangeRow(label: t('Межстрочный интервал'), value: s.d('lineHeight'), min: 1.1, max: 2.2, step: 0.05, onChanged: (v) => set({'lineHeight': v}), word: _lhW),
        RangeRow(label: t('Расстояние между стихами'), value: s.d('verseSpacing'), min: 0, max: 1.6, step: 0.05, onChanged: (v) => set({'verseSpacing': v}), word: _gapW),
        // ширина строки ограничивает текст только на широком экране — на телефоне не показываем (поля — «Поля по бокам»)
        if (MediaQuery.sizeOf(context).width >= 600)
          RangeRow(label: t('Ширина текста'), hint: t('Заметно на широком экране'), value: s.d('textWidth'), min: 24, max: 80, step: 1, onChanged: (v) => set({'textWidth': v}), word: _widthW),
        SegRow<String>(
          label: t('Выравнивание'),
          value: s.get<String>('textAlign'),
          options: [('left', t('По левому краю'), LucideIcons.alignLeft), ('justify', t('По ширине'), LucideIcons.alignJustify)],
          onChanged: (v) => set({'textAlign': v}),
        ),
      ]),
    ];
  }

  // Настройки под включённым переключателем карточки: раскрываются и сворачиваются плавно (зазор 14 — внутри)
  Widget _more(bool open, List<Widget> items) => Reveal(
        open: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final w in items) Padding(padding: const EdgeInsets.only(top: 14), child: w)]),
      );

  List<Widget> _nums(Settings s) {
    final pal = effectivePalette(s);
    final over = overridesOf(s);
    final raw = t('В начале{7225} сотворил{1254} Бог{430} небо{8064} и{853} землю.{776}');
    final plain = raw.replaceAll(RegExp(r'\{\d+\}'), '');
    final fs = s.d('fontSize') < 20 ? s.d('fontSize') : 20.0;
    // .ap-mini: рамка, фон страницы, шрифт текста, интервал 1.5
    Widget mini(List<InlineSpan> spans, {int lines = 2}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius * 0.75)),
          child: Text.rich(TextSpan(children: spans), maxLines: lines, overflow: TextOverflow.ellipsis, style: readerTextStyle(s, size: fs).copyWith(color: pal.text, height: 1.5)),
        );
    // Текст с номерами Стронга (бледнее, пока выключены)
    List<InlineSpan> withStrongs() {
      final on = s.get<bool>('showStrongs');
      final parts = raw.split(RegExp(r'\{\d+\}'));
      final nums = RegExp(r'\{(\d+)\}').allMatches(raw).map((m) => m.group(1)!).toList();
      return [
        for (var i = 0; i < parts.length; i++) ...[
          TextSpan(text: parts[i]),
          if (i < nums.length)
            WidgetSpan(alignment: PlaceholderAlignment.top, child: Opacity(opacity: on ? 1 : 0.4, child: Text(nums[i], style: TextStyle(fontSize: fs * 0.5, color: strongColor(s), height: 1)))),
        ],
      ];
    }

    return [
      Card2(children: [
        SwitchField(bold: true, big: true, label: t('Номера стихов'), value: s.get<bool>('showVerseNumbers'), onChanged: (v) => set({'showVerseNumbers': v})),
        mini([
          if (s.get<bool>('showVerseNumbers')) TextSpan(text: '1 ', style: TextStyle(color: pal.verseNum, fontSize: fs * 0.6)),
          TextSpan(text: '$plain '),
          if (s.get<bool>('showVerseNumbers')) TextSpan(text: '2 ', style: TextStyle(color: pal.verseNum, fontSize: fs * 0.6)),
          TextSpan(text: t('Земля же была безвидна и пуста, и тьма над бездною, и Дух Божий носился над водою.')),
        ]),
        _more(s.get<bool>('showVerseNumbers'), [
          RangeRow(label: t('Размер'), value: s.d('verseNumSize'), min: 0.4, max: 1.2, step: 0.05, onChanged: (v) => set({'verseNumSize': v}), word: _sizeW(0.52, 0.8)),
          SegRow<String>(label: t('Положение'), value: s.get<String>('verseNumPos'), options: [for (final k in const ['sup', 'inline']) (k, t(_pos[k]!), null)], onChanged: (v) => set({'verseNumPos': v})),
        ]),
      ]),
      Card2(children: [
        SwitchField(bold: true, big: true, label: t('Номера Стронга'), hint: t('Только в переводах с номерами Стронга, например RST+'), value: s.get<bool>('showStrongs'), onChanged: (v) => set({'showStrongs': v})),
        mini(withStrongs(), lines: 3),
        _more(s.get<bool>('showStrongs'), [
          RangeRow(label: t('Размер'), value: s.d('strongSize'), min: 0.35, max: 1, step: 0.05, onChanged: (v) => set({'strongSize': v}), word: _sizeW(0.45, 0.7)),
          SegRow<String>(label: t('Положение'), value: s.get<String>('strongPos'), options: [for (final k in const ['sup', 'inline', 'sub']) (k, t(_pos[k]!), null)], onChanged: (v) => set({'strongPos': v})),
          _ColorPick(label: t('Цвет'), s: s, colorKey: 'strong', list: _accents, onChanged: (v) => _setColor('strong', v), onReset: () => _resetColors(['strong']), changed: over['strong'] != null),
        ]),
      ]),
      Card2(children: [
        SwitchField(bold: true, big: true, label: t('Заголовки разделов'), value: s.get<bool>('showHeadings'), onChanged: (v) => set({'showHeadings': v})),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius * 0.75)),
          child: Opacity(
            opacity: s.get<bool>('showHeadings') ? 1 : 0.4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Сотворение неба и земли'), style: readerTextStyle(s, size: fs * s.d('headingSize'), weight: 650).copyWith(color: headingColor(s), height: 1.3)),
              Text(plain, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: readerTextStyle(s, size: fs).copyWith(color: pal.text, height: 1.5)),
            ]),
          ),
        ),
        _more(s.get<bool>('showHeadings'), [
          RangeRow(label: t('Размер'), value: s.d('headingSize'), min: 0.6, max: 1.4, step: 0.05, onChanged: (v) => set({'headingSize': v}), word: _sizeW(0.72, 1)),
          _ColorPick(label: t('Цвет'), s: s, colorKey: 'heading', list: _accents, onChanged: (v) => _setColor('heading', v), onReset: () => _resetColors(['heading']), changed: over['heading'] != null),
        ]),
      ]),
      Card2(title: t('Заголовки глав'), children: [
        mini([TextSpan(text: t('Глава {n}', {'n': '1'}), style: TextStyle(fontSize: s.d('chapterTitleSize') * 16, fontWeight: FontWeight.w800, height: 1.1))], lines: 1),
        RangeRow(label: t('Размер'), value: s.d('chapterTitleSize'), min: 1.1, max: 3.2, step: 0.1, onChanged: (v) => set({'chapterTitleSize': v}), word: _sizeW(1.7, 2.5)),
      ]),
    ];
  }

  // --- Фон ---

  bool _busy = false;

  Future<void> _useBg(Uint8List bytes, String? photo) async {
    try {
      await UserBg.save(bytes);
      set({'bgImage': DateTime.now().millisecondsSinceEpoch, 'bgPhoto': photo});
    } catch (_) {
      if (mounted) toast(context, t('Не удалось открыть картинку'));
    }
  }

  Future<void> _pickOwn() async {
    final Uint8List? bytes;
    try {
      bytes = await pickBgImage();
    } catch (_) {
      if (mounted) toast(context, t('Не удалось открыть картинку'));
      return;
    }
    if (bytes != null) await _useBg(bytes, null);
  }

  Future<void> _pickPhoto(Map ph) async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await loadSiteBytes('images/verse-bg/${ph['file']}');
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) return toast(context, t('Не удалось открыть картинку'));
    await _useBg(bytes, '${ph['id']}');
  }

  List<Widget> _bg(Settings s) {
    final pal = effectivePalette(s);
    final on = bgStamp(s) != 0;
    final photo = bgPhotoId(s);
    final own = on && photo == null;
    // .bg-tile: квадрат, рамка line, скругление 12; выбранный — кольцо акцента 3 px через зазор 2
    Widget tile({required bool selected, required Widget child, required VoidCallback onTap, String? tip, Color? fill}) => Tooltip(
          message: tip ?? '',
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.fastOutSlowIn,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: selected ? pal.accent : pal.accent.withValues(alpha: 0), width: 3)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: fill ?? pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(12)),
                  child: child,
                ),
              ),
            ),
          ),
        );
    Widget label(IconData icon, String text, Color color) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ico(icon), size: 22, color: color),
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.2, height: 1.15, color: color)),
          ]),
        );
    return [
      FutureBuilder<Map<String, dynamic>?>(
        future: _photosFuture ??= loadSiteJson('images/verse-bg/index.json'),
        builder: (context, snap) {
          final photos = ((snap.data?['images'] as List?) ?? const []).whereType<Map>().toList();
          return LayoutBuilder(
            builder: (context, c) {
              // 4 столбца, зазор 10 (плитка сама имеет поле 2 для кольца, поэтому зазор между ними 6)
              const gap = 6.0;
              final w = (c.maxWidth - gap * 3) / 4;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                SizedBox(
                  width: w,
                  child: tile(selected: !on, onTap: () {
                    UserBg.clear();
                    set({'bgImage': 0, 'bgPhoto': null});
                  }, child: label(LucideIcons.ban, t('Без фона'), pal.text)),
                ),
                SizedBox(
                  width: w,
                  child: tile(
                    selected: own,
                    onTap: _pickOwn,
                    fill: own ? const Color(0xff333333) : null,
                    child: Stack(fit: StackFit.expand, children: [
                      if (own) const _OwnThumb(),
                      if (own) const ColoredBox(color: Color(0x8C000000)),
                      label(LucideIcons.imagePlus, t('Своё фото'), own ? Colors.white : pal.text),
                    ]),
                  ),
                ),
                for (final ph in photos)
                  SizedBox(
                    width: w,
                    child: tile(
                      selected: on && photo == '${ph['id']}',
                      tip: t('${ph['title']}'),
                      fill: pal.line,
                      onTap: () => _pickPhoto(ph),
                      child: SiteImage('images/verse-bg/${ph['thumb']}'),
                    ),
                  ),
              ]);
            },
          );
        },
      ),
      // ползунки картинки раскрываются плавно; зазор 18 — внутри, чтобы свёрнутые не оставляли места
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Reveal(
          open: on,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Card2(children: [
              RangeRow(label: t('Картинку видно'), value: 100 - bgVeil(s), min: 5, max: 70, step: 1, onChanged: (v) => set({'bgVeil': 100 - v}), word: (v) => '${v.round()}%'),
              RangeRow(label: t('Размытие'), value: bgBlur(s), min: 0, max: 20, step: 1, onChanged: (v) => set({'bgBlur': v}), word: _blurW),
            ]),
          ),
        ),
        Text(t('Картинка хранится только на этом устройстве.'), style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4)),
      ]),
    ];
  }

  Future<Map<String, dynamic>?>? _photosFuture;

  // --- Комментарии ---

  String _commentsSub(Settings s) {
    final list = installedCommentaries();
    final inline = s.j['inlineCommentaries'];
    final n = inline is List ? list.where((m) => inline.contains(m.id)).length : list.length;
    return t('{n} из {total}', {'n': '$n', 'total': '${list.length}'});
  }

  List<Widget> _comments(Settings s, List<InstalledModule> list) {
    final pal = effectivePalette(s);
    final inline = s.j['inlineCommentaries'];
    final fs = s.d('commentaryFontSize');
    bool isOn(InstalledModule m) => inline is! List || inline.contains(m.id);
    // сначала — на языке приложения, затем остальные (внутри — в прежнем порядке)
    final sorted = [...list.where((m) => m.language == currentLang), ...list.where((m) => m.language != currentLang)];
    final sample = sorted.where(isOn).firstOrNull ?? sorted.firstOrNull;
    return [
      // образец — как комментарий в читалке: под стихом, с линией акцента слева и названием источника
      Card2(children: [
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.accent, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (sample != null) Text(sample.name, style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700, color: pal.accent)),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              style: TextStyle(fontSize: fs, height: 1.6, color: pal.text),
              child: Text(t('Так выглядит текст комментария.')),
            ),
          ]),
        ),
        RangeRow(label: t('Размер текста'), big: true, value: fs, min: 14, max: 32, step: 1, onChanged: (v) => set({'commentaryFontSize': v}), word: (v) => '${v.round()} px'),
      ]),
      // как показывать: текстом под стихом (свёрнут до двух строк) или прежней меткой после стиха
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (iosUiNow) Padding(padding: const EdgeInsets.only(left: iosHeaderLeft), child: GroupTitle(t('Как показывать'))) else Text(t('Как показывать'), style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted)),
        const SizedBox(height: 8),
        Segmented<String>(
          options: [('below', t('Под стихом')), ('tag', t('Меткой после стиха'))],
          value: s.get<String>('commentView') == 'tag' ? 'tag' : 'below',
          onChanged: (v) => set({'commentView': v}),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (iosUiNow) Padding(padding: const EdgeInsets.only(left: iosHeaderLeft), child: GroupTitle(t('Комментарии в тексте'))) else Text(t('Комментарии в тексте'), style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted)),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: iosUiNow ? iosHeaderLeft : 0, right: iosUiNow ? iosHeaderLeft : 0),
          child: Text(t('Отмеченные видны после стиха. Остальные — зажмите стих → «Комментарии».'), style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4)),
        ),
      ]),
      // источники — строками от края до края, как списки в настройках: название, ниже описание и язык, справа переключатель
      Column(children: [
        for (final (i, m) in sorted.indexed)
          (iosUiNow ? (Widget w) => IosCardItem(pal: pal, first: i == 0, last: i == sorted.length - 1, child: w) : bleed)(InkWell(
            onTap: () => _toggleInline(list, inline, m, !isOn(m)),
            child: Container(
              padding: iosUiNow ? const EdgeInsets.fromLTRB(iosRowIconLeft, 11, iosRowRight, 11) : const EdgeInsets.fromLTRB(20, 11, 16, 11),
              decoration: iosUiNow ? null : BoxDecoration(border: Border(top: i == 0 ? BorderSide(color: pal.line) : BorderSide.none, bottom: BorderSide(color: pal.line))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: iosUiNow ? TextStyle(fontSize: 17, color: pal.text) : TextStyle(fontSize: 15.2, fontWeight: FontWeight.w600, color: pal.text)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [if (m.title != m.name) m.title, langDisplayNames[currentLang]?[m.language] ?? m.language].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: iosUiNow ? 15 : 12.6, height: 1.35, color: pal.muted),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                AobSwitch(value: isOn(m), onChanged: (v) => _toggleInline(list, inline, m, v)),
              ]),
            ),
          )),
      ]),
    ];
  }

  void _toggleInline(List<InstalledModule> list, Object? inline, InstalledModule m, bool on) {
    final cur = inline is List ? inline.cast<String>() : [for (final x in list) x.id];
    set({'inlineCommentaries': on ? {...cur, m.id}.toList() : [for (final x in cur) if (x != m.id) x]});
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
      const _HlLabels(),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card2(title: t('Тонкая настройка цветов'), children: [
        Column(children: [
          for (final k in colorKeys.where((k) => k.$1 != 'strong' && k.$1 != 'heading'))
            _ColorLine(label: t(k.$2), color: colorFor(s, k.$1), changed: over[k.$1] != null, onPick: (c) => _setColor(k.$1, c), onReset: () => _resetColors([k.$1])),
        ]),
      ]),
      Reveal(open: over.isNotEmpty, child: Padding(padding: const EdgeInsets.only(top: 18), child: Align(alignment: Alignment.centerLeft, child: AobButton(block: true, icon: LucideIcons.rotateCcw, label: t('Все цвета — как в теме'), onTap: () => set({'colorOverrides': <String, dynamic>{}}))))),
      ]),
    ];
  }

  List<Widget> _ui(Settings s) => [
        Card2(title: t('В тексте'), children: [
          SwitchField(bold: true, label: t('Кнопки параллельных мест'), hint: t('Число после стиха — сколько у него параллельных мест'), value: s.get<bool>('showXrefButtons'), onChanged: (v) => set({'showXrefButtons': v})),
          SwitchField(bold: true, label: t('Значки иллюстраций у стихов'), value: s.get<bool>('showIllustrations'), onChanged: (v) => set({'showIllustrations': v})),
          SwitchField(bold: true, label: t('Режим чтения'), hint: t('Без кнопок в тексте, панель прячется при прокрутке'), value: s.get<bool>('focusMode'), onChanged: (v) => set({'focusMode': v})),
        ]),
        Card2(title: t('Меню и панели'), children: [
          RangeRow(label: t('Шрифт меню и окон'), big: true, value: s.d('uiFontSize'), min: 13, max: 20, step: 1, onChanged: (v) => set({'uiFontSize': v}), word: _sizeW(14, 16)),
          RangeRow(label: t('Высота верхней панели'), value: s.d('barHeight'), min: 44, max: 72, step: 2, onChanged: (v) => set({'barHeight': v}), word: _barW),
          SwitchField(bold: true, label: t('Анимации'), value: s.get<bool>('animations'), onChanged: (v) => set({'animations': v})),
        ]),
        Card2(children: [
          SegRow<String>(
            label: t('Разделённый экран'),
            value: s.get<String>('splitLayout'),
            options: [('auto', t('Авто'), null), ('columns', t('Рядом'), LucideIcons.columns2), ('rows', t('Друг над другом'), LucideIcons.rows2)],
            onChanged: (v) => set({'splitLayout': v}),
          ),
        ]),
      ];
}

// --- Мелкие части ---------------------------------------------------------------------------------------------------

/// Кружок темы (.theme-tile): её страница, полоска верхней панели (26%), буквы цветом текста и точка цвета акцента
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.id, required this.p, this.dark, required this.ring, required this.text, required this.on, required this.onTap});
  final String id;
  final Palette p;
  final Palette? dark; // у плитки «Системная» — тёмная половина
  final Color ring, text;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 66,
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Column(children: [
          // обводка выбранной — снаружи кружка: 3 px акцента с отступом 2
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.fastOutSlowIn,
            width: 54 + 10,
            height: 54 + 10,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? ring : ring.withValues(alpha: 0), width: 3)),
            child: Container(
              width: 54,
              height: 54,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: p.bg, shape: BoxShape.circle, border: Border.all(color: p.line), boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))]),
              // «Системная» — как соседние плитки, но левая половина светлой темы, правая — тёмной (сглаженными фигурами);
              // «А» — светлой темы, «а» — тёмной, вплотную у середины, как одно слово
              child: dark != null
                  ? CustomPaint(
                      painter: _HalfDark(dark!.bg, p.bar, dark!.bar),
                      child: Transform.translate(
                        offset: const Offset(0, 4),
                        child: Row(children: [
                          Expanded(child: Align(alignment: Alignment.centerRight, child: Text(t('Аа').substring(0, 1), style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 16, height: 1)))),
                          const SizedBox(width: 1),
                          Expanded(child: Align(alignment: Alignment.centerLeft, child: Text(t('Аа').substring(1), style: TextStyle(color: dark!.text, fontWeight: FontWeight.w600, fontSize: 16, height: 1)))),
                        ]),
                      ),
                    )
                  : Stack(alignment: Alignment.center, children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 54 * 0.26,
                  child: ColoredBox(color: p.bar),
                ),
                Transform.translate(offset: const Offset(-3, 4), child: Text(t('Аа'), style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: 0.16))),
                Positioned(right: 7, bottom: 10, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle))),
              ]),
            ),
          ),
          const SizedBox(height: 0),
          // название целиком: длинное (другие языки, «Системная» жирным) ужимается, а не обрезается
          FittedBox(fit: BoxFit.scaleDown, child: Text(id == 'auto' ? t('Системная') : t(p.label), maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12.8, height: 1.2, fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: text))),
        ]),
      ),
    );
  }
}

/// Плитка «Системная»: правая половина — фон тёмной темы, сверху полоса панели (слева светлая, справа тёмная);
/// фигуры сглаженные (резкий переход градиента давал зубцы)
class _HalfDark extends CustomPainter {
  _HalfDark(this.color, this.barLight, this.barDark);
  final Color color, barLight, barDark;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, half = w / 2, bar = h * 0.26;
    Paint fill(Color c) => Paint()
      ..color = c
      ..isAntiAlias = true;
    canvas.drawRect(Rect.fromLTWH(half, 0, w - half, h), fill(color));
    canvas.drawRect(Rect.fromLTWH(0, 0, half, bar), fill(barLight));
    canvas.drawRect(Rect.fromLTWH(half, 0, w - half, bar), fill(barDark));
  }

  @override
  bool shouldRepaint(_HalfDark old) => old.color != color || old.barLight != barLight || old.barDark != barDark;
}

/// Схема вида текста (.view-tile): строки-палочки; «n» — номер стиха, «i» — красная строка
class _ViewTile extends ConsumerWidget {
  const _ViewTile({required this.kind, required this.name, required this.on, required this.onTap});
  final String kind, name;
  final bool on;
  final VoidCallback onTap;

  // Как VIEW_PICS в веб-версии: число — ширина палочки в процентах; 'n' — номер, 'i' — красная строка, 'gap' — промежуток
  static const _pics = <String, List<Object>>{
    'verses': [['n', 88], [58], 'gap', ['n', 92], [100], [34], 'gap', ['n', 70]],
    'flow': [['n', 90], [100], [38, 'n', 50], [100], [72, 'n', 16], [56]],
    'book': [['i', 76], [100], [100], [100], [48], ['i', 70]],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final bar = pal.text.withValues(alpha: 0.36);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.fastOutSlowIn,
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(12),
          decoration: iosStyleOf(ref)
              ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius))
              : BoxDecoration(
                  color: pal.bg,
                  border: Border.all(color: on ? pal.accent : pal.line),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: on ? pal.accent : pal.accent.withValues(alpha: 0), spreadRadius: on ? 2 : 0)],
                ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              Widget row(List row) {
                final items = <Widget>[];
                for (final x in row) {
                  if (items.isNotEmpty) items.add(const SizedBox(width: 3));
                  if (x == 'n') {
                    items.add(Container(width: 6, height: 7, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(2))));
                  } else if (x == 'i') {
                    items.add(SizedBox(width: w * 0.16));
                  } else {
                    items.add(Flexible(child: Container(width: w * (x as num) / 100, height: 5, decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(3)))));
                  }
                }
                return SizedBox(height: 5, child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: items));
              }

              final rows = _pics[kind]!;
              return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) const SizedBox(height: 5),
                  r == 'gap' ? const SizedBox(height: 2) : row(r as List),
                ],
              ]);
            },
          ),
        ),
        const SizedBox(height: 7),
        if (iosStyleOf(ref)) ...[
          Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.2, color: pal.text)),
          const SizedBox(height: 8),
          Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 24, color: on ? pal.accent : sysColor(CupertinoColors.tertiaryLabel, dark: pal.dark)),
        ] else
          Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, height: 1.2, fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: pal.text)),
      ]),
    );
  }
}

/// Пунктирный круг (.swatch.custom)
class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1;
    final path = Path()..addOval(Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1));
    for (final PathMetric m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// Выбор цвета кружками (.swatches): первый — цвет темы, дальше готовые, последний — свой (палитра)
class _ColorPick extends ConsumerWidget {
  const _ColorPick({required this.label, required this.s, required this.colorKey, required this.list, required this.onChanged, required this.onReset, required this.changed});
  final String label, colorKey;
  final Settings s;
  final List<(String, String)> list;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;
  final bool changed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final cur = colorFor(s, colorKey);
    final base = colorKey == 'heading' || colorKey == 'strong' ? baseColorFor(s, 'accent') : baseColorFor(s, colorKey);
    // .swatch: 44, рамка 18% текста; выбранный — кольцо цвета текста через зазор цвета окна; галочка 18
    Widget dot(Color c, bool on, {String? tip, VoidCallback? onTap, Widget? child, bool dashed = false}) => Tooltip(
          message: tip ?? '',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 44 + 8,
              height: 44 + 8,
              alignment: Alignment.center,
              // место под кольцо: 2 + 2 снаружи
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.fastOutSlowIn,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dashed && !on ? pal.bg : c,
                  shape: BoxShape.circle,
                  border: dashed && !on ? null : Border.all(color: on ? Colors.transparent : pal.text.withValues(alpha: 0.18)),
                  boxShadow: on ? [BoxShadow(color: pal.panel, spreadRadius: 2), BoxShadow(color: pal.text, spreadRadius: 4)].reversed.toList() : null,
                ),
                foregroundDecoration: null,
                child: dashed && !on
                    ? CustomPaint(size: const Size(44, 44), painter: _DashedCircle(pal.muted), child: Center(child: child))
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.fastOutSlowIn,
                        switchOutCurve: Curves.fastOutSlowIn,
                        transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: w)),
                        child: on ? Icon(ico(LucideIcons.check), key: const ValueKey('on'), size: 18, color: isLight(c) ? const Color(0xFF1d1c1a) : Colors.white) : KeyedSubtree(key: const ValueKey('off'), child: child ?? const SizedBox.shrink()),
                      ),
              ),
            ),
          ),
        );
    final curHex = toHex(cur);
    final custom = changed && !list.any((e) => e.$1 == curHex);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // стиль iPhone: подпись над образцами — заголовком группы
      if (iosUiNow) GroupTitle(label) else Text(label, style: fieldLabel(pal, bold: true)),
      const SizedBox(height: 6),
      // зазор между кружками 8, а кольцо у выбранного занимает ещё по 4 с каждой стороны — берём его из ячейки 52
      Transform.translate(
        offset: const Offset(-4, 0),
        child: Wrap(spacing: 0, runSpacing: 0, children: [
          dot(base, !changed, tip: t('Как в теме'), onTap: onReset),
          for (final e in list) dot(parseHex(e.$1)!, changed && curHex == e.$1, tip: t(e.$2), onTap: () => onChanged(parseHex(e.$1)!)),
          dot(custom ? cur : Colors.transparent, custom, tip: t('Свой цвет'), dashed: true, child: Icon(ico(LucideIcons.pipette), size: 18, color: pal.text), onTap: () async {
            final c = await pickColor(context, cur);
            if (c != null) onChanged(c);
          }),
        ]),
      ),
    ]);
  }
}

/// Строка тонкой настройки (.color-row): название, «вернуть цвет темы», окошко цвета 44×32
class _ColorLine extends ConsumerWidget {
  const _ColorLine({required this.label, required this.color, required this.changed, required this.onPick, required this.onReset});
  final String label;
  final Color color;
  final bool changed;
  final ValueChanged<Color> onPick;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(children: [
        Expanded(child: Text(label, style: fieldLabel(pal, bold: true))),
        // у неизменённого цвета кнопка скрыта, но место занимает (visibility: hidden)
        Visibility(
          visible: changed,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: IconBtn(icon: LucideIcons.rotateCcw, size: 16, tooltip: t('Вернуть цвет темы'), onTap: onReset),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () async {
            final c = await pickColor(context, color);
            if (c != null) onPick(c);
          },
          child: Container(width: 44, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.line))),
        ),
      ]),
    );
  }
}

/// Выбор своего цвета: оттенок, насыщенность, яркость
Future<Color?> pickColor(BuildContext context, Color initial) => showAobSheet<Color>(context, initial: 0.6, builder: (_) => _PickColor(initial: initial), scripture: true);

class _PickColor extends ConsumerStatefulWidget {
  const _PickColor({required this.initial});
  final Color initial;
  @override
  ConsumerState<_PickColor> createState() => _PickColorState();
}

class _PickColorState extends ConsumerState<_PickColor> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);

  Widget _slider(double value, double max, ValueChanged<double> onChanged, Color active) {
    final pal = paletteOf(ref);
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 5,
        activeTrackColor: active,
        inactiveTrackColor: pal.text.withValues(alpha: 0.16),
        thumbColor: active,
        overlayColor: active.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      child: SizedBox(height: 44, child: Slider(value: value, max: max, onChanged: onChanged)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final color = hsv.toColor();
    return AppSheet(
      title: t('Свой цвет'),
      footer: Row(children: [
        Expanded(child: AobButton(label: t('Отмена'), wide: true, onTap: () => Navigator.pop(context))),
        const SizedBox(width: 8),
        Expanded(child: AobButton(label: t('Готово'), kind: BtnKind.primary, wide: true, onTap: () => Navigator.pop(context, color))),
      ]),
      children: [
        Container(height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: pal.line))),
        Text(toHex(color), style: TextStyle(fontSize: 15, color: pal.text)),
        _slider(hsv.hue, 359.9, (v) => setState(() => hsv = hsv.withHue(v)), HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()),
        _slider(hsv.saturation, 1, (v) => setState(() => hsv = hsv.withSaturation(v)), pal.accent),
        _slider(hsv.value, 1, (v) => setState(() => hsv = hsv.withValue(v)), pal.accent),
      ],
    );
  }
}


/// Образец фона (.bg-preview): заголовок и первый стих поверх выбранной картинки с вуалью и размытием
class _BgPreview extends ConsumerWidget {
  const _BgPreview({required this.s});
  final Settings s;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(s);
    final fs = s.d('fontSize') < 20 ? s.d('fontSize') : 20.0;
    final plain = t('В начале{7225} сотворил{1254} Бог{430} небо{8064} и{853} землю.{776}').replaceAll(RegExp(r'\{\d+\}'), '');
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minHeight: 132),
      decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
      child: Stack(children: [
        const Positioned.fill(child: ReaderBackground()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Сотворение неба и земли'), style: readerTextStyle(s, size: fs * s.d('headingSize'), weight: 650).copyWith(color: headingColor(s), height: 1.3)),
            const SizedBox(height: 4),
            Text(plain, style: readerTextStyle(s, size: fs).copyWith(color: pal.text, height: s.d('lineHeight'))),
          ]),
        ),
      ]),
    );
  }
}

/// Уменьшенная копия своей картинки в плитке «Своё фото»
class _OwnThumb extends StatelessWidget {
  const _OwnThumb();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: UserBg.version,
        builder: (context, _, _) => FutureBuilder<Uint8List?>(
          future: UserBg.load(),
          builder: (context, snap) => snap.data == null ? const SizedBox.shrink() : Image.memory(snap.data!, fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true),
        ),
      );
}

/// «Цвета выделений»: свои названия цветов выделения (подписи хранит функция закладок — highlightLabels)
class _HlLabels extends ConsumerStatefulWidget {
  const _HlLabels();
  @override
  ConsumerState<_HlLabels> createState() => _HlLabelsState();
}

class _HlLabelsState extends ConsumerState<_HlLabels> {
  late final Map<String, TextEditingController> _c = {
    for (final h in hlColors) h.id: TextEditingController(text: ref.read(marksProvider).hlLabels[h.id] ?? ''),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (iosUiNow) GroupTitle(t('Цвета выделений')) else Text(t('Цвета выделений'), style: fieldLabel(pal, bold: true)),
      const SizedBox(height: 4),
      Text(t('Дайте цветам названия — например, «Обетования», «Вопросы».'), style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4)),
      const SizedBox(height: 8),
      // .hl-labels: столбцы не уже 150, зазор 8
      LayoutBuilder(
        builder: (context, box) {
          final cols = ((box.maxWidth + 8) / 158).floor().clamp(1, 6);
          final w = (box.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in hlColors)
              SizedBox(
                width: w,
                child: Row(children: [
                  Container(width: 20, height: 20, decoration: BoxDecoration(color: h.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AobInput(
                      controller: _c[h.id]!,
                      icon: null,
                      clearable: false,
                      autocorrect: false,
                      hint: t(h.name),
                      height: 44,
                      onChanged: (v) => ref.read(marksProvider.notifier).update((m) => m.copyWith(hlLabels: {...m.hlLabels, h.id: v})),
                    ),
                  ),
                ]),
              ),
          ]);
        },
      ),
    ]);
  }
}
