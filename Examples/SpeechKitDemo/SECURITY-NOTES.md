# Demo privacy and verification

The demo accepts user-owned vendor keys or an explicitly enabled Relay. In direct mode it loads only the key for the provider about to run, preserving static-key authentication with opaque `.apiKey` credentials. It does not turn a saved key into a short-lived token. Keys stay in nonsynchronizable, WhenUnlockedThisDeviceOnly Keychain items. Existing device-local items migrate in place, without reading their values to populate settings. A failed save or removal leaves the previous UI status intact and shows an error. Saved keys are never displayed.

## Relay mode

Settings > Relay accepts an HTTPS origin, App Attest, a manually entered Bearer test token, or explicitly labelled development-only unauthenticated access. HTTP origins are limited to loopback. URL paths, queries, fragments and embedded credentials are rejected before replacing the service. No authentication fallback happens automatically. Unsupported App Attest is explained before enabling it, including the Simulator case; the SDK's runtime failure is also mapped to safe UI text.

The Bearer field is an empty, session-only replacement field. Enter a short-lived backend-issued sign-in token, not a vendor key or the SDK's internal Relay session ticket. The SDK performs the Relay session-ticket exchange. There is no integrated backend sign-in UI in this demo. The draft clears after Apply, on authentication changes, on disappearance and on scene inactivity. The resolver's access token has a five-minute local deadline; a timer calls `clearCredentials` at that deadline. The Relay must enforce the real token expiry and permissions. No secret is saved in UserDefaults or Keychain. This is a manual test mode, not production authentication or a claim that an arbitrary pasted token is short-lived on its issuing server.

Apply creates `SpeechService(relay:)`, stops and clears the previous service, and preserves the existing VOZ transcriber. The default provider set includes all nine cloud providers; only providers actually configured on the backend can succeed. Provider model/options still apply, but no vendor key is read in Relay mode. Proxy-all uses `.relayOnly`; optional vendor-token routing uses `.disallowStaticKeys` and `.vendorTokensWhenAvailable`. Unsupported token routes are left to the SDK's documented proxy behavior. This demo configures no public-key pins.

Only the validated origin, authentication choice and token-strategy preference are saved. Relay is never enabled automatically on launch. An expired or cleared Relay blocks cloud use until explicit reauthentication or Disable Relay, rather than silently falling back to saved vendor keys. Remove Key and key replacement call `clearCredentials`, including any Relay authorization on that service. Disable Relay clears it before restoring direct mode; it does not delete vendor keys from Keychain. Neither operation revokes credentials on a server or recalls audio already sent.

The UI displays bounded `SpeechFailure` categories, `SpeechFailureReason` values and safe Fish error cases, not arbitrary server or callback error text. HTTP authentication failures request reauthentication; rate limits request a delay rather than automatic audio replay. Unknown errors and VOZ model preparation failures use constant text.

Prompts, keywords, vocabulary, context bias, Fish Audio terms, and Apple contextual strings stay in the app session. Launch removes values saved by older versions. Settings > Clear private text also clears the current fields and those legacy preferences. Other provider choices and nonsecret options still use UserDefaults, declared with reason CA92.1 in the app privacy manifest. The manifest also declares C617.1 for modification dates read only on app-container files during expiry cleanup.

App-created dictation WAVs use `Library/Caches/SpeechKitDemo/Recordings`, excluded from backup, with complete file protection applied before capture. Failed starts, failed uploads, replacement, cancellation, provider changes and leaving the recording view discard the owned recording. A successful transcription keeps its WAV for an explicit export window of up to 15 minutes, ending earlier when export completes or is cancelled. Crash leftovers and legacy UUID-named temporary recordings expire after 24 hours on the next launch. The exporter releases its Data on completion or dismissal. Clearing references does not guarantee byte zeroization. File-import URLs and destinations chosen by the user are never deleted.

An opaque window covers all presentations in each inactive scene. Verify actual app-switcher snapshots, multiple scenes, permission alerts and lock/unlock on a device. This does not prevent screenshots or deliberate transcript copying/export.

## Updated smoke-test locations

These paths supersede the older Documents instructions in the demo README.

1. Copy fresh synthetic audio to `Library/Caches/SpeechKitDemo/SmokeTests/voz-smoke-input.aiff` in the app container. Create the directory if needed.
2. Launch a Debug build with `--voz-smoke-test`.
3. Collect `Library/Caches/SpeechKitDemo/SmokeTests/voz-smoke-result.json` within 15 minutes. It includes synthetic transcript content and timing.

The directory and files are protected and excluded from backup. The runner deletes its input after the attempt and its result after 15 minutes while the app runs. On later launches, files older than 15 minutes are removed. The old app-generated Documents result is removed on launch. Remove any old Documents input fixture manually. General file-import audio is never a smoke-test cleanup target.

## Checks available with Command Line Tools

From the repository root:

```sh
bash Examples/SpeechKitDemo/Verification/check-helpers.sh
bash Examples/SpeechKitDemo/Verification/check-migration.sh
GITLEAKS_BIN=/path/to/gitleaks python3 Examples/SpeechKitDemo/Verification/check-secret-scan.py
GITLEAKS_BIN=/path/to/gitleaks bash Examples/SpeechKitDemo/Verification/scan-secrets.sh
plutil -lint Examples/SpeechKitDemo/SpeechKitDemo.xcodeproj/project.pbxproj
plutil -lint Examples/SpeechKitDemo/SpeechKitDemo/PrivacyInfo.xcprivacy
```

The helper checks inject failed add/update/delete/read statuses, assert migration attributes and metadata-only presence queries, remove legacy preference values, and check storage expiry, file permissions, backup exclusion and preservation of an unrelated imported fixture. They never use real keys or access actual Keychain items.

The migration script builds the current SDK, then compiles and runs the actual demo configuration and credential store against that module with Swift 6 warnings treated as errors and a macOS 26 deployment target. It injects a synthetic credential store and never makes network requests. It checks all nine static-key credential kinds, selected-provider-only reads, Relay availability without vendor-key reads, token-strategy policies, five-minute expiry metadata, nonpersistence of the test token, explicit reset/clear/disable behavior, unsupported App Attest without fallback when unavailable on the host, URL rejection and error-text redaction. It does not wait five minutes to exercise the expiry timer or verify real backend token expiry.

On October 30, 2026, `swift build`, both verification scripts, a separate strict macOS typecheck of the configuration/store/private-text helpers and connection-state extension, and parsing all 24 app Swift files passed with Command Line Tools. The current build module is under the directory returned by `swift build --show-bin-path`, not the older cached `.build/arm64-apple-macosx/debug/Modules`. Both the pbxproj and privacy manifest pass `plutil -lint`. The project uses explicit groups, not file-system-synchronized groups; all 24 app Swift files are in the target Sources phase. The new verification executable is deliberately outside the app target. The local package symlink still resolves to the repository root. These checks do not typecheck the iOS SwiftUI app or replace an Xcode build. The SDK build emits a Command Line Tools developer-framework search-path warning.

CI installs gitleaks v8.30.0 from commit `6eaad039603a4de39fddd1cf5f727391efe9974e`. The scan suppresses all findings and prints only a pass/fail message. The synthetic verification uses a disposable repository and proves a canary on a custom checkpoint ref fails without printing its value. `--all` covers refs available in the checkout, including local `refs/t3/checkpoints/*`. Hosted CI cannot inspect private local refs, reflogs, unreachable objects or other copies. Run the local scan separately. No refs are rewritten or deleted by the scanner.

The demo still needs an Xcode build, archive privacy-report review including its dependencies, real Keychain migration/lock tests, audio-protection checks and snapshot tests. The local helper checks do not prove those device behaviors. Provider canaries need separately authorized disposable credentials.

## SpeechKit 3.0 migration points

`DemoConfiguration.prepare(_:for:)` is the only Keychain value-read path. All nine direct provider configurations now use opaque `.apiKey` credentials. Empty credentials in Relay provider configurations preserve option overrides while the SDK resolves Relay authorization. No credential getter is used. Do not wrap static vendor keys in a vendor-token resolver because that changes wire authentication.

`releaseAuthorization(from:)` drops per-operation provider configurations; their SDK setters invalidate pending work. `resetAuthorization(in:)` uses `resetSession` for Relay so ordinary navigation does not discard the explicitly configured authentication resolver, and `clearCredentials` for direct mode. Key removal/replacement, Disable Relay and test-token expiry use `clearAuthorization(in:)` and the SDK's full `clearCredentials` API. Reset discards SDK recordings and transcripts; ordinary Stop Speaking uses `stopListening` to preserve its intentional transcript/audio export window. Export completion/cancellation calls `discardRecording`. File and dictation views still cancel their tasks and ignore stale results.

Remaining acceptance requires an Xcode iOS build with the resolved SpeechKitVoz/Aurora dependencies, signed-device App Attest and backend environment/provisioning checks, real Keychain and protected-audio tests, background/lock expiry and pending-operation cancellation tests, and authorized provider canaries. Relay canaries must include Meta's handshake, Gemini large/background file routes, and both token strategies. Simulator testing must confirm that App Attest is unavailable without silently selecting another mode. No live Relay or provider calls were made for the local verification.
