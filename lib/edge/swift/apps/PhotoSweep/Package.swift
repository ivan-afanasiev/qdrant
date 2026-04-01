// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PhotoSweep",
    platforms: [
        .iOS(.v17),
    ],
    dependencies: [
        .package(name: "QdrantEdge", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "PhotoSweep",
            dependencies: ["QdrantEdge"],
            path: "Sources/PhotoSweep"
        ),
    ]
)
