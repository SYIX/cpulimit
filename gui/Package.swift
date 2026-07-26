// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CPULimitGUI",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "CPULimitGUI",
            path: "Sources/CPULimitGUI"
        )
    ]
)
