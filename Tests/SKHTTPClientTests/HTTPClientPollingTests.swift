import XCTest
@testable import SKHTTPClient

final class HTTPClientPollingTests: XCTestCase {
    
    private struct Status: Codable, Equatable {
        let value: Int
    }
    
    private var client: HTTPClient!
    private var request: URLRequest!
    private let fast = 0.05
    
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let serverURL = URL(string: "https://polling.test")!
        client = HTTPClient(serverURL: serverURL, session: session)
        request = client.createURLRequest(endPoint: serverURL.appendingPathComponent("status"), method: .GET)
    }
    
    func testStreamStopsWhenConditionIsMet() async throws {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        var values: [Int] = []
        let stream: AsyncThrowingStream<Status, Error> = client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast),
            until: { $0.value == 3 }
        )
        for try await status in stream { values.append(status.value) }
        
        XCTAssertEqual(values, [1, 2, 3])
        XCTAssertEqual(StubURLProtocol.requestCount, 3)
    }
    
    func testStreamStopsAtMaxAttempts() async throws {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        var values: [Int] = []
        let stream: AsyncThrowingStream<Status, Error> = client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast, maxAttempts: 2)
        )
        for try await status in stream { values.append(status.value) }
        
        XCTAssertEqual(values, [1, 2])
    }
    
    func testStreamThrowsOnTimeout() async {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        let stream: AsyncThrowingStream<Status, Error> = client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast, timeout: 0.3)
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected timeout")
        } catch let error as HTTPClientError<String?> {
            guard case .pollingTimeout = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
    
    func testStreamToleratesConsecutiveFailures() async throws {
        StubURLProtocol.responder = { attempt in
            attempt == 2 ? (500, Data()) : (200, try! JSONEncoder().encode(Status(value: attempt)))
        }
        
        var values: [Int] = []
        let stream: AsyncThrowingStream<Status, Error> = client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast, maxAttempts: 3, maxConsecutiveFailures: 1)
        )
        for try await status in stream { values.append(status.value) }
        
        XCTAssertEqual(values, [1, 3])
    }
    
    func testStreamThrowsAfterTooManyFailures() async {
        StubURLProtocol.responder = { _ in (500, Data()) }
        
        let stream: AsyncThrowingStream<Status, Error> = client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast, maxConsecutiveFailures: 1)
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected error")
        } catch let error as HTTPClientError<String> {
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }
    
    func testCancellingConsumerTaskStopsPolling() async throws {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        let task = Task {
            let stream: AsyncThrowingStream<Status, Error> = client.poll(
                with: self.request,
                errorModelType: String.self,
                configuration: .init(interval: fast)
            )
            for try await _ in stream {}
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = await task.result
        let countAfterCancel = StubURLProtocol.requestCount
        try await Task.sleep(nanoseconds: 300_000_000)
        
        XCTAssertGreaterThan(countAfterCancel, 0)
        XCTAssertEqual(StubURLProtocol.requestCount, countAfterCancel)
    }
    
    func testPollerCancelStopsCallbacksAndCallsOnFinish() async throws {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        let finished = expectation(description: "onFinish")
        
        let poller = client.startPolling(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast),
            onEvent: { (result: Result<Status, Error>) in
                if case .failure(let error) = result { XCTFail("Unexpected \(error)") }
            },
            onFinish: { finished.fulfill() }
        )
        
        try await Task.sleep(nanoseconds: 200_000_000)
        poller.cancel()
        await fulfillment(of: [finished], timeout: 2)
        
        XCTAssertTrue(poller.isCancelled)
        let countAfterCancel = StubURLProtocol.requestCount
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(StubURLProtocol.requestCount, countAfterCancel)
    }
    
    func testAsyncPollReturnsMatchingValue() async throws {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        let status: Status = try await client.poll(
            with: self.request,
            errorModelType: String.self,
            configuration: .init(interval: fast),
            until: { $0.value == 4 }
        )
        
        XCTAssertEqual(status, Status(value: 4))
    }
    
    func testAsyncPollThrowsWhenMaxAttemptsReached() async {
        StubURLProtocol.responder = { attempt in (200, try! JSONEncoder().encode(Status(value: attempt))) }
        
        do {
            let _: Status = try await client.poll(
                with: self.request,
                errorModelType: String.self,
                configuration: .init(interval: fast, maxAttempts: 2),
                until: { $0.value == 10 }
            )
            XCTFail("Expected error")
        } catch let error as HTTPClientError<String?> {
            guard case .pollingMaxAttemptsReached = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}

// MARK: - Stub

private final class StubURLProtocol: URLProtocol {
    
    private static let lock = NSLock()
    private static var _requestCount = 0
    static var responder: (Int) -> (Int, Data) = { _ in (200, Data()) }
    
    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestCount
    }
    
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _requestCount = 0
    }
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        let attempt = Self._requestCount
        Self.lock.unlock()
        
        let (statusCode, data) = Self.responder(attempt)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}
