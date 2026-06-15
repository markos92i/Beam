// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Beam",
    platforms: [
       .macOS(.v15), .iOS(.v18),
    ],
    products: [
        .library(
            name: "Beam",
            targets: ["Beam"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.2"),
    ],
    targets: [
        // Macro implementation (compiler plugin)
        .macro(
            name: "BeamMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Main library
        .target(
            name: "Beam",
            dependencies: ["BeamMacros"]
        ),

        // Tests
        .testTarget(
            name: "BeamTests",
            dependencies: ["Beam"]
        ),
        .testTarget(
            name: "BeamMacrosTests",
            dependencies: [
                "BeamMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
