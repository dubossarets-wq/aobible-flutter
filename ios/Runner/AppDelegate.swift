import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Напоминания о плане чтения (flutter_local_notifications): показывать и при открытом приложении
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Канал aobible/screen: экран не гаснет на «Кафедре» (lib/features/sermons/screen_on.dart)
    if let reg = engineBridge.pluginRegistry.registrar(forPlugin: "AobScreen") {
      FlutterMethodChannel(name: "aobible/screen", binaryMessenger: reg.messenger()).setMethodCallHandler { call, result in
        if call.method == "keepOn" {
          let on = (call.arguments as? Bool) == true
          DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = on }
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
