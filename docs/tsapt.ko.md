# tsapt 설명

tsapt는 root 권한이 없는 Dots 클라우드 컴퓨터에서 apt 패키지를 설치하는 도구입니다. dots-tsnet을 설치하면 `apt`, `apt-get`, `apt-cache`를 입력해도 tsapt가 받습니다.

## 일반 apt를 못 쓰는 이유

Dots 컴퓨터의 사용자 계정에는 sudo가 없고, `/usr`, `/etc`, `/var` 같은 시스템 폴더는 쓰기가 막혀 있습니다. 확인한 이미지에는 apt가 설치 상태를 기록하는 `/var/lib/dpkg`와 `/var/lib/apt`도 없습니다. 그래서 네트워크가 열려 있어도 `apt-get update`부터 권한 오류로 실패합니다.

## 동작 순서

1. **별도 apt 설정**: `/workspace/.tsnet/apt/apt.conf`를 `APT_CONFIG`로 지정해 진짜 `/usr/bin/apt-get`을 실행합니다. 상태, 목록, 캐시, 로그는 모두 `/workspace/.tsnet/apt` 아래에 둡니다. 저장소 파일은 처음 실행할 때 `/etc/os-release`를 보고 공식 저장소(Debian은 deb.debian.org, Ubuntu는 archive.ubuntu.com)로 만듭니다.
2. **설치된 패키지 추론**: dpkg 데이터베이스가 없으므로 `/usr/share/doc`에 문서 폴더가 있는 패키지, 필수(required, Essential) 패키지, 그리고 이들이 의존하는 패키지를 이미 설치된 것으로 기록합니다. 의존성 필드까지 그대로 옮기기 때문에 apt가 시스템 패키지를 다시 받거나 업그레이드 대상으로 세지 않습니다.
3. **내려받기**: `apt-get install --download-only`로 필요한 `.deb`만 받습니다. 다운로드는 tailscaled HTTP 프록시(기본 `127.0.0.1:1056`)를 지나 exit node로 나갑니다.
4. **풀기**: `dpkg-deb -x`로 `/workspace/.tsnet/root`에 풉니다. 패키지 안의 절대 경로 심볼릭 링크는 이 폴더 안을 가리키도록 고칩니다. postinst의 `update-alternatives --install` 항목은 시스템에 같은 경로가 없을 때만 심볼릭 링크로 만듭니다. figlet의 `/usr/bin/figlet`이 이렇게 생깁니다.
5. **경로 연결**: `env.sh`가 `PATH`, `LD_LIBRARY_PATH`, `PYTHONPATH`에 이 폴더를 넣어 두었으므로 설치 직후 바로 실행할 수 있습니다.

## 명령 대응

| 입력 | tsapt 동작 |
|---|---|
| `apt-get update`, `apt update` | 목록을 갱신하고 설치 상태를 다시 계산 |
| `apt-get install [-y] [-s] [-d] 패키지` | 설치. `-s`는 계획만, `-d`는 받기만 합니다. `-y`가 없고 터미널이면 확인을 묻습니다 |
| `apt install ./파일.deb` | 로컬 파일을 설치하고 의존성은 내려받음 |
| `apt upgrade`, `dist-upgrade`, `full-upgrade` | tsapt로 설치한 패키지만 갱신 |
| `apt remove`, `purge` | tsapt로 설치한 패키지만 제거 |
| `apt autoremove` | 정리할 것이 없다고 알리고 끝냄 |
| `apt list`, `apt search`, `apt show` | apt 출력 그대로 (tsapt 상태 기준) |
| `apt-cache ...` | apt-cache 그대로 |
| `apt-get download`, `source`, `changelog`, `clean` | apt-get 그대로 |
| `sudo apt ...` | sudo가 없는 컴퓨터에서 sudo 없이 같은 명령 실행 |

`build-dep`, `satisfy`처럼 시스템 dpkg 설치가 필요한 명령은 지원하지 않습니다.

## 한계

- **설치 스크립트**: postinst 같은 maintainer script는 실행하지 않습니다. 서비스 데몬, 사용자나 그룹 생성, setuid, 설치 중 설정 파일 생성이 필요한 패키지는 동작하지 않을 수 있습니다.
- **고정 경로**: 프로그램이 `/usr/share/...` 같은 고정 경로에서 데이터를 찾으면 `/workspace/.tsnet/root` 아래 파일을 찾지 못합니다. 예를 들어 figlet은 실행 파일은 생기지만 글꼴을 `/usr/share/figlet`에서 찾아서 그냥 실행하면 글꼴 오류가 납니다. 이런 프로그램은 `figlet -d /workspace/.tsnet/root/usr/share/figlet`처럼 데이터 경로를 지정하는 옵션이나 환경변수를 쓰면 됩니다.
- **파이썬 버전**: `python3-*` 패키지는 시스템 `/usr/bin/python3` 버전용입니다. 셸의 `python3`가 다른 인터프리터를 가리키면 C 확장 모듈이 맞지 않을 수 있습니다. 확인한 환경에서는 로그인 셸의 PATH에서 Codex 런타임의 Python 3.12가 시스템 3.13보다 먼저 잡혔습니다. 이럴 때는 `/usr/bin/python3`를 직접 쓰거나 pip로 설치하세요.
- **라이브러리 우선순위**: `LD_LIBRARY_PATH`는 시스템 라이브러리보다 먼저 검색됩니다. 시스템에 있는 라이브러리는 다시 받지 않으므로 보통은 문제가 없지만, 이상하면 최근에 설치한 패키지를 지워 보세요.
- **캐시**: 받은 `.deb`는 `/workspace/.tsnet/apt/cache/archives`에 남습니다. `apt-get clean`으로 지웁니다.

## 파일 위치

| 경로 | 내용 |
|---|---|
| `/workspace/.tsnet/root` | 패키지를 푼 위치 |
| `/workspace/.tsnet/apt/sources.list` | 저장소 목록. 고친 뒤 `apt update` |
| `/workspace/.tsnet/apt/state` | 패키지 목록과 추론한 설치 상태 |
| `/workspace/.tsnet/apt/user-status` | tsapt로 설치한 패키지 기록 |
| `/workspace/.tsnet/apt/info/*.list` | 패키지별 설치 파일 목록 (제거할 때 사용) |
| `/workspace/.tsnet/apt/cache/archives` | 내려받은 `.deb` |
