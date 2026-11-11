import Foundation
import Darwin
#if os(iOS)
import os
#endif

// Event-based, local diagnostics. Keep callers on opening/lifecycle boundaries;
// sampling from a timer, a result row or a location callback would add noise and work.
enum MikshatMemoryDiagnostics {
  enum SearchPhase: String {
    case deactivateSelection = "deactivate-selection"
    case constructScreen = "construct-screen"
    case screenConstructed = "screen-constructed"
    case observersRegistered = "observers-registered"
    case showScreen = "show-screen"
    case showReturned = "show-returned"
    case openReturned = "open-returned"
    case reuseScreen = "reuse-screen"
    case keyboardFocusBegin = "keyboard-focus-begin"
    case keyboardFocusReturned = "keyboard-focus-returned"
    case keyboardShown = "keyboard-shown"
    case closeRequested = "close-requested"
    // The state callback precedes dismissal animation/deallocation; it is not a release measurement.
    case closedState = "closed-state"
    case memoryWarning = "memory-warning"
  }

  struct Snapshot {
    let physicalFootprintBytes: UInt64?
    let residentBytes: UInt64?
    let availableBytes: UInt64?
    let error: kern_return_t?

    static func capture() -> Snapshot {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      // A successful call can return an older revision of this expanding struct.
      // Check that phys_footprint was returned instead of treating zero-filled tail fields as data.
      let footprintEnd = (MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint)
        ?? MemoryLayout<task_vm_info_data_t>.size) + MemoryLayout<mach_vm_size_t>.size
      guard result == KERN_SUCCESS, Int(count) * MemoryLayout<integer_t>.size >= footprintEnd else {
        return Snapshot(physicalFootprintBytes: nil, residentBytes: nil, availableBytes: nil,
                        error: result == KERN_SUCCESS ? KERN_FAILURE : result)
      }
      let available: UInt64?
      #if os(iOS)
      available = UInt64(os_proc_available_memory())
      #else
      available = nil
      #endif
      return Snapshot(physicalFootprintBytes: UInt64(info.phys_footprint),
                      residentBytes: UInt64(info.resident_size), availableBytes: available, error: nil)
    }

    var logFields: String {
      if let error { return "memory_sample_error=\(error)" }
      var fields = "phys_footprint_bytes=\(physicalFootprintBytes ?? 0) resident_bytes=\(residentBytes ?? 0)"
      if let availableBytes { fields += " available_bytes=\(availableBytes)" }
      return fields
    }
  }

  static func logSearchPhase(_ phase: SearchPhase) {
    let level: LogLevel = phase == .memoryWarning ? .warning : .info
    // Match the existing logger's level and file-logging settings. Nothing is uploaded.
    guard Logger.canLog(level) else { return }
    let snapshot = Snapshot.capture()
    LOG(level, "MikshatSearch phase=\(phase.rawValue) pid=\(getpid()) \(snapshot.logFields)")
  }
}
