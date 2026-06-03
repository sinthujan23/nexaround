import Flutter
import UIKit
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register plugins on the app delegate so that Firebase Messaging's native
    // APNs swizzling hooks (didRegisterForRemoteNotificationsWithDeviceToken, etc.)
    // are attached to this object. Without this, the Scene-based lifecycle
    // means the APNs token callback never reaches Firebase on iOS.
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Also register via the engine bridge for the Flutter plugin channel.
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
