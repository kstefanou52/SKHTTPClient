//
//  HTTPClientPollingConfiguration.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

public struct HTTPClientPollingConfiguration {
    
    /// Seconds to wait between the end of one request and the start of the next.
    public let interval: TimeInterval
    /// Maximum number of requests. `nil` means unlimited.
    public let maxAttempts: Int?
    /// Overall polling duration in seconds. `nil` means no timeout.
    public let timeout: TimeInterval?
    /// Number of consecutive failed requests tolerated before polling stops. `0` stops on the first error.
    public let maxConsecutiveFailures: Int
    /// Whether the first request fires immediately or after waiting `interval`.
    public let firesImmediately: Bool
    
    public init(
        interval: TimeInterval = 5,
        maxAttempts: Int? = nil,
        timeout: TimeInterval? = nil,
        maxConsecutiveFailures: Int = 0,
        firesImmediately: Bool = true
    ) {
        self.interval = interval
        self.maxAttempts = maxAttempts
        self.timeout = timeout
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.firesImmediately = firesImmediately
    }
}
