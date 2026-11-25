import Foundation

/// Presentation rules for provider metadata embedded in the supplementary maps.
/// Keep the raw feature values available for editing and other uses.
enum PlacePageSourceMetadata {
  static func descriptionForDisplay(_ description: String?) -> String? {
    guard let description else { return nil }
    let normalized = description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return normalized == "الحقوق محفوظة لتطبيق خرائط الصحراء" ? nil : description
  }

  static func websiteForDisplay(_ website: String?) -> String? {
    guard let website else { return nil }
    var urlString = website.trimmingCharacters(in: .whitespacesAndNewlines)
    if urlString.hasPrefix("//") {
      urlString = "https:" + urlString
    } else if !urlString.contains("://") {
      urlString = "https://" + urlString
    }
    guard let url = URLComponents(string: urlString),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host?.lowercased() else { return website }

    // Match the verified provider endpoints, preserving business sites and other paths.
    switch (host, url.path) {
    case ("knaree.com", "/ksa"), ("knaree.com", "/ksa/"),
         ("www.knaree.com", "/ksa"), ("www.knaree.com", "/ksa/"),
         ("desertsa.com", ""), ("desertsa.com", "/"),
         ("www.desertsa.com", ""), ("www.desertsa.com", "/"):
      return nil
    default:
      return website
    }
  }
}
