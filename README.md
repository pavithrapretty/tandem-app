# HapticRemote

Tap a button on the iPhone and the paired Apple Watch plays a haptic pattern.
No server, no internet, no paid Apple Developer account. The two apps talk
directly through WatchConnectivity.

It also works the other way around: the watch app opens on a page with the
same four buttons, and they make the iPhone vibrate. The iPhone app must be
open on screen for this, because iOS does not let an app in the background
play haptics.

Requires iOS 17+ and watchOS 10+.

## Files

| File | What it does |
| --- | --- |
| `Shared/Pattern.swift` | The patterns. Compiled into both apps. |
| `HapticRemote/ConnectivityManager.swift` | iPhone: sends patterns, tracks connection status, receives patterns from the watch. |
| `HapticRemote/PhoneHapticPlayer.swift` | iPhone: plays the same patterns on the phone with CoreHaptics. Forward and Turn around use the Anvil and Barrage presets from the [Pulsar](https://docs.swmansion.com/pulsar/) library, copied in as data. |
| `HapticRemote/SettingsView.swift` | iPhone: Settings ("20 Settings" in Figma), with "Redo the onboarding" to replay the tutorial and "Simulate a walk to Centraal", which opens the navigation screen with Back and Forward buttons to walk the route by hand (tap = 5 m, hold = keep walking). |
| `HapticRemote/GuidanceView.swift` | iPhone: the navigation screens ("09 – 14" in Figma). Follows the real route to Centraal or a searched place; the watch's remote buttons can take over. |
| `HapticRemote/SearchView.swift` | iPhone: search for a place or stop, by typing (Apple Maps suggestions) or by voice, on one screen; picking one shows it on the home screen, and its card starts navigation. |
| `HapticRemote/VoiceSearch.swift` | iPhone: the voice parts of the search screen ("06 Search · Listening" in Figma): speech recognition, the microphone circles and waveform that move with the voice, and the lookup of what was said. |
| `HapticRemote/Destination.swift` | iPhone: where the user is walking to (Centraal, or a place from search). |
| `HapticRemote/Compass.swift` | iPhone: which way the phone points. Turns the cone on the location dot and the pointer round the navigation dial. |
| `HapticRemote/RouteNavigator.swift` | iPhone: real walking navigation. Gets a walking route from MapKit and picks the signal from the GPS position (turns, wrong way, almost there, arrived, signal lost). |
| `HapticRemote/HomeView.swift` | iPhone: the home screen after the tutorial ("05 Home" in Figma). Still plays the watch's remote buttons on the phone. |
| `Shared/Palette.swift` | The Tandem colour palette. Compiled into both apps. |
| `HapticRemote/Typography.swift` | iPhone: the Atkinson Hyperlegible Next font (in `Fonts/`) and its sizes. |
| `HapticRemote/Onboarding/` | iPhone: the tutorial shown after installing (intro, six signals, practice, ready). The signal texts are in `TutorialSignal.swift`. |
| `HapticRemote Watch App/ConnectivityManager.swift` | Watch: receives patterns, and sends them when the watch is the remote. |
| `HapticRemote Watch App/HapticPlayer.swift` | Watch: plays the steps of a pattern. |
| `HapticRemote Watch App/RuntimeSessionManager.swift` | Watch: keeps the app alive with the wrist down. |
| `HapticRemote Watch App/ContentView.swift` | Watch: the two pages; the second (swipe up or turn the Digital Crown) shows the big arrow and title, and flashes. Starts the session. |
| `HapticRemote Watch App/RemoteView.swift` | Watch: the first page, the remote. Its buttons make the iPhone vibrate and switch its navigation screen. |
| `HapticRemote Watch App/Info.plist` | Watch: the `WKBackgroundModes` session type. |

## Signing with a free Apple ID (Personal Team)

1. Xcode → Settings → Accounts → **+** → Apple Account, and sign in.
2. Click the blue **HapticRemote** project at the top of the file list.
3. Select the **HapticRemote** target → **Signing & Capabilities** →
   tick **Automatically manage signing** → Team: **Your Name (Personal Team)**.
4. Do the same for the **HapticRemote Watch App** target. Use the same team.
5. If Xcode says the bundle identifier is not available, change it to something
   unique, for example `com.yourname.HapticRemote`. Then make these match:
   - Watch target bundle identifier: `com.yourname.HapticRemote.watchkitapp`
   - Watch target → Build Settings → search "companion" →
     **WKCompanionAppBundleIdentifier**: `com.yourname.HapticRemote`

The four test targets don't need signing. You never build them to run the app.

## Running on a real iPhone and Watch

1. **Developer Mode on the iPhone:** connect it to the Mac by cable, then on the
   phone go to Settings → Privacy & Security → Developer Mode → on. It restarts.
2. **Developer Mode on the Watch:** on the watch, Settings → Privacy & Security →
   Developer Mode → on. It restarts. The option only shows up after Xcode has
   seen the watch, so keep the phone connected, the watch unlocked and nearby,
   and open Xcode → Window → Devices and Simulators first.
3. In Xcode's toolbar choose the scheme **HapticRemote** and your iPhone as the
   destination, then press Run (⌘R). The first build to a new device is slow.
4. **Trust the developer profile:** the first launch fails with "Untrusted
   Developer". On the phone go to Settings → General → VPN & Device Management →
   your Apple ID → Trust.
5. Install the watch app: choose the scheme **HapticRemote Watch App** and your
   Apple Watch as the destination, then Run. This is the most reliable way. The
   first time, Xcode copies debug files from the watch, which can take
   10+ minutes.
6. Open the app on both devices. The phone should show three green checkmarks.
   Tap a pattern.

## The 7-day limit

Apps signed with a free Apple ID stop opening after 7 days. To fix it, connect
the phone and press Run in Xcode again for both schemes. **Re-install the day
before a demo.** A free account is also limited to 3 installed apps per device
and 10 new bundle identifiers per week, so don't rename the bundle ID often.

## Keeping the watch awake (the session)

Normally watchOS suspends an app a few seconds after you lower your wrist, and
the phone can no longer reach it. The watch app starts a
`WKExtendedRuntimeSession` by itself every time it comes on screen, so it keeps
running with the screen off.

The session type is set in `HapticRemote Watch App/Info.plist`
(`WKBackgroundModes`). An app can only have one type. This project uses
`mindfulness`:

| Type | Plist value | Max time | Behaviour |
| --- | --- | --- | --- |
| Self care | `self-care` | 10 min | App stays in front. |
| **Mindfulness** | `mindfulness` | 1 hour | App stays in front. Ends if you press the Digital Crown or open another app. |
| Physical therapy | `physical-therapy` | 1 hour | Keeps running in the background, even after you leave the app. |

Why mindfulness: the app stays the front app with the wrist down, which is the
state in which WatchConnectivity counts the watch as "reachable", so patterns
arrive live. Raising your wrist also shows the app (and the flash) instead of the
watch face. The cost is that pressing the crown ends the session.

Physical therapy survives leaving the app, but the app is then in the
background, where live delivery is less certain. To try it, change the plist
value to `physical-therapy`. No code change is needed.

After one hour the session expires. Raise your wrist or reopen the app to start
a new one: a session can only be started while the app is on screen.

## Adding a new pattern

Everything is in `Shared/Pattern.swift`:

1. Add a `case` to `enum Pattern`, for example `case triple`.
2. Add it to `title` and `symbol` (any SF Symbol name).
3. Add it to `steps`:

   ```swift
   case .triple:
       return [
           PatternStep(haptic: .click, delay: 0.3),
           PatternStep(haptic: .click, delay: 0.3),
           PatternStep(haptic: .click, delay: 0),
       ]
   ```

`delay` is the pause after that haptic, in seconds. Anything under 0.25 is raised
to 0.25, because watchOS drops haptics that are too close together. The new
phone lays its buttons out by hand, so also add a `patternButton(.triple)` line
in `HapticRemote/ContentView.swift`. Run both schemes again so the watch knows
the pattern too.

## Troubleshooting

**Watch not reachable**
- Open the app on the watch. Reachable means the watch app is running right now.
- Check Bluetooth is on for both, and the watch is unlocked and on your wrist.
- "Watch app installed" is red: see the install section below.
- Still stuck: force-quit both apps and open the watch app first, then the phone.
- The simulator pair is unreliable for WatchConnectivity. Test on real devices.

**Haptics not playing**
- The watch must be on your wrist and unlocked. It doesn't vibrate on a table or
  on the charger.
- Watch Settings → Sounds & Haptics → Haptic Alerts must be on.
- Check Do Not Disturb, Sleep and Theater Mode are off.
- The screen flashes but nothing is felt: it is a watch setting from this list,
  not the code.
- The phone says "queued": the watch was not reachable. The pattern plays when
  the watch app is next opened.
- Left and Right use Apple's navigation haptics, which are several taps long.
  Sending a new pattern cancels the remaining steps of the old one, but cannot
  stop a single haptic that has already started.

**App not installing on the watch**
- Run the **HapticRemote Watch App** scheme directly to the watch from Xcode.
- Developer Mode must be on for the watch, and the watch unlocked.
- Both targets must use the same team, and the bundle identifiers must match as
  described under signing.
- "Copying shared cache symbols" can sit for a long time on first connect. Keep
  the watch on its charger near the phone and wait.
- Out of options: restart watch, phone and Xcode, in that order. It is the usual fix.
- After 7 days the app needs re-installing (see above).
