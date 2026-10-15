# Working on Mac Authenticator

## Scope and architecture

Native SwiftUI application for macOS 14+, Swift tools 6.0 / Swift 5 language mode. No third-party runtime dependencies, server, telemetry, or cloud account.

- `Sources/AuthenticatorCore`: OTP generation, Base32, Google migration protobuf, QR decoding (Vision), Keychain persistence.
- `Sources/MacAuthenticator`: SwiftUI/AppKit UI, application state, LocalAuthentication, camera scanning.
- `Tests/AuthenticatorCoreTests/main.swift`: executable regression suite, including RFC 4226/6238 vectors and an isolated temporary Keychain namespace.
- `scripts/make-fixtures.py`: independent encoder for public synthetic migration fixtures.
- `Resources/Info.plist`: bundle metadata. `VERSION` is the release version source of truth.
- `scripts/build-app.sh`, `scripts/package-release.sh`: build and package the app.
- `.github/workflows/build.yml`: native tests and release packages for Apple Silicon and Intel; publishes releases for `v*` tags.

## Validation

Run commands from the repository root:

```sh
python3 scripts/make-fixtures.py --check
swift run AuthenticatorChecks
./scripts/build-app.sh
./scripts/package-release.sh
```

Use `swift run AuthenticatorChecks`, not `swift test`: the suite deliberately works with Command Line Tools without XCTest. Never replace an actual failing test with a skipped assertion. For parser/OTP/storage changes add focused regression coverage and run the suite. For UI changes also build and inspect the affected flow with synthetic accounts. `--demo` uses public test keys and does not write to the real vault.

Release checks must cover the packaged app: bundle version, CPU architecture, valid local signature, ZIP/DMG contents, and checksums. Passing source compilation alone does not establish a usable release. Do not modify the installed app in `~/Applications` as a side effect of building or testing.

## Credentials and data

- Never commit, print, upload, or embed real OTP secrets, user export QR images, decoded migration URIs, Keychain contents, personal account names, or credentials in fixtures, logs, screenshots, issues, artifacts, or releases.
- Use only generated synthetic fixtures and RFC test vectors. Reproduce parser problems with anonymized synthetic examples.
- Tests must use `local.macauthenticator.test.<UUID>` and delete only their own temporary items. Never clear or replace the production vault.
- Preserve the production bundle identifier and Keychain service/account identifiers unless an explicit migration is implemented and verified.
- Treat import data as untrusted. Keep size bounds, strict parameter validation, full multi-QR assembly, duplicate handling, and atomic persistence. Support export versions 1 and 2, missing batch IDs, and empty account names.
- Keep processing local. Do not send QR images, secrets, or generated codes to external services.
- Preserve fail-closed storage handling, authentication on unlock, and clipboard ownership checks.

## Release workflow

Keep `VERSION` in `MAJOR.MINOR.PATCH` format. A pushed `vMAJOR.MINOR.PATCH` tag must match `VERSION`. PRs and main pushes test/build on both native architectures and upload workflow artifacts. Tagged builds create a draft release, attach all archives and `SHA256SUMS.txt`, then publish only after both architecture jobs pass.

Use explicit file staging and inspect the complete diff before the first public push. Workflow tokens use read-only permissions except the release publishing job. Pin third-party actions to immutable commit SHAs. Never place signing credentials in repository files or command logs. Ad-hoc signing is not Developer ID signing or Apple notarization; documentation and release notes must say which was performed.

Default release commands after the desired commit has passed CI:

```sh
git tag -a "v$(cat VERSION)" -m "Mac Authenticator $(cat VERSION)"
git push origin "v$(cat VERSION)"
```

Check the live Actions result and download the published assets to verify them before reporting release completion. Do not overwrite an existing published version; use a new version for a changed binary.
