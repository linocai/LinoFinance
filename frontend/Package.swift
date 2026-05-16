// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinoFinanceFrontend",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "LinoFinanceCore", targets: ["LinoFinanceCore"]),
        .library(name: "LinoFinanceDesignSystem", targets: ["LinoFinanceDesignSystem"]),
        .library(name: "LinoFinanceFeatures", targets: ["LinoFinanceFeatures"]),
    ],
    targets: [
        .target(name: "LinoFinanceCore"),
        .target(
            name: "LinoFinanceDesignSystem",
            dependencies: ["LinoFinanceCore"]
        ),
        .target(
            name: "LinoFinanceFeatures",
            dependencies: ["LinoFinanceCore", "LinoFinanceDesignSystem"]
        ),
        .testTarget(
            name: "LinoFinanceCoreTests",
            dependencies: ["LinoFinanceCore"]
        ),
    ]
)
