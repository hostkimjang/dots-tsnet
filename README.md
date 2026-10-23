<h1 align="center">dots-tsnet</h1>

<p align="center">한국어 · <a href="README.en.md">English</a></p>

ChatGPT Dots 클라우드 컴퓨터의 터미널에서 `apt-get install`, `pip install`, `curl` 같은 다운로드가 **내 집 PC나 중계 서버를 거쳐** 인터넷으로 나가게 해 줍니다. 덤으로, root 권한이 없어도 `apt-get install`로 패키지를 설치할 수 있게 합니다.

Dots 컴퓨터에 Tailscale과 SSH를 올리는 부분은 [abruption/dots-tailscale](https://github.com/abruption/dots-tailscale)을 고치지 않고 그대로 씁니다. dots-tsnet은 그 위에 "다운로드가 어느 길로 나갈지"와 "패키지를 어디에 설치할지"를 더하고, Dots 저장소 정리에도 설치가 살아남도록 `/workspace/shared`에 설치합니다.

> OpenAI, Tailscale, dots-tailscale의 공식 프로젝트가 아닌 개인 프로젝트입니다. Dots 환경이 바뀌면 동작하지 않을 수 있습니다.

## 목차

- [왜 필요한가요](#왜-필요한가요)
- [준비물과 `{exit-node}`](#준비물과-exit-node)
- [설치하기](#설치하기)
- [매일 쓰는 명령](#매일-쓰는-명령)
- [설치 위치와 백업](#설치-위치와-백업)
- [속도](#속도)
- [설정 바꾸기](#설정-바꾸기)
- [exit node 없이 tailnet 기기에 접속하기](#exit-node-없이-tailnet-기기에-접속하기)
- [VM이 바뀌거나 설치 폴더가 지워졌을 때](#vm이-바뀌거나-설치-폴더가-지워졌을-때)
- [자주 묻는 질문](#자주-묻는-질문)
- [문제 해결](#문제-해결)
- [제거하기](#제거하기)

## 왜 필요한가요

Dots 터미널에서 처음 `apt-get update`를 실행하면 대개 이렇게 실패합니다.

```text
W: Unable to read /etc/apt/apt.conf.d/80-applied-apt-retries - open (13: Permission denied)
E: List directory /var/lib/apt/lists/partial is missing. - Acquire (2: No such file or directory)
```

원인은 세 가지입니다.

1. **sudo가 없습니다.** 일반 사용자 계정(uid 1000)으로만 작업합니다.
2. **시스템 폴더에 쓸 수 없습니다.** `/usr`, `/etc`, `/var`는 쓰기가 막혀 있고, apt가 설치 기록을 남기는 `/var/lib/dpkg`도 아예 없습니다.
3. **인터넷으로 바로 나갈 수 없습니다.** 플랫폼이 주는 HTTPS 프록시(`browser-proxy:8889`)를 거쳐야 하고, 이 프록시는 HTTPS 내용을 열어 봅니다.

dots-tsnet을 설치하면 다운로드가 이렇게 나갑니다.

```mermaid
flowchart LR
  A["apt-get, pip, curl<br/>(Dots 터미널)"] --> B["tailscaled 로컬 프록시<br/>127.0.0.1:1056"]
  B -->|"Tailscale (암호화)"| C["{exit-node}<br/>집 PC 또는 중계 서버"]
  C --> D["인터넷<br/>deb.debian.org, pypi.org ..."]
```

- **`apt`를 그대로 씁니다.** `apt`, `apt-get`, `apt-cache`를 입력하면 [tsapt](docs/tsapt.ko.md)가 받아서 의존성까지 내려받고 `/workspace/shared/.tsnet/root`에 설치합니다. sudo가 없으니 `sudo apt install ...`도 같은 명령으로 처리합니다. 셸 alias가 아니라 PATH 앞쪽에 둔 연결이라 스크립트 안에서 불러도 똑같이 동작합니다.
- **다운로드가 내 기기를 거쳐 나갑니다.** 새 셸에는 `http_proxy`, `https_proxy`가 잡혀 있어서 pip, curl, git(https), npm도 `{exit-node}`를 거쳐 나갑니다. 밖에서 보면 `{exit-node}`의 공인 IP에서 온 요청입니다.
- **한 번만 설치하면 됩니다.** 프로그램, 설정, 설치한 패키지를 모두 `/workspace/shared`(`.tsnet`, `.dots-tailscale`)에 둡니다. Dots의 scratch 정리 작업이 `/workspace` 최상위 폴더를 지울 때도 남는 곳이고, Dots 데스크톱도 사용자 설정을 이곳에 보존합니다. 자세한 내용은 [설치 위치와 백업](#설치-위치와-백업)에 있습니다.

어떻게 동작하는지 자세히 알고 싶다면 [동작 원리](docs/how-it-works.ko.md)를 보세요. tailscaled 실행 명령, Python shim이 하는 일, 측정한 네트워크 제약, 정리 작업 관찰 기록을 모두 정리해 두었습니다.

## 준비물과 `{exit-node}`

| 준비물 | 설명 |
|---|---|
| Tailscale 계정 | 무료 플랜으로 충분합니다 |
| Dots 클라우드 컴퓨터 | dots-tailscale이 없으면 설치 스크립트가 함께 설치합니다 |
| `{exit-node}` 기기 한 대 | 다운로드가 거쳐 나갈 **집 PC 또는 중계 서버** |

이 문서에서 `{exit-node}`라고 쓴 자리에는 그 기기의 **Tailscale 이름**을 넣습니다. 이름은 아무 기기에서나 `tailscale status`를 실행했을 때 두 번째 열에 나오는 값이고, [관리 콘솔의 Machines](https://console.tailscale.com/admin/machines) 화면에도 같은 이름이 보입니다. 예를 들어 집 PC 이름이 `home-pc`라면 `--exit-node home-pc`처럼 씁니다.

어떤 기기를 고를지 망설여진다면 이렇게 보면 됩니다.

- **집 PC**: 가장 빨리 시작할 수 있습니다. 다만 PC가 꺼지거나 절전 상태가 되면 Dots의 다운로드도 함께 멈춥니다.
- **중계 서버**: NAS, 공유기나 방화벽(OPNsense 등), 작은 클라우드 VM처럼 늘 켜져 있는 기기입니다. 오래 쓸 생각이라면 이쪽을 권합니다.

두 대를 모두 준비해 두면 하나가 꺼졌을 때 `tsnet exit-node {다른-기기}`로 바로 바꿀 수 있습니다.

## 설치하기

### 1단계: `{exit-node}` 준비

[exit node 준비하기](docs/exit-node.ko.md)를 따라 집 PC나 중계 서버에서 exit node를 켜고, Tailscale 관리 콘솔에서 승인합니다. 보통 5분이면 끝납니다.

### 2단계: Dots 터미널에서 내려받기

Dots 화면의 터미널(권장)이나 SSH 세션에서 실행합니다. Dots 터미널은 GitHub에 바로 연결하지 못하므로, 이번 한 번만 플랫폼 프록시를 지정해서 내려받습니다. 저장소는 어디에 받아도 되고, 설치 위치는 설치 스크립트가 정합니다.

```bash
cd ~
HTTPS_PROXY=http://browser-proxy:8889 HTTP_PROXY=http://browser-proxy:8889 \
  git clone --recurse-submodules https://github.com/hostkimjang/dots-tsnet.git
cd dots-tsnet
```

### 3단계: 설치 스크립트 실행

`{exit-node}` 자리에 1단계에서 준비한 기기 이름을 넣습니다.

```bash
bash install.sh --exit-node {exit-node}
```

설치 스크립트는 아래 순서로 진행하고, 이미 끝난 단계는 건너뜁니다.

1. **dots-tailscale 설치와 로그인**: 없으면 고정된 버전(v0.4.0)을 SHA-256으로 확인한 뒤 `/workspace/shared/.dots-tailscale`에 설치합니다. 처음이라면 Tailscale 로그인 URL이 나오니 브라우저에서 열어 승인하세요. 내 PC에서 SSH로 들어오고 싶다면 `--authorized-key '{ssh-public-key}'`로 공개키(`ssh-ed25519 AAAA...` 한 줄)를 함께 등록합니다.
2. **dots-tsnet 설치**: `tsnet`, `tsapt`, 셸 환경 파일을 `/workspace/shared/.tsnet`에 넣고 `~/.bashrc`에 연결합니다. 대화형 SSH가 끊기지 않게 하는 작은 보정 라이브러리도 이때 만듭니다([동작 원리](docs/how-it-works.ko.md#대화형-sshpty-보정)).
3. **exit node 지정**: Dots의 Tailscale이 `{exit-node}`로 나가도록 설정합니다.
4. **로컬 프록시 열기**: tailscaled를 SOCKS5(`127.0.0.1:1055`)와 HTTP(`127.0.0.1:1056`) 프록시와 함께 다시 시작합니다.

예전 버전으로 홈 폴더(0.1.2)나 `/workspace`(0.1.1 이하)에 설치했다면 같은 명령이 기존 설치를 `/workspace/shared`로 옮깁니다. Tailscale 기기 신원, SSH 키, 설정, 설치한 패키지를 그대로 가져가므로 다시 로그인하지 않아도 됩니다. 새 위치에서 띄우지 못하면 기존 설치로 되돌립니다. 옮기는 동안 tailscaled를 다시 띄우느라 SSH가 1~2분 끊기므로, SSH에서는 `--detach`를 붙여 실행합니다.

> **SSH로 접속해서 설치하는 경우**: 4번 단계나 기존 설치를 옮길 때 tailscaled가 다시 시작되면서 SSH 연결이 1~2분 끊깁니다. 물어볼 때 `y`를 입력하거나 처음부터 `--detach`를 붙이면 SSH 세션과 분리해서 진행하고, 실패하면 이전 상태로 되돌립니다. 기존 설치를 옮기는 기록은 `~/dots-tsnet-install.log`에 남습니다. Dots 화면의 터미널에서 실행하면 이런 걱정이 없습니다.

### 4단계: 확인

새 셸을 열거나 `source ~/.bashrc`를 실행한 다음 상태를 봅니다.

```bash
tsnet status
```

이런 모양이면 정상입니다.

```text
[exit node]
  {exit-node} 100.x.y.z online=True / 경로: DERP 릴레이 tok
[로컬 프록시]
  설정: {'http_port': 1056, 'socks_port': 1055} / 실행 중: {'http_port': 1056, 'socks_port': 1055} / 재시작 필요: False
[dots-tailscale]
  v0.4.0 / 파일 무결성: match
[tailscaled]
  PID 1234 / TS_ 환경변수: 없음
[설치 위치와 백업]
  설치: /workspace/shared/.tsnet, /workspace/shared/.dots-tailscale
  백업: /home/agent/.local/state/dots-tsnet / Tailscale 상태 2026-10-23 19:18 기준
[셸 연결]
  apt 연결: 켜짐 / sudo 대체: 켜짐 / 새 셸 자동 프록시: 켜짐
  지금 셸의 apt-get: /workspace/shared/.tsnet/shims/apt-get
[외부로 보이는 IP]
  프록시 경유: 203.0.113.10
```

마지막 줄의 IP가 `{exit-node}`의 공인 IP와 같으면 다운로드가 그 기기를 거쳐 나가고 있는 것입니다. 이제 패키지를 하나 설치해 봅니다.

```bash
apt-get update
apt-get install -y pv
pv --version
```

## 매일 쓰는 명령

| 하고 싶은 일 | 명령 |
|---|---|
| 지금 상태 보기 | `tsnet status` |
| 패키지 목록 갱신 | `apt-get update` 또는 `apt update` |
| 패키지 설치 | `apt-get install -y {package}` (`sudo`를 붙여도 됩니다) |
| tsapt로 설치한 패키지 갱신 | `apt upgrade` |
| 패키지 제거 | `apt remove {package}` |
| tsapt로 설치한 패키지 목록 | `tsapt list` |
| 쓸 수 있는 exit node 목록 | `tsnet exit-node` |
| exit node 바꾸기, 끄기 | `tsnet exit-node {exit-node}`, `tsnet exit-node off` |
| 지금 셸에서만 프록시 끄기, 켜기 | `tsnet_off`, `tsnet_on` |
| 프록시를 끈 셸에서 명령 하나만 프록시로 | `tsnet run {command}` |
| dots-tailscale 점검 | `tsnet doctor` (dots-tailscale 파일을 직접 고쳤다면 `tsnet doctor --fix`) |
| `TSNET_TAILSCALED_ENV`를 바로 적용 | `tsnet restart` (SSH에서는 `tsnet restart --detach`) |
| VM이 바뀐 뒤 Tailscale 다시 띄우기 | `tsnet start` |

## 설치 위치와 백업

| 무엇 | 위치 |
|---|---|
| dots-tailscale(Tailscale, sshd, 기기 신원) | `/workspace/shared/.dots-tailscale` |
| dots-tsnet(tsnet, tsapt, 설정, 설치한 패키지) | `/workspace/shared/.tsnet` |
| 기기 신원 백업 | `~/.local/state/dots-tsnet` |
| 실행 중 소켓과 로그 | `/tmp/dots-tailscale-1000` |

`/workspace/shared`가 없는 환경에서는 홈 폴더(`~/.tsnet`, `~/.dots-tailscale`)에 설치하고, 백업은 `/workspace/shared/.dots-tsnet-backup`에 둡니다.

**왜 `/workspace/shared`인가요.** 2026-10-23 06:49에 Dots의 scratch 정리 작업이 `/workspace` 최상위 폴더 여럿을 지웠습니다. 이 작업은 `/workspace/.scratch-cleaning/<작업 ID>`에 `v1`이라는 기록을 남겼습니다. `/workspace/.tsnet`, `/workspace/.dots-tailscale`, 저장소 사본이 사라졌고, Dots 작업 폴더인 `/workspace/scratch`와 홈 폴더는 남았습니다. 같은 작업이 같은 초에 `/workspace/shared`를 새로 만들었습니다. Dots 데스크톱 설정 파일(`/etc/orbit-os/config.toml`)도 사용자 설정을 `/workspace/shared/.orbit-os`에 보존(persist)한다고 적고 있습니다. 홈 폴더도 이번 정리에서는 남았지만, 안의 내용이 모두 VM이 켜진 뒤에 만들어진 것이라 VM이 바뀌어도 남는다는 근거가 없습니다. 그래서 Dots가 직접 보존용으로 쓰는 `/workspace/shared`에 설치합니다. 관찰 기록은 [동작 원리](docs/how-it-works.ko.md#dots-저장소와-설치-위치)에 있습니다.

**백업.** 기기 신원(Tailscale 상태 파일), SSH 호스트 키, `authorized_keys`, `tsnet.conf`, 설치한 패키지 목록을 설치 반대편인 홈 폴더(`~/.local/state/dots-tsnet`)에 복사해 둡니다. 새 셸을 열 때와 `tsnet start`, `tsnet status`를 실행할 때 바뀐 파일만 복사합니다. 어느 한쪽이 지워지면 `install.sh`가 다른 쪽에서 되돌리고, 예전 버전의 백업 위치(`/workspace/.dots-tsnet-backup`)도 찾아봅니다. 백업에는 Tailscale 개인키가 들어 있으니 다른 컴퓨터로 복사하지 마세요.

**작업물은 Dots 밖에도 백업하세요.** 설치와 백업은 같은 디스크에 있어서, Dots 환경이 통째로 예전 스냅숏으로 돌아가면 함께 되돌아갈 수 있습니다. 최근 작업이 사라지고 오래된 파일만 남았다는 보고도 여럿 있습니다([openai/codex#52765](https://github.com/openai/codex/issues/52765)). dots-tsnet은 저장소를 다시 받아 설치하면 되고, 기기 신원을 잃어도 `--new-identity`로 다시 로그인하면 됩니다. 하지만 Dots에서 만든 작업물은 Google Drive나 ChatGPT Library처럼 Dots 밖에도 두는 것이 안전합니다. Dots 샌드박스에는 `/dev/fuse`가 없어서 Google Drive를 마운트할 수는 없지만, `rclone copy`로 주기적으로 복사할 수는 있습니다.

**다른 곳에 두고 싶다면** 설치할 때 위치를 지정합니다. 홈 폴더에 두면 백업은 `/workspace/shared/.dots-tsnet-backup`으로 갑니다.

```bash
TSNET_DIR=~/.tsnet DOTS_TS_DIR=~/.dots-tailscale bash install.sh --exit-node {exit-node}
```

## 속도

Dots에서는 Tailscale 기기끼리 직접 연결(P2P)이 만들어지지 않아서, 모든 트래픽이 Tailscale의 DERP 중계 서버를 거칩니다. 그래서 다운로드는 수백 kB/s 수준이고, 시간대와 그때그때의 중계 경로에 따라 크게 달라집니다. 아래는 2026-10-23에 한국에 있는 `{exit-node}`(Windows PC, OPNsense)로 같은 7MB 파일을 받아 본 결과입니다.

| 경로 | 잰 시각 | 속도 |
|---|---|---|
| `{exit-node}` 경유, 연결 1개 | 새벽 3시 | 340~720kB/s |
| `{exit-node}` 경유, 연결 1개 | 저녁 7~8시 | 90~230kB/s |
| `{exit-node}` 경유, 연결 4개를 동시에 | 새벽 | 합쳐서 약 620kB/s |
| 플랫폼 프록시(`browser-proxy`)로 바로 | 새벽 | 약 18MB/s |

같은 설정으로 연달아 받아도 두 배 가까이 차이가 났고, tailscaled를 다시 띄운 직후 첫 다운로드가 느린 경향이 있었습니다. 직접 연결이 안 되는 이유는 [동작 원리](docs/how-it-works.ko.md#항상-derp를-거치는-이유와-속도)에 정리했습니다.

**apt만 빠르게 받고 싶다면** `/workspace/shared/.tsnet/tsnet.conf`에서 `TSNET_APT_PROXY=http://browser-proxy:8889`로 바꿉니다. apt 다운로드만 플랫폼 프록시로 나가고 pip, curl 등은 계속 `{exit-node}`를 거칩니다. 대신 플랫폼 프록시는 HTTPS 내용을 열어 보는 프록시라서 어떤 패키지를 받는지 플랫폼이 볼 수 있습니다. apt는 패키지의 GPG 서명을 확인하므로, 중간에 내용이 바뀌면 설치 단계에서 거부됩니다.

## 설정 바꾸기

설정 파일은 `/workspace/shared/.tsnet/tsnet.conf`입니다. `이름=값` 형식이고, 같은 이름의 환경변수가 있으면 그 값이 먼저입니다.

| 설정 | 기본값 | 설명 |
|---|---|---|
| `TSNET_EXIT_NODE` | 비어 있음 | 쓸 exit node. `tsnet exit-node`가 함께 바꿉니다 |
| `TSNET_SOCKS_PORT`, `TSNET_HTTP_PORT` | `1055`, `1056` | 로컬 프록시 포트. 바꾼 뒤 `tsnet apply` |
| `TSNET_AUTO_PROXY` | `1` | 새 셸에서 `http(s)_proxy`를 자동으로 설정 |
| `TSNET_APT_SHIM` | `1` | `apt`, `apt-get`, `apt-cache`를 tsapt로 연결 |
| `TSNET_SUDO_SHIM` | `1` | sudo가 없을 때 `sudo apt ...`를 tsapt로 연결 |
| `TSNET_PYTHONPATH` | `1` | tsapt로 설치한 `python3-*` 모듈을 `PYTHONPATH`에 추가 |
| `TSNET_APT_SOURCES` | `official` | `official`은 deb.debian.org 같은 공식 저장소, `system`은 이미지의 저장소 설정을 복사 |
| `TSNET_APT_PROXY` | 비어 있음 | apt 전용 프록시. 비우면 tailscaled HTTP 프록시, `off`면 직접 연결 |
| `TSNET_NO_PROXY` | `localhost,127.0.0.1,::1,browser-proxy` | 프록시를 거치지 않을 주소 |
| `TSNET_TAILSCALED_ENV` | 비어 있음 | tailscaled를 새로 띄울 때 붙일 `TS_이름=값` 목록. 바로 적용하려면 `tsnet restart`. GSO·GRO 끄기 같은 용도이며 [동작 원리](docs/how-it-works.ko.md#tailscale-udp-gsogro-설정)에 설명이 있습니다 |
| `TSNET_IDENTITY_BACKUP` | `1` | 기기 신원, SSH 호스트 키, 설정을 설치와 다른 위치에 백업 |
| `TSNET_SSH_PTY_FIX` | `1` | 대화형 SSH(PTY) 보정. 끄면 터미널 앱으로 접속할 때 바로 끊길 수 있습니다 |

설치 위치는 설치할 때 환경변수 `TSNET_DIR`(기본 `/workspace/shared/.tsnet`)과 `DOTS_TS_DIR`(기본 `/workspace/shared/.dots-tailscale`)로, 백업 위치는 `TSNET_BACKUP_DIR`로 바꿀 수 있습니다. `/workspace/shared`가 없으면 기본값은 홈 폴더입니다.

## exit node 없이 tailnet 기기에 접속하기

exit node는 **인터넷**으로 나가는 길만 정합니다. Dots와 내 tailnet 기기 사이의 통신에는 exit node가 필요 없습니다.

- **내 PC에서 Dots로 SSH**: `ssh agent@dots-sandbox` (dots-tailscale 기본 이름 기준)
- **Dots에서 tailnet 기기로**: Dots의 tailscaled는 TUN 장치 없이 동작하기 때문에, 프로그램이 로컬 프록시를 거쳐야 합니다.

```bash
curl -x http://127.0.0.1:1056 http://{tailnet-host}:{port}/
curl --socks5-hostname 127.0.0.1:1055 http://{tailnet-host}:{port}/
ssh -F /dev/null -o ProxyCommand="/workspace/shared/.dots-tailscale/dots-ts cli nc %h %p" {user}@{tailnet-host}
```

`{tailnet-host}`에는 접속할 tailnet 기기의 이름이나 `100.x.y.z` 주소를 넣습니다. 자세한 내용은 [동작 원리](docs/how-it-works.ko.md#exit-node-없이-tailnet에-접속하기)를 보세요.

## VM이 바뀌거나 설치 폴더가 지워졌을 때

**VM이 바뀐 경우.** `/workspace`가 남아 있으면 설정과 설치한 패키지도 그대로입니다. Tailscale만 다시 띄우면 됩니다. 홈 폴더가 초기화됐다면 `~/.bashrc` 연결도 다시 만듭니다.

```bash
/workspace/shared/.tsnet/bin/tsnet start          # Tailscale, SSH, 로컬 프록시 기동
/workspace/shared/.tsnet/bin/tsnet install-hook   # ~/.bashrc 연결이 사라졌을 때만
```

`tsnet start`는 dots-tailscale의 `start.sh`를 실행하면서 `TSNET_TAILSCALED_ENV`와 대화형 SSH 보정을 함께 넘깁니다.

**설치 폴더가 지워진 경우.** `tsnet` 명령이 없다고 나오거나, Chrome이나 apt가 갑자기 `ERR_TUNNEL_CONNECTION_FAILED`나 프록시 오류를 내면 설치 폴더가 지워졌을 수 있습니다. 저장소를 다시 받아 설치 스크립트를 실행합니다.

```bash
cd ~
HTTPS_PROXY=http://browser-proxy:8889 HTTP_PROXY=http://browser-proxy:8889 \
  git clone --recurse-submodules https://github.com/hostkimjang/dots-tsnet.git
cd dots-tsnet && bash install.sh
```

설치 스크립트는 이렇게 처리합니다.

- 지워진 파일로 아직 돌고 있는 옛 tailscaled, shim, sshd를 멈춥니다. 이 프로세스들이 포트와 소켓을 잡고 있으면 새로 띄울 수 없기 때문입니다.
- 백업에서 기기 신원, SSH 호스트 키, `tsnet.conf`를 되돌립니다. 그래서 같은 기기 이름과 같은 exit node 설정으로 돌아옵니다.
- 함께 지워진 패키지의 목록과, 다시 설치하는 명령을 알려 줍니다.

백업도 없다면 같은 기기로는 돌아갈 수 없습니다. 이때는 `bash install.sh --new-identity`로 새 기기로 로그인하고, 관리 콘솔에서 옛 기기를 지우거나 새 기기의 이름을 바꿉니다.

## 자주 묻는 질문

**공식적으로 지원되는 방법인가요?**
아닙니다. OpenAI도 Tailscale도 Dots에서 Tailscale을 쓰는 방법을 안내하지 않습니다. 일반 사용자 권한으로 Tailscale을 띄우고, 그 연결을 플랫폼 HTTPS 프록시로 통과시키는 우회 방식입니다. 플랫폼이 바뀌면 동작하지 않을 수 있습니다.

**Tailscale 직접 연결(P2P)은 안 되나요?**
지금은 안 됩니다. 우리가 시험한 범위에서 Dots의 UDP는 목적지 포트가 3478(STUN)일 때만 밖으로 나갔습니다. Tailscale 기기는 보통 41641이나 임의의 포트에서 기다리기 때문에 직접 연결이 만들어지지 않고, 항상 DERP 중계 서버를 거칩니다. `{exit-node}`가 UDP 3478에서 기다리게 하면 직접 연결이 생길 수도 있지만 아직 시험하지 않았습니다.

**플랫폼이 내 Tailscale 트래픽을 볼 수 있나요?**
tailscaled의 연결은 플랫폼 프록시를 거치고, 이 프록시는 TLS를 풀어 봅니다. 그래서 플랫폼은 Tailscale 서버(controlplane, DERP)에 접속한다는 사실과 HTTP 헤더를 볼 수 있습니다. 하지만 그 안의 제어 통신(Noise 암호화)과 tailnet 패킷(WireGuard 암호화)은 종단 간 암호화돼 있어서 내용은 보이지 않습니다. `{exit-node}`에서 인터넷으로 나간 뒤의 트래픽은 그 기기에서 직접 접속한 것과 같습니다.

**Tailscale의 UDP GSO·GRO를 끄면 빨라지나요?**
환경에 따라 다릅니다. 두 설정은 Tailscale이 UDP로 직접 통신할 때 쓰는 소켓의 오프로드를 끕니다. 커널 TUN이나 특정 커널·NIC에서 GSO가 제대로 동작하지 않는 곳에서는 끄면 크게 빨라집니다. 예를 들어 [tailscale#20858](https://github.com/tailscale/tailscale/issues/20858)에서는 약 20KiB/s가 14~20MB/s가 됐습니다. Dots에서는 트래픽이 모두 TCP 위의 DERP로 지나가서 이 설정이 닿는 경로가 없습니다. 2026-10-23에 끔과 켬을 번갈아 재 보니 끔은 117~124kB/s, 켬은 189kB/s였습니다. 다만 켬 단계의 왕복 지연도 192ms로 끔 단계(308~318ms)보다 낮았기 때문에, 차이는 경로 지연으로 설명됩니다. 끄고 싶다면 dots-tailscale 파일을 고치지 말고 `TSNET_TAILSCALED_ENV`를 쓰세요. 측정 기록과 적용 방법은 [동작 원리](docs/how-it-works.ko.md#tailscale-udp-gsogro-설정)에 있습니다.

## 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `tsapt: 프록시 http://127.0.0.1:1056 에 연결할 수 없습니다` | tailscaled가 꺼졌거나 로컬 프록시가 닫혔습니다. `tsnet status`로 확인하고, tailscaled가 없으면 `tsnet start`, 프록시만 닫혔으면 `tsnet apply` |
| 외부 IP 확인이 실패하거나 시간이 초과됨 | `{exit-node}`가 꺼졌거나 관리 콘솔에서 승인되지 않았습니다. `tsnet exit-node`로 목록을 보고, 급하면 `tsnet_off`로 잠시 프록시를 끕니다 |
| `tsnet` 명령이 없거나, Chrome·apt가 갑자기 `ERR_TUNNEL_CONNECTION_FAILED`나 프록시 500 오류를 냄 | 설치 폴더가 지워졌을 수 있습니다. [VM이 바뀌거나 설치 폴더가 지워졌을 때](#vm이-바뀌거나-설치-폴더가-지워졌을-때)를 따라 다시 설치합니다 |
| `previously authenticated state is missing`으로 멈춤 | 기기 신원 파일이 사라졌습니다. 백업이 있으면 `tsnet start`나 `install.sh`가 자동으로 되돌리고, 없으면 `tsnet start --new-identity` |
| `apt-get`이 아직 `/usr/local/bin/apt-get`을 가리킴 | 이 셸이 dots-tsnet 환경을 불러오지 않았습니다. `source ~/.bashrc`, 그래도 안 되면 `/workspace/shared/.tsnet/bin/tsnet install-hook` |
| 설치한 프로그램이 데이터 파일을 못 찾음 | tsapt는 설치 스크립트를 실행하지 않고 파일을 다른 위치에 풉니다. [tsapt의 한계](docs/tsapt.ko.md#한계)를 보세요 |
| `dots-ts doctor`가 `unhealthy`, `source integrity: mismatch` | dots-tailscale의 설치 파일(예: `setup.sh`)을 직접 고치면 나옵니다. `tsnet doctor --fix`가 직접 넣은 `TS_` 설정을 `tsnet.conf`로 옮기고 원본을 되살립니다 |
| 터미널 앱의 SSH가 `closed by remote host`로 바로 끊김(`ssh -T`는 됨) | sshd가 PTY 권한을 바꾸려다 실패합니다. `TSNET_SSH_PTY_FIX=1`(기본값)인지 확인하고 `tsnet start`를 실행하면 sshd가 보정과 함께 다시 뜹니다 |
| SSH가 `REMOTE HOST IDENTIFICATION HAS CHANGED`로 거부됨 | 다시 설치하면서 SSH 호스트 키가 바뀌었습니다. Dots 화면 터미널에서 `ssh-keygen -lf /workspace/shared/.dots-tailscale/sshd/ssh_host_ed25519_key.pub`로 지문을 확인한 뒤, 내 PC에서 `ssh-keygen -R {Dots 기기 이름}` |
| Dots에서 `ssh`가 `Bad owner or permissions on /etc/ssh/ssh_config.d/...`로 실패 | Dots 이미지의 시스템 SSH 설정 파일 권한 문제입니다. `ssh -F /dev/null ...`처럼 시스템 설정을 건너뜁니다 |

## 제거하기

```bash
cd ~/dots-tsnet
bash uninstall.sh                  # 설치한 패키지까지 모두 지움
bash uninstall.sh --keep-packages  # 설치한 패키지와 apt 캐시는 남김
```

dots-tailscale, Tailscale 로그인 상태, 백업(`~/.local/state/dots-tsnet`)은 건드리지 않습니다. exit node 기기에서 광고를 끄려면 그 기기에서 `tailscale set --advertise-exit-node=false`를 실행합니다.

## 더 읽을 거리

- [동작 원리](docs/how-it-works.ko.md): tailscaled 실행 명령, Python shim, 네트워크 제약, GSO·GRO, 정리 작업 관찰 기록, 대화형 SSH 보정
- [exit node 준비하기](docs/exit-node.ko.md): 집 PC 또는 중계 서버 설정
- [tsapt 설명](docs/tsapt.ko.md): root 없이 apt가 동작하는 방식과 한계
- [검증 체크리스트](docs/CHECKLIST.md), [변경 기록](CHANGELOG.md)

## 검증한 환경

2026-10-22~24에 Dots 클라우드 컴퓨터(Debian 13 trixie, x86_64)와 dots-tailscale v0.4.0(Tailscale 1.102.4)에서 확인했습니다. 예전 설치를 옮기는 과정(`/workspace` → 홈 폴더, 홈 폴더 → `/workspace/shared`)도 실제 Dots 컴퓨터에서 확인했습니다. `{exit-node}`는 Windows 11 PC(Tailscale 1.102.2)와 OPNsense 방화벽(FreeBSD 14.3, Tailscale 1.92.2) 두 가지로 시험했습니다.

## 라이선스

MIT입니다. dots-tailscale(MIT, abruption and contributors)은 `upstream/dots-tailscale` 서브모듈로 고치지 않고 연결합니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 있습니다.
