// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 把 `DataFailureReason` 映射为文案（app-shell.md「组件契约」）；文案与「阶段 0 文案」表逐字一致。
enum ErrorText {
    static func reason(_ reason: DataFailureReason) -> String {
        switch reason {
        case .diskFull:
            String(localized: .errorReasonDiskFull)
        case .readOnly:
            String(localized: .errorReasonReadOnly)
        case .permissionDenied:
            String(localized: .errorReasonPermissionDenied)
        case .corrupted:
            String(localized: .errorReasonCorrupted)
        case .busy:
            String(localized: .errorReasonBusy)
        case .newerSchema:
            String(localized: .errorReasonNewerSchema)
        case .ioError:
            String(localized: .errorReasonIoError)
        case .constraintViolation:
            String(localized: .errorReasonConstraintViolation)
        case .invalidLocation:
            String(localized: .errorReasonInvalidLocation)
        case .simulated:
            String(localized: .errorReasonSimulated)
        case .unknown(let code):
            String(localized: .errorReasonUnknown(code))
        }
    }
}

extension DataFailureReason {
    /// 日志用分类名（failure-modes.md「日志」：只记录错误分类和代码）。
    var classification: String {
        switch self {
        case .diskFull: "diskFull"
        case .readOnly: "readOnly"
        case .permissionDenied: "permissionDenied"
        case .corrupted: "corrupted"
        case .busy: "busy"
        case .newerSchema: "newerSchema"
        case .ioError: "ioError"
        case .constraintViolation: "constraintViolation"
        case .invalidLocation: "invalidLocation"
        case .simulated: "simulated"
        case .unknown(let code): "unknown(\(code))"
        }
    }
}

extension ShikeDataError {
    /// 日志用分类名：`类别/原因`（failure-modes.md「日志」）。
    var classification: String {
        switch self {
        case .notFound: "notFound"
        case .openFailed(let reason): "openFailed/\(reason.classification)"
        case .readFailed(let reason): "readFailed/\(reason.classification)"
        case .writeFailed(let reason): "writeFailed/\(reason.classification)"
        case .backupFailed(let reason): "backupFailed/\(reason.classification)"
        }
    }
}
