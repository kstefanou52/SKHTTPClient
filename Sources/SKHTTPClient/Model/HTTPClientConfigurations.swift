//
//  HTTPClientConfigurations.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

public struct HTTPClientConfigurations {
    
    public static let authorizationHTTPHeaderFieldKey: String = "Authorization"
    
    public enum Method: String {
        case GET
        case POST
        case PUT
        case DELETE
    }
    
    public enum Property {
        case header
        case url
        case body
    }
    
    public enum AuthorizationType {
        case none
        case apiKey(key: String, value: String, addToProperty: HTTPClientConfigurations.Property)
    }
    
}
