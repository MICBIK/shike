// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 同一条便签的三面编辑互斥（W4，docs/03 §16.7 的 UI 层补充）：
/// 面板行/主窗口行/卡片正文可同时进入同一条便签的编辑，先保存方的文字会被
/// 后保存方静默覆盖（数据层"后保存者覆盖"契约保留不改，见 §16.7:318）。
/// 仲裁规则是"后来者拿走，不弹窗不拒绝"：新面 claim 时，若该便签正被其他面
/// 编辑，先调用对方注册的结束闭包（触发各自的保存语义），再授权给新面——
/// 用户点了哪里，哪里拿到编辑。per-note 粒度：不同便签各编辑各的，互不干扰。
///
/// 实例为 App 环境级单份（AppEnvironment 装配注入），不做全局单例。
/// 结束闭包全部幂等（endEditingIfNeeded/takePendingEdit/endEditing(save:)
/// 对"不在编辑"都是无害空操作）；条目不做显式注销——过期条目经 isEditing
/// 探活自愈（探活为 false 即静默让位），漏掉某条结束路径也不会误伤他人。
@MainActor
final class EditArbiter {
    /// 编辑面的身份。
    enum Owner: Equatable {
        case panel
        case mainWindow
        case card
    }

    /// 一条在编记录：owner + 探活（该面是否仍在编辑这条）+ 结束编辑（触发保存）。
    private struct Entry {
        let owner: Owner
        let isEditing: () -> Bool
        let endEditing: () -> Void
    }

    /// 按 noteID 记当前编辑面（会话级，不持久化；量级=曾编辑过的便签数）。
    private var entries: [Note.ID: Entry] = [:]

    /// claim 一条便签的编辑权：目标正被其他面编辑时先让对方收尾（保存），
    /// 再授权给新 owner。同面重复 claim（已在编辑本行）不动既有记录。
    /// 先写新条目再调旧结束闭包：旧闭包内部不回调仲裁器，无重入风险。
    func claim(
        noteID: Note.ID,
        owner: Owner,
        isEditing: @escaping () -> Bool,
        endEditing: @escaping () -> Void
    ) {
        let previous = entries[noteID]
        entries[noteID] = Entry(owner: owner, isEditing: isEditing, endEditing: endEditing)
        if let previous, previous.owner != owner, previous.isEditing() {
            previous.endEditing()
        }
    }

    /// 测试与诊断：某条便签当前的编辑面（无则 nil）。
    func currentOwner(noteID: Note.ID) -> Owner? {
        entries[noteID]?.owner
    }
}
