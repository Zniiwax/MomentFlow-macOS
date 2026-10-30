#!/bin/bash
# 把本机已安装的 MomentFlow 更新到当前代码。
#
# 做的事：拉最新代码（如果是 git 仓库）→ 编译 → 替换 ~/Applications 里的那份 → 重启。
#
# 用法（在项目根目录）：
#   ./Scripts/update.sh
#
# 注意：脚本会先退出正在运行的 MomentFlow。录制中请先停止。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MomentFlow"
DEST="$HOME/Applications"
TARGET="$DEST/$APP_NAME.app"

bold() { printf "\n\033[1m%s\033[0m\n" "$*"; }

bold "==> 1/4 同步代码"
if [ -d .git ]; then
    git pull --ff-only || echo "   拉取失败，用当前本地代码继续"
else
    echo "   不是 git 仓库，直接用当前目录的代码"
fi
echo "   当前提交：$(git rev-parse --short HEAD 2>/dev/null || echo '（无）')"

bold "==> 2/4 编译"
./Scripts/build_app.sh >/dev/null
echo "   完成"

bold "==> 3/4 替换已安装的版本"
mkdir -p "$DEST"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.6

BACKUP="$DEST/.${APP_NAME}.app.old"
if [ -d "$TARGET" ]; then
    rm -rf "$BACKUP"
    mv "$TARGET" "$BACKUP"
fi
cp -R "Dist/$APP_NAME.app" "$DEST/"
rm -rf "$BACKUP"
rm -rf "Dist/$APP_NAME.app"
echo "   $TARGET"

bold "==> 4/4 启动"
open "$TARGET"
sleep 2
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "   运行中：$(ps -o comm= -p "$(pgrep -x "$APP_NAME" | head -1)")"
else
    echo "   没起来，检查一下权限设置"
fi

cat <<'DONE'

提示：
  · 如果之前跑过 ./Scripts/setup_signing.sh，更新后屏幕录制权限会保留。
  · 只用过 ad-hoc 签名的话，系统可能把你当成新 App，需要重新授权一次。
DONE
