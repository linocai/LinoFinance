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
    ],
    targets: [
        .target(name: "LinoFinanceCore"),
        .target(
            name: "LinoFinanceDesignSystem",
            dependencies: ["LinoFinanceCore"]
        ),
        .testTarget(
            name: "LinoFinanceCoreTests",
            dependencies: ["LinoFinanceCore"]
        ),
    ]
)
