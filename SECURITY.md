# Security Policy

SpeechKit is a client-side Swift package for speech-to-text integrations. The package does not require provider API keys at build time, and the demo stores user-entered keys in the local keychain.

## Supported Versions

Security fixes are prioritized for the latest public release and the current `main` branch.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| Latest tagged release | Yes |
| Older releases | Best effort |

## Reporting a Vulnerability

Please do not open a public issue for a suspected vulnerability.

Report security concerns by creating a private GitHub security advisory for this repository. Include:

- Affected version or commit.
- Platform and OS version.
- A minimal reproduction or affected API surface.
- Whether provider credentials, transcripts, local audio, or network requests are involved.
- Any logs or traces that do not contain secrets.

You should receive an initial response within 7 days. Confirmed vulnerabilities will be triaged by severity, fixed in `main`, and released with an advisory or release note when appropriate.

## Credential Safety

Do not commit real provider API keys, bearer tokens, `.netrc` credentials, transcripts containing private user data, or captured audio files. Examples and tests should use placeholders such as `<OPENAI_API_KEY>` or short fixture strings that cannot authenticate.

Apps that use SpeechKit should avoid shipping long-lived provider API keys directly in distributed clients. Prefer a server-side credential boundary, a short-lived token service when a provider supports it, or another backend proxy appropriate for your product.

## Scope

Security reports are in scope when they involve SpeechKit source code, package documentation, the demo app, credential handling in examples, transcript/audio data handling, or provider request construction.

Provider service availability, provider-side model behavior, account billing issues, and vulnerabilities in third-party services should be reported to the relevant provider unless SpeechKit is mishandling those integrations.
