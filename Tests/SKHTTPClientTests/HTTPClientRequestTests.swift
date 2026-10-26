import XCTest
@testable import SKHTTPClient

final class HTTPClientRequestTests: XCTestCase {
    
    private struct Payload: Codable, Equatable {
        let firstName: String
        let age: Int
    }
    
    private final class CustomSettingsClient: HTTPClient {
        override var settings: HTTPClientSettings {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return HTTPClientSettings(shouldLogRequest: false, timeoutInterval: 15, customJSONEncoder: encoder)
        }
    }
    
    private let serverURL = URL(string: "https://api.example.com")!
    private var endPoint: URL { serverURL.appendingPathComponent("users") }
    private var client: HTTPClient!
    
    override func setUp() {
        super.setUp()
        client = HTTPClient(serverURL: serverURL)
    }
    
    // MARK: - Method, Timeout, Headers
    
    func testMethodIsApplied() {
        for method in [HTTPClientConfigurations.Method.GET, .POST, .PUT, .PATCH, .DELETE] {
            let request = client.createURLRequest(endPoint: endPoint, method: method)
            XCTAssertEqual(request?.httpMethod, method.rawValue)
        }
    }
    
    func testTimeoutComesFromSettings() {
        XCTAssertEqual(client.createURLRequest(endPoint: endPoint, method: .GET)?.timeoutInterval, 60)
        
        let customClient = CustomSettingsClient(serverURL: serverURL)
        XCTAssertEqual(customClient.createURLRequest(endPoint: endPoint, method: .GET)?.timeoutInterval, 15)
    }
    
    func testCommonHeadersAreMergedAndOverriddenByRequestHeaders() {
        client.commonHeaders["Accept-Language"] = "en"
        
        let request = client.createURLRequest(
            endPoint: endPoint,
            method: .GET,
            headers: ["Accept-Language": "el", "X-Request-ID": "123"]
        )
        
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept-Language"), "el")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Request-ID"), "123")
    }
    
    // MARK: - Query
    
    func testDictionaryQuery() {
        let request = client.createURLRequest(endPoint: endPoint, method: .GET, urlQuery: .dictionary(["page": 2, "q": "swift"]))
        
        XCTAssertEqual(queryItems(of: request), ["page": "2", "q": "swift"])
        XCTAssertEqual(request?.url?.path, "/users")
    }
    
    func testItemsQueryKeepsOrder() {
        let items = [URLQueryItem(name: "b", value: "1"), URLQueryItem(name: "a", value: "2")]
        let request = client.createURLRequest(endPoint: endPoint, method: .GET, urlQuery: .items(items))
        
        XCTAssertEqual(request?.url?.query, "b=1&a=2")
    }
    
    // MARK: - Authorization
    
    func testBearerAuthorization() {
        client.authorizationType = .bearer(token: "abc")
        let request = client.createURLRequest(endPoint: endPoint, method: .GET)
        
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }
    
    func testBasicAuthorization() {
        client.authorizationType = .basicAuth(username: "user", password: "pass")
        let request = client.createURLRequest(endPoint: endPoint, method: .GET)
        
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjpwYXNz")
    }
    
    func testAPIKeyInHeader() {
        client.authorizationType = .apiKey(key: "X-API-Key", value: "secret", addToProperty: .header)
        let request = client.createURLRequest(endPoint: endPoint, method: .GET)
        
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-API-Key"), "secret")
        XCTAssertNil(request?.url?.query)
    }
    
    func testAPIKeyInURL() {
        client.authorizationType = .apiKey(key: "api_key", value: "secret", addToProperty: .url)
        let request = client.createURLRequest(endPoint: endPoint, method: .GET, urlQuery: .dictionary(["page": 1]))
        
        XCTAssertEqual(queryItems(of: request), ["page": "1", "api_key": "secret"])
        XCTAssertNil(request?.value(forHTTPHeaderField: "api_key"))
    }
    
    func testNoAuthorization() {
        client.authorizationType = HTTPClientConfigurations.AuthorizationType.none
        let request = client.createURLRequest(endPoint: endPoint, method: .GET)
        
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }
    
    // MARK: - Body
    
    func testEncodableBody() throws {
        let request = client.createURLRequest(endPoint: endPoint, method: .POST, body: .encodable(Payload(firstName: "Kostis", age: 3)))
        let body = try XCTUnwrap(request?.httpBody)
        
        XCTAssertEqual(try JSONDecoder().decode(Payload.self, from: body), Payload(firstName: "Kostis", age: 3))
    }
    
    func testEncodableBodyUsesPerRequestEncoder() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let request = client.createURLRequest(
            endPoint: endPoint,
            method: .POST,
            body: .encodable(Payload(firstName: "Kostis", age: 3), encoder: encoder)
        )
        
        XCTAssertEqual(try jsonObject(request?.httpBody)["first_name"] as? String, "Kostis")
    }
    
    func testEncodableBodyUsesSettingsEncoder() throws {
        let customClient = CustomSettingsClient(serverURL: serverURL)
        let request = customClient.createURLRequest(endPoint: endPoint, method: .POST, body: .encodable(Payload(firstName: "Kostis", age: 3)))
        
        XCTAssertEqual(try jsonObject(request?.httpBody)["first_name"] as? String, "Kostis")
    }
    
    func testDictionaryBody() throws {
        let request = client.createURLRequest(
            endPoint: endPoint,
            method: .POST,
            body: .dictionary(["name": "Kostis", "age": 3, "payload": Payload(firstName: "A", age: 1)])
        )
        let object = try jsonObject(request?.httpBody)
        
        XCTAssertEqual(object["name"] as? String, "Kostis")
        XCTAssertEqual(object["age"] as? Int, 3)
        XCTAssertEqual((object["payload"] as? [String: Any])?["firstName"] as? String, "A")
    }
    
    func testDataBody() {
        let data = Data("raw".utf8)
        let request = client.createURLRequest(endPoint: endPoint, method: .POST, body: .data(data))
        
        XCTAssertEqual(request?.httpBody, data)
    }
    
    // MARK: - Helpers
    
    private func queryItems(of request: URLRequest?) -> [String: String] {
        guard let url = request?.url else { return [:] }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
    
    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
