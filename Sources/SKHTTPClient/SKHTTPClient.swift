//
//  SKHTTPClient.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation
import Combine

@objc open class HTTPClient: NSObject {
    
    //MARK: - Properties
    
    open var session: URLSession = URLSession(configuration: .default)
    
    open var serverURL: URL
    
    open var settings: HTTPClientSettings { HTTPClientSettings() }
    
    open var commonHeaders: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
    
    open var authorizationType: HTTPClientConfigurations.AuthorizationType?
    
    public init(serverURL: URL) {
        self.serverURL = serverURL
    }
    
    //MARK: - Functionality
    
    open func createURLRequest(endPoint: URL,
                               method: HTTPClientConfigurations.Method,
                               urlParams: [String: Any] = [:],
                               headers: [String: String] = [:],
                               body: HTTPClientConfigurations.BodyType? = nil) -> URLRequest? {
        var request = URLRequest(url: endPoint.appendingQueryParameters(urlParams))
        
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
            switch body {
            case .data(let data):
                request.httpBody = data
            case .dictionary(let dictionary):
                do {
                    let data = try JSONSerialization.data(withJSONObject: dictionary as Any,
                                                          options: .prettyPrinted)
                    request.httpBody = data
                } catch {
                    print("🚫 - Creating Request: Unable to serialise data: \(error)") ; return nil
                }
            case let .encodable(encodable, encoder):
                do {
                    let data = try encoder.encode(encodable)
                    request.httpBody = data
                } catch {
                    print("🚫 - Creating Request: Unable to encode data: \(error)") ; return nil
                }
            }
        }
        
        return request
    }
    
    open func performURLDataTask<T: Decodable, U: Decodable>(with request: URLRequest?,
                                                             completion: @escaping(T?, HTTPClientError<U>?) -> Void) {
        guard let urlDataTask = getURLDataTask(with: request, completion: completion) else { return }
        urlDataTask.resume()
    }
    
    open func getURLDataTask<T: Decodable, U: Decodable>(with request: URLRequest?,
                                                         completion: @escaping(T?, HTTPClientError<U>?) -> Void) -> URLSessionDataTask? {
        if settings.printRequest { printRequest(request) }
        guard let request = request else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return nil }
        
        return session.dataTask(with: request) { [weak self] (data, urlResponse, error) in
            guard let self = self, error == nil else { completion(nil, HTTPClientError(type: .otherError(error))) ; return }
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
            
            if self.settings.printResponse {
                self.printResponse(request, statusCode: statusCode, responseData: data)
            }
            
            guard 200...299 ~= statusCode else {
                let decodedErrorData = try? (self.settings.customJSONDecoder ?? JSONDecoder()).decode(U.self, from: data ?? Data())
                
                completion(nil, HTTPClientError(statusCode: statusCode, type: .none, model: decodedErrorData))
                return
            }
            
            if data == nil, error == nil {
                completion(nil, nil) ; return
            }
            
            guard let data = data else { completion(nil, HTTPClientError(statusCode: statusCode, type: .invalidResponse)) ; return }
            
            do {
                let decodedData = try (self.settings.customJSONDecoder ?? JSONDecoder()).decode(T.self, from: data)
                completion(decodedData, nil)
            } catch {
                print(error)
                let decodedErrorData = try? (self.settings.customJSONDecoder ?? JSONDecoder()).decode(U.self, from: data)
                completion(nil, HTTPClientError(statusCode: statusCode, type: .parsingError, model: decodedErrorData))
            }
        }
    }
    
    @available(OSX 10.15, *)
    @available(iOS 13, *)
    open func getPublisher<T: Decodable>(with request: URLRequest?) -> AnyPublisher<T, Error>? {
        guard let request = request else { return nil }
        if settings.printRequest { printRequest(request) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()
        
        return session.dataTaskPublisher(for: request)
            .map { [weak self] in
                if (self?.settings.printResponse ?? false) {
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
    
    open func performURLDataTask(with url: URL, completion: @escaping(Data?) -> Void) {
        session.dataTask(with: url) { (data, response, error) in
            guard let data = data, error == nil else { print(error.debugDescription) ; completion(nil) ; return }
            completion(data)
        }
        .resume()
    }
}

// MARK: - Helpers

extension HTTPClient {
    
    private func injectAuthHeaderIfAny(authType: HTTPClientConfigurations.AuthorizationType) -> [String: String]? {
        switch authType {
        case .none:
            return nil
        case .apiKey(key: let key, value: let value, addToProperty: let addToProperty):
            guard addToProperty == .header else { return nil }
            return [key: value]
        case let .basicAuth(username: username, password: password):
            guard let basicAuthData = "\(username):\(password)".data(using: .utf8) else {
                print("🚫 - Basic Auth: Unable to encode given credentials") ; return nil
            }
            return [HTTPClientConfigurations.authorizationHTTPHeaderFieldKey: "Basic \(basicAuthData.base64EncodedString())"]
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
    
    private func printRequest(_ request: URLRequest?) {
        print("📡 - Network Request : \(request?.httpMethod ?? "-") -> \(request?.url?.absoluteString ?? "-")")
        print("👨‍🚀 - Headers : \(request?.allHTTPHeaderFields?.prettyPrintedJSONString ?? "-")")
        print("🎛 - Parameters : \(request?.httpBody?.prettyPrintedJSONString ?? "-")")
    }
    
    private func printResponse(_ request: URLRequest, statusCode: Int, responseData: Data?) {
        print("🌍 - Network Response : \(request.httpMethod ?? "-") -> \(request.url?.absoluteString ?? "-")")
        
        let isNetworkCallSuccessful: Bool = 200...299 ~= statusCode
        let statusCodeEmoji: String = isNetworkCallSuccessful ? "✅" : "❌"
        print("\(statusCodeEmoji) - Status Code : \(statusCode)")
        
        print(responseData?.prettyPrintedJSONString ?? "")
        print("\n")
    }
}

extension HTTPClient {
    
    public func performURLDataTask<T: Decodable, U: Decodable>(with request: URLRequest?,
                                                           completion: @escaping(Result<T?, HTTPClientError<U>>) -> Void) {
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(result))
            }
        }
        urlDataTask?.resume()
    }
    
    public func performURLDataTask<T: Decodable, U: Decodable>(with request: URLRequest?,
                                                           completion: @escaping(Result<T, HTTPClientError<U>>) -> Void) {
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let result = result {
                completion(.success(result))
            } else {
                completion(.failure(error ?? .init(type: .invalidResponse)))
            }
        }
        urlDataTask?.resume()
    }
    
    public func performURLDataTask<U: Decodable>(with request: URLRequest?,
                                                 completion: @escaping(Result<Void, HTTPClientError<U>>) -> Void) {
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
