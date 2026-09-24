import FBSDKShareKit
import Flutter
import Photos
import UIKit

/// iOS side of package:nexaround_share (lib/nexaround_share.dart).
///
/// Each method answers true when it handed the content to the other app, and
/// false when it could not, so Dart can fall back to the share menu.
public class NexaroundSharePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.nexaround.app/social_share",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(NexaroundSharePlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "facebookLink":
            guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                result(false)
                return
            }
            shareToFacebook(url, result: result)
        case "instagramStory":
            guard let image = (args["image"] as? FlutterStandardTypedData)?.data else {
                result(false)
                return
            }
            shareToInstagramStory(image, result: result)
        case "facebookStory":
            guard let image = (args["image"] as? FlutterStandardTypedData)?.data else {
                result(false)
                return
            }
            shareToFacebookStory(image, result: result)
        case "instagramPost":
            guard let image = (args["image"] as? FlutterStandardTypedData)?.data else {
                result(false)
                return
            }
            shareToInstagramPost(image, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Facebook's own share dialog: the Facebook app's post screen when it is
    /// installed, Facebook's web dialog when it is not. The link shows as a
    /// card built from the share page's Open Graph tags.
    private func shareToFacebook(_ url: URL, result: @escaping FlutterResult) {
        guard let presenter = Self.topViewController() else {
            result(false)
            return
        }
        let content = ShareLinkContent()
        content.contentURL = url
        let dialog = ShareDialog(viewController: presenter, content: content, delegate: nil)
        dialog.mode = .automatic
        guard dialog.canShow else {
            result(false)
            return
        }
        dialog.show()
        result(true)
    }

    /// Instagram's "Sharing to Stories": the image goes on the pasteboard
    /// under Instagram's keys, then the instagram-stories URL opens a new
    /// story with it. Instagram requires the Facebook App ID as the source.
    private func shareToInstagramStory(_ image: Data, result: @escaping FlutterResult) {
        let appID = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String ?? ""
        guard !appID.isEmpty,
              let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url)
        else {
            result(false)
            return
        }
        let items: [[String: Any]] = [[
            "com.instagram.sharedSticker.stickerImage": image,
            "com.instagram.sharedSticker.backgroundTopColor": "#00A3A6",
            "com.instagram.sharedSticker.backgroundBottomColor": "#005E60",
            "com.instagram.sharedSticker.appID": appID,
        ]]
        // Short-lived: nothing of ours should linger on the user's clipboard.
        UIPasteboard.general.setItems(
            items,
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url, options: [:]) { opened in
            result(opened)
        }
    }

    /// Facebook's "Sharing to Stories": the same pasteboard hand-off as
    /// Instagram's, under Facebook's keys, with the App ID on the pasteboard.
    private func shareToFacebookStory(_ image: Data, result: @escaping FlutterResult) {
        let appID = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String ?? ""
        guard !appID.isEmpty,
              let url = URL(string: "facebook-stories://share"),
              UIApplication.shared.canOpenURL(url)
        else {
            result(false)
            return
        }
        let items: [[String: Any]] = [[
            "com.facebook.sharedSticker.stickerImage": image,
            "com.facebook.sharedSticker.backgroundTopColor": "#00A3A6",
            "com.facebook.sharedSticker.backgroundBottomColor": "#005E60",
            "com.facebook.sharedSticker.appID": appID,
        ]]
        UIPasteboard.general.setItems(
            items,
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url, options: [:]) { opened in
            result(opened)
        }
    }

    /// A new Instagram feed post with [image]. Instagram only takes a post
    /// from the photo library, so the image is saved there first (add-only
    /// access, NSPhotoLibraryAddUsageDescription) and instagram://library
    /// opens the post editor on it. Answers the FlutterError
    /// "photos_denied" when the user refused photo access.
    private func shareToInstagramPost(_ image: Data, result: @escaping FlutterResult) {
        guard let probe = URL(string: "instagram://app"),
              UIApplication.shared.canOpenURL(probe)
        else {
            result(false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "photos_denied", message: nil, details: nil))
                }
                return
            }
            var assetID: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: image, options: nil)
                assetID = request.placeholderForCreatedAsset?.localIdentifier
            }) { saved, _ in
                DispatchQueue.main.async {
                    guard saved,
                          let id = assetID,
                          let url = URL(string: "instagram://library?LocalIdentifier=\(id)")
                    else {
                        result(false)
                        return
                    }
                    UIApplication.shared.open(url, options: [:]) { opened in
                        result(opened)
                    }
                }
            }
        }
    }

    /// The view controller currently on screen, to present Facebook's dialog.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
