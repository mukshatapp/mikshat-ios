import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


prepare = module("prepare_probe")
verify = module("verify_outcome")


class ExtractionTests(unittest.TestCase):
    def test_nested_comments_strings_and_braces_preserve_original_bytes(self):
        body = '''final class MikshatDirectionIndicator: UIView {
  // } not an ending brace
  /* } /* nested { */ still } */
  let normal = "} \\" {"
  let raw = #"} not a brace {"#
  let multi = """\n} also not a brace\n"""
  func go() { if true { print("}") } }
}'''
        self.assertEqual(prepare.extract_class("// before\n" + body + "\nclass Next {}"), body)

    def test_missing_duplicate_or_unbalanced_declaration_rejected(self):
        for source in ("class Other {}", "final class MikshatDirectionIndicator: UIView {",
                       "final class MikshatDirectionIndicator: UIView {}\nfinal class MikshatDirectionIndicator: UIView {}"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                prepare.extract_class(source)

    def test_real_class_and_math_are_copied_verbatim(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            manifest = prepare.prepare(ROOT, out, "fixed")
            source = (ROOT / prepare.INTERFACE).read_text()
            extracted = prepare.extract_class(source)
            self.assertEqual((out / "ProductionIndicator.swift").read_text(), "import UIKit\nimport CoreLocation\n\n" + extracted + "\n")
            self.assertEqual((out / "MikshatNavigationMath.swift").read_bytes(), (ROOT / prepare.MATH).read_bytes())
            self.assertEqual(manifest["class_sha256"], prepare.digest(extracted.encode()))


class ClassificationTests(unittest.TestCase):
    def test_setup_failure_or_missing_ready_cannot_be_called_reproduced(self):
        for ready, started, stage in ((False, 1, "case-started"), (True, 0, "setup"), (True, 1, "setup")):
            with self.subTest(ready=ready, started=started, stage=stage), tempfile.TemporaryDirectory() as directory:
                out = pathlib.Path(directory)
                (out / "generated").mkdir()
                (out / "generated/source-manifest.json").write_text(json.dumps({"variant": "baseline"}))
                (out / "probe-outcome.json").write_text(json.dumps({"variant": "baseline", "outcome": "reproduced", "cases_started": started, "stage": stage}))
                trace = [{"event": "ready", "footprint_bytes": 64_000_000, "metadata": {"application_active": True, "scene_foreground_active": True, "key_window": True, "target_distance_metres": 200, "horizontal_accuracy_metres": 2}}] if ready else []
                (out / "geometry-trace.jsonl").write_text("\n".join(json.dumps(item) for item in trace))
                with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(AssertionError):
                    verify.verify(out)


if __name__ == "__main__":
    unittest.main()
