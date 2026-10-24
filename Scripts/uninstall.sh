#!/bin/bash
# 卸载 MomentFlow。
#
# 默认只删除：App 本体、偏好设置。
# 不会删除任何录制文件 —— 它们是用户数据。
#
# 用法：
#   ./Scripts/uninstall.sh            # 删除 App 和偏好设置
#   ./Scripts/uninstall.sh --purge    # 另外删除本地签名证书
#   ./Scripts/uninstall.sh --dry-run  # 只打印会删什么，不动手

set -euo pipefail

APP_NAME="MomentFlow"
BUNDLE_ID="local.momentflow.app"
TARGET="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"
IDENTITY="MomentFlow Local Signing"

PURGE=0
DRY=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --dry-run) DRY=1 ;;
        *) echo "不认识的参数：$arg"; exit 1 ;;
    esac
done

run() {
    if [ "$DRY" -eq 1 ]; then
        echo "   [预演] $*"
    else
        "$@"
    fi
}

# 先读素材库位置，再删偏好设置 —— 这样还能告诉用户文件在哪。
LIBRARY="$(defaults read "$BUNDLE_ID" library.root 2>/dev/null || true)"
[ -z "$LIBRARY" ] && LIBRARY="$HOME/Desktop/MomentFlow"

echo
echo "==> 退出 MomentFlow"
if [ "$DRY" -eq 1 ]; then
    echo "   [预演] pkill -x $APP_NAME"
else
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.8
fi

echo "==> 删除 App"
if [ -d "$TARGET" ]; then
    run rm -rf "$TARGET"
    echo "   $TARGET"
else
    echo "   没有找到 $TARGET"
fi

echo "==> 删除偏好设置"
if [ -f "$PLIST" ]; then
    run rm -f "$PLIST"
    echo "   $PLIST"
    if [ "$DRY" -eq 0 ]; then
        killall cfprefsd 2>/dev/null || true
    fi
else
    echo "   没有找到 $PLIST"
fi

if [ "$PURGE" -eq 1 ]; then
    echo "==> 删除本地签名证书"
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
        run security delete-identity -c "$IDENTITY"
        echo "   $IDENTITY"
    else
        echo "   没有找到"
    fi
fi

cat <<DONE

==> 完成

没有动的东西：
  录制文件      $LIBRARY

还需要你手动做一步（系统不允许脚本代劳）：
  系统设置 → 隐私与安全性 → 录屏与系统录音
  → 选中 MomentFlow → 点列表下方的「−」

DONE
