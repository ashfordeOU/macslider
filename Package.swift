// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSlider",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacSlider", targets: ["MacSlider"]),
        .library(name: "MacSliderCore", targets: ["MacSliderCore"]),
    ],
    targets: [
        // Pure layout model: no AppKit, builds and tests on any platform.
        .target(name: "MacSliderCore"),
        // The macOS app: Accessibility engine, input, menu bar and settings.
        .executableTarget(
            name: "MacSlider",
            dependencies: ["MacSliderCore"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "MacSliderCoreTests", dependencies: ["MacSliderCore"]),
    ]
)
