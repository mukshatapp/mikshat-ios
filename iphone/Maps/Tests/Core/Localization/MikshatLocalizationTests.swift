import XCTest
@testable import Organic_Maps__Debug_

final class MikshatLocalizationTests: XCTestCase {
  func testAppBundleContainsOnlyArabicAndEnglishInterfaceLanguages() {
    XCTAssertEqual(Set(Bundle.main.localizations).subtracting(["Base"]), ["ar", "en"])
    XCTAssertEqual(Set(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []),
                   ["ar", "en"])
  }

  func testSettingsAndNavigationNamesHaveBothInterfaceTranslations() throws {
    let keys = [
      "settings", "general_settings", "map", "prefs_group_route", "pref_appearance_title",
      "pref_appearance_light", "pref_appearance_dark", "pref_map_3d_title", "pref_map_auto_zoom",
      "mobile_data", "bookmarks", "bookmarks_and_tracks", "bookmarks_text_placement_title",
      "mikshat_icloud_sync_title", "mikshat_compass_settings", "mikshat_direct", "mikshat_record_track",
      "mikshat_save_share", "mikshat_save_location", "mikshat_share_location", "mikshat_go_to",
      "mikshat_dirt_road_type",
      "pref_tts_voice_group_novelty", "pref_tts_voice_preview_play", "pref_tts_voice_preview_stop",
    ]
    for language in ["ar", "en"] {
      let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
      let bundle = try XCTUnwrap(Bundle(path: path))
      for key in keys {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertFalse(value.isEmpty, "\(language): \(key)")
        XCTAssertNotEqual(value, key, "\(language): \(key) is missing from the built app")
        if language == "ar" {
          XCTAssertTrue(value.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) },
                        "\(key) falls back to non-Arabic text: \(value)")
        }
      }
      XCTAssertEqual(bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"),
                     language == "ar" ? "مكشات" : "Mikshat")
      XCTAssertEqual(bundle.localizedString(forKey: "mikshat_dirt_road_type", value: nil, table: nil),
                     language == "ar" ? "درب" : "Dirt track")
    }
  }

  func testEnglishTermsMatchArabicMikshatFeatureNames() throws {
    let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
    let english = try XCTUnwrap(Bundle(path: path))
    XCTAssertEqual(english.localizedString(forKey: "bookmarks", value: nil, table: nil), "Favorites")
    XCTAssertEqual(english.localizedString(forKey: "mikshat_direct", value: nil, table: nil), "Direct guidance")
    XCTAssertEqual(english.localizedString(forKey: "mikshat_stop", value: nil, table: nil), "Finish")
    XCTAssertEqual(english.localizedString(forKey: "mobile_data", value: nil, table: nil), "Mobile data")
  }
}
