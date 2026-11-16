#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
subscription_sources="$repo_root/iphone/Maps/UI/Mikshat/Subscriptions"
subscription_tests="$repo_root/iphone/Maps/Tests/UI/Subscriptions/MikshatSubscriptionEntitlementTests.swift"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mikshat-subscriptions.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required to execute the production entitlement-policy tests." >&2
  exit 1
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  # The production XCTest file supplies its own Linux runner.
  swiftc "$subscription_sources/MikshatSubscriptionEntitlement.swift" \
    "$subscription_tests" -o "$test_root/entitlement-tests"
  "$test_root/entitlement-tests"
  echo "Entitlement-policy tests passed; iOS SDK typechecking requires macOS/Xcode."
  exit 0
fi

mkdir -p "$test_root/Sources/MikshatEntitlements" "$test_root/Tests/MikshatEntitlementsTests"
cp "$subscription_sources/MikshatSubscriptionEntitlement.swift" "$test_root/Sources/MikshatEntitlements/"
# Run the app's actual XCTest cases in a small package, without loading the map engine.
sed 's/@testable import Organic_Maps__Debug_/@testable import MikshatEntitlements/' \
  "$subscription_tests" > "$test_root/Tests/MikshatEntitlementsTests/EntitlementTests.swift"
cat > "$test_root/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "MikshatEntitlements",
  targets: [
    .target(name: "MikshatEntitlements"),
    .testTarget(name: "MikshatEntitlementsTests", dependencies: ["MikshatEntitlements"]),
  ]
)
SWIFT
swift test --package-path "$test_root"

ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
# The real app also imports CoreApi.Product through its Objective-C bridge. Keep that
# name collision in this focused SDK check; SDK-only imports would miss the integration error.
mkdir -p "$test_root/CoreApi"
cat > "$test_root/CoreApi/module.modulemap" <<'MODULE'
module CoreApi {
  header "CoreApi.h"
  export *
}
MODULE
cat > "$test_root/CoreApi/CoreApi.h" <<'OBJC'
#import <Foundation/Foundation.h>
@interface Product : NSObject
@end
OBJC
cat > "$test_root/AppBridge.h" <<'OBJC'
@import CoreApi;
OBJC
cat > "$test_root/PaywallStyleStub.swift" <<'SWIFT'
import UIKit
// The sole map-app dependency used by the paywall; the real value is in MikshatInterface.swift.
enum MikshatStyle {
  static let green = UIColor(red: 22 / 255, green: 78 / 255, blue: 63 / 255, alpha: 1)
}
SWIFT
xcrun swiftc -typecheck -swift-version 5 -sdk "$ios_sdk" -target arm64-apple-ios15.0 \
  -I "$test_root" -import-objc-header "$test_root/AppBridge.h" \
  "$subscription_sources/MikshatSubscriptionEntitlement.swift" \
  "$subscription_sources/MikshatSubscriptionStore.swift" \
  "$subscription_sources/MikshatSubscriptions.swift" \
  "$subscription_sources/MikshatPaywallViewController.swift" \
  "$test_root/PaywallStyleStub.swift"
echo "StoreKit service, lifecycle bridge and paywall passed iOS 15 SDK typechecking."
