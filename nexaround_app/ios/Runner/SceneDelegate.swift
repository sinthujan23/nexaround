import Flutter
import UIKit
import GoogleMaps

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let keysChannel = FlutterMethodChannel(name: "com.nexaround.app/keys",
                                           binaryMessenger: controller.binaryMessenger)
    keysChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "setGoogleMapsKey" {
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String {
          GMSServices.provideAPIKey(key)
          result(true)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }
}
