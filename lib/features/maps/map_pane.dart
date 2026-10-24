// Карта одного места (образец — MapPane.jsx веб-версии): MapLibre, подложка OpenFreeMap, по умолчанию — спутник
// Sentinel-2 cloudless 2016 от EOX (CC BY 4.0; свои снимки до приближения 13, дальше растягиваются).
// Кнопки: «Только карта и точка», «Спутник / Обычная карта», «Закрыть карту»; подпись источников — сверху и всегда видна;
// под картой — карточка места (название, тип, достоверность, отождествление, описание, стихи).
// Виджет не знает, где лежит: сейчас его открывает отдельный экран (openPlaceMap), позже — вторая половина главного экрана.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'places_data.dart';

const mapStyle = 'https://tiles.openfreemap.org/styles/liberty';
const satelliteTiles = 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg';
const satelliteCredit = 'Sentinel-2 cloudless — https://s2maps.eu by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016)';
const osmCredit = 'OpenFreeMap © OpenMapTiles Data from OpenStreetMap';

/// Масштаб по типу места: область видна целиком, город — с окрестностями
double zoomFor(String type) => RegExp('область|район|народ').hasMatch(type)
    ? 6.5
    : RegExp('хребет|долина|река|водоём|пустын').hasMatch(type)
        ? 8.5
        : 11;

// Слои подложки, которые закрывают снимки (сплошные заливки) и слои чистого режима «суша и вода»
final _fillLike = RegExp(r'^(background|park|water|landcover|landuse)(_|$)');
final _notFill = RegExp('name|label|shadow|building|aeroway|boundary');
bool isFillLayer(String id) => _fillLike.hasMatch(id) && !_notFill.hasMatch(id);

class MapPaneView extends ConsumerStatefulWidget {
  const MapPaneView({super.key, required this.place, required this.onClose, required this.onOpenVerse});
  final Place place;
  final VoidCallback onClose;
  final void Function(VerseRef ref) onOpenVerse;

  @override
  ConsumerState<MapPaneView> createState() => _MapPaneViewState();
}

class _MapPaneViewState extends ConsumerState<MapPaneView> {
  MapLibreMapController? _c;
  bool _ready = false;
  bool _sat = true; // по умолчанию — спутник
  bool _clean = false; // только подложка и точка
  bool? _cardOpen;
  List<String> _styleLayers = const [];

  @override
  void didUpdateWidget(MapPaneView old) {
    super.didUpdateWidget(old);
    if (old.place.id != widget.place.id && _ready) _showPlace(animate: true);
  }

  Map<String, dynamic> _point() => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [widget.place.lng, widget.place.lat]},
            'properties': <String, dynamic>{},
          },
        ],
      };

  Future<void> _showPlace({bool animate = false}) async {
    final c = _c;
    if (c == null) return;
    final at = LatLng(widget.place.lat, widget.place.lng);
    await c.setGeoJsonSource('place-pt', _point());
    final up = CameraUpdate.newLatLngZoom(at, zoomFor(widget.place.type));
    if (animate) {
      await c.animateCamera(up, duration: const Duration(milliseconds: 900));
    } else {
      await c.moveCamera(up);
    }
  }

  Future<void> _onStyle() async {
    final c = _c;
    if (c == null) return;
    final ids = (await c.getLayerIds()).cast<String>();
    final first = ids.length > 1 ? ids[1] : null;
    await c.addSource('satellite', const RasterSourceProperties(tiles: [satelliteTiles], tileSize: 256, maxzoom: 13, attribution: satelliteCredit));
    await c.addRasterLayer('satellite', 'satellite', const RasterLayerProperties(), belowLayerId: first);
    await c.addGeoJsonSource('place-pt', _point());
    final pal = ref.read(settingsProvider).palette;
    await c.addCircleLayer(
      'place-pt',
      'place-pt',
      CircleLayerProperties(circleRadius: 9, circleColor: _hex(pal.dark ? const Color(0xFFD9A35C) : const Color(0xFFB4451F)), circleStrokeColor: '#ffffff', circleStrokeWidth: 3),
    );
    _styleLayers = ids;
    if (!mounted) return;
    setState(() => _ready = true);
    await _applyLayers();
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // Спутник и «чистый» режим: на спутнике подложку-заливки прячем (иначе они закрывают снимки);
  // в чистом режиме на спутнике — только снимки, на обычной карте — только фон, суша и вода без подписей и линий
  Future<void> _applyLayers() async {
    final c = _c;
    if (c == null || !_ready) return;
    await c.setLayerVisibility('satellite', _sat);
    for (final id in _styleLayers) {
      final keep = _clean ? (!_sat && isFillLayer(id)) : !(_sat && isFillLayer(id));
      await c.setLayerVisibility(id, keep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final place = widget.place;
    final size = MediaQuery.sizeOf(context);
    // На низкой половине экрана (телефон) карточка сначала свёрнута — видна карта
    final cardOpen = _cardOpen ?? (size.height > 700 && size.width >= 720);
    return Column(children: [
      Container(
        height: 54,
        color: pal.bar,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Icon(Icons.place_outlined, size: 20, color: pal.barText),
          const SizedBox(width: 6),
          Expanded(child: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: pal.barText))),
          IconButton(
            tooltip: _clean ? t('Показать все наложения') : t('Только карта и точка'),
            icon: Icon(Icons.layers_outlined, color: _clean ? pal.accent : pal.barText),
            onPressed: !_ready
                ? null
                : () {
                    // Включая «только карту», сворачиваем карточку до строки с названием
                    setState(() {
                      if (!_clean) _cardOpen = false;
                      _clean = !_clean;
                    });
                    _applyLayers();
                  },
          ),
          IconButton(
            tooltip: _sat ? t('Обычная карта') : t('Спутник'),
            icon: Icon(_sat ? Icons.map_outlined : Icons.satellite_alt_outlined, color: pal.barText),
            onPressed: !_ready
                ? null
                : () {
                    setState(() => _sat = !_sat);
                    _applyLayers();
                  },
          ),
          IconButton(tooltip: t('Закрыть карту'), icon: Icon(Icons.close, color: pal.barText), onPressed: widget.onClose),
        ]),
      ),
      Expanded(
        child: Stack(children: [
          MapLibreMap(
            styleString: mapStyle,
            initialCameraPosition: CameraPosition(target: LatLng(place.lat, place.lng), zoom: zoomFor(place.type)),
            onMapCreated: (c) => _c = c,
            onStyleLoadedCallback: _onStyle,
            compassEnabled: false,
            tiltGesturesEnabled: false,
            logoEnabled: false,
            scaleControlEnabled: true,
          ),
          // Подпись источников — сверху и всегда видна (условие CC BY и ODbL); внизу её закрывали бы карточка и меню
          Positioned(left: 0, right: 0, top: 0, child: _Credits(sat: _sat)),
          if (!_ready) Center(child: _Status(pal: pal, text: t('Загружаю карту…'))),
        ]),
      ),
      if (!_clean || cardOpen) _PlaceCard(place: place, pal: pal, open: cardOpen, onToggle: () => setState(() => _cardOpen = !cardOpen), onOpenVerse: widget.onOpenVerse),
    ]);
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.pal, required this.text});
  final Palette pal;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: pal.text)),
        ]),
      );
}

class _Credits extends StatelessWidget {
  const _Credits({required this.sat});
  final bool sat;
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10.5, height: 1.25, color: Color(0xFF222222));
    return IgnorePointer(
      child: Container(
        color: const Color(0xCCFFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(sat ? '$satelliteCredit · $osmCredit' : osmCredit, style: style),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.pal, required this.open, required this.onToggle, required this.onOpenVerse});
  final Place place;
  final Palette pal;
  final bool open;
  final VoidCallback onToggle;
  final void Function(VerseRef) onOpenVerse;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: pal.muted, fontSize: 14);
    final refs = place.verses;
    return Container(
      color: pal.panel,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(height: 1, color: pal.line),
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: place.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: pal.text)),
                  if (place.type.isNotEmpty) TextSpan(text: ' · ${place.type}', style: muted),
                ])),
              ),
              Icon(open ? Icons.expand_more : Icons.expand_less, color: pal.muted),
            ]),
          ),
        ),
        if (open)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (place.modern.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${t('Сейчас:')} ', style: muted),
                      TextSpan(text: place.modern, style: TextStyle(color: pal.text, fontSize: 15)),
                    ])),
                  ),
                if (place.confidence != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Text(t('Достоверность: {pct}%', {'pct': '${place.confidence}'}), style: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: place.confidence!.clamp(0, 100) / 100, minHeight: 6, color: pal.accent, backgroundColor: pal.line),
                        ),
                      ),
                    ]),
                  ),
                if (place.description.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(place.description, style: TextStyle(color: pal.text, fontSize: 15, height: 1.4))),
                if (refs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      for (final r in refs.take(40))
                        ActionChip(
                          label: Text(Books.instance.formatRef(r.book, r.chapter, r.verse)),
                          backgroundColor: pal.bg,
                          side: BorderSide(color: pal.line),
                          labelStyle: TextStyle(color: pal.text),
                          onPressed: () => onOpenVerse(r),
                        ),
                      if (refs.length > 40) Text(t('и ещё {n}', {'n': '${refs.length - 40}'}), style: muted),
                    ]),
                  ),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/@${place.lat},${place.lng},2000m/data=!3m1!1e3'), mode: LaunchMode.externalApplication),
                    child: Text('${t('Спутник Google')} ↗', style: TextStyle(color: pal.accent, fontSize: 13, decoration: TextDecoration.underline)),
                  ),
                  Text(' · ${place.license.isEmpty ? 'OpenBible.info, CC BY 4.0' : place.license}', style: TextStyle(color: pal.muted, fontSize: 13)),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
