//
//  HTTPClient+Closures.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

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
