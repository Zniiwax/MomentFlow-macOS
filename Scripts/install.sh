#!/bin/bash
# MomentFlow 一键安装。
#
# 用法（复制整行到"终端"里回车）：
#   curl -fsSL https://raw.githubusercontent.com/Zniiwax/MomentFlow-macOS/main/Scripts/install.sh | bash
#
# 它做的事：检查环境 → 下载源码 → 编译 → 装到 ~/Applications → 打开。
# 不需要管理员密码，也不会向系统目录写任何东西。

set -euo pipefail

OWNER="Zniiwax"
REPO="MomentFlow-macOS"
APP_NAME="MomentFlow"
ARCHIVE="https://github.com/${OWNER}/${REPO}/archive/refs/heads/main.tar.gz"
DEST="${HOME}/Applications"

bold() { printf "\n\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\n\033[33m%s\033[0m\n" "$*"; }
die()  { printf "\n\033[31m%s\033[0m\n\n" "$*"; exit 1; }

bold "==> 1/5 检查系统"
if [ "$(uname -s)" != "Darwin" ]; then
    die "这个应用只能在 macOS 上运行。"
fi

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if [ "${MACOS_MAJOR}" -lt 14 ] 2>/dev/null; then
    die "需要 macOS 14 或更高版本，你当前是 ${MACOS_VERSION}。"
fi
echo "    macOS ${MACOS_VERSION}"

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    warn "还需要安装 Apple 的命令行开发工具（编译用，约 1-2 GB，一次性）。"
    echo "   现在会弹出安装窗口，点「安装」并等待完成，然后重新运行本命令。"
    xcode-select --install 2>/dev/null || true
    exit 0
fi
echo "    Swift $(swift --version 2>/dev/null | head -1 | sed 's/.*Swift version //;s/ .*//')"

bold "==> 2/5 下载源码"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
    "$ARCHIVE" -o "$WORK/src.tar.gz" \
    || die "下载失败。请检查网络，或改用 README 里的备用安装命令。"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -type d -name "${REPO}-*" | head -1)"
[ -d "$SRC" ] || die "解压失败。"
echo "    已下载到临时目录"

bold "==> 3/5 编译（大约 1 分钟）"
cd "$SRC"
if [ -x "./Scripts/build_app.sh" ]; then
    ./Scripts/build_app.sh >/dev/null 2>&1 || die "编译失败。请把以上信息反馈给作者。"
else
    swift build -c release >/dev/null 2>&1
fi
[ -d "Dist/${APP_NAME}.app" ] || die "没有找到编译产物。"
echo "    编译完成"

bold "==> 4/5 安装到 ${DEST}"
mkdir -p "$DEST"
pkill -x "$APP_NAME" 2>/dev/null || true
if [ -d "${DEST}/${APP_NAME}.app" ]; then
    rm -rf "${DEST}/${APP_NAME}.app"
fi
cp -R "Dist/${APP_NAME}.app" "${DEST}/"
echo "    已安装：${DEST}/${APP_NAME}.app"

bold "==> 5/5 完成"
if [ "${MOMENTFLOW_NO_LAUNCH:-}" != "1" ]; then
    open "${DEST}/${APP_NAME}.app"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || true
fi

cat <<'DONE'

接下来还有两步（系统安全限制，任何录屏软件都躲不掉）：

  1. 在「系统设置 → 隐私与安全性 → 录屏与系统录音」里，
     找到 MomentFlow 并打开开关。
     如果列表里没有，点列表下方的「+」，选择：
     ~/Applications/MomentFlow.app

  2. 退出 MomentFlow，再重新打开一次。
     屏幕录制权限只在程序启动时读取。

之后按 ⌘⇧R 就能录当前窗口了。
DONE
