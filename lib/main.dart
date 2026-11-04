// AO Bible на Flutter. Запуск: настройки, справочник книг, язык, модули — затем сразу экран чтения
// (книга читается из SQLite синхронно, без ожидания сети и без промежуточных экранов).
import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart' show CNTabBarRouteObserver;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
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
import 'ui/keyboard_emu.dart';
import 'ui/kit.dart' show SheetObserver;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Звук на компьютере (проверка на Windows) — через media_kit: прежний плеер для Windows слал сообщения из чужого
  // потока и подвешивал окно. На Android и iOS just_audio работает своим родным плеером, это их не касается
  if (Platform.isWindows || Platform.isLinux) JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
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
  runApp(const _Root());
}

/// Корень: состояние приложения (ProviderScope) можно пересоздать целиком — Hub.restartApp. Нужно после переноса
/// данных из старого приложения: всё, что уже успело прочитаться пустым (проповеди, планы, выделения…), читается заново
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
    Hub.restartApp = () => mounted ? setState(() => _key = UniqueKey()) : null;
  }

  @override
  Widget build(BuildContext context) => ProviderScope(key: _key, child: const AoBibleApp());
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
      // CNTabBarRouteObserver — системное стекло iOS 26 (glass.dart) не просвечивает сквозь открытые поверх окна
      navigatorObservers: [SheetObserver(), CNTabBarRouteObserver()],
      debugShowCheckedModeBanner: false,
      // перетаскивание мышью листает списки и ряды плашек (на компьютере — как пальцем на телефоне)
      scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus}),
      theme: ThemeData(colorScheme: scheme, scaffoldBackgroundColor: pal.bg, useMaterial3: true),
      // Строка состояния и нижняя системная панель — цвета темы. Через AnnotatedRegion: MaterialApp сам ставит
      // светлые/тёмные значки при каждой сборке, прямой вызов SystemChrome проиграл бы ему
      builder: (context, child) {
        final app = TabBarOverlay(child: child ?? const SizedBox.shrink());
        // на компьютере — эмуляция экранной клавиатуры (проверять, как интерфейс подстраивается под неё)
        return AnnotatedRegion<SystemUiOverlayStyle>(value: systemBarsStyle(pal), child: keyboardEmuAvailable ? KeyboardEmu(child: app) : app);
      },
      home: _ready ? const HomeScreen() : BootstrapScreen(onReady: () => setState(() => _ready = true)),
    );
  }
}
