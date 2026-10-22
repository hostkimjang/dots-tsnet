<h1 align="center">dots-tsnet</h1>

<p align="center"><a href="README.md">한국어</a> · English</p>

dots-tsnet routes package downloads on a ChatGPT Dots cloud computer (`apt-get`, `pip`, `curl`, git over HTTPS) through your own Tailscale exit node, and lets you install apt packages without root. Tailscale and SSH come from [abruption/dots-tailscale](https://github.com/abruption/dots-tailscale), which this project pins as a submodule and does not modify.

This is a personal project. It is not affiliated with OpenAI, Tailscale, or dots-tailscale.

## Why

On a Dots computer the terminal cannot reach the internet directly, the user has no sudo, and the system directories and dpkg database are not writable. So `apt-get update` fails with permission errors and most downloads fail to connect. After installing dots-tsnet:

- `apt`, `apt-get` and `apt-cache` are handled by **tsapt**, which resolves dependencies with the real apt and unpacks packages into `/workspace/.tsnet/root`. `sudo apt ...` works when sudo is missing. The commands are linked through PATH, so they also work inside scripts.
- New shells export `http_proxy` and `https_proxy` pointing at tailscaled's local HTTP proxy, so pip, curl, git and npm leave through the exit node.
- Settings and installed packages live under `/workspace` and survive VM replacement.

## Install

You need an approved exit node in your tailnet first; see [docs/exit-node.ko.md](docs/exit-node.ko.md) (Korean). Then, in the Dots terminal:

```bash
cd /workspace
HTTPS_PROXY=http://browser-proxy:8889 HTTP_PROXY=http://browser-proxy:8889 \
  git clone --recurse-submodules https://github.com/hostkimjang/dots-tsnet.git
cd dots-tsnet
bash install.sh --exit-node my-home-pc
```

The installer installs dots-tailscale v0.4.0 if it is missing (verified against pinned SHA-256 values), installs `tsnet` and `tsapt`, hooks `~/.bashrc`, selects the exit node, and finally restarts tailscaled with a local SOCKS5 (1055) and HTTP (1056) proxy. The restart drops SSH sessions for a few seconds; from SSH, pass `--detach` to run it outside the session with automatic rollback and a `start.sh` fallback.

## Usage

```bash
tsnet status                 # exit node, proxy, public IP seen through the proxy
tsnet exit-node [name|off]   # list, select, or clear the exit node
apt-get update
apt-get install -y pv
apt upgrade                  # upgrades packages installed by tsapt
apt remove pv
tsnet_off / tsnet_on         # disable or enable the proxy in the current shell
```

Settings live in `/workspace/.tsnet/tsnet.conf`; the Korean README lists every key.

## Limitations

- Maintainer scripts (postinst and friends) are not run, so daemons, setuid tools and packages that configure themselves at install time may not work. Simple `update-alternatives` links are recreated.
- Traffic goes through Tailscale DERP relays, so expect a few hundred kB/s.
- Only programs started from the shell are affected. The browser, ChatGPT connectors and the Dots agent itself are not.

Verified on 2026-10-22 on a Dots computer (Debian 13, x86_64) with dots-tailscale v0.4.0 and a Windows 11 exit node. See [docs/CHECKLIST.md](docs/CHECKLIST.md).

## License

MIT. dots-tailscale is MIT licensed by abruption and contributors; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
