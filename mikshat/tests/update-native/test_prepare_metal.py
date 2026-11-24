from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import prepare_metal


class MetalPreflightTests(unittest.TestCase):
    def check(self, working_after=0, download_status=0):
        calls, downloads = [], 0
        def run(args, **kwargs):
            nonlocal downloads
            calls.append(args)
            status, stdout, stderr = 0, "", ""
            if args == ["xcodebuild", "-version"]:
                stdout = "Xcode 27.0\nBuild version 27A266a\n"
            elif "--show-sdk-path" in args:
                stdout = "/selected/Xcode27/SDKs/" + args[2] + ".sdk\n"
            elif "-downloadComponent" in args:
                downloads += 1
                status = download_status
                stderr = "Failed fetching catalog for assetType MetalToolchain" if status else ""
            elif "metal" in args and "--find" not in args:
                if downloads >= working_after:
                    Path(args[args.index("-o") + 1]).write_bytes(b"compiled-metal-artifact")
                else:
                    status, stderr = 1, "missing Metal Toolchain"
            return subprocess.CompletedProcess(args, status, stdout=stdout, stderr=stderr)
        with tempfile.TemporaryDirectory() as temp, patch.object(prepare_metal.subprocess, "run", side_effect=run), patch.object(
                prepare_metal.time, "sleep") as sleep:
            report = prepare_metal.prepare(Path(temp))
            self.assertTrue((Path(temp) / "preflight.log").is_file())
            self.assertTrue((Path(temp) / "summary.json").is_file())
            backoffs = [entry.args[0] for entry in sleep.call_args_list]
        return report, calls, backoffs

    def test_installed_compiler_flushes_cache_and_compiles_both_sdks_without_download(self):
        report, calls, backoffs = self.check()
        self.assertTrue(report["passed"])
        self.assertEqual(report["downloadAttempts"], 0)
        self.assertFalse(any("-runFirstLaunch" in args or "-downloadComponent" in args for args in calls))
        first_compile = next(index for index, args in enumerate(calls) if "-c" in args)
        self.assertLess(calls.index(["xcrun", "-k"]), first_compile)
        self.assertLess(calls.index(["xcrun", "simctl", "runtime", "list"]), first_compile)
        self.assertEqual({args[2] for args in calls if "-c" in args}, set(prepare_metal.PLATFORMS))
        self.assertEqual(sum("metal" in args and "-target" in args and "-c" not in args for args in calls), 2)
        self.assertFalse(backoffs)

    def test_catalog_failure_then_second_attempt_installs_working_compiler(self):
        report, calls, backoffs = self.check(working_after=2, download_status=70)
        self.assertTrue(report["passed"], "Functional compilers decide success even after nonzero downloader output")
        self.assertEqual(report["downloadAttempts"], 2)
        self.assertEqual([entry["passed"] for entry in report["functionalChecks"]], [False, False, False, True])
        self.assertEqual(backoffs, [5])
        self.assertTrue(any(entry.get("exitStatus") == 70 and "catalog" in entry["stderr"] for entry in report["commands"]))

    def test_permanent_compile_failure_blocks_even_when_download_exits_zero(self):
        report, calls, backoffs = self.check(working_after=99)
        self.assertFalse(report["passed"])
        self.assertEqual(report["downloadAttempts"], 3)
        self.assertEqual(backoffs, [5, 15])
        self.assertIn("could not compile and link", report["error"])

    def test_zero_exit_without_fresh_outputs_cannot_reuse_stale_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for platform in prepare_metal.PLATFORMS:
                for suffix in (".air", ".metallib"):
                    (directory / (platform + suffix)).write_bytes(b"stale artifact")
            report = {"commands": [], "functionalChecks": []}
            with patch.object(prepare_metal.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout="/selected/SDK", stderr="")):
                passed = prepare_metal.functional_check(directory, report, directory / "preflight.log", 0)
            self.assertFalse(passed)
            self.assertFalse(list(directory.glob("*.air")))
            self.assertFalse(list(directory.glob("*.metallib")))

    def test_timed_out_command_retains_partial_streams_and_does_not_become_success(self):
        report = {"commands": []}
        with tempfile.TemporaryDirectory() as temp, patch.object(prepare_metal.subprocess, "run", side_effect=
                subprocess.TimeoutExpired(["tool"], 30, output=b"partial stdout", stderr=b"partial stderr")):
            log = Path(temp) / "preflight.log"
            entry = prepare_metal.run(["tool"], report, log)
            self.assertIn("partial stderr", log.read_text())
        self.assertTrue(entry["timedOut"])
        self.assertIsNone(entry["exitStatus"])
        self.assertEqual(entry["stdout"], "partial stdout")


if __name__ == "__main__":
    unittest.main()
