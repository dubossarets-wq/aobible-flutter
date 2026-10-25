// Карта одного места (образец — MapPane.jsx веб-версии): MapLibre, подложка OpenFreeMap, по умолчанию — спутник
// Sentinel-2 cloudless 2016 от EOX (CC BY 4.0; свои снимки до приближения 13, дальше растягиваются).
// Кнопки: «Только карта и точка», «Спутник / Обычная карта», «Закрыть карту»; подпись источников — сверху и всегда видна;
// поверх карты — карточка места (сворачивается) (название, тип, достоверность, отождествление, описание, стихи).
// Виджет не знает, где лежит: сейчас его открывает отдельный экран (openPlaceMap), позже — вторая половина главного экрана.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
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

/// Сама карта: MapLibre. Подменяется в тестах заглушкой (платформенного окна карты в тестах нет)
Widget Function(LatLng target, double zoom, void Function(MapLibreMapController) onCreated, VoidCallback onStyle) mapViewBuilder = (target, zoom, onCreated, onStyle) => MapLibreMap(
      styleString: mapStyle,
      initialCameraPosition: CameraPosition(target: target, zoom: zoom),
      onMapCreated: onCreated,
      onStyleLoadedCallback: onStyle,
      compassEnabled: false,
      tiltGesturesEnabled: false,
      logoEnabled: false,
      scaleControlEnabled: true,
    );

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
  final _cardKey = GlobalKey();
  double _areaW = 0;
  String _fitSig = '';
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
    if (!mounted) return;
    final up = CameraUpdate.newLatLngZoom(at, zoomFor(widget.place.type));
    if (animate) {
      await c.animateCamera(up, duration: const Duration(milliseconds: 900));
    } else {
      await c.moveCamera(up);
    }
    await _fit();
  }

  // Точка не должна прятаться под карточкой: сдвигаем центр на свободную часть (easeTo с padding в вебе)
  Future<void> _fit() async {
    final c = _c;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (c == null || !_ready || box == null || !box.hasSize) return;
    final side = _areaW >= 640;
    await c.animateCamera(CameraUpdate.newLatLng(LatLng(widget.place.lat, widget.place.lng)), duration: const Duration(milliseconds: 1));
    if (!mounted) return;
    final dx = side ? -(box.size.width + 20) / 2 : 0.0;
    final dy = side ? 0.0 : (box.size.height + 20) / 2;
    await c.animateCamera(CameraUpdate.scrollBy(dx, dy), duration: const Duration(milliseconds: 300));
  }

  Future<void> _onStyle() async {
    final c = _c;
    if (c == null) return;
    final pal = ref.read(settingsProvider).palette; // до первого await: после него виджета уже может не быть
    final ids = (await c.getLayerIds()).cast<String>();
    if (!mounted) return;
    final first = ids.length > 1 ? ids[1] : null;
    await c.addSource('satellite', const RasterSourceProperties(tiles: [satelliteTiles], tileSize: 256, maxzoom: 13, attribution: satelliteCredit));
    await c.addRasterLayer('satellite', 'satellite', const RasterLayerProperties(), belowLayerId: first);
    await c.addGeoJsonSource('place-pt', _point());
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
    // все вызовы уходят сразу (порядок на канале сохраняется) — а не по одному с ожиданием ответа на каждый слой
    await Future.wait([
      c.setLayerVisibility('satellite', _sat),
      for (final id in _styleLayers) c.setLayerVisibility(id, _clean ? (!_sat && isFillLayer(id)) : !(_sat && isFillLayer(id))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final place = widget.place;
    final size = MediaQuery.sizeOf(context);
    // На низкой половине экрана (телефон) карточка сначала свёрнута — видна карта
    final cardOpen = _cardOpen ?? (size.height > 700 && size.width >= 720);
    final fg = pal.barText;
    // .map-pane .toolbar: шапка панели (высота barHeight, цвет bar, тень-линия), кнопки 40×40
    return Column(children: [
      Container(
        height: ref.watch(settingsProvider.select((s) => s.d('barHeight'))),
        decoration: BoxDecoration(color: pal.bar, boxShadow: [BoxShadow(color: mix(pal.line, 0.7, Colors.black26), offset: const Offset(0, 1))]),
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Row(children: [
          // .tb-place: значок и название места, 1.08rem, жирность 600
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Icon(LucideIcons.mapPin, size: 18, color: fg),
                const SizedBox(width: 8),
                Expanded(child: Text(place.name, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.28, color: fg))),
              ]),
            ),
          ),
          _BarIcon(
            tooltip: _clean ? t('Показать все наложения') : t('Только карта и точка'),
            icon: LucideIcons.layers,
            size: 21,
            color: _clean ? barOnColor(pal) : fg,
            onTap: !_ready
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
          _BarIcon(
            tooltip: _sat ? t('Обычная карта') : t('Спутник'),
            icon: _sat ? LucideIcons.map : LucideIcons.satellite,
            size: 21,
            color: _sat ? barOnColor(pal) : fg,
            onTap: !_ready
                ? null
                : () {
                    setState(() => _sat = !_sat);
                    _applyLayers();
                  },
          ),
          _BarIcon(tooltip: t('Закрыть карту'), icon: LucideIcons.x, size: 22, color: fg, onTap: widget.onClose),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          // @container (min-width: 640px): карточка слева шириной 380
          final side = box.maxWidth >= 640;
          _areaW = box.maxWidth;
          final sig = '$_ready|$cardOpen|${!_clean || cardOpen}|$side';
          if (sig != _fitSig) {
            _fitSig = sig;
            WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _fit() : null);
          }
          return Stack(children: [
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFFDFE6E9),
                child: mapViewBuilder(LatLng(place.lat, place.lng), zoomFor(place.type), (c) => _c = c, _onStyle),
              ),
            ),
            // Подпись источников — сверху и всегда видна (условие CC BY и ODbL); внизу её закрывали бы карточка и меню
            Positioned(left: 6, top: 6, right: 64, child: Align(alignment: Alignment.topLeft, child: _Credits(sat: _sat))),
            // NavigationControl (maplibregl-ctrl-group): кнопки масштаба справа вверху, в чистом режиме скрыты
            if (!_clean) Positioned(right: 10, top: 10, child: _ZoomControl(onZoom: (d) => _c?.animateCamera(d > 0 ? CameraUpdate.zoomIn() : CameraUpdate.zoomOut()))),
            if (!_ready) Positioned(left: 12, right: 12, top: 12, child: _Status(pal: pal, text: t('Загружаю карту…'))),
            if (!_clean || cardOpen)
              Positioned(
                left: 10,
                right: side ? null : 10,
                width: side ? 380 : null,
                bottom: 10 + MediaQuery.paddingOf(context).bottom,
                child: KeyedSubtree(
                  key: _cardKey,
                  child: _PlaceCard(place: place, pal: pal, open: cardOpen, maxHeight: box.maxHeight * 0.55, onToggle: () => setState(() => _cardOpen = !cardOpen), onOpenVerse: widget.onOpenVerse),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }
}

/// .toolbar .tb-icon: круглая кнопка 40×40 в шапке; недоступная — бледная
class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.tooltip, required this.icon, required this.size, required this.color, required this.onTap});
  final String tooltip;
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: Tooltip(message: tooltip, child: Icon(icon, size: size, color: color))),
          ),
        ),
      );
}

/// .map-status: плашка «Загружаю карту…» сверху карты
class _Status extends StatefulWidget {
  const _Status({required this.pal, required this.text});
  final Palette pal;
  final String text;
  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(kRadius), boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 4))]),
      child: Row(children: [
        RotationTransition(turns: _spin, child: Icon(LucideIcons.loaderCircle, size: 20, color: pal.text)),
        const SizedBox(width: 8),
        Flexible(child: Text(widget.text, style: TextStyle(fontSize: 14.4, color: pal.text))),
      ]),
    );
  }
}

/// Подпись источников (maplibregl-ctrl-attrib): белая плашка 86%, скругление 6, строка 1.35
class _Credits extends StatelessWidget {
  const _Credits({required this.sat});
  final bool sat;
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, height: 1.35, color: Color(0xBF000000));
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(color: const Color(0xDBFFFFFF), borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(sat ? '$satelliteCredit · $osmCredit' : osmCredit, style: style),
      ),
    );
  }
}

/// .place-card: плавающая карточка поверх карты (панель, скругление, тень), шапка сворачивает и разворачивает
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.pal, required this.open, required this.maxHeight, required this.onToggle, required this.onOpenVerse});
  final Place place;
  final Palette pal;
  final bool open;
  final double maxHeight;
  final VoidCallback onToggle;
  final void Function(VerseRef) onOpenVerse;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: pal.muted);
    final refs = place.verses;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 28, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: place.name, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                      if (place.type.isNotEmpty) TextSpan(text: ' · ${place.type}', style: muted),
                    ]),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(fontSize: 15.68),
                  ),
                ),
                const SizedBox(width: 8),
                // Стрелка вниз у раскрытой, вверх у свёрнутой (.place-chev)
                AnimatedRotation(turns: open ? 0 : 0.5, duration: const Duration(milliseconds: 200), child: Icon(LucideIcons.chevronDown, size: 18, color: pal.muted)),
              ]),
            ),
          ),
        ),
        if (open)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 14.4, height: 1.45, color: pal.text),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (place.modern.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${t('Сейчас:')} ', style: muted),
                        TextSpan(text: place.modern),
                      ])),
                    ),
                  if (place.confidence != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Достоверность: {pct}%', {'pct': '${place.confidence}'}), style: TextStyle(fontSize: 13.12, height: 1.45, color: pal.muted)),
                        const SizedBox(height: 4),
                        // .conf-bar: 5 px, скругление 3, заливка акцентом
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            height: 5,
                            color: pal.muted.withValues(alpha: 0.2),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(widthFactor: place.confidence!.clamp(0, 100) / 100, child: ColoredBox(color: pal.accent)),
                          ),
                        ),
                      ]),
                    ),
                  if (place.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(place.description)),
                  if (refs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        for (final r in refs.take(40)) AobChip(label: Books.instance.formatRef(r.book, r.chapter, r.verse), onTap: () => onOpenVerse(r)),
                        if (refs.length > 40) Text(t('и ещё {n}', {'n': '${refs.length - 40}'}), style: TextStyle(fontSize: 12.8, color: pal.muted)),
                      ]),
                    ),
                  // .source-note: линия сверху, 0.8rem, ссылка цвета акцента со значком
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      InkWell(
                        onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/@${place.lat},${place.lng},2000m/data=!3m1!1e3'), mode: LaunchMode.externalApplication),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(t('Спутник Google'), style: TextStyle(color: pal.accent, fontSize: 12.8)),
                          const SizedBox(width: 3),
                          Icon(LucideIcons.externalLink, size: 12, color: pal.accent),
                        ]),
                      ),
                      Text(' · ${place.license.isEmpty ? 'OpenBible.info, CC BY 4.0' : place.license}', style: TextStyle(color: pal.muted, fontSize: 12.8)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// .maplibregl-ctrl-group: белая группа из двух кнопок 29×29, скругление 4, тонкая тёмная обводка
class _ZoomControl extends StatelessWidget {
  const _ZoomControl({required this.onZoom});
  final void Function(int dir) onZoom;
  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, int d, String tip) => SizedBox(
          width: 29,
          height: 29,
          child: InkWell(onTap: () => onZoom(d), child: Tooltip(message: tip, child: Icon(i, size: 18, color: const Color(0xFF333333)))),
        );
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Color(0x1A000000), spreadRadius: 2)]),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        btn(LucideIcons.plus, 1, t('Увеличить')),
        Container(width: 29, height: 1, color: const Color(0xFFDDDDDD)),
        btn(LucideIcons.minus, -1, t('Уменьшить')),
      ]),
    );
  }
}
