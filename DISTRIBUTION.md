# Distributing XCBuildStats

Goal: a `.dmg` people download and it **just works** — no Gatekeeper warnings.
That requires the app to be **signed with a Developer ID Application certificate**
and **notarized** by Apple. macOS flags anything downloaded from the internet
(`com.apple.quarantine`); notarization is what makes Gatekeeper let it through
silently.

> Note: an **"Apple Development"** certificate (the one most iOS devs already have)
> is for local development only and **cannot** notarize. You specifically need a
> **Developer ID Application** certificate, which comes from a **paid** Apple
> Developer Program membership.

## One-time setup

1. **Developer ID Application certificate.** Enroll in the Apple Developer Program
   ($99/year; **Individual** is enough — no D-U-N-S needed) at developer.apple.com,
   then create the cert in Xcode → Settings → Accounts → your account → Manage
   Certificates → **+ → Developer ID Application**. (If you already have access to a
   team that owns one, you can reuse it instead.) Verify:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   # e.g. Developer ID Application: Your Name (TEAMID)
   ```

2. **Notarization credential.** Either an **App Store Connect API key** (`.p8` +
   Key ID + Issuer ID) or an **Apple ID** + an **app-specific password**
   (appleid.apple.com). Store it once as a notarytool keychain profile:
   ```sh
   # API key:
   xcrun notarytool store-credentials XCBS_NOTARY \
     --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_UUID>
   # or Apple ID:
   xcrun notarytool store-credentials XCBS_NOTARY \
     --apple-id you@example.com --team-id <TEAMID> --password <app-specific-password>
   ```

## Build a notarized DMG

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
# → dist/XCBuildStats-<version>.dmg  (signed, notarized, stapled)
```

Share the `.dmg` (a GitHub release, Slack, Drive, …). Recipients open it, drag the
app to Applications, and launch — no warnings. Launch at login turns on
automatically on first run.

## Publishing a version

```sh
# bump MARKETING_VERSION in project.yml first, then:
git tag vX.Y && git push origin vX.Y
gh release create vX.Y dist/XCBuildStats-X.Y.dmg --title "XCBuildStats X.Y" --notes "…"
```
`scripts/release.sh` prints these commands with the real version at the end.

## Stopgap without a certificate

You can ship a working DMG today with no certificate:
```sh
./scripts/release.sh          # no DEV_ID → unsigned DMG in dist/
```
It runs fine, but because it isn't notarized the **first** launch is blocked by
Gatekeeper. Each user clears it once:
```sh
xattr -dr com.apple.quarantine /Applications/XCBuildStats.app
```
(or right-click the app in /Applications → **Open**). Fine for a small internal
group; switch to the notarized flow above once you have the cert.
