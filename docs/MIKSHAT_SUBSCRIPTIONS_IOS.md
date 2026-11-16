# Mikshat iOS subscription release

Mikshat remains a free download. A single annual auto-renewable subscription unlocks direct navigation,
compass guidance to a selected destination, and saving new places. Car navigation, the general compass,
Qibla, copying and sharing locations, and viewing, managing, deleting, and sharing existing saved places
remain free. Expiry must not delete saved places or tracks or interrupt an active navigation session.

## App Store Connect setup

The user has created the App Store Connect product with the matching Product ID and a one-year
duration. The user accepted SAR 39.99 because SAR 39 was unavailable, and selected the eight countries
listed below. These setup steps do not mean the product is approved or ready for sale. The review
screenshot and review information are not complete. The iOS legal/support pages were published and
verified with HTTP 200; account agreement, banking, and tax status are still unverified.

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
| Selected Saudi price | SAR 39.99 per year, accepted by the user |
| Selected initial countries | Bahrain, Iraq, Kuwait, Oman, Qatar, Saudi Arabia, United Arab Emirates, Yemen |
| Introductory offer / trial | None at launch |
| Arabic display name | مكشات بريميوم السنوي |
| English display name | Mikshat Premium Annual |
| Arabic description | التوجيه المباشر وبوصلة الوجهة وحفظ مواقع جديدة |
| English description | Direct navigation, destination compass and new saves |

Keep this Product ID identical in the app, local StoreKit test configuration, and App Store Connect.
The app must display StoreKit's localized price and billing period. SAR 39.99 is the selected Saudi
price; do not hardcode it in the purchase screen or advertise it as the price in every storefront.
Verify Apple's local price and currency for each selected country. Display names and descriptions above
remain the intended metadata until their saved values and review status are checked in App Store Connect.

The Account Holder must have an active Paid Apps Agreement and complete the applicable tax and banking
information. Verify the In-App Purchase capability for the app's registered identifier and signed build.
Do not place App Store keys, shared secrets, payment credentials, or commercial weather keys in the app
or repository. StoreKit verification on the device does not require a secret embedded in the client.

Continue the created product under App Store Connect → Mikshat → Monetization → Subscriptions.
Complete and verify localized group/product information, price, availability, tax category, and a review
screenshot showing the actual paywall. The first subscription and first group must be submitted with a new app version.
Creating a `.storekit` file only enables local testing; it does not create a purchasable App Store product.

## Metadata, legal pages, and privacy

Reviewed Arabic and English metadata lives in `iphone/metadata/ar-SA` and `iphone/metadata/en-US`.
These pages are published; recheck them on a phone and in a browser before submission:

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

The subscription source is in [draft PR #7](https://github.com/mukshatapp/mikshat-ios/pull/7), which is
not merged. A native build failure is being diagnosed. No successful signed subscription build or
TestFlight purchase validation is established by the App Store Connect setup described above.

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

The source provides a direct entry at Settings → **Mikshat subscription** (Arabic: **اشتراك مكشات**).
That screen contains **Restore purchases** (استعادة المشتريات) and **Manage or cancel subscription**
(إدارة الاشتراك وإلغاؤه). Use [the prepared English review notes](app-store/subscription-review-notes.txt)
after validating these paths in the actual submitted build. The text describes the intended review
flow, not evidence that a production or TestFlight build has already passed testing.

The product has been created and its initial price/countries selected by the user. Completion of its
review information, legal-page publication, commercial weather readiness, account agreements,
signed-build purchase testing, and App Review approval remain separate release requirements.
Source code and metadata changes alone do not complete them. Small Business Program application
submission is not proof of acceptance or an active reduced commission.

Apple references: [subscription configuration and first submission](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/),
[In-App Purchase account setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/),
and [purchase screen disclosures](https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase).
