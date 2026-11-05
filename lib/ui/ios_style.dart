// «Стиль iPhone» (настройка iosStyle, включается в «Оформлении» на iPhone): системные цвета iOS, окна-листы,
// строки как в «Настройках» iPhone, переключатели и кнопки iOS, значки из набора Apple (Cupertino Icons).
// Выключен — всё как обычно. Цвета — палитры iosLight / iosDark (settings.dart), остальное — общие элементы kit.dart.
import 'package:flutter/cupertino.dart' show CupertinoColors, CupertinoIcons, CupertinoListTile;
import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/settings.dart';
import 'kit.dart' show GroupTitle, MenuSep;

/// Включён ли стиль iPhone (виджет перестраивается при переключении)
bool iosStyleOf(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.get<bool>('iosStyle')));

/// Палитра стиля iPhone — для элементов без доступа к настройкам (им передают только палитру)
bool iosPal(Palette p) => p.label == 'iOS' || p.label == 'iOS тёмная';

/// Фон строк поверх серого фона групп (secondarySystemGroupedBackground, приподнятый)
Color iosCard(Palette p) => sysColor(CupertinoColors.secondarySystemGroupedBackground, dark: p.dark, elevated: true);

/// Заливка кнопок и плашек без рамки (tertiarySystemFill)
Color iosFill(Palette p) => sysColor(CupertinoColors.tertiarySystemFill, dark: p.dark);

/// Общий отступ от краёв экрана в стиле iPhone: шапка, текст, круглые кнопки и нижнее меню — на одной линии,
/// у меню снизу — такой же, как по бокам
const iosEdge = 20.0;

/// Системный зелёный — включённый переключатель (UIKit systemGreen: светлая / тёмная)
const iosGreen = Color(0xff34c759);
Color iosGreenOf(Palette p) => sysColor(CupertinoColors.systemGreen, dark: p.dark);

/// Уровень, как в UIKit: окно поверх текста — «приподнятое» (в тёмной: фон #1C1C1E, карточки #2C2C2E),
/// страница на весь экран — базовое (фон #000000, карточки #1C1C1E); в светлой — всегда #F2F2F7 и белые карточки
class IosElevated extends InheritedWidget {
  const IosElevated({super.key, required this.elevated, required super.child});
  final bool elevated;
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosElevated>()?.elevated ?? true;
  @override
  bool updateShouldNotify(IosElevated old) => old.elevated != elevated;
}

/// Фон карточки группы по уровню (secondarySystemGroupedBackground)
Color iosCardAt(Palette p, bool elevated) => sysColor(CupertinoColors.secondarySystemGroupedBackground, dark: p.dark, elevated: elevated);

/// Фон окна по уровню (systemGroupedBackground)
Color iosGroupedBg(Palette p, bool elevated) => sysColor(CupertinoColors.systemGroupedBackground, dark: p.dark, elevated: elevated);

/// Значок из набора Apple вместо нашего (если есть похожий), иначе — тот же
IconData iosIcon(IconData i) => _map[i] ?? i;

/// Включён ли сейчас стиль iPhone (ставит главное окно по настройке iosStyle) — для мест без доступа к настройкам
bool iosUiNow = false;

/// Значок для показа: в стиле iPhone — системный знак iOS (CupertinoIcons, аналог SF Symbols), иначе — как есть
T ico<T extends IconData?>(T i) => (iosUiNow && i != null ? iosIcon(i) : i) as T;

final Map<IconData, IconData> _map = {
  LucideIcons.x: CupertinoIcons.xmark,
  LucideIcons.plus: CupertinoIcons.add,
  LucideIcons.minus: CupertinoIcons.minus,
  LucideIcons.check: CupertinoIcons.checkmark,
  LucideIcons.chevronRight: CupertinoIcons.chevron_forward,
  LucideIcons.chevronLeft: CupertinoIcons.chevron_back,
  LucideIcons.chevronDown: CupertinoIcons.chevron_down,
  LucideIcons.arrowLeft: CupertinoIcons.arrow_left,
  LucideIcons.arrowRight: CupertinoIcons.arrow_right,
  LucideIcons.trash2: CupertinoIcons.trash,
  LucideIcons.scrollText: CupertinoIcons.doc_text,
  LucideIcons.scroll: CupertinoIcons.doc_text,
  LucideIcons.headphones: CupertinoIcons.headphones,
  LucideIcons.bookOpen: CupertinoIcons.book,
  LucideIcons.bookText: CupertinoIcons.book,
  LucideIcons.bookOpenCheck: CupertinoIcons.book_solid,
  LucideIcons.search: CupertinoIcons.search,
  LucideIcons.library: CupertinoIcons.collections,
  LucideIcons.heart: CupertinoIcons.heart,
  LucideIcons.refreshCw: CupertinoIcons.arrow_clockwise,
  LucideIcons.rotateCw: CupertinoIcons.arrow_clockwise,
  LucideIcons.rotateCcw: CupertinoIcons.arrow_counterclockwise,
  LucideIcons.link2: CupertinoIcons.link,
  LucideIcons.image: CupertinoIcons.photo,
  LucideIcons.imagePlus: CupertinoIcons.photo_on_rectangle,
  LucideIcons.columns2: CupertinoIcons.square_split_2x1,
  LucideIcons.type: CupertinoIcons.textformat,
  LucideIcons.letterText: CupertinoIcons.textformat_alt,
  LucideIcons.notebookPen: CupertinoIcons.square_pencil,
  LucideIcons.penLine: CupertinoIcons.pencil,
  LucideIcons.mapPin: CupertinoIcons.location,
  LucideIcons.map: CupertinoIcons.map,
  LucideIcons.download: CupertinoIcons.cloud_download,
  LucideIcons.upload: CupertinoIcons.cloud_upload,
  LucideIcons.share2: CupertinoIcons.share,
  LucideIcons.messageSquareText: CupertinoIcons.text_bubble,
  LucideIcons.layers: CupertinoIcons.layers,
  LucideIcons.languages: CupertinoIcons.globe,
  LucideIcons.highlighter: CupertinoIcons.paintbrush,
  LucideIcons.palette: CupertinoIcons.paintbrush,
  LucideIcons.hardDrive: CupertinoIcons.archivebox,
  LucideIcons.copy: CupertinoIcons.doc_on_doc,
  LucideIcons.calendarCheck: CupertinoIcons.calendar,
  LucideIcons.bookmark: CupertinoIcons.bookmark,
  LucideIcons.bookmarkCheck: CupertinoIcons.bookmark_fill,
  LucideIcons.triangleAlert: CupertinoIcons.exclamationmark_triangle,
  LucideIcons.star: CupertinoIcons.star,
  LucideIcons.sparkles: CupertinoIcons.sparkles,
  LucideIcons.info: CupertinoIcons.info_circle,
  LucideIcons.folder: CupertinoIcons.folder,
  LucideIcons.folderPlus: CupertinoIcons.folder_badge_plus,
  LucideIcons.zoomIn: CupertinoIcons.zoom_in,
  LucideIcons.zoomOut: CupertinoIcons.zoom_out,
  LucideIcons.slidersHorizontal: CupertinoIcons.slider_horizontal_3,
  LucideIcons.history: CupertinoIcons.clock,
  LucideIcons.hash: CupertinoIcons.number,
  LucideIcons.externalLink: CupertinoIcons.arrow_up_right_square,
  LucideIcons.ellipsisVertical: CupertinoIcons.ellipsis_vertical,
  LucideIcons.cornerUpLeft: CupertinoIcons.arrow_uturn_left,
  LucideIcons.undo2: CupertinoIcons.arrow_uturn_left,
  LucideIcons.redo2: CupertinoIcons.arrow_uturn_right,
  LucideIcons.ban: CupertinoIcons.nosign,
  LucideIcons.wifiOff: CupertinoIcons.wifi_slash,
  LucideIcons.volume2: CupertinoIcons.speaker_2,
  LucideIcons.volume1: CupertinoIcons.speaker_1,
  LucideIcons.settings: CupertinoIcons.gear,
  LucideIcons.send: CupertinoIcons.paperplane,
  LucideIcons.save: CupertinoIcons.floppy_disk,
  LucideIcons.printer: CupertinoIcons.printer,
  LucideIcons.play: CupertinoIcons.play_fill,
  LucideIcons.music: CupertinoIcons.music_note,
  LucideIcons.moon: CupertinoIcons.moon,
  LucideIcons.menu: CupertinoIcons.line_horizontal_3,
  LucideIcons.mail: CupertinoIcons.mail,
  LucideIcons.maximize2: CupertinoIcons.fullscreen,
  LucideIcons.stickyNote: CupertinoIcons.doc_plaintext,
  LucideIcons.textQuote: CupertinoIcons.text_quote,
  LucideIcons.pipette: CupertinoIcons.eyedropper,
  LucideIcons.hand: CupertinoIcons.hand_raised,
  LucideIcons.rows2: CupertinoIcons.square_split_1x2,
  LucideIcons.scanText: CupertinoIcons.doc_text_viewfinder,
  LucideIcons.messageSquareWarning: CupertinoIcons.exclamationmark_bubble,
  LucideIcons.link: CupertinoIcons.link,
  LucideIcons.globe: CupertinoIcons.globe,
  LucideIcons.eyeOff: CupertinoIcons.eye_slash,
  LucideIcons.eye: CupertinoIcons.eye,
  LucideIcons.cornerDownLeft: CupertinoIcons.arrow_turn_down_left,
  LucideIcons.circlePlay: CupertinoIcons.play_circle,
  LucideIcons.bookOpenText: CupertinoIcons.book,
  LucideIcons.satellite: CupertinoIcons.antenna_radiowaves_left_right,
  LucideIcons.listChecks: CupertinoIcons.checkmark_rectangle,
  LucideIcons.italic: CupertinoIcons.italic,
  LucideIcons.flame: CupertinoIcons.flame,
  LucideIcons.ellipsis: CupertinoIcons.ellipsis,
  LucideIcons.copyPlus: CupertinoIcons.plus_square_on_square,
  LucideIcons.compass: CupertinoIcons.compass,
  LucideIcons.clock: CupertinoIcons.clock,
  LucideIcons.circleCheck: CupertinoIcons.checkmark_circle,
  LucideIcons.circleAlert: CupertinoIcons.exclamationmark_circle,
  LucideIcons.chevronUp: CupertinoIcons.chevron_up,
  LucideIcons.calendarPlus: CupertinoIcons.calendar_badge_plus,
  LucideIcons.bookCopy: CupertinoIcons.book,
  LucideIcons.bold: CupertinoIcons.bold,
  LucideIcons.bell: CupertinoIcons.bell,
  LucideIcons.arrowUp: CupertinoIcons.arrow_up,
  LucideIcons.arrowDown: CupertinoIcons.arrow_down,
  LucideIcons.alignLeft: CupertinoIcons.text_alignleft,
  LucideIcons.alignJustify: CupertinoIcons.text_justify,
  LucideIcons.alarmClockPlus: CupertinoIcons.alarm,
  LucideIcons.alarmClock: CupertinoIcons.alarm,
  LucideIcons.presentation: CupertinoIcons.rectangle_on_rectangle,
  LucideIcons.panelTop: CupertinoIcons.rectangle,
  LucideIcons.mousePointerClick: CupertinoIcons.hand_point_right,
  LucideIcons.eraser: CupertinoIcons.clear,
};

// --- Группы строк, как в «Настройках» iPhone -----------------------------------------------------------

/// Строка, которая в стиле iPhone собирается в общую карточку с соседними (PrefRow, MenuRow, SwitchRow…);
/// iosIndent — откуда начинается линия-разделитель под строкой (от начала текста)
abstract interface class IosGroupRow {
  double get iosIndent;
}

/// Строка с пояснением под карточкой (как серый текст под «True Tone» в «Экран и яркость»)
abstract interface class IosFooterRow {
  String? get iosFooter;
}

/// Строка, у которой подпись — заголовком над своей карточкой (ползунок: «Яркость» над карточкой с ползунком)
abstract interface class IosHeaderRow {
  String? get iosHeader;
}

/// Строка стоит внутри карточки группы (её подпись уже показана заголовком над карточкой)
class IosInCard extends InheritedWidget {
  const IosInCard({super.key, required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosInCard>() != null;
  @override
  bool updateShouldNotify(IosInCard old) => false;
}

/// Отступ заголовка и пояснения группы от края карточки — по линии текста строк без значка (20, как в iOS 26)
const iosHeaderLeft = 20.0;

/// Пояснение под карточкой: серый текст, как в «Настройках» iPhone
class IosFooter extends StatelessWidget {
  const IosFooter(this.text, {super.key, required this.pal, this.margin = 0});
  final String text;
  final Palette pal;
  final double margin;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(margin + iosHeaderLeft, 0, margin + iosHeaderLeft, 0),
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.3, color: pal.muted)),
      );
}

/// Блок группы со своими полями внутри карточки (ползунок «Размер текста» и т. п.), а не строка CupertinoListTile
abstract interface class IosGroupBlock implements IosGroupRow {}

/// Поля блока внутри карточки: как у строк — 18 слева и 20 справа
const iosBlockPadding = EdgeInsets.fromLTRB(iosRowIconLeft, 10, iosRowRight, 6);

/// Скругление карточки группы — как у списков «Настроек» в iOS 26
const iosRadius = 26.0;

/// Скругление Apple: непрерывная кривая (суперэллипс, как у значков и карточек iOS) — угол плавно переходит
/// в сторону, без излома, как у обычной дуги окружности
ShapeDecoration iosShape(Color color, BorderRadius radius, {BorderSide side = BorderSide.none}) =>
    ShapeDecoration(color: color, shape: RoundedSuperellipseBorder(borderRadius: radius, side: side));

/// Промежуток между разделами (карточками) — как в «Настройках» iPhone
const iosSectionGap = 35.0;

/// Разрыв: строки до и после него — в разных карточках (например, «Сбросить» отдельно, как «Выключить» в iPhone)
class IosBreak extends StatelessWidget {
  const IosBreak({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Подряд идущие строки — в одну белую скруглённую карточку с отступом iosEdge от краёв окна
/// (sidePad — поля самого списка: карточка добавляет к ним недостающее; gap — промежуток списка между
/// элементами: до iosSectionGap между разделами добавляется недостающее). Остальное — как было
List<Widget> iosGroup(List<Widget> children, Palette pal, double sidePad, {double gap = 12}) {
  IosGroupRow? rowOf(Widget w) => w is IosGroupRow ? w as IosGroupRow : (w is Padding && w.child is IosGroupRow ? w.child! as IosGroupRow : null);
  final m = (iosEdge - sidePad).clamp(0.0, iosEdge);
  final extra = (iosSectionGap - gap).clamp(0.0, iosSectionGap);
  // 0 — прочее, 1 — подзаголовок, 2 — карточка
  final out = <(Widget, int)>[];
  var run = <(Widget, IosGroupRow)>[];
  void flush() {
    if (run.isEmpty) return;
    Widget body(Widget w, IosGroupRow r) {
      final c = w is Padding ? w.child! : w;
      return r is IosGroupBlock ? Padding(padding: iosBlockPadding, child: c) : c;
    }

    out.add((IosSection(rows: [for (final (w, r) in run) body(w, r)], indents: [for (final (_, r) in run) r.iosIndent], pal: pal, margin: m), 2));
    run = [];
  }

  for (final w in children) {
    final r = rowOf(w);
    if (r != null) {
      // подпись ползунка — заголовком над его карточкой, сам ползунок — отдельной карточкой
      final header = r is IosHeaderRow ? (r as IosHeaderRow).iosHeader : null;
      if (header != null) {
        flush();
        out.add((GroupTitle(header), 1));
      }
      run.add((w, r));
      final footer = r is IosFooterRow ? (r as IosFooterRow).iosFooter : null;
      if (header != null || footer != null) flush();
      if (footer != null) out.add((IosFooter(footer, pal: pal, margin: m), 3));
    } else {
      flush();
      // разделитель групп (MenuSep во всю ширину) — тоже разрыв: промежуток между карточками ставится здесь
      if (w is! IosBreak && !(w is MenuSep && w.full)) out.add((w, w is GroupTitle ? 1 : 0));
    }
  }
  flush();

  // промежутки как в iPhone: перед подзаголовком и карточкой — увеличенный (у подзаголовка 14 сверху уже есть),
  // между подзаголовком и его карточкой — обычный, после карточки — тоже увеличенный
  final res = <Widget>[];
  for (var i = 0; i < out.length; i++) {
    final (w, k) = out[i];
    final prev = i > 0 ? out[i - 1].$2 : -1;
    final next = i + 1 < out.length ? out[i + 1].$2 : -1;
    var top = 0.0;
    if (i > 0) {
      // после пояснения промежуток меньше (у пояснения свой воздух снизу), как в iOS
      final base = prev == 3 ? extra - 10 : extra;
      if (k == 1) top = base - 14;
      if (k == 2 && prev != 1) top = base;
      if (k == 0 && (prev == 2 || prev == 3)) top = base;
      if (k == 3) top = 0;
    }
    // подзаголовок прямо над карточкой — на линии текста её строк, как в «Настройках» iPhone
    final left = k == 1 && next == 2 ? m + iosHeaderLeft : 0.0;
    res.add(top <= 0 && left == 0 ? w : Padding(padding: EdgeInsets.only(left: left, top: top.clamp(0.0, iosSectionGap)), child: w));
  }
  return res;
}

/// Карточка группы: белая (в тёмной — графитовая), системное скругление, линии между строками — от начала текста
class IosSection extends StatelessWidget {
  const IosSection({super.key, required this.rows, required this.indents, required this.pal, this.margin = 0});
  final List<Widget> rows;
  final List<double> indents;
  final Palette pal;
  final double margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.symmetric(horizontal: margin),
        clipBehavior: Clip.antiAlias,
        decoration: iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++) ...[
            IosInCard(child: rows[i]),
            if (i < rows.length - 1) Padding(padding: EdgeInsets.only(left: indents[i], right: iosRowRight), child: Container(height: 0.5, color: pal.line)),
          ],
        ]),
      );
}

/// Строка длинного списка (строится по ходу прокрутки) как часть карточки группы iOS: у первой — скруглён верх,
/// у последней — низ; между строками — тонкая линия от начала текста
class IosCardItem extends StatelessWidget {
  const IosCardItem({super.key, required this.child, required this.pal, this.first = false, this.last = false, this.indent = iosRowIconLeft, this.margin = iosEdge - 16});
  final Widget child;
  final Palette pal;
  final bool first, last;
  final double indent, margin;
  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(iosRadius);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: margin),
      clipBehavior: Clip.antiAlias,
      decoration: iosShape(
        iosCardAt(pal, IosElevated.of(context)),
        BorderRadius.only(topLeft: first ? r : Radius.zero, topRight: first ? r : Radius.zero, bottomLeft: last ? r : Radius.zero, bottomRight: last ? r : Radius.zero),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        child,
        if (!last) Padding(padding: EdgeInsets.only(left: indent), child: Container(height: 0.5, color: pal.line)),
      ]),
    );
  }
}

/// Значок строки, как в «Настройках» iPhone: белый знак в цветном скруглённом квадрате 30×30
class IosIconSquare extends StatelessWidget {
  const IosIconSquare(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        width: iosRowIcon,
        height: iosRowIcon,
        decoration: iosShape(color ?? iosIconColor(icon), BorderRadius.circular(6.5)),
        child: Icon(iosIcon(icon), size: 17, color: const Color(0xffffffff)),
      );
}

/// Размеры строки списка, как в «Настройках» iPhone: значок 28 в 18 от края карточки, текст — в 60, высота 52,
/// «›» и конец линии — в 20 от правого края
const iosRowIconLeft = 18.0, iosRowIcon = 28.0, iosRowTextLeft = 60.0, iosRowRight = 20.0, iosRowHeight = 52.0;

/// Строка списка стиля iPhone: системная CupertinoListTile с размерами «Настроек» iPhone
Widget iosTile({Widget? leading, required Widget title, Widget? additionalInfo, Widget? trailing, VoidCallback? onTap}) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: iosRowHeight),
      child: CupertinoListTile(
        padding: EdgeInsetsDirectional.only(start: leading == null ? iosRowIconLeft + 2 : iosRowIconLeft, end: iosRowRight, top: 8, bottom: 8),
        leading: leading,
        leadingSize: iosRowIcon,
        leadingToTitle: iosRowTextLeft - iosRowIconLeft - iosRowIcon,
        title: title,
        additionalInfo: additionalInfo,
        trailing: trailing,
        onTap: onTap,
      ),
    );

/// Стрелка «›» справа у строки (серая, как в iOS)
Color iosChevron(Palette p) => sysColor(CupertinoColors.tertiaryLabel, dark: p.dark);

/// Цвет квадрата значка — по смыслу пункта (системные цвета iOS), прочие — синие
Color iosIconColor(IconData i) => _colors[i] ?? const Color(0xff007aff);

const _orange = Color(0xffff9500), _red = Color(0xffff3b30), _pink = Color(0xffff2d55), _green = Color(0xff34c759);
const _blue = Color(0xff007aff), _indigo = Color(0xff5856d6), _purple = Color(0xffaf52de), _gray = Color(0xff8e8e93), _teal = Color(0xff30b0c7), _cyan = Color(0xff32ade6);

final Map<IconData, Color> _colors = {
  LucideIcons.bookmark: _orange,
  LucideIcons.bookmarkCheck: _orange,
  LucideIcons.heart: _pink,
  LucideIcons.scrollText: _indigo,
  LucideIcons.calendarCheck: _red,
  LucideIcons.headphones: _pink,
  LucideIcons.map: _green,
  LucideIcons.mapPin: _green,
  LucideIcons.link: _blue,
  LucideIcons.link2: _blue,
  LucideIcons.rows2: _indigo,
  LucideIcons.columns2: _indigo,
  LucideIcons.library: _teal,
  LucideIcons.palette: _purple,
  LucideIcons.settings: _gray,
  LucideIcons.bookOpen: _blue,
  LucideIcons.bookOpenText: _blue,
  LucideIcons.bookOpenCheck: _blue,
  LucideIcons.info: _gray,
  LucideIcons.messageSquareWarning: _red,
  LucideIcons.sparkles: _orange,
  LucideIcons.circlePlay: _green,
  LucideIcons.eye: _indigo,
  LucideIcons.eyeOff: _indigo,
  LucideIcons.globe: _blue,
  LucideIcons.languages: _blue,
  LucideIcons.hardDrive: _gray,
  LucideIcons.refreshCw: _green,
  // «Оформление»: разные системные цвета, как разделы «Настроек» iPhone
  LucideIcons.type: _gray,
  LucideIcons.hash: _orange,
  LucideIcons.image: _cyan,
  LucideIcons.panelTop: _indigo,
  LucideIcons.messageSquareText: _green,
  LucideIcons.ellipsisVertical: _indigo,
  LucideIcons.download: _blue,
  LucideIcons.trash2: _red,
};

// --- Системный шрифт iOS ------------------------------------------------------------------------------------

/// Межбуквенный интервал системного шрифта iOS (SF Pro) по размеру — таблица трекинга Apple (Human Interface
/// Guidelines → Typography): мелкий текст чуть разрежен, 13–20 pt сжат, крупные заголовки — снова свободнее
double iosTracking(double size) {
  final t = <double, double>{11: 0.06, 12: 0, 13: -0.08, 14: -0.15, 15: -0.23, 16: -0.31, 17: -0.43, 18: -0.44, 19: -0.45, 20: -0.45, 22: -0.26, 24: 0.07, 28: 0.38, 34: 0.40};
  final keys = t.keys.toList();
  if (size <= keys.first) return t[keys.first]!;
  if (size >= keys.last) return t[keys.last]!;
  for (var i = 1; i < keys.length; i++) {
    if (size <= keys[i]) {
      final a = keys[i - 1], b = keys[i];
      return t[a]! + (t[b]! - t[a]!) * (size - a) / (b - a);
    }
  }
  return 0;
}

/// Тема текста для iPhone: системный шрифт и системный трекинг вместо интервалов Material (+0,25…+0,5)
TextTheme iosTextTheme(TextTheme base) {
  TextStyle? f(TextStyle? s) => s?.copyWith(letterSpacing: iosTracking(s.fontSize ?? 17));
  return base.copyWith(
    displayLarge: f(base.displayLarge), displayMedium: f(base.displayMedium), displaySmall: f(base.displaySmall),
    headlineLarge: f(base.headlineLarge), headlineMedium: f(base.headlineMedium), headlineSmall: f(base.headlineSmall),
    titleLarge: f(base.titleLarge), titleMedium: f(base.titleMedium), titleSmall: f(base.titleSmall),
    bodyLarge: f(base.bodyLarge), bodyMedium: f(base.bodyMedium), bodySmall: f(base.bodySmall),
    labelLarge: f(base.labelLarge), labelMedium: f(base.labelMedium), labelSmall: f(base.labelSmall),
  );
}

// --- Смахивание строки, как в iOS 26 («Заметки», «Напоминания») ------------------------------------------------

/// Кнопка за строкой: цветная капсула со знаком, подпись под ней
class IosSwipeAction {
  const IosSwipeAction({required this.icon, required this.label, required this.color, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool destructive; // смахивание до конца — сразу это действие (удаление)
}

/// Строка смахивается влево и открывает кнопки-капсулы с подписями; дальше половины ширины — выполняется
/// последнее (разрушающее) действие; нажатие по открытой строке или смахивание вправо — закрывает
class IosSwipe extends StatefulWidget {
  const IosSwipe({super.key, required this.child, required this.actions, required this.pal});
  final Widget child;
  final List<IosSwipeAction> actions;
  final Palette pal;
  @override
  State<IosSwipe> createState() => _IosSwipeState();
}

class _IosSwipeState extends State<IosSwipe> with SingleTickerProviderStateMixin {
  static const _btn = 74.0, _gap = 8.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), lowerBound: -4000, upperBound: 0, value: 0);
  double get _open => widget.actions.length * (_btn + _gap) + _gap;
  double _w = 400;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _to(double x) => _c.animateTo(x, curve: Curves.easeOutCubic);

  void _end(DragEndDetails d) {
    final x = _c.value, v = d.primaryVelocity ?? 0;
    final last = widget.actions.isEmpty ? null : widget.actions.last;
    if (last != null && last.destructive && (x < -_w * 0.6 || (v < -1800 && x < -_open))) {
      _c.animateTo(-_w, curve: Curves.easeOut).then((_) => last.onTap());
      return;
    }
    _to(v < -300 || (v <= 300 && x < -_open / 2) ? -_open : 0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        _w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => _c.value = (_c.value + d.primaryDelta!).clamp(-_w, 0.0),
          onHorizontalDragEnd: _end,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final x = _c.value;
              final shown = (-x / _open).clamp(0.0, 1.0);
              return Stack(children: [
                // кнопки справа: проявляются по мере смахивания
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: shown,
                      child: Padding(
                        padding: const EdgeInsets.only(right: _gap),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final a in widget.actions)
                            Padding(
                              padding: const EdgeInsets.only(left: _gap),
                              child: Semantics(
                                button: true,
                                label: a.label,
                                child: GestureDetector(
                                  onTap: () {
                                    _to(0);
                                    a.onTap();
                                  },
                                  child: SizedBox(
                                    width: _btn,
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Container(
                                        width: _btn,
                                        height: 40,
                                        decoration: BoxDecoration(color: a.color, borderRadius: BorderRadius.circular(20)),
                                        child: Icon(a.icon, size: 20, color: const Color(0xffffffff)),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: widget.pal.muted)),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(x, 0),
                  child: x < 0
                      // открытая строка — отдельной скруглённой плашкой (как в «Заметках»); нажатие закрывает её
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _to(0),
                          child: DecoratedBox(
                            decoration: iosShape(sysColor(CupertinoColors.tertiarySystemGroupedBackground, dark: widget.pal.dark), BorderRadius.circular(iosRadius * 0.8)),
                            child: AbsorbPointer(child: child),
                          ),
                        )
                      : child,
                ),
              ]);
            },
            child: widget.child,
          ),
        );
      });
}
