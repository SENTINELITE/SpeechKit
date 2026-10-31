# Testing the demo against a Relay

Use this to try App Attest and Relay end to end with a test deployment of `speechkit-relay`.

## 1. Deploy a test relay

Do this in your clone of `speechkit-relay`. Use a separate Worker name so the test deployment never shares state with production.

1. In `wrangler.toml`, set `name = "speechkit-relay-demo"` and change these `[vars]`:

   ```toml
   AUTH_MODE = "appattest"
   APPLE_TEAM_ID = "9JJ9796LNX"
   APPLE_BUNDLE_IDS = "com.sentinelite.SpeechKitDemo"
   APP_ATTEST_ENV = "development"
   ```

   Builds run from Xcode attest in Apple's development environment. Production attestations are rejected while `APP_ATTEST_ENV` is `development`, and the reverse is also true.

2. Add the secrets. Wrangler prompts for each value, so nothing lands in shell history.

   ```sh
   npx wrangler secret put TICKET_SIGNING_KEY   # any random 32+ byte value, e.g. from `openssl rand -base64 48`
   npx wrangler secret put OPENAI_API_KEY       # repeat for each provider you want to test
   npx wrangler deploy
   ```

3. Check that it's up: `curl https://<worker>.workers.dev/speechkit/v1/info`

## 2. Run the demo on a real device

App Attest doesn't run in the Simulator; the Simulator reports `isSupported == false`.

1. Open `SpeechKitDemo.xcodeproj`, choose your iPhone as the destination, and run.
   - Signing is automatic with team `9JJ9796LNX`.
   - `SpeechKitDemo.entitlements` sets `com.apple.developer.devicecheck.appattest-environment` to `development`.
2. In the app, open **Settings → Relay**:
   - URL: `https://<worker>.workers.dev`, as the origin only, without a path.
   - Authentication: **App Attest**.
   - Tap **Enable Relay**.
3. Start any cloud workflow. The first request registers the device's App Attest key; requests after that send assertions.

## What to check

- **Registration and transcription:** registration succeeds, and one file transcription and one realtime session complete per provider you configured.
- **Keys:** with Relay enabled, provider screens say vendor keys aren't loaded.
- **Metering:** imported voice memos (M4A) transcribe, and `wrangler tail` shows the duration being metered, not a 415.
- **Wrong environment:** with `APP_ATTEST_ENV = "production"`, registration fails with `attestation_failed`. This confirms the environment check.

## Before TestFlight or the App Store

Switch the relay to `APP_ATTEST_ENV = "production"` and deploy the production Worker separately. Set the entitlement to `production` for those builds.
