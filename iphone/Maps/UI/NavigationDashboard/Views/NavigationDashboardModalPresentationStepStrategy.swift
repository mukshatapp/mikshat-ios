enum NavigationDashboardModalPresentationStep: Int, CaseIterable, ModalPresentationStep {
  case regular
  case halfScreen
  case compact
  case estimates
  case hidden
}

final class NavigationDashboardModalPresentationStepStrategy: ModalPresentationStepStrategy {
  private enum Constants {
    static let centeredWidth: CGFloat = 720
    static let centeredInset: CGFloat = 12
    static let defaultContentHeight: CGFloat = 190
    static let halfScreenHeightFactorPortrait: CGFloat = 0.55
    static let halfScreenOriginFactorPortrait: CGFloat = 0.5
    static let topInset: CGFloat = 8
  }

  static let halfScreenActivationHeightFactor: CGFloat = 2.0 / 3.0

  typealias Step = NavigationDashboardModalPresentationStep

  static func == (lhs: NavigationDashboardModalPresentationStepStrategy, rhs: NavigationDashboardModalPresentationStepStrategy) -> Bool {
    lhs.regularHeight == rhs.regularHeight &&
      lhs.compactBaseHeight == rhs.compactBaseHeight &&
      lhs.estimatesHeight == rhs.estimatesHeight &&
      lhs.compactDiscoverabilityOffset == rhs.compactDiscoverabilityOffset &&
      lhs.shouldUseCompactDiscoverabilityOffset == rhs.shouldUseCompactDiscoverabilityOffset &&
      lhs.shouldShowHalfScreenStep == rhs.shouldShowHalfScreenStep &&
      lhs.shouldShowEstimatesStep == rhs.shouldShowEstimatesStep
  }

  var regularHeight: CGFloat = .zero
  var compactBaseHeight: CGFloat = .zero
  var estimatesHeight: CGFloat = .zero
  var compactDiscoverabilityOffset: CGFloat = .zero
  var shouldUseCompactDiscoverabilityOffset = true
  var shouldShowHalfScreenStep = false
  var shouldShowEstimatesStep = false

  var compactHeight: CGFloat {
    compactBaseHeight + (shouldUseCompactDiscoverabilityOffset ? compactDiscoverabilityOffset : 0)
  }

  var steps: [Step] {
    var availableSteps: [Step] = [.regular]
    if shouldShowHalfScreenStep {
      availableSteps.append(.halfScreen)
    }
    availableSteps.append(.compact)
    if shouldShowEstimatesStep {
      availableSteps.append(.estimates)
    }
    availableSteps.append(.hidden)
    return availableSteps
  }

  func upperTo(_ step: Step) -> Step {
    switch step {
    case .regular, .halfScreen:
      return .regular
    case .compact:
      return shouldShowHalfScreenStep ? .halfScreen : .regular
    case .estimates:
      return .compact
    case .hidden:
      return shouldShowEstimatesStep ? .estimates : .compact
    }
  }

  func lowerTo(_ step: Step) -> Step {
    switch step {
    case .regular:
      return shouldShowHalfScreenStep ? .halfScreen : .compact
    case .halfScreen:
      return .compact
    case .compact:
      return shouldShowEstimatesStep ? .estimates : .compact
    case .estimates:
      return .estimates
    case .hidden:
      return .hidden
    }
  }

  func resolvedStep(_ step: Step) -> Step {
    switch step {
    case .halfScreen where !shouldShowHalfScreenStep:
      return .regular
    case .estimates where !shouldShowEstimatesStep:
      return .compact
    default:
      return step
    }
  }

  static func usesCenteredLayout(in container: UIViewController) -> Bool {
    container.traitCollection.userInterfaceIdiom == .pad || container.view.bounds.width > container.view.bounds.height
  }

  func frame(_ step: Step, for _: UIView, in containerViewController: UIViewController) -> CGRect {
    let bounds = containerViewController.view.bounds
    guard !bounds.isEmpty else { return .zero }
    let safeAreaInsets = containerViewController.view.safeAreaInsets
    let safe = bounds.inset(by: safeAreaInsets)

    if Self.usesCenteredLayout(in: containerViewController) {
      let available = safe.insetBy(dx: Constants.centeredInset, dy: Constants.topInset)
      let desiredHeight: CGFloat
      switch step {
      case .regular, .halfScreen:
        desiredHeight = regularHeight
      case .compact:
        // The route-point list is hidden. Do not retain its old discoverability
        // padding as blank space in the compact, centered preview.
        desiredHeight = compactBaseHeight
      case .estimates:
        desiredHeight = estimatesHeight > 0 ? estimatesHeight : compactBaseHeight
      case .hidden:
        desiredHeight = regularHeight
      }
      let height = min(max(1, available.height), desiredHeight > 0 ? desiredHeight : Constants.defaultContentHeight)
      let width = min(Constants.centeredWidth, max(1, available.width))
      return CGRect(x: safe.midX - width / 2,
                    y: step == .hidden ? bounds.maxY : safe.midY - height / 2,
                    width: width, height: height)
    }

    // Preserve the phone's portrait bottom-sheet steps.
    var frame = bounds
    switch step {
    case .regular:
      frame.origin.y = regularHeight > 0
        ? max(bounds.maxY - regularHeight, safe.minY + Constants.topInset)
        : bounds.height * Constants.halfScreenHeightFactorPortrait
    case .halfScreen:
      frame.origin.y = max(bounds.height * Constants.halfScreenOriginFactorPortrait, safe.minY + Constants.topInset)
    case .compact:
      frame.origin.y = compactHeight > 0 ? bounds.maxY - compactHeight : bounds.height * Constants.halfScreenHeightFactorPortrait
    case .estimates:
      let height = estimatesHeight > 0 ? estimatesHeight : compactHeight
      frame.origin.y = height > 0 ? bounds.maxY - height : bounds.height * Constants.halfScreenHeightFactorPortrait
    case .hidden:
      frame.origin.y = bounds.maxY
    }
    return frame
  }
}
