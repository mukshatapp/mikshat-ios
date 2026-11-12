#!/usr/bin/env python3
"""Validate native evidence; never turn a baseline setup failure into a repro."""
import json
import pathlib
import sys


def verify(directory):
    result = json.loads((directory / "probe-outcome.json").read_text())
    manifest = json.loads((directory / "generated/source-manifest.json").read_text())
    traces = [json.loads(line) for line in (directory / "geometry-trace.jsonl").read_text().splitlines()] if (directory / "geometry-trace.jsonl").exists() else []
    print(json.dumps(result, indent=2, sort_keys=True))
    assert result["variant"] == manifest["variant"], "Wrong variant report"
    ready = next((item for item in traces if item.get("event") == "ready"), None)
    assert ready, "No real phone scene readiness record; not a reproduction"
    assert ready.get("footprint_bytes", 0) > 0, "Native memory safeguard was unavailable"
    assert all(ready["metadata"][key] is True for key in ("application_active", "scene_foreground_active", "key_window")), "Inactive UIKit scene"
    assert ready["metadata"]["target_distance_metres"] > ready["metadata"]["horizontal_accuracy_metres"], "Fixture would hide the arrow as already arrived"
    outcome = result["outcome"]
    if result["variant"] == "baseline" and outcome == "reproduced":
        assert result.get("cases_started", 0) > 0 and result.get("stage") == "case-started", "Setup failure must never count as reproduction"
        assert result["reason"] in ("oversized-accessory-geometry", "case-footprint-guard", "case-layout-deadline"), "Unrelated baseline failure"
        assert any(item.get("event") == "case-started" for item in traces), "Missing durable pre-operation marker"
        if result["reason"] == "oversized-accessory-geometry":
            fields = ("outer_bounds", "outer_frame", "image_bounds", "image_frame")
            assert any(abs(value) > 84 for key in fields for value in result["last_geometry"].get(key, [])[2:]), "No oversized geometry evidence"
        print("BASELINE: native unsafe layout case stopped by guard; inspect trace for exact geometry/stage. This is not a full-app device reproduction.")
        return
    expected = "passed" if result["variant"] == "fixed" else "not-reproduced"
    assert outcome == expected, f"Unexpected result: {outcome} / {result.get('reason')}"
    assert result["cases_completed"] == result["expected_cases"] == 48, "Incomplete native case coverage"
    assert result["reuse_count"] > 0, "No real UITableView reuse occurred"
    completed = [item for item in traces if item.get("event") == "layout-7"]
    assert len(completed) == 48, "Missing post-layout evidence"
    assert {item["case"]["direction"] for item in completed} == {"LTR", "RTL"}, "Missing layout direction"
    for item in completed:
        state = item["geometry"]
        assert state["outer_alpha"] > 0.99 and not state["accessibility_hidden"], "Hidden arrows are invalid coverage"
        assert state["image_present"] and abs(state["image_angle_degrees"]) > 1, "No actual nonzero symbol rotation"
        if result["variant"] == "fixed":
            assert state["outer_identity"] and not state["image_is_outer"], "Rotated outer accessory"
            for key in ("outer_bounds", "outer_frame", "image_bounds"):
                assert all(abs(value - 28) < .01 for value in state[key][2:]), f"Unsafe {key}"
    print("FIXED: actual UIKit symbol geometry and reuse invariants passed." if result["variant"] == "fixed" else "BASELINE: no unsafe growth/stall reproduced. Do not claim the device watchdog is proven or resolved by this probe.")


if __name__ == "__main__":
    try:
        verify(pathlib.Path(sys.argv[1]))
    except (AssertionError, KeyError, OSError, ValueError) as error:
        print(f"PROBE VALIDATION FAILED: {error}", file=sys.stderr)
        sys.exit(1)
