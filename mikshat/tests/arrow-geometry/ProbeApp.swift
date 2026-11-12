import UIKit
import CoreLocation
import Darwin

// These are the only production dependencies replaced by the fixture. Geometry,
// SF Symbol creation, target validation, bearing and rotation use extracted code.
enum MikshatStyle { static let green = UIColor(red: 0.07, green: 0.30, blue: 0.24, alpha: 1) }
func L(_ key: String) -> String { key }
enum MikshatHeading {
  static let fixtureLocation = CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753),
    altitude: 0, horizontalAccuracy: 2, verticalAccuracy: 2, timestamp: Date())
  // Activate this only after the durable case-started marker. Setup never
  // starts unsafe baseline symbol geometry before the safety monitor is ready.
  static var currentLocation: CLLocation?
  static var heading = 0.0
  static func reading() -> (degrees: Double?, gps: Bool) { (heading, false) }
}

private func footprint() -> UInt64 {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let status = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return status == KERN_SUCCESS ? info.phys_footprint : 0
}

private func rectangle(_ value: CGRect) -> [Double] {
  [Double(value.origin.x), Double(value.origin.y), Double(value.width), Double(value.height)]
}
private func matrix(_ value: CGAffineTransform) -> [Double] {
  [Double(value.a), Double(value.b), Double(value.c), Double(value.d), Double(value.tx), Double(value.ty)]
}
private func imageView(in indicator: MikshatDirectionIndicator) -> UIImageView? {
  if let image = indicator as? UIImageView { return image }
  return indicator.subviews.compactMap { $0 as? UIImageView }.first
}
private func geometry(_ indicator: MikshatDirectionIndicator) -> [String: Any] {
  var value: [String: Any] = [
    "outer_class": NSStringFromClass(type(of: indicator)),
    "outer_bounds": rectangle(indicator.bounds), "outer_frame": rectangle(indicator.frame),
    "outer_transform": matrix(indicator.transform), "outer_identity": indicator.transform.isIdentity,
    "outer_alpha": Double(indicator.alpha), "window_attached": indicator.window != nil,
    "accessibility_element": indicator.isAccessibilityElement,
    "accessibility_hidden": indicator.accessibilityElementsHidden,
    "accessibility_label": indicator.accessibilityLabel ?? "",
    "accessibility_value": indicator.accessibilityValue ?? "",
    "footprint_bytes": footprint(),
  ]
  if let target = indicator.target { value["target"] = [target.latitude, target.longitude] }
  if let image = imageView(in: indicator) {
    value["image_bounds"] = rectangle(image.bounds)
    value["image_frame"] = rectangle(image.frame)
    value["image_transform"] = matrix(image.transform)
    value["image_angle_degrees"] = atan2(Double(image.transform.b), Double(image.transform.a)) * 180 / .pi
    value["image_present"] = image.image != nil
    value["image_is_outer"] = image === indicator
  }
  return value
}

// The monitor never touches UIKit off the main thread. It reads only locked
// stage metadata and the process footprint. A killed/failed setup is not a repro.
private final class Recorder {
  static let shared = Recorder()
  private let lock = NSLock()
  private var stage = "setup"
  private var stageStart = ProcessInfo.processInfo.systemUptime
  private let appStart = ProcessInfo.processInfo.systemUptime
  private var baselineFootprint: UInt64 = 0
  private var lastGeometry: [String: Any] = [:]
  private var caseMetadata: [String: Any] = [:]
  private var casesStarted = 0
  private var casesCompleted = 0
  private var reuseCount = 0
  private var done = false
  private var timer: DispatchSourceTimer?
  private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  private var trace: FileHandle?

  func start() {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("geometry-trace.jsonl")
    FileManager.default.createFile(atPath: path.path, contents: nil)
    trace = try? FileHandle(forWritingTo: path)
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
    timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
    timer.setEventHandler { [weak self] in self?.watchdog() }
    self.timer = timer
    timer.resume()
  }

  func ready(_ metadata: [String: Any]) -> Bool {
    lock.lock(); defer { lock.unlock() }
    baselineFootprint = footprint()
    guard baselineFootprint > 0 else {
      finishLocked("setup-failed", reason: "process-footprint-monitor-unavailable")
      return false
    }
    stage = "ready"
    stageStart = ProcessInfo.processInfo.systemUptime
    appendLocked(["event": "ready", "metadata": metadata, "footprint_bytes": baselineFootprint])
    return true
  }

  func begin(_ metadata: [String: Any]) {
    lock.lock(); defer { lock.unlock() }
    guard !done else { return }
    stage = "case-started"
    stageStart = ProcessInfo.processInfo.systemUptime
    casesStarted += 1
    caseMetadata = metadata
    appendLocked(["event": "case-started", "case": metadata, "previous_geometry": lastGeometry])
  }

  func sample(_ value: [String: Any], event: String) {
    lock.lock(); defer { lock.unlock() }
    guard !done else { return }
    lastGeometry = value
    appendLocked(["event": event, "case": caseMetadata, "geometry": value])
  }

  func completeCase(reuses: Int) {
    lock.lock(); defer { lock.unlock() }
    casesCompleted += 1
    reuseCount = reuses
    stage = "between-cases"
    stageStart = ProcessInfo.processInfo.systemUptime
  }

  func finish(_ outcome: String, reason: String) {
    lock.lock(); defer { lock.unlock() }
    finishLocked(outcome, reason: reason)
  }

  private func appendLocked(_ record: [String: Any]) {
    var record = record
    record["elapsed_seconds"] = ProcessInfo.processInfo.systemUptime - appStart
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
      trace?.write(data)
      trace?.write(Data([10]))
      try? trace?.synchronize()
    }
  }

  private func finishLocked(_ outcome: String, reason: String) {
    guard !done else { return }
    done = true
    let record: [String: Any] = [
      "schema": 1, "variant": probeVariant, "outcome": outcome, "reason": reason,
      "stage": stage, "case": caseMetadata, "cases_started": casesStarted,
      "cases_completed": casesCompleted, "expected_cases": ProbeController.caseCount,
      "reuse_count": reuseCount, "last_geometry": lastGeometry,
      "elapsed_seconds": ProcessInfo.processInfo.systemUptime - appStart,
      "baseline_footprint_bytes": baselineFootprint, "final_footprint_bytes": footprint(),
      "limitations": "Standalone UIKit, actual indicator and math; deterministic injected location/heading. No physical GPS, active map, or full-app end-to-end claim.",
    ]
    appendLocked(["event": "finished", "result": record])
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: directory.appendingPathComponent("probe-outcome.json"), options: .atomic)
    }
    timer?.cancel()
  }

  private func watchdog() {
    lock.lock(); defer { lock.unlock() }
    guard !done else { return }
    let elapsed = ProcessInfo.processInfo.systemUptime - stageStart
    let resident = footprint()
    let memoryExceeded = baselineFootprint > 0 && resident > baselineFootprint + 160 * 1024 * 1024
    let absoluteExceeded = resident > 512 * 1024 * 1024
    if stage == "case-started", casesStarted > 0, elapsed > 3 || memoryExceeded || absoluteExceeded {
      // The durable pre-operation case record distinguishes a source-layout
      // stall from app launch/scene readiness failure. Do not continue rasterizing.
      let reason = (memoryExceeded || absoluteExceeded) ? "case-footprint-guard" : "case-layout-deadline"
      finishLocked(probeVariant == "baseline" ? "reproduced" : "failed", reason: reason)
      _exit(40)
    }
    if memoryExceeded || absoluteExceeded {
      finishLocked("setup-failed", reason: "footprint-guard-outside-layout-case")
      _exit(41)
    }
    if ProcessInfo.processInfo.systemUptime - appStart > 35 {
      finishLocked("setup-failed", reason: "scene-or-probe-global-deadline")
      _exit(41)
    }
  }
}

private final class ProbeCell: UITableViewCell {
  let indicator = MikshatDirectionIndicator()
  static var reuseCount = 0

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: .default, reuseIdentifier: reuseIdentifier)
  }
  required init?(coder: NSCoder) { fatalError("unused") }

  func configure(_ row: Int, target: CLLocationCoordinate2D) {
    // Same accessory assignment order as production SearchHistoryCell. The
    // extracted arrow, including all transform changes, remains untouched.
    indicator.target = nil
    accessoryView = nil
    indicator.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
    indicator.target = target
    accessoryView = indicator
    textLabel?.text = "History \(row) — سجل البحث"
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    Self.reuseCount += 1
    // No test-only transform/bounds repair here: production behavior must
    // determine whether a reused, previously rotated accessory remains safe.
  }
}

private final class ProbeController: UIViewController, UITableViewDataSource {
  static let caseCount = 48
  private let table = UITableView(frame: .zero, style: .plain)
  private let status = UILabel()
  private var caseIndex = 0
  private var started = false
  private let angles: [Double] = [15, 30, 45, 60, 90, 120, 135, 150]
  private let target = CLLocationCoordinate2D(latitude: 24.7156, longitude: 46.6773)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.text = "\(probeVariant): waiting for active phone scene"
    status.numberOfLines = 0
    table.dataSource = self
    table.register(ProbeCell.self, forCellReuseIdentifier: "history")
    table.rowHeight = 64
    view.addSubview(table)
    view.addSubview(status)
    table.translatesAutoresizingMaskIntoConstraints = false
    status.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      status.heightAnchor.constraint(equalToConstant: 90),
      table.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      table.heightAnchor.constraint(equalToConstant: 320),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    awaitActiveScene()
  }

  private func awaitActiveScene() {
    guard !started else { return }
    guard UIApplication.shared.applicationState == .active,
          view.window?.isKeyWindow == true,
          view.window?.windowScene?.activationState == .foregroundActive else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.awaitActiveScene() }
      return
    }
    started = true
    view.layoutIfNeeded()
    guard Recorder.shared.ready([
      "application_active": true, "scene_foreground_active": true, "key_window": true,
      "screen_bounds": rectangle(view.window!.bounds), "screen_scale": UIScreen.main.scale,
      "os": UIDevice.current.systemVersion, "device": UIDevice.current.model,
      "target_distance_metres": MikshatHeading.fixtureLocation.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)),
      "horizontal_accuracy_metres": MikshatHeading.fixtureLocation.horizontalAccuracy,
    ]) else { return }
    if let cell = table.visibleCells.first as? ProbeCell {
      Recorder.shared.sample(geometry(cell.indicator), event: "ready-hidden-arrow-before-injected-fix")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.runCase() }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 40 }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath) as! ProbeCell
    cell.configure(indexPath.row, target: target)
    return cell
  }

  private func runCase() {
    guard caseIndex < Self.caseCount else {
      guard ProbeCell.reuseCount > 0 else {
        Recorder.shared.finish("setup-failed", reason: "UITableView-did-not-reuse-cells")
        return
      }
      status.text = "\(probeVariant): \(Self.caseCount) active UIKit cases complete; \(ProbeCell.reuseCount) real cell reuses"
      Recorder.shared.finish(probeVariant == "baseline" ? "not-reproduced" : "passed", reason: "all-layout-and-reuse-cases-completed")
      return
    }
    let angle = angles[caseIndex % angles.count]
    let rtl = caseIndex >= Self.caseCount / 2
    let bearing = MikshatNavigationMath.bearing(latitude: MikshatHeading.fixtureLocation.coordinate.latitude,
      longitude: MikshatHeading.fixtureLocation.coordinate.longitude,
      targetLatitude: target.latitude, targetLongitude: target.longitude)
    MikshatHeading.heading = MikshatNavigationMath.normalize(bearing - angle)
    Recorder.shared.begin(["index": caseIndex, "expected_angle_degrees": angle,
      "bearing_degrees": bearing, "heading_degrees": MikshatHeading.heading, "direction": rtl ? "RTL" : "LTR"])
    MikshatHeading.currentLocation = MikshatHeading.fixtureLocation
    table.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
    let row = caseIndex % (Self.caseCount / 2)
    table.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
    table.setNeedsLayout()
    table.layoutIfNeeded()
    guard let cell = table.cellForRow(at: IndexPath(row: row, section: 0)) as? ProbeCell else {
      Recorder.shared.finish("setup-failed", reason: "expected-visible-cell-missing")
      return
    }
    Recorder.shared.sample(geometry(cell.indicator), event: "before-reconfigure")
    cell.configure(row, target: target)
    Recorder.shared.sample(geometry(cell.indicator), event: "after-reconfigure")
    for pass in 0..<8 {
      cell.setNeedsLayout()
      cell.layoutIfNeeded()
      let snapshot = geometry(cell.indicator)
      Recorder.shared.sample(snapshot, event: "layout-\(pass)")
      if geometryOversized(cell.indicator) {
        status.text = "\(probeVariant): oversized geometry stopped before further raster work"
        Recorder.shared.finish(probeVariant == "baseline" ? "reproduced" : "failed", reason: "oversized-accessory-geometry")
        return
      }
      if let failure = invariantFailure(cell.indicator, angle: angle, bearing: bearing) {
        Recorder.shared.finish("failed", reason: failure)
        return
      }
    }
    status.text = "\(probeVariant): \(caseIndex + 1)/\(Self.caseCount), \(rtl ? "RTL" : "LTR"), \(Int(angle))°"
    Recorder.shared.completeCase(reuses: ProbeCell.reuseCount)
    caseIndex += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.runCase() }
  }

  private func geometryOversized(_ indicator: MikshatDirectionIndicator) -> Bool {
    var views: [UIView] = [indicator]
    if let image = imageView(in: indicator) { views.append(image) }
    return views.contains { element in
      [element.bounds.width, element.bounds.height, element.frame.width, element.frame.height].contains {
        !$0.isFinite || $0 < 0 || $0 > 84
      }
    }
  }

  private func invariantFailure(_ indicator: MikshatDirectionIndicator, angle: Double, bearing: Double) -> String? {
    guard indicator.window != nil, indicator.alpha > 0.99, !indicator.accessibilityElementsHidden else { return "arrow-not-visible-under-valid-heading-and-location" }
    guard indicator.isAccessibilityElement, indicator.accessibilityLabel == "mikshat_arrow_to_point",
          indicator.accessibilityValue == String(format: "%.0f°", bearing) else { return "accessibility-label-or-bearing-value-lost" }
    guard let savedTarget = indicator.target, savedTarget.latitude == target.latitude, savedTarget.longitude == target.longitude else { return "target-changed" }
    guard let image = imageView(in: indicator), image.image != nil else { return "actual-symbol-image-missing" }
    let rendered = MikshatNavigationMath.normalize(atan2(Double(image.transform.b), Double(image.transform.a)) * 180 / .pi)
    guard abs(rendered - angle) < 0.001 else { return "nonzero-production-rotation-not-exercised" }
    if probeVariant == "fixed" {
      guard !(indicator is UIImageView), indicator.transform.isIdentity else { return "outer-container-rotated" }
      guard abs(indicator.bounds.width - 28) < 0.01, abs(indicator.bounds.height - 28) < 0.01,
            abs(indicator.frame.width - 28) < 0.01, abs(indicator.frame.height - 28) < 0.01 else { return "outer-container-not-28-points" }
      guard abs(image.bounds.width - 28) < 0.01, abs(image.bounds.height - 28) < 0.01 else { return "symbol-bounds-not-28-points" }
    }
    return nil
  }
}

@main
final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Recorder.shared.start()
    return true
  }
  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Arrow Probe", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = ProbeSceneDelegate.self
    return configuration
  }
}

final class ProbeSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = ProbeController()
    self.window = window
    window.makeKeyAndVisible()
  }
}
