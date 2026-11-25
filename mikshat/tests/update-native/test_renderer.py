import importlib.util
from pathlib import Path
import re
import unittest


SPEC = importlib.util.spec_from_file_location("rotation_renderer", Path(__file__).with_name("renderer.py"))
RENDERER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RENDERER)


class RendererPlanTests(unittest.TestCase):
    def test_only_native_target_switches_from_hosted_to_renderer_mode(self):
        original = {"TestConfigurations": [{"TestTargets": [
            {"BlueprintName": "OMapsTests", "CommandLineArguments": ["-IsTests", "-OtherFlag", "-AppleLanguages", "(en)"]},
            {"BlueprintName": "UnrelatedUITests", "CommandLineArguments": ["-IsTests"]},
        ]}]}
        plan, targets = RENDERER.patch_plan(original)
        args = targets[0]
        self.assertNotIn("-IsTests", args)
        self.assertIn("-MikshatRequireRenderer", args)
        self.assertIn("-OtherFlag", args)
        self.assertEqual(args[args.index("-AppleLanguages") + 1], "(ar)")
        self.assertEqual(plan["TestConfigurations"][0]["TestTargets"][1]["CommandLineArguments"], ["-IsTests"])
        self.assertIn("-IsTests", original["TestConfigurations"][0]["TestTargets"][0]["CommandLineArguments"])

    def test_missing_native_target_fails(self):
        with self.assertRaises(ValueError):
            RENDERER.patch_plan({"OtherTests": {"CommandLineArguments": []}})

    def test_malformed_paired_argument_fails(self):
        with self.assertRaises(ValueError):
            RENDERER.patch_plan({"BlueprintName": "OMapsTests", "CommandLineArguments": ["-AppleLanguages"]})


class RendererEvidenceTests(unittest.TestCase):
    def records(self):
        def record(event, **extra):
            return dict(event=event, timestamp=1, rendererReady=True, graphicsReady=True, active=True,
                        windowAttached=True, layer="CAMetalLayer", direction="RTL", language="ar", **extra)
        result = [record("ready")]
        for cycle in range(3):
            for orientation in (3, 1, 4, 1):
                width, height = (852, 393) if orientation in (3, 4) else (393, 852)
                result.append(record("rotated", cycle=cycle, orientation=orientation, width=width, height=height))
        result.append(record("completed"))
        for index, entry in enumerate(result):
            entry["timestamp"] = index + 1
        return result

    def captures(self):
        return [dict(exitStatus=0, width=393, height=852, startedAt=5, completedAt=5.1)]

    def test_complete_renderer_evidence_passes(self):
        self.assertTrue(RENDERER.verify_records(self.records(), self.captures())["passed"])

    def test_missing_rotation_fails(self):
        self.assertFalse(RENDERER.verify_records(self.records()[:-2] + self.records()[-1:], self.captures())["passed"])

    def test_duplicate_run_or_restart_fails(self):
        self.assertFalse(RENDERER.verify_records(self.records() * 2, self.captures())["passed"])

    def test_hosted_or_nonmetal_state_fails(self):
        records = self.records()
        records[5]["rendererReady"] = False
        self.assertFalse(RENDERER.verify_records(records, self.captures())["passed"])

    def test_wrong_actual_window_orientation_fails(self):
        records = self.records()
        records[1]["width"], records[1]["height"] = 393, 852
        self.assertFalse(RENDERER.verify_records(records, self.captures())["passed"])

    def test_screenshot_before_ready_is_insufficient(self):
        captures = self.captures()
        captures[0]["startedAt"] = 0.5
        self.assertFalse(RENDERER.verify_records(self.records(), captures)["passed"])


class RendererNativeInventoryTests(unittest.TestCase):
    def log(self):
        events = []
        for name, methods in RENDERER.CASES.items():
            for method in methods:
                # ObjC++ XCTest classes have no Swift module prefix.
                prefix = "" if name == "MikshatVehicleRoutingEntryTests" else "OMapsTests."
                case = f"-[{prefix}{name} {method}]"
                events += [f"Test Case '{case}' started.", f"Test Case '{case}' passed (1.0 seconds)."]
        events += ["Executed 3 tests, with 0 failures in 24.0 seconds", "** TEST EXECUTE SUCCEEDED **"]
        return "\n".join(events) + "\n"

    def test_rotation_and_both_vehicle_entry_methods_must_execute(self):
        report = RENDERER.native_result(self.log())
        self.assertTrue(report["passed"])
        self.assertEqual(report["expectedTotal"], 3)

    def test_matching_class_count_cannot_substitute_a_vehicle_entry_method(self):
        method = RENDERER.CASES["MikshatVehicleRoutingEntryTests"][0]
        report = RENDERER.native_result(self.log().replace(method, "testUnrelatedVehicleRoute"))
        self.assertFalse(report["passed"])
        self.assertEqual(report["missingCases"], ["MikshatVehicleRoutingEntryTests." + method])
        self.assertEqual(report["unexpectedCases"], ["MikshatVehicleRoutingEntryTests.testUnrelatedVehicleRoute"])

    def test_skips_and_repeated_execution_cannot_pass(self):
        for log in (self.log().replace("passed (1.0 seconds).", "skipped (1.0 seconds).", 1), self.log() * 2):
            self.assertFalse(RENDERER.native_result(log)["passed"])

    def test_workflow_selects_the_exact_renderer_inventory(self):
        workflow = (RENDERER.ROOT / ".github/workflows/mikshat-responsive-ui.yml").read_text()
        step = workflow.split("id: rotation-renderer-tests", 1)[1].split("\n    - name:", 1)[0]
        selected = re.findall(r"-only-testing:OMapsTests/([^/\s]+)/([^\s]+)", step)
        expected = [(name, method) for name, methods in RENDERER.CASES.items() for method in methods]
        self.assertCountEqual(selected, expected)
        routing = (RENDERER.ROOT / "iphone/Maps/Tests/Core/Routing/MikshatRoutingEntryTests.mm").read_text()
        for method in RENDERER.CASES["MikshatVehicleRoutingEntryTests"]:
            self.assertIn("- (void)" + method, routing)


if __name__ == "__main__":
    unittest.main()
