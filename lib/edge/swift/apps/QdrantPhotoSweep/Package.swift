// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "QdrantPhotoSweep",
    platforms: [
        .iOS(.v17),
    ],
    dependencies: [
        .package(name: "QdrantEdge", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "QdrantPhotoSweep",
            dependencies: ["QdrantEdge"],
            path: "Sources/QdrantPhotoSweep"
        ),
    ]
)
