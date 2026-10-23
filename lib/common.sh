# dots-tsnet 공통 셸 함수입니다. tsnet, env.sh, install.sh, uninstall.sh 가 불러 씁니다.
# shellcheck shell=bash

# KEY=VALUE 형식의 설정 파일을 읽습니다. 이미 환경변수로 정해진 값은 덮어쓰지 않습니다.
tsnet_load_conf() {
  local file="$1" key value
  [ -f "$file" ] || return 0
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in '' | '#'*) continue ;; esac
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [ -n "${!key+x}" ] || printf -v "$key" '%s' "$value"
  done < "$file"
}

# 기본 설치 위치의 부모 폴더입니다. /workspace/shared 가 있으면 그곳, 없으면 홈 폴더입니다.
# Dots 의 scratch 정리 작업은 /workspace 최상위 폴더를 지우면서 /workspace/shared 는 새로 만들었고,
# Dots 데스크톱도 사용자 설정을 이곳에 보존합니다(/etc/orbit-os/config.toml). 테스트에서는 TSNET_SHARED_BASE 로 바꿉니다.
tsnet_install_base() {
  local home="${HOME:-}" shared="${TSNET_SHARED_BASE:-/workspace/shared}"
  # HOME 이 비어 있으면 bash 는 ~ 를 계정 정보의 홈 디렉터리로 풉니다.
  [ -n "$home" ] || home="$(cd ~ 2> /dev/null && pwd)" || true
  if [ -d "$shared" ] && [ -w "$shared" ]; then
    printf '%s\n' "$shared"
  else
    printf '%s\n' "$home"
  fi
}

tsnet_defaults() {
  local base
  base="$(tsnet_install_base)"
  : "${TSNET_DIR:=$base/.tsnet}"
  : "${DOTS_TS_DIR:=$base/.dots-tailscale}"
  : "${TSNET_EXIT_NODE:=}"
  : "${TSNET_SOCKS_PORT:=1055}"
  : "${TSNET_HTTP_PORT:=1056}"
  : "${TSNET_NO_PROXY:=localhost,127.0.0.1,::1,browser-proxy}"
  : "${TSNET_AUTO_PROXY:=1}"
  : "${TSNET_APT_SHIM:=1}"
  : "${TSNET_SUDO_SHIM:=1}"
  : "${TSNET_PYTHONPATH:=1}"
  : "${TSNET_TAILSCALED_ENV:=}"
  TSNET_HTTP_PROXY="http://127.0.0.1:${TSNET_HTTP_PORT}"
  TSNET_SOCKS_PROXY="socks5h://127.0.0.1:${TSNET_SOCKS_PORT}"
  TSNET_ROOT="$TSNET_DIR/root"
}

# tsnet.conf 의 값을 바꾸거나 새로 추가합니다.
tsnet_set_conf() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "$file.XXXXXX")"
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" '
      index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
      { print }
      END { if (!done) print k "=" v }' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
}

tsnet_valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ] && [ "$1" -ne 18089 ]; }
tsnet_valid_node() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]; }
tsnet_in_ssh() { [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ]; }

# dots-tailscale 이 제공하는 Tailscale CLI 를 그 설치의 소켓으로 실행합니다.
tsnet_ts() { timeout 20 "$DOTS_TS_DIR/dots-ts" cli "$@"; }

tsnet_backend_running() {
  timeout 5 "$DOTS_TS_DIR/dots-ts" cli status --json 2> /dev/null | grep -q '"BackendState": "Running"'
}

tsnet_proxy_configure() {
  "$DOTS_TS_DIR/dots-ts" proxy configure --socks-port "$TSNET_SOCKS_PORT" --http-port "$TSNET_HTTP_PORT" > /dev/null
}

# 저장한 프록시 설정과 실행 중인 데몬이 다르면 성공(0)을 반환합니다.
tsnet_proxy_pending() {
  "$DOTS_TS_DIR/dots-ts" proxy show |
    python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)["restart_required"] else 1)'
}

# tsnet.conf 에서 키 하나만 읽습니다. 다른 변수는 건드리지 않습니다.
tsnet_conf_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n 1
}

# TSNET_TAILSCALED_ENV 값("TS_이름=값 TS_이름=값")을 검사해서 TSNET_TS_ENV_ARGS 배열에 담습니다.
# tailscaled 동작을 바꾸는 TS_ 환경변수만 받고, 셸이 해석할 수 있는 문자는 거부합니다.
tsnet_tailscaled_env() {
  local item
  local -a items=()
  TSNET_TS_ENV_ARGS=()
  read -r -a items <<< "${1:-}"
  for item in "${items[@]}"; do
    if [[ ! "$item" =~ ^TS_[A-Z0-9_]+=[A-Za-z0-9._:/,-]*$ ]]; then
      printf 'tsnet: TSNET_TAILSCALED_ENV 에는 TS_이름=값 형식만 쓸 수 있습니다: %s\n' "$item" >&2
      return 2
    fi
    TSNET_TS_ENV_ARGS+=("$item")
  done
}

# 이 설치의 tailscaled PID 를 출력합니다. 실행 중이 아니면 아무것도 출력하지 않습니다.
tsnet_daemon_pid() {
  pgrep -u "$(id -u)" -f "^$DOTS_TS_DIR/tailscaled( |$)" 2> /dev/null | head -n 1 || true
}

# 실행 중인 tailscaled 에 적용된 TS_ 환경변수를 한 줄에 하나씩 출력합니다. 키처럼 보이는 값은 가립니다.
tsnet_daemon_knobs() {
  tr '\0' '\n' < "/proc/$1/environ" 2> /dev/null | grep -E '^TS_' |
    sed -E 's/^([A-Z0-9_]*(KEY|SECRET|TOKEN|AUTH)[A-Z0-9_]*=).*/\1<redacted>/' || true
}

# 이 사용자의 tailscaled 소켓 경로입니다. dots-tailscale 과 같은 규칙을 씁니다.
tsnet_socket_path() { printf '/tmp/dots-tailscale-%s/tailscaled.sock\n' "$(id -u)"; }

# 설치 경로(첫 인자)에 속한 dots-tailscale 프로세스(tailscaled, shim.py, sshd 리스너)를 "PID 이름 [소켓]" 줄로 출력합니다.
# 두 번째 인자가 stale 이면, 실행 파일이 지워진(" (deleted)") tailscaled 가 있을 때만 출력합니다.
tsnet_install_processes() {
  python3 - "$1" "${2:-all}" << 'PY' 2> /dev/null || true
import os, sys
d = os.path.normpath(sys.argv[1])
daemon, uid, procs = d + "/tailscaled", os.getuid(), []
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        if os.stat("/proc/" + pid).st_uid != uid:
            continue
        with open("/proc/%s/cmdline" % pid, "rb") as f:
            argv = f.read().rstrip(b"\0").decode("utf-8", "replace").split("\0")
        exe = os.readlink("/proc/%s/exe" % pid)
    except OSError:
        continue
    procs.append((int(pid), argv, exe))
if sys.argv[2] == "stale" and not any(argv[0] == daemon and exe == daemon + " (deleted)" for _, argv, exe in procs):
    sys.exit(0)
for pid, argv, exe in sorted(procs):
    line = " ".join(argv)
    if argv[0] == daemon:
        sock = next((a.split("=", 1)[1] for a in argv[1:] if a.startswith("--socket=")), "")
        print(pid, "tailscaled", sock)
    elif os.path.basename(exe).startswith("python") and d + "/shim/shim.py" in argv[1:]:
        print(pid, "shim.py")
    elif os.path.basename(exe) == "sshd" and "[listener]" in line and d + "/sshd/sshd_config" in line:
        print(pid, "sshd")
PY
}

# 설치 파일이 지워진 뒤에도 메모리에 남아 도는 옛 dots-tailscale 프로세스입니다. 이런 프로세스는 상태 파일을
# 저장하지 못하고 새 연결도 만들지 못하면서, 프록시 포트와 소켓은 계속 잡고 있습니다.
tsnet_stale_processes() { tsnet_install_processes "$DOTS_TS_DIR" stale; }

# tsnet_install_processes 가 출력한 줄의 프로세스를 멈추고, 멈춘 tailscaled 가 쓰던 소켓 파일을 지웁니다.
tsnet_stop_listed() {
  local lines="$1" pid name sock left="" socks=""
  [ -n "$lines" ] || return 0
  while read -r pid name sock; do
    kill -TERM "$pid" 2> /dev/null || true
    if [ "$name" = tailscaled ] && [ -n "$sock" ]; then socks="$socks $sock"; fi
  done <<< "$lines"
  for _ in $(seq 1 50); do
    left=""
    while read -r pid name sock; do
      if kill -0 "$pid" 2> /dev/null; then left="$left $pid"; fi
    done <<< "$lines"
    [ -n "$left" ] || break
    sleep 0.2
  done
  for pid in $left; do kill -KILL "$pid" 2> /dev/null || true; done
  for sock in $socks; do
    if [ -S "$sock" ] && [ ! -L "$sock" ] && [ -O "$sock" ] &&
      ! pgrep -u "$(id -u)" -f -- "--socket=$sock" > /dev/null 2>&1; then
      rm -f -- "$sock"
    fi
  done
}

# 옛 프로세스를 멈춥니다. SSH 세션은 그 tailscaled 를 거쳐 연결돼 있을 수 있으므로 멈추지 않고 3 을 반환합니다.
tsnet_stop_stale() {
  local lines
  lines="$(tsnet_stale_processes)"
  [ -n "$lines" ] || return 0
  echo "설치 파일이 지워진 채로 돌고 있는 dots-tailscale 프로세스가 있습니다:"
  printf '%s\n' "$lines" | cut -d ' ' -f 1,2 | sed 's/^/  PID /'
  echo "  상태를 저장하지도 새 연결을 만들지도 못하면서 프록시 포트와 소켓만 잡고 있어서, 멈추고 새로 띄웁니다."
  if tsnet_in_ssh; then
    echo "tsnet: 지금 SSH 연결도 이 tailscaled 를 거칠 수 있어 여기서는 멈추지 않습니다. Dots 화면의 터미널에서 다시 실행하세요." >&2
    return 3
  fi
  tsnet_stop_listed "$lines"
}

# 로컬 포트를 다시 열 수 있을 때까지 최대 첫 인자(초)만큼 기다립니다. dots-tailscale 의 기동 검사는 방금 멈춘
# 데몬의 연결이 TIME_WAIT 로 남아 있어도 'occupied port' 로 거부하기 때문입니다.
tsnet_wait_ports() {
  local limit="$1" waited=0
  shift
  while ! python3 - "$@" 2> /dev/null << 'PY'; do
import socket, sys
for port in sys.argv[1:]:
    with socket.socket() as s:
        s.bind(("127.0.0.1", int(port)))
PY
    [ "$waited" -lt "$limit" ] || return 1
    [ "$waited" != 0 ] || echo "포트 $*가 아직 묶여 있어 풀릴 때까지 기다립니다 (최대 ${limit}초)"
    sleep 2
    waited=$((waited + 2))
  done
}

# dots-tailscale 설치에 실행에 필요한 파일이 모두 있으면 성공(0)을 반환합니다.
tsnet_dots_ts_complete() {
  local f
  for f in installed tailscale tailscaled dots-ts dots_proxy.py setup.sh start.sh shim/shim.py shim/ca.crt \
    shim/ca.key shim/bundle.crt sshd/sshd_config sshd/ssh_host_ed25519_key sshd/authorized_keys; do
    [ -f "$DOTS_TS_DIR/$f" ] || return 1
  done
}

# 한 번 로그인했던 설치인데 Tailscale 상태 파일이 사라졌으면 성공(0)을 반환합니다. 이때 dots-tailscale 은
# 기기 신원을 몰래 바꾸지 않으려고 기동을 거부합니다.
tsnet_identity_lost() {
  [ -e "$DOTS_TS_DIR/authenticated" ] && [ ! -s "$DOTS_TS_DIR/state/tailscaled.state" ]
}

# 백업 위치입니다. 설치와 다른 쪽에 둡니다: /workspace(/workspace/shared 포함)에 설치했으면 홈 폴더,
# 홈 폴더에 설치했으면 /workspace/shared. 한쪽이 지워져도 다른 쪽에서 되살리기 위해서입니다.
# 여기에는 Tailscale 개인키가 들어 있으니 다른 컴퓨터로 복사하거나 공유하면 안 됩니다.
tsnet_backup_dir() {
  if [ -n "${TSNET_BACKUP_DIR:-}" ]; then
    printf '%s\n' "$TSNET_BACKUP_DIR"
    return 0
  fi
  case "$DOTS_TS_DIR/" in
    "${HOME:-/nonexistent}"/*) printf '%s\n' "${TSNET_SHARED_BASE:-/workspace/shared}/.dots-tsnet-backup" ;;
    *) printf '%s\n' "${HOME:-}/.local/state/dots-tsnet" ;;
  esac
}

# 되살릴 때 찾아볼 백업 위치입니다. 지금 위치를 먼저 보고, 예전 버전이 쓰던 위치도 봅니다
# (0.1.2 는 홈 폴더 설치의 백업을 /workspace/.dots-tsnet-backup 에 뒀습니다).
tsnet_backup_candidates() {
  local primary d
  primary="$(tsnet_backup_dir)"
  printf '%s\n' "$primary"
  [ -z "${TSNET_BACKUP_DIR:-}" ] || return 0
  for d in "${HOME:-/nonexistent}/.local/state/dots-tsnet" "${TSNET_SHARED_BASE:-/workspace/shared}/.dots-tsnet-backup" \
    /workspace/.dots-tsnet-backup; do
    [ "$d" = "$primary" ] || printf '%s\n' "$d"
  done
}

# 백업 후보 가운데 이름이 name 인 파일이 처음 있는 경로를 출력합니다. 내 소유가 아닌 폴더와 심볼릭 링크는 건너뜁니다.
tsnet_backup_find() {
  local dir
  while IFS= read -r dir; do
    [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] || continue
    if [ -s "$dir/$1" ] && [ ! -L "$dir/$1" ]; then
      printf '%s\n' "$dir/$1"
      return 0
    fi
  done <<< "$(tsnet_backup_candidates)"
  return 1
}

# src 가 dst 보다 새것이면 권한을 지켜 복사합니다. 심볼릭 링크는 따라가지 않습니다.
_tsnet_copy_newer() {
  local src="$1" dst="$2"
  [ -s "$src" ] && [ ! -L "$src" ] && [ ! -L "$dst" ] || return 0
  if [ ! -e "$dst" ] || [ "$src" -nt "$dst" ]; then
    (umask 077 && cp -p -- "$src" "$dst.tmp" && chmod 600 "$dst.tmp" && mv -f -- "$dst.tmp" "$dst") || rm -f -- "$dst.tmp"
  fi
}

# Tailscale 신원(상태 파일), SSH 호스트 키, authorized_keys, tsnet.conf, tsapt 패키지 목록을 백업 위치에 복사합니다.
# 바뀐 파일만 복사하므로 새 셸마다 불러도 됩니다. TSNET_IDENTITY_BACKUP=0 이면 아무것도 하지 않습니다.
tsnet_backup_identity() {
  local dir
  [ "${TSNET_IDENTITY_BACKUP:-1}" = 1 ] || return 0
  [ -s "$DOTS_TS_DIR/state/tailscaled.state" ] || return 0
  dir="$(tsnet_backup_dir)"
  (umask 077 && mkdir -p -- "$dir") 2> /dev/null || return 0
  [ ! -L "$dir" ] && [ -O "$dir" ] || return 0
  _tsnet_copy_newer "$DOTS_TS_DIR/state/tailscaled.state" "$dir/tailscaled.state"
  _tsnet_copy_newer "$DOTS_TS_DIR/sshd/ssh_host_ed25519_key" "$dir/ssh_host_ed25519_key"
  _tsnet_copy_newer "$DOTS_TS_DIR/sshd/ssh_host_ed25519_key.pub" "$dir/ssh_host_ed25519_key.pub"
  _tsnet_copy_newer "$DOTS_TS_DIR/sshd/authorized_keys" "$dir/authorized_keys"
  _tsnet_copy_newer "$TSNET_DIR/tsnet.conf" "$dir/tsnet.conf"
  if [ -s "$TSNET_DIR/apt/user-status" ] && { [ ! -e "$dir/packages.txt" ] || [ "$TSNET_DIR/apt/user-status" -nt "$dir/packages.txt" ]; }; then
    (umask 077 && sed -n 's/^Package: //p' "$TSNET_DIR/apt/user-status" > "$dir/packages.txt") 2> /dev/null || true
  fi
}

# 지워진 Tailscale 상태 파일, SSH 호스트 키, authorized_keys 를 백업에서 되돌립니다.
# 비어 있는 자리만 채우고, 이미 있는 파일은 건드리지 않습니다. 되돌린 것이 있으면 한 줄로 알립니다.
tsnet_restore_identity() {
  local restored="" used="" f
  if [ ! -s "$DOTS_TS_DIR/state/tailscaled.state" ] && f="$(tsnet_backup_find tailscaled.state)"; then
    (umask 077 && mkdir -p -- "$DOTS_TS_DIR/state" && cp -p -- "$f" "$DOTS_TS_DIR/state/tailscaled.state") &&
      restored="$restored, Tailscale 상태" used="$(dirname -- "$f")"
  fi
  if [ ! -e "$DOTS_TS_DIR/sshd/ssh_host_ed25519_key" ] && [ ! -e "$DOTS_TS_DIR/sshd/ssh_host_ed25519_key.pub" ] &&
    f="$(tsnet_backup_find ssh_host_ed25519_key)" && [ -s "$f.pub" ] && [ ! -L "$f.pub" ]; then
    (umask 077 && mkdir -p -- "$DOTS_TS_DIR/sshd" && cp -p -- "$f" "$f.pub" "$DOTS_TS_DIR/sshd/") &&
      restored="$restored, SSH 호스트 키" used="${used:-$(dirname -- "$f")}"
  fi
  if [ ! -e "$DOTS_TS_DIR/sshd/authorized_keys" ] && f="$(tsnet_backup_find authorized_keys)"; then
    (umask 077 && mkdir -p -- "$DOTS_TS_DIR/sshd" && cp -p -- "$f" "$DOTS_TS_DIR/sshd/authorized_keys") &&
      restored="$restored, authorized_keys" used="${used:-$(dirname -- "$f")}"
  fi
  if [ -n "$restored" ]; then printf '백업(%s)에서 되돌렸습니다:%s\n' "$used" "${restored#,}"; fi
}

tsnet_sha256() { sha256sum -- "$1" 2> /dev/null | cut -d ' ' -f 1; }

# 대화형 SSH(PTY) 보정 라이브러리 경로입니다(lib/pty_chown_shim.c 를 설치할 때 컴파일).
tsnet_pty_shim() { printf '%s\n' "$TSNET_DIR/lib/pty_chown_shim.so"; }

# PTY 보정 라이브러리를 컴파일합니다. C 컴파일러가 없으면 건너뜁니다(대화형 SSH 만 영향).
tsnet_build_pty_shim() {
  local src="$1" out
  out="$(tsnet_pty_shim)"
  [ "${TSNET_SSH_PTY_FIX:-1}" = 1 ] || return 0
  command -v cc > /dev/null 2>&1 || {
    echo "참고: C 컴파일러(cc)가 없어 대화형 SSH 보정을 만들지 못했습니다. 'ssh -T' 처럼 PTY 없이는 접속됩니다."
    return 0
  }
  install -d -m 700 "$(dirname -- "$out")"
  if cc -shared -fPIC -O2 -o "$out.tmp" "$src" 2> /dev/null || cc -shared -fPIC -O2 -o "$out.tmp" "$src" -ldl; then
    chmod 644 "$out.tmp" && mv -f -- "$out.tmp" "$out"
  else
    rm -f -- "$out.tmp"
    echo "참고: 대화형 SSH 보정 라이브러리를 컴파일하지 못했습니다." >&2
  fi
}

# dots-tailscale 의 start.sh 에 붙일 LD_PRELOAD 를 TSNET_PRELOAD_ARGS 배열에 담습니다(보정 라이브러리가 있을 때만).
# start.sh 가 띄우는 sshd 에 붙고, sshd 는 로그인한 셸의 환경을 새로 만들므로 사용자 셸에는 넘어가지 않습니다.
tsnet_preload_args() {
  TSNET_PRELOAD_ARGS=()
  if [ "${TSNET_SSH_PTY_FIX:-1}" = 1 ] && [ -f "$(tsnet_pty_shim)" ]; then
    TSNET_PRELOAD_ARGS=("LD_PRELOAD=$(tsnet_pty_shim)")
  fi
}

# 실행 중인 sshd 리스너가 PTY 보정 없이 떠 있으면 리스너만 멈춥니다. 이어서 실행하는 start.sh 가 보정과 함께
# 다시 띄웁니다. 이미 열린 SSH 세션은 별도 프로세스라 끊기지 않습니다.
tsnet_refresh_sshd() {
  local pid name rest
  [ "${#TSNET_PRELOAD_ARGS[@]}" -gt 0 ] || return 0
  while read -r pid name rest; do
    [ "$name" = sshd ] || continue
    if ! grep -qF "$(tsnet_pty_shim)" "/proc/$pid/maps" 2> /dev/null; then
      echo "대화형 SSH 보정을 붙이려고 sshd 리스너(PID $pid)를 다시 띄웁니다. 열린 SSH 세션은 그대로입니다."
      kill -TERM "$pid" 2> /dev/null || true
      sleep 1
    fi
  done <<< "$(tsnet_install_processes "$DOTS_TS_DIR")"
}

# dots-tailscale 설치 기록(source-manifest.json)에 적힌 setup.sh 원본의 SHA-256 입니다.
tsnet_manifest_setup_hash() {
  python3 - "$DOTS_TS_DIR/source-manifest.json" << 'PY' 2> /dev/null || true
import json, sys
print(json.load(open(sys.argv[1]))["files"]["tailscale-setup.sh"])
PY
}
