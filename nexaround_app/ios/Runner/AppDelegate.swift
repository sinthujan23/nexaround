import Flutter
import UIKit
import FirebaseMessaging
import GoogleMaps
import UserNotifications

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

    // The Google Maps iOS key is NOT hardcoded. It is supplied at runtime from the
    // backend (admin-managed, stored in the DB) via the method channel registered
    // in didInitializeImplicitFlutterEngine below.

    // Force APNs registration to happen early/on-startup
    application.registerForRemoteNotifications()
    
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Single, authoritative plugin registration point.
    // Firebase Messaging's APNs swizzling hooks are established here via
    // the plugin's own initialisation — no manual forward is needed.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Receive the Google Maps API key from Dart. main.dart fetches it from the
    // backend /config/keys (admin-managed value in the DB) and sends it here.
    // Google Maps iOS accepts the key at runtime via GMSServices.provideAPIKey,
    // so nothing is hardcoded and the admin panel stays the single source of truth.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoogleMapsKeyChannel") {
      let channel = FlutterMethodChannel(
        name: "com.nexaround.app/keys",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "setGoogleMapsKey",
              let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              !key.isEmpty else {
          result(FlutterMethodNotImplemented)
          return
        }
        GMSServices.provideAPIKey(key)
        result(true)
      }
    }
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

  // Forward incoming remote notifications to Firebase Messaging (required when swizzling is disabled).
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    Messaging.messaging().appDidReceiveMessage(userInfo)
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  // MARK: - UNUserNotificationCenterDelegate
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Pass to flutter engine
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: { _ in })
    
    // Present the notification in foreground
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Let flutter handle the tap
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
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
