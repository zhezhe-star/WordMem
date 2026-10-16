# TestFlight Distribution Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare WordMem for repeatable Apple TestFlight distribution through Xcode Cloud.

**Architecture:** Keep the existing SwiftUI app unchanged. Add App Store export-compliance metadata directly to the app's Info.plist, standardize the initial beta marketing version, and document the App Store Connect / Xcode Cloud / TestFlight setup and release procedure that cannot be fully automated from source alone.

**Tech Stack:** Swift/SwiftUI, Xcode 27.1, Xcode project build settings, property-list metadata, Xcode Cloud, App Store Connect, TestFlight.

**Spec:** The approved chat design specifies official TestFlight as the long-term distribution channel, Xcode Cloud automation, `ITSAppUsesNonExemptEncryption = NO`, an optional `0.1.0` beta version, and a `docs/testflight-release.md` runbook.

## Global Constraints

- Preserve all existing app behavior and files except distribution/configuration metadata.
- Do not implement iCloud synchronization or unrelated app features.
- Keep bundle identifier `zhezhe.WordMem`.
- Keep development team `C4JRX5Y34R`.
- Use marketing version `0.1.0` for the initial beta.
- Do not store Apple credentials, API keys, or secrets in the repository.
- Do not configure App Store Connect credentials in source control.

---

### Task 1: Add export-compliance and beta version metadata

**Files:**

- Modify: `WordMem/Info.plist`
- Modify: `WordMem.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Existing `Info.plist`, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION` build settings.
- Produces: `ITSAppUsesNonExemptEncryption = NO` in the built app's Info.plist and `MARKETING_VERSION = 0.1.0` for Debug and Release configurations.

- [x] **Step 1: Add export-compliance key**

Add:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

- [x] **Step 2: Set beta marketing version**

Change both target-level `MARKETING_VERSION` values from `1.0` to `0.1.0`.

- [x] **Step 3: Validate plist and build settings**

Run `plutil -lint WordMem/Info.plist`. Run a Debug simulator build and verify it exits successfully.

### Task 2: Document TestFlight setup and mobile release flow

**Files:**

- Create: `docs/testflight-release.md`

**Interfaces:**

- Consumes: Bundle ID, development team, Xcode Cloud concept, TestFlight groups.
- Produces: Operator-facing runbook for one-time setup, tester onboarding, and mobile-triggered releases.

- [x] **Step 1: Write one-time setup checklist**

Document creating the App Store Connect app record, connecting GitHub to Xcode Cloud, and creating the TestFlight beta group.

- [x] **Step 2: Write repeatable release checklist**

Document the mobile-friendly flow: merge/push to `release/testflight`, Xcode Cloud archives and uploads, testers update through TestFlight.

- [x] **Step 3: Review documentation against approved design**

Verify every approved flow element is represented and no unsupported automation claims are made.

- [x] **Step 4: Commit local preparation**

Commit Info.plist, project version, and documentation changes with a focused conventional commit.
