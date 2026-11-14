public enum AdapterError: Error, Equatable, Sendable {
    case authorization(String)
    case embedding(String)
    case vectorStore(String)
    case photoLibrary(String)
    case deletion(String)
    /// The user rejected the Photos deletion prompt.
    case deletionDeclined
}
