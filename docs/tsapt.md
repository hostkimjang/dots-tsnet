# tsapt

English · [한국어](tsapt.ko.md) · [Back to README](../README.en.md)

tsapt is a small Python tool that installs apt packages on a Dots cloud computer without root. Once dots-tsnet is installed, typing `apt`, `apt-get` or `apt-cache` runs tsapt, so you can keep using apt as usual. Its messages are in Korean for now.

## Try it

```text
$ apt-get update
...
tsapt: 시스템 패키지 1430개를 설치된 것으로 인식했습니다 (tsapt 설치 0개).
      (treated 1430 system packages as already installed)

$ apt-get install -y iperf3
tsapt: 3개 패키지를 /workspace/shared/.tsnet/root 에 설치합니다: libsctp1 1.0.21+dfsg-1, libiperf0 3.18-2+deb13u2, iperf3 3.18-2+deb13u2
      (installing 3 packages into /workspace/shared/.tsnet/root)
...

$ iperf3 --version
iperf 3.18 (cJSON 1.7.15)
```

Libraries that the system already has are not downloaded again; only the missing ones (here `libsctp1` and `libiperf0`) are.

## Why regular apt does not work

The user account on a Dots computer has no sudo, and system directories such as `/usr`, `/etc` and `/var` cannot be written. The image we tested also has no `/var/lib/dpkg` or `/var/lib/apt`, where apt records what is installed. So `apt-get update` fails with permission errors even when the network is open.

## How it works

1. **A separate apt configuration.** tsapt runs the real `/usr/bin/apt-get` with `APT_CONFIG` pointing at `/workspace/shared/.tsnet/apt/apt.conf`. Package lists, install state, cache and logs all live under `/workspace/shared/.tsnet/apt`. On first run, the source list is generated from `/etc/os-release` using official mirrors (deb.debian.org for Debian, archive.ubuntu.com for Ubuntu).
2. **Inferring what is already installed.** With no dpkg records, tsapt marks as installed every package that has a directory in `/usr/share/doc`, every required or Essential package, and everything those depend on. Dependency fields are copied as well, so apt neither re-downloads system packages nor counts them as upgradable.
3. **Downloading only what is missing.** `apt-get install --download-only` fetches just the missing `.deb` files. Downloads go through tailscaled's HTTP proxy (`127.0.0.1:1056` by default) and out via `{exit-node}`.
4. **Unpacking into your own directory.** `dpkg-deb -x` unpacks into `/workspace/shared/.tsnet/root`. Absolute symlinks inside packages are rewritten to point inside that directory. `update-alternatives --install` entries from install scripts (postinst) become symlinks when the system does not already have that path; that is how figlet's `/usr/bin/figlet` appears.
5. **Ready to run.** `env.sh` has already added that directory to `PATH`, `LD_LIBRARY_PATH` and `PYTHONPATH`, so programs work right after installation.

## Command reference

| You type | tsapt does |
|---|---|
| `apt-get update`, `apt update` | Refreshes lists and recalculates install state |
| `apt-get install [-y] [-s] [-d] {package}` | Installs. `-s` only shows the plan, `-d` only downloads. Without `-y` in a terminal, it asks first |
| `apt install ./{file}.deb` | Installs a local file and downloads its dependencies |
| `apt upgrade`, `dist-upgrade`, `full-upgrade` | Upgrades packages installed by tsapt only |
| `apt remove`, `purge` | Removes packages installed by tsapt only |
| `apt autoremove` | Says there is nothing to clean up |
| `apt list`, `apt search`, `apt show` | Regular apt output, based on tsapt's install state |
| `apt-cache ...` | Regular apt-cache |
| `apt-get download`, `source`, `changelog`, `clean` | Regular apt-get |
| `sudo apt ...` | On computers without sudo, runs the same command without it |
| `tsapt list` | Lists packages installed by tsapt |

Commands that truly need a system dpkg install, such as `build-dep` and `satisfy`, are refused with a short message.

## Limits

- **Install scripts are not run.** Maintainer scripts such as postinst are skipped. Packages that need a service daemon, new users or groups, setuid binaries, or configuration generated at install time may not work.
- **Some programs look in fixed paths.** A program that looks for data in a fixed path such as `/usr/share/...` will not find files under `/workspace/shared/.tsnet/root`. figlet, for example, installs fine but looks for fonts in `/usr/share/figlet`, so running it plainly gives a font error. Use an option or environment variable that points to the data, such as `figlet -d /workspace/shared/.tsnet/root/usr/share/figlet`.
- **Check your Python version.** `python3-*` packages are built for the system `/usr/bin/python3`. If `python3` in your shell is a different interpreter, C extension modules may not load. In our environment, the Codex runtime's Python 3.12 came before the system Python 3.13 in the login shell's PATH. Use `/usr/bin/python3` directly, or install with pip.
- **Library search order.** `LD_LIBRARY_PATH` is searched before system libraries. Since system libraries are never downloaded again, this is usually fine; if something misbehaves, try removing the most recently installed package.
- **Downloaded files stay.** Downloaded `.deb` files remain in `/workspace/shared/.tsnet/apt/cache/archives`. `apt-get clean` removes them.

## File locations

| Path | Contents |
|---|---|
| `/workspace/shared/.tsnet/root` | Where packages are unpacked |
| `/workspace/shared/.tsnet/apt/sources.list` | Repository list. Run `apt update` after editing |
| `/workspace/shared/.tsnet/apt/state` | Package lists and the inferred install state |
| `/workspace/shared/.tsnet/apt/user-status` | Packages installed by tsapt |
| `/workspace/shared/.tsnet/apt/info/*.list` | Files installed by each package, used for removal |
| `/workspace/shared/.tsnet/apt/cache/archives` | Downloaded `.deb` files |
