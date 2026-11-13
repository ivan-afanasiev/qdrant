/// A resource whose construction is inert and whose initialization can be retried.
public protocol BootstrapResource: AnyObject, Sendable {
    func prepare() async throws
}
