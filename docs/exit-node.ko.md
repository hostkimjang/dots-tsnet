# exit node 준비

dots-tsnet은 Dots 컴퓨터의 다운로드를 Tailscale exit node로 내보냅니다. 같은 tailnet에 있는 기기 하나를 exit node로 켜고, 관리 콘솔에서 승인하면 됩니다. 항상 켜져 있는 기기(NAS, 라우터, 클라우드 VM)가 가장 좋고, 데스크톱 PC도 켜져 있는 동안에는 잘 동작합니다.

## 1. 기기에서 exit node 켜기

**Windows**는 PowerShell에서 실행합니다. 확인한 환경(Windows 11, Tailscale 1.102.2)에서는 관리자 권한 없이 됐습니다. 작업 표시줄의 Tailscale 메뉴에서 exit node 실행 항목을 켜도 같습니다.

```powershell
tailscale set --advertise-exit-node
```

**macOS**는 메뉴 막대의 Tailscale 메뉴에서 exit node 실행 항목을 켜거나 같은 CLI 명령을 씁니다.

**Linux**는 IP 포워딩을 켠 뒤 광고합니다.

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale set --advertise-exit-node
```

## 2. 관리 콘솔에서 승인

[Machines](https://console.tailscale.com/admin/machines)에서 해당 기기를 열고 **Edit route settings**를 누른 뒤 **Use as exit node**를 체크하고 저장합니다. 기기 상세 화면의 Exit Node 항목이 Awaiting approval에서 Allowed로 바뀌면 됩니다. 접근 정책의 `autoApprovers`로 자동 승인하도록 할 수도 있습니다.

기본 접근 정책은 모든 tailnet 멤버의 인터넷 사용을 허용합니다. 정책을 바꿨다면 Dots 기기(기본 이름 `dots-sandbox`)가 `autogroup:internet`에 접근할 수 있어야 합니다.

## 3. Dots에서 지정

```bash
tsnet exit-node               # 사용할 수 있는 목록
tsnet exit-node my-home-pc    # 지정 (tsnet.conf 에도 저장)
tsnet status                  # 외부로 보이는 IP 가 exit node 기기의 공인 IP 인지 확인
```

## 참고

- 승인된 exit node는 접근 정책이 허용하는 다른 tailnet 기기도 쓸 수 있습니다.
- 그만 쓰려면 Dots에서 `tsnet exit-node off`, exit node 기기에서 `tailscale set --advertise-exit-node=false`를 실행합니다.
