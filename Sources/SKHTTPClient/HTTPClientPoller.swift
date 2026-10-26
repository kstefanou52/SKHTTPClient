//
//  HTTPClientPoller.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

/// A handle to a running polling operation started with `HTTPClient.startPolling`.
/// Polling is not cancelled when the handle is deallocated; call `cancel()` to stop it.
public final class HTTPClientPoller {
    
    private let task: Task<Void, Never>
    
    public var isCancelled: Bool { task.isCancelled }
    
    init(task: Task<Void, Never>) {
        self.task = task
    }
    
    public func cancel() {
        task.cancel()
    }
}
