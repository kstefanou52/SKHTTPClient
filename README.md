# SKHTTPClient

A lightweight HTTP client for Swift built on top of `URLSession`. It gives you one place to configure requests (base URL, common headers, authorization, JSON coding, logging) and lets you call your API in whichever style fits your code: closures, Combine, or async/await.

- JSON request bodies and `Decodable` responses, with typed error models
- Authorization: API key (header or URL), Basic, Bearer
- GET, POST, PUT, PATCH and DELETE
- Closures, Combine publishers and async/await
- Forward cache: get the cached response first, then the fresh one
- Chunked (streaming) responses
- Server-Sent Events
- WebSockets with automatic ping
- Cancellable polling
- Structured logging with `OSLog`

## Requirements

- iOS 14+ / macOS 11+
- Swift 5.5+

Some features need newer OS versions: Server-Sent Events need iOS 15 / macOS 12 (or iOS 18 / macOS 15 for the `any AsyncSequence` variant).

## Installation

### Swift Package Manager

In Xcode choose **File › Add Package Dependencies…** and enter:

```
https://github.com/kstefanou52/SKHTTPClient.git
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kstefanou52/SKHTTPClient.git", branch: "master")
],
targets: [
    .target(name: "MyApp", dependencies: ["SKHTTPClient"])
]
```

## Getting started

Create a client with your server URL. The usual pattern is to subclass `HTTPClient` and add one method per endpoint.

```swift
import SKHTTPClient

struct User: Decodable {
    let id: Int
    let name: String
}

struct APIError: Codable {
    let message: String
}

final class APIClient: HTTPClient {

    init() {
        super.init(serverURL: URL(string: "https://api.example.com")!)
        authorizationType = .bearer(token: "<token>")
    }

    func getUser(id: Int) async throws -> User {
        let request = createURLRequest(
            endPoint: serverURL.appendingPathComponent("users/\(id)"),
            method: .GET
        )
        return try await performURLDataTask(with: request, errorModelType: APIError.self)
    }
}
```

## Configuration

### Settings

`settings` is an overridable property. Override it in your subclass to change logging, the request timeout, or the JSON encoder/decoder.

```swift
final class APIClient: HTTPClient {

    override var settings: HTTPClientSettings {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return HTTPClientSettings(
            shouldLogRequest: true,
            shouldLogResponse: true,
            shouldMakeLoggingRequestPrivacyPublic: false,
            shouldMakeLoggingResponsePrivacyPublic: false,
            timeoutInterval: 30,
            customJSONEncoder: nil,
            customJSONDecoder: decoder
        )
    }
}
```

| Option | Default | Description |
| --- | --- | --- |
| `shouldLogRequest` | `true` | Log outgoing requests. |
| `shouldLogResponse` | `true` | Log responses, stream chunks, SSE events and WebSocket messages. |
| `shouldMakeLoggingRequestPrivacyPublic` | `false` | Mark logged request values as `.public` in `OSLog` (otherwise they are redacted outside the debugger). |
| `shouldMakeLoggingResponsePrivacyPublic` | `false` | Same, for responses. |
| `timeoutInterval` | `60` | Request timeout in seconds. |
| `customJSONEncoder` | `nil` | Encoder for request bodies. Defaults to `JSONEncoder()`. |
| `customJSONDecoder` | `nil` | Decoder for responses. Defaults to `JSONDecoder()`. |

### Common headers

`commonHeaders` is added to every request. It defaults to `Content-Type: application/json; charset=utf-8`. Headers you pass to `createURLRequest` override it.

```swift
commonHeaders["Accept-Language"] = "en"
```

### Authorization

Set `authorizationType` and it is applied to every request created with `createURLRequest`.

```swift
authorizationType = .bearer(token: "<token>")
authorizationType = .basicAuth(username: "user", password: "pass")
authorizationType = .apiKey(key: "X-API-Key", value: "<key>", addToProperty: .header)
authorizationType = .apiKey(key: "api_key", value: "<key>", addToProperty: .url)
authorizationType = HTTPClientConfigurations.AuthorizationType.none
```

### Custom URLSession

Pass your own session if you need a custom configuration (for example a `URLCache` for the forward cache):

```swift
let configuration = URLSessionConfiguration.default
configuration.urlCache = URLCache(memoryCapacity: 10_000_000, diskCapacity: 50_000_000)
let client = HTTPClient(serverURL: serverURL, session: URLSession(configuration: configuration))
```

Chunked responses rely on the built-in `HTTPClientSessionDelegate`. If you pass a session with a different delegate, that feature won't receive data.

## Creating requests

```swift
let request = createURLRequest(
    endPoint: serverURL.appendingPathComponent("users"),
    method: .POST,
    headers: ["X-Request-ID": UUID().uuidString],
    urlQuery: .dictionary(["page": 1, "limit": 20]),
    body: .encodable(NewUser(name: "Kostis"))
)
```

- `method`: `.GET`, `.POST`, `.PUT`, `.PATCH`, `.DELETE`
- `urlQuery`: `.dictionary([String: Any])` or `.items([URLQueryItem])`
- `body`:
  - `.encodable(value, encoder: nil)`: any `Encodable` value, with an optional encoder just for this request
  - `.dictionary([String: Encodable])`: a dictionary encoded as a JSON object
  - `.data(Data?)`: raw body data

`createURLRequest` returns `nil` if the body can't be encoded. Every perform method accepts a `URLRequest?` and reports an `.invalidRequest`/`.invalidResponse` error in that case.

## Performing requests

### async/await

```swift
// Decoded response
let user: User = try await performURLDataTask(with: request, errorModelType: APIError.self)

// No response body
try await performURLDataTask(with: request, errorModelType: APIError.self) as Void

// Raw data from a URL
let data = try await performURLDataTask(with: imageURL)
```

### Closures

Annotate the result type so the compiler can pick the overload:

```swift
performURLDataTask(with: request) { (result: Result<User, HTTPClientError<APIError>>) in
    switch result {
    case .success(let user): print(user)
    case .failure(let error): print(error.statusCode ?? -1, error.model?.message ?? "")
    }
}

// No response body
performURLDataTask(with: request) { (result: Result<Void, HTTPClientError<APIError>>) in }
```

`getURLDataTask(with:completion:)` returns the `URLSessionDataTask` without starting it, if you want to control it yourself.

### Combine

```swift
let publisher: AnyPublisher<User, Error>? = getPublisher(with: request)
let dataPublisher = getPublisher(for: imageURL)
```

## Error handling

Failures are reported as `HTTPClientError<ErrorModel>`:

```swift
do {
    let user: User = try await performURLDataTask(with: request, errorModelType: APIError.self)
} catch let error as HTTPClientError<APIError> {
    error.statusCode // HTTP status code, if a response was received
    error.model      // Your error model decoded from the response body, if it could be decoded
    error.type       // HTTPClientError.Code
}
```

`HTTPClientError.Code`:

| Case | Meaning |
| --- | --- |
| `.none` | The server returned a non-2xx status. Check `statusCode` and `model`. |
| `.invalidRequest` | The request was `nil` (e.g. the body could not be encoded). |
| `.invalidResponse` | The response was missing or not an HTTP response. |
| `.parsingError` | The response could not be decoded into the expected type. |
| `.otherError(Error?)` | A transport error from `URLSession`. |
| `.pollingTimeout` | Polling exceeded its overall timeout. |
| `.pollingMaxAttemptsReached` | Polling reached `maxAttempts` without meeting its condition. |
| `.AUTH_FAILED`, `.FAILED`, `.SERVICE_UNAVAILABLE` | Available for your own mapping. |

Errors that don't depend on your error model (such as `.invalidRequest` and the polling errors) are thrown as `HTTPClientError<String?>`.

## Forward cache

Get the cached response immediately (if the session's `URLCache` has one), then the fresh response from the network.

```swift
// async/await: yields the cached value first, then the network value
let stream: AsyncThrowingStream<User, Error> = performURLDataTaskWithForwardCache(
    with: request,
    errorModelType: APIError.self
)
for try await user in stream {
    render(user)
}

// Closure: the completion is called up to twice
performURLDataTaskWithForwardCache(with: request) { (result: Result<User, HTTPClientError<APIError>>) in }

// Combine
let publisher: AnyPublisher<User, Error>? = getPublisherWithForwardCache(with: request)
```

## Chunked responses

For endpoints that send several JSON objects over one response, each chunk is decoded and yielded as it arrives. Chunks that fail to decode are logged and skipped.

```swift
let stream: AsyncThrowingStream<Progress, Error> = performURLDataTask(
    with: request,
    errorModelType: APIError.self
)
for try await progress in stream {
    update(progress)
}
```

## Server-Sent Events

Read a `text/event-stream` response and decode each event's `data` field as JSON. The data type must be `Decodable`, `Sendable` and `Hashable`.

```swift
struct Message: Decodable, Sendable, Hashable {
    let text: String
}

let events: AsyncThrowingStream<ServerSentEventWithJSONData<Message>, Error> =
    try await getEventStreamWithJSONData(with: request)

for try await event in events {
    print(event.event ?? "message", event.id ?? "-", event.data?.text ?? "")
}
```

On iOS 18+ there is also a variant that returns `any AsyncSequence<ServerSentEventWithJSONData<T>, Error>`. Cancelling the task that iterates the stream closes the connection.

## WebSockets

`subscribe` opens a WebSocket, keeps listening for messages and, by default, sends a ping every 25 seconds. It returns the `URLSessionWebSocketTask`, which you use to send messages and to close the connection.

```swift
// Decodable messages (from binary frames)
let socket = try subscribe(with: request) { (event: Result<ChatMessage, Error>) in }

// Text messages
let socket = try subscribe(with: request) { (event: Result<String, Error>) in }

// Raw messages, custom ping interval
let socket = try subscribe(with: request, autoSendPing: true, pingInterval: 10) {
    (event: Result<URLSessionWebSocketTask.Message, Error>) in
}

socket.send(.string("hello")) { error in }
socket.cancel(with: .normalClosure, reason: nil)
```

Use a `ws://` or `wss://` URL for the request.

## Polling

Call an endpoint repeatedly at a fixed interval. The request is re-evaluated on every attempt, so headers such as authorization stay fresh. Cancelling also cancels the request in flight.

```swift
let configuration = HTTPClientPollingConfiguration(
    interval: 5,                  // seconds between requests
    maxAttempts: 20,              // nil = unlimited
    timeout: 120,                 // overall limit; throws .pollingTimeout
    maxConsecutiveFailures: 2,    // failed requests in a row tolerated; 0 = stop on first error
    firesImmediately: true        // first request without waiting `interval`
)
```

There are three ways to use it:

```swift
// 1. AsyncThrowingStream: stop by breaking the loop or cancelling the task
let task = Task {
    let stream: AsyncThrowingStream<JobStatus, Error> = client.poll(
        with: client.createURLRequest(endPoint: statusURL, method: .GET),
        errorModelType: APIError.self,
        configuration: configuration,
        until: { $0.state == .done }
    )
    for try await status in stream {
        update(status)
    }
}
task.cancel()

// 2. Closure based with a cancellable handle
let poller = client.startPolling(
    with: client.createURLRequest(endPoint: statusURL, method: .GET),
    errorModelType: APIError.self,
    configuration: configuration,
    onEvent: { (result: Result<JobStatus, Error>) in update(result) },
    onFinish: { print("Polling finished") }
)
poller.cancel()

// 3. Await the first response that satisfies the condition
let finalStatus: JobStatus = try await client.poll(
    with: client.createURLRequest(endPoint: statusURL, method: .GET),
    errorModelType: APIError.self,
    configuration: configuration,
    until: { $0.state == .done }
)
```

Notes:
- The stream ends normally when the condition is met, `maxAttempts` is reached, or it's cancelled. It throws on timeout or after too many failures in a row.
- `startPolling` callbacks are not called on the main thread. Releasing the `HTTPClientPoller` does not stop polling: call `cancel()`.

## Logging

Logs go through `OSLog` with the subsystem set to your bundle identifier and the category `Network`, so you can filter them in Console.app or Xcode. Each request, response, cached response, stream chunk, SSE event, WebSocket message and polling attempt is logged with an emoji prefix (📡 request, 🌍 network response, 💾 cached response, 📦 chunk, 📧 SSE event, ⚡️ WebSocket message, 🔁 polling attempt). Turn logging off or make values public through [`settings`](#settings).

## Testing

Run the tests on macOS:

```sh
swift test
```

Or on an iOS simulator:

```sh
xcodebuild test -scheme SKHTTPClient -destination 'platform=iOS Simulator,name=<device>'
```

The tests use a stub `URLProtocol` (`Tests/SKHTTPClientTests/Helpers/StubURLProtocol.swift`), so they don't touch the network.
