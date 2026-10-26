# SKHTTPClient

A description of this package.

## Polling

Poll an endpoint at a fixed interval. The request is re-evaluated on every attempt, so headers such as authorization stay fresh. Polling can stop when a condition is met, after a maximum number of attempts, or on an overall timeout (`HTTPClientError` with `.pollingTimeout`). `maxConsecutiveFailures` sets how many failed requests in a row are tolerated before polling stops. Cancelling also cancels the in-flight request.

```swift
let configuration = HTTPClientPollingConfiguration(interval: 5, maxAttempts: 20, timeout: 120, maxConsecutiveFailures: 2)

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
