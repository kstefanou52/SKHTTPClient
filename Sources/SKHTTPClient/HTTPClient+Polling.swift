//
//  HTTPClient+Polling.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

// MARK: - Polling

public extension HTTPClient {
    
    /// Polls the given request and yields every successfully decoded response.
    /// The request is re-evaluated on every attempt, so headers such as authorization stay fresh.
    /// Polling stops when `condition` returns true, `maxAttempts` is reached, the consumer stops iterating
    /// or its task is cancelled. It throws on `timeout` or after more than `maxConsecutiveFailures` failed requests.
    func poll<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: @escaping @autoclosure () -> URLRequest?,
        errorModelType: ErrorModel.Type,
        configuration: HTTPClientPollingConfiguration = .init(),
        until condition: ((ResponseModel) -> Bool)? = nil
    ) -> AsyncThrowingStream<ResponseModel, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await self.runPollingLoop(
                                request: request,
                                errorModelType: errorModelType,
                                configuration: configuration,
                                condition: condition,
                                continuation: continuation
                            )
                        }
                        
                        if let timeout = configuration.timeout {
                            group.addTask {
                                try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                                throw HTTPClientError<String?>(type: .pollingTimeout)
                            }
                        }
                        
                        try await group.next()
                        group.cancelAll()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if self.settings.isLoggingResponseEnabled {
                        self.logger.error("❌ - Polling stopped with error: \(error.localizedDescription)")
                    }
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Starts polling and reports every response through `onEvent`.
    /// A terminal error is reported once as `.failure`; cancellation is not reported as an error.
    /// `onFinish` is called when polling ends for any reason. Callbacks are not called on the main thread.
    @discardableResult
    func startPolling<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: @escaping @autoclosure () -> URLRequest?,
        errorModelType: ErrorModel.Type,
        configuration: HTTPClientPollingConfiguration = .init(),
        until condition: ((ResponseModel) -> Bool)? = nil,
        onEvent: @escaping (Result<ResponseModel, Error>) -> Void,
        onFinish: (() -> Void)? = nil
    ) -> HTTPClientPoller {
        let task = Task {
            let stream: AsyncThrowingStream<ResponseModel, Error> = poll(
                with: request(),
                errorModelType: errorModelType,
                configuration: configuration,
                until: condition
            )
            
            do {
                for try await response in stream {
                    guard !Task.isCancelled else { break }
                    onEvent(.success(response))
                }
            } catch is CancellationError {
            } catch {
                onEvent(.failure(error))
            }
            onFinish?()
        }
        return HTTPClientPoller(task: task)
    }
    
    /// Polls until a response satisfies `condition` and returns it.
    /// Throws `.pollingMaxAttemptsReached` if `maxAttempts` is reached first, `.pollingTimeout` on timeout
    /// and `CancellationError` if the calling task is cancelled.
    func poll<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: @escaping @autoclosure () -> URLRequest?,
        errorModelType: ErrorModel.Type,
        configuration: HTTPClientPollingConfiguration = .init(),
        until condition: @escaping (ResponseModel) -> Bool
    ) async throws -> ResponseModel {
        let stream: AsyncThrowingStream<ResponseModel, Error> = poll(
            with: request(),
            errorModelType: errorModelType,
            configuration: configuration,
            until: condition
        )
        
        for try await response in stream where condition(response) {
            return response
        }
        
        try Task.checkCancellation()
        throw HTTPClientError<String?>(type: .pollingMaxAttemptsReached)
    }
}

// MARK: - Polling Helpers

private extension HTTPClient {
    
    func runPollingLoop<ResponseModel: Decodable, ErrorModel: Codable>(
        request: @escaping () -> URLRequest?,
        errorModelType: ErrorModel.Type,
        configuration: HTTPClientPollingConfiguration,
        condition: ((ResponseModel) -> Bool)?,
        continuation: AsyncThrowingStream<ResponseModel, Error>.Continuation
    ) async throws {
        let intervalNanoseconds = UInt64(max(configuration.interval, 0) * 1_000_000_000)
        var attempt = 0
        var consecutiveFailures = 0
        
        if !configuration.firesImmediately {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        
        while true {
            try Task.checkCancellation()
            attempt += 1
            
            if settings.isLoggingRequestEnabled { logger.info("🔁 - Polling attempt \(attempt)") }
            
            do {
                let response: ResponseModel = try await performCancellableURLDataTask(
                    with: request(),
                    errorModelType: errorModelType
                )
                consecutiveFailures = 0
                continuation.yield(response)
                
                if condition?(response) ?? false {
                    if settings.isLoggingRequestEnabled { logger.info("⏹ - Polling finished: condition met") }
                    return
                }
            } catch {
                try Task.checkCancellation()
                consecutiveFailures += 1
                guard consecutiveFailures <= configuration.maxConsecutiveFailures else { throw error }
            }
            
            if let maxAttempts = configuration.maxAttempts, attempt >= maxAttempts {
                if settings.isLoggingRequestEnabled { logger.info("⏹ - Polling finished: max attempts reached") }
                return
            }
            
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
    
    /// Same as the async `performURLDataTask`, but cancels the underlying data task when the calling task is cancelled.
    func performCancellableURLDataTask<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: URLRequest?,
        errorModelType: ErrorModel.Type
    ) async throws -> ResponseModel {
        let dataTaskBox = CancellableDataTaskBox()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResponseModel, Error>) in
                let dataTask = getURLDataTask(with: request) { (response: ResponseModel?, error: HTTPClientError<ErrorModel>?) in
                    if let response {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: error ?? HTTPClientError<ErrorModel>(type: .invalidResponse))
                    }
                }
                guard let dataTask else { return }
                dataTaskBox.set(dataTask)
                dataTask.resume()
            }
        } onCancel: {
            dataTaskBox.cancel()
        }
    }
}

private final class CancellableDataTaskBox: @unchecked Sendable {
    
    private let lock = NSLock()
    private var dataTask: URLSessionDataTask?
    private var isCancelled = false
    
    func set(_ dataTask: URLSessionDataTask) {
        lock.lock()
        self.dataTask = dataTask
        let isCancelled = self.isCancelled
        lock.unlock()
        
        if isCancelled { dataTask.cancel() }
    }
    
    func cancel() {
        lock.lock()
        isCancelled = true
        let dataTask = self.dataTask
        lock.unlock()
        
        dataTask?.cancel()
    }
}
