// «Карты» в меню «Ещё» (образец — MapsSheet.jsx): поиск места по названию и библейские карты (модуль bible-maps) с увеличением.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/net.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'map_screen.dart';
import 'places_data.dart';

/// Одна библейская карта из модуля (картинка лежит на сайте, путь относительный)
class BibleMap {
  BibleMap(this.id, this.title, this.description, this.image, this.refs, this.moduleName);
  final String id, title, description, image, moduleName;
  final List<String> refs;
}

/// Карты всех установленных модулей типа maps (кроме таблиц мест — их читает PlaceStore)
List<BibleMap> installedMaps() {
  final out = <BibleMap>[];
  for (final m in ModuleStore.instance.installed.where((m) => m.type == 'maps')) {
    try {
      final rows = ModuleStore.instance.db(m.id).select('SELECT json FROM payload');
      if (rows.isEmpty) continue;
      final j = jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
      for (final x in (j['maps'] as List? ?? const []).cast<Map>()) {
        out.add(BibleMap(x['id'] as String, x['title'] as String? ?? '', x['description'] as String? ?? '', x['image'] as String? ?? '',
            [for (final r in (x['refs'] as List? ?? const [])) r as String], m.name));
      }
    } catch (_) {
      // у модуля нет таблицы payload (это «Места») — пропускаем
    }
  }
  return out;
}

final _images = <String, Future<Uint8List>>{};
Future<Uint8List> _image(String path) => _images.putIfAbsent(path, () => download(path).catchError((e) {
      _images.remove(path);
      throw e as Object;
    }));

void openMapsSheet(BuildContext context, WidgetRef ref, int pane) {
  showAobSheet(context, builder: (_) => _MapsSheet(pane: pane, outer: context), tab: 'more');
}

class _MapsSheet extends ConsumerStatefulWidget {
  const _MapsSheet({required this.pane, required this.outer});
  final int pane;
  final BuildContext outer; // контекст экрана под окном — для открытия библиотеки
  @override
  ConsumerState<_MapsSheet> createState() => _MapsSheetState();
}

class _MapsSheetState extends ConsumerState<_MapsSheet> {
  final _q = TextEditingController();
  final _tc = TransformationController();
  late final List<BibleMap> _maps = installedMaps();
  late final int _placeCount = PlaceStore.count;
  BibleMap? _open;

  @override
  void dispose() {
    _q.dispose();
    _tc.dispose();
    super.dispose();
  }

  String? _foundFor;
  List<Place> _foundList = const [];
  List<Place> _found() {
    if (_q.text != _foundFor) {
      _foundFor = _q.text;
      _foundList = PlaceStore.search(_foundFor!);
    }
    return _foundList;
  }


  void _goVerse(String osis) {
    final v = parseOsis(osis);
    if (v == null) return;
    Navigator.pop(context);
    ref.read(panesProvider.notifier).navigate(widget.pane, v);
  }

  // Увеличение — от 1× до 6×, шаг ×1,5 (как в веб-версии)
  void _zoom(double k) {
    final s = (_tc.value.getMaxScaleOnAxis() * k).clamp(1.0, 6.0);
    _tc.value = Matrix4.diagonal3Values(s, s, 1);
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final open = _open;
    return AobSheet(
      title: open?.title ?? t('Карты'),
      subtitle: open?.moduleName,
      scroll: false,
      onBack: open == null
          ? null
          : () => setState(() {
                _open = null;
                _tc.value = Matrix4.identity();
              }),
      actions: [
        if (open != null) ...[
          IconBtn(icon: LucideIcons.zoomOut, size: 20, tooltip: t('Уменьшить'), onTap: () => _zoom(1 / 1.5)),
          IconBtn(icon: LucideIcons.zoomIn, size: 20, tooltip: t('Увеличить'), onTap: () => _zoom(1.5)),
        ],
      ],
      child: open != null ? _Viewer(map: open, pal: pal, controller: _tc, onVerse: _goVerse) : _list(pal),
    );
  }

  Widget _list(Palette pal) {
    final found = _found(); // запрос к базе — только когда изменилась строка поиска, а не на каждую перестройку
    final query = _q.text.trim();
    return Builder(builder: (bc) => CustomScrollView(slivers: [
      if (_placeCount > 0)
        SliverToBoxAdapter(
          // .nav-group: заголовок, поле поиска, найденные места (промежутки 8)
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GroupTitle('${t('Места')} · $_placeCount'),
            const SizedBox(height: 2),
            AobInput(controller: _q, hint: t('Найти место: Хеврон, Вифлеем…'), onChanged: (_) => setState(() {})),
            for (final p in found)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  openPlaceMap(context, p);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(LucideIcons.mapPin, size: 14, color: pal.accent),
                      const SizedBox(width: 6),
                      Flexible(child: Text(p.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text))),
                    ]),
                    const SizedBox(height: 3),
                    Text([p.type, p.modern].where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.08, height: 1.4, color: pal.muted)),
                  ]),
                ),
              ),
            if (query.length >= 2 && found.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('Ничего не найдено.'), style: TextStyle(fontSize: 13.12, height: 1.4, color: pal.muted))),
            const SizedBox(height: 14),
          ]),
        ),
      if (_maps.isEmpty && _placeCount == 0)
        SliverToBoxAdapter(
          // .empty: значок 28, заголовок, подсказка
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
            child: Column(children: [
              Icon(LucideIcons.map, size: 28, color: pal.muted),
              const SizedBox(height: 8),
              Text(t('Карты не установлены'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              const SizedBox(height: 8),
              Text(t('Установите карты из каталога.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, height: 1.45, color: pal.muted)),
              if (Hub.openLibrary != null)
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Hub.openLibrary!(widget.outer, ref, widget.pane);
                  },
                  child: Text(t('Открыть библиотеку'), style: TextStyle(fontSize: 14.4, color: pal.accent, decoration: TextDecoration.underline)),
                ),
            ]),
          ),
        ),
      if (_maps.isNotEmpty)
        // .map-list: сетка auto-fill от 220 px, промежуток 10; плитка — картинка 4:3 и подпись
        SliverLayoutBuilder(builder: (context, c) {
          final cols = ((c.crossAxisExtent + 10) / 230).floor().clamp(1, 6);
          final w = (c.crossAxisExtent - 10 * (cols - 1)) / cols;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: w * 0.75 + 58),
            itemCount: _maps.length,
            itemBuilder: (_, i) => _MapTile(map: _maps[i], pal: pal, onTap: () => setState(() => _open = _maps[i])),
          );
        }),
      SliverToBoxAdapter(child: SizedBox(height: 8 + MediaQuery.paddingOf(bc).bottom)),
    ]));
  }
}

/// .map-row: рамка, скругление, картинка 4:3 сверху, название и описание в одну строку
class _MapTile extends StatelessWidget {
  const _MapTile({required this.map, required this.pal, required this.onTap});
  final BibleMap map;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: pal.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: BorderSide(color: pal.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SizedBox(width: double.infinity, child: _Thumb(path: map.image, pal: pal))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(map.title, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                const SizedBox(height: 2),
                Text(map.description.isEmpty ? map.moduleName : map.description, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 13.6, color: pal.muted)),
              ]),
            ),
          ]),
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.pal});
  final String path;
  final Palette pal;
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _image(path),
        builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover, cacheWidth: 480) : ColoredBox(color: pal.line),
      );
}

/// Просмотр карты с увеличением (жесты и кнопки в шапке окна), описание и стихи
class _Viewer extends StatelessWidget {
  const _Viewer({required this.map, required this.pal, required this.controller, required this.onVerse});
  final BibleMap map;
  final Palette pal;
  final TransformationController controller;
  final void Function(String osis) onVerse;

  @override
  Widget build(BuildContext context) {
    final m = map;
    return ListView(children: [
      // .map-view: рамка line, скругление, фон bg
      Container(
        height: MediaQuery.sizeOf(context).height * 0.5,
        decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List>(
          future: _image(m.image),
          builder: (_, s) => s.hasData
              ? InteractiveViewer(transformationController: controller, minScale: 1, maxScale: 6, child: Image.memory(s.data!, fit: BoxFit.contain))
              : Center(
                  child: s.hasError
                      ? Padding(padding: const EdgeInsets.all(12), child: Text(t('Карта не загрузилась. Проверьте интернет.'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)))
                      : Icon(LucideIcons.loaderCircle, size: 20, color: pal.muted),
                ),
        ),
      ),
      if (m.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(m.description, style: TextStyle(fontSize: 15, height: 1.5, color: pal.text))),
      if (m.refs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in m.refs)
              if (parseOsis(r) case final v?) AobChip(label: Books.instance.formatRef(v.book, v.chapter, v.verse), onTap: () => onVerse(r)),
          ]),
        ),
    ]);
  }
}
