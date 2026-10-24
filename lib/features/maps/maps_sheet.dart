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
  final pal = ref.read(settingsProvider).palette;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.panel,
    useSafeArea: true,
    builder: (_) => _MapsSheet(pane: pane),
  );
}

class _MapsSheet extends ConsumerStatefulWidget {
  const _MapsSheet({required this.pane});
  final int pane;
  @override
  ConsumerState<_MapsSheet> createState() => _MapsSheetState();
}

class _MapsSheetState extends ConsumerState<_MapsSheet> {
  final _q = TextEditingController();
  late final List<BibleMap> _maps = installedMaps();
  late final int _placeCount = PlaceStore.count;
  BibleMap? _open;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _goVerse(String osis) {
    final v = parseOsis(osis);
    if (v == null) return;
    Navigator.pop(context);
    ref.read(panesProvider.notifier).navigate(widget.pane, v);
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final open = _open;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(children: [
        _Header(
          pal: pal,
          title: open?.title ?? t('Карты'),
          subtitle: open?.moduleName,
          onBack: open == null ? null : () => setState(() => _open = null),
          onClose: () => Navigator.pop(context),
        ),
        Expanded(child: open != null ? _Viewer(map: open, pal: pal, onVerse: _goVerse) : _list(pal)),
      ]),
    );
  }

  Widget _list(Palette pal) {
    final found = PlaceStore.search(_q.text);
    final query = _q.text.trim();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (_placeCount > 0) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('${t('Места')} · $_placeCount', style: TextStyle(fontWeight: FontWeight.w700, color: pal.muted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: pal.text),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: pal.muted),
              hintText: t('Найти место: Хеврон, Вифлеем…'),
              hintStyle: TextStyle(color: pal.muted),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: pal.line)),
            ),
          ),
        ),
        for (final p in found)
          ListTile(
            leading: Icon(Icons.place_outlined, color: pal.accent, size: 20),
            title: Text(p.name, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            subtitle: Text([p.type, p.modern].where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted)),
            onTap: () {
              Navigator.pop(context);
              openPlaceMap(context, p);
            },
          ),
        if (query.length >= 2 && found.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Text(t('Ничего не найдено.'), style: TextStyle(color: pal.muted))),
      ],
      if (_maps.isEmpty && _placeCount == 0)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(Icons.map_outlined, size: 40, color: pal.muted),
            const SizedBox(height: 10),
            Text(t('Карты не установлены'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 4),
            Text(t('Установите карты из каталога.'), style: TextStyle(color: pal.muted)),
          ]),
        ),
      for (final m in _maps)
        InkWell(
          onTap: () => setState(() => _open = m),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              SizedBox(width: 72, height: 54, child: _Thumb(path: m.image, pal: pal)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                  Text(m.description.isEmpty ? m.moduleName : m.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pal, required this.title, this.subtitle, this.onBack, required this.onClose});
  final Palette pal;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: Row(children: [
          if (onBack != null) IconButton(icon: Icon(Icons.arrow_back, color: pal.text), onPressed: onBack) else const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: pal.muted)),
            ]),
          ),
          IconButton(icon: Icon(Icons.close, color: pal.text), onPressed: onClose),
        ]),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.pal});
  final String path;
  final Palette pal;
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _image(path),
        builder: (_, s) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: s.hasData ? Image.memory(s.data!, fit: BoxFit.cover, cacheWidth: 200) : ColoredBox(color: pal.line),
        ),
      );
}

/// Просмотр карты с увеличением (жесты и кнопки «Увеличить / Уменьшить»), описание и стихи
class _Viewer extends StatefulWidget {
  const _Viewer({required this.map, required this.pal, required this.onVerse});
  final BibleMap map;
  final Palette pal;
  final void Function(String osis) onVerse;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  final _tc = TransformationController();

  void _zoom(double k) {
    final s = (_tc.value.getMaxScaleOnAxis() * k).clamp(1.0, 6.0);
    _tc.value = Matrix4.diagonal3Values(s, s, 1);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final m = widget.map;
    return ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        IconButton(tooltip: t('Уменьшить'), icon: Icon(Icons.zoom_out, color: pal.text), onPressed: () => _zoom(1 / 1.5)),
        IconButton(tooltip: t('Увеличить'), icon: Icon(Icons.zoom_in, color: pal.text), onPressed: () => _zoom(1.5)),
      ]),
      SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: FutureBuilder<Uint8List>(
          future: _image(m.image),
          builder: (_, s) => s.hasData
              ? InteractiveViewer(transformationController: _tc, minScale: 1, maxScale: 6, child: Image.memory(s.data!, fit: BoxFit.contain))
              : Center(child: s.hasError ? Text(t('Карта не загрузилась. Проверьте интернет.'), style: TextStyle(color: pal.muted)) : const CircularProgressIndicator()),
        ),
      ),
      if (m.description.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(m.description, style: TextStyle(color: pal.text, height: 1.4))),
      if (m.refs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in m.refs)
              if (parseOsis(r) case final v?)
                ActionChip(
                  label: Text(Books.instance.formatRef(v.book, v.chapter, v.verse)),
                  backgroundColor: pal.bg,
                  side: BorderSide(color: pal.line),
                  labelStyle: TextStyle(color: pal.text),
                  onPressed: () => widget.onVerse(r),
                ),
          ]),
        ),
    ]);
  }
}
