"""Compile actual TabView sources in a UIKit app; only visual/app dependencies are stubs."""
from pathlib import Path
import argparse
import hashlib
import json
import re

TAB = 'iphone/Maps/UI/ReusableComponents/TabView/TabView.swift'
CONTROLLER = 'iphone/Maps/UI/ReusableComponents/TabView/TabViewController.swift'

PREFIX = r'''import UIKit
import Foundation

extension UIFont {
  static var semibold14: UIFont { .systemFont(ofSize: 14, weight: .semibold) }
  var dynamic: UIFont { self }
}
extension UIColor {
  static var whitePrimary: UIColor { .white }
  func interpolated(to other: UIColor, progress: CGFloat) -> UIColor { progress >= 0.5 ? other : self }
}
extension UILabel {
  func configureSingleLineAutoScaling() {
    adjustsFontSizeToFitWidth = true
    minimumScaleFactor = 0.5
    numberOfLines = 1
  }
}
enum ProbeEdge { case bottom }
extension UIView {
  @discardableResult func addSeparator(_ edge: ProbeEdge) -> UIView {
    let separator = UIView()
    separator.backgroundColor = .lightGray
    separator.translatesAutoresizingMaskIntoConstraints = false
    addSubview(separator)
    NSLayoutConstraint.activate([
      separator.leftAnchor.constraint(equalTo: leftAnchor),
      separator.rightAnchor.constraint(equalTo: rightAnchor),
      separator.bottomAnchor.constraint(equalTo: bottomAnchor),
      separator.heightAnchor.constraint(equalToConstant: 0.5),
    ])
    return separator
  }
}
class MWMViewController: UIViewController {}

private var probeTraceCount = 0
private func probeTrace(_ stage: String, _ values: Any...) {
  guard probeTraceCount < 300 else { return }
  probeTraceCount += 1
  print("MIKSHAT_TAB_TRACE \(stage) \(values)")
  fflush(stdout)
}

'''

APP = r'''
@main
final class TabProbeDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var failures: [String] = []
  private var geometry: [[String: Any]] = []

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    self.window = window
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.exercise() }
    return true
  }

  private func check(_ value: Bool, _ message: String) {
    if !value { failures.append(message) }
  }

  private func sample(_ name: String, tabs: TabView, content: UICollectionView) {
    let ratio = content.bounds.width > 0 ? content.contentOffset.x / content.bounds.width : nil
    let detail: [String: Any] = [
      "case": name, "bounds": [content.bounds.width, content.bounds.height],
      "contentSize": [content.contentSize.width, content.contentSize.height],
      "offset": [content.contentOffset.x, content.contentOffset.y],
      "selectedIndex": tabs.selectedIndex ?? -1, "pagePosition": ratio ?? -1,
      "windowAttached": tabs.window != nil,
      "safeAreaInsets": [tabs.safeAreaInsets.top, tabs.safeAreaInsets.left,
                         tabs.safeAreaInsets.bottom, tabs.safeAreaInsets.right],
    ]
    geometry.append(detail)
    print("MIKSHAT_TAB_PROBE \(detail)")
    fflush(stdout)
  }

  private func runCase(_ name: String, sizes: [CGSize], hosted: Bool = false) {
    let controller = TabViewController()
    controller.loadViewIfNeeded()
    controller.viewControllers = [UIViewController(), UIViewController()]
    let tabs = controller.tabView
    tabs.selectedIndex = 1
    // Keep the original unhosted XCTest fixtures and separately exercise the same
    // production view while it is attached to a real, visible UIKit window.
    if hosted, let host = window?.rootViewController {
      host.addChild(controller)
      host.view.addSubview(tabs)
      controller.didMove(toParent: host)
      check(tabs.window != nil, "\(name): view is not attached to the visible window")
    }
    defer {
      if hosted {
        controller.willMove(toParent: nil)
        tabs.removeFromSuperview()
        controller.removeFromParent()
      }
    }
    guard let content = tabs.subviews.compactMap({ $0 as? UICollectionView }).first else {
      failures.append("Missing content collection")
      return
    }
    for size in sizes {
      tabs.frame = CGRect(origin: .zero, size: size)
      tabs.setNeedsLayout()
      tabs.layoutIfNeeded()
      tabs.layoutIfNeeded()
      let ratio = content.bounds.width > 0 ? content.contentOffset.x / content.bounds.width : nil
      let metrics = tabs.collectionView(content, layout: UICollectionViewFlowLayout(),
                                         sizeForItemAt: IndexPath(item: 1, section: 0))
      let detail: [String: Any] = [
        "case": name, "requested": [size.width, size.height],
        "bounds": [content.bounds.width, content.bounds.height],
        "contentSize": [content.contentSize.width, content.contentSize.height],
        "offset": [content.contentOffset.x, content.contentOffset.y],
        "selectedIndex": tabs.selectedIndex ?? -1,
        "pagePosition": ratio ?? -1,
        "itemSize": [metrics.width, metrics.height],
        "windowAttached": tabs.window != nil,
        "safeAreaInsets": [tabs.safeAreaInsets.top, tabs.safeAreaInsets.left,
                           tabs.safeAreaInsets.bottom, tabs.safeAreaInsets.right],
      ]
      geometry.append(detail)
      print("MIKSHAT_TAB_PROBE \(detail)")
      fflush(stdout)
      check(tabs.selectedIndex == 1, "\(name): selected tab changed at \(size)")
      check(content.contentOffset.x.isFinite && content.contentOffset.y.isFinite, "\(name): nonfinite offset")
      check(content.contentSize.width.isFinite && content.contentSize.height.isFinite, "\(name): nonfinite content size")
      check(metrics.width.isFinite && metrics.height.isFinite && metrics.width >= 0 && metrics.height >= 0,
            "\(name): invalid item size")
      if size != .zero {
        check(ratio != nil && abs(ratio! - 1) < 0.01, "\(name): selected page not aligned at \(size), position=\(String(describing: ratio))")
      }
    }
    // Stable layout passes should keep the selected page without geometry churn.
    for _ in 0..<10 { tabs.setNeedsLayout(); tabs.layoutIfNeeded() }
    check(tabs.selectedIndex == 1, "\(name): stable passes changed selected tab")
    sample("\(name)-after-stable", tabs: tabs, content: content)
  }

  private func runNextLoopCase(completion: @escaping () -> Void) {
    let controller = TabViewController()
    controller.loadViewIfNeeded()
    controller.viewControllers = [UIViewController(), UIViewController()]
    let tabs = controller.tabView
    tabs.selectedIndex = 1
    guard let host = window?.rootViewController,
          let content = tabs.subviews.compactMap({ $0 as? UICollectionView }).first else {
      failures.append("hosted-next-loop: missing host or collection")
      completion()
      return
    }
    host.addChild(controller)
    host.view.addSubview(tabs)
    controller.didMove(toParent: host)
    check(tabs.window != nil, "hosted-next-loop: view is not window-attached")
    for size in [CGSize(width: 320, height: 480), CGSize(width: 480, height: 320)] {
      tabs.frame = CGRect(origin: .zero, size: size)
      tabs.setNeedsLayout()
      tabs.layoutIfNeeded()
      tabs.layoutIfNeeded()
    }
    sample("hosted-next-loop-immediate", tabs: tabs, content: content)
    // Let a visible-window UIKit/CA layout transaction finish. No explicit layout,
    // invalidation, frame assignment, or forced stable passes occur in between.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.sample("hosted-next-loop-deferred", tabs: tabs, content: content)
      controller.willMove(toParent: nil)
      tabs.removeFromSuperview()
      controller.removeFromParent()
      completion()
    }
  }

  private func exercise() {
    print("MIKSHAT_TAB_PROBE begin label=__LABEL__ iOS=\(UIDevice.current.systemVersion)")
    fflush(stdout)
    runCase("existing-resize", sizes: [CGSize(width: 320, height: 480), CGSize(width: 480, height: 320)])
    runCase("nonempty-collapse", sizes: [CGSize(width: 320, height: 480), .zero, CGSize(width: 480, height: 320)])
    runCase("hosted-resize", sizes: [CGSize(width: 320, height: 480), CGSize(width: 480, height: 320)], hosted: true)
    runCase("hosted-collapse", sizes: [CGSize(width: 320, height: 480), .zero, CGSize(width: 480, height: 320)], hosted: true)
    runNextLoopCase { self.finish() }
  }

  private func finish() {
    let result = failures.isEmpty ? "passed" : "failed"
    let report: [String: Any] = [
      "result": result, "label": "__LABEL__", "iOS": UIDevice.current.systemVersion,
      "model": UIDevice.current.model, "failures": failures, "geometry": geometry,
      "scope": "Actual TabView and TabViewController; UIKit real; only visual helpers/base app controller stubbed; unhosted XCTest fixtures and visible-window child-controller fixtures"
    ]
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
      try? data.write(to: documents.appendingPathComponent("probe-result.json"))
    }
    print("MIKSHAT_TAB_PROBE \(result.uppercased()) failures=\(failures)")
    fflush(stdout)
    exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
  }
}
'''



def trace_variant(source):
    edits = [
        ('  override func layoutSubviews() {\n    super.layoutSubviews()\n    let width = pageCount',
         '''  override func layoutSubviews() {
    probeTrace("parent-entry", bounds.size, tabsContentCollectionView.bounds.size, lastContentSize)
    super.layoutSubviews()
    probeTrace("parent-after-super", bounds.size, tabsContentCollectionView.bounds.size, lastContentSize)
    let width = pageCount'''),
        ('    let contentSize = tabsContentCollectionView.bounds.size\n',
         '''    let contentSize = tabsContentCollectionView.bounds.size
    probeTrace("parent-compare", bounds.size, contentSize, lastContentSize)
    probeTrace("layout-identity", ObjectIdentifier(tabsContentLayout),
               ObjectIdentifier(tabsContentCollectionView.collectionViewLayout),
               String(describing: type(of: tabsContentCollectionView.collectionViewLayout)),
               tabsContentLayout.estimatedItemSize,
               (tabsContentCollectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.estimatedItemSize ?? .zero)
'''),
        ('    let size = CGSize(width: max(0, bounds.width), height: max(0, bounds.height))\n',
         '''    let size = CGSize(width: max(0, bounds.width), height: max(0, bounds.height))
    probeTrace("delegate-size", collectionView == tabsContentCollectionView ? "content" : "header",
               collectionView.bounds.size, lastContentSize, size)
'''),
    ]
    for before, after in edits:
        if source.count(before) != 1:
            raise ValueError('Expected exactly one trace insertion point: ' + before)
        source = source.replace(before, after, 1)
    return source, {'stages': ['parent-entry', 'parent-after-super', 'parent-compare', 'layout-identity', 'delegate-size'],
                    'limit': 300, 'layoutBehaviorChanged': False}



def prepare(root, output, label, variant, trace_layout=False):
    output.mkdir(parents=True, exist_ok=True)
    source = (root / TAB).read_text()
    original = source
    if variant != 'as-is':
        raise ValueError('The permanent probe compiles source as-is; experimental variants are unsupported')
    transform = None
    if trace_layout:
        source, trace = trace_variant(source)
        transform = {'trace': trace}
    controller = (root / CONTROLLER).read_text()
    (output / 'TabView.original.swift').write_text(original)
    (output / 'TabView.compiled.swift').write_text(source)
    (output / 'TabViewController.original.swift').write_text(controller)
    (output / 'Probe.swift').write_text(PREFIX + source + '\n' + controller + APP.replace('__LABEL__', label))
    digest = lambda value: hashlib.sha256(value.encode()).hexdigest()
    report = dict(label=label, variant=variant, traceLayout=trace_layout, sourceRoot=str(root),
                  tabSource=TAB, originalSHA256=digest(original), compiledSHA256=digest(source),
                  controllerSource=CONTROLLER, controllerSHA256=digest(controller), transform=transform)
    (output / 'source-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--variant', choices=['as-is'], default='as-is')
    parser.add_argument('--trace-layout', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch('[A-Za-z0-9-]+', args.label):
        parser.error('label must contain only letters, digits or hyphens')
    print(json.dumps(prepare(args.source_root.resolve(), args.output.resolve(), args.label, args.variant, args.trace_layout)))
