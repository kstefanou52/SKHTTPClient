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
        case basicAuth(username: String, password: String)
        case bearer(token: String)
    }
    
    public enum BodyType {
        case data(Data?)
        case dictionary([String: Any])
        case encodable(Encodable, encoder: JSONEncoder = .init())
    }
    
    public enum URLQueryType {
        case dictionary([String: Any])
        case items([URLQueryItem])
    }
}
