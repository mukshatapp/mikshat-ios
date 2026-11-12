#if DEBUG && targetEnvironment(simulator)
import UIKit
import QuartzCore
import Metal
import CoreLocation
import Darwin

// Diagnostic branch only. A normal foreground app is launched by simctl;
// neither XCTest hosting nor -IsTests is used. No fixture preferences, windows,
// controllers, location fixes or rendering contexts are manufactured here.
@MainActor
@objc(MikshatLiveSearchProbe)
final class MikshatLiveSearchProbe: NSObject {
  private static var session: LiveSearchSession?

  @objc static func installIfRequested() {
    guard ProcessInfo.processInfo.arguments.contains("-MikshatLiveSearchProbe"), session == nil else { return }
    let arguments = ProcessInfo.processInfo.arguments
    let repeats: Int
    if let index = arguments.firstIndex(of: "-MikshatLiveSearchRepeats"), index + 1 < arguments.count {
      repeats = Int(arguments[index + 1]) ?? 0
    } else { repeats = 1 }
    let value = LiveSearchSession(repeats: repeats)
    session = value
    value.start()
  }
}

@MainActor
private final class LiveSearchSession {
  private enum Stage: String {
    case readiness, waitingForSearch, openSettling, waitingForClose, closedSettling
  }
  private static let requiredReadiness = [
    "normalApp", "active", "windowAttached", "windowKey", "windowVisible", "sceneActive",
    "metal", "drapeReady", "graphicsReady", "rtl", "arabic", "satelliteDisabled",
    "saudiNorthRegistered", "saudiSouthRegistered", "freshSyntheticLocation", "noPresentedController"
  ]
  private let repeats: Int
  private let journal: LiveSearchJournal
  private var stage = Stage.readiness
  private var deadline = ProcessInfo.processInfo.systemUptime + 40
  private var stageBegan = ProcessInfo.processInfo.systemUptime
  private var timer: Timer?
  private var watchdog: DispatchSourceTimer?
  private var observers: [NSObjectProtocol] = []
  private var keyboardShown = false
  private var lastReadiness: [String: Bool] = [:]
  private weak var lastSearch: SearchOnMapViewController?

  init(repeats: Int) {
    self.repeats = repeats
    journal = LiveSearchJournal(repeats: repeats, requiredReadiness: Self.requiredReadiness)
  }

  func start() {
    journal.record("installed", extra: ["argumentsIncludeIsTests": MapsAppDelegate.isTestsEnvironment(),
                                        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                                        "systemVersion": UIDevice.current.systemVersion])
    guard (1...5).contains(repeats), !MapsAppDelegate.isTestsEnvironment() else {
      journal.finish(status: "setup-failed", reason: "Expected normal app launch, no -IsTests, and repeats in 1...5")
      return
    }
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor [weak self] in self?.journal.record("application-did-become-active") }
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification,
                                                             object: nil, queue: .main) { [weak self] notification in
      let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
      Task { @MainActor [weak self] in
        guard let self else { return }
        let window = MapsAppDelegate.theApp().window
        self.keyboardShown = window.map { $0.bounds.intersects($0.convert(frame, from: nil)) && frame.height > 0 } ?? false
        self.journal.record("keyboard-did-show", extra: ["keyboardIntersectsWindow": self.keyboardShown,
                                                         "keyboardHeight": Double(frame.height)])
      }
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.keyboardShown = false
        self?.journal.record("keyboard-did-hide")
      }
    })
    let journal = journal
    let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    watchdog.schedule(deadline: .now() + 0.5, repeating: 0.5)
    watchdog.setEventHandler {
      journal.checkDeadlineAndHeartbeat()
    }
    self.watchdog = watchdog
    watchdog.resume()
    timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    tick()
  }

  private func tick() {
    journal.heartbeat()
    guard !journal.isFinished else { stop(); return }
    let now = ProcessInfo.processInfo.systemUptime
    let appWindow = MapsAppDelegate.theApp().window
    let map: MapViewController?
    if let root = appWindow?.rootViewController { map = findMap(in: root) } else { map = nil }
    let readiness = makeReadiness(map: map, window: appWindow)
    journal.updateReadiness(readiness)
    if readiness != lastReadiness {
      lastReadiness = readiness
      journal.record("readiness-changed", extra: ["readiness": readiness,
                                                  "applicationState": UIApplication.shared.applicationState.rawValue,
                                                  "windowHidden": appWindow?.isHidden ?? true,
                                                  "sceneState": appWindow?.windowScene?.activationState.rawValue ?? -1,
                                                  "downloadedCountries": Storage.shared().downloadedCountries(),
                                                  "presentedController": map?.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"])
    }
    if let map, map.isViewLoaded, let layer = map.mapView.layer as? CAMetalLayer, let device = layer.device {
      journal.updateMetalBytes(UInt64(device.currentAllocatedSize))
    }
    guard now <= deadline else {
      journal.finish(status: stage == .readiness ? "setup-failed" : "search-failed",
                     reason: "Timed out in \(stage.rawValue); individual readiness and phase fields identify missing coverage")
      stop()
      return
    }
    switch stage {
    case .readiness:
      guard Self.requiredReadiness.allSatisfy({ readiness[$0] == true }), let map, let window = appWindow else { return }
      journal.record("ready", extra: ["readiness": readiness,
                                      "historyQueries": MWMSearchFrameworkHelper.lastSearchQueries().count])
      openSearch(in: map, window: window)
    case .waitingForSearch:
      guard let map, let controller = map.searchManager.viewController, controller.parent === map,
            let root = controller.viewIfLoaded, root.window === appWindow,
            let field = searchField(in: root), field.isFirstResponder, keyboardShown else { return }
      lastSearch = controller
      journal.record("search-opened", extra: ["firstResponder": true, "keyboardShown": true,
                                               "controllerAttached": true, "readiness": readiness])
      setStage(.openSettling, timeout: 4)
    case .openSettling:
      guard now - stageBegan >= 1 else { return }
      guard let controller = lastSearch, let root = controller.viewIfLoaded, let window = appWindow,
            let button = visibleButtons(in: root, window: window).first(where: { $0.title(for: .normal) == L("cancel") }) else {
        journal.finish(status: "search-failed", reason: "Actual visible search Cancel button was not found")
        stop(); return
      }
      journal.record("cancel-before-action")
      journal.setStage("cancel-button-action")
      button.sendActions(for: .touchUpInside)
      journal.record("cancel-action-returned")
      setStage(.waitingForClose, timeout: 12)
    case .waitingForClose:
      let firstResponder = lastSearch?.viewIfLoaded.map { searchField(in: $0)?.isFirstResponder == true } ?? false
      guard let map, !map.searchManager.isSearching, lastSearch?.parent == nil, !firstResponder else { return }
      journal.completeIteration()
      journal.record("search-closed", extra: ["controllerDetached": true, "keyboardShown": keyboardShown])
      setStage(.closedSettling, timeout: 4)
    case .closedSettling:
      guard now - stageBegan >= 0.5 else { return }
      guard Self.requiredReadiness.allSatisfy({ readiness[$0] == true }) else {
        journal.finish(status: "search-failed", reason: "Renderer/window/location readiness was lost after closing search")
        stop(); return
      }
      if journal.iterationsCompleted == repeats {
        journal.finish(status: "passed", reason: "Normal foreground Metal app opened search through its actual button, displayed its keyboard and closed through Cancel")
        stop()
      } else if let map, let window = appWindow { openSearch(in: map, window: window) }
    }
  }

  private func openSearch(in map: MapViewController, window: UIWindow) {
    let buttons = visibleButtons(in: map.view, window: window).filter { $0.accessibilityLabel == L("search") }
    guard buttons.count == 1, !map.searchManager.isSearching else {
      journal.finish(status: "setup-failed", reason: "Expected one hittable Search button and a closed search; found \(buttons.count) buttons")
      stop(); return
    }
    keyboardShown = false
    journal.startIteration()
    journal.record("search-button-before-action", extra: ["visibleSearchButtons": buttons.count,
                                                         "buttonType": String(describing: type(of: buttons[0]))])
    journal.setStage("search-button-action")
    // The existing button's UIAction reaches the real presenter/interactor.
    buttons[0].sendActions(for: .touchUpInside)
    journal.record("search-button-action-returned")
    setStage(.waitingForSearch, timeout: 12)
  }

  private func makeReadiness(map: MapViewController?, window: UIWindow?) -> [String: Bool] {
    let root = map?.viewIfLoaded
    let registered = Set(Storage.shared().downloadedCountries())
    let fix = MikshatHeading.currentLocation
    let reference = CLLocation(latitude: 24.7136, longitude: 46.6753)
    let synthetic = fix.map { $0.distance(from: reference) <= 100 } ?? false
    return [
      "normalApp": !MapsAppDelegate.isTestsEnvironment(),
      "active": UIApplication.shared.applicationState == .active,
      "windowAttached": root?.window != nil && root?.window === window,
      "windowKey": window?.isKeyWindow == true,
      "windowVisible": window.map { !$0.isHidden && $0.alpha > 0 && !$0.bounds.isEmpty } ?? false,
      "sceneActive": window?.windowScene?.activationState == .foregroundActive,
      "metal": root != nil && map?.mapView.layer is CAMetalLayer,
      "drapeReady": root != nil && map?.mapView.drapeEngineCreated == true,
      "graphicsReady": root != nil && map?.mapView.graphicContextInitialized == true,
      "rtl": root?.effectiveUserInterfaceLayoutDirection == .rightToLeft,
      "arabic": Locale.preferredLanguages.first?.hasPrefix("ar") == true,
      "satelliteDisabled": !UserDefaults.standard.bool(forKey: "mikshat_satellite_enabled") && !Settings.backgroundTilesEnabled(),
      "saudiNorthRegistered": registered.contains("Saudi Arabia_North"),
      "saudiSouthRegistered": registered.contains("Saudi Arabia_South"),
      "freshSyntheticLocation": synthetic,
      "noPresentedController": map != nil && map?.presentedViewController == nil,
    ]
  }

  private func findMap(in controller: UIViewController) -> MapViewController? {
    if let map = controller as? MapViewController { return map }
    for child in controller.children { if let found = findMap(in: child) { return found } }
    return nil
  }

  private func searchField(in view: UIView) -> UITextField? {
    if let bar = view as? UISearchBar { return bar.searchTextField }
    for child in view.subviews { if let found = searchField(in: child) { return found } }
    return nil
  }

  private func visibleButtons(in view: UIView, window: UIWindow) -> [UIButton] {
    guard !view.isHidden, view.alpha > 0, view.window === window else { return [] }
    var result: [UIButton] = []
    if let button = view as? UIButton, button.isEnabled, !button.bounds.isEmpty {
      let rect = button.convert(button.bounds, to: window)
      let hit = window.hitTest(CGPoint(x: rect.midX, y: rect.midY), with: nil)
      if rect.intersects(window.bounds), hit === button || hit?.isDescendant(of: button) == true { result.append(button) }
    }
    for child in view.subviews { result += visibleButtons(in: child, window: window) }
    return result
  }

  private func setStage(_ value: Stage, timeout: TimeInterval) {
    stage = value
    stageBegan = ProcessInfo.processInfo.systemUptime
    deadline = stageBegan + timeout
    journal.setStage(value.rawValue)
  }

  private func stop() {
    timer?.invalidate(); timer = nil
    watchdog?.cancel(); watchdog = nil
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
  }
}

// The watchdog owns no UIKit objects and can persist evidence while the main
// thread is blocked. The host workflow may sample the still-running process.
private final class LiveSearchJournal: @unchecked Sendable {
  private let lock = NSLock()
  private let writes = DispatchQueue(label: "mikshat.live-search.journal")
  private let began = ProcessInfo.processInfo.systemUptime
  private let expected: Int
  private let requiredReadiness: [String]
  private var completed = 0
  private var started = 0
  private var finished = false
  private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
  private var heartbeatCount = 0
  private var stage = "readiness"
  private var readiness: [String: Bool] = [:]
  private var metalBytes: UInt64?
  private var peakFootprint: UInt64 = 0
  private var didReportStall = false
  private let directory: URL

  init(repeats: Int, requiredReadiness: [String]) {
    expected = repeats
    self.requiredReadiness = requiredReadiness
    directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
  var iterationsCompleted: Int { lock.lock(); defer { lock.unlock() }; return completed }
  func heartbeat() { lock.lock(); lastHeartbeat = ProcessInfo.processInfo.systemUptime; heartbeatCount += 1; lock.unlock() }
  func setStage(_ value: String) { lock.lock(); stage = value; lock.unlock() }
  func updateReadiness(_ value: [String: Bool]) { lock.lock(); readiness = value; lock.unlock() }
  func updateMetalBytes(_ value: UInt64) { lock.lock(); metalBytes = value; lock.unlock() }
  func startIteration() { lock.lock(); started += 1; lock.unlock() }
  func completeIteration() { lock.lock(); completed += 1; lock.unlock() }

  private func fields() -> [String: Any] {
    let memory = MikshatMemoryDiagnostics.Snapshot.capture()
    lock.lock(); defer { lock.unlock() }
    peakFootprint = max(peakFootprint, memory.physicalFootprintBytes ?? 0)
    var result: [String: Any] = ["schemaVersion": 1, "pid": getpid(), "stage": stage,
      "timestamp": Date().timeIntervalSince1970, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began,
      "iterationsExpected": expected, "iterationsStarted": started, "iterationsCompleted": completed,
      "readiness": readiness, "requiredReadinessKeys": requiredReadiness,
      "heartbeatCount": heartbeatCount, "heartbeatAgeSeconds": ProcessInfo.processInfo.systemUptime - lastHeartbeat,
      "peakPhysicalFootprintBytes": peakFootprint,
      "scope": "normal foreground Debug simulator; not physical-device Jetsam"]
    if let bytes = memory.physicalFootprintBytes { result["physicalFootprintBytes"] = bytes }
    if let bytes = memory.residentBytes { result["residentBytes"] = bytes }
    if let bytes = memory.availableBytes { result["availableBytes"] = bytes }
    if let error = memory.error { result["memorySampleError"] = error }
    if let bytes = metalBytes { result["metalCurrentAllocatedBytes"] = bytes }
    return result
  }

  func record(_ event: String, extra: [String: Any] = [:]) {
    var value = fields()
    value["event"] = event
    value.merge(extra) { _, new in new }
    write(value, summary: false)
  }

  func finish(status: String, reason: String) {
    lock.lock()
    guard !finished else { lock.unlock(); return }
    finished = true
    lock.unlock()
    record("finished", extra: ["status": status, "reason": reason])
    var value = fields()
    value["complete"] = true
    value["passed"] = status == "passed"
    value["status"] = status
    value["reason"] = reason
    write(value, summary: true)
    NSLog("MikshatLiveSearchProbe completed status=%@ pid=%d", status, getpid())
  }

  func checkDeadlineAndHeartbeat() {
    lock.lock()
    let done = finished
    let gap = ProcessInfo.processInfo.systemUptime - lastHeartbeat
    let report = gap > 3 && !didReportStall && !done
    if report { didReportStall = true }
    lock.unlock()
    guard !done else { return }
    if report { record("main-thread-heartbeat-delayed", extra: ["delaySeconds": gap]) }
    if gap > 10 {
      finish(status: "timed-out", reason: "Main-thread heartbeat stalled for more than 10 seconds; host should sample this live PID")
    } else if ProcessInfo.processInfo.systemUptime - began >= 90 {
      finish(status: "timed-out", reason: "The 90-second diagnostic deadline expired")
    }
  }

  private func write(_ value: [String: Any], summary: Bool) {
    writes.sync {
      do {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        data.append(0x0a)
        if summary {
          try data.write(to: directory.appendingPathComponent("mikshat-search-live-summary.json"), options: .atomic)
        } else {
          let url = directory.appendingPathComponent("mikshat-search-live-events.jsonl")
          if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
          let handle = try FileHandle(forWritingTo: url)
          defer { try? handle.close() }
          try handle.seekToEnd()
          try handle.write(contentsOf: data)
          try handle.synchronize()
        }
      } catch { NSLog("MikshatLiveSearchProbe evidence write failed: %@", String(describing: error)) }
    }
  }
}
#endif
