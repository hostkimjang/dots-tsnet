"""lib/common.sh 의 설정 읽기와 tailscaled 환경변수 검사를 확인하는 오프라인 테스트입니다."""
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DOLLAR_BRACE = "$" + "{"


def bash(script, *args, env=None):
    prelude = 'set -euo pipefail; . "%s/lib/common.sh"; ' % REPO
    full_env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    full_env.update(env or {})
    return subprocess.run(["bash", "-c", prelude + script.replace("@{", DOLLAR_BRACE), "bash"] + list(args),
                          capture_output=True, text=True, env=full_env)


class TailscaledEnvTest(unittest.TestCase):
    def test_accepts_tailscale_knobs(self):
        result = bash('tsnet_tailscaled_env "$1"; printf "%s\\n" "@{TSNET_TS_ENV_ARGS[@]}"',
                      "TS_DEBUG_DISABLE_UDP_GSO=true  TS_DEBUG_DISABLE_UDP_GRO=true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["TS_DEBUG_DISABLE_UDP_GSO=true", "TS_DEBUG_DISABLE_UDP_GRO=true"])

    def test_empty_value_means_no_extra_environment(self):
        result = bash('tsnet_tailscaled_env ""; echo "@{#TSNET_TS_ENV_ARGS[@]}"')
        self.assertEqual(result.stdout.strip(), "0")

    def test_rejects_other_variables_and_shell_syntax(self):
        for value in ("PATH=/tmp", "LD_PRELOAD=/tmp/x.so", "TS_X=$(id)", "TS_X=*", "ts_lower=1", "TS_X=a;b"):
            with self.subTest(value=value):
                result = bash('tsnet_tailscaled_env "$1"', value)
                self.assertEqual(result.returncode, 2)


class ConfigFileTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.conf = Path(self.tmp.name) / "tsnet.conf"
        self.conf.write_text("# 주석\nTSNET_EXIT_NODE=from-file\nTSNET_HTTP_PORT=2000\n"
                             "TSNET_TAILSCALED_ENV=TS_DEBUG_DISABLE_UDP_GSO=true TS_DEBUG_DISABLE_UDP_GRO=true\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_environment_wins_over_file(self):
        result = bash('tsnet_load_conf "$1"; tsnet_defaults; echo "$TSNET_EXIT_NODE $TSNET_HTTP_PORT $TSNET_HTTP_PROXY"',
                      str(self.conf), env={"TSNET_EXIT_NODE": "from-env"})
        self.assertEqual(result.stdout.strip(), "from-env 2000 http://127.0.0.1:2000")

    def test_conf_get_reads_one_key_with_spaces(self):
        result = bash('tsnet_conf_get "$1" TSNET_TAILSCALED_ENV', str(self.conf))
        self.assertEqual(result.stdout.strip(), "TS_DEBUG_DISABLE_UDP_GSO=true TS_DEBUG_DISABLE_UDP_GRO=true")

    def test_set_conf_replaces_and_appends(self):
        result = bash('tsnet_set_conf "$1" TSNET_EXIT_NODE relay; tsnet_set_conf "$1" TSNET_NEW_KEY 1', str(self.conf))
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.conf.read_text()
        self.assertIn("TSNET_EXIT_NODE=relay\n", text)
        self.assertNotIn("from-file", text)
        self.assertTrue(text.endswith("TSNET_NEW_KEY=1\n"))


@unittest.skipUnless(Path("/proc/self/exe").exists(), "Linux /proc 가 필요합니다")
class StaleProcessTest(unittest.TestCase):
    """설치 폴더가 지워진 뒤에도 남은 tailscaled 를 찾아 멈추는지 확인합니다. 가짜 데몬은 bash 사본입니다."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.daemon = self.dir / "tailscaled"
        shutil.copy(shutil.which("bash"), self.daemon)
        self.sock_path = self.dir / "tailscaled.sock"
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.sock_path))
        # "; :" 를 붙여 bash 가 sleep 으로 exec 되지 않고 데몬 자리에 남게 합니다.
        self.proc = subprocess.Popen([str(self.daemon), "-c", "sleep 30; :", "--socket=" + str(self.sock_path)],
                                     start_new_session=True)
        self.env = {"DOTS_TS_DIR": str(self.dir)}

    def tearDown(self):
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.proc.wait()
        self.listener.close()
        self.tmp.cleanup()

    def stale(self):
        return bash("tsnet_stale_processes", env=self.env).stdout.split()

    def test_running_daemon_with_its_executable_is_not_stale(self):
        self.assertEqual(self.stale(), [])
        listed = bash('tsnet_install_processes "$DOTS_TS_DIR"', env=self.env).stdout.split()
        self.assertEqual(listed, [str(self.proc.pid), "tailscaled", str(self.sock_path)])

    def test_finds_and_stops_daemon_whose_executable_was_deleted(self):
        self.daemon.unlink()
        self.assertEqual(self.stale(), [str(self.proc.pid), "tailscaled", str(self.sock_path)])
        result = bash("tsnet_stop_stale", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PID %d tailscaled" % self.proc.pid, result.stdout)
        self.proc.wait(timeout=5)
        self.assertFalse(self.sock_path.exists())
        self.assertEqual(self.stale(), [])

    def test_ssh_session_is_not_cut(self):
        self.daemon.unlink()
        result = bash("tsnet_stop_stale", env=dict(self.env, SSH_CONNECTION="100.64.0.1 50000 127.0.0.1 22"))
        self.assertEqual(result.returncode, 3)
        self.assertIsNone(self.proc.poll())
        self.assertTrue(self.sock_path.exists())


class InstallStateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.env = {"DOTS_TS_DIR": str(self.dir)}

    def tearDown(self):
        self.tmp.cleanup()

    def test_identity_lost_only_when_authenticated_marker_has_no_state(self):
        check = 'if tsnet_identity_lost; then echo lost; else echo ok; fi'
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "ok")
        (self.dir / "authenticated").write_text("")
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "lost")
        (self.dir / "state").mkdir()
        (self.dir / "state" / "tailscaled.state").write_text("{}")
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "ok")

    def test_install_with_a_missing_binary_is_incomplete(self):
        names = ["installed", "tailscale", "tailscaled", "dots-ts", "dots_proxy.py", "setup.sh", "start.sh",
                 "shim/shim.py", "shim/ca.crt", "shim/ca.key", "shim/bundle.crt", "sshd/sshd_config",
                 "sshd/ssh_host_ed25519_key", "sshd/authorized_keys"]
        for name in names:
            (self.dir / name).parent.mkdir(exist_ok=True)
            (self.dir / name).write_text("x")
        check = 'if tsnet_dots_ts_complete; then echo complete; else echo incomplete; fi'
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "complete")
        (self.dir / "tailscaled").unlink()
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "incomplete")

    def test_backup_goes_to_the_other_location(self):
        home, shared = self.dir / "home", self.dir / "shared"
        env = {"HOME": str(home), "TSNET_SHARED_BASE": str(shared), "DOTS_TS_DIR": str(home / ".dots-tailscale")}
        self.assertEqual(bash("tsnet_backup_dir", env=env).stdout.strip(), str(shared / ".dots-tsnet-backup"))
        env["DOTS_TS_DIR"] = str(shared / ".dots-tailscale")
        self.assertEqual(bash("tsnet_backup_dir", env=env).stdout.strip(), str(home / ".local/state/dots-tsnet"))
        env["TSNET_BACKUP_DIR"] = "/elsewhere"
        self.assertEqual(bash("tsnet_backup_dir", env=env).stdout.strip(), "/elsewhere")

    def test_default_install_location_prefers_workspace_shared(self):
        shared = self.dir / "shared"
        env = {"HOME": "/home/agent", "TSNET_SHARED_BASE": str(shared)}
        check = 'tsnet_defaults; echo "$TSNET_DIR $DOTS_TS_DIR"'
        # /workspace/shared 가 없는 환경에서는 홈 폴더에 설치합니다.
        self.assertEqual(bash(check, env=env).stdout.split(), ["/home/agent/.tsnet", "/home/agent/.dots-tailscale"])
        shared.mkdir()
        self.assertEqual(bash(check, env=env).stdout.split(), [str(shared / ".tsnet"), str(shared / ".dots-tailscale")])

    def test_env_sh_finds_its_own_install_location(self):
        tsnet = self.dir / "somewhere" / ".tsnet"
        (tsnet / "lib").mkdir(parents=True)
        shutil.copy(REPO / "lib" / "env.sh", tsnet / "env.sh")
        shutil.copy(REPO / "lib" / "common.sh", tsnet / "lib" / "common.sh")
        (tsnet / "tsnet.conf").write_text("DOTS_TS_DIR=%s\nTSNET_AUTO_PROXY=0\n" % (self.dir / "nothing"))
        result = subprocess.run(["bash", "-c", '. "$1"; echo "$TSNET_DIR"; echo "$PATH"', "bash", str(tsnet / "env.sh")],
                                capture_output=True, text=True, env={"PATH": "/usr/bin:/bin", "HOME": str(self.dir)})
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], str(tsnet), result.stderr)
        self.assertIn(str(tsnet / "bin"), lines[1].split(":"))


@unittest.skipUnless(Path("/proc/self/exe").exists(), "Linux 가 필요합니다")
class WaitPortsTest(unittest.TestCase):
    def test_waits_only_while_the_port_is_taken(self):
        with socket.socket() as held:
            held.bind(("127.0.0.1", 0))
            held.listen()
            port = str(held.getsockname()[1])
            self.assertEqual(bash('tsnet_wait_ports 0 "$1"', port).returncode, 1)
        self.assertEqual(bash('tsnet_wait_ports 0 "$1"', port).returncode, 0)


@unittest.skipUnless(shutil.which("cc") and Path("/proc/self/exe").exists(), "Linux 와 C 컴파일러가 필요합니다")
class PtyShimTest(unittest.TestCase):
    def test_only_dev_pts_chown_is_reported_as_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = bash('tsnet_build_pty_shim "$1"; tsnet_preload_args; printf "%s\\n" "@{TSNET_PRELOAD_ARGS[@]}"',
                          str(REPO / "lib" / "pty_chown_shim.c"), env={"TSNET_DIR": tmp})
            shim = Path(tmp) / "lib" / "pty_chown_shim.so"
            self.assertTrue(shim.exists(), result.stdout + result.stderr)
            self.assertEqual(result.stdout.strip(), "LD_PRELOAD=%s" % shim)
            code = ("import os, sys\n"
                    "os.chown('/dev/pts/999999', os.getuid(), 5)\n"
                    "try:\n    os.chown(sys.argv[1], 0, 0)\nexcept OSError:\n    print('other paths still checked')\n")
            run = subprocess.run([sys.executable, "-c", code, tmp], capture_output=True, text=True,
                                 env={"LD_PRELOAD": str(shim)})
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn("other paths still checked", run.stdout)


@unittest.skipUnless(Path("/proc/self/exe").exists(), "Linux 파일 권한이 필요합니다")
class IdentityBackupTest(unittest.TestCase):
    """Dots 정리 작업이 설치 폴더를 지운 상황을 흉내 내서 다른 쪽에 둔 백업과 복원을 확인합니다."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.ts, self.tsnet, self.backup = root / "dots-tailscale", root / "tsnet", root / "backup"
        for sub in ("state", "sshd"):
            (self.ts / sub).mkdir(parents=True)
        (self.tsnet / "apt").mkdir(parents=True)
        self.state = self.ts / "state" / "tailscaled.state"
        self.state.write_text('{"node":"old"}')
        (self.ts / "sshd" / "ssh_host_ed25519_key").write_text("private")
        (self.ts / "sshd" / "ssh_host_ed25519_key.pub").write_text("public")
        (self.ts / "sshd" / "authorized_keys").write_text("ssh-ed25519 AAAA test")
        (self.tsnet / "tsnet.conf").write_text("TSNET_EXIT_NODE=relay\n")
        (self.tsnet / "apt" / "user-status").write_text("Package: pv\nVersion: 1\n\nPackage: sl\nVersion: 2\n")
        self.env = {"DOTS_TS_DIR": str(self.ts), "TSNET_DIR": str(self.tsnet), "TSNET_BACKUP_DIR": str(self.backup),
                    "HOME": str(root)}

    def tearDown(self):
        self.tmp.cleanup()

    def test_backup_then_restore_after_workspace_wipe(self):
        result = bash("tsnet_backup_identity", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.backup / "tailscaled.state").read_text(), '{"node":"old"}')
        self.assertEqual(self.backup.stat().st_mode & 0o777, 0o700)
        for name in ("tailscaled.state", "ssh_host_ed25519_key", "tsnet.conf", "packages.txt"):
            self.assertEqual((self.backup / name).stat().st_mode & 0o777, 0o600, name)
        self.assertEqual((self.backup / "packages.txt").read_text().split(), ["pv", "sl"])
        shutil.rmtree(self.ts)
        shutil.rmtree(self.tsnet)
        result = bash("tsnet_restore_identity", env=self.env)
        self.assertIn("Tailscale 상태, SSH 호스트 키, authorized_keys", result.stdout)
        self.assertEqual(self.state.read_text(), '{"node":"old"}')
        self.assertEqual((self.ts / "sshd" / "ssh_host_ed25519_key").read_text(), "private")
        self.assertEqual((self.ts / "sshd" / "authorized_keys").read_text(), "ssh-ed25519 AAAA test")
        check = 'if tsnet_identity_lost; then echo lost; else echo ok; fi'
        self.assertEqual(bash(check, env=self.env).stdout.strip(), "ok")

    def test_restore_never_overwrites_existing_files(self):
        bash("tsnet_backup_identity", env=self.env)
        self.state.write_text('{"node":"new"}')
        result = bash("tsnet_restore_identity", env=self.env)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.state.read_text(), '{"node":"new"}')

    def test_restore_falls_back_to_an_older_backup_location(self):
        # 지금 위치에 백업이 없으면 예전 버전이 쓰던 백업 위치에서 되돌립니다.
        root = Path(self.tmp.name)
        home = root / "home"
        env = {"HOME": str(home), "TSNET_SHARED_BASE": str(root / "shared"),
               "DOTS_TS_DIR": str(home / ".dots-tailscale"), "TSNET_DIR": str(self.tsnet)}
        older = home / ".local" / "state" / "dots-tsnet"
        older.mkdir(parents=True, mode=0o700)
        (older / "tailscaled.state").write_text('{"node":"older"}')
        result = bash("tsnet_restore_identity", env=env)
        self.assertIn("Tailscale 상태", result.stdout, result.stderr)
        self.assertIn(str(older), result.stdout)
        self.assertEqual((home / ".dots-tailscale" / "state" / "tailscaled.state").read_text(), '{"node":"older"}')

    def test_backup_follows_newer_state_unless_turned_off(self):
        bash("tsnet_backup_identity", env=self.env)
        self.state.write_text('{"node":"renewed"}')
        later = time.time() + 5
        os.utime(self.state, (later, later))
        bash("tsnet_backup_identity", env=dict(self.env, TSNET_IDENTITY_BACKUP="0"))
        self.assertEqual((self.backup / "tailscaled.state").read_text(), '{"node":"old"}')
        bash("tsnet_backup_identity", env=self.env)
        self.assertEqual((self.backup / "tailscaled.state").read_text(), '{"node":"renewed"}')


if __name__ == "__main__":
    unittest.main()
