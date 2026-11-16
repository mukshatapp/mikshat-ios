# Mikshat iOS subscription release

Mikshat remains a free download. A single annual auto-renewable subscription unlocks direct navigation,
compass guidance to a selected destination, and saving new places. Car navigation, the general compass,
Qibla, copying and sharing locations, and viewing, managing, deleting, and sharing existing saved places
remain free. Expiry must not delete saved places or tracks or interrupt an active navigation session.

## App Store Connect setup

These are the selected settings, not evidence that an App Store product has been created or approved.

| Field | Value |
| --- | --- |
| App | Mikshat / مكشات |
| App Store Apple ID | `6828427541` |
| Bundle ID | `com.mikshat.maps` |
| App download price | Free |
| Subscription group reference name | `Mikshat Premium` |
| Product ID | `com.mikshat.maps.premium.annual` |
| Reference name | `Mikshat Premium Annual` |
| Duration | 1 year, automatically renewing |
| Initial intended Saudi price | SAR 39 per year; confirm the actual available App Store price point |
| Introductory offer / trial | None at launch |
| Arabic display name | مكشات بريميوم السنوي |
| English display name | Mikshat Premium Annual |
| Arabic description | التوجيه المباشر والملاحة بالبوصلة وحفظ مواقع جديدة |
| English description | Direct and compass navigation; save new places |

Keep this Product ID identical in the app, local StoreKit test configuration, and App Store Connect.
The app must display StoreKit's localized price and billing period. Do not hardcode SAR 39 in the purchase
screen or advertise that price in every storefront. If SAR 39 is unavailable, settle the exact price point
before release rather than silently choosing another amount. Select subscription availability explicitly.

The Account Holder must have an active Paid Apps Agreement and complete the applicable tax and banking
information. Verify the In-App Purchase capability for the app's registered identifier and signed build.
Do not place App Store keys, shared secrets, payment credentials, or commercial weather keys in the app
or repository. StoreKit verification on the device does not require a secret embedded in the client.

Create the subscription group and product under App Store Connect → Mikshat → Monetization → Subscriptions.
Add localized group/product information, price, availability, tax category, and a review screenshot showing
the actual paywall. The first subscription and first group must be submitted with a new app version.
Creating a `.storekit` file only enables local testing; it does not create a purchasable App Store product.

## Metadata, legal pages, and privacy

Reviewed Arabic and English metadata lives in `iphone/metadata/ar-SA` and `iphone/metadata/en-US`.
Before submission, publish and verify these pages on a phone and in a browser:

- Privacy: https://mukshatapp.github.io/ios-privacy.html
- Terms and subscription: https://mukshatapp.github.io/ios-terms.html
- Support: https://mukshatapp.github.io/support.html
- Support contact: `alhadafsystem@gmail.com`

The existing `privacy.html` and `terms.html` describe Android/Google Play and must not be presented as
iOS terms unchanged. Keep in-app links, App Store privacy URL, and the terms link in the description
consistent. State the annual duration, automatic renewal, restoration, cancellation, and what remains
available after expiry. Use current iPhone/iPad screenshots showing the actual free and paid experience.

Other locale directories still contain inherited Organic Maps metadata. Upload only the reviewed Arabic
and English entries, or review/update other App Store localizations before using them. Do not bulk-upload
the entire inherited metadata directory unchanged. Metadata files are drafts until entered in App Store
Connect; a successful binary upload does not upload these text files.

The weather client retains the user's selected free Open-Meteo endpoint for development and testing.
It sends the selected latitude and longitude to that provider. Open-Meteo's
[terms](https://open-meteo.com/en/terms) restrict that endpoint to noncommercial use and explicitly
classify apps with subscriptions as commercial. Its CC BY attribution does not grant free commercial
API access, and Apple approval does not change those service terms. Resolve the weather service
arrangement before commercial sales; its [pricing](https://open-meteo.com/en/pricing) describes the
commercial endpoint. Do not embed a commercial key in the app. The iOS privacy policy and App Store
privacy answers must accurately describe weather location transmission and the provider's retention,
rather than claiming no location leaves the device. This service decision does not prevent preparing
the subscription source, metadata, or purchase tests.

## Build and purchase validation

Use the Mikshat signed Codemagic workflow in `codemagic.yaml`, `mikshat-ios-testflight`. It signs
`com.mikshat.maps`, uploads to TestFlight, and does not submit a public App Store release automatically.
The inherited `xcode/fastlane/Deliverfile`, `xcode/fastlane/Fastfile`, and
`iphone/upload_to_appstore.sh` still refer to Organic Maps identifiers/signing settings. Do not use them
to upload Mikshat unchanged. Update app/widget versions together when preparing the subscription build.

Validate the exact uploaded build on iPhone and iPad, in portrait and landscape:

- Non-subscribers see the paywall for each of the three paid actions; free actions and saved data remain usable.
- Product loading shows the real annual localized price; unavailable products and connection failures allow retry.
- Successful verified purchases unlock access. Pending, cancelled, failed, unverified, expired, and revoked
  purchases do not grant access. No local test override grants access in a release build.
- Restore works on a second installation using the purchasing Apple account. Manage subscription opens
  Apple's controls. Turning off renewal preserves access through the entitled period.
- Verified access remains usable offline within its validity. Expiry/refund/revocation updates access when
  learned; an in-progress trip is not stopped and existing saved places/tracks are retained.

Check the changed metadata without copying fallback files into other locales:

```bash
python3 tools/python/check_store_metadata.py files iphone/metadata/ar-SA/*.txt iphone/metadata/en-US/*.txt
```

The bulk `ios` checker also copies fallback/overlay metadata; review its working-tree changes if used.
Record StoreKit local tests and TestFlight/sandbox purchase results separately: local fixtures alone do
not prove that the App Store product, account agreements, or production purchases are ready.

## Submission notes

Attach the first subscription to the new app version, select the processed build, complete privacy,
age rating and export-compliance fields, and supply the subscription review screenshot and notes.
Review notes should identify how to open the paywall from direct navigation, destination compass
guidance, and saving a new point, and where to restore/manage the subscription. Explain that car
navigation, general compass, Qibla, copying/sharing, and access to existing saved places remain free.
Check every reviewer instruction against the actual submitted UI. No Mikshat account is required for
the StoreKit purchase flow; do not invent credentials or bypass Apple's payment review.

App Store Connect product creation, legal-page publication, commercial weather readiness, account
agreements, signed-build purchase testing, and App Review approval are separate release requirements.
Source code and metadata changes alone do not complete them. Small Business Program application
submission is not proof of acceptance or an active reduced commission.

Apple references: [subscription configuration and first submission](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/),
[In-App Purchase account setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/),
and [purchase screen disclosures](https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase).
