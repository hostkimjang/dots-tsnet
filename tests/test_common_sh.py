"""lib/common.sh 의 설정 읽기와 tailscaled 환경변수 검사를 확인하는 오프라인 테스트입니다."""
import os
import subprocess
import tempfile
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


if __name__ == "__main__":
    unittest.main()
