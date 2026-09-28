#!/usr/bin/env bash
# Shike（拾刻）
# Copyright (C) 2026 Shike contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# 架构合规检查（conventions.md「检查项」）。本地与 CI（checks 作业）运行同一份。
# 用法：
#   bash scripts/checks.sh              # 检查当前仓库
#   bash scripts/checks.sh --self-check # 构造违规样例，逐条验证规则会失败（checks 作业先跑这个）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIOLATIONS=0

# 报告一条违规并累计；不中断，把所有违规一次报完。
fail() {
    echo "✗ [$1] $2" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
}

# 可选访问级别修饰 + import 的公共前缀：conventions 要求"包括带 @testable
# 或访问级别修饰的写法"都要被识别。
import_re() {
    printf '%s' '^[[:space:]]*(@testable[[:space:]]+)?((internal|public|fileprivate|private)[[:space:]]+)?import[[:space:]]+'
}

# 用法：check_swift_headers <仓库根>
# 规则：Shike/、ShikeTests/、Packages/ShikeKit/、scripts/ 中每个 .swift、.sh 文件
# 的前 5 行包含 SPDX-License-Identifier: GPL-3.0-only（Package.swift 的第一行是
# swift-tools-version，文件头紧随其后，同样在前 5 行内）；
# 含"源自 Reminders MenuBar"的文件，其仓库内路径必须出现在 NOTICE.md 中。
check_swift_headers() {
    local root="$1"
    local file
    while IFS= read -r file; do
        if ! head -n 5 "$file" | grep -q "SPDX-License-Identifier: GPL-3.0-only"; then
            fail "文件头" "${file#"$root"/} 的前 5 行没有 SPDX-License-Identifier: GPL-3.0-only"
        fi
    done < <(find "$root/Shike" "$root/ShikeTests" "$root/Packages/ShikeKit" "$root/scripts" \
        \( -name "*.swift" -o -name "*.sh" \) 2>/dev/null | grep -v "/.build/" | sort)

    # 排除本脚本：其中的规则字符串会自我命中
    local ported rel
    while IFS= read -r ported; do
        rel="${ported#"$root"/}"
        if ! grep -qF "$rel" "$root/NOTICE.md"; then
            fail "文件头" "移植文件 $rel 未登记到 NOTICE.md（要求登记文件路径）"
        fi
    done < <(grep -rl "源自 Reminders MenuBar" \
        "$root/Shike" "$root/ShikeTests" "$root/Packages/ShikeKit" "$root/scripts" 2>/dev/null \
        | grep -v "/.build/" | grep -v "scripts/checks.sh" | sort)
}

# 用法：check_imports <仓库根>
# 规则：导入边界（conventions.md 检查项 2）。
check_imports() {
    local root="$1"
    local match
    while IFS= read -r match; do
        fail "导入边界" "ShikeKit 中不允许 import AppKit/SwiftUI/Cocoa/UIKit/Carbon：${match%%:*}"
    done < <(grep -rEn "$(import_re)(AppKit|SwiftUI|Cocoa|UIKit|Carbon)\b" \
        "$root/Packages/ShikeKit" 2>/dev/null | grep -v "/.build/")

    while IFS= read -r match; do
        fail "导入边界" "App 层不允许 import GRDB：${match%%:*}"
    done < <(grep -rEn "$(import_re)GRDB\b" \
        "$root/Shike" "$root/ShikeTests" 2>/dev/null)

    # ShikeData 里凡引入 GRDB 必须是 internal import；裸 import、public 等一律违规
    while IFS= read -r match; do
        fail "导入边界" "ShikeData 中引入 GRDB 只能写 internal import GRDB：${match%%:*}"
    done < <(grep -rEn '^[[:space:]]*(@testable[[:space:]]+)?((public|fileprivate|private)[[:space:]]+)?import[[:space:]]+GRDB\b' \
        "$root/Packages/ShikeKit/Sources/ShikeData" 2>/dev/null)

    while IFS= read -r match; do
        fail "导入边界" "ShikeDateParser 只 import Foundation：${match%%:*}"
    done < <(grep -rEn "$(import_re)" \
        "$root/Packages/ShikeKit/Sources/ShikeDateParser" 2>/dev/null | grep -vE "import[[:space:]]+Foundation\b")
}

# 用法：check_parser_region <仓库根>
# 规则：解析器源码不读取系统的日历与区域设置（conventions.md 检查项 3）。
check_parser_region() {
    local root="$1"
    local match
    while IFS= read -r match; do
        fail "解析器区域" "解析器不得读取系统日历/区域：${match%%:*}"
    done < <(grep -rnE "Calendar\.current|Locale\.current|autoupdatingCurrent" \
        "$root/Packages/ShikeKit/Sources/ShikeDateParser" 2>/dev/null)
}

# 用法：check_forbidden <仓库根>
# 规则：禁用项（conventions.md 检查项 4）。
check_forbidden() {
    local root="$1"
    local match
    while IFS= read -r match; do
        fail "禁用项" "不允许使用 eraseDatabaseOnSchemaChange：${match%%:*}"
    done < <(grep -rn "eraseDatabaseOnSchemaChange" \
        "$root/Shike" "$root/ShikeTests" "$root/Packages/ShikeKit" 2>/dev/null | grep -v "/.build/")

    while IFS= read -r match; do
        fail "禁用项" "App 中不允许全局单例（static shared）：${match%%:*}"
    done < <(grep -rEn "static[[:space:]]+(let|var)[[:space:]]+shared\b" "$root/Shike" 2>/dev/null)
}

# 真实检查前先确认四个检查根存在：目录缺失时静默空转会伪装成通过。
require_roots() {
    local dir
    for dir in Shike ShikeTests Packages/ShikeKit scripts; do
        if [ ! -d "$1/$dir" ]; then
            fail "检查环境" "检查根目录不存在：$1/$dir"
        fi
    done
    if [ ! -f "$1/NOTICE.md" ]; then
        fail "检查环境" "NOTICE.md 不存在，移植登记无从核对"
    fi
}

# 用法：run_all_checks <仓库根>
run_all_checks() {
    check_swift_headers "$1"
    check_imports "$1"
    check_parser_region "$1"
    check_forbidden "$1"
}

# 自检：为每条规则构造违规样例，断言样例被对应规则命中；
# 另放一个合规文件做正向对照，确认规则没有过宽误报。
self_check() {
    local sandbox
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox/Shike/App" "$sandbox/ShikeTests" "$sandbox/scripts" \
        "$sandbox/Packages/ShikeKit/Sources/ShikeDateParser" \
        "$sandbox/Packages/ShikeKit/Sources/ShikeData" \
        "$sandbox/Packages/ShikeKit/Tests"

    : > "$sandbox/NOTICE.md"   # 存在但不含登记：移植样例应因"未登记"而失败

    local header='// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
'

    # 违规样例：路径 -> 期望命中的规则
    printf '// 无文件头的文件\nimport Foundation\n' > "$sandbox/Shike/App/Bare.swift"
    printf '%s\n// 源自 Reminders MenuBar\nimport Foundation\n' "$header" > "$sandbox/Shike/App/Ported.swift"
    printf '%simport AppKit\n' "$header" > "$sandbox/Packages/ShikeKit/Sources/ShikeData/BadImport.swift"
    printf '%spublic import AppKit\n' "$header" > "$sandbox/Packages/ShikeKit/Sources/ShikeData/ModifierImport.swift"
    printf '%simport GRDB\n' "$header" > "$sandbox/Shike/App/BadGRDB.swift"
    printf '%spublic import GRDB\n' "$header" > "$sandbox/Packages/ShikeKit/Sources/ShikeData/PublicGRDB.swift"
    printf '%simport SwiftUI\n' "$header" > "$sandbox/Packages/ShikeKit/Sources/ShikeDateParser/BadModule.swift"
    printf '%slet c = Calendar.current\n' "$header" > "$sandbox/Packages/ShikeKit/Sources/ShikeDateParser/Region.swift"
    printf '%slet c = eraseDatabaseOnSchemaChange\n' "$header" > "$sandbox/Shike/App/Forbidden.swift"
    printf '%sfinal class A { static let shared = A() }\n' "$header" > "$sandbox/Shike/App/Singleton.swift"
    printf '#!/usr/bin/env bash\n# 无文件头的脚本\n' > "$sandbox/scripts/bare.sh"

    # 正向对照：完全合规的文件不得出现在违规输出中
    printf '%simport Foundation\n' "$header" > "$sandbox/ShikeTests/Clean.swift"

    local log
    log="$(mktemp)"
    VIOLATIONS=0 run_all_checks "$sandbox" 2> "$log"

    local failures=0
    assert_reported "$log" "文件头" "Bare.swift" || failures=$((failures + 1))
    assert_reported "$log" "文件头" "Ported.swift" || failures=$((failures + 1))
    assert_reported "$log" "导入边界" "BadImport.swift" || failures=$((failures + 1))
    assert_reported "$log" "导入边界" "ModifierImport.swift" || failures=$((failures + 1))
    assert_reported "$log" "导入边界" "BadGRDB.swift" || failures=$((failures + 1))
    assert_reported "$log" "导入边界" "PublicGRDB.swift" || failures=$((failures + 1))
    assert_reported "$log" "导入边界" "BadModule.swift" || failures=$((failures + 1))
    assert_reported "$log" "解析器区域" "Region.swift" || failures=$((failures + 1))
    assert_reported "$log" "禁用项" "Forbidden.swift" || failures=$((failures + 1))
    assert_reported "$log" "禁用项" "Singleton.swift" || failures=$((failures + 1))
    assert_reported "$log" "文件头" "bare.sh" || failures=$((failures + 1))

    if grep -q "Clean.swift" "$log"; then
        echo "✗ 自检：合规对照文件 Clean.swift 被误报" >&2
        failures=$((failures + 1))
    fi

    rm -rf "$sandbox" "$log"

    if [ "$failures" -ne 0 ]; then
        echo "✗ 自检失败：$failures 个样例断言未满足" >&2
        exit 1
    fi
    echo "✓ 自检通过：11 个违规样例各被对应规则命中，合规对照未被误报"
}

# 用法：assert_reported <日志> <规则名> <样例文件名>；该样例必须被该规则报出。
assert_reported() {
    if grep -q "\[$2\].*$3" "$1"; then
        return 0
    fi
    echo "✗ 自检：样例 $3 未被规则「$2」命中" >&2
    return 1
}

main() {
    case "${1:-}" in
        "")
            require_roots "$REPO_ROOT"
            VIOLATIONS=0
            run_all_checks "$REPO_ROOT"
            if [ "$VIOLATIONS" -gt 0 ]; then
                echo "✗ 检查失败：$VIOLATIONS 处违规" >&2
                exit 1
            fi
            echo "✓ 检查通过：文件头、导入边界、解析器区域、禁用项"
            ;;
        --self-check)
            VIOLATIONS=0
            self_check
            ;;
        *)
            echo "用法：checks.sh [--self-check]；未知参数：$1" >&2
            exit 2
            ;;
    esac
}

main "$@"
