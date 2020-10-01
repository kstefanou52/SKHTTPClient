//
//  HTTPClientError.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

public final class HTTPClientError<T: Codable>: Error {
    
    public let statusCode: Int?
    public let type: Code
    public let model: T?
    
    public enum Code: Int {
        case none
        case invalidResponse
        case invalidRequest
        case parsingError
        case AUTH_FAILED = 401
        case FAILED = 500
        case SERVICE_UNAVAILABLE = 501
    }
    
    public required init(statusCode: Int? = nil, type: Code, model: T? = nil) {
        self.statusCode = statusCode
        self.type = type
        self.model = model
    }
}
