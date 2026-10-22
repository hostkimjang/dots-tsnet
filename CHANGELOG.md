# 변경 기록

## 0.1.0 - 2026-10-22

처음 공개한 버전입니다.

- dots-tailscale v0.4.0을 서브모듈로 고정하고, 설치돼 있지 않으면 SHA-256 확인 후 설치
- tailscaled 로컬 SOCKS5·HTTP 프록시 설정과 적용 (`tsnet apply`, SSH 세션 분리 실행 지원)
- exit node 지정과 상태 확인 (`tsnet exit-node`, `tsnet status`)
- root 없이 apt 패키지를 설치하는 tsapt와 `apt`, `apt-get`, `apt-cache` 연결, sudo 대체
- update-alternatives 링크 재현과 절대 경로 심볼릭 링크 보정
