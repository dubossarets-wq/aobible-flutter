// Карты и места: пункт «Карта» в выборке над названием места в стихе и «Карты» в меню «Ещё».
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../hub.dart';
import 'map_screen.dart';
import 'maps_sheet.dart';
import 'places_data.dart';

void register() {
  Hub.mapPaneBuilder = mapPaneFor;
  // Нажатие на слово: если стих упоминает место с такой основой названия — «Название · Карта»
  Hub.wordMenuItems.add((context, ref, tap) {
    final List<Place> places;
    try {
      places = PlaceStore.forWord(tap.token.text, tap.ref);
    } catch (_) {
      return const [];
    }
    return [
      for (final p in places)
        WordMenuItem(label: p.name, sub: t('Карта'), order: 10, onTap: () => openPlaceMap(context, p)),
    ];
  });

  Hub.moreItems.add(MoreItem(id: 'maps', icon: Icons.map_outlined, label: t('Карты'), order: 60, run: openMapsSheet));
}
