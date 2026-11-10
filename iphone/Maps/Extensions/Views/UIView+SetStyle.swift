private enum AssociatedKeys {
  static var styleName: UInt8 = 0
  static var isStyleApplied: UInt8 = 1
}

@objc extension UIView: StyleApplicable {
  dynamic func sw_viewDidMoveToWindow() {
    // A nil app window (a CarPlay-first launch, or a disconnected phone scene) must not match a
    // view that is leaving the hierarchy: nil === nil is true.
    guard let appWindow = MapsAppDelegate.theApp().window, appWindow === window else {
      sw_viewDidMoveToWindow()
      return
    }
    applyTheme()
    isStyleApplied = true
    sw_viewDidMoveToWindow()
  }

  var styleName: String {
    get {
      isStyleApplied = false
      guard let value = objc_getAssociatedObject(self, &AssociatedKeys.styleName) as? String else {
        return ""
      }
      return value
    }
    set(newValue) {
      objc_setAssociatedObject(self, &AssociatedKeys.styleName, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  var isStyleApplied: Bool {
    get {
      guard let value = objc_getAssociatedObject(self, &AssociatedKeys.isStyleApplied) as? Bool else {
        return false
      }
      return value
    }
    set(newValue) {
      objc_setAssociatedObject(self, &AssociatedKeys.isStyleApplied, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  func setStyleNameAndApply(_ styleName: String) {
    self.styleName = styleName
    applyTheme()
  }
}
