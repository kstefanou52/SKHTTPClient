import Foundation
@testable import SKHTTPClient

struct StubResponse {
    var statusCode: Int = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    /// Each chunk is delivered with a separate `didLoad` call. The Content-Type header stops URLSession
    /// from buffering the start of the body for content sniffing, which would merge the chunks.
    var chunks: [Data] = []
    
    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> StubResponse {
        StubResponse(statusCode: statusCode, chunks: [try! JSONEncoder().encode(value)])
    }
    
    static func status(_ statusCode: Int, data: Data = Data()) -> StubResponse {
        StubResponse(statusCode: statusCode, chunks: [data])
    }
}

/// Serves canned responses for any request and counts the requests it receives.
final class StubURLProtocol: URLProtocol {
    
    private static let lock = NSLock()
    private static var _requestCount = 0
    private static var _requests: [URLRequest] = []
    /// Receives the 1-based attempt number.
    static var responder: (Int) -> StubResponse = { _ in .status(200) }
    
    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestCount
    }
    
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }
    
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _requestCount = 0
        _requests = []
        responder = { _ in .status(200) }
    }
    
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
    
    /// A session that uses the library's delegate, needed for chunked responses.
    static func makeSession(configuration: URLSessionConfiguration = makeSessionConfiguration()) -> URLSession {
        URLSession(configuration: configuration, delegate: HTTPClientSessionDelegate(), delegateQueue: nil)
    }
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        Self._requests.append(request)
        let attempt = Self._requestCount
        let responder = Self.responder
        Self.lock.unlock()
        
        let stub = responder(attempt)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        guard stub.chunks.count > 1 else {
            stub.chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Space chunks out, otherwise URLSession may merge chunks loaded back to back into one delegate call.
        for (index, chunk) in stub.chunks.enumerated() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05 * Double(index)) {
                self.client?.urlProtocol(self, didLoad: chunk)
                if index == stub.chunks.count - 1 { self.client?.urlProtocolDidFinishLoading(self) }
            }
        }
    }
    
    override func stopLoading() {}
}
