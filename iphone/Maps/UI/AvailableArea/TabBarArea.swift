final class TabBarArea: AvailableArea {
  override var areaFrame: CGRect {
    if traitCollection.userInterfaceIdiom == .phone,
       let parent = superview, parent.bounds.width > parent.bounds.height {
      // The storyboard's compact area is a narrow sidebar. The home bar needs
      // the actual safe viewport instead, in its parent's coordinate space.
      let safe = parent.safeAreaLayoutGuide.layoutFrame
      let safeBottom = max(0, parent.bounds.maxY - safe.maxY)
      let extraHeight = max(0, UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 36) - 36)
      let height = min(parent.bounds.maxY - safe.minY, 76 + safeBottom + extraHeight)
      return CGRect(x: safe.minX, y: parent.bounds.maxY - height,
                    width: safe.width, height: height)
    }
    var areaFrame = frame
    // Spacing is used only for devices with zero bottom safe area (such as SE).
    // window can be nil during a CarPlay-first cold launch, before the phone window scene connects.
    let additionalBottomSpacing: CGFloat = (MapsAppDelegate.theApp().window?.safeAreaInsets.bottom ?? 0).isZero ? -10 : .zero
    let extraHeight = max(0, UIFontMetrics.default.scaledValue(for: 96) - 96)
    areaFrame.origin.y += additionalBottomSpacing - extraHeight
    areaFrame.size.height += extraHeight
    return areaFrame
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  override func isAreaAffectingView(_ other: UIView) -> Bool {
    !other.tabBarAreaAffectDirections.isEmpty
  }

  override func addAffectingView(_ other: UIView) {
    let ov = other.tabBarAreaAffectView
    let directions = ov.tabBarAreaAffectDirections
    addConstraints(otherView: ov, directions: directions)
  }

  override func notifyObserver() {
    BottomTabBarViewController.updateAvailableArea(areaFrame)
  }
}

extension UIView {
  @objc var tabBarAreaAffectDirections: MWMAvailableAreaAffectDirections { [] }

  var tabBarAreaAffectView: UIView { self }
}
