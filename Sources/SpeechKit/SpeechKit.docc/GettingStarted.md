# Getting Started

Configure ``SpeechService`` with the providers your app uses.

## Overview

SpeechKit uses Swift concurrency for all network work and SwiftUI observation for realtime transcript state. Most apps create one ``SpeechService`` and share it through SwiftUI's environment.

```swift
import Foundation
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!)
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
        }
    }
}
```

Inside a view, read the service from SwiftUI's `speechService` environment value.

```swift
struct ContentView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        Text(speech.transcriptText)
    }
}
```

Apps that use realtime microphone transcription must include the platform's microphone permission usage description in their app target.

Apple local Speech does not require an API key, but it requires iOS 26, macOS 26, or visionOS 26 and is unavailable on watchOS. See <doc:AppleLocalSpeech> for asset preparation and availability guidance.

The relay template is a self-hosted sibling repository, [speechkit-relay](https://github.com/SENTINELITE/speechkit-relay), not yet published. App Attest is the default and fails closed on unsupported devices. Configure the entitlement and deploy/review your relay before using this URL. For BYOK, native tokens, and existing login providers, see <doc:ShippingInProduction>. For source changes from 2.x, see <doc:MigratingTo3>.

## Topics

### Next Steps

- <doc:RealtimeTranscription>
- <doc:FileTranscription>
- <doc:AppleLocalSpeech>
- <doc:ProviderConfiguration>

- <doc:ShippingInProduction>
- <doc:MigratingTo3>
