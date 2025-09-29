//
//  AsyncSequence+AsyncThrowingStream.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 30/9/25.
//

import Foundation

extension AsyncSequence {
    
    func asAsyncThrowingStream() -> AsyncThrowingStream<Element, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
