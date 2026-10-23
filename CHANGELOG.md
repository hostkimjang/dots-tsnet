# 변경 기록

## 0.1.2 - 2026-10-23

Dots 정리 작업이 설치 폴더를 지운 일을 겪고, 설치 위치를 홈 폴더로 옮기고 복구 경로를 더했습니다. GSO·GRO와 UDP에 관한 틀린 서술도 측정값으로 고쳤습니다.

- 설치 위치: dots-tailscale은 `~/.dots-tailscale`, dots-tsnet은 `~/.tsnet`(패키지 포함)에 설치합니다. 2026-10-23 06:49에 Dots 정리 작업이 `/workspace` 최상위 폴더를 지웠을 때 홈 폴더는 남았기 때문입니다. `TSNET_DIR`, `DOTS_TS_DIR`로 바꿀 수 있습니다.
- `install.sh`: `/workspace`에 있던 예전 설치를 홈 폴더로 옮깁니다. 같은 Tailscale 신원, SSH 키, 설정, 패키지를 가져가고, 새 위치에서 띄우지 못하면 되돌리며, 바탕화면 실행 아이콘의 경로도 고칩니다. SSH에서는 `--detach`로 분리해서 진행합니다.
- 백업: 기기 신원, SSH 호스트 키, `authorized_keys`, `tsnet.conf`, 패키지 목록을 설치 반대편(`/workspace/.dots-tsnet-backup`)에 복사하고, 다시 설치할 때 비어 있는 자리만 되돌립니다. `TSNET_IDENTITY_BACKUP=0`으로 끕니다.
- 지워진 파일로 도는 옛 tailscaled, shim, sshd를 `tsnet start`와 `install.sh`가 찾아 멈추고 새로 띄웁니다. SSH 세션 안에서는 연결이 끊기지 않게 안내만 합니다.
- 빠진 dots-tailscale 파일은 같은 버전으로 다시 채웁니다. 기기 신원이 사라졌고 백업도 없으면 멈추고, `--new-identity`를 줄 때만 새 기기로 로그인합니다.
- 대화형 SSH(PTY) 보정: Dots의 `/dev/pts` 권한 때문에 sshd가 접속을 끊는 문제를 작은 `LD_PRELOAD` 라이브러리(`/dev/pts` 아래 `chown`만 성공으로 처리)로 피합니다. `TSNET_SSH_PTY_FIX=0`으로 끕니다.
- `tsnet doctor [--fix]`: dots-tailscale 점검에 더해, `setup.sh`에 직접 넣은 `TS_` 설정을 `tsnet.conf`로 옮기고 원본을 되살립니다.
- `tsnet restart [--detach]`: `TSNET_TAILSCALED_ENV`를 바로 적용합니다. 프록시 포트가 풀릴 때까지 최대 90초 기다리고, 세 번까지 다시 시도하고, 실제 트래픽을 확인하며, 실패하면 이전 설정으로 되돌립니다.
- `install.sh`: 기동 직후 기기 목록이 늦게 와서 exit node 지정이 실패하면 몇 번 다시 시도합니다.
- 문서: "Dots에서는 GSO·GRO가 속도에 영향이 없다"는 측정 없이 쓴 단정을 지우고, 끔·켬을 번갈아 잰 결과와 끄면 빨라지는 Tailscale 이슈 사례를 넣었습니다.
- 문서: "Dots의 UDP는 목적지에 따라 막힌다", "DERP 28개 지역 STUN에 응답 없음"을 고쳤습니다. 다시 재 보니 목적지 포트 3478로만 나갑니다.
- 문서: 설치 위치와 백업, 정리 작업 관찰 기록, 복구 방법, 대화형 SSH 보정, 저녁 시간대 속도를 더했습니다.
- 테스트: 37개. 옛 프로세스 찾기와 정리, 백업과 복원, 백업 위치, 포트 대기, `env.sh`의 설치 위치 찾기, PTY 보정을 더했습니다. `tests/smoke.sh`는 홈 폴더 설치를 먼저 찾고, 없으면 예전 위치(`/workspace/.tsnet`)를 씁니다.

## 0.1.1 - 2026-10-23

문서를 다시 쓰고, tailscaled 환경변수를 원본 파일 수정 없이 유지하는 방법을 더했습니다.

- 문서: README와 docs를 한국어·영어로 모두 다시 썼습니다. exit node 예시 이름을 `{exit-node}`(집 PC 또는 중계 서버) 같은 자리표시로 바꿨습니다.
- 문서: [동작 원리](docs/how-it-works.ko.md)를 새로 썼습니다. tailscaled 실행 명령, Python shim이 하는 일, Dots 네트워크 제약 측정 결과, exit node 없이 tailnet에 접속하는 방법, Tailscale UDP GSO·GRO 설정을 다룹니다.
- 문서: 영어판 [exit node 준비하기](docs/exit-node.md)와 [tsapt 설명](docs/tsapt.md)을 추가했습니다.
- `tsnet start`: dots-tailscale의 `start.sh`를 실행하면서 `tsnet.conf`의 `TSNET_TAILSCALED_ENV`(`TS_이름=값` 목록)를 tailscaled에 넘깁니다. `install.sh`도 같은 값을 씁니다.
- `tsnet status`: exit node까지의 연결 경로(직접 연결 또는 DERP 릴레이)와, 실행 중인 tailscaled에 적용된 `TS_` 환경변수를 보여 줍니다.
- dots-tailscale을 띄울 때 셸의 `http(s)_proxy` 변수를 빼서, tsnet 프록시 설정이 tailscaled 기동에 섞이지 않게 했습니다.
- 테스트: `lib/common.sh`의 설정 읽기와 환경변수 검사 테스트를 추가했습니다.

## 0.1.0 - 2026-10-22

처음 공개한 버전입니다.

- dots-tailscale v0.4.0을 서브모듈로 고정하고, 설치돼 있지 않으면 SHA-256 확인 후 설치
- tailscaled 로컬 SOCKS5·HTTP 프록시 설정과 적용 (`tsnet apply`, SSH 세션 분리 실행 지원)
- exit node 지정과 상태 확인 (`tsnet exit-node`, `tsnet status`)
- root 없이 apt 패키지를 설치하는 tsapt와 `apt`, `apt-get`, `apt-cache` 연결, sudo 대체
- update-alternatives 링크 재현과 절대 경로 심볼릭 링크 보정
