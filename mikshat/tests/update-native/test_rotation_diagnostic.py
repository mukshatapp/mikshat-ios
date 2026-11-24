import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


DIRECTORY = Path(__file__).parent
sys.path.insert(0, str(DIRECTORY))
import hang_sampler
import rotation_diagnostic


class SamplingScopeTests(unittest.TestCase):
    def phase(self, **changes):
        value = dict(version=1, bundle=hang_sampler.BUNDLE, mainThread=True, pid=123,
                     run="9b3b4353-851a-4e88-b88e-3561d9260d80", sequence=1,
                     phase="layout.map.begin", timestamp=100)
        value.update(changes)
        return value

    def test_only_a_stale_active_main_phase_becomes_a_candidate(self):
        self.assertTrue(hang_sampler.phase_candidate(self.phase(), 111, 10))
        for changes in (dict(phase="test.completed"),
                        dict(timestamp=110), dict(bundle="org.other.app"), dict(mainThread=False),
                        dict(pid=True), dict(run="../../outside")):
            self.assertFalse(hang_sampler.phase_candidate(self.phase(**changes), 111, 10), changes)

    def test_event_loop_hang_after_a_synchronous_end_marker_still_gets_a_stack(self):
        self.assertTrue(hang_sampler.phase_candidate(self.phase(phase="layout.window.end"), 111, 10))

    def test_swift_uppercase_uuid_phase_is_accepted(self):
        record = self.phase(run="9B3B4353-851A-4E88-B88E-3561D9260D80")
        self.assertTrue(hang_sampler.valid_identity(record))
        self.assertTrue(hang_sampler.phase_candidate(record, 111, 10))

    def test_shell_or_other_simulator_cannot_match_the_exact_app_process(self):
        executable = Path("/sim/one/Organic Maps.app/Organic Maps")
        self.assertTrue(hang_sampler.exact_app_process(str(executable) + " -IsTests", executable))
        for command in ("sh -c " + str(executable), "/sim/two/Organic Maps.app/Organic Maps",
                        str(executable) + "Suffix", "Organic Maps"):
            self.assertFalse(hang_sampler.exact_app_process(command, executable))

    def test_a_pid_for_another_process_is_never_sampled(self):
        with tempfile.TemporaryDirectory() as temp:
            sampler = hang_sampler.PhaseSampler("isolated-sim", temp)
            sampler.executable = Path("/sim/one/app/Organic Maps")
            with patch.object(hang_sampler.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout="/unrelated/process", stderr="")) as run:
                sampler.sample(self.phase())
            self.assertEqual(run.call_count, 1)
            report = json.loads((Path(temp) / "monitor.jsonl").read_text())
            self.assertEqual(report["result"], "process-not-matched")

    def test_hard_timeout_stops_launcher_and_preserves_failure(self):
        class Sampler:
            ticks = 0
            def tick(self):
                self.ticks += 1
        sampler = Sampler()
        with tempfile.TemporaryDirectory() as temp:
            status, timed_out = rotation_diagnostic.run_bounded(
                [sys.executable, "-c", "import time; time.sleep(60)"], Path(temp) / "test.log", sampler, 0.01)
        self.assertTrue(timed_out)
        self.assertNotEqual(status, 0)
        self.assertGreater(sampler.ticks, 0)

    def test_sample_timeout_retains_streams_and_uses_one_reverified_lldb_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            sampler = hang_sampler.PhaseSampler("isolated-sim", temp)
            sampler.executable = Path("/sim/app/Organic Maps")
            sampler.journal = Path(temp) / "journal.jsonl"
            phase = self.phase(timestamp=time.time() - 30)
            sampler.started = phase["timestamp"] - 1
            sampler.journal.write_text(json.dumps(phase) + '\n{"incomplete":')
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                if args[0] == "ps":
                    return subprocess.CompletedProcess(args, 0, stdout=str(sampler.executable) + " -IsTests", stderr="")
                if args[0] == "/usr/bin/sample":
                    Path(args[-1]).write_text("Sampling process; no thread frames yet")
                    raise subprocess.TimeoutExpired(args, 20, output=b"captured raw samples", stderr=b"symbolication pending")
                return subprocess.CompletedProcess(args, 0, stdout="* thread #1\n  frame #0: 0x123 UIKitCore`layout\n", stderr="")
            with patch.object(hang_sampler.subprocess, "run", side_effect=run):
                sampler.sample(phase)
                sampler.sample(phase)
            self.assertEqual(sum(args[:2] == ["xcrun", "lldb"] for args in calls), 1)
            first_lldb = next(index for index, args in enumerate(calls) if args[:2] == ["xcrun", "lldb"])
            self.assertEqual(calls[first_lldb - 1][0], "ps")
            reports = [json.loads(line) for line in (Path(temp) / "monitor.jsonl").read_text().splitlines()]
            sample = reports[0]
            self.assertTrue(sample["timedOut"])
            self.assertTrue(sample["partialFilePresent"])
            self.assertIn("captured raw samples", sample["stdout"])
            self.assertIn("symbolication pending", sample["stderr"])
            self.assertFalse(sample["stackFramesCaptured"])
            self.assertTrue(next(row for row in reports if row["event"] == "stale-phase-lldb")["stackFramesCaptured"])

    def test_fallback_never_attaches_after_the_test_phase_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            sampler = hang_sampler.PhaseSampler("isolated-sim", temp)
            sampler.executable = Path("/sim/app/Organic Maps")
            sampler.journal = Path(temp) / "journal.jsonl"
            phase = self.phase(timestamp=time.time() - 30)
            sampler.journal.write_text(json.dumps(dict(phase, sequence=2, phase="test.completed")) + "\n")
            with patch.object(hang_sampler.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout=str(sampler.executable), stderr="")) as run:
                sampler.fallback(phase)
            self.assertEqual(run.call_count, 1)
            report = json.loads((Path(temp) / "monitor.jsonl").read_text())
            self.assertEqual(report["result"], "fallback-identity-or-phase-changed")
            self.assertNotIn(phase["pid"], sampler.fallback_pids)
            next_phase = dict(phase, sequence=3, phase="scene.geometry.wait")
            sampler.started = phase["timestamp"] - 1
            sampler.journal.write_text(json.dumps(next_phase) + '\n{"partial":')
            with patch.object(hang_sampler.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout=str(sampler.executable), stderr="")) as run:
                sampler.fallback(next_phase)
            self.assertEqual(run.call_count, 2, "Skipped attachment must not consume the later stale phase's capture budget")
            self.assertIn(phase["pid"], sampler.fallback_pids)


class ProbePlanTests(unittest.TestCase):
    def test_only_native_target_gets_each_explicit_probe_and_renderer_stays_off(self):
        original = {"TestTargets": [{"BlueprintName": "OMapsTests", "CommandLineArguments": ["-IsTests", "-MikshatRequireRenderer"]},
                                     {"BlueprintName": "UnrelatedTests", "CommandLineArguments": ["-MikshatRequireRenderer"]}]}
        automatic = rotation_diagnostic.patch_plan(original, "automatic")
        self.assertEqual(automatic["TestTargets"][0]["CommandLineArguments"], ["-IsTests", "-MikshatRotationDiagnostics"])
        for mode, flag in [("fixed-title", "-MikshatFixedTitleHeight"), ("preview-insets", "-MikshatPreviewInsetsNever")]:
            plan = rotation_diagnostic.patch_plan(original, mode)
            self.assertEqual(plan["TestTargets"][0]["CommandLineArguments"], ["-IsTests", "-MikshatRotationDiagnostics", flag])
            self.assertIn("-MikshatRequireRenderer", plan["TestTargets"][1]["CommandLineArguments"])
        self.assertIn("-MikshatRequireRenderer", original["TestTargets"][0]["CommandLineArguments"])

    def test_missing_or_duplicate_native_target_is_infrastructure_failure(self):
        with self.assertRaises(ValueError):
            rotation_diagnostic.patch_plan({}, "automatic")
        with self.assertRaises(ValueError):
            rotation_diagnostic.patch_plan([{"BlueprintName": "OMapsTests"}] * 2, "automatic")

    def test_production_plan_removes_all_layout_probes_and_diagnostic_hook(self):
        original = {"TestTargets": [{"BlueprintName": "OMapsTests", "CommandLineArguments":
                                     ["-IsTests", *sorted(rotation_diagnostic.PROBE_FLAGS), rotation_diagnostic.PRODUCTION_FLAG]},
                                    {"BlueprintName": "UnrelatedTests", "CommandLineArguments": ["-MikshatRotationDiagnostics"]}]}
        plan = rotation_diagnostic.patch_plan(original, "automatic", production=True)
        self.assertEqual(plan["TestTargets"][0]["CommandLineArguments"], ["-IsTests", rotation_diagnostic.PRODUCTION_FLAG])
        self.assertEqual(plan["TestTargets"][1], original["TestTargets"][1])
        diagnostic = rotation_diagnostic.patch_plan(original, "automatic")
        self.assertNotIn(rotation_diagnostic.PRODUCTION_FLAG, diagnostic["TestTargets"][0]["CommandLineArguments"])
        with self.assertRaises(ValueError):
            rotation_diagnostic.patch_plan(original, "preview-insets", production=True)


class ProductionGateTests(unittest.TestCase):
    def phases(self, language="ar"):
        return [dict(phase="scene.attach.end", language=language, direction="RTL" if language == "ar" else "LTR"),
                dict(phase="verification.previewInsets.observed", insetsLayoutMarginsFromSafeArea=False,
                     diagnosticHookEnabled=False, runtimeProbeFlags=[]),
                *[dict(phase="rotation.end", cycle=cycle, orientation=orientation)
                  for cycle, orientation in rotation_diagnostic.ROTATIONS],
                dict(phase="test.completed")]

    def log(self, language="ar", family="phone"):
        events = ["MIKSHAT_FEATURE_LAYOUT_PROFILE " + json.dumps({
            "language": language, "direction": "RTL" if language == "ar" else "LTR",
            "idiom": "pad" if family == "tablet" else "phone", "productionVerification": True,
            "runtimeProbeFlags": []})]
        cases = rotation_diagnostic.selected_cases(True, family)
        for name, methods in cases.items():
            for method in methods:
                case = f"-[OMapsTests.{name} {method}]"
                events += [f"Test Case '{case}' started.", f"Test Case '{case}' passed (1.0 seconds)."]
        count = sum(len(methods) for methods in cases.values())
        events += [f"Executed {count} tests, with 0 failures in 24.0 seconds", "** TEST EXECUTE SUCCEEDED **"]
        return "\n".join(events) + "\n"

    def evaluate(self, directory, phases, log=None, language="ar", profile="phone-ar", family="phone"):
        samples = directory / "native-samples"
        samples.mkdir(exist_ok=True)
        (samples / "phases-seen.jsonl").write_text("".join(json.dumps(item) + "\n" for item in phases))
        if log is None:
            log = self.log(language, family)
        (directory / "xcodebuild-test.log").write_text(log)
        return rotation_diagnostic.evaluate_mode("automatic", directory, 0, False, production=True,
                                                 language=language, profile=profile, family=family)

    def test_source_layout_and_all_twelve_rotations_pass_without_claiming_physical_proof(self):
        with tempfile.TemporaryDirectory() as temp:
            report = self.evaluate(Path(temp), self.phases())
        self.assertTrue(report["productionLayoutSimulatorVerified"])
        self.assertTrue(report["productionEvidence"]["rotationPatternMatched"])
        self.assertEqual(rotation_diagnostic.classify([report], production=True), "infrastructureFailed")
        self.assertEqual(rotation_diagnostic.classify([report]), "infrastructureFailed")
        profiles = []
        with tempfile.TemporaryDirectory() as temp:
            for profile in rotation_diagnostic.PRODUCTION_PROFILES:
                directory = Path(temp) / profile["id"]
                directory.mkdir()
                phases = self.phases(profile["language"]) if profile["family"] == "phone" else []
                profiles.append(self.evaluate(directory, phases, language=profile["language"],
                                              profile=profile["id"], family=profile["family"]))
        self.assertEqual(rotation_diagnostic.classify(profiles, production=True), "productionLayoutSimulatorPassed")
        profiles[-1]["profile"] = "phone-ar"
        self.assertEqual(rotation_diagnostic.classify(profiles, production=True), "infrastructureFailed")

    def test_exact_feature_cases_are_required_even_when_class_totals_match(self):
        original = "testEveryBundledMapCanActivateDeactivateAndReactivateWithoutDeletingItsFile"
        with tempfile.TemporaryDirectory() as temp:
            report = self.evaluate(Path(temp), self.phases(), self.log().replace(original, "testUnrelatedMapCase"))
        self.assertFalse(report["passed"])
        self.assertEqual(report["nativeExecution"]["casesStarted"], 24)
        self.assertEqual(report["nativeExecution"]["missingCases"], ["MikshatSupplementaryMapsTests." + original])
        self.assertEqual(report["nativeExecution"]["unexpectedCases"], ["MikshatSupplementaryMapsTests.testUnrelatedMapCase"])

    def test_wrong_language_or_direction_cannot_satisfy_english_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for phases in (self.phases(), [dict(item, direction="RTL") if item["phase"] == "scene.attach.end"
                                          else item for item in self.phases("en")]):
                report = self.evaluate(directory, phases, language="en", profile="phone-en")
                self.assertFalse(report["localeConfirmed"])
                self.assertFalse(report["passed"])

    def test_skipped_feature_case_cannot_be_hidden_by_rotation_success(self):
        log = self.log().replace("passed (1.0 seconds).", "skipped (1.0 seconds).", 1)
        with tempfile.TemporaryDirectory() as temp:
            report = self.evaluate(Path(temp), self.phases(), log)
        self.assertFalse(report["passed"])

    def test_production_filters_select_all_24_declared_methods_and_no_probe_case(self):
        filters = rotation_diagnostic.testing_filters(True)
        self.assertEqual(len(filters), 24)
        self.assertEqual(len(set(filters)), 24)
        self.assertEqual(rotation_diagnostic.testing_filters(False), [
            "-only-testing:OMapsTests/MikshatMapSceneLayoutTests/" + rotation_diagnostic.CASE])
        files = {
            "MikshatMapSceneLayoutTests": "MikshatResponsivePresentationTests.swift",
            "MikshatResponsivePresentationTests": "MikshatResponsivePresentationTests.swift",
            "MikshatResponsivePlaceCoordinatesTests": "MikshatResponsiveUITests.swift",
            "SearchHistoryOnlyTests": "SearchHistoryOnlyTests.swift",
            "SearchOnMapTests": "SearchOnMapTests.swift",
        }
        for name, methods in rotation_diagnostic.PRODUCTION_CASES.items():
            path = (rotation_diagnostic.ROOT / "iphone/Maps/Tests/Core/Storage/MikshatSupplementaryMapsTests.swift"
                    if name == "MikshatSupplementaryMapsTests" else rotation_diagnostic.ROOT /
                    "iphone/Maps/Tests/UI/SearchOnMapTests" / files[name])
            source = path.read_text()
            for method in methods:
                self.assertIn("func " + method + "(", source)

    def test_tablets_require_23_component_cases_and_actual_locale_without_claiming_scene_rotation(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            report = self.evaluate(directory, [], language="en", profile="tablet-en", family="tablet")
            self.assertTrue(report["passed"])
            self.assertEqual(report["nativeExecution"]["expectedTotal"], 23)
            self.assertFalse(report["productionEvidence"]["phoneSceneRotationRequired"])
            self.assertIsNone(report["productionEvidence"]["rotationPatternMatched"])
            for changes in ({"language": "ar"}, {"direction": "RTL"}, {"idiom": "phone"},
                            {"productionVerification": False}, {"runtimeProbeFlags": ["-MikshatRotationDiagnostics"]}):
                log = self.log("en", "tablet")
                marker = json.loads(log.splitlines()[0].split(" ", 1)[1])
                marker.update(changes)
                log = "MIKSHAT_FEATURE_LAYOUT_PROFILE " + json.dumps(marker) + "\n" + log.split("\n", 1)[1]
                report = self.evaluate(directory, [], log, language="en", profile="tablet-en", family="tablet")
                self.assertFalse(report["passed"], changes)
            no_marker = self.log("en", "tablet").split("\n", 1)[1]
            self.assertFalse(self.evaluate(directory, [], no_marker, language="en", profile="tablet-en",
                                           family="tablet")["passed"])
        filters = rotation_diagnostic.testing_filters(True, "tablet")
        self.assertEqual(len(filters), 23)
        self.assertFalse(any(rotation_diagnostic.CASE in item for item in filters))

    def test_installed_phone_and_tablet_types_are_required(self):
        available = [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16", "name": "iPhone 16"},
                     {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB",
                      "name": "iPad Pro 13-inch (M4) (8GB)"}]
        self.assertEqual(rotation_diagnostic.device_type("phone", available), available[0]["identifier"])
        self.assertEqual(rotation_diagnostic.device_type("tablet", available), available[1]["identifier"])
        with self.assertRaises(RuntimeError):
            rotation_diagnostic.device_type("tablet", available[:1])

    def test_probe_contamination_missing_rotation_or_terminal_cannot_pass(self):
        variations = []
        for key, value in [("insetsLayoutMarginsFromSafeArea", True), ("diagnosticHookEnabled", True),
                           ("runtimeProbeFlags", ["-MikshatPreviewInsetsNever"])]:
            phases = self.phases()
            phases[1][key] = value
            variations.append(phases)
        variations += [self.phases()[:-1], self.phases()[:2] + self.phases()[3:],
                       self.phases() + [dict(phase="probe.previewInsetsNever.applied")],
                       self.phases() + [dict(phase="layout.probe.armed")]]
        with tempfile.TemporaryDirectory() as temp:
            for phases in variations:
                with self.subTest(phases=phases):
                    report = self.evaluate(Path(temp), phases)
                    self.assertFalse(report["passed"])
                    self.assertFalse(report["productionLayoutSimulatorVerified"])

    def test_source_marker_cannot_turn_zero_native_tests_into_a_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            report = self.evaluate(Path(temp), self.phases(), log="Executed 0 tests, with 0 failures\n** TEST EXECUTE SUCCEEDED **")
        self.assertFalse(report["productionLayoutSimulatorVerified"])
        self.assertEqual(rotation_diagnostic.classify([report], production=True), "infrastructureFailed")


class EvidenceClassificationTests(unittest.TestCase):
    def rows(self, passed=False):
        return [dict(mode=mode, passed=passed, modeApplied=True) for mode in rotation_diagnostic.MODES]

    def test_unapplied_probe_is_not_a_successful_ab_comparison(self):
        rows = self.rows()
        rows[1].update(passed=True, modeApplied=False)
        self.assertEqual(rotation_diagnostic.classify(rows), "modeNotApplied")

    def test_baseline_failure_and_probe_pass_comparison_does_not_claim_a_hang_cause(self):
        rows = self.rows()
        rows[1].update(passed=True, hangStackCollected=False)
        self.assertEqual(rotation_diagnostic.classify(rows), "baselineFailsProbePasses")

    def test_expected_diagnostic_outcomes_remain_distinct(self):
        self.assertEqual(rotation_diagnostic.classify([]), "infrastructureFailed")
        self.assertEqual(rotation_diagnostic.classify(self.rows(True)), "allPass")
        self.assertEqual(rotation_diagnostic.classify(self.rows(False)), "allFail")
        rows = self.rows()
        rows[2]["mode"] = "fixed-title"
        self.assertEqual(rotation_diagnostic.classify(rows), "infrastructureFailed")

    def test_nonempty_error_output_is_not_a_native_stack_or_a_passing_test(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            samples = directory / "native-samples"
            samples.mkdir()
            (samples / "sample-error.txt").write_text("Analysis of process 123; no call graph")
            report = rotation_diagnostic.evaluate_mode("automatic", directory, -15, True)
            self.assertFalse(report["nativeStackCollected"])
            self.assertFalse(report["passed"])
            (samples / "lldb-stack.txt").write_text("* thread #1\n  frame #0: 0x123 UIKitCore`layout\n")
            report = rotation_diagnostic.evaluate_mode("automatic", directory, -15, True)
            self.assertTrue(report["nativeStackCollected"])
            self.assertTrue(report["hangStackCollected"])
            self.assertFalse(report["passed"], "A captured stack must never convert zero executed cases into a pass")

    def test_zero_native_starts_remain_infrastructure_failure_even_with_a_probe_marker(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            samples = directory / "native-samples"
            samples.mkdir()
            (samples / "phases-seen.jsonl").write_text(json.dumps(dict(phase="probe.titleInsetsAutomatic.observed", behavior=0)) + "\n")
            report = rotation_diagnostic.evaluate_mode("automatic", directory, 0, False)
            self.assertTrue(report["modeApplied"])
            self.assertFalse(report["passed"])
            rows = self.rows(True)
            rows[0] = report
            self.assertEqual(rotation_diagnostic.classify(rows), "infrastructureFailed")


class DiagnosticExportTests(unittest.TestCase):
    def test_export_copies_only_capped_text_and_preserves_optional_timeout_details(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            reports = root / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)
            (reports / "Organic Maps.ips").write_text('{"threads": []}')
            (reports / "Other App.ips").write_text("unrelated")
            (reports / "Organic binary.ips").write_bytes(b"\x00binary")
            bundle = root / "Result.xcresult"
            bundle.mkdir()
            destination = root / "output"
            destination.mkdir()
            def run(args, **kwargs):
                if "help" in args:
                    return subprocess.CompletedProcess(args, 0, stdout="--path PATH --output-path OUTPUT --only-failures", stderr="")
                exported = Path(args[args.index("--output-path") + 1])
                exported.mkdir()
                # The four MiB boundary splits this final Arabic character.
                (exported / "native.hang").write_text("x" + "ض" * (2 * 1024 * 1024 + 1))
                (exported / "binary.trace").write_bytes(b"\x00binary")
                raise subprocess.TimeoutExpired(args, 60, output=b"partial export", stderr=b"export timed out")
            with patch.object(rotation_diagnostic.Path, "home", return_value=root), patch.object(
                    rotation_diagnostic.subprocess, "run", side_effect=run):
                report = rotation_diagnostic.collect_diagnostics(bundle, destination, time.time() - 1)
            names = {row["file"] for row in report["files"]}
            self.assertIn("host-app-reports/Organic Maps.ips", names)
            self.assertNotIn("host-app-reports/Other App.ips", names)
            self.assertNotIn("host-app-reports/Organic binary.ips", names)
            exported = next(row for row in report["files"] if row["file"] == "xcresult-diagnostics/native.hang")
            self.assertEqual(exported["bytes"], 4 * 1024 * 1024 - 1)
            (destination / "exported-diagnostics" / exported["file"]).read_text(encoding="utf-8")
            self.assertTrue(exported["truncated"])
            self.assertTrue(report["commands"][-1]["timedOut"])
            self.assertIn("partial export", report["commands"][-1]["stdout"])
            attachments = [row for row in report["commands"] if row["command"][2:4] == ["export", "attachments"]]
            self.assertEqual(len(attachments), 1)
            self.assertIn("--only-failures", attachments[0]["command"])
            self.assertIn("xcresult-attachments/native.hang", names)


if __name__ == "__main__":
    unittest.main()
