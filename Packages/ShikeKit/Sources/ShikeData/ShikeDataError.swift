// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// ShikeData 抛出的全部错误；App 层负责把原因映射成中文文案（app-shell.md）。
public enum ShikeDataError: Error, Sendable, Equatable {
    case notFound
    case openFailed(DataFailureReason)
    case readFailed(DataFailureReason)
    case writeFailed(DataFailureReason)
    case backupFailed(DataFailureReason)
}

/// 失败原因，按 SQLite 主结果码与文件系统错误分类（data-layer.md「错误分类」）。
public enum DataFailureReason: Sendable, Equatable {
    case diskFull
    case readOnly
    case permissionDenied
    case corrupted
    case busy
    case newerSchema
    case ioError
    case constraintViolation
    /// 数据目录不是绝对路径的文件 URL（如 `-ShikeDataDirectory` 写错）。
    case invalidLocation
    /// 调试启动参数触发。
    case simulated
    case unknown(code: Int32)
}
