# iBuild

A phone-first control plane for iOS and Flutter builds. The phone never compiles anything: it starts builds on remote Mac infrastructure, follows them live, and shows when they reach testers.

```
Your phone  ──►  Codemagic (Mac mini M2)  ──►  App Store Connect  ──►  TestFlight
   iBuild         build, test, sign, upload       processing             testers
```

The pipeline is drawn as a transit line: **Fetch → Test → Build → Upload → TestFlight**. The travelled part of the line fills in cobalt, the station the build is at pulses amber, and a failure stops the line in red at the station where it happened.

## What it does

- **Build & test** from the phone on any branch and workflow, with the version read from `pubspec.yaml` on that branch.
- **Live progress.** Steps update every few seconds; tap a step to read its log in a terminal-style view that follows along while it runs.
- **Cancel, rerun, download.** Cancel a running build, start the same branch and workflow again, and download `.ipa` or `.aab` artifacts through short-lived public links.
- **TestFlight status.** After a build uploads, iBuild watches App Store Connect until Apple finishes processing, then marks the last station done.
- **Tester groups.** List beta groups, create a public TestFlight invitation link, and copy it to share.
- **Repository detection.** Pick a GitHub repo and iBuild checks for `pubspec.yaml`, `ios/`, `android/` and `codemagic.yaml`, then fills in the workflow and bundle ID it finds.
- **Config generator.** No `codemagic.yaml` yet? Choose iOS, Android, and TestFlight, App Store or Ad Hoc distribution, preview the file, then copy it or commit it straight to the repo.
- **Demo mode** (on by default) runs everything against a simulated RecipEase project so the whole app can be explored before connecting any account.

## Getting started

Requires Flutter 3.27 or newer (Dart 3.6+).

```bash
./scripts/bootstrap.sh   # generates android/ and ios/, adds the INTERNET permission, runs pub get
flutter run
```

The repository keeps only `lib/`, `test/` and configuration; `bootstrap.sh` runs `flutter create .` to generate the platform folders so they always match your installed Flutter version. If you prefer to commit them, run the script once and commit the result.

## Connecting real accounts

Open **Settings**. Each connection is tested before it is saved, and saving a Codemagic token turns demo mode off.

| Service | What you need | Used for |
| --- | --- | --- |
| Codemagic | API token (Codemagic account settings, Integrations, Codemagic API) | Listing apps, starting, polling and canceling builds, logs, artifacts |
| GitHub | Fine-grained personal access token with read access to Contents and Metadata (add write access to Contents to commit `codemagic.yaml`) | Branches, `pubspec.yaml` version, workflow detection |
| App Store Connect | Team API key: issuer ID, key ID and the `.p8` file contents. Developer role can read builds; App Manager is needed for public links | TestFlight processing state, beta groups, public links |

GitHub and App Store Connect are optional. Without them the app still builds; it just shows less.

Then add a project: pick the Codemagic app, optionally link its repository, and choose the workflow. The workflow is the **key** in `codemagic.yaml` (for example `ios-testflight`), which is what the Codemagic API expects.

### Signing

iOS signing is handled where the Mac is. The generated config uses Codemagic's automatic signing (`ios_signing` with `distribution_type` and `bundle_identifier`) and an App Store Connect API key integration referenced by name. Set those up once in Codemagic's team settings, and every build from the phone signs and uploads without further steps.

## Demo mode

The demo project behaves like a real one: builds take about 40 seconds, logs stream in, uploads appear in TestFlight as processing and then ready. Builds on any `feature/` branch fail their tests on purpose, so the failure path can be seen too. Nothing leaves the device.

## Architecture

```
lib/
  app/        AppController (ChangeNotifier), AppScope (InheritedNotifier), theme
  models/     Build, BuildStep, Artefact, pipeline stations, Project, TestFlight
  services/   CiProvider + CodemagicService, SourceHost + GitHubService,
              StoreConnect + AppStoreConnectService, DemoWorld, YAML helpers,
              codemagic.yaml generator
  widgets/    TransitLine, StationDot, StepLine, shared panels
  screens/    Build, History, TestFlight, Settings, project setup, config generator
```

- **Provider interfaces.** `CiProvider`, `SourceHost` and `StoreConnect` are small interfaces. `DemoWorld` implements all three, and new CI backends (GitHub Actions, Bitrise, Xcode Cloud) slot in behind `CiProvider` without touching the UI.
- **Polling, not push.** A single ticker runs only while something is in flight (every 5 seconds for real builds, every second in demo mode) and stops when everything is settled.
- **API resilience.** Codemagic's REST API is in preview and has two build endpoints. iBuild tries the long-standing `api.codemagic.io/builds/:id` first and falls back to the newer `codemagic.io/api/v3/builds/:id`; the parser accepts both shapes.
- **Credentials** live in the iOS Keychain or Android Keystore via `flutter_secure_storage` and are only sent to the service they belong to. App Store Connect requests are signed on the device with a short-lived ES256 JWT.

## Tests

```bash
flutter test
```

Covers pipeline state mapping, Codemagic response parsing, YAML generation (round-tripped through the parser) and the transit line widget. GitHub Actions runs `flutter analyze` and `flutter test` on every push.

## Roadmap

- More CI providers behind `CiProvider`: GitHub Actions, Bitrise, Xcode Cloud.
- Push notifications when a build finishes, via Codemagic webhooks and a small relay.
- GitHub sign-in with the OAuth device flow instead of a pasted token.
- Optional backend for key custody, so App Store Connect keys never sit on the phone.
- Tester management: invite individual testers and add them to groups.
