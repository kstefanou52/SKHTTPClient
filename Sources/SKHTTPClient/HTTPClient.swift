//
//  SKHTTPClient.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import OSLog
import Combine
import Foundation

@objc open class HTTPClient: NSObject {
    
    // Properties
    open var settings: HTTPClientSettings { HTTPClientSettings() }
    
    open var commonHeaders: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
    
    open var authorizationType: HTTPClientConfigurations.AuthorizationType?
    
    let logger = Logger(
        subsystem: Bundle(for: HTTPClient.self).bundleIdentifier ?? "SKHTTPClient",
        category: "Network"
    )
    
    // Dependencies
    open var serverURL: URL
    public let session: URLSession
    public let sessionDelegate: any URLSessionDelegate
    
    public init(serverURL: URL, session: URLSession? = nil) {
        self.serverURL = serverURL
        self.sessionDelegate = session?.delegate ?? HTTPClientSessionDelegate(logger: logger)
        self.session = session ?? URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    //MARK: - Implementation
    
    open func createURLRequest(
        endPoint: URL,
        method: HTTPClientConfigurations.Method,
        headers: [String: String] = [:],
        urlQuery: HTTPClientConfigurations.URLQueryType = .dictionary([:]),
        body: HTTPClientConfigurations.BodyType? = nil
    ) -> URLRequest? {
        var request: URLRequest = {
            switch urlQuery {
            case .dictionary(let dictionary): URLRequest(url: endPoint.appendingQueryParameters(dictionary))
            case .items(let items): URLRequest(url: endPoint.appendingQueryItems(items))
            }
        }()
        
        request.httpMethod = method.rawValue
        request.timeoutInterval = settings.timeoutInterval
        request.allHTTPHeaderFields = commonHeaders.merging(headers) { (_, new) in new }
        
        if let authType = authorizationType {
            if let authHeaders = injectAuthHeaderIfAny(authType: authType) {
                request.allHTTPHeaderFields = request.allHTTPHeaderFields?.merging(authHeaders) { (_, new) in new }
            }
            
            if let authUrlParam = injectAuthURLParamIfAny(authType: authType) {
                request.url = request.url?.appendingQueryParameters(authUrlParam)
            }
        }
        
        if let body = body {
            let jsonEncoder: JSONEncoder = (settings.customJSONEncoder ?? JSONEncoder())
            
            switch body {
            case .data(let data):
                request.httpBody = data
            case .dictionary(let dictionary):
                do {
                    let data = try dictionary.encodeToData(using: jsonEncoder)
                    request.httpBody = data
                } catch {
                    if settings.isLoggingRequestEnabled {
                        logger.error("🚫 - Creating Request: Unable to serialise data: \(error)") ; return nil
                    }
                }
            case let .encodable(encodable, encoder):
                do {
                    let data = try (encoder ?? jsonEncoder).encode(encodable)
                    request.httpBody = data
                } catch {
                    if settings.isLoggingRequestEnabled {
                        logger.error("🚫 - Creating Request: Unable to encode data: \(error)") ; return nil
                    }
                }
            }
        }
        
        return request
    }
    
    open func getCachedResponse(for request: URLRequest) -> CachedURLResponse? {
        return session.configuration.urlCache?.cachedResponse(for: request)
    }
    
    open func decodeCacheResponse<ResponseModel: Decodable>(for request: URLRequest?) -> ResponseModel? {
        guard let request else { return nil }
        
        if let cachedResponse = self.getCachedResponse(for: request) {
            do {
                let decoder = (self.settings.customJSONDecoder ?? JSONDecoder())
                let cachedModel = try decoder.decode(ResponseModel.self, from: cachedResponse.data)
                
                if self.settings.isLoggingResponseEnabled {
                    let statusCode = (cachedResponse.response as? HTTPURLResponse)?.statusCode ?? 0
                    self.printResponse(
                        request,
                        statusCode: statusCode,
                        responseData: cachedResponse.data,
                        cached: true
                    )
                }
                return cachedModel
            } catch {
                if self.settings.isLoggingResponseEnabled {
                    self.logger.error(" - Cache Parsing Error \(ResponseModel.self): \(error)")
                }
            }
        } else {
            if self.settings.isLoggingResponseEnabled {
                self.logger.info("⚠️ No cache data found for \(request.url?.absoluteString ?? "unknown")")
            }
        }
        return nil
    }
    
    // MARK: - Closure Based Methods
    // can be overridden.
    
    open func performURLDataTask<T: Decodable, U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(T?, HTTPClientError<U>?) -> Void
    ) {
        guard let urlDataTask = getURLDataTask(with: request, completion: completion) else { return }
        urlDataTask.resume()
    }
    
    open func getURLDataTask<T: Decodable, U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(T?, HTTPClientError<U>?) -> Void
    ) -> URLSessionDataTask? {
        if settings.isLoggingRequestEnabled { printRequest(request) }
        guard let request = request else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return nil }
        
        return session.dataTask(with: request) { [weak self] (data, urlResponse, error) in
            guard let self = self, error == nil else { completion(nil, HTTPClientError(type: .otherError(error))) ; return }
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode else {
                completion(nil, HTTPClientError(type: .invalidResponse)) ; return
            }
            
            let decoder = self.settings.customJSONDecoder ?? JSONDecoder()
            if self.settings.isLoggingResponseEnabled {
                self.printResponse(request, statusCode: statusCode, responseData: data)
            }
            
            guard 200...299 ~= statusCode else {
                let decodedErrorData = try? decoder.decode(U.self, from: data ?? Data())
                
                completion(nil, HTTPClientError(statusCode: statusCode, type: .none, model: decodedErrorData))
                return
            }
            
            if data == nil, error == nil {
                completion(nil, nil) ; return
            }
            
            guard let data = data else {
                completion(nil, HTTPClientError(statusCode: statusCode, type: .invalidResponse)) ; return
            }
            
            do {
                let decodedData = try (self.settings.customJSONDecoder ?? JSONDecoder()).decode(T.self, from: data)
                completion(decodedData, nil)
            } catch {
                if settings.isLoggingResponseEnabled { logger.error("🪛 - Parsing Error \(T.self): \(error)") }
                
                do {
                    let decodedErrorData = try decoder.decode(U.self, from: data)
                    completion(nil, HTTPClientError(statusCode: statusCode, type: .parsingError, model: decodedErrorData))
                } catch {
                    if settings.isLoggingResponseEnabled { logger.error("🪛 - Parsing Error \(U.self): \(error)") }
                    completion(nil, HTTPClientError(statusCode: statusCode, type: .parsingError, model: nil))
                }
            }
        }
    }
    
    open func performURLDataTask(with url: URL, completion: @escaping(Result<Data, Error>) -> Void) {
        session.dataTask(with: url) { (data, response, error) in
            if let data {
                completion(.success(data))
                return
            }
            if let error {
                completion(.failure(error))
            }
        }
        .resume()
    }
    
    // MARK: - Combine Based
    // can be overridden.
    
    @available(OSX 10.15, *)
    @available(iOS 13, *)
    open func getPublisher<T: Decodable>(with request: URLRequest?) -> AnyPublisher<T, Error>? {
        guard let request = request else { return nil }
        if settings.isLoggingRequestEnabled { printRequest(request) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()
        
        return session.dataTaskPublisher(for: request)
            .map { [weak self] in
                if (self?.settings.isLoggingResponseEnabled ?? false) {
                    let statusCode = ($0.response as? HTTPURLResponse)?.statusCode ?? 0
                    self?.printResponse(request, statusCode: statusCode, responseData: $0.data)
                }
                return $0.data
            }
            .decode(type: T.self, decoder: decoder)
            .eraseToAnyPublisher()
    }
    
    @available(OSX 10.15, *)
    @available(iOS 13, *)
    open func getPublisher(for url: URL) -> AnyPublisher<Data, URLError> {
        return session.dataTaskPublisher(for: url)
            .map(\.data)
            .eraseToAnyPublisher()
    }
    
    @available(OSX 10.15, *)
    @available(iOS 13, *)
    open func getPublisherWithForwardCache<T: Decodable>(with request: URLRequest?) -> AnyPublisher<T, Error>? {
        let prependElements: [T] = {
            guard let cachedResponse: T = decodeCacheResponse(for: request) else { return [] }
            return [cachedResponse]
        }()
        
        return getPublisher(with: request)?
            .prepend(prependElements)
            .eraseToAnyPublisher()
    }
}

// MARK: - Closure Based Convenience Methods

extension HTTPClient {
    
    public func performURLDataTask<T: Decodable, U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(Result<T?, HTTPClientError<U>>) -> Void
    ) {
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(result))
            }
        }
        urlDataTask?.resume()
    }
    
    public func performURLDataTask<T: Decodable, U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(Result<T, HTTPClientError<U>>) -> Void
    ) {
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let result = result {
                completion(.success(result))
            } else {
                completion(.failure(error ?? .init(type: .invalidResponse)))
            }
        }
        urlDataTask?.resume()
    }
    
    public func performURLDataTaskWithForwardCache<T: Decodable, U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(Result<T, HTTPClientError<U>>) -> Void
    ) {
        if let cachedResponse: T = decodeCacheResponse(for: request) {
            completion(.success(cachedResponse))
        }
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let result = result {
                completion(.success(result))
            } else {
                completion(.failure(error ?? .init(type: .invalidResponse)))
            }
        }
        urlDataTask?.resume()
    }
    
    public func performURLDataTask<U: Decodable>(
        with request: URLRequest?,
        completion: @escaping(Result<Void, HTTPClientError<U>>) -> Void
    ) {
        let urlDataTask = getURLDataTask(with: request) { (result: HTTPClientVoid?, error: HTTPClientError<U>?) in
            if result != nil {
                completion(.success(()))
            } else {
                completion(.failure(error ?? .init(type: .invalidResponse)))
            }
        }
        urlDataTask?.resume()
    }
}

// MARK: - Concurrency Based

public extension HTTPClient {
    
    func performURLDataTask<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: URLRequest?,
        errorModelType: ErrorModel.Type
    ) async throws -> ResponseModel {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResponseModel, Error>) in
            performURLDataTask(with: request) { (result: Result<ResponseModel, HTTPClientError<ErrorModel>>) in
                continuation.resume(with: result)
            }
        }
    }
    
    func performURLDataTask(with url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            performURLDataTask(with: url) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func performURLDataTask<ErrorModel: Codable>(
        with request: URLRequest?,
        errorModelType: ErrorModel.Type
    ) async throws -> Void {
        try await withCheckedThrowingContinuation { continuation in
            performURLDataTask(with: request) { (result: Result<Void, HTTPClientError<ErrorModel>>) in
                continuation.resume(with: result)
            }
        }
    }
    
    func performURLDataTask<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: URLRequest?,
        errorModelType: ErrorModel.Type
    ) -> AsyncThrowingStream<ResponseModel, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let request, let self else {
                continuation.finish(throwing: HTTPClientError<String?>(type: .invalidRequest))
                return
            }
            
            let dataTask = session.dataTask(with: request)
            
            let sessionDelegate = (sessionDelegate as? HTTPClientSessionDelegate)
            let decoder = (self.settings.customJSONDecoder ?? JSONDecoder())
            
            let listener = HTTPClientSessionListener(
                dataTaskId: dataTask.taskIdentifier,
                onDidReceiveData: { [weak self] (task, data) in
                    guard let self else { return }
                    if self.settings.isLoggingResponseEnabled { self.printResponse(task, responseData: data) }
                    
                    do {
                        let chunkResponse = try decoder.decode(ResponseModel.self, from: data)
                        continuation.yield(chunkResponse)
                    } catch {
                        if self.settings.isLoggingResponseEnabled {
                            self.logger.error(
                                """
                                🪛 - Chunk Parsing Error \(ResponseModel.self): \n \(error) \n 
                                Raw Response: \(String(data: data, encoding: .utf8) ?? "-")
                                """
                            )
                        }
                    }
                }, onDidCompleteWithError: { task, error in
                    if self.settings.isLoggingResponseEnabled {
                        self.logger.info("📥 - Chunk Response Finished")
                    }
                    continuation.finish(throwing: error)
                })
            
            sessionDelegate?.addSessionListener(listener)
            dataTask.resume()
            
            if self.settings.isLoggingRequestEnabled { printRequest(request) }
            
            continuation.onTermination = { _ in
                dataTask.cancel()
                sessionDelegate?.removeSessionListener(dataTask.taskIdentifier)
            }
        }
    }
    
    func performURLDataTaskWithForwardCache<ResponseModel: Decodable, ErrorModel: Codable>(
        with request: URLRequest?,
        errorModelType: ErrorModel.Type
    ) -> AsyncThrowingStream<ResponseModel, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let request, let self else {
                continuation.finish(throwing: HTTPClientError<String?>(type: .invalidRequest))
                return
            }
                
            let dataTask = getURLDataTask(with: request) { (
                response: ResponseModel?,
                error: HTTPClientError<ErrorModel>?
            ) in
                if let response {
                    continuation.yield(response)
                    continuation.finish()
                } else {
                    continuation.finish(throwing: error)
                }
            }
            
            if let cachedResponse: ResponseModel = self.decodeCacheResponse(for: request) {
                continuation.yield(cachedResponse)
            }
            
            dataTask?.resume()
            
            continuation.onTermination = { _ in
                dataTask?.cancel()
            }
        }
    }
    
    @available(iOS 18.0, *)
    func getEventStreamWithJSONData<JSONDataType: Decodable>(
        with request: URLRequest?
    ) async throws -> any AsyncSequence<ServerSentEventWithJSONData<JSONDataType>, Error> {
        guard let request else {
            throw HTTPClientError<String?>(type: .invalidRequest)
        }

        if settings.isLoggingRequestEnabled { printRequest(request) }
        
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw HTTPClientError<String?>(type: .invalidResponse)
        }

        if self.settings.isLoggingResponseEnabled { self.printResponse(httpResponse) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()

        return asyncBytes
            .chunkedSSERawEvents()
            .printResponse(
                isLoggingResponseEnabled: settings.isLoggingResponseEnabled,
                isLoggingResponsePrivacyPublic: settings.isLoggingResponsePrivacyPublic,
                response: httpResponse,
                logger: logger
            )
            .asDecodedServerSentEventsWithJSONData(of: JSONDataType.self, decoder: decoder)
    }
    
    @available(iOS 15.0, *)
    func getEventStreamWithJSONData<JSONDataType: Decodable>(
        with request: URLRequest?
    ) async throws -> AsyncThrowingStream<ServerSentEventWithJSONData<JSONDataType>, Error> {
        guard let request else {
            throw HTTPClientError<String?>(type: .invalidRequest)
        }

        if settings.isLoggingRequestEnabled { printRequest(request) }
        
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw HTTPClientError<String?>(type: .invalidResponse)
        }

        if self.settings.isLoggingResponseEnabled { self.printResponse(httpResponse) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()

        return asyncBytes
            .chunkedSSERawEvents()
            .printResponse(
                isLoggingResponseEnabled: settings.isLoggingResponseEnabled,
                isLoggingResponsePrivacyPublic: settings.isLoggingResponsePrivacyPublic,
                response: httpResponse,
                logger: logger
            )
            .asDecodedServerSentEventsWithJSONData(of: JSONDataType.self, decoder: decoder)
            .asAsyncThrowingStream()
    }
}

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

// MARK: - Helpers

private extension HTTPClient {
    
    private func injectAuthHeaderIfAny(authType: HTTPClientConfigurations.AuthorizationType) -> [String: String]? {
        switch authType {
        case .none:
            return nil
        case .apiKey(key: let key, value: let value, addToProperty: let addToProperty):
            guard addToProperty == .header else { return nil }
            return [key: value]
        case let .basicAuth(username: username, password: password):
            guard let basicAuthData = "\(username):\(password)".data(using: .utf8) else {
                logger.error("🚫 - Basic Auth: Unable to encode given credentials") ; return nil
            }
            return [
                HTTPClientConfigurations.authorizationHTTPHeaderFieldKey: "Basic \(basicAuthData.base64EncodedString())"
            ]
        case .bearer(token: let token):
            return [HTTPClientConfigurations.authorizationHTTPHeaderFieldKey: "Bearer \(token)"]
        }
    }
    
    private func injectAuthURLParamIfAny(authType: HTTPClientConfigurations.AuthorizationType) -> [String: String]? {
        switch authType {
        case .none, .basicAuth, .bearer:
            return nil
        case .apiKey(key: let key, value: let value, addToProperty: let addToProperty):
            guard addToProperty == .url else { return nil }
            return [key: value]
        }
    }
}
