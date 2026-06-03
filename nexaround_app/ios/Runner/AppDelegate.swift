import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // NOTE: Do NOT call GeneratedPluginRegistrant.register(with: self) here.
    // This Flutter embedding registers plugins in didInitializeImplicitFlutterEngine
    // (below). Registering in both places throws "duplicate plugin key" in
    // -[FlutterEngine registrarForPlugin:] and crashes the app at launch (SIGABRT).
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Single, correct plugin registration for this Flutter version. This also
    // wires up Firebase Messaging's APNs swizzling — no extra registration needed.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
