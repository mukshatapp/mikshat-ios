import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("update_core_run", Path(__file__).with_name("run.py"))
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class NativeExecutionVerifierTests(unittest.TestCase):
    cases = ["source.cpp::First", "source.cpp::Second"]

    def complete_log(self, cases=None):
        selected = self.cases if cases is None else cases
        return "\n".join("Running " + case + "\n[OK]" for case in selected) + "\nAll tests passed.\n"

    def test_complete_execution_passes(self):
        self.assertTrue(RUNNER.verify(self.complete_log(), self.cases, 0)["passed"])

    def test_empty_selection_does_not_pass_a_success_summary(self):
        self.assertFalse(RUNNER.verify("All tests passed.", [], 0)["passed"])

    def test_missing_registered_case_fails(self):
        report = RUNNER.verify(self.complete_log(self.cases[:1]), self.cases, 0)
        self.assertFalse(report["passed"])
        self.assertEqual(report["missingCases"], self.cases[1:])

    def test_repeated_execution_fails(self):
        report = RUNNER.verify(self.complete_log(self.cases + self.cases[:1]), self.cases, 0)
        self.assertFalse(report["passed"])
        self.assertEqual(report["repeatedCases"], self.cases[:1])

    def test_unexpected_case_cannot_replace_a_required_case(self):
        report = RUNNER.verify(self.complete_log([self.cases[0], "source.cpp::Other"]), self.cases, 0)
        self.assertFalse(report["passed"])
        self.assertEqual(report["unexpectedCases"], ["source.cpp::Other"])

    def test_nonzero_exit_fails_even_with_complete_success_events(self):
        self.assertFalse(RUNNER.verify(self.complete_log(), self.cases, 1)["passed"])

    def test_native_failure_marker_fails_even_with_success_summary(self):
        self.assertFalse(RUNNER.verify(self.complete_log() + "[FAILED]", self.cases, 0)["passed"])

    def test_started_cases_require_individual_success_events(self):
        log = "\n".join("Running " + case for case in self.cases) + "\nAll tests passed.\n"
        self.assertFalse(RUNNER.verify(log, self.cases, 0)["passed"])


if __name__ == "__main__":
    unittest.main()
