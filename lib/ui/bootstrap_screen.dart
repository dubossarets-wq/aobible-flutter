// Первый запуск: ставим основной перевод (дальше — остальные стартовые модули, по мере переноса функций).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/settings.dart';

class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  double _p = 0;
  String _label = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _label = t('Подключаю каталог…');
    });
    try {
      final cat = await ModuleStore.instance.catalog();
      final id = ref.read(settingsProvider).get<String>('primaryModule');
      final e = cat.firstWhere((m) => m.id == id, orElse: () => cat.firstWhere((m) => m.id == 'rst-plus'));
      await ModuleStore.instance.install(e, onProgress: (p, l) => setState(() {
            _p = p;
            _label = '${e.name}: ${t(l)}';
          }));
      widget.onReady();
    } catch (err) {
      setState(() => _error = t('Не удалось подключиться к серверу. Проверьте интернет.') + '\n$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_outlined, size: 40, color: pal.accent),
            const SizedBox(height: 12),
            Text('AO Bible', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: pal.text)),
            const SizedBox(height: 16),
            if (_error == null) ...[
              Text(t('Готовлю Синодальный перевод, словари и параллельные места…'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _p, color: pal.accent, backgroundColor: pal.line),
              const SizedBox(height: 8),
              Text(_label, style: TextStyle(color: pal.muted, fontSize: 13)),
            ] else ...[
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: Text(t('Повторить'))),
            ],
          ]),
        ),
      ),
    );
  }
}
