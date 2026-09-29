// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 搜索（S2-09，03 §8）：搜索框替换输入框位置；结果分「便签」「待办」两组，
/// 匹配文字高亮；点击结果切模式并定位；Esc 退出。
struct SearchView: View {
    @Bindable var model: PanelModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: .searchPlaceholder),
                    text: $model.searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFieldFocused)
                .onSubmit {
                    model.runSearch() // 防抖之外，回车立即检索
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            searchResults
        }
        .onAppear {
            isFieldFocused = true
            model.runSearch() // 恢复已有关键词时立即检索
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Spacer()
        } else if model.searchNoteResults.isEmpty, model.searchTodoResults.isEmpty {
            VStack(spacing: 8) {
                Text(String(localized: .searchEmpty(model.searchQuery)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(String(localized: .searchClear)) {
                    model.searchQuery = ""
                    isFieldFocused = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if !model.searchNoteResults.isEmpty {
                    Section(String(localized: .listGroupNotes)) {
                        ForEach(model.searchNoteResults) { note in
                            SearchRow(
                                text: note.content,
                                query: model.searchQuery,
                                title: nil
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.locateSearchResult(note: note)
                            }
                            .id(note.uuid.uuidString)
                        }
                    }
                }
                if !model.searchTodoResults.isEmpty {
                    Section(String(localized: .listGroupTodos)) {
                        ForEach(model.searchTodoResults) { todo in
                            SearchRow(
                                text: todo.title,
                                query: model.searchQuery,
                                title: nil
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.locateSearchResult(todoUUID: todo.uuid)
                            }
                            .id(todo.uuid.uuidString)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

/// 搜索结果行：匹配子串高亮（不区分大小写，全部命中处）。
struct SearchRow: View {
    let text: String
    let query: String
    let title: String?

    /// 命中区间（UTF-16，不区分大小写）；纯函数供 L2 复用。
    static func matchRanges(text: String, query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    var body: some View {
        let ranges = Self.matchRanges(text: text, query: query)
        HStack {
            if ranges.isEmpty {
                Text(text).font(.system(size: 13))
            } else {
                highlightedText(ranges: ranges).font(.system(size: 13))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func highlightedText(ranges: [Range<String.Index>]) -> Text {
        var attributed = AttributedString(text)
        for range in ranges {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = .accentColor.opacity(0.30)
            }
        }
        return Text(attributed)
    }
}
