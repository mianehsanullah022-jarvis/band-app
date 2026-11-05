"""Write the SideStore / AltStore source file (source.json) for the newest build.

SideStore reads this file to know which version is newest and where to download it.
"""
import argparse
import datetime
import json
import plistlib

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True)          # owner/name
parser.add_argument("--build", required=True)         # build number, e.g. 42
parser.add_argument("--size", required=True, type=int)
parser.add_argument("--info", required=True)          # path to the built Info.plist
parser.add_argument("--out", required=True)
a = parser.parse_args()

with open(a.info, "rb") as f:
    info = plistlib.load(f)

owner, name = a.repo.split("/")
raw = f"https://raw.githubusercontent.com/{a.repo}"

# Privacy texts must match the app exactly, or SideStore refuses to install.
privacy = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}

source = {
    "name": "Band",
    "identifier": f"io.github.{owner.lower()}.band",
    "subtitle": "Your own app for your band",
    "website": f"https://github.com/{a.repo}",
    "iconURL": f"{raw}/main/BandApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
    "tintColor": "#2ECC71",
    "apps": [
        {
            "name": "Band",
            "bundleIdentifier": info["CFBundleIdentifier"],
            "developerName": "Ehsanullah",
            "subtitle": "Heart rate, steps, vibrations and more",
            "localizedDescription": "Your own app for your WP band: heart rate, blood pressure, steps, "
                                    "water, workouts, vibration patterns, calls and alarms.",
            "iconURL": f"{raw}/main/BandApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
            "tintColor": "#2ECC71",
            "category": "lifestyle",
            "versions": [
                {
                    "version": info["CFBundleShortVersionString"],
                    "buildVersion": info["CFBundleVersion"],
                    "date": datetime.date.today().isoformat(),
                    "localizedDescription": f"Band {info['CFBundleShortVersionString']}",
                    "downloadURL": f"https://github.com/{a.repo}/releases/download/build-{a.build}/Band.ipa",
                    "size": a.size,
                    "minOSVersion": info.get("MinimumOSVersion", "16.0"),
                }
            ],
            "appPermissions": {
                "entitlements": [],
                "privacy": privacy,
            },
        }
    ],
    "news": [],
}

with open(a.out, "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
