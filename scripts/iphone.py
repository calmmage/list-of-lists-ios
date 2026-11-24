"""Build List of Lists with Xcode and install it on an explicitly selected iPhone."""

import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = "ListOfLists.xcodeproj"
SCHEME = "ListOfLists"


def doctor():
    version = subprocess.check_output(["xcodebuild", "-version"], text=True).splitlines()[0]
    if int(version.split()[1].split(".")[0]) < 16:
        sys.exit("Use Xcode 16 or later with iOS platform support.")
    for sdk in ["iphoneos", "iphonesimulator"]:
        subprocess.run(["xcrun", "--sdk", sdk, "--show-sdk-path"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["xcrun", "--find", "devicectl"], check=True, stdout=subprocess.DEVNULL)
    print(f"cli: ok ({version}, iPhone and simulator SDKs)")


def build(destination, data, sdk, settings):
    print(f"Building {SCHEME} for {sdk}…", flush=True)
    subprocess.run([
        "xcodebuild", "-quiet", "-project", PROJECT, "-scheme", SCHEME, "-configuration", "Debug",
        "-sdk", sdk, "-destination", destination, "-derivedDataPath", str(data), *settings, "build",
    ], check=True)
    app = data / "Build" / "Products" / f"Debug-{sdk}" / f"{SCHEME}.app"
    if not (app / "Info.plist").is_file():
        sys.exit(f"Xcode finished but could not find {app}/Info.plist.")
    return app


def devices():
    # xcdevice lists hardware UDIDs accepted by both xcodebuild and devicectl.
    result = subprocess.check_output(["xcrun", "xcdevice", "list", "--timeout", "5"], text=True)
    return [d for d in json.loads(result)
            if not d.get("simulator") and d.get("modelCode", "").startswith("iPhone")
            and d.get("platform") == "com.apple.platform.iphoneos"]


def signing_teams():
    # The certificate's OU is the team ID. Its common-name suffix can be a different ID.
    certificates = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    teams = set()
    for pem in re.findall(b"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                          certificates.stdout, re.DOTALL):
        cert = subprocess.run(["/usr/bin/openssl", "x509", "-noout", "-subject",
                               "-nameopt", "sep_multiline,sname"], input=pem, stdout=subprocess.PIPE)
        team = re.search(rb"^\s*OU\s*=\s*([A-Z0-9]{10})\s*$", cert.stdout, re.MULTILINE)
        if team:
            teams.add(team[1].decode())
    return sorted(teams)


def wizard():
    print("Looking for physical iPhones…", flush=True)
    phones = devices()
    for phone in phones:
        status = "available" if phone.get("available") else "unavailable"
        print(f"{phone['name']} ({status})  DEVICE_ID={phone['identifier']}")
    if not phones:
        print("Connect and unlock your iPhone, then pair it in Xcode and run make wizard again.")
    teams = signing_teams()
    if teams:
        print("Team IDs from local Apple Development certificates: " + ", ".join(teams))
    else:
        print("For a signing team, sign in under Xcode → Settings → Apple Accounts.")
    print("Choose your iPhone, team and unique bundle ID. See docs/install-iphone.md, then run make preflight.")


def selected_inputs(needs_team):
    device, team, bundle = (os.environ.get(k, "") for k in ("DEVICE_ID", "TEAM_ID", "BUNDLE_ID"))
    if not device:
        sys.exit("Set DEVICE_ID to the hardware UDID shown by make wizard.")
    if needs_team and not re.fullmatch(r"[A-Z0-9]{10}", team):
        sys.exit("Set TEAM_ID to your 10-character Apple development team ID.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        sys.exit("Set BUNDLE_ID to your own unique reverse-DNS identifier.")
    return device, team, bundle


def devicectl(*args):
    # A file works on older Xcode versions where --json-output - is unavailable.
    with tempfile.TemporaryDirectory() as tmp:
        result = Path(tmp) / "result.json"
        proc = subprocess.run(["xcrun", "devicectl", "--timeout", "120", "--json-output", str(result), *args],
                              stdout=subprocess.PIPE, text=True)
        if proc.returncode:
            print(proc.stdout.rstrip(), file=sys.stderr)
            proc.check_returncode()
        return json.loads(result.read_text())["result"]


def check_phone(device):
    phone = next((p for p in devices() if p["identifier"].lower() == device.lower()), None)
    if not phone or not phone.get("available"):
        sys.exit("Selected iPhone unavailable. Unlock, pair in Xcode, and check its UDID with make wizard.")
    if int(phone["operatingSystemVersion"].split(".")[0]) < 17:
        sys.exit("This app requires iOS 17 or later.")
    try:
        details = devicectl("device", "info", "details", "--device", device)
    except subprocess.CalledProcessError:
        sys.exit("Could not reach the selected iPhone. Unlock and reconnect it, then check pairing in Xcode.")
    properties = details.get("properties", {})
    state = properties.get("state", {}).get("developerModeStatus")
    if state is None:
        state = details.get("deviceProperties", {}).get("developerModeStatus")
    if state == "disabled" or (isinstance(state, dict) and "disabled" in state):
        sys.exit("Turn on Settings → Privacy & Security → Developer Mode on the iPhone, restart and confirm.")
    print(f"Selected {phone['name']} · iOS {phone['operatingSystemVersion']}", flush=True)


def verify(device, bundle):
    try:
        apps = devicectl("device", "info", "apps", "--device", device,
                         "--filter", f"bundleIdentifier == '{bundle}'")
    except subprocess.CalledProcessError:
        sys.exit("Installed-app readback unavailable. Unlock and reconnect the iPhone, then run make verify-iphone.")
    app = next((a for a in apps["apps"] if a.get("bundleIdentifier") == bundle), None)
    if app is None:
        sys.exit(f"Installed-app readback did not find {bundle} on the selected iPhone.")
    print(f"Installed: {bundle} · version {app.get('version', '?')} ({app.get('bundleVersion', '?')})",
          flush=True)
    try:
        launch = devicectl("device", "process", "launch", "--device", device, "--terminate-existing", bundle)
        pid = launch.get("process", {}).get("processIdentifier")
        if not isinstance(pid, int) or pid < 1:
            sys.exit("Installed app found. Xcode did not return a launch PID; launch remains unverified.")
        result = devicectl("device", "info", "processes", "--device", device, "--filter", f"processIdentifier == {pid}")
        if not any(p.get("processIdentifier") == pid for p in result["runningProcesses"]):
            sys.exit("Installed app found. Its launched process was absent at readback.")
    except subprocess.CalledProcessError:
        sys.exit("Installed app found. Launch unverified. Unlock the iPhone, check developer trust, then run make verify-iphone.")
    print(f"Running: {bundle} · PID {pid} confirmed on the selected iPhone")


def main(command):
    os.chdir(ROOT)
    if command == "doctor":
        return doctor()
    if command == "wizard":
        return wizard()
    if command == "setup":
        app = build("generic/platform=iOS Simulator", ROOT / "build" / "simulator", "iphonesimulator",
                    ["CODE_SIGNING_ALLOWED=NO"])
        print(f"Simulator app: {app.relative_to(ROOT)}")
        return
    if command not in {"preflight", "install-iphone", "verify-iphone"}:
        sys.exit("Run make help for available commands.")
    device, team, bundle = selected_inputs(command != "verify-iphone")
    check_phone(device)
    if command == "preflight":
        print(f"Preflight passed for {bundle}. Xcode checks signing access during the build.")
        return
    if command == "install-iphone":
        data = ROOT / "build" / "iphone" / team / bundle
        app = build(f"id={device}", data, "iphoneos", [
            "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration", "CODE_SIGN_STYLE=Automatic",
            f"DEVELOPMENT_TEAM={team}", f"PRODUCT_BUNDLE_IDENTIFIER={bundle}",
        ])
        with (app / "Info.plist").open("rb") as plist:
            if plistlib.load(plist)["CFBundleIdentifier"] != bundle:
                sys.exit("The built bundle identifier differs from BUNDLE_ID. Stopped before installation.")
        subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
        signature = subprocess.run(["codesign", "-dv", "--verbose=2", str(app)],
                                   check=True, stderr=subprocess.PIPE, text=True)
        if f"TeamIdentifier={team}" not in signature.stderr.splitlines():
            sys.exit("The build signature differs from TEAM_ID. Stopped before installation.")
        print("Installing the signed app on the selected iPhone…", flush=True)
        devicectl("device", "install", "app", "--device", device, str(app))
    verify(device, bundle)


if __name__ == "__main__":
    try:
        main(sys.argv[1] if len(sys.argv) == 2 else "help")
    except FileNotFoundError as error:
        sys.exit(f"Missing {error.filename}. Install and open Xcode, then run make doctor.")
    except subprocess.CalledProcessError as error:
        sys.exit(f"{error.cmd[0]} exited {error.returncode}. See the tool's error above and docs/install-iphone.md.")
