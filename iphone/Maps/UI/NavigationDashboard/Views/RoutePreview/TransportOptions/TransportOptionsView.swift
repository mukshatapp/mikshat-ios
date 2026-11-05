import UIKit

final class TransportOptionsView: UIView {
  private let stack = UIStackView()
  private var buttons: [UIButton] = []
  private var selectedRouterType: MWMRouterType = .vehicle
  private let panelPanGestureRecognizer = UIPanGestureRecognizer()
  weak var interactor: NavigationDashboard.Interactor?
  var onPanGesture: ((UIPanGestureRecognizer) -> Void)?

  init() {
    super.init(frame: .zero)
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.semanticContentAttribute = .forceLeftToRight
    stack.backgroundColor = .secondarySystemBackground
    stack.layer.cornerRadius = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    let modes = [("mikshat_direct", "arrow.up"), ("mikshat_car", "car.fill"), ("mikshat_heading", "safari")]
    for (index, item) in modes.enumerated() {
      let button = UIButton(type: .system)
      button.setImage(MikshatSymbols.image(named: item.1), for: .normal)
      button.accessibilityLabel = L(item.0)
      button.accessibilityIdentifier = "mikshat_navigation_mode_\(index)"
      button.tag = index
      button.tintColor = MikshatStyle.green
      button.layer.cornerRadius = 18
      button.addTarget(self, action: #selector(selectMode(_:)), for: .touchUpInside)
      buttons.append(button)
      stack.addArrangedSubview(button)
    }
    addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
    panelPanGestureRecognizer.addTarget(self, action: #selector(handlePanGesture(_:)))
    panelPanGestureRecognizer.delegate = self
    panelPanGestureRecognizer.cancelsTouchesInView = false
    addGestureRecognizer(panelPanGestureRecognizer)
    updateSelection()
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func set(transportOptions: [MWMRouterType], selectedRouterType: MWMRouterType) {
    self.selectedRouterType = selectedRouterType
    updateSelection()
  }
  private func updateSelection() {
    let selection = selectedRouterType == .vehicle ? 1 : (MikshatNavigationCoordinator.compassSelected ? 2 : 0)
    for (index, button) in buttons.enumerated() {
      button.backgroundColor = index == selection ? MikshatStyle.cream : .clear
      button.accessibilityTraits = index == selection ? [.button, .selected] : [.button]
    }
  }
  @objc private func selectMode(_ sender: UIButton) {
    selectedRouterType = sender.tag == 1 ? .vehicle : .ruler
    MikshatNavigationCoordinator.compassSelected = sender.tag == 2
    updateSelection()
    interactor?.process(.selectRouterType(selectedRouterType))
  }
  @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) { onPanGesture?(gesture) }
}

extension TransportOptionsView: UIGestureRecognizerDelegate {
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    let velocity = panelPanGestureRecognizer.velocity(in: self)
    return abs(velocity.y) > abs(velocity.x) + 5
  }
}
