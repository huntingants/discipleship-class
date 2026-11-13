# Android app

The Android app is a Trusted Web Activity: it opens https://huntingants.github.io/discipleship-class/
in Chrome's engine, full screen. Changes to the website reach the app straight away, so a new APK is
only needed to change the app's name, icon or version, or to add the address-bar fix below.

- Package name: `io.github.huntingants.discipleshipclass` (never change it)
- Signing key: `discipleship-class.keystore`, alias `discipleship`. **Kept privately, not in this
  repository.** Every update must be signed with the same key.
- Signing key SHA-256 fingerprint:
  `20:DD:A5:D2:E8:80:BA:23:C1:5B:1B:52:02:AB:9E:12:AA:AF:26:A9:9B:C6:D6:2C:52:98:19:B0:2C:35:33:6A`

## Building a new version

Needs Java 17 and the Android SDK (platform 36, build-tools 35), or use Bubblewrap
(`npm i -g @bubblewrap/cli`), which can install them for you.

1. In `twa-manifest.json` and `app/build.gradle`, raise `appVersionCode` / `versionCode` by 1 and
   set a new version name.
2. Put the keystore next to this file (it is ignored by git).
3. `bubblewrap build` — or `gradlew assembleRelease bundleRelease`, then sign the APK with
   `apksigner` and the bundle with `jarsigner`.

## Removing the address bar (optional)

Create a public GitHub repository named `huntingants.github.io` containing an empty `.nojekyll`
file and `.well-known/assetlinks.json` with:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "io.github.huntingants.discipleshipclass",
    "sha256_cert_fingerprints": ["20:DD:A5:D2:E8:80:BA:23:C1:5B:1B:52:02:AB:9E:12:AA:AF:26:A9:9B:C6:D6:2C:52:98:19:B0:2C:35:33:6A"]
  }
}]
```

No new APK is needed: installed apps hide the bar once the file is live. If you later publish on
Google Play with Play App Signing, add Play's fingerprint to the same list too.
