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


class ProbePlanTests(unittest.TestCase):
    def test_only_the_native_target_gets_the_never_probe_and_renderer_stays_off(self):
        original = {"TestTargets": [{"BlueprintName": "OMapsTests", "CommandLineArguments": ["-IsTests", "-MikshatRequireRenderer"]},
                                     {"BlueprintName": "UnrelatedTests", "CommandLineArguments": ["-MikshatRequireRenderer"]}]}
        automatic = rotation_diagnostic.patch_plan(original, "automatic")
        never = rotation_diagnostic.patch_plan(original, "never")
        self.assertEqual(automatic["TestTargets"][0]["CommandLineArguments"], ["-IsTests"])
        self.assertEqual(never["TestTargets"][0]["CommandLineArguments"], ["-IsTests", "-MikshatTitleInsetsNever"])
        self.assertIn("-MikshatRequireRenderer", never["TestTargets"][1]["CommandLineArguments"])
        self.assertIn("-MikshatRequireRenderer", original["TestTargets"][0]["CommandLineArguments"])

    def test_missing_or_duplicate_native_target_is_infrastructure_failure(self):
        with self.assertRaises(ValueError):
            rotation_diagnostic.patch_plan({}, "automatic")
        with self.assertRaises(ValueError):
            rotation_diagnostic.patch_plan([{"BlueprintName": "OMapsTests"}] * 2, "automatic")


class EvidenceClassificationTests(unittest.TestCase):
    def test_unapplied_probe_is_not_a_successful_ab_comparison(self):
        self.assertEqual(rotation_diagnostic.classify([
            dict(passed=False, modeApplied=True), dict(passed=True, modeApplied=False)]), "modeNotApplied")

    def test_native_failure_without_a_hang_stack_cannot_prove_the_hang_difference(self):
        self.assertEqual(rotation_diagnostic.classify([
            dict(passed=False, modeApplied=True, hangStackCollected=False),
            dict(passed=True, modeApplied=True)]), "otherFailure")

    def test_expected_diagnostic_outcomes_remain_distinct(self):
        self.assertEqual(rotation_diagnostic.classify([]), "infrastructureFailed")
        self.assertEqual(rotation_diagnostic.classify([
            dict(passed=False, modeApplied=True, hangStackCollected=True),
            dict(passed=True, modeApplied=True)]), "autoHangsNeverPasses")
        self.assertEqual(rotation_diagnostic.classify([dict(passed=True, modeApplied=True)] * 2), "bothPass")
        self.assertEqual(rotation_diagnostic.classify([dict(passed=False, modeApplied=True)] * 2), "bothFail")


if __name__ == "__main__":
    unittest.main()
