import UIKit

enum MikshatCompassAppearance {
  static let changed = Notification.Name("MikshatCompassAppearanceChanged")
  static var enabled: Bool { UserDefaults.standard.bool(forKey: "mikshat_compass_transparency_enabled") }
  static var percentage: Int {
    guard UserDefaults.standard.object(forKey: "mikshat_compass_transparency") != nil else { return 40 }
    return max(0, min(100, UserDefaults.standard.integer(forKey: "mikshat_compass_transparency")))
  }
}

final class MikshatToolsViewController: MWMTableViewController {
  private let modeKeys = ["mikshat_heading_sensor", "mikshat_heading_gps", "mikshat_heading_auto"]
  init() { super.init(style: .insetGrouped) }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = L("mikshat_compass_settings")
    view.tintColor = MikshatStyle.green
  }
  override func numberOfSections(in tableView: UITableView) -> Int { 2 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : 2 }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    L(section == 0 ? "mikshat_heading_source" : "mikshat_compass_transparency_title")
  }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    L(section == 0 ? "mikshat_heading_hint" : "mikshat_compass_transparency_hint")
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.textLabel?.numberOfLines = 0
    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
    cell.detailTextLabel?.numberOfLines = 0
    cell.selectionStyle = .none
    if indexPath.section == 0 {
      cell.textLabel?.text = L(modeKeys[indexPath.row])
      cell.accessoryType = UserDefaults.standard.integer(forKey: "mikshat_heading_mode") == indexPath.row ? .checkmark : .none
    } else if indexPath.row == 0 {
      cell.textLabel?.text = L("mikshat_compass_transparency_enable")
      let toggle = UISwitch()
      toggle.isOn = MikshatCompassAppearance.enabled
      toggle.accessibilityLabel = cell.textLabel?.text
      toggle.addTarget(self, action: #selector(transparencyChanged(_:)), for: .valueChanged)
      cell.accessoryView = toggle
    } else {
      cell.textLabel?.text = L("mikshat_compass_transparency_amount")
      cell.detailTextLabel?.text = "\(MikshatCompassAppearance.percentage)%"
      let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
      slider.minimumValue = 0; slider.maximumValue = 100
      slider.value = Float(MikshatCompassAppearance.percentage)
      slider.isEnabled = MikshatCompassAppearance.enabled
      slider.isContinuous = false
      slider.accessibilityLabel = cell.textLabel?.text
      slider.addTarget(self, action: #selector(amountChanged(_:)), for: .valueChanged)
      cell.accessoryView = slider
    }
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard indexPath.section == 0 else { return }
    UserDefaults.standard.set(indexPath.row, forKey: "mikshat_heading_mode")
    tableView.reloadData()
  }
  @objc private func transparencyChanged(_ sender: UISwitch) {
    UserDefaults.standard.set(sender.isOn, forKey: "mikshat_compass_transparency_enabled")
    changed()
  }
  @objc private func amountChanged(_ sender: UISlider) {
    UserDefaults.standard.set(Int(sender.value.rounded()), forKey: "mikshat_compass_transparency")
    changed()
  }
  private func changed() {
    NotificationCenter.default.post(name: MikshatCompassAppearance.changed, object: nil)
    tableView.reloadData()
  }
}
