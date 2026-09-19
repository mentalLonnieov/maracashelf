// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaracaShelf",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MaracaShelf",
            path: "Sources/MaracaShelf"
        )
    ]
)
