// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HermesDashboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HermesDashboard", targets: ["HermesDashboard"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "HermesDashboard",
            dependencies: ["CSQLite"],
            resources: [.copy("Resources/dashboard-data.json")]
        )
    ]
)
