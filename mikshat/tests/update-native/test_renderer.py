import importlib.util
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
