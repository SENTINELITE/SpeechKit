// SpeechKit - Modular Voice API Framework

@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.UUID

/// A deprecated compatibility alias for ElevenLabs model identifiers.
@available(*, deprecated, message: "Use provider-scoped model types such as ElevenLabsModelID, AquaModelID, CohereModelID, or GrokModelID.")
public typealias SpeechModelID = ElevenLabsModelID
