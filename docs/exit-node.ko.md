# exit node 준비하기

[English](exit-node.md) · 한국어 · [README로 돌아가기](../README.md)

dots-tsnet은 Dots 컴퓨터의 다운로드를 내 tailnet의 기기 한 대로 보낸 뒤, 그 기기에서 인터넷으로 내보냅니다. 이 역할을 하는 기기를 Tailscale에서는 **exit node**라고 부르고, 이 문서에서는 `{exit-node}`라고 씁니다. 준비는 세 단계입니다.

1. 기기에서 exit node 기능을 켭니다.
2. Tailscale 관리 콘솔에서 승인합니다.
3. Dots에서 그 기기를 지정합니다.

## 어떤 기기가 좋을까요

| 기기 | 좋은 점 | 아쉬운 점 |
|---|---|---|
| **집 PC** | 이미 Tailscale이 깔려 있다면 바로 시작 가능 | 꺼지거나 절전 상태가 되면 Dots 다운로드도 멈춤 |
| **중계 서버** (NAS, 공유기·방화벽, 작은 클라우드 VM) | 늘 켜져 있어서 안정적 | 처음 설정이 조금 더 필요할 수 있음 |

밖에서 보면 Dots의 다운로드가 `{exit-node}`의 공인 IP에서 온 것으로 보입니다. 회사망처럼 다른 사람과 같이 쓰는 네트워크라면 그 망의 정책을 먼저 확인하세요.

두 대를 준비해 두면 하나가 꺼졌을 때 바로 바꿀 수 있어서 편합니다.

## 1단계: 기기에서 exit node 켜기

**Windows**

PowerShell에서 실행합니다. 확인한 환경(Windows 11, Tailscale 1.102.2)에서는 관리자 권한 없이 됐습니다. 작업 표시줄의 Tailscale 메뉴에서 exit node 실행 항목을 켜도 같습니다.

```powershell
tailscale set --advertise-exit-node
```

**macOS**

메뉴 막대의 Tailscale 메뉴에서 exit node 실행 항목을 켜거나, 같은 CLI 명령을 씁니다.

**Linux**

패킷 전달(IP forwarding)을 켠 다음 광고합니다.

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale set --advertise-exit-node
```

**OPNsense, pfSense 같은 방화벽**

Tailscale 플러그인 설정 화면(OPNsense는 VPN > Tailscale)에서 exit node 광고 옵션을 켭니다. 방화벽은 Tailscale 주소 대역(`100.64.0.0/10`)에서 들어온 트래픽을 WAN으로 내보낼 수 있어야 합니다(outbound NAT와 방화벽 규칙). 확인한 OPNsense(FreeBSD 14.3, Tailscale 1.92.2)에서는 별도 조정 없이 동작했지만, 규칙을 직접 관리하고 있다면 이 부분을 확인하세요.

## 2단계: 관리 콘솔에서 승인하기

기기가 exit node를 광고해도, tailnet 관리자가 승인하기 전에는 쓸 수 없습니다.

1. [관리 콘솔의 Machines](https://console.tailscale.com/admin/machines)에서 `{exit-node}`를 엽니다. 목록에 **Exit Node** 배지가 있고 옆에 ⓘ 표시가 있으면 승인을 기다리는 상태입니다.
2. **Routing Settings**의 Exit Node 항목 옆 **Edit**을 누릅니다.
3. **Use as exit node**를 체크하고 **Save**를 누릅니다.
4. Exit Node 항목이 **Awaiting approval**에서 **Allowed**로 바뀌면 끝입니다.

자주 추가하는 기기라면 접근 정책의 `autoApprovers`로 자동 승인하게 할 수도 있습니다.

접근 정책을 직접 바꿔 썼다면 Dots 기기(기본 이름 `dots-sandbox`)가 `autogroup:internet`을 쓸 수 있어야 합니다. Tailscale 기본 정책은 모든 멤버에게 허용합니다.

## 3단계: Dots에서 지정하기

dots-tsnet을 아직 설치하지 않았다면 `bash install.sh --exit-node {exit-node}`가 이 단계를 대신합니다. 이미 설치했다면 Dots 터미널에서 이렇게 합니다.

```bash
tsnet exit-node                  # 쓸 수 있는 exit node 목록. 방금 승인한 기기가 보여야 합니다
tsnet exit-node {exit-node}      # 지정 (tsnet.conf 에도 저장)
tsnet status                     # [외부로 보이는 IP] 가 {exit-node} 의 공인 IP 인지 확인
```

`{exit-node}`의 공인 IP는 그 기기에서 `curl https://ifconfig.me`로 확인할 수 있습니다.

## 바꾸기와 그만 쓰기

- **다른 기기로 바꾸기**: `tsnet exit-node {다른-기기}`
- **잠시 끄기**: 지금 셸에서만 `tsnet_off`. Dots 전체에서 끄려면 `tsnet exit-node off`
- **광고 그만하기**: `{exit-node}` 기기에서 `tailscale set --advertise-exit-node=false`

## 참고

- 승인된 exit node는 접근 정책이 허용하는 다른 tailnet 기기도 쓸 수 있습니다.
- Dots와 `{exit-node}` 사이는 항상 DERP 중계 서버를 거칩니다. 기기의 방화벽 포트를 열어도 속도는 그대로입니다. 이유는 [동작 원리](how-it-works.ko.md#항상-derp를-거치는-이유와-속도)에 있습니다.
