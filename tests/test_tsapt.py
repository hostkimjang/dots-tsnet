"""tsapt 의 명령줄 해석과 설치 상태 추론을 확인하는 오프라인 테스트입니다."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def load_tsapt(tsnet_dir, doc_dir):
    os.environ["TSNET_DIR"] = str(tsnet_dir)
    os.environ["TSNET_DOC_DIR"] = str(doc_dir)
    loader = importlib.machinery.SourceFileLoader("tsapt_under_test", str(REPO / "lib" / "bin" / "tsapt"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    module._ARCH = "amd64"
    return module


class CommandLineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tsapt = load_tsapt(Path(self.tmp.name), Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def test_option_before_command(self):
        _, pos, flags = self.tsapt.split_args(["-y", "install", "curl"])
        self.assertEqual(pos, ["install", "curl"])
        self.assertIn("-y", flags)

    def test_option_value_is_not_a_package(self):
        _, pos, _ = self.tsapt.split_args(["-o", "Acquire::Retries=5", "install", "jq"])
        self.assertEqual(pos, ["install", "jq"])

    def test_combined_short_flags(self):
        opts, _, flags = self.tsapt.split_args(["install", "-qy", "jq"])
        self.assertTrue({"-q", "-y"} <= flags)
        self.assertEqual(self.tsapt.forward_opts(opts), ["-q"])

    def test_forwarded_options_drop_modes_handled_by_tsapt(self):
        opts, _, _ = self.tsapt.split_args(["install", "-y", "-s", "--no-install-recommends", "-o", "A=1", "x"])
        self.assertEqual(self.tsapt.forward_opts(opts), ["-o", "A=1"])

    def test_simulation_lines(self):
        lines = [
            "Inst libsctp1 (1.0.21+dfsg-1 Debian:13.7/stable [amd64])",
            "Inst tzdata [2025a-1] (2025b-0+deb13u1 Debian:13.7/stable-updates [all])",
            "Inst libcares2 (1.34.5-1+deb13u1 Debian:13.7/stable, Debian-Security:13/stable-security [amd64])",
            "Conf libsctp1 (1.0.21+dfsg-1 Debian:13.7/stable [amd64])",
        ]
        got = [m.groups() for m in map(self.tsapt.INST.match, lines) if m]
        self.assertEqual(got, [("libsctp1", "1.0.21+dfsg-1", "amd64"),
                               ("tzdata", "2025b-0+deb13u1", "all"),
                               ("libcares2", "1.34.5-1+deb13u1", "amd64")])

    def test_alternatives_from_postinst(self):
        script = ("#!/bin/sh\nset -e\n"
                  "update-alternatives --install /usr/bin/figlet figlet /usr/bin/figlet-figlet 100 \\\n"
                  "  --slave /usr/share/man/man6/figlet.6.gz figlet.6.gz /usr/share/man/man6/figlet-figlet.6.gz\n"
                  "update-alternatives --install /usr/bin/x x \"$TARGET\" 50\n")
        self.assertEqual(self.tsapt.alternatives_from_script(script), [
            ("/usr/bin/figlet", "/usr/bin/figlet-figlet"),
            ("/usr/share/man/man6/figlet.6.gz", "/usr/share/man/man6/figlet-figlet.6.gz"),
        ])


class StatusInferenceTest(unittest.TestCase):
    PACKAGES = (
        "Package: app\nVersion: 1.0\nArchitecture: amd64\nDepends: libdep (>= 1), virt | other\n\n"
        "Package: libdep\nVersion: 1.2\nArchitecture: amd64\n\n"
        "Package: prov\nVersion: 3\nArchitecture: all\nProvides: virt\n\n"
        "Package: base\nVersion: 7\nArchitecture: amd64\nPriority: required\n\n"
        "Package: unrelated\nVersion: 9\nArchitecture: amd64\n"
    )

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "doc" / "app").mkdir(parents=True)
        self.tsapt = load_tsapt(root / "tsnet", root / "doc")
        self.tsapt.ensure_dirs()
        (self.tsapt.LISTS / "example_Packages").write_text(self.PACKAGES)

    def tearDown(self):
        self.tmp.cleanup()

    def status(self):
        return {b["Package"]: b for b in self.tsapt.parse_blocks(self.tsapt.STATUS.read_text())}

    def test_documented_packages_and_their_dependencies_are_installed(self):
        self.tsapt.rebuild_status()
        status = self.status()
        self.assertEqual(set(status), {"app", "libdep", "prov", "base"})
        self.assertEqual(status["app"]["Status"], "install ok installed")
        self.assertEqual(status["app"]["Depends"], "libdep (>= 1), virt | other")

    def test_package_installed_by_tsapt_wins(self):
        self.tsapt.USER_STATUS.write_text("Package: libdep\nStatus: install ok installed\nVersion: 2.0\n"
                                          "Architecture: amd64\n")
        self.tsapt.rebuild_status()
        status = self.status()
        self.assertEqual(status["libdep"]["Version"], "2.0")
        self.assertEqual(self.tsapt.STATUS.read_text().count("Package: libdep\n"), 1)


if __name__ == "__main__":
    unittest.main()
