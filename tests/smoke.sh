#!/usr/bin/env bash
# 설치를 마친 Dots 클라우드 컴퓨터에서 실제 네트워크와 패키지 설치를 확인합니다.
# 사용법: bash tests/smoke.sh [패키지 (기본 pv)] [실행 파일 이름 (기본 패키지 이름)]
set -euo pipefail
TSNET_DIR="${TSNET_DIR:-$HOME/.tsnet}"
# 0.1.1 까지의 기본 위치(/workspace/.tsnet)에 설치했다면 그쪽을 씁니다.
[ -f "$TSNET_DIR/env.sh" ] || [ ! -f /workspace/.tsnet/env.sh ] || TSNET_DIR=/workspace/.tsnet
# shellcheck source=/dev/null
. "$TSNET_DIR/env.sh"
PKG="${1:-pv}"
BIN="${2:-$PKG}"
pass() { printf '  통과: %s\n' "$*"; }
fail() { printf '  실패: %s\n' "$*" >&2; exit 1; }

echo "[1] 상태"
tsnet status

echo "[2] 프록시 경유 HTTPS"
code="$(curl -sS -m 30 -o /dev/null -w '%{http_code}' https://deb.debian.org/debian/ || true)"
[ "$code" = 200 ] || fail "deb.debian.org 응답 $code"
pass "deb.debian.org HTTP $code"

echo "[3] apt-get 연결"
[ "$(readlink -f "$(type -P apt-get)")" = "$(readlink -f "$TSNET_DIR/bin/tsapt")" ] || fail "apt-get 이 tsapt 를 가리키지 않습니다"
pass "apt-get -> tsapt"

echo "[4] apt-get update"
apt-get update -q > /dev/null || fail "apt-get update"
pass "목록 갱신"

if type -P "$BIN" > /dev/null && ! tsapt list | grep -q "^$PKG "; then
  echo "  $BIN 이 이미 시스템에 있어 설치 확인을 건너뜁니다. 다른 패키지를 인자로 주세요."
  exit 0
fi

echo "[5] apt-get install -y $PKG"
apt-get install -y "$PKG" > /dev/null || fail "apt-get install"
hash -r
type -P "$BIN" > /dev/null || fail "$BIN 실행 파일이 PATH 에 없습니다"
pass "$BIN 설치: $(type -P "$BIN")"

echo "[6] apt remove $PKG"
apt remove "$PKG" > /dev/null || fail "apt remove"
hash -r
if type -P "$BIN" > /dev/null; then fail "$BIN 이 남아 있습니다"; fi
pass "제거"

echo "모든 확인을 통과했습니다."
