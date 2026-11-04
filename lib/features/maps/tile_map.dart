// Карта на компьютере (Windows, macOS, Linux): у MapLibre там нет платформенного окна карты — здесь своя простая
// карта из растровых тайлов спутника EOX (те же снимки, что на телефоне и в веб-версии) с точкой места.
// Перетаскивание мышью или пальцем, колесо и «+ −» — масштаб; снимки — до приближения 13, дальше растягиваются.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TileMap extends StatefulWidget {
  const TileMap({super.key, required this.lat, required this.lng, required this.zoom, required this.tiles, required this.pointColor, this.maxTileZoom = 13});
  final double lat, lng, zoom;
  final String tiles; // адрес тайла с {z}, {x}, {y}
  final Color pointColor;
  final int maxTileZoom;

  @override
  State<TileMap> createState() => TileMapState();
}

class TileMapState extends State<TileMap> {
  static const _tile = 256.0;
  late double _zoom = widget.zoom;
  late Offset _center = _world(widget.lat, widget.lng, 0); // мировые координаты на масштабе 0 (0…256)
  double? _startZoom;
  Offset? _startFocal;
  Offset? _startCenter;

  static Offset _world(double lat, double lng, double z) {
    final s = _tile * math.pow(2, z);
    final sin = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return Offset((lng + 180) / 360 * s, (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * s);
  }

  @override
  void didUpdateWidget(TileMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // другое место — к нему
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      setState(() {
        _center = _world(widget.lat, widget.lng, 0);
        _zoom = widget.zoom;
      });
    }
  }

  /// «+» / «−»: на один шаг масштаба
  void zoomBy(double d) => setState(() => _zoom = (_zoom + d).clamp(2.0, 17.0));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final tz = _zoom.floor().clamp(0, widget.maxTileZoom);
      final k = math.pow(2, _zoom).toDouble(); // мир 0…256 → пиксели экрана
      final tileSize = _tile * math.pow(2, _zoom - tz); // размер тайла уровня tz на экране
      final c = _center * k; // центр в пикселях текущего масштаба
      final topLeft = c - Offset(size.width / 2, size.height / 2);
      final n = 1 << tz;
      final x0 = (topLeft.dx / tileSize).floor(), x1 = ((topLeft.dx + size.width) / tileSize).floor();
      final y0 = math.max(0, (topLeft.dy / tileSize).floor()), y1 = math.min(n - 1, ((topLeft.dy + size.height) / tileSize).floor());
      final tiles = <Widget>[
        for (var y = y0; y <= y1; y++)
          for (var x = x0; x <= x1; x++)
            Positioned(
              left: x * tileSize - topLeft.dx,
              top: y * tileSize - topLeft.dy,
              width: tileSize + 0.5, // без щелей между тайлами при дробном размере
              height: tileSize + 0.5,
              child: Image.network(
                widget.tiles.replaceAll('{z}', '$tz').replaceAll('{x}', '${((x % n) + n) % n}').replaceAll('{y}', '$y'),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
      ];
      final pt = _world(widget.lat, widget.lng, 0) * k - topLeft;
      return Listener(
        // колесо мыши — масштаб вокруг курсора
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          final d = e.scrollDelta.dy > 0 ? -0.5 : 0.5;
          final nz = (_zoom + d).clamp(2.0, 17.0);
          final f = e.localPosition - Offset(size.width / 2, size.height / 2);
          setState(() {
            _center = _center + f / k - f / math.pow(2, nz).toDouble();
            _zoom = nz;
          });
        },
        child: GestureDetector(
          onScaleStart: (d) {
            _startZoom = _zoom;
            _startFocal = d.localFocalPoint;
            _startCenter = _center;
          },
          onScaleUpdate: (d) {
            final nz = (_startZoom! + math.log(d.scale) / math.ln2).clamp(2.0, 17.0);
            final nk = math.pow(2, nz).toDouble(), sk = math.pow(2, _startZoom!).toDouble();
            final half = Offset(size.width / 2, size.height / 2);
            // точка под пальцами в начале жеста остаётся под пальцами
            final anchor = _startCenter! + (_startFocal! - half) / sk;
            setState(() {
              _zoom = nz;
              _center = anchor - (d.localFocalPoint - half) / nk;
            });
          },
          child: ClipRect(
            child: Stack(children: [
              ...tiles,
              // точка места (как circle-слой на телефоне): радиус 9, белая обводка 3
              Positioned(
                left: pt.dx - 12,
                top: pt.dy - 12,
                width: 24,
                height: 24,
                child: DecoratedBox(decoration: BoxDecoration(color: widget.pointColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
