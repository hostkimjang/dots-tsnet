"""lib/setup_knobs.py 가 setup.sh 에 직접 넣은 TS_ 설정만 골라내는지 확인하는 오프라인 테스트입니다."""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("setup_knobs", REPO / "lib" / "setup_knobs.py")
setup_knobs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup_knobs)
UPSTREAM = REPO / "upstream" / "dots-tailscale" / "tailscale-setup.sh"

PRISTINE = """#!/usr/bin/env bash
set -euo pipefail
# 원본 주석
start_all() {
    nohup "$D/tailscaled" --tun=userspace-networking --port=0 >> "$R/tailscaled.log" 2>&1 9>&- &
}

echo done
"""
LAUNCH = '    nohup "$D/tailscaled" --tun=userspace-networking --port=0 >> "$R/tailscaled.log" 2>&1 9>&- &'
GSO_GRO = ["TS_DEBUG_DISABLE_UDP_GSO=true", "TS_DEBUG_DISABLE_UDP_GRO=true"]


def with_prefix(text, line, prefix):
    indent = line[: len(line) - len(line.lstrip())]
    return text.replace(line, indent + prefix + line.strip())


class ExtractTest(unittest.TestCase):
    def test_identical_file_has_no_knobs(self):
        self.assertEqual(setup_knobs.extract(PRISTINE, PRISTINE), [])

    def test_prefix_on_launch_line(self):
        edited = with_prefix(PRISTINE, LAUNCH, " ".join(GSO_GRO) + " ")
        self.assertEqual(setup_knobs.extract(PRISTINE, edited), GSO_GRO)

    def test_export_lines_comments_and_quotes(self):
        edited = PRISTINE.replace("set -euo pipefail\n", "set -euo pipefail\n# GSO 끄기\n"
                                  "export TS_DEBUG_DISABLE_UDP_GSO=\"true\"\n\nTS_DEBUG_DISABLE_UDP_GRO=true\n")
        self.assertEqual(setup_knobs.extract(PRISTINE, edited), GSO_GRO)

    def test_removed_comment_and_crlf_are_harmless(self):
        edited = PRISTINE.replace("# 원본 주석\n", "").replace("\n", "\r\n")
        self.assertEqual(setup_knobs.extract(PRISTINE, edited), [])

    def test_last_value_wins(self):
        edited = PRISTINE.replace("set -euo pipefail\n", "set -euo pipefail\nexport TS_X=1\n")
        edited = with_prefix(edited, LAUNCH, "TS_X=2 ")
        self.assertEqual(setup_knobs.extract(PRISTINE, edited), ["TS_X=2"])

    def test_other_changes_are_rejected(self):
        cases = {
            "changed flag": PRISTINE.replace("--port=0", "--port=41641"),
            "added command": PRISTINE.replace("echo done", "echo done\nrm -rf /tmp/x"),
            "removed command": PRISTINE.replace("echo done\n", ""),
            "other variable": with_prefix(PRISTINE, LAUNCH, "LD_PRELOAD=/tmp/x.so "),
            "shell expansion": with_prefix(PRISTINE, LAUNCH, "TS_X=$(id) "),
        }
        for name, edited in cases.items():
            with self.subTest(name):
                with self.assertRaises(setup_knobs.OtherChange):
                    setup_knobs.extract(PRISTINE, edited)

    @unittest.skipUnless(UPSTREAM.is_file(), "dots-tailscale 서브모듈이 없습니다")
    def test_real_upstream_setup_with_gso_gro_edit(self):
        original = UPSTREAM.read_text(encoding="utf-8")
        line = next(l for l in original.splitlines() if 'nohup "$D/tailscaled"' in l)
        edited = with_prefix(original, line, " ".join(GSO_GRO) + " ")
        self.assertNotEqual(original, edited)
        self.assertEqual(setup_knobs.extract(original, edited), GSO_GRO)


class MergeTest(unittest.TestCase):
    def test_merge_replaces_and_appends(self):
        self.assertEqual(setup_knobs.merge("TS_A=1 TS_B=2", ["TS_B=3", "TS_C=4"]), "TS_A=1 TS_B=3 TS_C=4")

    def test_merge_rejects_other_variables(self):
        with self.assertRaises(ValueError):
            setup_knobs.merge("PATH=/tmp", [])


class CommandLineTest(unittest.TestCase):
    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(REPO / "lib" / "setup_knobs.py")] + list(args),
                              capture_output=True, text=True)

    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            pristine, fixable, other = (Path(tmp) / name for name in ("a", "b", "c"))
            pristine.write_text(PRISTINE)
            fixable.write_text(with_prefix(PRISTINE, LAUNCH, " ".join(GSO_GRO) + " "))
            other.write_text(PRISTINE.replace("--port=0", "--port=1"))
            result = self.run_tool("extract", str(pristine), str(fixable))
            self.assertEqual((result.returncode, result.stdout.split()), (0, GSO_GRO))
            self.assertEqual(self.run_tool("extract", str(pristine), str(other)).returncode, 1)
        self.assertEqual(self.run_tool("merge", "", "TS_A=1").stdout.strip(), "TS_A=1")
        self.assertEqual(self.run_tool("merge", "", "A=1").returncode, 2)


if __name__ == "__main__":
    unittest.main()
