//
//  HTTPClientSessionDelegate.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 18/11/24.
//

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
