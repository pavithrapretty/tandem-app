# Destination voice search: Deepgram experiment

Apple Speech remains the default. Choose the provider in **Settings → Destination
voice search**. Both providers use the existing microphone animation, chimes,
haptics, transcript field, and destination lookup. Typed search remains available.
No new package dependency is required.

## Setup on a physical iPhone

1. Open this checkout's `HapticRemote.xcodeproj` in Xcode, select the
   **HapticRemote** scheme and your connected iPhone (iOS 17+). Configure your
   signing team locally; do not commit personal signing or provisioning changes.
   Enable Developer Mode on the phone if needed, then Run when ready to test.
   The existing bundle identifier replaces any installed copy with that identifier.
   Configure companion Watch signing too if your checkout builds the Watch target.
2. First test Apple Speech and allow microphone and speech recognition permissions.
3. Each teammate obtains their own Deepgram API key with speech-to-text access.
   On their own iPhone, open **Settings → Destination voice search → Deepgram**,
   enter it in the secure **Deepgram API key** field, and tap **Save key**.
   Do not put keys in source, Xcode schemes/build settings, environment files,
   screenshots, logs, review comments, or commits.
4. Deepgram requires an internet connection and streams microphone audio to
   Deepgram during voice search. This experiment uses Nova-3 with English (`en`).
   Deepgram requires microphone permission, not Apple Speech authorization.

The key is stored in the device's Keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; it is not synced or backed up.
The saved key is not displayed. Enter a replacement and tap **Save key**, or use
**Delete key**. Only the provider choice is saved in UserDefaults. Switching
providers does not delete the key. For a distributed app, use a backend that
issues short-lived credentials rather than a permanent key on the client.

## Manual checks

- With Apple Speech selected, speak a place or address. Check the listening chime,
  animated rings, speech haptics, live text, completion chime, and destination.
- Select Deepgram and repeat. Test pausing after speech and tapping the microphone
  to finish. It waits up to five seconds for final results before destination lookup.
  Try a multiword destination to check that final segments are retained.
- Select Deepgram without a saved key, with an invalid key, and with internet
  disabled. Confirm a clear error and **Try again**, **Use Apple Speech**, and
  **Type instead** actions. Restore connectivity/key and retry. Apple Speech may
  also need internet; switching providers is not a promise of offline recognition.
- Cancel or choose **Type instead** while listening or finishing; confirm that the
  microphone stops and no late transcript chooses a destination. Try restarting
  quickly, backgrounding the app, and interrupting audio with a phone call.
- Relaunch: check provider/key persistence, replacement, and deletion. Restore
  Apple Speech and delete the key when finished testing.

## Validation and review scope

All four changed Swift files passed syntax parsing. The speech implementation
passed scoped typechecking against the installed iPhone SDK; existing warnings
in unchanged `Transit.swift` remain. No packages were downloaded and no app or
simulator builds were run. Physical-device and live API checks remain to be done.

The change intentionally excludes local Xcode signing, scheme/Watch build changes,
workspace state, and unrelated README edits inherited by the experimental copy.
