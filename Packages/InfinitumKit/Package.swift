// swift-tools-version: 5.9
// InfinitumKit: the shared shell every Infinitum Apple app runs on.
// Cumulus ID sign-in (OAuth 2.0 code + PKCE S256), the product web view, and Amplitude
// (page views and sessions only) for commercial products.
import PackageDescription

let package = Package(
    name: "InfinitumKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InfinitumKit", targets: ["InfinitumKit"]),
    ],
    dependencies: [
        // Official SDK, pinned (standing rule: Amplitude-Swift 1.20.0).
        .package(url: "https://github.com/amplitude/Amplitude-Swift.git", exact: "1.20.0"),
    ],
    targets: [
        .target(
            name: "InfinitumKit",
            dependencies: [.product(name: "AmplitudeSwift", package: "Amplitude-Swift")]
        ),
        .testTarget(name: "InfinitumKitTests", dependencies: ["InfinitumKit"]),
    ]
)
