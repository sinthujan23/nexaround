import Flutter
import UIKit
import FirebaseMessaging
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // NOTE: Do NOT call GeneratedPluginRegistrant.register(with: self) here.
    // For scene-based apps the Flutter engine is initialised implicitly; plugins
    // must be registered exactly once via didInitializeImplicitFlutterEngine
    // below. Calling register(with:) here AND there triggers a duplicate-plugin
    // NSAssertion in FlutterEngine.mm that crashes the app on launch (SIGABRT).

    // Initialize Google Maps SDK (required before MapView is shown).
    // Replace the string below with your actual Google Maps iOS API key.
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Single, authoritative plugin registration point.
    // Firebase Messaging's APNs swizzling hooks are established here via
    // the plugin's own initialisation — no manual forward is needed.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Manually forward the APNs device token to Firebase Messaging.
  // This is required when using UISceneDelegate — iOS delivers the APNs token
  // here on AppDelegate, but Firebase must receive it to exchange it for an FCM token.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Forward APNs registration failures for better debugging.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
