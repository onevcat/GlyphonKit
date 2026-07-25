// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "recommender-eval",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    .package(path: "..")
  ],
  targets: [
    .executableTarget(
      name: "recommender-eval",
      dependencies: [
        .product(name: "GlyphonKit", package: "GlyphonKit")
      ]
    )
  ]
)
