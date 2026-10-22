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

tsnet_defaults() {
  : "${TSNET_DIR:=/workspace/.tsnet}"
  : "${DOTS_TS_DIR:=/workspace/.dots-tailscale}"
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
