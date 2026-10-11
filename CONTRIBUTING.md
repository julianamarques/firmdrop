# How to Contribute

Thank you for your interest in contributing to FirmDrop. This guide describes the recommended workflow for proposing fixes, improvements and documentation changes.

## Workflow

- Fork the repository and clone the project.
- Create a branch from the main branch.
- Use descriptive branch names, such as `feature/feature-name` or
  `fix/short-description`.
- See `README.md` to build, package and run the app locally.
- Keep pull requests small and focused on one main change.
- In the pull request, explain the problem solved, the solution applied and how
  the change was validated.

## Commits

Write messages in English, short, in the imperative mood and with a prefix that
indicates the type of change ([Conventional Commits](https://www.conventionalcommits.org/)):

```text
feat: show the Android version of previous firmware versions
fix: resume downloads after the server rotates the nonce
refactor: move the download state machine into FirmDropCore
test: cover the version.xml parser
docs: update installation instructions
build: pin a newer auth_param.dat
chore: release v1.1.0
```

## Code Standards

- Follow the existing organization: everything that does not depend on the
  interface (FUS protocol, cryptography, download, update check) lives in
  `Sources/FirmDropCore`, with tests in `Tests/FirmDropCoreTests`; the SwiftUI
  app lives in `Sources/FirmDrop`.
- Do not add comments to Swift code: prefer clear names, small functions and
  explicit types. Scripts may have comments.
- The project uses the Swift 6 language mode, with strict concurrency
  checking. Do not introduce build warnings.
- New logic in `FirmDropCore` must come with tests.
- Treat everything that comes from the servers as untrusted: read XML with
  `XMLDocument.untrusted`, validate models, regions, versions, file names and
  paths with `Identifiers` and build local paths with
  `FirmwareDownload.localURLs`.
- User-facing strings are written in Brazilian Portuguese in the code and
  translated to English in `Resources/Localizable.xcstrings`. After adding or
  changing strings, run `scripts/sync-strings.sh` and fill in the translation;
  `swift test` fails while any string is untranslated or has placeholders
  (`%@`, `%lld`) that differ from the original.
- Do not commit `Resources/auth_param.dat` (downloaded by
  `scripts/fetch-auth-params.sh`), downloaded firmware, credentials or personal
  data.
- When updating `auth_param.dat`, change the commit in
  `scripts/fetch-auth-params.sh` and `paramsSHA256` in
  `Sources/FirmDropCore/Authenticator.swift` together.

## Validation

Before opening a pull request, run the checks that apply:

```sh
scripts/fetch-auth-params.sh   # once
swift build
swift test
FIRMDROP_LIVE=1 swift test     # when the change affects the protocol or the download
scripts/build-app.sh
```

Also check that:

- The change is limited to the proposed scope.
- The build produces no warnings and all tests pass.
- New rules have tests where applicable.
- The app was actually tested when the change affects search, download, pause and
  resume, or decryption.
- New strings show up correctly in Portuguese and in English.
- No credentials, tokens or personal data were committed.
- The documentation was updated when the change affects how the project is used.

## Pull Requests

When opening a pull request, include:

- A short summary of the change.
- The reason for the change.
- The commands run for validation.
- The models and regions (CSC) used in manual testing and the macOS version.
- Notes on compatibility impact, if any.

## Issues

To report vulnerabilities, do not open an issue: follow the
[security policy](SECURITY.md).

When opening an issue, include:

- A clear description of the problem or improvement.
- Steps to reproduce, for a bug.
- Expected and actual behavior.
- The FirmDrop version, the macOS version and whether the Mac is Apple Silicon or Intel.
- The model, region (CSC) and firmware version involved.
- The error message shown in the app, which can be selected and copied in the
  downloads list.
- For problems with the update check, the logs, which can be collected with:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.julianamarques.FirmDrop"' --info
```
