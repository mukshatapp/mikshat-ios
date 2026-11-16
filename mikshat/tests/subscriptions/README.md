# Subscription verification

Run `bash mikshat/tests/subscriptions/run.sh` on macOS with Xcode. The script runs the app's entitlement XCTest cases against the actual production decision code, then typechecks the StoreKit service, Objective-C lifecycle bridge and UIKit paywall against the iOS 15 SDK. The paywall's shared green color and an imported `CoreApi.Product` name-collision fixture are supplied as small standalone stubs. This requires subscription code to distinguish `StoreKit.Product` from the existing app type. Linux with Swift can run the entitlement cases but cannot perform iOS SDK checks.

This focused check does not replace building the complete app or testing Apple purchase sheets. It does not verify any App Store Connect product, Saudi storefront price, banking agreement or signed archive.

## Local StoreKit testing

`MikshatSubscriptions.storekit` is an optional local-only annual product fixture with a simulated price of SAR 39.99 and no introductory offer. Add it to Xcode and select it in a **separate local testing scheme** under Run → Options → StoreKit Configuration. Production schemes and archives must keep StoreKit Configuration set to None. The real price and availability come from App Store Connect; this fixture does not create a product there.

Use Xcode's StoreKit transaction manager to exercise purchase, cancel, pending/Ask to Buy, approval, restore, expiration and revocation. Confirm an unrelated or unverified transaction cannot unlock the three paid actions. Repeat with App Store sandbox/TestFlight and the actual configured annual product before submitting for review.

## Device acceptance

- Without an entitlement, direct navigation, destination compass and adding a saved location show the paywall. Closing, cancelling, pending approval, store failure and empty restore leave those actions locked.
- Successful verified purchase or restore unlocks the three actions. Changing the selected destination while a purchase is pending must not navigate to an old destination.
- Car navigation, the general compass, Qibla, copying and sharing coordinates, accessing/editing/removing existing saved locations, and restoring a backup remain free.
- An offline customer with a locally verified unexpired subscription keeps access. Expiry or revocation blocks the next paid action without interrupting an already started trip or hiding existing data.
- Check the paywall and its close/restore/manage/legal controls on iPhone and iPad in portrait and landscape, with Arabic/English and larger accessibility text. Scroll to read every disclosure when space is limited.
