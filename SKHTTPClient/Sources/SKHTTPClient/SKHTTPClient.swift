//
//  SKHTTPClient.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

@objc public class HTTPClient: NSObject {
    
    //MARK: - Properties
    
    public var session: URLSession { URLSession(configuration: .default) }
    
    public var serverURL: URL { URL(string: "")! }
    
    public var printResponse: Bool { true }
    
    public private(set) var token: String? = nil
    
    //MARK: - Functionality
    
    public func setTokenInHeaders(withKey key: String, andValue value: String?) {
        if var httpAdditionalHeaders = session.configuration.httpAdditionalHeaders {
            httpAdditionalHeaders[key] = value
        } else {
            session.configuration.httpAdditionalHeaders = [key: value as Any]
        }
        token = value
    }
    
    public func createURLRequest(endPoint: URL, method: HTTPClientConfigurations.Method, urlParams: [String: Any] = [:], headers: [String: String]? = nil, body: [String: Any]? = nil) -> URLRequest? {
        var request = URLRequest(url: endPoint.appendingQueryParameters(urlParams))
        
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body as Any, options: .prettyPrinted) else { print("unable to serialize data") ; return nil }
        request.httpBody = bodyData
        
        return request
    }
    
    public func performURLDataTask<T: Codable, U: Codable>(with request: URLRequest?, completion: @escaping(T?, HTTPClientError<U>?) -> Void) {
        guard let request = request else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
        
        session.dataTask(with: request) { (data, urlResponse, error) in
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode else { completion(nil, HTTPClientError(type: .invalidResponse)) ; return }
            
            if self.printResponse {
                print("URL : \(request.url?.absoluteString ?? "-")")
                print("Status Code : \(statusCode)")
                print(data?.prettyPrintedJSONString ?? "unable to print json-response")
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
    
    public func performURLDataTask(with url: URL, completion: @escaping(Data?) -> Void) {
        session.dataTask(with: url) { (data, response, error) in
            guard let data = data, error == nil else { print(error.debugDescription) ; completion(nil) ; return }
            completion(data)
        }.resume()
    }
}
