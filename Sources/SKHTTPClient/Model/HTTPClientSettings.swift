//
//  HTTPClientSettings.swift
//  
//
//  Created by kostis stefanou on 2/8/20.
//

import Foundation

public struct HTTPClientSettings {
    
    public var printResponse: Bool = true
    public var printRequest: Bool = true
    
    public var timeoutInternval: TimeInterval = 60
    
    public var customJSONDecoder: JSONDecoder?
}
