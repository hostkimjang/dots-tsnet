# dots-tsnet 셸 환경입니다. ~/.bashrc 에서 불러옵니다.
# apt, apt-get, apt-cache 를 tsapt 로 연결하고, 다운로드가 Tailscale exit node 로 나가도록 프록시 변수를 설정합니다.
[ -n "${BASH_VERSION:-}" ] || return 0
TSNET_DIR="${TSNET_DIR:-/workspace/.tsnet}"
{ [ -f "$TSNET_DIR/lib/common.sh" ] && [ -f "$TSNET_DIR/tsnet.conf" ]; } || return 0
. "$TSNET_DIR/lib/common.sh"
tsnet_load_conf "$TSNET_DIR/tsnet.conf"
tsnet_defaults

_tsnet_prepend() {
  local cur="${!1:-}"
  case ":$cur:" in *":$2:"*) ;; *) export "$1=$2${cur:+:$cur}" ;; esac
}
_tsnet_prepend PATH "$TSNET_ROOT/usr/games"
_tsnet_prepend PATH "$TSNET_ROOT/usr/sbin"
_tsnet_prepend PATH "$TSNET_ROOT/usr/bin"
_tsnet_prepend PATH "$TSNET_DIR/bin"
if [ "$TSNET_APT_SHIM" = 1 ]; then _tsnet_prepend PATH "$TSNET_DIR/shims"; fi
_tsnet_prepend LD_LIBRARY_PATH "$TSNET_ROOT/usr/lib"
_tsnet_prepend LD_LIBRARY_PATH "$TSNET_ROOT/usr/lib/${HOSTTYPE:-x86_64}-linux-gnu"
if [ "$TSNET_PYTHONPATH" = 1 ]; then _tsnet_prepend PYTHONPATH "$TSNET_ROOT/usr/lib/python3/dist-packages"; fi
unset -f _tsnet_prepend

# 현재 셸의 HTTP(S) 다운로드를 tailscaled 프록시로 보내거나 되돌립니다.
tsnet_on() {
  export http_proxy="$TSNET_HTTP_PROXY" https_proxy="$TSNET_HTTP_PROXY"
  export HTTP_PROXY="$TSNET_HTTP_PROXY" HTTPS_PROXY="$TSNET_HTTP_PROXY"
  export no_proxy="$TSNET_NO_PROXY" NO_PROXY="$TSNET_NO_PROXY"
}
tsnet_off() { unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; }
if [ "$TSNET_AUTO_PROXY" = 1 ]; then tsnet_on; fi

# sudo 가 없는 컴퓨터에서 'sudo apt ...' 를 그대로 쓸 수 있게 합니다.
if [ "$TSNET_SUDO_SHIM" = 1 ] && ! type -P sudo > /dev/null 2>&1; then
  sudo() {
    local -a envs=()
    while [ $# -gt 0 ]; do
      case "$1" in
        -u | -g | --user | --group) shift 2 ;;
        --) shift; break ;;
        -*) shift ;;
        *=*) envs+=("$1"); shift ;;
        *) break ;;
      esac
    done
    case "${1:-}" in
      apt | apt-get | apt-cache | tsapt) env "${envs[@]}" "$@" ;;
      *)
        printf 'sudo: 이 컴퓨터에는 sudo 가 없습니다. apt, apt-get 은 sudo 없이 tsapt 로 동작합니다.\n' >&2
        return 1
        ;;
    esac
  }
fi
true
