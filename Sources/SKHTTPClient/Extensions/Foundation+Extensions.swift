//
//  Foundation+Extensions.swift
//  SKHTTPClient
//
//  Created by kostis stefanou on 1/21/20.
//  Copyright © 2020 silonk. All rights reserved.
//

import Foundation

extension URL {
    
    /// Append query parameters at the end of the given url, default fallback is the self.
    /// - Parameter parameters: A dictionary with the parameters you want to append
    public func appendingQueryParameters(_ parameters: [String: Any]) -> URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: true)
        var items = urlComponents?.queryItems ?? []
        items += parameters.map({ URLQueryItem(name: $0, value: "\($1)") })
        urlComponents?.queryItems = items
        
        return urlComponents?.url ?? self
    }
    
    /// Append query parameters at the end of the given url, default fallback is the self.
    /// - Parameter parameters: A dictionary with the parameters you want to append
    public func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: true)
        var currentItems = urlComponents?.queryItems ?? []
        currentItems += items
        urlComponents?.queryItems = currentItems
        
        return urlComponents?.url ?? self
    }
}

extension Data {
    
    /// Provides you with human readable, json formatted string, thanks to: https://github.com/cprovatas
   var prettyPrintedJSONString: NSString? { /// NSString gives us a nice sanitized debugDescription
       guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
             let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
             let prettyPrintedString = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return nil }

       return prettyPrintedString
   }
}

extension Dictionary {
    
    var prettyPrintedJSONString: NSString? {
        let jsonData = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted)
        return jsonData?.prettyPrintedJSONString
    }
}
