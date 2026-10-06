// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CNSNNCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "CNSNNCore", targets: ["CNSNNCore"])], targets: [.target(name: "CNSNNCore", path: "Core"), .testTarget(name: "CNSNNCoreTests", dependencies: ["CNSNNCore"], path: "Tests/Core")])
