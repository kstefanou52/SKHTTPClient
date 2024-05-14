//
//  HTTPClientSettings.swift
//
//
//  Created by kostis stefanou on 2/8/20.
//

import OSLog
import Foundation

public struct HTTPClientSettings {
    
    public let isLoggingRequestEnabled: Bool
    public let isLoggingResponseEnabled: Bool
    
    public let isLoggingRequestPrivacyPublic: Bool
    public let isLoggingResponsePrivacyPublic: Bool
    
    public let timeoutInterval: TimeInterval
    public let customJSONDecoder: JSONDecoder?
    
    public init(shouldLogRequest: Bool = true,
                shouldLogResponse: Bool = true,
                shouldMakeLoggingRequestPrivacyPublic: Bool = false,
                shouldMakeLoggingResponsePrivacyPublic: Bool = false,
                timeoutInterval: TimeInterval = 60,
                customJSONDecoder: JSONDecoder? = nil) {
        self.isLoggingRequestEnabled = shouldLogRequest
        self.isLoggingResponseEnabled = shouldLogResponse
        self.isLoggingRequestPrivacyPublic = shouldMakeLoggingRequestPrivacyPublic
        self.isLoggingResponsePrivacyPublic = shouldMakeLoggingResponsePrivacyPublic
        self.timeoutInterval = timeoutInterval
        self.customJSONDecoder = customJSONDecoder
    }
}
