// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "GlyphonKit",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(name: "GlyphonKit", targets: ["GlyphonKit"]),
  ],
  targets: [
    .target(
      name: "GlyphonKit",
      resources: [.process("Resources")]
    ),
    .executableTarget(
      name: "glyphon-extract",
      path: "Sources/GlyphonExtract"
    ),
    .testTarget(
      name: "GlyphonKitTests",
      dependencies: ["GlyphonKit"]
    ),
  ]
)
