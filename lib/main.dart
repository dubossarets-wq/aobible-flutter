// AO Bible на Flutter. Запуск: настройки, справочник книг, язык, модули — затем сразу экран чтения
// (книга читается из SQLite синхронно, без ожидания сети и без промежуточных экранов).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/books.dart';
import 'core/i18n.dart';
import 'core/modules.dart';
import 'core/panes.dart' show updateAvailable;
import 'core/settings.dart';
import 'features/features.dart';
import 'features/hub.dart';
import 'ui/bootstrap_screen.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final started = DateTime.now();
  prefs = await SharedPreferences.getInstance();
  systemDark.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  await Books.load();
  await initI18n();
  await ModuleStore.init();
  registerFeatures();
  onLangChanged = () {
    Hub.reset();
    registerFeatures();
  };
  debugPrint('AOB start ${DateTime.now().difference(started).inMilliseconds} ms');
  runApp(const ProviderScope(child: AoBibleApp()));
}

class AoBibleApp extends ConsumerStatefulWidget {
  const AoBibleApp({super.key});
  @override
  ConsumerState<AoBibleApp> createState() => _AoBibleAppState();
}

class _AoBibleAppState extends ConsumerState<AoBibleApp> with WidgetsBindingObserver {
  bool _ready = ModuleStore.instance.bibles.isNotEmpty;

  // Тема системы сменилась — «Как в системе» перекрашивается сразу
  @override
  void didChangePlatformBrightness() => systemDark.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    systemDark.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    // Тихая проверка обновления (Google Play): на «Ещё» загорается точка
    if (Platform.isAndroid) {
      InAppUpdate.checkForUpdate().then((i) => updateAvailable.value = i.updateAvailability == UpdateAvailability.updateAvailable, onError: (_) {});
    }
    // Дела после первого кадра (доустановка модулей, перенос данных, напоминания) — не задерживают показ текста
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final job in Hub.afterStart) {
        try {
          await job(ref);
        } catch (e) {
          debugPrint('afterStart: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final scheme = ColorScheme.fromSeed(seedColor: pal.accent, brightness: pal.dark ? Brightness.dark : Brightness.light).copyWith(primary: pal.accent, surface: pal.panel, onPrimary: pal.onAccent);
    return MaterialApp(
      title: 'AO Bible',
      scaffoldMessengerKey: Hub.messengerKey,
      navigatorKey: Hub.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, scaffoldBackgroundColor: pal.bg, useMaterial3: true),
      // Строка состояния и нижняя системная панель — цвета темы. Через AnnotatedRegion: MaterialApp сам ставит
      // светлые/тёмные значки при каждой сборке, прямой вызов SystemChrome проиграл бы ему
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(value: systemBarsStyle(pal), child: child ?? const SizedBox.shrink()),
      home: _ready ? const HomeScreen() : BootstrapScreen(onReady: () => setState(() => _ready = true)),
    );
  }
}
