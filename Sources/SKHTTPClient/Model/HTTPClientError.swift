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
    
    public enum Code {
        case none
        case invalidResponse
        case invalidRequest
        case parsingError
        case AUTH_FAILED
        case FAILED
        case SERVICE_UNAVAILABLE
        case otherError(Error?)
    }
    
    public required init(statusCode: Int? = nil, type: Code, model: T? = nil) {
        self.statusCode = statusCode
        self.type = type
        self.model = model
    }
}
