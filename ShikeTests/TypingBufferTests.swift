// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.5：呼出即打字（app-shell.md「组件契约」、03 §4）。
/// NSTextView.keyDown → insertText 不依赖窗口与焦点，回放测试直接用文档视图。
@MainActor
struct TypingBufferTests {
    // - MARK: 判断与上限（纯函数）

    private func event(characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
        )!
    }

    @Test("isTypingEvent：可打印与 Shift 组合算打字；裸回车入缓冲；⌘/⌃ 组合与控制字符不算")
    func typingEventClassification() {
        #expect(TypingBuffer.isTypingEvent(modifiers: [], characters: "a"))
        #expect(TypingBuffer.isTypingEvent(modifiers: [.shift], characters: "A"))
        #expect(TypingBuffer.isTypingEvent(modifiers: [], characters: "中"))
        #expect(TypingBuffer.isTypingEvent(modifiers: [.option], characters: "å")) // ⌥ 组合（输出字符）算打字
        #expect(TypingBuffer.isTypingEvent(modifiers: [], characters: "\r")) // 裸回车入缓冲（AC：回放执行提交）
        #expect(TypingBuffer.isTypingEvent(modifiers: [.shift], characters: "\r")) // ⇧↩ 也缓冲（回放按提交，见 TypingBuffer 注释）
        #expect(!TypingBuffer.isTypingEvent(modifiers: [.command], characters: "\r")) // ⌘↩ 是命令
        #expect(!TypingBuffer.isTypingEvent(modifiers: [.command], characters: "a")) // ⌘A 是命令
        #expect(!TypingBuffer.isTypingEvent(modifiers: [.control], characters: "a"))
        #expect(!TypingBuffer.isTypingEvent(modifiers: [], characters: "\t")) // 控制字符
        #expect(!TypingBuffer.isTypingEvent(modifiers: [], characters: ""))
        #expect(!TypingBuffer.isTypingEvent(modifiers: [], characters: nil))
    }

    @Test("缓冲上限：超过 200 丢弃最早的")
    func bufferLimitDropsOldest() {
        let oldest = event(characters: "1")
        var buffer: [NSEvent] = [oldest]
        for ascii in UInt8(2)...201 { // 再推 200 个，共 201
            buffer = TypingBuffer.appended(buffer, with: event(characters: String(UnicodeScalar(ascii))), limit: 200)
        }
        #expect(buffer.count == 200)
        // 最早的 "1" 被丢弃，现在的第一项是第二个推入的事件（UnicodeScalar 2）
        #expect(buffer.first?.characters == String(UnicodeScalar(2)))
        buffer = TypingBuffer.appended(buffer, with: event(characters: "z"), limit: 200)
        #expect(buffer.count == 200)
        #expect(buffer.last?.characters == "z")
        #expect(buffer.first?.characters == String(UnicodeScalar(3))) // 又丢一个最早的
    }

    // - MARK: 缓冲与回放

    @Test("enqueue 后回放：字符按序进入文本视图，缓冲清空；空缓冲回放为无操作")
    func replayReplaysInOrderAndClears() throws {
        let buffer = TypingBuffer()
        buffer.enqueue(event(characters: "买"))
        buffer.enqueue(event(characters: "奶"))
        buffer.enqueue(event(characters: "牛"))

        let scrollView = NSTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? NSTextView)

        buffer.replayPendingEvents(in: textView)
        #expect(textView.string == "买奶牛")
        #expect(buffer.pendingEvents.isEmpty)

        // 空缓冲：无操作
        buffer.replayPendingEvents(in: textView)
        #expect(textView.string == "买奶牛")
    }

    @Test("reset：丢弃缓冲（面板收起语义）")
    func resetDiscardsPending() {
        let buffer = TypingBuffer()
        buffer.enqueue(event(characters: "a"))
        buffer.reset()
        #expect(buffer.pendingEvents.isEmpty)
    }

    @Test("captureDidBegin/End：就绪标志的复位路径（AppEnvironment 组装验证）")
    func captureWindowLifecycle() throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        let model = environment.panelModel
        #expect(model.isCaptureReady == false)

        model.beginCaptureWindow()
        #expect(model.isCaptureReady == false)

        // 就绪：置位（真实回放闭包未接，注入计数替身）
        var replayCount = 0
        model.replayBufferedKeys = { _ in replayCount += 1 }
        let textView = NSTextView()
        model.captureDidBecomeReady(textView)
        #expect(model.isCaptureReady == true)
        #expect(replayCount == 1)

        model.endCaptureWindow()
        #expect(model.isCaptureReady == false)
    }
}
