//
//  Dictionary+Encodable.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 4/4/25.
//

import Foundation

extension Dictionary where Key == String, Value == Encodable {
    
    func encodeToData(using encoder: JSONEncoder = .init()) throws -> Data {
        let dict = self.mapValues { value -> Any in
            if let jsonData = try? encoder.encode(value),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                return jsonObject
            }
            return value
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }
}
