from pathlib import Path
import tempfile
import unittest

import run_native


IDENTITY = "-[OMapsTests.CarPlayServiceTests testPanDirectionOffset]"
NSLOG = (
    "2026-11-28 12:08:13.272774+0000 Organic Maps (Debug)[54404:137352] [OM] "
    "I(4) 82.15433 map/bookmark_helpers.cpp:690 SaveKmlFileSafe(): "
    "Save kml file of type FileType [.kml] to /tmp/bookmarks/CarPlayTests.kml"
)
START = f"Test Case '{IDENTITY}' started.\n"
PASS = f"Test Case '{IDENTITY}' passed (0.002 seconds).\n"
SUMMARY = "Executed 1 test, with 0 failures (0 unexpected).\n** TEST EXECUTE SUCCEEDED **\n"


class CarPlayNativeResultTests(unittest.TestCase):
    cases = {"CarPlayServiceTests": ["testPanDirectionOffset"]}

    def analyze(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "xcodebuild-test.log"
            path.write_text(text)
            result = run_native.analyze(path, self.cases)
            self.assertEqual(path.read_text(), text, "The original evidence must remain unchanged")
            return result

    def interrupted(self, outcome="passed (0.002 seconds).", message=NSLOG):
        return f"Test Case '{IDENTITY}'{message}\n {outcome}\n"

    def testRealConcurrentNSLogExampleRetainsOneStartAndPass(self):
        result = self.analyze(START + self.interrupted() + SUMMARY)
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["interruptedCaseEventsNormalized"], 1)
        counts = result["classCounts"]["CarPlayServiceTests"]
        self.assertEqual((counts["uniqueCases"], counts["started"], counts["passed"]), (1, 1, 1))

    def testOrdinaryCompleteEventsAreNotChanged(self):
        result = self.analyze(START + PASS + SUMMARY)
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["interruptedCaseEventsNormalized"], 0)

    def testInterruptedFailuresAndSkipsRemainFailures(self):
        for outcome in ("failed (0.002 seconds).", "skipped.", "cancelled.", "canceled."):
            with self.subTest(outcome=outcome):
                result = self.analyze(START + self.interrupted(outcome) + SUMMARY)
                self.assertFalse(result["passed"], result)
                self.assertEqual(result["interruptedCaseEventsNormalized"], 1)

    def testErrorInThePreservedNSLogStillBlocksSuccess(self):
        message = NSLOG + " Fixture.swift:12: error: -[OMapsTests.CarPlayServiceTests testPanDirectionOffset] assertion failed"
        result = self.analyze(START + self.interrupted(message=message) + SUMMARY)
        self.assertFalse(result["passed"], result)
        self.assertTrue(any("Fixture.swift:12: error:" in line for line in result["testFailures"]))

    def testDuplicatePassIsNotHiddenByNormalization(self):
        result = self.analyze(START + self.interrupted() + PASS + SUMMARY)
        self.assertFalse(result["passed"], result)
        self.assertIn("CarPlayServiceTests.testPanDirectionOffset", result["incompleteOrRepeatedCases"])

    def testDuplicateStartRemainsAFailure(self):
        result = self.analyze(START + START + self.interrupted() + SUMMARY)
        self.assertFalse(result["passed"], result)

    def testMissingStartRemainsAFailure(self):
        result = self.analyze(self.interrupted() + SUMMARY)
        self.assertFalse(result["passed"], result)

    def testMissingTerminalOutcomeRemainsAFailure(self):
        result = self.analyze(START + f"Test Case '{IDENTITY}'{NSLOG}\n" + SUMMARY)
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["interruptedCaseEventsNormalized"], 0)

    def testWrongMethodCannotSatisfyTheRequiredCase(self):
        text = (START + self.interrupted() + SUMMARY).replace("testPanDirectionOffset", "testUnexpected")
        result = self.analyze(text)
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["missingCases"], ["CarPlayServiceTests.testPanDirectionOffset"])
        self.assertEqual(result["unexpectedCases"], ["CarPlayServiceTests.testUnexpected"])

    def testUnexpectedClassRemainsAFailure(self):
        text = (START + self.interrupted() + SUMMARY).replace("CarPlayServiceTests", "OtherTests")
        result = self.analyze(text)
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["unexpectedClasses"], ["OtherTests"])

    def testArbitraryInterruptionDoesNotCreateAnOutcome(self):
        result = self.analyze(START + self.interrupted(message="unrecognized output") + SUMMARY)
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["interruptedCaseEventsNormalized"], 0)

    def testNormalizationDoesNotCrossAnotherTestEvent(self):
        other = "Test Case '-[OMapsTests.CarPlayServiceTests testOther]' passed (0.001 seconds).\n"
        text = START + f"Test Case '{IDENTITY}'{NSLOG}\n" + other + " passed (0.002 seconds).\n" + SUMMARY
        result = self.analyze(text)
        self.assertFalse(result["passed"], result)
        self.assertEqual(result["interruptedCaseEventsNormalized"], 0)

    def testFailureSummaryRemainsAFailure(self):
        result = self.analyze(START + self.interrupted() + SUMMARY.replace("0 failures", "1 failure"))
        self.assertFalse(result["passed"], result)

    def testBuildSuccessAloneCannotPass(self):
        result = self.analyze("** TEST BUILD SUCCEEDED **\n")
        self.assertFalse(result["passed"], result)


if __name__ == "__main__":
    unittest.main()
