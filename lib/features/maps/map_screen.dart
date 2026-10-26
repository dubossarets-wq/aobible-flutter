// Карта места отдельным экраном. Когда в ядре появится «панель-карта» во второй половине главного экрана,
// этот же MapPaneView встанет туда, а openPlaceMap станет вызовом ядра (см. отчёт).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart' show closeToReader;
import 'map_pane.dart';
import 'places_data.dart';

/// Открыть карту места во второй половине главного экрана (панель-карта ядра: mapPaneProvider)
void openPlaceMap(BuildContext context, Place place) {
  ProviderScope.containerOf(context, listen: false).read(mapPaneProvider.notifier).open(place);
}

/// Панель-карта для главного экрана (Hub.mapPaneBuilder): нажатие на стих в карточке ведёт первую панель,
/// карта остаётся
Widget mapPaneFor(BuildContext context, WidgetRef ref, Object place) => MapPaneView(
      key: ValueKey(place),
      place: place as Place,
      onClose: () => ref.read(mapPaneProvider.notifier).close(),
      onOpenVerse: (r) => ref.read(panesProvider.notifier).navigate(0, r),
    );

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: MapPaneView(
          place: place,
          onClose: () => Navigator.pop(context),
          onOpenVerse: (r) {
            closeToReader(context); // сразу в Библию
            ref.read(panesProvider.notifier).navigate(0, r);
          },
        ),
      ),
    );
  }
}
