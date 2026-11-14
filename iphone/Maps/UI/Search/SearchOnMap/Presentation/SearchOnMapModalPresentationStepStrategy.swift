enum SearchOnMapModalPresentationStep: Int, CaseIterable, ModalPresentationStep {
  case expanded
  case halfScreen
  case compact
  case hidden
}

struct SearchOnMapModalPresentationStepStrategy: ModalPresentationStepStrategy {
  private enum Constants {
    static let iPadWidth: CGFloat = 350
    static let compactBaseOffset: CGFloat = 64
    static let halfScreenHeightFactorPortrait: CGFloat = 0.55
    static let topInset: CGFloat = 8
    static func compactHeightOffset(bottomSafeAreaInset: CGFloat) -> CGFloat {
      compactBaseOffset + max(0, bottomSafeAreaInset - topInset) // empiric value
    }
  }

  typealias Step = SearchOnMapModalPresentationStep

  func upperTo(_ step: Step) -> Step {
    switch step {
    case .expanded:
      return .expanded
    case .halfScreen:
      return .expanded
    case .compact:
      return .halfScreen
    case .hidden:
      return .compact
    }
  }

  func lowerTo(_ step: Step) -> Step {
    switch step {
    case .expanded:
      return .halfScreen
    case .halfScreen:
      return .compact
    case .compact:
      return .compact
    case .hidden:
      return .hidden
    }
  }

  func frame(_ step: Step, for _: UIView, in containerViewController: UIViewController) -> CGRect {
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    var containerSize = containerViewController.view.bounds.size
    if containerSize == .zero {
      containerSize = UIScreen.main.bounds.size
    }
    let safeAreaInsets = containerViewController.view.safeAreaInsets
    let traitCollection = containerViewController.traitCollection
    var frame = CGRect(origin: .zero, size: containerSize)
    let safeWidth = max(0, containerSize.width - safeAreaInsets.left - safeAreaInsets.right)
    let safeHeight = max(0, containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
    let sheetWidth = min(Constants.iPadWidth, safeWidth)
    let centeredX = safeAreaInsets.left + (safeWidth - sheetWidth) / 2

    if isIPad {
      frame.size.width = sheetWidth
      switch step {
      case .hidden:
        frame.origin.x = -Constants.iPadWidth
      default:
        frame.origin.x = centeredX
        frame.origin.y = safeAreaInsets.top
        frame.size.height = safeHeight
      }
      return frame
    }

    let isPortraitOrientation = traitCollection.verticalSizeClass == .regular
    if isPortraitOrientation {
      switch step {
      case .expanded:
        frame.origin.y = safeAreaInsets.top + Constants.topInset
      case .halfScreen:
        frame.origin.y = containerSize.height * Constants.halfScreenHeightFactorPortrait
      case .compact:
        frame.origin.y =
          containerSize.height - Constants.compactHeightOffset(bottomSafeAreaInset: safeAreaInsets.bottom)
      case .hidden:
        frame.origin.y = containerSize.height
      }
    } else {
      frame.size.width = sheetWidth
      frame.origin.x = centeredX
      switch step {
      case .expanded:
        frame.origin.y = safeAreaInsets.top + Constants.topInset
        frame.size.height = max(0, safeHeight - 2 * Constants.topInset)
      case .halfScreen, .compact:
        frame.origin.y =
          containerSize.height - Constants.compactHeightOffset(bottomSafeAreaInset: safeAreaInsets.bottom)
      case .hidden:
        frame.origin.y = containerSize.height
      }
    }
    return frame
  }
}
