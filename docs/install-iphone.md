# Install List of Lists on your iPhone

You can build and run the app directly from your Mac using your Apple Account. You'll need an iPhone running iOS 17 or later and the full Xcode 16 or later with iOS support. Choose an Xcode version that supports your phone's iOS version.

## Give this to your coding agent

```text
Install List of Lists from https://github.com/calmmage/list-of-lists-ios on my iPhone using this Mac. Follow AGENTS.md and docs/install-iphone.md. Discover the physical iPhones and signing teams, then use the iPhone and team I identify. Look up the installed List of Lists bundle ID for an update, or use the stable per-team ID for my first install. Run the preflight, build, install, and open the app. Let me handle Apple sign-in and any trust, unlock or Developer Mode prompts. Tell me the installed bundle ID and the PID verified on my phone. If something fails, tell me the last step that worked and resume there.
```

## Prepare your Mac and iPhone

1. Install Xcode and open it once to finish installing its components. In **Xcode → Settings → Locations**, select this Xcode under **Command Line Tools**. Under **Apple Accounts** (called **Accounts** in earlier versions), sign in. A free **Personal Team** supports installing on your own device. [Apple Account and Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)
2. Connect the iPhone with a USB data cable and unlock it. Accept **Trust This Computer** on the phone if asked. Pair it in Xcode's **Device Hub** or, in earlier versions, **Window → Devices and Simulators**. After pairing, Xcode can also reach the phone over the local network. [Pair a device with Xcode](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)
3. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, restart and confirm after unlocking. If the setting is missing, initiate pairing in Xcode first. [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

```sh
git clone https://github.com/calmmage/list-of-lists-ios.git
cd list-of-lists-ios
make wizard
```

The wizard checks Xcode and prints the names and hardware IDs of physical iPhones and team IDs found in local Apple Development certificates. If your account has several teams, choose the one you intend to sign with. If your team has no certificate yet, select the team under Xcode's **Apple Accounts → Manage Certificates**, click **+ → Apple Development**, then run the wizard again.

## Build, install and open

Set these variables in the same terminal, replacing both values with your selections from the wizard. Look up earlier installations on that phone by their display name.

```sh
export DEVICE_ID='your-iphone-hardware-udid'
export TEAM_ID='your-development-team-id'
xcrun devicectl device info apps --device "$DEVICE_ID" \
  --filter "name == 'List of Lists' OR name == 'ListOfLists'"
```

**First install.** If the lookup succeeds and there are no matches, use this bundle ID. The same team produces the same ID every time.

```sh
export BUNDLE_ID="org.localdev.t${TEAM_ID}.listoflists"
```

**Update.** If you see your app, copy its exact **Bundle Identifier** into `export BUNDLE_ID='…'`. If several copies appear, select the one containing your lists. Use the original signing team.

```sh
make preflight
make install-iphone
```

Preflight checks the selected phone and input formats. The install command uses automatic signing with your team and bundle ID. It allows Xcode to register the app ID and phone with Apple as needed, verifies the signature, and installs `ListOfLists.app` using `devicectl`. On the Home Screen the app is called **List of Lists**. The installer queries the phone for the exact bundle ID, opens it and checks the running process. The last two lines show **Installed** with the bundle ID and version, then **Running** with the PID.

## If a step needs your attention

| What you see | What to do |
| --- | --- |
| No available iPhone | Unlock it, reconnect by USB, finish pairing in Xcode, and run `make wizard` again. |
| Xcode reports a signing or registration error | Check your signed-in team and its development certificate. For an unavailable first-install bundle ID, generate a new unique ID. Rerun `make install-iphone`. |
| Installed, then launch failed | Unlock the iPhone. If iOS says **Untrusted Developer**, open **Settings → General → VPN & Device Management** and trust your own developer identity when prompted. Run `make verify-iphone` to reopen the existing installation and check the PID. |
| The app stops opening after several days on a Personal Team | Apple Personal Team provisioning expires after seven days. Use the same team and bundle ID to rebuild and reinstall. [Apple's Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account) |

For updates, pull the latest source, use the same three values and rerun `make install-iphone`. Keeping the bundle ID updates the existing app and its local lists. A different bundle ID creates a separate app. Keep the existing installation when renewing a profile.

For a simulator build on the Mac, `make setup` produces `build/simulator/Build/Products/Debug-iphonesimulator/ListOfLists.app`. For an interactive run, open `ListOfLists.xcodeproj`, select the **ListOfLists** scheme and an iPhone simulator, then press **⌘R**.
