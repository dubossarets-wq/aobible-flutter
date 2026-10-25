// Карты и места: пункт «Карта» в выборке над названием места в стихе и «Карты» в меню «Ещё».

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import '../shell/fonts.dart' show menuFlag;
import 'map_screen.dart';
import 'maps_sheet.dart';
import 'places_data.dart';

bool _hasMapsModule() {
  try {
    return ModuleStore.instance.installed.any((m) => m.type == 'maps');
  } catch (_) {
    return false;
  }
}

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

  // Пункт «Карты»: по настройке меню и только если установлен (и включён) модуль карт — m.maps && modules.some(maps) в moreItems.jsx
  Hub.moreItems.add(MoreItem(
    id: 'maps',
    icon: LucideIcons.map,
    label: t('Карты'),
    order: 60,
    run: openMapsSheet,
    visible: (ref) => menuFlag(ref.watch(settingsProvider), 'maps') && _hasMapsModule(),
  ));
}
