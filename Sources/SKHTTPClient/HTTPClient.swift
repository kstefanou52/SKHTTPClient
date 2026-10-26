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
