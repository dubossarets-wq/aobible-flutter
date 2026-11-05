// Системное стекло iOS 26 (Liquid Glass) — настоящие элементы UIKit из пакета cupertino_native_better.
// Только iPhone и iPad с iOS 26 и новее; ниже iOS 26, на Android, Windows и в тестах — наши обычные виджеты.
// Стекло — только у неподвижных элементов над текстом (нижние вкладки, круглые кнопки глав и «Слушать»):
// каждый такой элемент — отдельный системный слой поверх Flutter, в прокручиваемом списке он тормозил бы.
import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Системное стекло доступно (iOS 26+)
bool get nativeGlass => !kIsWeb && Platform.isIOS && PlatformVersion.shouldUseNativeGlass;

/// Сколько панелей можно открыть, чтобы у каждой кнопки над текстом было стекло: при большем числе
/// системных слоёв становится слишком много — кнопки рисуются как обычно
const glassMaxPanes = 2;

/// Круглая стеклянная кнопка 44 px (как RoundFab), значок — наш, цвет значка — tint
class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.icon, required this.onTap, this.label, this.tint});
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final Color? tint;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: CNButton.icon(
          customIcon: icon,
          onPressed: onTap,
          semanticLabel: label,
          tint: tint,
          config: const CNButtonConfig(style: CNButtonStyle.glass),
        ),
      );
}
