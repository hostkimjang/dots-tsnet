# 변경 기록

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
