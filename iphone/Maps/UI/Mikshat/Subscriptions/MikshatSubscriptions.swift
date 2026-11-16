import Foundation

/// Objective-C entry points for the app's aggregate (including CarPlay) lifecycle.
@objc(MikshatSubscriptions)
final class MikshatSubscriptions: NSObject {
  @objc static func start() {
    Task { @MainActor in
      MikshatSubscriptionStore.shared.start()
    }
  }
}
