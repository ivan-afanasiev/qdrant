// swift-tools-version: 6.2
import PackageDescription

let safeDI: Target.Dependency = .product(name: "SafeDI", package: "SafeDI")
let package = Package(
    name: "PhotoSweep",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [.library(name: "SweepComposition", targets: ["SweepComposition"])],
    dependencies: [.package(url: "https://github.com/dfed/SafeDI.git", exact: "2.2.0"), .package(path: "../../../..") ],
    targets: [
        .target(name: "SweepDomain"),
        .target(name: "SweepQdrant", dependencies: ["SweepDomain", .product(name: "QdrantEdge", package: "swift")]),
        .target(name: "SweepPhotos", dependencies: ["SweepDomain"]),
        .target(name: "SweepEmbeddings", dependencies: ["SweepDomain"]),
        .target(name: "SweepPersistence", dependencies: ["SweepDomain"]),
        .target(name: "SweepDesignSystem", resources: [.process("Resources")]),
        .target(name: "SweepFeatureState"),
        .target(name: "SweepReviewFeature", dependencies: ["SweepUseCases", "SweepFeatureState", "SweepDesignSystem"]),
        .target(name: "SweepSettingsFeature", dependencies: ["SweepUseCases", "SweepFeatureState", "SweepDesignSystem"]),
        .target(name: "SweepOnboardingFeature", dependencies: ["SweepUseCases", "SweepFeatureState", "SweepDesignSystem"]),
        .target(name: "SweepTestSupport", dependencies: ["SweepDomain"]),
        .target(name: "SweepSystem", dependencies: ["SweepDomain", safeDI]),
        .target(name: "SweepUseCases", dependencies: ["SweepDomain", safeDI]),
        .target(name: "SweepLibraryFeature", dependencies: ["SweepUseCases", "SweepFeatureState", "SweepDesignSystem", safeDI]),
        .target(name: "SweepComposition", dependencies: ["SweepDomain", "SweepSystem", "SweepUseCases", "SweepLibraryFeature", "SweepReviewFeature", "SweepSettingsFeature", "SweepOnboardingFeature", "SweepQdrant", "SweepPhotos", "SweepEmbeddings", "SweepPersistence", safeDI],
                plugins: [.plugin(name: "SafeDIGenerator", package: "SafeDI")]),
        .testTarget(name: "SweepPhotosTests", dependencies: ["SweepPhotos"]),
        .testTarget(name: "SweepEmbeddingsTests", dependencies: ["SweepEmbeddings"]),
        .testTarget(name: "SweepDesignSystemTests", dependencies: ["SweepDesignSystem"]),
        .testTarget(name: "SweepQdrantTests", dependencies: ["SweepQdrant", "SweepDomain"]),
        .testTarget(name: "SweepCompositionTests", dependencies: ["SweepComposition", "SweepDomain", "SweepUseCases"])
    ],
    swiftLanguageModes: [.v6]
)
