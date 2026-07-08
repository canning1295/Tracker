# AGENTS.md

Instructions for coding agents working on Tracker.

## Project Snapshot

Tracker is a personal SwiftUI workout app for iPhone and Apple Watch. The iPhone app imports Apple Health workouts, summarizes training, edits activities, queues Strava uploads, and sends start/settings payloads to the Watch. The Watch app records HealthKit workouts, displays live metrics/maps/intervals, and notifies the phone after workout and route finalization.

The source of truth for targets and settings is `project.yml`, generated with XcodeGen. The checked-in `Tracker.xcodeproj` exists for convenience, but target membership, signing defaults, bundle IDs, schemes, and deployment settings should be changed in `project.yml` first, then regenerated.

Targets:

- `Tracker`: signed iPhone app target that embeds the Watch app for physical-device use.
- `TrackerPhoneOnly`: iPhone simulator smoke-test target for machines without a watchOS simulator runtime.
- `TrackerWatch`: watchOS app target.
- `TrackerWatchWidgets`: watchOS widget/complication extension.
- `TrackerCoreTests`: hostless unit tests for shared workout logic.

Key directories:

- `Shared/`: Codable models, settings storage, calculations, App Intents, Strava upload planning, TCX export, and logic shared by iOS, watchOS, and tests.
- `iOS/`: SwiftUI phone UI, `AppState`, HealthKit import, WatchConnectivity phone client, Strava OAuth/upload client, and Keychain storage.
- `Watch/`: SwiftUI watch UI, `WatchAppState`, HealthKit workout session manager, Crown menus, route/map presentation, and live controls.
- `WatchWidgets/`: complication launcher.
- `Tests/`: shared logic tests.
- `Scripts/verify-device-install.sh`: signed physical iPhone plus Watch install check.

## Branch Hygiene

Branch confusion is the main failure mode to avoid. Agents must verify identity before editing, committing, or pushing.

At the start of every task, run:

```sh
pwd
git status -sb
git branch --show-current
git remote -v
```

Expected public remote after publishing:

```text
origin  https://github.com/canning1295/Tracker.git
```

If the folder is not a git repository, stop unless the user has explicitly asked to initialize or publish it. If the branch is empty, detached, or unclear, stop and resolve that before edits.

Default branch policy:

- `main` is the public default branch.
- Do not do repair work directly on `main` after the initial public import.
- Create task branches from up-to-date `main` using `agent/YYYY-MM-DD-short-topic` or `repair/short-topic`.
- Before switching branches, run `git status -sb` and preserve uncommitted work. Never discard user changes.
- Before pushing, run `git fetch origin`, `git status -sb`, `git branch --show-current`, and `git log --oneline --decorate -5`.
- Confirm the active GitHub account is `canning1295` with `gh auth status` before creating remotes, pushing, or opening PRs.
- Never force-push `main`. Do not rewrite public history unless the user explicitly asks and the exact branch is named.

Commit scope rules:

- Stage explicit paths unless the worktree contains only intentional changes.
- Do not commit `build/`, `DerivedData/`, `.xcresult`, `.xcarchive`, provisioning profiles, certificates, `.p12` files, `xcuserdata/`, or local device identifiers.
- Do not mark a README verification claim as complete unless that exact command or device test was run in the current work.

## Public Repository Hygiene

This repository is intended to be public under `canning1295/Tracker`.

Never commit Strava client secrets, access tokens, refresh tokens, exported Keychain data, Apple provisioning profiles, certificates, or device-specific identifiers. Strava credentials are entered in-app and stored through Keychain. Physical-device IDs must be passed through `TRACKER_IPHONE_DEVICE` and `TRACKER_WATCH_DEVICE`, not hardcoded.

`project.yml` currently contains the local Apple Developer team ID and bundle identifier family. Treat changes to signing, bundle IDs, entitlements, or HealthKit capabilities as intentional release-affecting changes. If a different developer needs to build, prefer local Xcode signing changes or documented environment overrides unless the user asks to change the repository defaults.

## Build And Test Commands

Regenerate the Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

Run shared unit tests:

```sh
xcodebuild -project Tracker.xcodeproj -scheme TrackerCoreTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

Run the iPhone simulator smoke build:

```sh
xcodebuild -project Tracker.xcodeproj -scheme TrackerPhoneOnly -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
```

Run the watchOS SDK compile check:

```sh
xcodebuild -project Tracker.xcodeproj -target TrackerWatch -sdk watchos CODE_SIGNING_ALLOWED=NO build
```

Run the signed physical-device check only when the connected iPhone and Watch are available:

```sh
TRACKER_IPHONE_DEVICE="<iPhone CoreDevice identifier or name>" \
TRACKER_WATCH_DEVICE="<Apple Watch CoreDevice identifier or name>" \
Scripts/verify-device-install.sh
```

HealthKit entitlement warnings are expected in unsigned simulator builds using `CODE_SIGNING_ALLOWED=NO`. Real HealthKit recording, route writing, Action Button behavior, and Watch install/launch require signed physical-device validation.

## Implementation Guidance

Keep shared logic platform-neutral. Files in `Shared/` are compiled into iOS, watchOS, and test targets, so do not introduce UIKit, WatchKit, or unavailable framework imports there unless they are carefully gated.

Maintain Codable compatibility for persisted `WorkoutSettings`, `IntervalWorkout`, `ActivityEdit`, `StravaUploadRecord`, and related models. New persisted fields should decode with defaults using `decodeIfPresent` when older payloads may exist.

Use the existing state boundaries:

- `iOS/AppState.swift` owns phone-side app state, settings persistence, HealthKit refresh, Strava queue processing, and phone-to-watch requests.
- `Watch/WatchAppState.swift` owns watch-side settings synchronization and received start requests.
- `Watch/WorkoutSessionManager.swift` owns live HealthKit session behavior, location/route capture, pause/resume/end flow, haptics, and watch-to-phone completion notifications.
- `iOS/HealthKitClient.swift` owns HealthKit authorization, workout import, route/heart-rate/user-metric loading, and supported workout classification.
- `iOS/StravaClient.swift`, `Shared/WorkoutExporter.swift`, and `Shared/StravaUploadPlanner.swift` own Strava credential, upload, export, retry, edit, and duplicate-avoidance behavior.

When fixing behavior, prefer adding focused tests to `Tests/WorkoutCoreTests.swift` for pure logic in `Shared/`. For UI or hardware-dependent behavior, document the simulator build and physical-device validation that was run.

## XcodeGen Rules

Edit `project.yml` for target membership, schemes, entitlements paths, bundle IDs, build settings, deployment targets, or dependencies. Then run `xcodegen generate` and review the generated project diff. Avoid hand-editing `Tracker.xcodeproj/project.pbxproj` unless XcodeGen cannot represent the needed setting and the reason is documented.

## Known Constraints

The full `Tracker` scheme embeds the Watch app and is meant for signed physical-device testing. `TrackerPhoneOnly` exists for simulator UI checks when a watchOS simulator runtime is not installed. The Watch app can still be compile-verified with the watchOS SDK.

Strava end-to-end upload verification requires a real Strava API application and user authorization with `activity:write`. Do not fake a successful upload state in docs or tests unless the behavior is covered by local planner/export tests only.

## Repair Workflow

For each repair:

1. Verify branch, remote, and account before editing.
2. Read the affected files plus the relevant tested logic in `Tests/WorkoutCoreTests.swift`.
3. Make the smallest scoped change that fits the current architecture.
4. Regenerate Xcode only when `project.yml` changes.
5. Run the narrowest meaningful tests first, then the relevant build command.
6. Summarize exactly what changed, which branch it is on, what was verified, and what still needs physical-device validation.
