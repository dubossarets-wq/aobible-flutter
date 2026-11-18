// Стих дня (VerseOfDayCard.jsx): крупно на свободной фотографии, кнопки «Читать», «Картинка», «Поделиться».
// Стих и фото выбираются по дате. Текст — из установленного перевода.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../shell/fonts.dart' show readerTextStyle;
import 'net_cache.dart';
import 'ui_kit.dart';
import 'verse_list.dart';
import 'verse_text.dart';
import '../../ui/ios_style.dart';
import '../../core/rtl.dart';

class DayVerse {
  const DayVerse(this.ref, this.text, this.module);
  final VerseRef ref;
  final String text;
  final InstalledModule module;
}

VerseRef parseKey(String k) {
  final p = k.split('.');
  return VerseRef(p[0], int.parse(p[1]), int.parse(p[2]));
}

/// Текст стиха на дату. Если в установленных переводах его нет (например, только Новый Завет) — следующий стих списка
DayVerse? loadDayVerse(List<InstalledModule> mods, [DateTime? date]) {
  final first = verseOfDayKey(date);
  final start = verseList.indexOf(first);
  for (var k = 0; k < 40; k++) {
    final ref = parseKey(verseList[(start + k) % verseList.length]);
    for (final m in mods) {
      final text = verseText(m.id, ref)?.trim() ?? '';
      if (text.isNotEmpty) return DayVerse(ref, text, m);
    }
  }
  return null;
}

/// Фото на сегодня — из свободных снимков для картинок со стихом, тоже по дате
Future<Map<String, dynamic>?> todayPhoto() async {
  final j = await siteJson('images/verse-bg/index.json');
  final list = (j?['images'] as List?) ?? const [];
  return list.isEmpty ? null : (list[dayOfYear() % list.length] as Map).cast<String, dynamic>();
}

class VerseOfDayCard extends ConsumerStatefulWidget {
  const VerseOfDayCard({super.key, required this.pane, required this.onRead});
  final int pane;
  final void Function(VerseRef ref) onRead; // закрыть окно и перейти к стиху

  @override
  ConsumerState<VerseOfDayCard> createState() => _VerseOfDayCardState();
}


class _VerseOfDayCardState extends ConsumerState<VerseOfDayCard> {
  DayVerse? _v;
  bool _loaded = false;
  Map<String, dynamic>? _photo;

  @override
  void initState() {
    super.initState();
    final panes = ref.read(panesProvider);
    final mods = verseModules(panes.isEmpty ? null : panes.first.moduleId, ref.read(settingsProvider).get<String>('primaryModule'));
    _v = loadDayVerse(mods);
    _loaded = true;
    todayPhoto().then((p) => mounted ? setState(() => _photo = p) : null);
  }

  Future<void> _share() async {
    final v = _v!;
    await SharePlus.instance.share(ShareParams(text: quoteVerse(v.text, quoteLabel([v.ref]))));
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && _v == null) return const SizedBox.shrink();
    final pal = paletteOf(ref);
    final v = _v!;
    final light = _photo?['tone'] == 'light';
    final size = MediaQuery.sizeOf(context);
    // .today-verse: min-height min(360px, 46vh); .today-text: clamp(1.3rem, 5.6vw, 1.75rem)
    final textSize = (size.width * 0.056).clamp(20.8, 28.0).toDouble();
    // Фон-градиент — слоем под фото внутри одной обрезки: фон у самой рамки просвечивал тонкой каймой по скруглённому краю
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      // стиль iPhone — скругление карточек (системное, как у статистики и списка планов)
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onRead(v.ref),
        child: ClipPath(
      clipper: ShapeBorderClipper(shape: iosUiNow ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(iosRadius)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: const Alignment(-0.34, -1), end: const Alignment(0.34, 1), colors: [mix(pal.accent, 0.55, const Color(0xFF0B1020)), const Color(0xFF0B1020)]),
            ),
          ),
        ),
        if (_photo != null) Positioned.fill(child: SiteImage('images/verse-bg/${_photo!['file']}')),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.4, 1], colors: [
                Colors.black.withValues(alpha: light ? 0.4 : 0.28),
                Colors.black.withValues(alpha: light ? 0.55 : 0.42),
                Colors.black.withValues(alpha: light ? 0.78 : 0.7),
              ]),
            ),
          ),
        ),
        // высота — у содержимого, а не у рамки: стих по центру свободного места, кнопки — внизу (без пустоты под ними)
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.min(320, size.height * 0.42)),
          child: IntrinsicHeight(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // .today-verse-body: по центру свободного места, промежуток 14
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Стих дня'), style: const TextStyle(color: Color(0xE0FFFFFF), fontSize: 13.8, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Text(v.text, style: readerTextStyle(ref.watch(settingsProvider), size: textSize, weight: 500).copyWith(color: Colors.white, height: 1.38, fontWeight: FontWeight.w500, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 1))]), textDirection: textDirOf(v.text)),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: 0.95,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Opacity(opacity: 0.7 / 0.95, child: Container(width: 36, height: 2, color: Colors.white)),
                      const SizedBox(height: 10),
                      Text(selectionLabel([v.ref], full: true), style: const TextStyle(color: Colors.white, fontSize: 16.3, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ),
            ),
            // Автор и лицензия фото — в «О приложении → Лицензии», не на карточке
          ]),
          ),
        ),
        // «Отправить» — сверху справа, с ровными отступами от краёв карточки
        Positioned(
          top: 14,
          right: 14,
          child: Tooltip(
            message: t('Поделиться'),
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.45))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _share,
                child: SizedBox(width: 40, height: 40, child: Center(child: AIcon(ico(LucideIcons.share2), size: 18, color: Colors.white))),
              ),
            ),
          ),
        ),
      ]),
      )),
    );
  }
}
