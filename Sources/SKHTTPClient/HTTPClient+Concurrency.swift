//
//  HTTPClient+Concurrency.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

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
}
