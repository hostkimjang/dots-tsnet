#!/usr/bin/env bash
# dots-tsnet 제거 스크립트. dots-tailscale 설치와 Tailscale 로그인 상태는 그대로 둡니다.
set -euo pipefail
# 0.1.2 부터 기본 설치 위치는 홈 폴더입니다. 그 전 버전으로 /workspace 에 설치했다면 그쪽을 지웁니다.
if [ -z "${TSNET_DIR:-}" ]; then
  TSNET_DIR="$HOME/.tsnet"
  [ -x "$TSNET_DIR/bin/tsnet" ] || [ ! -x /workspace/.tsnet/bin/tsnet ] || TSNET_DIR=/workspace/.tsnet
fi
KEEP_PACKAGES=0
case "${1:-}" in
  '') ;;
  --keep-packages) KEEP_PACKAGES=1 ;;
  -h | --help) echo "사용법: bash uninstall.sh [--keep-packages]"; exit 0 ;;
  *) echo "uninstall: 알 수 없는 옵션입니다: $1" >&2; exit 2 ;;
esac
case "$TSNET_DIR" in
  /*/*) ;;
  *) echo "uninstall: TSNET_DIR 은 절대 경로여야 합니다: $TSNET_DIR" >&2; exit 2 ;;
esac
if [ ! -x "$TSNET_DIR/bin/tsnet" ] || [ ! -f "$TSNET_DIR/VERSION" ]; then
  echo "dots-tsnet 설치가 없습니다: $TSNET_DIR"
  exit 0
fi

. "$TSNET_DIR/lib/common.sh"
tsnet_load_conf "$TSNET_DIR/tsnet.conf"
tsnet_defaults

"$TSNET_DIR/bin/tsnet" remove-hook || true
"$TSNET_DIR/bin/tsnet" exit-node off || true
"$DOTS_TS_DIR/dots-ts" proxy disable > /dev/null || true

if [ "$KEEP_PACKAGES" = 1 ]; then
  rm -rf -- "$TSNET_DIR/bin" "$TSNET_DIR/lib" "$TSNET_DIR/shims" "$TSNET_DIR/env.sh" \
    "$TSNET_DIR/VERSION" "$TSNET_DIR/tsnet.conf" "$TSNET_DIR/apply.log" "$TSNET_DIR/restart.log"
  echo "프로그램을 지웠습니다. 설치한 패키지, apt 캐시, setup.sh 백업(backup/)은 $TSNET_DIR 에 남겼습니다."
else
  rm -rf -- "$TSNET_DIR"
  echo "$TSNET_DIR 를 지웠습니다."
fi

cat << EOF
dots-tailscale 과 Tailscale 로그인 상태는 그대로입니다.
- 실행 중인 로컬 프록시는 다음 tailscaled 재시작 때 닫힙니다. 바로 닫으려면 Dots 화면 터미널에서:
    $DOTS_TS_DIR/dots-ts proxy apply
- 이미 열려 있는 셸에는 이전 환경이 남아 있으니 새 셸을 여세요.
- exit node 로 쓰던 기기의 광고를 끄려면 그 기기에서: tailscale set --advertise-exit-node=false
EOF
if [ -n "$TSNET_TAILSCALED_ENV" ]; then
  echo "- TSNET_TAILSCALED_ENV($TSNET_TAILSCALED_ENV)는 이제 tailscaled 에 붙지 않습니다. 계속 쓰려면 start.sh 를 실행할 때 앞에 직접 붙이세요."
fi
BACKUP_DIR="$(tsnet_backup_dir)"
if [ -d "$BACKUP_DIR" ]; then
  echo "- 백업($BACKUP_DIR)에는 Tailscale 개인키가 들어 있어 남겨 뒀습니다. 이 기기를 tailnet 에서 완전히 지울 때 함께 지우세요."
fi
