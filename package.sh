#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Cliplet.xcodeproj"
SCHEME="Cliplet"
ARCH="${1:-arm64}"

fail() {
    printf '错误：%s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

[[ $# -le 1 ]] || fail "用法：./package.sh [arm64|x86_64]"
case "$ARCH" in
    arm64|x86_64) ;;
    *) fail "不支持的架构：$ARCH（可选：arm64、x86_64）" ;;
esac

DIST_DIR="$PROJECT_ROOT/dist"
DERIVED_DATA="$PROJECT_ROOT/build/PackageDerivedData-$ARCH"
MODULE_CACHE="$PROJECT_ROOT/build/ModuleCache"
APP_PATH="$DIST_DIR/Nimclip.app"
ARCHIVE_PATH="$DIST_DIR/Nimclip-macOS-$ARCH.zip"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
BUILT_APP_PATH="$DERIVED_DATA/Build/Products/Release/Nimclip.app"
OLD_APP_PATH="$DIST_DIR/Cliplet.app"
OLD_ARCHIVE_PATH="$DIST_DIR/Cliplet-macOS-$ARCH.zip"

[[ "$(uname -s)" == "Darwin" ]] || fail "该脚本只能在 macOS 上运行"
[[ -d "$PROJECT_PATH" ]] || fail "找不到项目：$PROJECT_PATH"
[[ -f "$PROJECT_ROOT/Application_logo/Nimclip-touming.png" ]] || fail "找不到 Logo：Application_logo/Nimclip-touming.png"

for command_name in swift xcodebuild codesign ditto lipo unzip shasum; do
    require_command "$command_name"
done

mkdir -p "$DIST_DIR" "$DERIVED_DATA" "$MODULE_CACHE/clang" "$MODULE_CACHE/swift"
rm -rf \
    "$APP_PATH" \
    "$OLD_APP_PATH" \
    "$DIST_DIR/Cliplet.swiftmodule" \
    "$DIST_DIR/Nimclip.app.dSYM"
rm -f "$OLD_ARCHIVE_PATH" "$ARCHIVE_PATH" "$CHECKSUM_PATH"

printf '[1/5] 生成 Logo、菜单栏图标和 AppIcon...\n'
(
    cd "$PROJECT_ROOT"
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE/clang" \
    SWIFT_MODULECACHE_PATH="$MODULE_CACHE/swift" \
        swift Design/generate_app_icon.swift
)

printf '[2/5] 构建 %s Release...\n' "$ARCH"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE/clang" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE/swift" \
    xcodebuild \
        -quiet \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        ARCHS="$ARCH" \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGNING_ALLOWED=NO \
        clean build

[[ -x "$BUILT_APP_PATH/Contents/MacOS/Nimclip" ]] || fail "构建完成但未找到 Nimclip.app"
if ! lipo "$BUILT_APP_PATH/Contents/MacOS/Nimclip" -verify_arch "$ARCH"; then
    fail "构建产物不包含目标架构：$ARCH"
fi
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
printf '%s  %s\n' "$CHECKSUM" "$(basename "$ARCHIVE_PATH")" > "$CHECKSUM_PATH"

printf '\n打包完成：\n'
printf '  架构：%s\n' "$ARCH"
printf '  应用：%s\n' "$APP_PATH"
printf '  压缩包：%s\n' "$ARCHIVE_PATH"
printf '  校验文件：%s\n' "$CHECKSUM_PATH"
printf '  SHA-256：%s\n' "$CHECKSUM"
