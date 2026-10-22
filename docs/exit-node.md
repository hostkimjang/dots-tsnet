# Preparing an exit node

English · [한국어](exit-node.ko.md) · [Back to README](../README.en.md)

dots-tsnet sends downloads from the Dots computer to one device in your tailnet, and that device sends them on to the internet. Tailscale calls such a device an **exit node**; these docs write it as `{exit-node}`. Getting one ready takes three steps:

1. Turn on the exit node feature on the device.
2. Approve it in the Tailscale admin console.
3. Select it on Dots.

## Which device to use

| Device | Good | Not so good |
|---|---|---|
| **Home PC** | Starts right away if Tailscale is already installed | Downloads on Dots stop when it shuts down or sleeps |
| **Relay server** (NAS, router or firewall, small cloud VM) | Always on, so it is dependable | May need a bit more setup at first |

To the outside world, Dots's downloads will appear to come from `{exit-node}`'s public IP. If that device sits on a shared network, such as an office network, check its rules first.

Preparing two devices is handy: when one is down, you can switch to the other in a second.

## Step 1: Turn on the exit node feature

**Windows**

Run this in PowerShell. In our test (Windows 11, Tailscale 1.102.2) it worked without administrator rights. Turning on the exit node option in the Tailscale menu in the taskbar does the same thing.

```powershell
tailscale set --advertise-exit-node
```

**macOS**

Turn on the exit node option in the Tailscale menu in the menu bar, or use the same CLI command.

**Linux**

Enable packet forwarding first, then advertise:

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale set --advertise-exit-node
```

**Firewalls such as OPNsense or pfSense**

Turn on the exit node option in the Tailscale plugin settings (on OPNsense: VPN > Tailscale). The firewall must be able to send traffic from Tailscale addresses (`100.64.0.0/10`) out of the WAN, which means outbound NAT and firewall rules that allow it. On the OPNsense we tested (FreeBSD 14.3, Tailscale 1.92.2) it worked without extra changes, but check this if you manage those rules by hand.

## Step 2: Approve it in the admin console

Advertising alone is not enough; a tailnet admin has to approve the exit node.

1. Open `{exit-node}` on the [Machines page](https://console.tailscale.com/admin/machines). An **Exit Node** badge with an ⓘ icon means it is waiting for approval.
2. Under **Routing Settings**, click **Edit** next to Exit Node.
3. Check **Use as exit node** and click **Save**.
4. You are done when the Exit Node entry changes from **Awaiting approval** to **Allowed**.

If you add exit nodes often, `autoApprovers` in your access policy can approve them automatically.

If you have customized your access policy, the Dots machine (default name `dots-sandbox`) must be allowed to use `autogroup:internet`. Tailscale's default policy allows it for everyone.

## Step 3: Select it on Dots

If you have not installed dots-tsnet yet, `bash install.sh --exit-node {exit-node}` does this step for you. Otherwise, in the Dots terminal:

```bash
tsnet exit-node                  # list available exit nodes; the one you just approved should be there
tsnet exit-node {exit-node}      # select it (also saved in tsnet.conf)
tsnet status                     # check that the public IP matches {exit-node}'s public IP
```

You can find `{exit-node}`'s public IP by running `curl https://ifconfig.me` on that device.

## Switching and stopping

- **Switch to another device**: `tsnet exit-node {another-device}`
- **Pause**: `tsnet_off` for the current shell only, or `tsnet exit-node off` for the whole Dots computer
- **Stop advertising**: run `tailscale set --advertise-exit-node=false` on `{exit-node}`

## Notes

- An approved exit node can be used by any tailnet device that your access policy allows.
- Traffic between Dots and `{exit-node}` always goes through a DERP relay. Opening firewall ports on the device does not make it faster. See [How it works](how-it-works.md#why-traffic-is-always-relayed-and-how-fast-it-is) for why.
