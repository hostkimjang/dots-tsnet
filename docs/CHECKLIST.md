# 검증 체크리스트

릴리스 전에 Dots 클라우드 컴퓨터에서 아래 항목을 확인합니다. 마지막 확인은 v0.1.1, 2026-10-23, Debian 13 (trixie) x86_64, dots-tailscale v0.4.0(Tailscale 1.102.4) 환경이고, exit node는 Windows 11(Tailscale 1.102.2)과 OPNsense(FreeBSD 14.3, Tailscale 1.92.2)입니다.

## 오프라인 검사

- [x] `bash -n`으로 셸 스크립트 문법 확인
- [x] `python3 -m py_compile lib/bin/tsapt`
- [x] `python3 -m unittest discover -s tests` (14개 통과)
- [x] GitHub Actions `checks` 통과

## 설치

- [x] 서브모듈의 dots-tailscale 파일 체크섬 확인 (`bash install.sh --check-upstream`)
- [x] 서브모듈이 없을 때 릴리스 파일을 browser-proxy로 내려받고 체크섬 확인 (`TSNET_UPSTREAM_SOURCE=download bash install.sh --check-upstream`)
- [x] 공개 저장소를 browser-proxy로 `--recurse-submodules` clone한 뒤 체크섬과 단위 테스트 통과
- [x] 기존 설치 위에 다시 설치해도 설정과 설치한 패키지가 유지됨 (0.1.0 → 0.1.1 포함)
- [x] `uninstall.sh --keep-packages` 후 셸 연결, 프록시 변수, exit node가 정리되고 재설치로 복구됨
- [x] SSH 세션에서 `tsnet apply --detach --force` 분리 실행 경로 (설정이 같아 재시작 없이 로그까지 기록)
- [x] tailscaled 실제 재시작 후 프록시 listener 확인 (`dots-ts proxy apply` 절차, 약 3초)
- [x] `TSNET_TAILSCALED_ENV=... bash install.sh`가 값을 `tsnet.conf`에 저장하고 기동 단계에 넘김
- [ ] dots-tailscale이 없는 새 VM에서 처음부터 설치 (로그인 URL 승인 포함)

## tsnet

- [x] `tsnet status`가 exit node 경로(DERP 릴레이 지역)와 tailscaled의 `TS_` 환경변수를 보여 줌
- [x] `tsnet status`가 아직 적용되지 않은 `TSNET_TAILSCALED_ENV` 항목을 알려 줌
- [x] `tsnet start`가 실행 중인 tailscaled를 그대로 쓰고 정상 종료
- [x] `tsnet start`가 `TS_` 값만 넘기고 셸의 `http(s)_proxy`, `no_proxy`는 빼서 `start.sh`를 실행 (가짜 `start.sh`로 확인, 인자 `login` 전달 포함)
- [x] 잘못된 `TSNET_TAILSCALED_ENV`(`PATH=...`, `TS_X=$(id)`)는 종료 코드 2로 거부
- [ ] 새로 띄운 tailscaled가 `TSNET_TAILSCALED_ENV`를 받는지 (VM 교체나 데몬 재기동 때 확인)

## 네트워크

- [x] 프록시를 거친 외부 IP가 exit node 기기의 공인 IP와 같음
- [x] 프록시 없이 직접 연결하면 실패함 (Dots 기본 정책)
- [x] exit node를 Windows 11에서 OPNsense로 바꾸면 외부 IP도 OPNsense 공인 IP로 바뀌고 `apt-get update`, 7MB 다운로드가 정상 동작
- [x] exit node 없이 tailnet 기기 접속: HTTP 프록시와 SOCKS5 모두 HTTP 200, `dots-ts cli nc`로 SSH 포트 연결, 인터넷 요청은 실패
- [x] Dots에서 UDP STUN: DERP 28개 지역과 Google은 응답 없음, Cloudflare만 응답. `tailscale ping`은 양쪽 방향 모두 DERP 경유
- [x] 속도: exit node 경유 연결 1개 270~390kB/s, 4개 병렬 약 620kB/s, browser-proxy 약 18MB/s (7MB 파일)
- [x] `TSNET_APT_PROXY=http://browser-proxy:8889`로 `apt-get update` 5초 (exit node 경유 약 32초), 다음 실행에서 원래 프록시로 복귀

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
- [x] pip가 같은 프록시로 내려받음
- [x] `tests/smoke.sh` 통과

## 문서

- [x] exit node 예시 이름을 `{exit-node}`(집 PC 또는 중계 서버) 자리표시로 통일, 저장소에 개인 기기 이름·IP 없음
- [x] README, how-it-works, exit-node, tsapt 문서의 한국어·영어판이 같은 내용을 다룸
- [x] 문서의 tailscaled 실행 명령과 `/proc` 확인 명령이 실제 Dots 출력과 일치

## 아직 확인하지 않은 것

- [ ] VM 교체 후 `tsnet start`만으로 프록시까지 다시 열리는지
- [ ] `dots-ts cli set --accept-routes`로 서브넷 경로 사용
- [ ] Ubuntu 기반 이미지
- [ ] arm64
