//
//  AsyncSequence+UInt8.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 27/9/25.
//

import Foundation

extension AsyncSequence where Element == UInt8 {
    
    func chunkedSSERawEvents(
        maxEventBytes: Int? = nil,
        includeDelimiterBytes: Bool = true
    ) -> AsyncThrowingStream<ArraySlice<UInt8>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer: [UInt8] = []
                var tail: [UInt8] = []
                tail.reserveCapacity(4)
                
                var bytesInCurrent = 0

                @inline(__always)
                func isDelimiter() -> (matched: Bool, len: Int) {
                    if tail.count >= 2 && tail.suffix(2).elementsEqual([10,10]) { return (true, 2) } // two new line chars
                    if tail.count >= 4 && tail.suffix(4).elementsEqual([13,10,13,10]) { return (true, 4) } //
                    return (false, 0)
                }

                do {
                    for try await b in self {
                        buffer.append(b)
                        tail.append(b)
                        if tail.count > 4 { tail.removeFirst() }
                        bytesInCurrent &+= 1

                        if let max = maxEventBytes, bytesInCurrent > max {
                            continuation.finish(throwing: NSError(
                                domain: "SSEParser",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "SSE event exceeded \(max) bytes"]
                            ))
                            return
                        }

                        let delimiter = isDelimiter()
                        if delimiter.matched {
                            if includeDelimiterBytes {
                                continuation.yield(ArraySlice(buffer))
                            } else {
                                let end = buffer.count - delimiter.len
                                continuation.yield(ArraySlice(buffer[..<end]))
                            }
                            buffer.removeAll(keepingCapacity: true)
                            tail.removeAll(keepingCapacity: true)
                            bytesInCurrent = 0
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(ArraySlice(buffer))
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
