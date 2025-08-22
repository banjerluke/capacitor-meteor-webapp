// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorMeteorWebApp",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [
        .library(
            name: "CapacitorMeteorWebApp",
            targets: ["CapacitorMeteorWebAppPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CapacitorMeteorWebAppPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CapacitorMeteorWebAppPlugin",
            exclude: ["CapacitorMeteorWebAppPlugin.swift"],
            swiftSettings: [.define("TESTING")]),
        .testTarget(
            name: "CapacitorMeteorWebAppTests",
            dependencies: ["CapacitorMeteorWebAppPlugin"],
            path: "ios/Tests/CapacitorMeteorWebAppTests",
            resources: [.copy("../../../tests/fixtures")],
            swiftSettings: [.define("TESTING")])
    ]
)
