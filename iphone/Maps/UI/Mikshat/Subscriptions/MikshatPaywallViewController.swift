import UIKit
import Combine
import StoreKit

enum MikshatSubscriptionLinks {
  static let privacy = URL(string: "https://mukshatapp.github.io/ios-privacy.html")!
  static let terms = URL(string: "https://mukshatapp.github.io/ios-terms.html")!
  static let support = URL(string: "https://mukshatapp.github.io/support.html")!
  static let manage = URL(string: "https://apps.apple.com/account/subscriptions")!
}

@MainActor
enum MikshatPremiumAccess {
  /// Callers capture and validate the original destination/location before resuming.
  static func require(from controller: UIViewController, onUnlock: @escaping () -> Void) {
    guard controller.viewIfLoaded?.window != nil, !controller.isBeingDismissed,
          controller.presentedViewController == nil else { return }
    let store = MikshatSubscriptionStore.shared
    store.start()
    if store.hasActiveSubscription {
      onUnlock()
      return
    }
    present(from: controller, onUnlock: onUnlock)
  }

  static func presentManage(from controller: UIViewController) {
    MikshatSubscriptionStore.shared.start()
    present(from: controller, onUnlock: nil)
  }

  private static func present(from controller: UIViewController, onUnlock: (() -> Void)?) {
    guard controller.viewIfLoaded?.window != nil, !controller.isBeingDismissed,
          controller.presentedViewController == nil else { return }
    let paywall = MikshatPaywallViewController(onUnlock: onUnlock)
    paywall.modalPresentationStyle = .overFullScreen
    paywall.modalTransitionStyle = .crossDissolve
    controller.present(paywall, animated: true)
  }
}

@MainActor
final class MikshatPaywallViewController: UIViewController {
  private let store = MikshatSubscriptionStore.shared
  private let onUnlock: (() -> Void)?
  private let priceLabel = UILabel()
  private let statusLabel = UILabel()
  private let purchaseButton = UIButton(type: .system)
  private let restoreButton = UIButton(type: .system)
  private let retryButton = UIButton(type: .system)
  private let closeButton = UIButton(type: .system)
  private let activity = UIActivityIndicatorView(style: .medium)
  private var subscriptions: Set<AnyCancellable> = []

  init(onUnlock: (() -> Void)?) {
    self.onUnlock = onUnlock
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.accessibilityIdentifier = "subscription.paywall"
    view.accessibilityViewIsModal = true
    view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

    let title = label(text(ar: "مكشات بلس", en: "Mikshat Plus"), style: .title1)
    title.textColor = MikshatStyle.green
    closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    closeButton.tintColor = MikshatStyle.green
    closeButton.accessibilityLabel = text(ar: "إغلاق", en: "Close")
    closeButton.accessibilityIdentifier = "subscription.close"
    closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    NSLayoutConstraint.activate([
      closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    let header = UIStackView(arrangedSubviews: [title, closeButton])
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = 12
    title.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let benefits = label(text(ar: "اشتراك سنوي يفتح لك:\n• الملاحة المباشرة إلى الوجهة\n• التوجيه بالبوصلة إلى الوجهة\n• حفظ مواقع جديدة", en: "An annual subscription unlocks:\n• Direct navigation to your destination\n• Compass guidance to your destination\n• Saving new locations"), style: .body)
    benefits.textAlignment = .natural
    let freeFeatures = label(text(ar: "تظل ملاحة السيارة والبوصلة العامة والقبلة ونسخ الإحداثيات ومشاركتها متاحة مجانًا. يمكنك الوصول إلى مواقعك المحفوظة سابقًا وتعديلها وحذفها ومشاركتها دون اشتراك.", en: "Car navigation, the general compass, Qibla, and copying and sharing coordinates remain free. You can still access, edit, delete and share your previously saved locations without a subscription."), style: .footnote)
    freeFeatures.textColor = .secondaryLabel
    priceLabel.font = .preferredFont(forTextStyle: .title2)
    priceLabel.adjustsFontForContentSizeCategory = true
    priceLabel.textAlignment = .center
    priceLabel.numberOfLines = 0
    priceLabel.accessibilityIdentifier = "subscription.price"
    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.adjustsFontForContentSizeCategory = true
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center
    statusLabel.accessibilityIdentifier = "subscription.status"
    configure(purchaseButton, title: text(ar: "اشترك سنويًا", en: "Subscribe annually"), filled: true)
    purchaseButton.accessibilityIdentifier = "subscription.purchase"
    purchaseButton.addAction(UIAction { [weak self] _ in self?.purchase() }, for: .touchUpInside)
    configure(restoreButton, title: text(ar: "استعادة المشتريات", en: "Restore purchases"))
    restoreButton.accessibilityIdentifier = "subscription.restore"
    restoreButton.addAction(UIAction { [weak self] _ in self?.restore() }, for: .touchUpInside)
    configure(retryButton, title: text(ar: "إعادة تحميل الاشتراك", en: "Reload subscription"))
    retryButton.accessibilityIdentifier = "subscription.retry"
    retryButton.addAction(UIAction { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.store.loadProduct()
        self.render()
      }
    }, for: .touchUpInside)
    let terms = label(text(ar: "يتجدد الاشتراك سنويًا تلقائيًا ما لم تلغه قبل نهاية الفترة الحالية بـ24 ساعة على الأقل. يُخصم المبلغ من حساب Apple عند تأكيد الشراء، ويمكنك إدارة الاشتراك أو إلغاؤه من إعدادات حسابك. يُعرض السعر الفعلي أعلاه وفق متجر حسابك.", en: "The subscription renews automatically each year unless cancelled at least 24 hours before the current period ends. Payment is charged to your Apple Account at purchase confirmation. Manage or cancel your subscription in your account settings. The actual price above is provided by your App Store storefront."), style: .footnote)
    terms.textColor = .secondaryLabel
    let legal = UIStackView()
    legal.axis = .vertical
    legal.spacing = 0
    legal.addArrangedSubview(link(text(ar: "إدارة الاشتراك وإلغاؤه", en: "Manage or cancel subscription"), url: MikshatSubscriptionLinks.manage))
    legal.addArrangedSubview(link(text(ar: "سياسة الخصوصية", en: "Privacy policy"), url: MikshatSubscriptionLinks.privacy))
    legal.addArrangedSubview(link(text(ar: "شروط الاستخدام", en: "Terms of use"), url: MikshatSubscriptionLinks.terms))
    legal.addArrangedSubview(link(text(ar: "الدعم", en: "Support"), url: MikshatSubscriptionLinks.support))

    let card = UIStackView(arrangedSubviews: [header, benefits, freeFeatures, priceLabel, activity, statusLabel, purchaseButton, restoreButton, retryButton, terms, legal])
    card.axis = .vertical
    card.spacing = 14
    card.isLayoutMarginsRelativeArrangement = true
    card.layoutMargins = UIEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
    card.backgroundColor = .systemBackground
    card.layer.cornerRadius = 24
    let scroll = UIScrollView()
    scroll.accessibilityIdentifier = "subscription.content"
    scroll.layer.cornerRadius = 24
    scroll.clipsToBounds = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    scroll.addSubview(card)
    let preferredWidth = scroll.widthAnchor.constraint(equalToConstant: 560)
    preferredWidth.priority = UILayoutPriority(999)
    let naturalHeight = scroll.heightAnchor.constraint(equalTo: card.heightAnchor)
    naturalHeight.priority = .defaultHigh
    NSLayoutConstraint.activate([
      scroll.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      scroll.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
      scroll.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      scroll.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      scroll.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      scroll.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      preferredWidth, naturalHeight,
      card.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      card.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      card.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      card.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      card.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    Publishers.CombineLatest4(store.$product, store.$isBusy, store.$message, store.$isCheckingEntitlements)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.render() }
      .store(in: &subscriptions)
    render()
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.store.refreshEntitlements()
      self.render()
      await self.store.loadProduct()
      self.render()
    }
  }

  private func render() {
    let active = store.hasActiveSubscription
    let busy = store.isBusy || store.isCheckingEntitlements
    if active {
      priceLabel.text = text(ar: "اشتراكك فعّال", en: "Your subscription is active")
    } else if let product = store.product {
      priceLabel.text = text(ar: "\(product.displayPrice) / سنويًا", en: "\(product.displayPrice) / year")
    } else if store.message != nil {
      priceLabel.text = text(ar: "الاشتراك غير متاح حاليًا", en: "Subscription currently unavailable")
    } else {
      priceLabel.text = text(ar: "جارٍ تحميل السعر من App Store…", en: "Loading the price from the App Store…")
    }
    statusLabel.text = store.message
    statusLabel.isHidden = store.message?.isEmpty != false
    purchaseButton.setTitle(active ? text(ar: "متابعة", en: "Continue") : text(ar: "اشترك سنويًا", en: "Subscribe annually"), for: .normal)
    purchaseButton.configuration?.title = active ? text(ar: "متابعة", en: "Continue") : text(ar: "اشترك سنويًا", en: "Subscribe annually")
    purchaseButton.isHidden = active && onUnlock == nil
    purchaseButton.isEnabled = !busy && (active || store.product != nil)
    restoreButton.isEnabled = !busy
    retryButton.isHidden = store.product != nil || active
    retryButton.isEnabled = !busy
    closeButton.isEnabled = !store.isBusy
    isModalInPresentation = store.isBusy
    activity.isHidden = !busy
    busy ? activity.startAnimating() : activity.stopAnimating()
  }

  private func purchase() {
    guard !store.isBusy, !store.isCheckingEntitlements else { return }
    if store.hasActiveSubscription { finishUnlock(); return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      if await self.store.purchase() { self.finishUnlock() }
      self.render()
    }
  }

  private func restore() {
    guard !store.isBusy, !store.isCheckingEntitlements else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      if await self.store.restore(), self.onUnlock != nil { self.finishUnlock() }
      self.render()
    }
  }

  private func finishUnlock() {
    guard store.hasActiveSubscription, let onUnlock, presentingViewController != nil,
          presentedViewController == nil else { return }
    dismiss(animated: true) {
      guard MikshatSubscriptionStore.shared.hasActiveSubscription else { return }
      onUnlock()
    }
  }

  private func configure(_ button: UIButton, title: String, filled: Bool = false) {
    var configuration: UIButton.Configuration = filled ? .filled() : .plain()
    configuration.title = title
    configuration.baseForegroundColor = filled ? .white : MikshatStyle.green
    configuration.baseBackgroundColor = MikshatStyle.green
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    button.configuration = configuration
    button.titleLabel?.numberOfLines = 0
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
  }

  private func link(_ title: String, url: URL) -> UIButton {
    let button = UIButton(type: .system)
    configure(button, title: title)
    button.addAction(UIAction { _ in UIApplication.shared.open(url) }, for: .touchUpInside)
    return button
  }

  private func label(_ value: String, style: UIFont.TextStyle) -> UILabel {
    let label = UILabel()
    label.text = value
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    return label
  }

  private func text(ar: String, en: String) -> String { MikshatSubscriptionText.text(ar: ar, en: en) }
}
