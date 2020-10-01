//
//  SKHTTPClient.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

@objc open class HTTPClient: NSObject {
    
    //MARK: - Properties
    
    open var session: URLSession = URLSession(configuration: .default)
    
    open var serverURL: URL?
    
    open var settings: HTTPClientSettings { HTTPClientSettings() }

    open var commonHeaders: [String: String] = ["application/json; charset=utf-8": "Content-Type"]
        
    open var authorizationType: HTTPClientConfigurations.AuthorizationType?
    
    //MARK: - Functionality
    
    open func createURLRequest(endPoint: URL, method: HTTPClientConfigurations.Method, urlParams: [String: Any] = [:], headers: [String: String] = [:], body: [String: Any]? = nil) -> URLRequest? {
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
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body as Any, options: .prettyPrinted) else { print("unable to serialize data") ; return nil }
            request.httpBody = bodyData
        }
        
        return request
    }
    
    open func performURLDataTask<T: Codable, U: Codable>(with request: URLRequest?, completion: @escaping(T?, HTTPClientError<U>?) -> Void) {
        if settings.printRequest { printRequest(request) }
        guard let request = request else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
        
        session.dataTask(with: request) { (data, urlResponse, error) in
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
            
            if self.settings.printResponse {
                self.printResponse(request, statusCode: statusCode, responseData: data)
            }
            
            guard Double(statusCode / 200) < 1.5 else { // all status codes begining with 2 are successfull
                let decodedErrorData = try? JSONDecoder().decode(U.self, from: data ?? Data())
                
                completion(nil, HTTPClientError(statusCode: statusCode, type: .none, model: decodedErrorData))
                return
            }
            
            guard let data = data, error == nil else { completion(nil, HTTPClientError(statusCode: statusCode, type: .invalidResponse)) ; return }
            
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                completion(decodedData, nil)
            } catch {
                print(error)
                let decodedErrorData = try? JSONDecoder().decode(U.self, from: data)
                completion(nil, HTTPClientError(statusCode: statusCode, type: .parsingError, model: decodedErrorData))
            }
        }.resume()
    }
    
    open func performURLDataTask(with url: URL, completion: @escaping(Data?) -> Void) {
        session.dataTask(with: url) { (data, response, error) in
            guard let data = data, error == nil else { print(error.debugDescription) ; completion(nil) ; return }
            completion(data)
        }.resume()
    }
}

// MARK: - Helpers

extension HTTPClient {
    
    private func injectAuthHeaderIfAny(authType: HTTPClientConfigurations.AuthorizationType) -> [String: String]? {
        switch authType {
        case .none: return nil
        case .apiKey(key: let key, value: let value, addToProperty: let addToProperty):
            guard addToProperty == .header else { return nil }
            return [key: value]
        }
    }
    
    private func injectAuthURLParamIfAny(authType: HTTPClientConfigurations.AuthorizationType) -> [String: String]? {
        switch authType {
        case .none: return nil
        case .apiKey(key: let key, value: let value, addToProperty: let addToProperty):
            guard addToProperty == .url else { return nil }
            return [key: value]
        }
    }
    
    private func printRequest(_ request: URLRequest?) {
        print("📡 - Network Request : \(request?.httpMethod ?? "-") -> \(request?.url?.absoluteString ?? "-")")
        
        let headersData: Data? = NSKeyedArchiver.archivedData(withRootObject: request?.allHTTPHeaderFields as Any)
        print("👨‍🚀 - Headers : \(headersData?.prettyPrintedJSONString ?? "")")
        
        print("🎛 - Parameters : \(request?.httpBody?.prettyPrintedJSONString ?? "")")
    }
    
    private func printResponse(_ request: URLRequest, statusCode: Int, responseData: Data?) {
        print("🌍 - Network Response : \(request.httpMethod ?? "-") -> \(request.url?.absoluteString ?? "-")")
                
        let isNetworkCallSuccesfull: Bool = Double(statusCode / 200) < 1.5
        let statusCodeEmoji: String = isNetworkCallSuccesfull ? "✅" : "❌"
        print("\(statusCodeEmoji) - Status Code : \(statusCode)")
            
        print(responseData?.prettyPrintedJSONString ?? "")
        print("\n")
    }
}
