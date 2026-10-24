// Стих дня (VerseOfDayCard.jsx): крупно на свободной фотографии, кнопки «Читать», «Картинка», «Поделиться».
// Стих и фото выбираются по дате. Текст — из установленного перевода.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import 'net_cache.dart';
import 'ui_kit.dart';
import 'verse_image.dart';
import 'verse_list.dart';
import 'verse_text.dart';

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
    final pal = ref.watch(settingsProvider).palette;
    final v = _v!;
    final light = _photo?['tone'] == 'light';
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      constraints: BoxConstraints(minHeight: (h * 0.46).clamp(0, 360).toDouble()),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [mix(pal.accent, const Color(0xFF0B1020), 0.45), const Color(0xFF0B1020)]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
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
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Стих дня'), style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Text(v.text, style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.38, fontWeight: FontWeight.w500, fontFamily: 'serif', shadows: [Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 1))])),
              const SizedBox(height: 14),
              Container(width: 36, height: 2, color: Colors.white70),
              const SizedBox(height: 10),
              Text(selectionLabel([v.ref], full: true), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Expanded(child: _Act(pal: pal, icon: Icons.menu_book_outlined, label: t('Читать'), primary: true, onTap: () => widget.onRead(v.ref))),
              const SizedBox(width: 8),
              Expanded(child: _Act(pal: pal, icon: Icons.image_outlined, label: t('Картинка'), onTap: () => showPage(context, (_) => VerseImageSheet(refs: [v.ref], moduleId: v.module.id)))),
              const SizedBox(width: 8),
              Expanded(child: _Act(pal: pal, icon: Icons.share_outlined, label: t('Поделиться'), onTap: _share)),
            ]),
          ),
          if (_photo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '${t('Фото: {title}', {'title': t('${_photo!['title']}')})}${_photo!['author'] != null ? ' — ${_photo!['author']}' : ''} (${_photo!['license']})',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 10.5),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act({required this.pal, required this.icon, required this.label, required this.onTap, this.primary = false});
  final Palette pal;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? pal.onAccent : pal.text;
    return Material(
      color: primary ? pal.accent : pal.panel.withValues(alpha: 0.86),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 5),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg))),
          ]),
        ),
      ),
    );
  }
}
