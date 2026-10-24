// AO Bible на Flutter. Запуск: настройки, справочник книг, язык, модули — затем сразу экран чтения
// (книга читается из SQLite синхронно, без ожидания сети и без промежуточных экранов).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/books.dart';
import 'core/i18n.dart';
import 'core/modules.dart';
import 'core/settings.dart';
import 'ui/bootstrap_screen.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final started = DateTime.now();
  prefs = await SharedPreferences.getInstance();
  await Books.load();
  await initI18n();
  await ModuleStore.init();
  debugPrint('AOB start ${DateTime.now().difference(started).inMilliseconds} ms');
  runApp(const ProviderScope(child: AoBibleApp()));
}

class AoBibleApp extends ConsumerStatefulWidget {
  const AoBibleApp({super.key});
  @override
  ConsumerState<AoBibleApp> createState() => _AoBibleAppState();
}

class _AoBibleAppState extends ConsumerState<AoBibleApp> {
  bool _ready = ModuleStore.instance.bibles.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final scheme = ColorScheme.fromSeed(seedColor: pal.accent, brightness: pal.dark ? Brightness.dark : Brightness.light).copyWith(primary: pal.accent, surface: pal.panel, onPrimary: pal.onAccent);
    return MaterialApp(
      title: 'AO Bible',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, scaffoldBackgroundColor: pal.bg, useMaterial3: true),
      home: _ready ? const HomeScreen() : BootstrapScreen(onReady: () => setState(() => _ready = true)),
    );
  }
}
