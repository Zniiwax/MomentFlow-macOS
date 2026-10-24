#!/bin/bash
# 创建一个本地自签名代码签名证书，让屏幕录制权限能跨重新打包保留。
#
# 为什么需要：
#   adhoc 签名下 macOS 只能靠 cdhash 认这个 App，而 cdhash 包含二进制内容——
#   每重新打包一次就换一个身份，之前授的屏幕录制权限全部作废。
#   典型表现是反复弹权限框，或者录的时候报「用户拒绝了……TCC」。
#
#   换成证书签名之后，身份由证书决定、和二进制内容无关，授权一次就够了。
#
# 这个脚本会做三件事：
#   1. 生成一个 10 年有效的自签名证书（CN = "MomentFlow Local Signing"）
#   2. 导入登录钥匙串，并允许 codesign 免密使用它的私钥
#   3. 把它标记为「仅用于代码签名」的受信任证书
#
# 第 3 步可能会弹一次系统密码框——修改信任设置必须授权，这一步跳不掉。
# 影响范围只有这一张证书，不会动系统级信任设置，不需要 sudo。
#
# 撤销：
#   security delete-identity -c "MomentFlow Local Signing"
#   再打开「钥匙串访问」删掉同名证书即可。
set -euo pipefail

IDENTITY_NAME="MomentFlow Local Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

KEYCHAIN="$(security default-keychain -d user | tr -d '"')"
if [ -z "$KEYCHAIN" ] || [ ! -f "$KEYCHAIN" ]; then
    KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
fi

echo "钥匙串：$KEYCHAIN"
echo

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "✅ 已经存在可用的「${IDENTITY_NAME}」，不用重建。"
    exit 0
fi

# MARK: - 1/3 生成证书

echo "==> 1/3 生成自签名证书"
# 用配置文件而不是 -addext：系统自带的 LibreSSL 不认 -addext，
# 换成配置文件两边的 openssl 都能跑。
cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $IDENTITY_NAME

[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1

# MARK: - 2/3 导入钥匙串

echo "==> 2/3 导入钥匙串"
# 这里必须指定旧式 PBE。
# OpenSSL 3 的 pkcs12 默认用 AES-256 + SHA256，macOS 的安全框架读不了，
# 直接导入会报 "MAC verification failed during PKCS12 import"。
openssl pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY_NAME" \
    -out "$WORK/identity.p12" -passout pass:momentflow \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

security import "$WORK/identity.p12" \
    -k "$KEYCHAIN" -P momentflow \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# MARK: - 3/3 标记受信任

echo "==> 3/3 标记为受信任（可能会弹一次密码框）"
# 不加 -d：只写用户信任设置，不需要管理员权限。
# 不信任的话 codesign 会直接说 "no identity found"——这一步不能省。
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$KEYCHAIN" "$WORK/cert.pem" >/dev/null 2>&1 || {
    echo
    echo "⚠️ 自动加信任失败。手动来一下："
    echo "   打开「钥匙串访问」→ 找到「${IDENTITY_NAME}」→ 双击"
    echo "   → 展开「信任」→「代码签名」选「始终信任」→ 关闭时输入密码。"
    exit 1
}

echo
if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$IDENTITY_NAME"; then
    echo "✅ 完成。"
    security find-identity -v -p codesigning "$KEYCHAIN" | grep "$IDENTITY_NAME"
    echo
    echo "之后 ./Scripts/build_app.sh 会自动用它签名。"
    echo "重建一次 App，再去系统设置里授权屏幕录制——这次授权会一直有效。"
    echo
    echo "提示：第一次签名时如果弹出钥匙串访问请求，点「始终允许」，以后再问就不弹了。"
else
    echo "⚠️ 证书在，但仍未被当成有效的代码签名身份。"
    echo "   打开「钥匙串访问」手动确认「代码签名」是「始终信任」。"
    exit 1
fi
