#!/bin/bash
# 构建 .app 包。
#
# 菜单栏应用也必须打包成 bundle：屏幕录制 / 麦克风权限是发给「App」的，
# 直接跑裸可执行文件的话，系统会按终端去授权，换个终端权限就没了。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="MomentFlow"
DISPLAY_NAME="灵感捕捉器"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
APP="$ROOT/Dist/$APP_NAME.app"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "==> 提示：缺少 Resources/AppIcon.icns（可运行 swift Scripts/GenerateIcon.swift 生成）"
fi

# 菜单栏用的是自己画的模板图标，和 App 图标是同一套视觉语言。
if [ -f "$ROOT/Resources/MenuBarIcon.png" ]; then
    cp "$ROOT/Resources/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
fi

# 三级签名策略，从好到差：
#
#   1. Developer ID（Apple 开发者证书）→ 能公证、能给别人用
#   2. 本地自签名证书               → 只能自己用，但权限能跨重打包保留
#   3. ad-hoc                       → 每次重打包都会让屏幕录制权限失效
#
# 之所以要分级，是因为 ad-hoc 签名下 macOS 只能靠 cdhash 认这个 App，
# 而 cdhash 每次重打包都会变；有证书之后身份才是稳定的。
SIGNED=0

if command -v codesign >/dev/null 2>&1; then
    # 1) Developer ID：可分发
    # 末尾的 `|| true` 不能省：脚本开了 set -e + pipefail，
    # 没装 Developer ID 证书时 grep 找不到东西会返回非零，
    # 整个脚本就会在这里静悄悄退出，App 连签名都没有。
    DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/^[^"]*"([^"]*)".*$/\1/' || true)"
    if [ -n "${DEVELOPER_ID}" ]; then
        # hardened runtime 是公证的硬性要求。
        if codesign --force --deep --options runtime --sign "${DEVELOPER_ID}" "$APP" >/dev/null 2>&1; then
            SIGNED=1
            echo "==> 已用 Developer ID「${DEVELOPER_ID}」签名（可公证、可分发给别人）"
        fi
    fi

    # 2) 本地自签名证书：本机可用，权限稳定
    LOCAL_IDENTITY="MomentFlow Local Signing"
    if [ "$SIGNED" -eq 0 ] \
        && security find-identity -v -p codesigning 2>/dev/null | grep -q "${LOCAL_IDENTITY}"; then
        if codesign --force --deep --sign "${LOCAL_IDENTITY}" "$APP" >/dev/null 2>&1; then
            SIGNED=1
            # 变量用 ${} 包起来：后面紧跟中文标点时，bash 会把标点的
            # 首字节算进变量名，报 "unbound variable"。
            echo "==> 已用本地证书「${LOCAL_IDENTITY}」签名（权限可跨重打包保留）"
        fi
    fi

    # 3) 兜底
    if [ "$SIGNED" -eq 0 ]; then
        codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
            && echo "==> 已做 ad-hoc 签名" \
            || echo "==> 跳过签名（不影响本机运行）"
        echo "    注意：ad-hoc 签名下，每次重新打包都会让屏幕录制权限失效。"
        echo "    跑一次 ./Scripts/setup_signing.sh 可以一劳永逸。"
    fi
fi

echo "==> 完成：$APP"
echo "运行：open \"$APP\""
echo "提示：首次运行会要屏幕录制权限，授权后需要退出重开。"
