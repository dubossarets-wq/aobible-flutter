// Картинка со стихом (VerseImageSheet.jsx): фон (фото в общественном достоянии или спокойный градиент), текст и ссылка.
// Текст двигается одним пальцем, размер — двумя. «Поделиться» отправляет картинку, «Сохранить» кладёт в «Картинки».
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../shell/appearance_sheet.dart' show pickBgImage;
import 'loc.dart';
import 'net_cache.dart';
import 'ui_kit.dart';
import 'verse_text.dart';

class _Gradient {
  const _Gradient(this.id, this.title, this.stops, this.tone);
  final String id, title, tone;
  final List<Color> stops;
}

const _gradients = [
  _Gradient('g-dawn', 'Рассвет', [Color(0xFF3B2A4D), Color(0xFFC0705A), Color(0xFFF1C27D)], 'dark'),
  _Gradient('g-sea', 'Море', [Color(0xFF0F2F45), Color(0xFF1F6D86), Color(0xFF7FB7C4)], 'dark'),
  _Gradient('g-olive', 'Олива', [Color(0xFF2C3523), Color(0xFF5D6B3C), Color(0xFFA3A46B)], 'dark'),
  _Gradient('g-night', 'Ночь', [Color(0xFF0B1020), Color(0xFF1D2440), Color(0xFF3B3F66)], 'dark'),
  _Gradient('g-paper', 'Бумага', [Color(0xFFF6EFE1), Color(0xFFEFE3C8), Color(0xFFE5D3AD)], 'paper'),
  _Gradient('g-stone', 'Камень', [Color(0xFF2B2A28), Color(0xFF4A4741), Color(0xFF6D675C)], 'dark'),
];

const _sizes = {'square': Size(1080, 1080), 'post': Size(1080, 1350), 'story': Size(1080, 1920)};

/// Всё, что нужно, чтобы нарисовать картинку; рисует и предпросмотр, и итоговый файл
class _Art {
  const _Art({required this.img, required this.gradient, required this.photoTone, required this.text, required this.ref, required this.format, required this.baseFs, required this.scale, required this.dx, required this.dy});
  final ui.Image? img;
  final _Gradient gradient;
  final String photoTone;
  final String text, ref, format;
  final double baseFs, scale, dx, dy; // baseFs — размер букв, при котором стих помещается; scale — выбранный пальцами

  Size get size => _sizes[format]!;

  TextPainter _text(double fs, Color color, bool shadow) => TextPainter(
        text: TextSpan(text: '«$text»', style: TextStyle(fontFamily: 'PT Serif', fontFamilyFallback: const ['Georgia', 'serif'], fontSize: fs, height: 1.38, color: color, shadows: shadow ? const [Shadow(color: Color(0x59000000), blurRadius: 12)] : null)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.78);

  void paint(Canvas canvas) {
    final W = size.width, H = size.height;
    final paper = img == null && gradient.tone == 'paper';
    if (img != null) {
      paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, W, H), image: img!, fit: BoxFit.cover);
      final a = photoTone == 'light' ? 0.55 : 0.38;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), [Colors.black.withValues(alpha: a - 0.1), Colors.black.withValues(alpha: a), Colors.black.withValues(alpha: a + 0.12)], [0, 0.5, 1]),
      );
    } else {
      final s = gradient.stops;
      canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(W * 0.4, H), s, [for (var i = 0; i < s.length; i++) i / (s.length - 1)]));
    }
    final color = paper ? const Color(0xFF2D2418) : Colors.white;
    final fs = math.max(14.0, baseFs * scale);
    final tp = _text(fs, color, !paper);
    final refSize = math.max(18.0, fs * 0.6);
    final total = tp.height + refSize * 2.2;
    final cx = W / 2 + dx * W;
    final top = (H - total) / 2 + dy * H;
    tp.paint(canvas, Offset(cx - tp.width / 2, top));
    final lineY = top + tp.height + refSize * 0.5;
    canvas.drawRect(Rect.fromLTWH(cx - 40, lineY, 80, 3), Paint()..color = color.withValues(alpha: 0.75));
    final rp = TextPainter(
      text: TextSpan(text: ref, style: TextStyle(fontFamily: 'PT Sans', fontFamilyFallback: const ['Segoe UI', 'sans-serif'], fontSize: refSize, fontWeight: FontWeight.w700, color: color)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: W * 0.78);
    rp.paint(canvas, Offset(cx - rp.width / 2, lineY + refSize * 0.3));
  }

  /// Размер букв, при котором стих помещается (как в веб-версии: от 74 вниз до 26)
  static double fit(String text, String format) {
    final size = _sizes[format]!;
    final boxH = size.height * (format == 'story' ? 0.55 : 0.62);
    var fs = 74.0;
    for (;;) {
      final tp = TextPainter(
        text: TextSpan(text: '«$text»', style: TextStyle(fontFamily: 'PT Serif', fontFamilyFallback: const ['Georgia', 'serif'], fontSize: fs, height: 1.38)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.78);
      if (tp.height <= boxH || fs <= 26) return fs;
      fs -= 2;
    }
  }
}

class _Painter extends CustomPainter {
  _Painter(this.art);
  final _Art art;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / art.size.width);
    art.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Painter o) => true;
}

class VerseImageSheet extends ConsumerStatefulWidget {
  const VerseImageSheet({super.key, required this.refs, required this.moduleId});
  final List<VerseRef> refs;
  final String moduleId;

  @override
  ConsumerState<VerseImageSheet> createState() => _VerseImageSheetState();
}

class _VerseImageSheetState extends ConsumerState<VerseImageSheet> {
  List<Map<String, dynamic>> _photos = [];
  String? _bgId;
  ui.Image? _img;
  bool _imgFailed = false;
  String _text = '';
  bool _textReady = false;
  String _format = 'post';
  double _scale = 1, _dx = 0, _dy = 0;
  double _baseFs = 74;
  // начало жеста
  double _s0 = 1, _dx0 = 0, _dy0 = 0;
  Offset _f0 = Offset.zero;
  bool _busy = false;
  // привязка к центру: текст рядом с серединой «прилипает» к ней, пока его ведут — видны направляющие
  static const _snap = 0.025;
  bool _snapX = false, _snapY = false, _dragging = false;
  // своё фото фоном (только для этой картинки, никуда не сохраняется)
  Uint8List? _ownBytes;
  ui.Image? _ownImg;

  late final String _label = selectionLabel(widget.refs, full: true);

  @override
  void initState() {
    super.initState();
    final lines = <String>[];
    for (final r in widget.refs) {
      final v = verseText(widget.moduleId, r);
      if (v != null) lines.add(v);
    }
    _text = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    _baseFs = _Art.fit(_text, _format);
    _textReady = true;
    _bgId = _gradients.first.id; // пока не пришёл список фото
    ensureDict();
    siteJson('images/verse-bg/index.json').then((j) {
      if (!mounted) return;
      final list = [for (final x in (j?['images'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      setState(() => _photos = list);
      _pick(list.isNotEmpty ? list.first['id'] as String : _gradients.first.id);
    });
  }

  Map<String, dynamic>? get _photo => _photos.where((p) => p['id'] == _bgId).firstOrNull;
  // фото не загрузилось — тот же текст на спокойном градиенте
  _Gradient get _grad => _gradients.where((g) => g.id == _bgId).firstOrNull ?? _gradients.first;

  Future<void> _pickOwn() async {
    final bytes = await pickBgImage();
    if (bytes == null || !mounted) return;
    ui.Image? im;
    try {
      im = await decodeImageFromList(bytes);
    } catch (_) {}
    if (!mounted || im == null) return;
    setState(() {
      _ownBytes = bytes;
      _ownImg = im;
      _bgId = 'own';
      _img = im;
      _imgFailed = false;
    });
  }

  Future<void> _pick(String id, {bool load = true}) async {
    if (id == 'own') {
      setState(() {
        _bgId = id;
        _img = _ownImg;
        _imgFailed = false;
      });
      return;
    }
    setState(() {
      _bgId = id;
      _img = null;
      _imgFailed = false;
    });
    if (!load) return;
    final p = _photos.where((p) => p['id'] == id).firstOrNull;
    if (p == null) return;
    final bytes = await siteFile('images/verse-bg/${p['file']}');
    ui.Image? im;
    if (bytes != null) {
      try {
        im = await decodeImageFromList(bytes);
      } catch (_) {}
    }
    if (!mounted || _bgId != id) return;
    setState(() {
      _img = im;
      _imgFailed = im == null;
    });
  }

  _Art get _art => _Art(
        img: _img,
        gradient: _grad,
        photoTone: '${_photo?['tone'] ?? 'dark'}',
        text: _text,
        ref: _label,
        format: _format,
        baseFs: _baseFs,
        scale: _scale,
        dx: _dx,
        dy: _dy,
      );

  Future<File> _render() async {
    final art = _art;
    final rec = ui.PictureRecorder();
    art.paint(Canvas(rec));
    final image = await rec.endRecording().toImage(art.size.width.round(), art.size.height.round());
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}${_label.replaceAll(RegExp(r'[:\s]+'), '_')}.png');
    await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return f;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await _render();
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], title: _label));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await _render();
      try {
        final dir = Directory('/storage/emulated/0/Pictures/AO Bible')..createSync(recursive: true);
        await f.copy('${dir.path}${Platform.pathSeparator}${f.uri.pathSegments.last}');
        if (mounted) toast(context, t('Картинка сохранена'));
      } catch (_) {
        // общая папка недоступна — отдаём системному окну, оттуда можно сохранить куда угодно
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], title: _label));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setFormat(String f) => setState(() {
        _format = f;
        _baseFs = _Art.fit(_text, f);
      });

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final size = _sizes[_format]!;
    final photo = _photo;
    final loading = !_textReady || _bgId == null || (photo != null && _img == null && !_imgFailed);
    // .sheet-body: колонка с промежутком 12 между блоками
    const gap = SizedBox(height: 12);
    final s = ref.watch(settingsProvider);
    return AobSheet(
      title: t('Картинка со стихом'),
      subtitle: _label,
      // на широком экране содержимое не шире текста Библии (настройка «Ширина текста»)
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: s.d('textWidth') * s.d('fontSize')),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // .vimg-preview: ширина min(100% − 40, 340) (история — 250), скругление, тень, margin-bottom 12; по бокам — поля
        // 20 внутри окна, чтобы картинка не упиралась в края
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _format == 'story' ? 250 : 340),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: const BoxConstraints(minHeight: 200),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), color: pal.bg, boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 4))]),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: loading
                    ? Center(child: Spinner(size: 24, color: pal.text))
                    : LayoutBuilder(
                        builder: (_, c) => GestureDetector(
                          onScaleStart: (d) {
                            _s0 = _scale;
                            _dx0 = _dx;
                            _dy0 = _dy;
                            _f0 = d.localFocalPoint;
                            setState(() => _dragging = true);
                          },
                          onScaleUpdate: (d) => setState(() {
                            final dx = (_dx0 + (d.localFocalPoint.dx - _f0.dx) / c.maxWidth).clamp(-0.45, 0.45);
                            final dy = (_dy0 + (d.localFocalPoint.dy - _f0.dy) / c.maxHeight).clamp(-0.45, 0.45);
                            final sx = dx.abs() < _snap, sy = dy.abs() < _snap;
                            if ((sx && !_snapX) || (sy && !_snapY)) HapticFeedback.selectionClick(); // «щелчок» при прилипании
                            _snapX = sx;
                            _snapY = sy;
                            _dx = sx ? 0 : dx;
                            _dy = sy ? 0 : dy;
                            if (d.pointerCount > 1) _scale = (_s0 * d.scale).clamp(0.4, 2.2);
                          }),
                          onScaleEnd: (_) => setState(() => _dragging = false),
                          child: Stack(fit: StackFit.expand, children: [
                            CustomPaint(painter: _Painter(_art), size: Size.infinite),
                            // направляющие по центру — пока текст ведут и он прилип к середине
                            IgnorePointer(
                              child: Stack(children: [
                                AnimatedOpacity(
                                  opacity: _dragging && _snapX ? 1 : 0,
                                  duration: const Duration(milliseconds: 140),
                                  child: Center(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.7))),
                                ),
                                AnimatedOpacity(
                                  opacity: _dragging && _snapY ? 1 : 0,
                                  duration: const Duration(milliseconds: 140),
                                  child: Center(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.7))),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
              ),
            ),
          ),
        ),
        ),
        // .vimg-bgs: полоса фонов 52×64, промежуток 8; от края до края, у краёв, за которыми есть ещё, — затухание
        FadeRow(
          bleed: true,
          gap: 8,
          padding: const EdgeInsets.symmetric(vertical: 2),
          children: [
            if (_ownImg != null) _Bg(pal: pal, on: _bgId == 'own', onTap: () => _pick('own'), tip: t('Своё фото'), child: Image.memory(_ownBytes!, fit: BoxFit.cover)),
            for (final p in _photos) _Bg(pal: pal, on: _bgId == p['id'], onTap: () => _pick(p['id'] as String), tip: t('${p['title']}'), child: SiteImage('images/verse-bg/${p['thumb']}')),
            for (final g in _gradients) _Bg(pal: pal, on: _bgId == g.id, onTap: () => _pick(g.id, load: false), tip: t(g.title), gradient: g.stops),
          ],
        ),
        const SizedBox(height: 10),
        // своё фото — сразу под всеми фонами
        AobButton(wide: true, icon: LucideIcons.imagePlus, label: t('Своё фото'), onTap: _pickOwn),
        gap,
        Segmented<String>(
          value: _format,
          onChanged: _setFormat,
          options: [
            ('square', t('Квадрат')),
            ('post', t('Пост')),
            ('story', tx('История@@формат картинки: вертикальная, для «историй» в соцсетях')),
          ],
        ),
        gap,
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t('Двигайте текст пальцем, размер — двумя пальцами.'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 13.4))),
        // .vimg-size: подпись, «как было», минус и плюс; отступы 10 сверху и снизу
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(child: Text(t('Размер текста'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text))),
            if (_scale != 1 || _dx != 0 || _dy != 0)
              GestureDetector(
                onTap: () => setState(() => (_scale = 1, _dx = 0, _dy = 0)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t('как было'), style: TextStyle(fontSize: 15, color: pal.accent, decoration: TextDecoration.underline, decorationColor: pal.accent))),
              ),
            IconBtn(icon: LucideIcons.minus, size: 18, tooltip: t('Мельче'), onTap: () => setState(() => _scale = math.max(0.4, double.parse((_scale - 0.1).toStringAsFixed(2))))),
            const SizedBox(width: 6),
            IconBtn(icon: LucideIcons.plus, size: 18, tooltip: t('Крупнее'), onTap: () => setState(() => _scale = math.min(2.2, double.parse((_scale + 0.1).toStringAsFixed(2))))),
          ]),
        ),
        // .pref-btns
        Row(children: [
          Expanded(child: AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.share2, label: t('Поделиться'), onTap: loading || _busy ? null : _share)),
          const SizedBox(width: 8),
          Expanded(child: AobButton(wide: true, icon: LucideIcons.download, label: t('Сохранить'), onTap: loading || _busy ? null : _save)),
        ]),
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(top: 22), // margin-top 10 + промежуток 12
            child: Text('${t('Фото: {title}', {'title': t('${photo['title']}')})}${photo['author'] != null ? ' — ${photo['author']}' : ''} (${photo['license']})', style: TextStyle(color: pal.muted, fontSize: 11.8)),
          ),
          ]),
        ),
      ),
    );
  }
}

/// .vimg-bg: 52×64, скругление 10, без обводки; выбранный — рамка цвета акцента поверх края, проявляется плавно
class _Bg extends StatelessWidget {
  const _Bg({required this.pal, required this.on, required this.onTap, required this.tip, this.child, this.gradient});
  final Palette pal;
  final bool on;
  final VoidCallback onTap;
  final String tip;
  final Widget? child;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.fastOutSlowIn,
            width: 52,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: gradient == null ? null : LinearGradient(begin: const Alignment(-0.34, -1), end: const Alignment(0.34, 1), colors: gradient!),
            ),
            foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? pal.accent : pal.accent.withValues(alpha: 0), width: 2.5)),
            child: child,
          ),
        ),
      );
}
