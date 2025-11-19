//
//  HTTPClient+Log.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 29/9/25.
//

import OSLog
import Foundation

extension HTTPClient {
    
    func printRequest(_ request: URLRequest?) {
        let urlParams: String = {
            guard let url = request?.url else { return " - " }
            return URLComponents(url: url, resolvingAgainstBaseURL: true)?
                .queryItems?
                .map { "   ◦ \($0.name) : \($0.value ?? "-")" }
                .joined(separator: "\n") ?? " - "
        }()
        
        if settings.isLoggingRequestPrivacyPublic {
            logger.info("""
                        📡 - Network Request : \(request?.httpMethod ?? "-", privacy: .public) → \(request?.url?.absoluteString ?? "-", privacy: .public)
                        👨‍🚀 - Headers : \(request?.allHTTPHeaderFields?.prettyPrintedJSONString ?? "-", privacy: .public)
                        🔗 - Parameters : \n\(urlParams, privacy: .public)
                        🎛 - Body : \(request?.httpBody?.prettyPrintedJSONString ?? "-", privacy: .public)
                        """)
        } else {
            logger.info("""
                        📡 - Network Request : \(request?.httpMethod ?? "-") → \(request?.url?.absoluteString ?? "-")
                        👨‍🚀 - Headers : \(request?.allHTTPHeaderFields?.prettyPrintedJSONString ?? "-")
                        🔗 - Parameters : \n\(urlParams)
                        🎛 - Body : \(request?.httpBody?.prettyPrintedJSONString ?? "-")
                        """)
        }
    }
    
    func printResponse(_ response: HTTPURLResponse) {
        let isNetworkCallSuccessful: Bool = 200...299 ~= response.statusCode
        let statusCodeEmoji: String = isNetworkCallSuccessful ? "✅" : "❌"
        
        if settings.isLoggingResponsePrivacyPublic {
            logger.info("""
                        📩 - Response :  \(response.url?.absoluteString ?? "-", privacy: .public)
                        \(statusCodeEmoji, privacy: .public) - Status Code : \(response.statusCode, privacy: .public)
                        📎 - Content-Type : \(response.value(forHTTPHeaderField: "Content-Type") ?? "-", privacy: .public)
                        """)
        } else {
            logger.info("""
                        📩 - Response :  \(response.url?.absoluteString ?? "-")
                        \(statusCodeEmoji, privacy: .public) - Status Code : \(response.statusCode)
                        📎 - Content-Type : \(response.value(forHTTPHeaderField: "Content-Type") ?? "-")
                        """)
        }
    }
    
    func printResponse(_ request: URLRequest, statusCode: Int, responseData: Data?, cached: Bool = false) {
        let isNetworkCallSuccessful: Bool = 200...299 ~= statusCode
        let statusCodeEmoji: String = isNetworkCallSuccessful ? "✅" : "❌"
        let responseEmoji: String = cached ? "💾" : "🌍"
        let responseTypeText: String = cached ? "Cached" : "Network"
        
        if settings.isLoggingResponsePrivacyPublic {
            logger.info("""
                        \(responseEmoji) - \(responseTypeText) Response : \(request.httpMethod ?? "-", privacy: .public) → \(request.url?.absoluteString ?? "-", privacy: .public)
                        \(statusCodeEmoji, privacy: .public) - Status Code : \(statusCode, privacy: .public)
                        🎛 - Body : \(request.httpBody?.prettyPrintedJSONString ?? "-", privacy: .public)
                        \(responseData?.prettyPrintedJSONString ?? "", privacy: .public)
                        """)
        } else {
            logger.info("""
                        \(responseEmoji) - \(responseTypeText) Response : \(request.httpMethod ?? "-") → \(request.url?.absoluteString ?? "-")
                        \(statusCodeEmoji) - Status Code : \(statusCode)
                        🎛 - Body : \(request.httpBody?.prettyPrintedJSONString ?? "-")
                        \(responseData?.prettyPrintedJSONString ?? "")
                        """)
        }
    }
    
    func printResponse(_ task: URLSessionDataTask, responseData: Data) {
        if settings.isLoggingResponsePrivacyPublic {
            logger.info("""
                        📦 - Network Chunk Response : \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-", privacy: .public)
                        🎛 - Body : \(responseData.prettyPrintedJSONString ?? "-", privacy: .public)
                        """)
        } else {
            logger.info("""
                        📦 - Network Chunk Response : \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-")
                        🎛 - Body : \(responseData.prettyPrintedJSONString ?? "-")
                        """)
        }
    }
    
    func printWebSocketMessage(_ task: URLSessionWebSocketTask, message: URLSessionWebSocketTask.Message) {
        let messageString: String = {
            switch message {
            case .data(let data): String(data: data, encoding: .utf8) ?? " - "
            case .string(let text): text
            @unknown default: "Unsupported message type"
            }
        }()
        if settings.isLoggingResponsePrivacyPublic {
            logger.info("""
                        ⚡️ - WebSocket Message Response: \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-", privacy: .public)
                        💬 - Body : \(messageString, privacy: .public)
                        """)
        } else {
            logger.info("""
                        ⚡️ - WebSocket Message Response : \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-")
                        💬 - Body : \(messageString)
                        """)
        }
    }
    
    func printWebSocketError(_ task: URLSessionWebSocketTask, error: any Error) {
        if settings.isLoggingResponsePrivacyPublic {
            logger.error("""
                        ❌ - WebSocket Error : \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-", privacy: .public)
                        ℹ️ - Error : \(error.localizedDescription, privacy: .public)
                        """)
        } else {
            logger.error("""
                        ❌ - WebSocket Error : \(task.originalRequest?.httpMethod ?? "-", privacy: .public) → \(task.originalRequest?.url?.absoluteString ?? "-")
                        ℹ️ - Error : \(error.localizedDescription)
                        """)
        }
    }
}

extension AsyncSequence where Element == ArraySlice<UInt8> {
    
    func printResponse(
        isLoggingResponseEnabled: Bool,
        isLoggingResponsePrivacyPublic: Bool,
        response: HTTPURLResponse,
        logger: Logger
    ) -> AsyncThrowingStream<ArraySlice<UInt8>, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        if isLoggingResponseEnabled {
                            if isLoggingResponsePrivacyPublic {
                                logger.info("""
                                📧 - Server Side Event Response : \(response.url?.absoluteString ?? "-")
                                📝 - Event : \n\(String(bytes: event, encoding: .utf8) ?? "-", privacy: .public)
                                """)
                            } else {
                                logger.info("""
                                📧 - Server Side Event Response : \(response.url?.absoluteString ?? "-")
                                📝 - Event : \n\(String(bytes: event, encoding: .utf8) ?? "-")
                                """)
                            }
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
