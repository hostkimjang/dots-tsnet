#!/usr/bin/env bash
# dots-tsnet 설치 스크립트
# dots-tailscale(Tailscale + OpenSSH) 위에 exit node 경유 다운로드, tsapt, apt 연결을 얹습니다.
set -euo pipefail
umask 077

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

TSNET_DIR="${TSNET_DIR:-/workspace/.tsnet}"
DOTS_TS_DIR="${DOTS_TS_DIR:-/workspace/.dots-tailscale}"
UPSTREAM_PROXY="${UPSTREAM_PROXY:-http://browser-proxy:8889}"
LOCK="$REPO_DIR/upstream/dots-tailscale.lock"
UPSTREAM_FILES=(tailscale-setup.sh shim.py dots-ts dots_proxy.py source-manifest.json)

EXIT_NODE="" AUTH_KEY_LINE="" SOCKS_PORT="" HTTP_PORT=""
DETACH=0 DO_APPLY=1 DO_HOOK=1 DO_LOGIN=1 CHECK_UPSTREAM_ONLY=0

usage() {
  cat << 'EOF'
사용법: bash install.sh [옵션]
  --exit-node {exit-node}             exit node 로 쓸 집 PC 또는 중계 서버의 Tailscale 이름
  --authorized-key '{ssh-public-key}' SSH 공개키 한 줄(ssh-ed25519 AAAA...)을 authorized_keys 에 추가
  --socks-port 포트       로컬 SOCKS5 프록시 포트 (기본 1055)
  --http-port 포트        로컬 HTTP 프록시 포트 (기본 1056)
  --detach                SSH 에서 실행할 때 tailscaled 재시작을 분리 실행 (SSH 가 몇 초 끊김)
  --no-apply              프록시 설정만 저장하고 tailscaled 는 재시작하지 않음
  --no-hook               ~/.bashrc 를 바꾸지 않음
  --skip-login            Tailscale 로그인이 필요하면 진행하지 않고 멈춤
  --check-upstream        dots-tailscale 원본 파일을 준비해 체크섬만 확인하고 끝냄

환경변수 TSNET_TAILSCALED_ENV='TS_이름=값 ...' 를 주면 tailscaled 를 새로 띄울 때 붙이고 tsnet.conf 에 저장합니다.
EOF
}

need_value() {
  if [ $# -lt 2 ] || [ -z "$2" ]; then
    printf 'install: %s 에 값이 필요합니다\n' "$1" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --exit-node) need_value "$@"; EXIT_NODE="$2"; shift 2 ;;
    --exit-node=*) EXIT_NODE="${1#*=}"; shift ;;
    --authorized-key) need_value "$@"; AUTH_KEY_LINE="$2"; shift 2 ;;
    --socks-port) need_value "$@"; SOCKS_PORT="$2"; shift 2 ;;
    --http-port) need_value "$@"; HTTP_PORT="$2"; shift 2 ;;
    --detach) DETACH=1; shift ;;
    --no-apply) DO_APPLY=0; shift ;;
    --no-hook) DO_HOOK=0; shift ;;
    --skip-login) DO_LOGIN=0; shift ;;
    --check-upstream) CHECK_UPSTREAM_ONLY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'install: 알 수 없는 옵션입니다: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }
lock_value() { sed -n "s/^$1=//p" "$LOCK" | head -n 1; }

verify_upstream_dir() {
  local dir="$1" f want got
  for f in "${UPSTREAM_FILES[@]}"; do
    want="$(lock_value "$f")"
    [ -f "$dir/$f" ] || return 1
    got="$(sha256sum "$dir/$f" | cut -d ' ' -f 1)"
    [ "$got" = "$want" ] || return 1
  done
}

# 검증된 dots-tailscale 원본 파일이 있는 디렉터리를 출력합니다.
# 서브모듈을 먼저 쓰고, 없거나 체크섬이 다르면 같은 버전의 릴리스 파일을 내려받습니다.
prepare_upstream() {
  local ref repo dir f
  ref="$(lock_value ref)"
  repo="$(lock_value repo)"
  dir="$REPO_DIR/upstream/dots-tailscale"
  if [ "${TSNET_UPSTREAM_SOURCE:-auto}" != download ] && verify_upstream_dir "$dir"; then
    printf '%s\n' "$dir"
    return 0
  fi
  echo "dots-tailscale $ref 파일을 내려받습니다 (프록시 $UPSTREAM_PROXY)" >&2
  dir="$(mktemp -d "${TMPDIR:-/tmp}/dots-tsnet-upstream.XXXXXX")"
  for f in "${UPSTREAM_FILES[@]}"; do
    if ! curl -fsSL --proxy "$UPSTREAM_PROXY" --connect-timeout 10 --max-time 180 \
      "$repo/releases/download/$ref/$f" -o "$dir/$f" &&
      ! curl -fsSL --proxy "$UPSTREAM_PROXY" --connect-timeout 10 --max-time 180 \
        "${repo/github.com/raw.githubusercontent.com}/$ref/$f" -o "$dir/$f"; then
      rm -rf "$dir"
      echo "내려받기 실패: $f" >&2
      return 1
    fi
  done
  if ! verify_upstream_dir "$dir"; then
    rm -rf "$dir"
    echo "내려받은 파일의 체크섬이 upstream/dots-tailscale.lock 과 다릅니다." >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

preflight() {
  local c
  [ "$(uname -s)" = Linux ] || die "Linux 에서 실행하세요."
  for c in python3 curl sha256sum setsid timeout dpkg-deb; do
    command -v "$c" > /dev/null || die "필요한 명령이 없습니다: $c"
  done
  [ -x /usr/bin/apt-get ] || die "/usr/bin/apt-get 이 없습니다. Debian 계열 이미지가 필요합니다."
  [ -f "$LOCK" ] || die "upstream/dots-tailscale.lock 이 없습니다. 저장소 전체를 받았는지 확인하세요."
}

[ -z "$EXIT_NODE" ] || tsnet_valid_node "$EXIT_NODE" || die "잘못된 exit node 이름입니다: $EXIT_NODE"
for port in $SOCKS_PORT $HTTP_PORT; do
  tsnet_valid_port "$port" || die "잘못된 포트입니다: $port (1024-65535, 18089 제외)"
done
case "$AUTH_KEY_LINE" in
  '' | ssh-* | ecdsa-* | sk-*) ;;
  *) die "--authorized-key 에는 'ssh-ed25519 AAAA...' 형식의 공개키 한 줄을 주세요." ;;
esac
TS_ENV_VALUE="${TSNET_TAILSCALED_ENV-$(tsnet_conf_get "$TSNET_DIR/tsnet.conf" TSNET_TAILSCALED_ENV)}"
tsnet_tailscaled_env "$TS_ENV_VALUE" || exit 2

preflight

if [ "$CHECK_UPSTREAM_ONLY" = 1 ]; then
  src="$(prepare_upstream)" || die "dots-tailscale 원본 파일을 확인하지 못했습니다."
  echo "dots-tailscale $(lock_value ref) 체크섬 일치: $src"
  case "$src" in "$REPO_DIR"/*) ;; *) rm -rf "$src" ;; esac
  exit 0
fi

step "dots-tailscale"
if [ -f "$DOTS_TS_DIR/installed" ]; then
  echo "기존 설치를 사용합니다: $DOTS_TS_DIR"
else
  src="$(prepare_upstream)" || die "dots-tailscale 원본 파일을 준비하지 못했습니다."
  echo "dots-tailscale $(lock_value ref) 을(를) 설치합니다."
  DOTS_TS_DIR="$DOTS_TS_DIR" UPSTREAM_PROXY="$UPSTREAM_PROXY" bash "$src/tailscale-setup.sh" install
fi
if [ -n "$AUTH_KEY_LINE" ]; then
  keys="$DOTS_TS_DIR/sshd/authorized_keys"
  touch "$keys"
  chmod 600 "$keys"
  grep -qxF "$AUTH_KEY_LINE" "$keys" || printf '%s\n' "$AUTH_KEY_LINE" >> "$keys"
  echo "SSH 공개키를 등록했습니다: $keys"
fi

step "Tailscale 기동"
start_dots_ts() {
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u no_proxy -u NO_PROXY \
    "${TSNET_TS_ENV_ARGS[@]}" bash "$DOTS_TS_DIR/start.sh" "$@"
}
[ "${#TSNET_TS_ENV_ARGS[@]}" = 0 ] || echo "tailscaled 를 새로 띄울 때 붙일 환경변수: ${TSNET_TS_ENV_ARGS[*]}"
rc=0
start_dots_ts || rc=$?
if [ "$rc" = 10 ]; then
  [ "$DO_LOGIN" = 1 ] || die "Tailscale 로그인이 필요합니다: bash $DOTS_TS_DIR/start.sh login"
  echo "Tailscale 로그인이 필요합니다. 아래에 나오는 URL 을 브라우저에서 열어 승인하세요."
  rc=0
  start_dots_ts login || rc=$?
fi
case "$rc" in
  0) ;;
  13) die "Tailscale 관리 콘솔에서 이 기기를 승인한 뒤 다시 실행하세요." ;;
  *) die "dots-tailscale 기동에 실패했습니다 (종료 코드 $rc). $DOTS_TS_DIR/dots-ts doctor 로 원인을 확인하세요." ;;
esac
"$DOTS_TS_DIR/dots-ts" proxy show > /dev/null 2>&1 ||
  die "dots-ts proxy 명령을 쓸 수 없습니다. dots-tailscale v0.4.0 이상이 필요합니다 ($DOTS_TS_DIR)."

step "dots-tsnet $(cat "$REPO_DIR/VERSION") 설치: $TSNET_DIR"
install -d -m 700 "$TSNET_DIR" "$TSNET_DIR/bin" "$TSNET_DIR/lib" "$TSNET_DIR/shims"
install -m 755 "$REPO_DIR/lib/bin/tsnet" "$REPO_DIR/lib/bin/tsapt" "$TSNET_DIR/bin/"
install -m 644 "$REPO_DIR/lib/common.sh" "$TSNET_DIR/lib/common.sh"
install -m 644 "$REPO_DIR/lib/env.sh" "$TSNET_DIR/env.sh"
install -m 644 "$REPO_DIR/VERSION" "$TSNET_DIR/VERSION"
for name in apt apt-get apt-cache; do
  ln -sfn ../bin/tsapt "$TSNET_DIR/shims/$name"
done
CONF="$TSNET_DIR/tsnet.conf"
[ -f "$CONF" ] || install -m 600 "$REPO_DIR/lib/tsnet.conf.default" "$CONF"
[ -z "$EXIT_NODE" ] || tsnet_set_conf "$CONF" TSNET_EXIT_NODE "$EXIT_NODE"
[ -z "$SOCKS_PORT" ] || tsnet_set_conf "$CONF" TSNET_SOCKS_PORT "$SOCKS_PORT"
[ -z "$HTTP_PORT" ] || tsnet_set_conf "$CONF" TSNET_HTTP_PORT "$HTTP_PORT"
[ -z "${TSNET_TAILSCALED_ENV+x}" ] || tsnet_set_conf "$CONF" TSNET_TAILSCALED_ENV "$TSNET_TAILSCALED_ENV"
tsnet_set_conf "$CONF" DOTS_TS_DIR "$DOTS_TS_DIR"
tsnet_load_conf "$CONF"
tsnet_defaults
echo "설정 파일: $CONF"

if [ "$DO_HOOK" = 1 ]; then
  step "셸 연결"
  "$TSNET_DIR/bin/tsnet" install-hook
fi

step "exit node"
if [ -n "$TSNET_EXIT_NODE" ]; then
  "$TSNET_DIR/bin/tsnet" exit-node "$TSNET_EXIT_NODE" ||
    echo "경고: exit node '$TSNET_EXIT_NODE' 를 지정하지 못했습니다. 관리 콘솔에서 승인됐는지 확인한 뒤 'tsnet exit-node $TSNET_EXIT_NODE' 를 다시 실행하세요." >&2
else
  "$TSNET_DIR/bin/tsnet" exit-node || true
  echo "exit node 를 아직 지정하지 않았습니다. docs/exit-node.ko.md 를 따라 준비한 뒤 'tsnet exit-node {exit-node}' 를 실행하세요."
fi

step "마무리"
cat << EOF
설치를 마쳤습니다. 새 셸을 열거나 'source ~/.bashrc' 를 실행하면 적용됩니다.
  tsnet status                  상태 확인
  apt-get update                패키지 목록 갱신
  apt-get install -y <패키지>    설치 (위치: $TSNET_ROOT)
  tsnet start                   VM 이 바뀐 뒤 Tailscale 다시 띄우기
EOF

# tailscaled 재시작은 SSH 를 끊을 수 있으므로 항상 마지막에 둡니다.
if [ "$DO_APPLY" = 0 ]; then
  "$TSNET_DIR/bin/tsnet" apply --configure-only
  exit 0
fi
step "tailscaled 로컬 프록시 (SOCKS5 $TSNET_SOCKS_PORT, HTTP $TSNET_HTTP_PORT)"
"$TSNET_DIR/bin/tsnet" apply --configure-only > /dev/null
if ! tsnet_proxy_pending; then
  echo "로컬 프록시가 이미 열려 있습니다."
  exit 0
fi
if tsnet_in_ssh && [ "$DETACH" = 0 ] && [ -t 0 ]; then
  answer=""
  read -r -p "SSH 세션에서 tailscaled 를 재시작하면 연결이 몇 초 끊깁니다. 분리 실행할까요? [y/N] " answer || true
  case "$answer" in y | Y | yes | YES) DETACH=1 ;; esac
fi
if [ "$DETACH" = 1 ]; then
  "$TSNET_DIR/bin/tsnet" apply --detach
else
  "$TSNET_DIR/bin/tsnet" apply
fi
