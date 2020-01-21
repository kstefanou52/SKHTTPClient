//
//  HTTPClientError.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/6/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

public final class HTTPClientError<T: Codable>: Error {
    
    let statusCode: Int?
    let type: Code
    let model: T?
    
    enum Code: Int {
        case none
        case invalidResponse
        case invalidRequest
        case parsingError
        case AUTH_FAILED = 401
        case FAILED = 500
        case SERVICE_UNAVAILABLE = 501
    }
    
    required init(statusCode: Int? = nil, type: Code, model: T? = nil) {
        self.statusCode = statusCode
        self.type = type
        self.model = model
    }
}
