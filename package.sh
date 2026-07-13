#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Cliplet.xcodeproj"
SCHEME="Cliplet"
DIST_DIR="$PROJECT_ROOT/dist"
DERIVED_DATA="$PROJECT_ROOT/build/PackageDerivedData"
MODULE_CACHE="$PROJECT_ROOT/build/ModuleCache"
APP_PATH="$DIST_DIR/Nimclip.app"
ARCHIVE_PATH="$DIST_DIR/Nimclip-macOS-arm64.zip"
BUILT_APP_PATH="$DERIVED_DATA/Build/Products/Release/Nimclip.app"
OLD_APP_PATH="$DIST_DIR/Cliplet.app"
OLD_ARCHIVE_PATH="$DIST_DIR/Cliplet-macOS-arm64.zip"

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "该脚本只能在 macOS 上运行"
[[ -d "$PROJECT_PATH" ]] || fail "找不到项目：$PROJECT_PATH"
[[ -f "$PROJECT_ROOT/Application_logo/Nimclip-touming.png" ]] || fail "找不到 Logo：Application_logo/Nimclip-touming.png"

for command_name in swift xcodebuild codesign ditto unzip shasum; do
    require_command "$command_name"
done

mkdir -p "$DIST_DIR" "$DERIVED_DATA" "$MODULE_CACHE/clang" "$MODULE_CACHE/swift"
rm -rf \
    "$APP_PATH" \
    "$OLD_APP_PATH" \
    "$DIST_DIR/Cliplet.swiftmodule" \
    "$DIST_DIR/Nimclip.app.dSYM"
rm -f "$OLD_ARCHIVE_PATH" "$ARCHIVE_PATH"

printf '[1/5] 生成 Logo、菜单栏图标和 AppIcon...\n'
(
    cd "$PROJECT_ROOT"
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE/clang" \
    SWIFT_MODULECACHE_PATH="$MODULE_CACHE/swift" \
        swift Design/generate_app_icon.swift
)

printf '[2/5] 构建 arm64 Release...\n'
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE/clang" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE/swift" \
    xcodebuild \
        -quiet \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGNING_ALLOWED=NO \
        clean build

[[ -x "$BUILT_APP_PATH/Contents/MacOS/Nimclip" ]] || fail "构建完成但未找到 Nimclip.app"
ditto "$BUILT_APP_PATH" "$APP_PATH"
[[ -x "$APP_PATH/Contents/MacOS/Nimclip" ]] || fail "无法将 Nimclip.app 复制到 dist"

printf '[3/5] 添加本机 ad-hoc 签名...\n'
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

printf '[4/5] 生成 ZIP 软件包...\n'
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

printf '[5/5] 校验压缩包...\n'
unzip -tq "$ARCHIVE_PATH"
CHECKSUM="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"

printf '\n打包完成：\n'
printf '  应用：%s\n' "$APP_PATH"
printf '  压缩包：%s\n' "$ARCHIVE_PATH"
printf '  SHA-256：%s\n' "$CHECKSUM"
