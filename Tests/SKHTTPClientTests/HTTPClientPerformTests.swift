import XCTest
import Combine
@testable import SKHTTPClient

final class HTTPClientPerformTests: XCTestCase {
    
    private struct User: Codable, Equatable {
        let id: Int
        let name: String
    }
    
    private struct APIError: Codable, Equatable {
        let message: String
    }
    
    private struct Message: Codable, Hashable, Sendable {
        let text: String
    }
    
    private let serverURL = URL(string: "https://api.example.com")!
    private var client: HTTPClient!
    private var request: URLRequest!
    private var cancellables: Set<AnyCancellable> = []
    
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = HTTPClient(serverURL: serverURL, session: StubURLProtocol.makeSession())
        request = client.createURLRequest(endPoint: serverURL.appendingPathComponent("users/1"), method: .GET)
    }
    
    override func tearDown() {
        cancellables = []
        super.tearDown()
    }
    
    // MARK: - async/await
    
    func testAsyncDecodesResponse() async throws {
        StubURLProtocol.responder = { _ in .json(User(id: 1, name: "Kostis")) }
        
        let user: User = try await client.performURLDataTask(with: request, errorModelType: APIError.self)
        
        XCTAssertEqual(user, User(id: 1, name: "Kostis"))
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/users/1")
    }
    
    func testAsyncVoidSucceedsWithJSONBody() async throws {
        StubURLProtocol.responder = { _ in .status(200, data: Data("{}".utf8)) }
        
        try await client.performURLDataTask(with: request, errorModelType: APIError.self) as Void
    }
    
    func testAsyncRawData() async throws {
        StubURLProtocol.responder = { _ in .status(200, data: Data("raw".utf8)) }
        
        let data = try await client.performURLDataTask(with: serverURL)
        
        XCTAssertEqual(data, Data("raw".utf8))
    }
    
    func testNon2xxReturnsStatusCodeAndErrorModel() async {
        StubURLProtocol.responder = { _ in .json(APIError(message: "Not found"), statusCode: 404) }
        
        do {
            let _: User = try await client.performURLDataTask(with: request, errorModelType: APIError.self)
            XCTFail("Expected error")
        } catch let error as HTTPClientError<APIError> {
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertEqual(error.model, APIError(message: "Not found"))
            guard case .none = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
    
    func testUndecodableResponseReturnsParsingError() async {
        StubURLProtocol.responder = { _ in .status(200, data: Data("{\"unexpected\":true}".utf8)) }
        
        do {
            let _: User = try await client.performURLDataTask(with: request, errorModelType: APIError.self)
            XCTFail("Expected error")
        } catch let error as HTTPClientError<APIError> {
            XCTAssertEqual(error.statusCode, 200)
            guard case .parsingError = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
    
    func testNilRequestReturnsInvalidResponse() async {
        do {
            let _: User = try await client.performURLDataTask(with: nil, errorModelType: APIError.self)
            XCTFail("Expected error")
        } catch let error as HTTPClientError<APIError> {
            guard case .invalidResponse = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }
    
    func testCustomDecoderFromSettings() async throws {
        final class SnakeCaseClient: HTTPClient {
            override var settings: HTTPClientSettings {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return HTTPClientSettings(customJSONDecoder: decoder)
            }
        }
        struct Profile: Decodable { let firstName: String }
        
        StubURLProtocol.responder = { _ in .status(200, data: Data("{\"first_name\":\"Kostis\"}".utf8)) }
        let snakeCaseClient = SnakeCaseClient(serverURL: serverURL, session: StubURLProtocol.makeSession())
        
        let profile: Profile = try await snakeCaseClient.performURLDataTask(with: request, errorModelType: APIError.self)
        
        XCTAssertEqual(profile.firstName, "Kostis")
    }
    
    // MARK: - Closures
    
    func testClosureSuccess() {
        StubURLProtocol.responder = { _ in .json(User(id: 1, name: "Kostis")) }
        let completed = expectation(description: "completion")
        
        client.performURLDataTask(with: request) { (result: Result<User, HTTPClientError<APIError>>) in
            XCTAssertEqual(try? result.get(), User(id: 1, name: "Kostis"))
            completed.fulfill()
        }
        
        wait(for: [completed], timeout: 2)
    }
    
    func testClosureFailure() {
        StubURLProtocol.responder = { _ in .json(APIError(message: "Unauthorized"), statusCode: 401) }
        let completed = expectation(description: "completion")
        
        client.performURLDataTask(with: request) { (result: Result<User, HTTPClientError<APIError>>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.statusCode, 401)
                XCTAssertEqual(error.model?.message, "Unauthorized")
            } else {
                XCTFail("Expected failure")
            }
            completed.fulfill()
        }
        
        wait(for: [completed], timeout: 2)
    }
    
    // MARK: - Combine
    
    func testPublisherDecodesResponse() throws {
        StubURLProtocol.responder = { _ in .json(User(id: 1, name: "Kostis")) }
        let received = expectation(description: "value")
        
        let publisher: AnyPublisher<User, Error> = try XCTUnwrap(client.getPublisher(with: request))
        publisher
            .sink(receiveCompletion: { _ in }, receiveValue: { user in
                XCTAssertEqual(user, User(id: 1, name: "Kostis"))
                received.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [received], timeout: 2)
    }
    
    // MARK: - Forward Cache
    
    func testForwardCacheYieldsCachedThenNetworkResponse() async throws {
        let configuration = StubURLProtocol.makeSessionConfiguration()
        configuration.urlCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        client = HTTPClient(serverURL: serverURL, session: StubURLProtocol.makeSession(configuration: configuration))
        
        let cachedResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        configuration.urlCache?.storeCachedResponse(
            CachedURLResponse(response: cachedResponse, data: try JSONEncoder().encode(User(id: 1, name: "Cached"))),
            for: request
        )
        StubURLProtocol.responder = { _ in .json(User(id: 1, name: "Fresh")) }
        
        var names: [String] = []
        let stream: AsyncThrowingStream<User, Error> = client.performURLDataTaskWithForwardCache(
            with: request,
            errorModelType: APIError.self
        )
        for try await user in stream { names.append(user.name) }
        
        XCTAssertEqual(names, ["Cached", "Fresh"])
    }
    
    func testForwardCacheWithoutCacheYieldsNetworkResponseOnly() async throws {
        StubURLProtocol.responder = { _ in .json(User(id: 1, name: "Fresh")) }
        
        var names: [String] = []
        let stream: AsyncThrowingStream<User, Error> = client.performURLDataTaskWithForwardCache(
            with: request,
            errorModelType: APIError.self
        )
        for try await user in stream { names.append(user.name) }
        
        XCTAssertEqual(names, ["Fresh"])
    }
    
    // MARK: - Chunked Responses
    
    func testChunkedResponseYieldsEachChunk() async throws {
        StubURLProtocol.responder = { _ in
            StubResponse(chunks: [
                try! JSONEncoder().encode(User(id: 1, name: "A")),
                try! JSONEncoder().encode(User(id: 2, name: "B"))
            ])
        }
        
        var ids: [Int] = []
        let stream: AsyncThrowingStream<User, Error> = client.performURLDataTask(with: request, errorModelType: APIError.self)
        for try await user in stream { ids.append(user.id) }
        
        XCTAssertEqual(ids, [1, 2])
    }
    
    // MARK: - Server-Sent Events
    
    func testServerSentEventsAreDecoded() async throws {
        let body = """
        event: greeting
        id: 1
        data: {"text":"hello"}
        
        data: {"text":"world"}
        
        
        """
        StubURLProtocol.responder = { _ in
            StubResponse(headers: ["Content-Type": "text/event-stream"], chunks: [Data(body.utf8)])
        }
        
        var events: [ServerSentEventWithJSONData<Message>] = []
        let stream: AsyncThrowingStream<ServerSentEventWithJSONData<Message>, Error> =
            try await client.getEventStreamWithJSONData(with: request)
        for try await event in stream { events.append(event) }
        
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.event, "greeting")
        XCTAssertEqual(events.first?.id, "1")
        XCTAssertEqual(events.map { $0.data?.text }, ["hello", "world"])
    }
    
    func testServerSentEventsThrowOnNon2xx() async {
        StubURLProtocol.responder = { _ in .status(500) }
        
        do {
            let _: AsyncThrowingStream<ServerSentEventWithJSONData<Message>, Error> =
                try await client.getEventStreamWithJSONData(with: request)
            XCTFail("Expected error")
        } catch let error as HTTPClientError<String?> {
            guard case .invalidResponse = error.type else { return XCTFail("Unexpected \(error.type)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
