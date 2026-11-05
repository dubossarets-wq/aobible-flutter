// «Стиль iPhone» (настройка iosStyle, включается в «Оформлении» на iPhone): системные цвета iOS, окна-листы,
// строки как в «Настройках» iPhone, переключатели и кнопки iOS, значки из набора Apple (Cupertino Icons).
// Выключен — всё как обычно. Цвета — палитры iosLight / iosDark (settings.dart), остальное — общие элементы kit.dart.
import 'package:flutter/cupertino.dart' show CupertinoColors, CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/settings.dart';

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
};

// --- Группы строк, как в «Настройках» iPhone -----------------------------------------------------------

/// Строка, которая в стиле iPhone собирается в общую карточку с соседними (PrefRow, MenuRow, SwitchRow…);
/// iosIndent — откуда начинается линия-разделитель под строкой (от начала текста)
abstract interface class IosGroupRow {
  double get iosIndent;
}

/// Подряд идущие строки — в одну белую скруглённую карточку с отступом iosEdge от краёв окна
/// (sidePad — поля самого списка: карточка добавляет к ним недостающее). Остальное — как было
List<Widget> iosGroup(List<Widget> children, Palette pal, double sidePad) {
  IosGroupRow? rowOf(Widget w) => w is IosGroupRow ? w as IosGroupRow : (w is Padding && w.child is IosGroupRow ? w.child! as IosGroupRow : null);
  final out = <Widget>[];
  var run = <(Widget, IosGroupRow)>[];
  void flush() {
    if (run.isEmpty) return;
    out.add(IosSection(rows: [for (final (w, _) in run) w is Padding ? w.child! : w], indents: [for (final (_, r) in run) r.iosIndent], pal: pal, margin: (iosEdge - sidePad).clamp(0.0, iosEdge)));
    run = [];
  }

  for (final w in children) {
    final r = rowOf(w);
    if (r != null) {
      run.add((w, r));
    } else {
      flush();
      out.add(w);
    }
  }
  flush();
  return out;
}

/// Карточка группы: белая (в тёмной — графитовая), скругление 26, линии между строками — от начала текста
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
        decoration: BoxDecoration(color: iosCardAt(pal, IosElevated.of(context)), borderRadius: BorderRadius.circular(26)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) Padding(padding: EdgeInsets.only(left: indents[i], right: 16), child: Container(height: 0.5, color: pal.line)),
          ],
        ]),
      );
}

/// Значок строки, как в «Настройках» iPhone: белый знак в цветном скруглённом квадрате 30×30
class IosIconSquare extends StatelessWidget {
  const IosIconSquare(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color ?? iosIconColor(icon), borderRadius: BorderRadius.circular(7.5)),
        child: Icon(iosIcon(icon), size: 18, color: const Color(0xffffffff)),
      );
}

/// Стрелка «›» справа у строки (серая, как в iOS)
Color iosChevron(Palette p) => sysColor(CupertinoColors.tertiaryLabel, dark: p.dark);

/// Цвет квадрата значка — по смыслу пункта (системные цвета iOS), прочие — синие
Color iosIconColor(IconData i) => _colors[i] ?? const Color(0xff007aff);

const _orange = Color(0xffff9500), _red = Color(0xffff3b30), _pink = Color(0xffff2d55), _green = Color(0xff34c759);
const _blue = Color(0xff007aff), _indigo = Color(0xff5856d6), _purple = Color(0xffaf52de), _gray = Color(0xff8e8e93), _teal = Color(0xff30b0c7);

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
  LucideIcons.type: _blue,
  LucideIcons.download: _blue,
  LucideIcons.trash2: _red,
};
