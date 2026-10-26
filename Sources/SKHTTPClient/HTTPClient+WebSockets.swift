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
    
    private func sendPing(_ task: URLSessionWebSocketTask, every seconds: UInt64) async {
        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        
        guard task.state == .running else {
            logger.info("✋ - Ping stopped: WebSocket task is not running.")
            return
        }
        
        if self.settings.isLoggingRequestEnabled ?? false {
            logger.info("🙋 - Ping Sent")
        }
        
        task.sendPing { [weak self] error in
            guard self?.settings.isLoggingResponseEnabled ?? false else { return }
            if let error {
                self?.logger.error("❌ - Pong Responded with Error : \(error.localizedDescription)")
            } else {
                self?.logger.info("🏓 - Pong Received")
                
                Task { try? await self?.sendPing(task, every: seconds) }
            }
        }
    }
}
