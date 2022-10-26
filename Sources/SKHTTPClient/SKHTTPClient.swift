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
                               body: [String: Any]? = nil) -> URLRequest? {
        var request = URLRequest(url: endPoint.appendingQueryParameters(urlParams))
        
        request.httpMethod = method.rawValue
        request.timeoutInterval = settings.timeoutInternval
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
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body as Any,
                                                             options: .prettyPrinted) else {
                print("🚫 - Creating Request: Unable to serialise data") ; return nil
            }
            request.httpBody = bodyData
        }
        
        return request
    }
    
    open func performURLDataTask<T: Codable, U: Codable>(with request: URLRequest?, completion: @escaping(T?, HTTPClientError<U>?) -> Void) {
        guard let urlDataTask = getURLDataTask(with: request, completion: completion) else { return }
        urlDataTask.resume()
    }
    
    open func performURLDataTask<T: Codable, U: Codable>(with request: URLRequest?, completion: @escaping(Result<T?, HTTPClientError<U>>) -> Void) {
        let urlDataTask = getURLDataTask(with: request) { (result: T?, error: HTTPClientError<U>?) in
            if let error = error {
                completion(.failure(error))
            }
            completion(.success(result))
        }
        urlDataTask?.resume()
    }
    
    open func getURLDataTask<T: Codable, U: Codable>(with request: URLRequest?, completion: @escaping(T?, HTTPClientError<U>?) -> Void) -> URLSessionDataTask? {
        if settings.printRequest { printRequest(request) }
        guard let request = request else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return nil }
        
        return session.dataTask(with: request) { (data, urlResponse, error) in
            guard error == nil else { completion(nil, HTTPClientError(type: .otherError(error))) ; return }
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
            
            if self.settings.printResponse {
                self.printResponse(request, statusCode: statusCode, responseData: data)
            }
            
            guard 200...299 ~= statusCode else {
                let decodedErrorData = try? JSONDecoder().decode(U.self, from: data ?? Data())
                
                completion(nil, HTTPClientError(statusCode: statusCode, type: .none, model: decodedErrorData))
                return
            }
            
            if data == nil, error == nil {
                completion(nil, nil) ; return
            }
            
            guard let data = data else { completion(nil, HTTPClientError(statusCode: statusCode, type: .invalidResponse)) ; return }
            
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                completion(decodedData, nil)
            } catch {
                print(error)
                let decodedErrorData = try? JSONDecoder().decode(U.self, from: data)
                completion(nil, HTTPClientError(statusCode: statusCode, type: .parsingError, model: decodedErrorData))
            }
        }
    }
    
    @available(OSX 10.15, *)
    @available(iOS 13, *)
    open func getPublisher<T: Codable>(with request: URLRequest?) -> AnyPublisher<T, Error>? {
        guard let request = request else { return nil }
        if settings.printRequest { printRequest(request) }
        
        return session.dataTaskPublisher(for: request)
            .map({ [weak self] in
                if (self?.settings.printResponse ?? false) {
                    let statusCode = ($0.response as? HTTPURLResponse)?.statusCode ?? 0
                    self?.printResponse(request, statusCode: statusCode, responseData: $0.data)
                }
                return $0.data
            })
            .decode(type: T.self, decoder: JSONDecoder())
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
        
        let headersData: Data? = try? NSKeyedArchiver.archivedData(withRootObject: request?.allHTTPHeaderFields as Any, requiringSecureCoding: true)
        print("👨‍🚀 - Headers : \(headersData?.prettyPrintedJSONString ?? "")")
        
        print("🎛 - Parameters : \(request?.httpBody?.prettyPrintedJSONString ?? "")")
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
