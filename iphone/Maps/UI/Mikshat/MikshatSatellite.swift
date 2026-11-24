import UIKit

final class MikshatSatelliteController {
  static let shared = MikshatSatelliteController()
  private struct Source: Decodable {
    let url: String
    let minZoom: Int
    let maxZoom: Int
    let embeddedTileCount: Int
  }
  private var source: Source?
  private weak var button: UIButton?
  private var isLoading = false
  private var topConstraint: NSLayoutConstraint?
  private var enabled: Bool { UserDefaults.standard.bool(forKey: "mikshat_satellite_enabled") }

  func install(in view: UIView) {
    guard button == nil else { return }
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "globe"), for: .normal)
    button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 27), forImageIn: .normal)
    button.tintColor = MikshatStyle.green
    button.layer.cornerRadius = 24
    button.layer.borderWidth = 2
    button.layer.borderColor = MikshatStyle.green.cgColor
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    topConstraint = button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 58)
    NSLayoutConstraint.activate([
      button.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 14),
      topConstraint!,
      button.widthAnchor.constraint(equalToConstant: 48), button.heightAnchor.constraint(equalToConstant: 48),
    ])
    button.showsMenuAsPrimaryAction = true
    button.accessibilityIdentifier = "map.layers"
    self.button = button
    MikshatSupplementaryMaps.shared.restoreSelection()
    refreshButton()
    loadSource()
  }

  func updateLayout(in view: UIView) {
    topConstraint?.constant = view.bounds.width > view.bounds.height ? 8 : 58
  }
  func buttonFrame(in view: UIView) -> CGRect? {
    guard let button, button.window != nil, !button.isHidden else { return nil }
    return button.convert(button.bounds, to: view)
  }

  private func loadSource() {
    guard !isLoading else { return }
    isLoading = true
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let value = Bundle.main.url(forResource: "MikshatSatellite", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Source.self, from: $0) }
      DispatchQueue.main.async {
        guard let self else { return }
        self.isLoading = false
        if let value, value.minZoom == 0, value.maxZoom == 20, Settings.isWellFormedBackgroundTilesURL(value.url) {
          self.source = value
          self.apply(self.enabled)
        }
        self.refreshButton()
      }
    }
  }

  private func apply(_ value: Bool) {
    guard let source else { return }
    if value {
      Settings.setBackgroundTiles(enabled: true, url: source.url, cacheSizeMB: 100, areaOpacityPct: 0)
    } else { Settings.setBackgroundTilesEnabled(false) }
    UserDefaults.standard.set(value, forKey: "mikshat_satellite_enabled")
    refreshButton()
  }

  private func refreshButton() {
    let maps = MikshatSupplementaryMaps.shared
    let anyEnabled = enabled || !maps.enabledIDs.isEmpty
    button?.backgroundColor = anyEnabled ? UIColor(red: 0.82, green: 0.94, blue: 0.85, alpha: 1) : .white
    button?.setImage(UIImage(systemName: enabled ? "globe.europe.africa.fill" : "globe"), for: .normal)
    button?.accessibilityLabel = L("mikshat_map_layers")
    button?.accessibilityValue = L(anyEnabled ? "on" : "off")
    button?.accessibilityTraits = anyEnabled ? [.button, .selected] : .button

    let satellite = UIAction(title: L(enabled ? "mikshat_satellite_disable" : "mikshat_satellite_enable"),
                             image: UIImage(systemName: "globe.europe.africa"),
                             attributes: source == nil ? [.disabled] : [],
                             state: enabled ? .on : .off) { [weak self] _ in
      guard let self else { return }
      self.apply(!self.enabled)
    }
    let offlineMaps = MikshatSupplementaryMaps.catalog.map { map in
      UIAction(title: L(map.titleKey), state: maps.enabledIDs.contains(map.id) ? .on : .off) { [weak self] _ in
        if !maps.setEnabled(!maps.enabledIDs.contains(map.id), id: map.id) {
          self?.showMapError()
        }
        self?.refreshButton()
      }
    }
    button?.menu = UIMenu(title: L("mikshat_map_layers"), children: [
      satellite,
      UIMenu(title: L("mikshat_supplementary_maps"), image: UIImage(systemName: "map"), children: offlineMaps),
    ])
  }

  private func showMapError() {
    DispatchQueue.main.async { [weak self] in
      var presenter = self?.button?.window?.rootViewController
      while let presented = presenter?.presentedViewController { presenter = presented }
      let alert = UIAlertController(title: L("mikshat_supplementary_maps"),
                                    message: L("mikshat_supplementary_map_unavailable"), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: L("ok"), style: .default))
      presenter?.present(alert, animated: true)
    }
  }
}
