# WordMem TestFlight Release Runbook

This project uses Apple TestFlight as the official beta-distribution channel. Xcode Cloud provides the repeatable build path, so a new beta can be triggered by pushing or merging to the release branch without needing a local Mac session.

## Distribution identity

| Value | Value |
| --- | --- |
| App name | WordMem |
| Bundle identifier | `com.zhezhe.wordmem` |
| Apple development team | `C4JRX5Y34R` |
| Marketing version | `0.1.0` |
| Export compliance key | `ITSAppUsesNonExemptEncryption = NO` |

`ITSAppUsesNonExemptEncryption = NO` records the current decision that WordMem does not expose non-exempt encryption requiring a separate export-compliance answer. Revisit this setting before release if the app adds custom cryptography, non-system payment/security code, or other regulated encryption functionality.

## One-time App Store Connect setup

Complete these steps once in a browser while signed in to the Apple account for team `C4JRX5Y34R`:

1. Open [App Store Connect](https://appstoreconnect.apple.com/).
2. Confirm that the `com.zhezhe.wordmem` App ID exists under **Certificates, IDs & Profiles**. Create it from the explicit App ID if necessary.
3. Create the App Store Connect app record under **Apps**:
   - Platform: iOS
   - Name: `WordMem`
   - Primary language: Simplified Chinese
   - Bundle ID: `com.zhezhe.wordmem`
   - SKU: `WORDMEM1`
4. Confirm the created App Store Connect Apple ID is `6823975529`, then open the app and select the **Xcode Cloud** section.
5. Connect the GitHub account/repository `zhezhe-star/WordMem` and grant Xcode Cloud access when GitHub prompts for authorization.

## One-time Xcode Cloud workflow setup

Create a workflow named `TestFlight Beta` in the WordMem Xcode Cloud product:

1. **Branch changes**
   - Start the workflow when a branch is updated.
   - Track `release/testflight`.
   - Do not start this workflow from feature branches.
2. **Conditions**
   - Start on push.
   - Restrict source changes to the repository so that all approved app changes produce a beta.
3. **Archive action**
   - Project: `WordMem.xcodeproj`
   - Scheme: `WordMem`
   - Configuration: Release
   - Destination: an iOS device destination selected by Xcode Cloud
4. **Post-actions**
   - Add **Distribute** / **TestFlight**.
   - Upload to the internal WordMem TestFlight group initially.
   - After the first external review succeeds, add the external `WordMem Beta` group.
5. **Version and build number**
   - Keep `MARKETING_VERSION` under source control.
   - Let Xcode Cloud set the upload build number automatically or use its current-build-number increment action. Do not hand-edit build numbers in source for every test build.

Xcode Cloud manages signing for the upload after App Store Connect authorization. Do not store signing certificates, App Store Connect API keys, or Apple credentials in the repository.

## One-time TestFlight tester setup

1. In App Store Connect, open the app and go to **TestFlight**.
2. Create an external group named `WordMem Beta`.
3. Invite the tester by email, or create an invitation link if you prefer not to maintain a tester list.
4. Complete the first-build test information:
   - Beta App Description
   - Beta App Review Notes
   - Review contact information
5. Submit the first external build for Beta App Review if TestFlight requests it.

Testers install Apple's TestFlight app from the App Store, accept the invitation, and then install WordMem. External testers need only an Apple ID; they do not need access to the source repository or App Store Connect.

## Repeatable mobile release flow

After the one-time setup, use this flow for normal beta updates:

1. Merge reviewed changes into `main`.
2. Merge or fast-forward `release/testflight` to the approved `main` commit.
3. Push `release/testflight` to GitHub, or create and merge a pull request whose base branch is `release/testflight`.
4. Xcode Cloud detects the branch update and runs the `TestFlight Beta` workflow.
5. Confirm that the build completes and the artifact reaches TestFlight processing.
6. Tell the tester that a new build is available. TestFlight can update automatically, or the tester can open TestFlight and tap **Update**.

Equivalent local commands:

```sh
git fetch origin
git switch release/testflight
git merge --ff-only origin/main
git push origin release/testflight
```

The branch does not need to exist before the first setup; create it from the first approved distribution commit and push it with `-u`:

```sh
git switch -c release/testflight
git push -u origin release/testflight
```

## Build verification before merging

Run a simulator build before merging a change intended for TestFlight:

```sh
env DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer' \
  xcodebuild \
  -project WordMem.xcodeproj \
  -scheme WordMem \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ReleaseVerification \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build
```

Expect the final line to be `** BUILD SUCCEEDED **`. This local check validates compilation and metadata generation; it does not replace Xcode Cloud archive signing or App Store Connect upload validation.

## Failure checklist

| Symptom | Check |
| --- | --- |
| No workflow starts | `release/testflight` was updated and Xcode Cloud is connected to the GitHub repository. |
| Upload fails at signing | The App Store Connect app record, bundle ID, and Xcode Cloud authorization all use team `C4JRX5Y34R`. |
| Build missing in TestFlight | Wait for processing, then inspect the App Store Connect TestFlight build list and Xcode Cloud post-action logs. |
| External tester has no build | The build was added to the external group and the first external Beta App Review is approved. |
| Export-compliance prompt reappears | Confirm `ITSAppUsesNonExemptEncryption` remains `NO`, or update it and the runbook if the app's encryption scope changed. |
