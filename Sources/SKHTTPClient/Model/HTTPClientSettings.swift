//
//  HTTPClientSettings.swift
//  
//
//  Created by kostis stefanou on 2/8/20.
//

import Foundation

public struct HTTPClientSettings {
    
    public var printResponse: Bool
    public var printRequest: Bool
    public var timeoutInterval: TimeInterval
    public var customJSONDecoder: JSONDecoder?
    
    public init(printResponse: Bool = true,
                printRequest: Bool = true,
                timeoutInterval: TimeInterval = 60,
                customJSONDecoder: JSONDecoder? = nil) {
        self.printResponse = printResponse
        self.printRequest = printRequest
        self.timeoutInterval = timeoutInterval
        self.customJSONDecoder = customJSONDecoder
    }
}
