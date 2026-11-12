"""Build a small UIKit app using the repository's actual window-hook methods.

Only theme rendering and the Maps app delegate are stubbed. UIKit, Swift/ObjC
method dispatch, the extracted hook bodies and SwizzleStyle.m are real.
"""
from pathlib import Path
import argparse
import json
import re
import shutil

FILES = {
    'UIView': 'iphone/Maps/Extensions/Views/UIView+SetStyle.swift',
    'UITextField': 'iphone/Maps/Core/Theme/Renderers/UITextFieldRenderer.swift',
    'UISearchBar': 'iphone/Maps/Core/Theme/Renderers/UISearchBarRenderer.swift',
}


def extract_hook(source):
    pattern = re.compile(r'(?m)^  (?:(?:@objc|override|dynamic)\s+)*func (sw_\w+)\(\)\s*\{')
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise ValueError(f'Expected one window hook, found {len(matches)}')
    match = matches[0]
    depth = 1
    position = match.end()
    # These short production methods contain no multiline strings or comments.
    while depth:
        if position >= len(source):
            raise ValueError('Unclosed window hook')
        if source.startswith('//', position):
            position = source.find('\n', position)
            if position < 0:
                raise ValueError('Unclosed window hook comment')
            continue
        character = source[position]
        if character == '"':
            position += 1
            while position < len(source):
                if source[position] == '\\':
                    position += 2
                elif source[position] == '"':
                    break
                else:
                    position += 1
        elif character == '{':
            depth += 1
        elif character == '}':
            depth -= 1
        position += 1
    return match.group(1), source[match.start():position]


SWIFT_PREFIX = r'''import UIKit
import Foundation
import ObjectiveC

private var styleAppliedKey: UInt8 = 0
private var themeApplications = 0

@objc extension UIView {
  func applyTheme() { themeApplications += 1 }
  var isStyleApplied: Bool {
    get { (objc_getAssociatedObject(self, &styleAppliedKey) as? NSNumber)?.boolValue ?? false }
    set { objc_setAssociatedObject(self, &styleAppliedKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }
}

'''

SWIFT_APP = r'''
@main
@objc(MapsAppDelegate)
final class MapsAppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var cycle = 0
  private let started = ProcessInfo.processInfo.systemUptime
  private var retainedHost: UIView?
  static func theApp() -> MapsAppDelegate { UIApplication.shared.delegate as! MapsAppDelegate }

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    print("MIKSHAT_PROBE begin label=__LABEL__ iOS=\(UIDevice.current.systemVersion)")
    fflush(stdout)
    SwizzleStyle.swizzle()
    let window = UIWindow(frame: UIScreen.main.bounds)
    self.window = window
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.nextCycle() }
    return true
  }

  private func nextCycle() {
    if cycle == 20 {
      // The baseline did not promise idempotence. Exercise one extra install only
      // for the fixed source; the full-app XCTest separately covers this contract.
      if __REINSTALL__ { SwizzleStyle.swizzle() }
      if __REINSTALL__ {
        let field = UITextField(frame: CGRect(x: 16, y: 100, width: 200, height: 44))
        window!.addSubview(field)
        guard field.isStyleApplied else { finish("failed", detail: "Reinstall disabled theming"); return }
        field.removeFromSuperview()
      }
      finish("passed", detail: "20 real UIKit attach/focus/detach cycles completed")
      return
    }
    cycle += 1
    print("MIKSHAT_PROBE cycle=\(cycle) phase=construct")
    fflush(stdout)
    let host = UIView(frame: window!.bounds)
    let field = UITextField(frame: CGRect(x: 16, y: 100, width: 200, height: 44))
    let bar = UISearchBar(frame: CGRect(x: 16, y: 160, width: 300, height: 56))
    field.text = "coordinate"
    bar.placeholder = "search"
    host.addSubview(field)
    host.addSubview(bar)
    print("MIKSHAT_PROBE cycle=\(cycle) phase=attach")
    fflush(stdout)
    window!.addSubview(host)
    retainedHost = host
    host.layoutIfNeeded()
    guard field.window === window, bar.window === window,
          field.isStyleApplied, bar.isStyleApplied else {
      finish("failed", detail: "Attached controls did not receive their theme hooks")
      return
    }
    print("MIKSHAT_PROBE cycle=\(cycle) phase=focus")
    fflush(stdout)
    _ = bar.searchTextField.becomeFirstResponder()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      host.endEditing(true)
      print("MIKSHAT_PROBE cycle=\(self.cycle) phase=detach")
      fflush(stdout)
      host.removeFromSuperview()
      self.retainedHost = nil
      guard field.window == nil, bar.window == nil else {
        self.finish("failed", detail: "Controls retained a window after removal")
        return
      }
      DispatchQueue.main.async { self.nextCycle() }
    }
  }

  private func finish(_ result: String, detail: String) {
    let payload: [String: Any] = [
      "result": result, "label": "__LABEL__", "iOS": UIDevice.current.systemVersion,
      "cycles": cycle, "themeApplications": themeApplications,
      "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
      "detail": detail,
      "scope": "Actual theme hook bodies and swizzler with UIKit; theme rendering and app delegate are stubs"
    ]
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
      try? data.write(to: directory.appendingPathComponent("probe-result.json"))
    }
    print("MIKSHAT_PROBE \(result.uppercased()): \(detail)")
    fflush(stdout)
    exit(result == "passed" ? EXIT_SUCCESS : EXIT_FAILURE)
  }
}
'''


def prepare(source_root, output, label):
    output.mkdir(parents=True, exist_ok=True)
    methods = []
    selectors = {}
    for class_name, relative in FILES.items():
        name, method = extract_hook((source_root / relative).read_text())
        selectors[class_name] = name
        declaration = '@objc extension UIView' if class_name == 'UIView' else f'extension {class_name}'
        methods.append(f'{declaration} {{\n{method}\n}}\n')
    fixed = len(set(selectors.values())) == 3
    swift = SWIFT_PREFIX + '\n'.join(methods) + SWIFT_APP.replace('__LABEL__', label).replace('__REINSTALL__', str(fixed).lower())
    (output / 'Probe.swift').write_text(swift)
    directory = source_root / 'iphone/Maps/Core/Theme/Swizzle'
    for name in ['SwizzleStyle.m', 'SwizzleStyle.h']:
        shutil.copyfile(directory / name, output / name)
    if (directory / 'SwizzleRuntime.h').exists():
        shutil.copyfile(directory / 'SwizzleRuntime.h', output / 'SwizzleRuntime.h')
    (output / 'Bridge.h').write_text('#import "SwizzleStyle.h"\n')
    manifest = {'source_root': str(source_root), 'label': label, 'selectors': selectors, 'distinct_aliases': fixed}
    (output / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', default='probe')
    arguments = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', arguments.label):
        parser.error('label must contain only letters, digits, underscores and hyphens')
    print(json.dumps(prepare(arguments.source_root.resolve(), arguments.output.resolve(), arguments.label)))
