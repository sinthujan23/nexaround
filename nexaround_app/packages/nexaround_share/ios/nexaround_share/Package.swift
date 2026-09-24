// swift-tools-version: 5.9
import PackageDescription

// Same Facebook SDK package and version range as facebook_app_events, so Swift
// Package Manager resolves one copy of Facebook's SDK for both plugins.
let package = Package(
    name: "nexaround_share",
    platforms: [
        .iOS("14.0")
    ],
    products: [
        // A plugin name containing "_" must use "-" in its library name.
        .library(name: "nexaround-share", targets: ["nexaround_share"])
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", "18.0.0"..<"19.0.0")
    ],
    targets: [
        .target(
            name: "nexaround_share",
            dependencies: [
                .product(name: "FacebookShare", package: "facebook-ios-sdk")
            ]
        )
    ]
)
