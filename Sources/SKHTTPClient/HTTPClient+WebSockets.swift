//
//  HTTPClient+WebSockets.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

// MARK: - WebSockets

public extension HTTPClient {
    
    @discardableResult
    func subscribe(
        with request: URLRequest?,
        autoSendPing: Bool = true,
        pingInterval: Int = 25,
        onEvent: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) throws -> URLSessionWebSocketTask {
        guard let request else { throw HTTPClientError<String?>(type: .invalidRequest, model: nil) }
        
        let task = session.webSocketTask(with: request)
        task.resume()

        listen(task, onEvent: onEvent)
        
        if autoSendPing {
            Task { await sendPing(task, every: UInt64(pingInterval)) }
        }
        return task
    }
    
    @discardableResult
    func subscribe(
        with request: URLRequest?,
        autoSendPing: Bool = true,
        pingInterval: Int = 25,
        onEvent: @escaping (Result<String, Error>) -> Void
    ) throws -> URLSessionWebSocketTask {
        try subscribe(
            with: request,
            autoSendPing: autoSendPing,
            pingInterval: pingInterval,
            onEvent: { event in
                switch event {
                case .success(let message):
                    guard case let .string(text) = message else {
                        let error = HTTPClientError<String?>(type: .invalidResponse, model: nil)
                        onEvent(.failure(error))
                        return
                    }
                    onEvent(.success(text))
                case .failure(let error):
                    onEvent(.failure(error))
                }
        })
    }
    
    @discardableResult
    func subscribe<Model: Decodable>(
        with request: URLRequest?,
        autoSendPing: Bool = true,
        pingInterval: Int = 25,
        onEvent: @escaping (Result<Model, Error>) -> Void
    ) throws -> URLSessionWebSocketTask {
        try subscribe(
            with: request,
            autoSendPing: autoSendPing,
            pingInterval: pingInterval,
            onEvent: { (event: Result<URLSessionWebSocketTask.Message, Error>) in
            switch event {
            case .success(let message):
                guard case let .data(data) = message else {
                    let error = HTTPClientError<String?>(type: .invalidResponse, model: nil)
                    onEvent(.failure(error))
                    return
                }
                
                do {
                    let decoder = (self.settings.customJSONDecoder ?? JSONDecoder())
                    let model = try decoder.decode(Model.self, from: data)
                    onEvent(.success(model))
                } catch {
                    onEvent(.failure(error))
                }
                
            case .failure(let error):
                onEvent(.failure(error))
            }
        })
    }
    
    private func listen(
        _ task: URLSessionWebSocketTask,
        onEvent: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        task.receive { [weak self] result in
            switch result {
            case .success(let message):
                if self?.settings.isLoggingResponseEnabled ?? false {
                    self?.printWebSocketMessage(task, message: message)
                }
                self?.listen(task, onEvent: onEvent)
            case .failure(let error):
                if self?.settings.isLoggingResponseEnabled ?? false {
                    self?.printWebSocketError(task, error: error)
                }
                task.cancel(with: .goingAway, reason: error.localizedDescription.data(using: .utf8))
            }
            
            onEvent(result)
        }
    }
    
    /// A dead connection (e.g. half-open after a Wi-Fi drop) never fails `receive` on its own, so the task would
    /// stay `.running` forever. A ping that errors or gets no pong in time cancels the task, letting the caller
    /// see it complete and reconnect.
    private func sendPing(_ task: URLSessionWebSocketTask, every seconds: UInt64) async {
        while true {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)

            guard task.state == .running else {
                logger.info("✋ - Ping stopped: WebSocket task is not running.")
                return
            }

            if settings.isLoggingRequestEnabled {
                logger.info("🙋 - Ping Sent")
            }

            if let error = await ping(task, timeout: seconds) {
                logger.error("❌ - Pong Responded with Error : \(error.localizedDescription)")
                task.cancel(with: .goingAway, reason: error.localizedDescription.data(using: .utf8))
                return
            }

            if settings.isLoggingResponseEnabled {
                logger.info("🏓 - Pong Received")
            }
        }
    }

    /// `sendPing`'s handler may never be called on a dead connection, hence the timeout.
    private func ping(_ task: URLSessionWebSocketTask, timeout seconds: UInt64) async -> Error? {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var isResumed = false

            func resume(_ error: Error?) {
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(returning: error)
            }

            task.sendPing { error in resume(error) }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int(seconds))) {
                resume(URLError(.timedOut))
            }
        }
    }
}
