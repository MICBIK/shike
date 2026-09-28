// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// Story 1.3：SQLite 主结果码 → DataFailureReason 与 data-layer.md「错误分类」表一一对应。
/// newerSchema（hasBeenSuperseded）、invalidLocation（URL 校验）与 simulated（仓储写路径，
/// Story 1.4 起产生）不经过结果码映射，各有专项测试。
struct ErrorMappingTests {
    private func reason(forCode rawValue: Int32) -> DataFailureReason {
        mapResultCode(rawValue)
    }

    @Test("分类表中的每个主结果码都映射到对应原因")
    func mapsDocumentedCodes() {
        #expect(reason(forCode: 13) == .diskFull)             // SQLITE_FULL
        #expect(reason(forCode: 8) == .readOnly)              // SQLITE_READONLY
        #expect(reason(forCode: 3) == .permissionDenied)      // SQLITE_PERM
        #expect(reason(forCode: 23) == .permissionDenied)     // SQLITE_AUTH
        #expect(reason(forCode: 11) == .corrupted)            // SQLITE_CORRUPT
        #expect(reason(forCode: 26) == .corrupted)            // SQLITE_NOTADB
        #expect(reason(forCode: 5) == .busy)                  // SQLITE_BUSY
        #expect(reason(forCode: 6) == .busy)                  // SQLITE_LOCKED
        #expect(reason(forCode: 10) == .ioError)              // SQLITE_IOERR
        #expect(reason(forCode: 14) == .ioError)              // SQLITE_CANTOPEN
        #expect(reason(forCode: 19) == .constraintViolation)  // SQLITE_CONSTRAINT
    }

    @Test("表外的代码映射为 unknown(code:)，扩展码先屏蔽到主码")
    func mapsUnknownCodesAndMasksExtendedOnes() {
        #expect(reason(forCode: 1) == .unknown(code: 1))      // SQLITE_ERROR
        #expect(reason(forCode: 2) == .unknown(code: 2))      // SQLITE_INTERNAL
        #expect(mapFailure(DatabaseError(resultCode: .init(rawValue: 1299))) == .constraintViolation) // SQLITE_CONSTRAINT_NOTNULL
    }

    @Test("文件系统错误：权限问题归 permissionDenied，其余归 ioError")
    func mapsFileSystemErrors() {
        #expect(mapFailure(CocoaError(.fileWriteNoPermission)) == .permissionDenied)
        #expect(mapFailure(CocoaError(.fileReadUnknown)) == .ioError)

        let posixDenied = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        #expect(mapFailure(posixDenied) == .permissionDenied)

        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS)),
        ])
        #expect(mapFailure(wrapped) == .permissionDenied)
    }
}
