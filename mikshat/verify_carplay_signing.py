"""Verify the navigation entitlement in the selected profile and exported app."""

import argparse
import datetime
import json
from pathlib import Path
import plistlib
import subprocess


TEAM_IDENTIFIER = "6W3WJ7KLLY"
APPLICATION_IDENTIFIER = f"{TEAM_IDENTIFIER}.com.mikshat.maps"
CARPLAY_ENTITLEMENT = "com.apple.developer.carplay-maps"


def require_navigation_entitlement(entitlements, source):
    if entitlements.get("application-identifier") != APPLICATION_IDENTIFIER:
        raise ValueError(f"{source}: unexpected application identifier")
    if entitlements.get("com.apple.developer.team-identifier") != TEAM_IDENTIFIER:
        raise ValueError(f"{source}: unexpected developer team")
    if entitlements.get(CARPLAY_ENTITLEMENT) is not True:
        raise ValueError(f"{source}: CarPlay navigation entitlement is missing")
    if entitlements.get("get-task-allow", False) is not False:
        raise ValueError(f"{source}: distribution signing must disable debugging")


def read_plist(command):
    result = subprocess.run(command, check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def verify(mode, path):
    profile_path = path if mode == "profile" else path / "embedded.mobileprovision"
    profile = read_plist(["security", "cms", "-D", "-i", str(profile_path)])
    require_navigation_entitlement(profile.get("Entitlements", {}), "Provisioning profile")
    if profile.get("TeamIdentifier") != [TEAM_IDENTIFIER]:
        raise ValueError("Provisioning profile: unexpected team identifier")
    expiry = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
    if expiry <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Provisioning profile has expired")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("An App Store provisioning profile is required")
    if profile["Entitlements"].get("beta-reports-active") is not True:
        raise ValueError("Provisioning profile does not support TestFlight")
    if mode == "app":
        signed = read_plist(["codesign", "-d", "--entitlements", ":-", str(path)])
        require_navigation_entitlement(signed, "Signed application")
    return {
        "applicationIdentifier": APPLICATION_IDENTIFIER,
        "profileName": profile.get("Name"),
        "profileUUID": profile.get("UUID"),
        "expirationDateUTC": expiry.isoformat(),
        "carPlayNavigation": True,
        "signedApplicationChecked": mode == "app",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("profile", "app"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = verify(args.mode, args.path)
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"CarPlay signing validation failed: {error}") from error
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
