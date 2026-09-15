import Foundation

/// A typed key for values that extension packages store on a ``SpeechService``.
///
/// Separate packages can attach their own state to a shared ``SpeechService``
/// without SpeechKit knowing the type. Declare one key per stored value and give
/// it a reverse-DNS name owned by the package that defines it, so two extension
/// packages cannot collide:
///
/// ```swift
/// extension SpeechServiceExtensionKey where Value == VozTranscriber {
///     static var vozTranscriber: Self {
///         SpeechServiceExtensionKey("com.example.SpeechKitVoz.transcriber")
///     }
/// }
/// ```
///
/// The `Value` type is part of the key's identity at compile time only. Reading a
/// key with a different `Value` than the one used to store it returns `nil`
/// rather than trapping.
public struct SpeechServiceExtensionKey<Value>: Sendable, Hashable {
    /// The unique name identifying the stored value.
    public let name: String

    /// Creates a key with a globally unique name.
    ///
    /// - Parameter name: A reverse-DNS name owned by the declaring package.
    public init(_ name: String) {
        self.name = name
    }
}

extension SpeechService {
    /// Reads or writes a value that an extension package associates with this service.
    ///
    /// Assigning `nil` removes the stored value. Because ``SpeechService`` is
    /// observable, SwiftUI views that read a key are invalidated when that key's
    /// value changes.
    ///
    /// - Parameter key: The key declared by the extension package.
    /// - Returns: The stored value, or `nil` when nothing is stored for `key` or
    ///   the stored value has a different type.
    public subscript<Value>(extension key: SpeechServiceExtensionKey<Value>) -> Value? {
        get { extensionStorage[key.name] as? Value }
        set {
            if let newValue {
                extensionStorage[key.name] = newValue
            } else {
                extensionStorage.removeValue(forKey: key.name)
            }
        }
    }
}
