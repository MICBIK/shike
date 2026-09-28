// swift-tools-version: 6.2
// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import PackageDescription

// 警告即错误只在 CI 开启：CI 设置 SHIKE_WARNINGS_AS_ERRORS=YES（stack.md）。
// 只作用于本包的四个目标，不影响 GRDB。
let strictWarnings: [SwiftSetting] = ProcessInfo.processInfo.environment["SHIKE_WARNINGS_AS_ERRORS"] == "YES"
    ? [.treatAllWarnings(as: .error)]
    : []

let package = Package(
    name: "ShikeKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ShikeDateParser", targets: ["ShikeDateParser"]),
        .library(name: "ShikeData", targets: ["ShikeData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")
    ],
    targets: [
        .target(name: "ShikeDateParser", swiftSettings: strictWarnings),
        .target(
            name: "ShikeData",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: strictWarnings
        ),
        .testTarget(
            name: "ShikeDateParserTests",
            dependencies: [
                .byName(name: "ShikeDateParser")
            ],
            swiftSettings: strictWarnings
        ),
        .testTarget(
            name: "ShikeDataTests",
            dependencies: [
                .byName(name: "ShikeData"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: strictWarnings
        ),
    ],
    swiftLanguageModes: [.v6]
)
