// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SeventyTwoBlocks",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SeventyTwoBlocks",
            targets: ["SeventyTwoBlocks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SeventyTwoBlocks",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources"
        ),
    ]
)
