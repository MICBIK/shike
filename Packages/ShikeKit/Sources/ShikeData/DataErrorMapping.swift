// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// SQLite 主结果码与文件系统错误到 DataFailureReason 的映射
/// （data-layer.md「错误分类」表，一一对应）。
func mapFailure(_ error: any Error) -> DataFailureReason {
    if let databaseError = error as? DatabaseError {
        // 扩展结果码屏蔽到主结果码再分类
        return mapResultCode(databaseError.resultCode.rawValue & 0xFF)
    }

    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain {
        return mapPOSIXCode(Int32(bitPattern: UInt32(nsError.code)))
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
        underlying.domain == NSPOSIXErrorDomain
    {
        return mapPOSIXCode(Int32(bitPattern: UInt32(underlying.code)))
    }
    // 走到这里的一般是手工构造的 CocoaError；真实文件管理器错误都携带
    // POSIX underlying error，已被上面的分支接住。
    if let cocoa = error as? CocoaError {
        switch cocoa.code {
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .permissionDenied
        default:
            return .ioError
        }
    }
    return .ioError
}

/// POSIX errno：EACCES、EPERM、EROFS 视为权限问题，其余文件系统错误归 ioError。
private func mapPOSIXCode(_ code: Int32) -> DataFailureReason {
    switch code {
    case EACCES, EPERM, EROFS:
        return .permissionDenied
    default:
        return .ioError
    }
}

/// SQLite 主结果码（data-layer.md「错误分类」表）。
func mapResultCode(_ primaryCode: Int32) -> DataFailureReason {
    switch primaryCode {
    case ResultCode.SQLITE_FULL.rawValue: return .diskFull
    case ResultCode.SQLITE_READONLY.rawValue: return .readOnly
    case ResultCode.SQLITE_PERM.rawValue, ResultCode.SQLITE_AUTH.rawValue: return .permissionDenied
    case ResultCode.SQLITE_CORRUPT.rawValue, ResultCode.SQLITE_NOTADB.rawValue: return .corrupted
    case ResultCode.SQLITE_BUSY.rawValue, ResultCode.SQLITE_LOCKED.rawValue: return .busy
    case ResultCode.SQLITE_IOERR.rawValue, ResultCode.SQLITE_CANTOPEN.rawValue: return .ioError
    case ResultCode.SQLITE_CONSTRAINT.rawValue: return .constraintViolation
    default: return .unknown(code: primaryCode)
    }
}
