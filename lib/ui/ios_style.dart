// «Стиль iPhone» (настройка iosStyle, включается в «Оформлении» на iPhone): системные цвета iOS, окна-листы,
// строки как в «Настройках» iPhone, переключатели и кнопки iOS, значки из набора Apple (Cupertino Icons).
// Выключен — всё как обычно. Цвета — палитры iosLight / iosDark (settings.dart), остальное — общие элементы kit.dart.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/settings.dart';

/// Включён ли стиль iPhone (виджет перестраивается при переключении)
bool iosStyleOf(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.get<bool>('iosStyle')));

/// Фон строк поверх серого фона групп (secondarySystemGroupedBackground)
Color iosCard(Palette p) => p.dark ? const Color(0xff2c2c2e) : const Color(0xffffffff);

/// Заливка кнопок и плашек без рамки (tertiarySystemFill)
Color iosFill(Palette p) => p.dark ? const Color(0x3d767680) : const Color(0x1f767680);

/// Системный зелёный — включённый переключатель
const iosGreen = Color(0xff34c759);

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
