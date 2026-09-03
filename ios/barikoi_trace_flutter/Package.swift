// swift-tools-version: 5.9

// Swift Package Manager manifest for the iOS side of `barikoi_trace_flutter`.
//
// Used by Flutter's Swift Package Manager integration (Flutter 3.24+, enabled
// by default from 3.44). The Flutter tool generates a wrapper package that
// depends on this one and links it into the Runner target; CocoaPods hosts go
// through `../barikoi_trace_flutter.podspec` instead, which compiles the same
// sources.
//
// Note on the `Flutter` framework: it is *not* declared as a package
// dependency, because there is no `Flutter` Swift package to depend on. The
// Flutter tool passes the `Flutter.xcframework` search paths to every plugin
// package it builds, which is what makes `import Flutter` resolve. This
// matches the shape of every first-party Flutter plugin that has migrated to
// SPM (path_provider_foundation, shared_preferences_foundation, …) — adding a
// `.product(name: "Flutter", …)` dependency here would fail to resolve.

import PackageDescription

let package = Package(
    name: "barikoi_trace_flutter",
    platforms: [
        // Matches the BarikoiTrace iOS SDK's own floor. `CLLocation.sourceInformation`
        // (used for the `isMock` wire field) is iOS 15+, as is the SDK's
        // background coordinator.
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "barikoi-trace-flutter",
            targets: ["barikoi_trace_flutter"]
        )
    ],
    dependencies: [
        // Pinned exactly, not `.upToNextMinor`: `BarikoiTrace.nativeSdkVersion`
        // on the Dart side is a constant that host apps read, and the wire
        // contract's version pin (§8) says the two move together.
        .package(
            url: "https://github.com/barikoi/BarikoiTrace-ios-sdk.git",
            exact: "0.4.0"
        )
    ],
    targets: [
        .target(
            name: "barikoi_trace_flutter",
            dependencies: [
                .product(name: "BarikoiTrace", package: "BarikoiTrace-ios-sdk")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
