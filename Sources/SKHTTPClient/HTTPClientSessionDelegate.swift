//
//  HTTPClientSessionDelegate.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 18/11/24.
//

import OSLog
import Foundation

open class HTTPClientSessionListener {
    
    let dataTaskId: Int
    var onDidReceiveData: ((_ task: URLSessionDataTask, _ data: Data) -> Void)?
    var onDidCompleteWithError: ((_ task: URLSessionTask, _ error: (any Error)?) -> Void)?
    
    init(
        dataTaskId: Int,
        onDidReceiveData: @escaping (_ dataTask: URLSessionDataTask, _ data: Data) -> Void,
        onDidCompleteWithError: @escaping (_ task: URLSessionTask, _ error: (any Error)?) -> Void
    ) {
        self.dataTaskId = dataTaskId
        self.onDidReceiveData = onDidReceiveData
        self.onDidCompleteWithError = onDidCompleteWithError
    }
}

open class HTTPClientSessionDelegate: NSObject, URLSessionDataDelegate {
    
    private var sessionListeners: [HTTPClientSessionListener] = []
    private let logger: Logger?
    
    init(logger: Logger? = nil) {
        self.logger = logger
    }
    
    public func addSessionListener(_ listener: HTTPClientSessionListener) {
        sessionListeners.append(listener)
    }
    
    public func removeSessionListener(_ listenerId: Int) {
        sessionListeners.removeAll(where: { $0.dataTaskId == listenerId })
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let sessionListener = sessionListeners.first(where: { $0.dataTaskId == dataTask.taskIdentifier }) {
            sessionListener.onDidReceiveData?(dataTask, data)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let sessionListener = sessionListeners.first(where: { $0.dataTaskId == task.taskIdentifier }) {
            sessionListener.onDidCompleteWithError?(task, error)
        }
    }
}

extension HTTPClientSessionDelegate: URLSessionWebSocketDelegate {
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        logger?.info("""
            🔌 - WebSocket Did Open : \(webSocketTask.currentRequest?.url?.absoluteString ?? "-")
            """)
    }
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        logger?.info("""
            🚪 - WebSocket Did Close : \(webSocketTask.currentRequest?.url?.absoluteString ?? "-")
            💬 - Reason : \(closeCode.rawValue) \n\(String(data: reason ?? .init(), encoding: .utf8) ?? "-")
            """)
    }
}
