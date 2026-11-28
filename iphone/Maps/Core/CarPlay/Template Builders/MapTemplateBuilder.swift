import CarPlay

final class MapTemplateBuilder {
  enum MapButtonType {
    case startPanning
    case zoomIn
    case zoomOut
    case recenter
    case northUp
    case headingUp
  }

  enum BarButtonType {
    case dismissPaning
    case destination
    case settings
    case mute
    case unmute
    case redirectRoute
    case endRoute
    case saveLocation
    case tripInformation
  }

  private enum Constants {
    static let carPlayGuidanceBackgroundColor = UIColor(46, 100, 51, 1.0)
  }

  // MARK: - CPMapTemplate builders

  class func buildBaseTemplate(positionMode: MWMMyPositionMode, isOnRoute: Bool) -> CPMapTemplate {
    let mapTemplate = CPMapTemplate()
    mapTemplate.hidesButtonsWithNavigationBar = false
    configureBaseUI(mapTemplate, positionMode: positionMode, isOnRoute: isOnRoute)
    return mapTemplate
  }

  class func buildNavigationTemplate(positionMode: MWMMyPositionMode) -> CPMapTemplate {
    let mapTemplate = CPMapTemplate()
    mapTemplate.hidesButtonsWithNavigationBar = false
    configureNavigationUI(mapTemplate, positionMode: positionMode)
    return mapTemplate
  }

  class func buildTripPreviewTemplate(forTrips trips: [CPTrip]) -> CPMapTemplate {
    let mapTemplate = CPMapTemplate()
    mapTemplate.userInfo = MapInfo(type: CPConstants.TemplateType.preview, trips: trips)
    setupMapButtons(mapTemplate, positionMode: .pendingPosition, allowsPanning: false)
    mapTemplate.leadingNavigationBarButtons = []
    let settingsButton = buildBarButton(type: .settings) { [weak mapTemplate] _ in
      guard let mapTemplate else { return }
      mapTemplate.userInfo = MapInfo(type: CPConstants.TemplateType.previewSettings)
      let gridTemplate = SettingsTemplateBuilder.buildGridTemplate()
      CarPlayService.shared.pushTemplate(gridTemplate, animated: true)
    }
    mapTemplate.trailingNavigationBarButtons = [settingsButton]
    return mapTemplate
  }

  // MARK: - MapTemplate UI configs

  class func configureBaseUI(_ mapTemplate: CPMapTemplate, positionMode: MWMMyPositionMode, isOnRoute: Bool) {
    mapTemplate.userInfo = MapInfo(type: CPConstants.TemplateType.main)
    setupMapButtons(mapTemplate, positionMode: positionMode)
    setupLeadingNavigationBarButtons(mapTemplate, positionMode: positionMode, isOnRoute: isOnRoute)
    let settingsButton = buildBarButton(type: .settings) { _ in
      let gridTemplate = SettingsTemplateBuilder.buildGridTemplate()
      CarPlayService.shared.pushTemplate(gridTemplate, animated: true)
    }
    let informationButton = buildBarButton(type: .tripInformation) { _ in
      CarPlayService.shared.showTripInformation()
    }
    mapTemplate.trailingNavigationBarButtons = [settingsButton, informationButton]
  }

  class func configurePanUI(_ mapTemplate: CPMapTemplate) {
    mapTemplate.hidesButtonsWithNavigationBar = false
    let recenterButton = buildMapButton(type: .recenter) { _ in
      CarPlayService.shared.recenterMap()
    }
    let zoomInButton = buildMapButton(type: .zoomIn) { _ in
      FrameworkHelper.zoomMap(.in)
    }
    let zoomOutButton = buildMapButton(type: .zoomOut) { _ in
      FrameworkHelper.zoomMap(.out)
    }
    mapTemplate.mapButtons = [recenterButton, zoomInButton, zoomOutButton]

    let doneButton = buildBarButton(type: .dismissPaning) { [weak mapTemplate] _ in
      mapTemplate?.dismissPanningInterface(animated: true)
    }
    mapTemplate.leadingNavigationBarButtons = []
    mapTemplate.trailingNavigationBarButtons = [doneButton]
  }

  class func configureNavigationUI(_ mapTemplate: CPMapTemplate, positionMode: MWMMyPositionMode) {
    mapTemplate.userInfo = MapInfo(type: CPConstants.TemplateType.navigation)
    setupMapButtons(mapTemplate, positionMode: positionMode)
    setupLeadingNavigationBarButtons(mapTemplate, positionMode: positionMode, isOnRoute: true)
    let endButton = buildBarButton(type: .endRoute) { _ in
      CarPlayService.shared.cancelCurrentTrip()
    }
    let informationButton = buildBarButton(type: .tripInformation) { _ in
      CarPlayService.shared.showTripInformation()
    }
    mapTemplate.trailingNavigationBarButtons = [informationButton, endButton]
    mapTemplate.guidanceBackgroundColor = Constants.carPlayGuidanceBackgroundColor
  }

  // MARK: - Conditional navigation buttons

  class func setupMapButtons(_ mapTemplate: CPMapTemplate, positionMode: MWMMyPositionMode, northUp: Bool? = nil, allowsPanning: Bool = true) {
    mapTemplate.hidesButtonsWithNavigationBar = false
    guard !mapTemplate.isPanningInterfaceVisible else { return }
    let panningButton = buildMapButton(type: .startPanning) { [weak mapTemplate] _ in
      mapTemplate?.showPanningInterface(animated: true)
    }
    let recenterButton = buildMapButton(type: .recenter) { _ in
      CarPlayService.shared.recenterMap()
    }
    let orientationButton = buildMapButton(type: (northUp ?? CarPlayService.shared.isNorthUp) ? .northUp : .headingUp) { _ in
      CarPlayService.shared.toggleMapOrientation()
    }
    mapTemplate.mapButtons = allowsPanning ? [recenterButton, orientationButton, panningButton] : [recenterButton, orientationButton]
  }

  class func setupLeadingNavigationBarButtons(_ mapTemplate: CPMapTemplate, positionMode: MWMMyPositionMode, isOnRoute: Bool) {
    let isTTSEnabled = MWMTextToSpeech.isTTSEnabled()
    let muteButton = buildBarButton(type: isTTSEnabled ? .mute : .unmute) { [weak mapTemplate] _ in
      guard let mapTemplate else { return }
      MWMTextToSpeech.setTTSEnabled(!MWMTextToSpeech.isTTSEnabled())
      setupLeadingNavigationBarButtons(mapTemplate, positionMode: positionMode, isOnRoute: isOnRoute)
    }
    let saveButton = buildBarButton(type: .saveLocation) { _ in
      CarPlayService.shared.saveCurrentLocation()
    }
    let destinationButton = buildBarButton(type: .destination) { _ in
      let listTemplate = ListTemplateBuilder.buildListTemplate(for: .history)
      CarPlayService.shared.pushTemplate(listTemplate, animated: true)
    }
    if isOnRoute {
      mapTemplate.leadingNavigationBarButtons = [muteButton, saveButton]
      return
    }
    switch positionMode {
    case .follow, .followAndRotate, .notFollow:
      if !mapTemplate.isPanningInterfaceVisible {
        mapTemplate.leadingNavigationBarButtons = [destinationButton, saveButton]
      }
    case .pendingPosition, .notFollowNoPosition:
      mapTemplate.leadingNavigationBarButtons = [saveButton]
    }
  }

  // MARK: - CPMapButton builder

  private class func buildMapButton(type: MapButtonType, action: ((CPMapButton) -> Void)?) -> CPMapButton {
    let (image, focusedImage): (UIImage, UIImage) = switch type {
    case .startPanning: (.btnCarplayPan, .btnCarplayPanFocused)
    case .zoomIn: (.btnZoomIn, .btnCarplayZoomInFocused)
    case .zoomOut: (.btnZoomOut, .btnCarplayZoomOutFocused)
    case .recenter: (.btnGetPosition, .btnCarplayGetPositionFocused)
    case .northUp: orientationImages(symbolName: "n.circle")
    case .headingUp: orientationImages(symbolName: "arrow.up.circle")
    }
    let button = CPMapButton(handler: action)
    // Original rendering keeps the artwork's own contrast; CarPlay would otherwise tint both states.
    // The focused variants swap the disc and glyph colours so the button stands out when selected.
    button.image = image.withRenderingMode(.alwaysOriginal)
    button.focusedImage = resolveFocusedImage(focusedImage, for: CarPlayService.shared.templateTraitCollection)
    switch type {
    case .startPanning: button.accessibilityLabel = L("mikshat_carplay_pan")
    case .zoomIn: button.accessibilityLabel = L("zoom_in")
    case .zoomOut: button.accessibilityLabel = L("zoom_out")
    case .recenter: button.accessibilityLabel = L("mikshat_carplay_gps")
    case .northUp: button.accessibilityLabel = L("mikshat_carplay_north_up")
    case .headingUp: button.accessibilityLabel = L("mikshat_carplay_heading_up")
    }
    return button
  }

  private class func orientationImages(symbolName: String) -> (UIImage, UIImage) {
    let symbol = UIImage(systemName: symbolName,
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold))!
    return (symbol.withTintColor(.black, renderingMode: .alwaysOriginal),
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal))
  }

  /// CarPlay sends the image of a map button in both appearances, but the focused image only as given,
  /// so it must be resolved for the car: CarPlayService rebuilds the buttons when its appearance changes.
  class func resolveFocusedImage(_ image: UIImage, for traits: UITraitCollection) -> UIImage {
    (image.imageAsset?.image(with: traits) ?? image).withRenderingMode(.alwaysOriginal)
  }

  // MARK: - CPBarButton builder

  private class func buildBarButton(type: BarButtonType, action: ((CPBarButton) -> Void)?) -> CPBarButton {
    switch type {
    case .dismissPaning:
      CPBarButton(title: L("done"), handler: action)
    case .destination:
      CPBarButton(title: L("pick_destination"), handler: action)
    case .settings:
      CPBarButton(image: UIImage.icCarplaySettings, handler: action)
    case .mute:
      CPBarButton(image: UIImage.icCarplayUnmuted, handler: action)
    case .unmute:
      CPBarButton(image: UIImage.icCarplayMuted, handler: action)
    case .redirectRoute:
      CPBarButton(image: UIImage.icCarplayRedirectRoute, handler: action)
    case .endRoute:
      CPBarButton(title: L("navigation_stop_button").capitalized, handler: action)
    case .saveLocation:
      CPBarButton(title: L("mikshat_carplay_save_location"), handler: action)
    case .tripInformation:
      CPBarButton(title: L("mikshat_carplay_trip_info"), handler: action)
    }
  }
}
