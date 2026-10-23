# 검증 체크리스트

릴리스 전에 Dots 클라우드 컴퓨터에서 아래 항목을 확인합니다. 마지막 확인은 v0.1.3, 2026-10-24, Debian 13 (trixie) x86_64, dots-tailscale v0.4.0(Tailscale 1.102.4) 환경이고, exit node는 Windows 11(Tailscale 1.102.2)과 OPNsense(FreeBSD 14.3, Tailscale 1.92.2)입니다.

## 오프라인 검사

- [x] `bash -n`으로 셸 스크립트 문법 확인
- [x] `python3 -m py_compile lib/bin/tsapt lib/setup_knobs.py`
- [x] `python3 -m unittest discover -s tests` (Dots에서 38개 통과)
- [x] GitHub Actions `checks` 통과 (2ba16b8)

## 설치

- [x] 서브모듈의 dots-tailscale 파일 체크섬 확인 (`bash install.sh --check-upstream`)
- [x] 서브모듈이 없을 때 릴리스 파일을 browser-proxy로 내려받고 체크섬 확인 (`TSNET_UPSTREAM_SOURCE=download bash install.sh --check-upstream`)
- [x] 공개 저장소를 browser-proxy로 `--recurse-submodules` clone한 뒤 체크섬과 단위 테스트 통과 (0.1.3: `git pull` 뒤 38개 통과)
- [x] 0.1.3을 받은 뒤 `bash install.sh`: 옮겨 둔 설치와 실행 중인 tailscaled를 그대로 쓰고, exit node와 `TS_` 환경변수 유지
- [x] 기존 설치 위에 다시 설치해도 설정과 설치한 패키지가 유지됨 (0.1.0 → 0.1.1 → 0.1.2)
- [x] `/workspace` 설치를 홈 폴더로 옮김: SSH에서 `--detach`로 분리 실행, 같은 기기 신원과 exit node 설정 유지, 패키지 446MB 복사, 실행 아이콘 두 개 경로 수정, 옛 위치 삭제 (2026-10-23 실제 Dots)
- [x] 홈 폴더(0.1.2) 설치를 `/workspace/shared`로 옮김: SSH에서 `--detach`로 분리 실행, 같은 기기 신원과 exit node 설정 유지, SSH 호스트 키 지문 그대로, 패키지 446MB 복사, 실행 아이콘 두 개 경로 수정, 옛 위치 삭제 (2026-10-23 밤 실제 Dots)
- [x] 옮긴 뒤 dots-tailscale 파일 무결성 `match`, 백업이 `~/.local/state/dots-tsnet`(폴더 700, 파일 600)에 생기고 예전 백업 위치(`/workspace/.dots-tsnet-backup`)는 지워짐, `ssh -tt`로 `/dev/pts/6` 할당
- [x] `uninstall.sh --keep-packages` 후 셸 연결, 프록시 변수, exit node가 정리되고 재설치로 복구됨 (0.1.1에서 확인)
- [x] tailscaled 실제 재시작 후 프록시 listener 확인 (`dots-ts proxy apply` 절차, 약 3초)
- [x] `TSNET_TAILSCALED_ENV=... bash install.sh`가 값을 `tsnet.conf`에 저장하고 기동 단계에 넘김
- [ ] dots-tailscale이 없는 새 VM에서 처음부터 `/workspace/shared`에 설치 (로그인 URL 승인 포함)
- [ ] 설치 폴더가 지워진 뒤 `install.sh`가 백업에서 같은 신원으로 되돌림 (단위 테스트로만 확인. 예전 백업 위치에서 되돌리기 포함)

## tsnet

- [x] `tsnet status`가 exit node 경로, dots-tailscale 무결성, tailscaled의 `TS_` 환경변수, 설치 위치와 백업을 보여 줌
- [x] `tsnet status`가 아직 적용되지 않은 `TSNET_TAILSCALED_ENV` 항목을 알려 줌
- [x] `tsnet start`가 실행 중인 tailscaled를 그대로 쓰고 정상 종료
- [x] 잘못된 `TSNET_TAILSCALED_ENV`(`PATH=...`, `TS_X=$(id)`)는 종료 코드 2로 거부
- [x] `tsnet doctor --fix`가 `setup.sh`에 넣은 GSO·GRO 설정을 `tsnet.conf`로 옮기고 원본을 되살림, `dots-ts doctor` healthy
- [x] `tsnet restart`(분리 실행)가 프록시 포트가 풀리길 기다렸다가 새 tailscaled로 트래픽 확인 (두 번, 각각 약 68초)
- [x] 새로 띄운 tailscaled가 `TSNET_TAILSCALED_ENV`를 받음 (재시작과 홈 폴더 이동 모두)
- [x] 대화형 SSH: 보정 전에는 `ssh -tt`가 `closed by remote host`, 보정 후 `/dev/pts/6` 할당
- [ ] 실제 Dots에서 지워진 파일로 도는 옛 tailscaled를 `tsnet start`가 정리 (가짜 데몬으로 단위 테스트만)
- [ ] `tsnet restart` 실패 시 이전 설정으로 되돌리기 (실제 실패 상황은 아직 없음)

## 네트워크

- [x] 프록시를 거친 외부 IP가 exit node 기기의 공인 IP와 같음
- [x] 홈 폴더로 옮긴 뒤 계속 돌던 Dots Chrome이 새 tailscaled의 HTTP 프록시(1056)로 다시 연결됨 (연결 13개, 프록시 경유 Google HTTP 200)
- [x] `/workspace/shared`로 옮긴 뒤에도 계속 돌던 Dots Chrome이 새 tailscaled의 HTTP 프록시로 다시 연결됨 (연결 10개)
- [x] 프록시 없이 직접 연결하면 실패함 (Dots 기본 정책)
- [x] exit node를 Windows 11에서 OPNsense로 바꾸면 외부 IP도 OPNsense 공인 IP로 바뀌고 `apt-get update`, 7MB 다운로드가 정상 동작
- [x] exit node 없이 tailnet 기기 접속: HTTP 프록시와 SOCKS5 모두 HTTP 200, `dots-ts cli nc`로 SSH 포트 연결, 인터넷 요청은 실패
- [x] Dots의 UDP: 목적지 포트 3478만 통과 (DERP 28개 지역 Tailscale 형식 STUN, Google·Cloudflare 3478 응답. 53, 123, 443, 19302 무응답)
- [x] `tailscale ping`은 양쪽 방향 모두 DERP 경유, tailscaled 통계의 직접 경로 바이트 0
- [x] 속도: 새벽 연결 1개 340~720kB/s, 4개 병렬 약 620kB/s, 저녁 90~230kB/s, browser-proxy 약 18MB/s (7MB 파일)
- [x] GSO·GRO 끔/켬/끔 비교: 117~124 / 189 / 117kB/s, 왕복 308 / 192 / 318ms (2026-10-23 저녁)
- [x] `TSNET_APT_PROXY=http://browser-proxy:8889`로 `apt-get update` 5초 (exit node 경유 약 32초), 다음 실행에서 원래 프록시로 복귀
- [ ] `{exit-node}`를 UDP 3478에서 기다리게 했을 때 직접 연결이 생기는지

## 패키지

- [x] `apt-get update` (Debian 목록 약 10MB)
- [x] `apt-get install -y iperf3`: 라이브러리 의존성 2개와 함께 설치, `ldd`로 경로 확인 후 실행
- [x] update-alternatives로 만들어지는 실행 파일 (figlet의 `/usr/bin/figlet`)
- [x] `/usr/games`에 설치되는 실행 파일 (sl)
- [x] `sudo apt install -y pv`, 옵션을 명령 앞에 둔 `apt-get -y -q install sl`
- [x] `apt -s install`은 계획만 보여 주고 설치하지 않음
- [x] `apt list --installed`, `apt-cache policy`
- [x] `apt remove`, 시스템 패키지 제거 요청은 거부 (종료 코드 100)
- [x] `apt upgrade`가 시스템 패키지를 업그레이드 대상으로 세지 않음 (0 not upgraded)
- [x] `apt-get build-dep`는 지원하지 않는다고 안내 (종료 코드 100)
- [x] 패키지 폴더를 다른 위치로 복사해도 링크가 깨지지 않음 (tsapt의 링크는 상대 경로, 홈 폴더 이동 때 Chrome 포함 확인)
- [x] pip가 같은 프록시로 내려받음
- [x] `tests/smoke.sh` 통과 (0.1.3, 공개 저장소 사본에서 실행, pv를 `/workspace/shared/.tsnet/root`에 설치하고 제거, 옮겨 온 `apt.conf`가 새 경로로 다시 만들어짐)

## 문서

- [x] exit node 예시 이름을 `{exit-node}`(집 PC 또는 중계 서버) 자리표시로 통일, 저장소에 개인 기기 이름·IP 없음
- [x] README, how-it-works, exit-node, tsapt 문서의 한국어·영어판이 같은 내용을 다룸
- [x] 문서의 경로가 `/workspace/shared` 설치 기준 (`/workspace/shared/.tsnet`, `/workspace/shared/.dots-tailscale`)
- [x] Dots 저장소 구조, scratch 정리 기록, 환경 복원 사례(openai/codex#52765), Google Drive를 마운트할 수 없는 근거(`/dev/fuse` 없음, capability 0, `NoNewPrivs=1`)가 문서에 있음
- [x] GSO·GRO 문단이 측정값과 근거 링크를 담고, 측정하지 않은 단정이 없음

## 아직 확인하지 않은 것

- [ ] VM 교체 후 `tsnet start`만으로 프록시까지 다시 열리는지 (`/workspace`가 남는 경우)
- [ ] VM 교체나 스냅숏 복원 뒤 `/workspace/shared` 설치가 남는지, 지워졌다면 홈 폴더 백업에서 되돌리기
- [ ] `dots-ts cli set --accept-routes`로 서브넷 경로 사용
- [ ] Ubuntu 기반 이미지
- [ ] arm64
