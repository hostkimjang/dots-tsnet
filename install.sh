#!/usr/bin/env bash
# dots-tsnet 설치 스크립트
# dots-tailscale(Tailscale + OpenSSH) 위에 exit node 경유 다운로드, tsapt, apt 연결을 얹습니다.
set -euo pipefail
umask 077

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

# 기본 설치 위치는 홈 폴더입니다. 2026-10-23 Dots 정리 작업이 /workspace 최상위 폴더를 지웠을 때 홈 폴더는 남았습니다.
: "${HOME:=$(cd ~ && pwd)}"
TSNET_DIR="${TSNET_DIR:-$HOME/.tsnet}"
DOTS_TS_DIR="${DOTS_TS_DIR:-$HOME/.dots-tailscale}"
# 0.1.1 까지의 기본 설치 위치입니다. 여기에 설치가 있으면 홈 폴더로 옮깁니다.
LEGACY_TSNET_DIR="${TSNET_LEGACY_DIR:-/workspace/.tsnet}"
LEGACY_TS_DIR="${DOTS_TS_LEGACY_DIR:-/workspace/.dots-tailscale}"
ORIG_ARGS=("$@")
UPSTREAM_PROXY="${UPSTREAM_PROXY:-http://browser-proxy:8889}"
LOCK="$REPO_DIR/upstream/dots-tailscale.lock"
UPSTREAM_FILES=(tailscale-setup.sh shim.py dots-ts dots_proxy.py source-manifest.json)

EXIT_NODE="" AUTH_KEY_LINE="" SOCKS_PORT="" HTTP_PORT=""
DETACH=0 DO_APPLY=1 DO_HOOK=1 DO_LOGIN=1 CHECK_UPSTREAM_ONLY=0 NEW_IDENTITY=0

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
  --new-identity          Tailscale 상태 파일이 사라진 설치를 새 기기로 다시 로그인 (로그인 URL 승인 필요)
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
    --new-identity) NEW_IDENTITY=1; shift ;;
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
# /workspace 에 설치돼 있으면(0.1.1 까지의 기본값) 홈 폴더로 옮깁니다. 같은 Tailscale 신원을 그대로 씁니다.
MIGRATE=0 TSNET_DIR_EXISTED=0
[ ! -e "$TSNET_DIR" ] || TSNET_DIR_EXISTED=1
if [ "$CHECK_UPSTREAM_ONLY" = 0 ] && [ "$DOTS_TS_DIR" != "$LEGACY_TS_DIR" ] && [ ! -e "$DOTS_TS_DIR" ] &&
  [ -f "$LEGACY_TS_DIR/installed" ] && [ -x "$LEGACY_TS_DIR/tailscaled" ] &&
  [ -s "$LEGACY_TS_DIR/state/tailscaled.state" ]; then
  MIGRATE=1
fi
if [ "$MIGRATE" = 1 ] && tsnet_in_ssh; then
  if [ "$DETACH" = 0 ] && [ -t 0 ]; then
    answer=""
    read -r -p "기존 /workspace 설치를 홈 폴더로 옮기려면 tailscaled 를 다시 띄워야 해서 SSH 가 1~2분 끊깁니다. 분리 실행할까요? [y/N] " answer || true
    case "$answer" in y | Y | yes | YES) DETACH=1 ;; esac
  fi
  [ "$DETACH" = 1 ] || die "기존 /workspace 설치를 홈 폴더로 옮기려면 Dots 화면 터미널에서 실행하거나 --detach 를 붙이세요."
  log="$HOME/dots-tsnet-install.log"
  : > "$log"
  setsid -f nohup env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
    bash "$REPO_DIR/install.sh" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"} >> "$log" 2>&1 < /dev/null
  echo "SSH 세션과 분리해서 설치를 이어 갑니다. SSH 가 끊기면 1~2분 뒤 다시 접속해서 $log 를 확인하세요."
  exit 0
fi
BACKUP_DIR="$(tsnet_backup_dir)"
if [ "$MIGRATE" = 1 ] && [ -f "$LEGACY_TSNET_DIR/tsnet.conf" ] && [ ! -f "$TSNET_DIR/tsnet.conf" ]; then
  install -d -m 700 "$TSNET_DIR"
  install -m 600 "$LEGACY_TSNET_DIR/tsnet.conf" "$TSNET_DIR/tsnet.conf"
elif [ "$CHECK_UPSTREAM_ONLY" = 0 ] && [ ! -f "$TSNET_DIR/tsnet.conf" ] && [ -s "$BACKUP_DIR/tsnet.conf" ] &&
  [ ! -L "$BACKUP_DIR/tsnet.conf" ]; then
  # 설치 폴더가 지워졌으면 백업의 tsnet.conf(exit node, TSNET_TAILSCALED_ENV 등)를 먼저 되돌립니다.
  install -d -m 700 "$TSNET_DIR"
  install -m 600 "$BACKUP_DIR/tsnet.conf" "$TSNET_DIR/tsnet.conf"
  echo "백업에서 tsnet.conf 를 되돌렸습니다: $BACKUP_DIR/tsnet.conf"
fi
TS_ENV_VALUE="${TSNET_TAILSCALED_ENV-$(tsnet_conf_get "$TSNET_DIR/tsnet.conf" TSNET_TAILSCALED_ENV)}"
tsnet_tailscaled_env "$TS_ENV_VALUE" || exit 2

preflight

if [ "$CHECK_UPSTREAM_ONLY" = 1 ]; then
  src="$(prepare_upstream)" || die "dots-tailscale 원본 파일을 확인하지 못했습니다."
  echo "dots-tailscale $(lock_value ref) 체크섬 일치: $src"
  case "$src" in "$REPO_DIR"/*) ;; *) rm -rf "$src" ;; esac
  exit 0
fi

# 옮기다가 홈 폴더에서 띄우지 못하면 /workspace 의 기존 설치로 되돌립니다.
tsnet_preload_args
start_env() {
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u no_proxy -u NO_PROXY \
    ${TSNET_PRELOAD_ARGS[@]+"${TSNET_PRELOAD_ARGS[@]}"} "${TSNET_TS_ENV_ARGS[@]}" "$@"
}
migrate_rollback() {
  echo "install: 홈 폴더에서 Tailscale 을 띄우지 못해 /workspace 의 기존 설치로 되돌립니다." >&2
  tsnet_stop_listed "$(tsnet_install_processes "$DOTS_TS_DIR")"
  tsnet_wait_ports 90 "$WAIT_SOCKS" "$WAIT_HTTP" || true
  start_env bash "$LEGACY_TS_DIR/start.sh" ||
    echo "install: 되돌리지도 못했습니다. Dots 화면 터미널에서 bash $LEGACY_TS_DIR/start.sh 를 실행하세요." >&2
  rm -rf -- "$DOTS_TS_DIR"
  [ "$TSNET_DIR_EXISTED" = 1 ] || rm -rf -- "$TSNET_DIR"
}
if [ "$MIGRATE" = 1 ]; then
  step "/workspace 설치를 홈 폴더로 옮기기"
  echo "Dots 정리 작업이 /workspace 최상위 폴더를 지울 수 있어서 옮깁니다."
  echo "  $LEGACY_TS_DIR → $DOTS_TS_DIR"
  echo "  $LEGACY_TSNET_DIR → $TSNET_DIR"
  install -d -m 700 "$DOTS_TS_DIR" "$DOTS_TS_DIR/state" "$DOTS_TS_DIR/sshd"
  cp -p -- "$LEGACY_TS_DIR/tailscale" "$LEGACY_TS_DIR/tailscaled" "$DOTS_TS_DIR/"
  for f in ssh_host_ed25519_key ssh_host_ed25519_key.pub authorized_keys; do
    [ ! -f "$LEGACY_TS_DIR/sshd/$f" ] || cp -p -- "$LEGACY_TS_DIR/sshd/$f" "$DOTS_TS_DIR/sshd/$f"
  done
  [ ! -f "$LEGACY_TS_DIR/outbound-proxy.json" ] || cp -p -- "$LEGACY_TS_DIR/outbound-proxy.json" "$DOTS_TS_DIR/"
  if [ -d "$LEGACY_TSNET_DIR/root" ] && [ ! -e "$TSNET_DIR/root" ]; then
    echo "tsapt 로 설치한 패키지를 복사합니다 ($(du -sh "$LEGACY_TSNET_DIR/root" 2> /dev/null | cut -f 1))."
    install -d -m 700 "$TSNET_DIR"
    cp -a -- "$LEGACY_TSNET_DIR/root" "$TSNET_DIR/root"
    [ ! -d "$LEGACY_TSNET_DIR/apt" ] || cp -a -- "$LEGACY_TSNET_DIR/apt" "$TSNET_DIR/apt"
    rm -f -- "$TSNET_DIR"/apt/cache/archives/*.deb
  fi
  WAIT_SOCKS="$(tsnet_conf_get "$TSNET_DIR/tsnet.conf" TSNET_SOCKS_PORT)" WAIT_SOCKS="${WAIT_SOCKS:-1055}"
  WAIT_HTTP="$(tsnet_conf_get "$TSNET_DIR/tsnet.conf" TSNET_HTTP_PORT)" WAIT_HTTP="${WAIT_HTTP:-1056}"
  echo "/workspace 의 tailscaled, shim, sshd 를 멈추고 같은 Tailscale 신원으로 홈 폴더에서 다시 띄웁니다."
  tsnet_stop_listed "$(tsnet_install_processes "$LEGACY_TS_DIR")"
  # 멈춘 뒤에 복사해야 데몬이 마지막으로 저장한 상태가 들어갑니다.
  cp -a -- "$LEGACY_TS_DIR/state/." "$DOTS_TS_DIR/state/"
  tsnet_wait_ports 90 "$WAIT_SOCKS" "$WAIT_HTTP" || echo "포트가 아직 묶여 있지만 그래도 시작해 봅니다."
fi

step "dots-tailscale"
UPSTREAM_SRC=""
drop_upstream_src() {
  case "$UPSTREAM_SRC" in '' | "$REPO_DIR"/*) ;; *) rm -rf -- "$UPSTREAM_SRC" ;; esac
}
trap drop_upstream_src EXIT
# Tailscale 신원과 SSH 호스트 키가 지워졌으면 백업에서 먼저 되돌립니다(--new-identity 이면 되돌리지 않음).
[ "$NEW_IDENTITY" = 1 ] || tsnet_restore_identity
if [ -f "$DOTS_TS_DIR/installed" ] && tsnet_dots_ts_complete; then
  echo "기존 설치를 사용합니다: $DOTS_TS_DIR"
  # tsnet doctor --fix 가 쓸 원본 setup.sh 사본을 준비합니다. 실패해도 설치는 계속합니다.
  UPSTREAM_SRC="$(prepare_upstream)" || {
    UPSTREAM_SRC=""
    echo "경고: dots-tailscale 원본 파일을 준비하지 못해 'tsnet doctor --fix' 는 쓸 수 없습니다." >&2
  }
else
  UPSTREAM_SRC="$(prepare_upstream)" || die "dots-tailscale 원본 파일을 준비하지 못했습니다."
  if [ "$MIGRATE" = 1 ]; then
    echo "옮긴 설치에 dots-tailscale $(lock_value ref) 의 나머지 파일을 채웁니다."
  elif [ -f "$DOTS_TS_DIR/installed" ]; then
    echo "기존 dots-tailscale 설치($DOTS_TS_DIR)에서 빠진 파일을 같은 버전으로 다시 채웁니다."
  else
    echo "dots-tailscale $(lock_value ref) 을(를) 설치합니다."
  fi
  DOTS_TS_DIR="$DOTS_TS_DIR" UPSTREAM_PROXY="$UPSTREAM_PROXY" bash "$UPSTREAM_SRC/tailscale-setup.sh" install
fi
if [ -n "$AUTH_KEY_LINE" ]; then
  keys="$DOTS_TS_DIR/sshd/authorized_keys"
  touch "$keys"
  chmod 600 "$keys"
  grep -qxF "$AUTH_KEY_LINE" "$keys" || printf '%s\n' "$AUTH_KEY_LINE" >> "$keys"
  echo "SSH 공개키를 등록했습니다: $keys"
fi

step "Tailscale 기동"
# 설치 폴더가 지워진 뒤에도 옛 tailscaled 가 남아 포트를 잡고 있으면 새로 띄울 수 없습니다.
tsnet_stop_stale || exit $?
# 대화형 SSH(PTY) 보정 라이브러리를 만들고, 보정 없이 떠 있는 sshd 리스너는 다시 띄우게 합니다.
tsnet_build_pty_shim "$REPO_DIR/lib/pty_chown_shim.c"
tsnet_preload_args
tsnet_refresh_sshd
if tsnet_identity_lost; then
  if [ "$NEW_IDENTITY" = 0 ]; then
    cat >&2 << EOF
install: Tailscale 상태 파일($DOTS_TS_DIR/state/tailscaled.state)이 없습니다. 이 기기의 Tailscale 신원이 사라졌습니다.
  백업($BACKUP_DIR)에도 없어서 되돌리지 못했습니다.
  다른 곳에 백업해 둔 상태 파일이 있으면 그 자리에 되돌려 놓고 다시 실행하세요.
  없으면 새 기기로 로그인합니다(로그인 URL 승인 필요):  bash install.sh --new-identity ${EXIT_NODE:+--exit-node $EXIT_NODE}
  등록한 뒤 Tailscale 관리 콘솔에서 옛 기기를 지우거나 새 기기의 이름을 바꾸세요.
EOF
    exit 4
  fi
  rm -f -- "$DOTS_TS_DIR/authenticated"
  echo "옛 Tailscale 신원 표시(authenticated)를 지웠습니다. 새 기기로 로그인합니다."
fi
start_dots_ts() { start_env bash "$DOTS_TS_DIR/start.sh" "$@"; }
[ "${#TSNET_TS_ENV_ARGS[@]}" = 0 ] || echo "tailscaled 를 새로 띄울 때 붙일 환경변수: ${TSNET_TS_ENV_ARGS[*]}"
rc=0
start_dots_ts || rc=$?
if [ "$MIGRATE" = 1 ] && [ "$rc" != 0 ]; then
  # 옮긴 상태로 로그인이 다시 필요하다면 신원을 잘못 옮긴 것이므로, 새로 로그인하지 않고 되돌립니다.
  migrate_rollback
  die "홈 폴더로 옮기지 못했습니다 (종료 코드 $rc). /workspace 의 기존 설치로 되돌렸습니다."
fi
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
install -d -m 700 "$TSNET_DIR" "$TSNET_DIR/bin" "$TSNET_DIR/lib" "$TSNET_DIR/lib/upstream" "$TSNET_DIR/shims"
install -m 755 "$REPO_DIR/lib/bin/tsnet" "$REPO_DIR/lib/bin/tsapt" "$TSNET_DIR/bin/"
install -m 644 "$REPO_DIR/lib/common.sh" "$REPO_DIR/lib/setup_knobs.py" "$TSNET_DIR/lib/"
install -m 644 "$REPO_DIR/lib/env.sh" "$TSNET_DIR/env.sh"
install -m 644 "$REPO_DIR/VERSION" "$TSNET_DIR/VERSION"
if [ -n "$UPSTREAM_SRC" ]; then
  # tsnet doctor --fix 가 setup.sh 를 되살릴 때 쓰는 원본 사본입니다 (SHA-256 확인을 거친 파일).
  install -m 600 "$UPSTREAM_SRC/tailscale-setup.sh" "$TSNET_DIR/lib/upstream/tailscale-setup.sh"
fi
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
tsnet_backup_identity
echo "백업: $BACKUP_DIR (Tailscale 신원, SSH 호스트 키, tsnet.conf. 다른 컴퓨터로 옮기지 마세요)"
if [ ! -s "$TSNET_DIR/apt/user-status" ] && [ -s "$BACKUP_DIR/packages.txt" ]; then
  echo "이전에 tsapt 로 설치했던 패키지 $(wc -l < "$BACKUP_DIR/packages.txt")개는 설치 폴더와 함께 지워졌습니다. 다시 설치하려면:"
  echo "  apt-get update && apt-get install -y \$(cat $BACKUP_DIR/packages.txt)"
fi

if [ "$DO_HOOK" = 1 ]; then
  step "셸 연결"
  "$TSNET_DIR/bin/tsnet" install-hook
fi

step "exit node"
if [ -n "$TSNET_EXIT_NODE" ]; then
  # 막 기동한 tailscaled 는 기기 목록(netmap)을 받기 전이라 exit node 를 못 찾을 수 있어 몇 번 다시 시도합니다.
  exit_ok=0
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if exit_err="$("$TSNET_DIR/bin/tsnet" exit-node "$TSNET_EXIT_NODE" 2>&1)"; then
      exit_ok=1
      printf '%s\n' "$exit_err"
      break
    fi
    sleep 3
  done
  if [ "$exit_ok" = 0 ]; then
    printf '%s\n' "$exit_err" >&2
    echo "경고: exit node '$TSNET_EXIT_NODE' 를 지정하지 못했습니다. 관리 콘솔에서 승인됐는지 확인한 뒤 'tsnet exit-node $TSNET_EXIT_NODE' 를 다시 실행하세요." >&2
  fi
else
  "$TSNET_DIR/bin/tsnet" exit-node || true
  echo "exit node 를 아직 지정하지 않았습니다. docs/exit-node.ko.md 를 따라 준비한 뒤 'tsnet exit-node {exit-node}' 를 실행하세요."
fi

step "마무리"
tsnet_backup_identity
if [ "$MIGRATE" = 1 ]; then
  # 바탕화면 실행 아이콘이 옛 위치의 프로그램을 가리키면 새 위치로 고칩니다.
  for f in "$HOME"/.local/share/applications/*.desktop "$HOME"/.config/autostart/*.desktop; do
    if [ -f "$f" ] && [ ! -L "$f" ] && grep -qF "$LEGACY_TSNET_DIR/" "$f"; then
      sed -i "s#$LEGACY_TSNET_DIR/#$TSNET_DIR/#g" "$f"
      echo "실행 아이콘의 경로를 새 위치로 고쳤습니다: $f"
    fi
  done
  rm -rf -- "$LEGACY_TS_DIR"
  echo "옛 dots-tailscale 설치($LEGACY_TS_DIR)를 지웠습니다. Tailscale 신원은 $DOTS_TS_DIR 와 백업에 있습니다."
  if [ -d "$LEGACY_TSNET_DIR" ]; then
    in_use=""
    for p in /proc/[0-9]*/exe; do
      l="$(readlink "$p" 2> /dev/null)" || continue
      case "$l" in "$LEGACY_TSNET_DIR"/*) in_use="$l"; break ;; esac
    done
    if [ -n "$in_use" ]; then
      find "$LEGACY_TSNET_DIR" -mindepth 1 -maxdepth 1 ! -name root -exec rm -rf -- {} +
      echo "실행 중인 프로그램(${in_use% (deleted)})이 옛 위치의 파일을 쓰고 있어 $LEGACY_TSNET_DIR/root 만 남겼습니다."
      echo "  그 프로그램을 다시 시작하면 새 위치에서 실행되고, 그 뒤에 지워도 됩니다."
    else
      rm -rf -- "$LEGACY_TSNET_DIR"
      echo "옛 dots-tsnet 설치($LEGACY_TSNET_DIR)를 지웠습니다."
    fi
  fi
fi
"$TSNET_DIR/bin/tsnet" _check-setup || true
cat << EOF
설치를 마쳤습니다. 새 셸을 열거나 'source ~/.bashrc' 를 실행하면 적용됩니다.
  tsnet status                  상태 확인
  tsnet doctor                  dots-tailscale 점검 (setup.sh 를 직접 고쳤다면 --fix)
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
