import UIKit

// Retain the old internal class name for compatibility, but expose only the settings page.
final class MikshatToolsViewController: UITableViewController {
  private let modeKeys = ["mikshat_heading_sensor", "mikshat_heading_gps", "mikshat_heading_auto"]
  init() { super.init(style: .insetGrouped) }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = L("mikshat_heading_source")
    view.tintColor = MikshatStyle.green
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { modeKeys.count }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { L("mikshat_heading_hint") }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.textLabel?.text = L(modeKeys[indexPath.row])
    cell.textLabel?.numberOfLines = 0
    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
    cell.accessoryType = UserDefaults.standard.integer(forKey: "mikshat_heading_mode") == indexPath.row ? .checkmark : .none
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    UserDefaults.standard.set(indexPath.row, forKey: "mikshat_heading_mode")
    tableView.reloadData()
  }
}
