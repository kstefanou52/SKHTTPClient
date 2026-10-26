//
//  HTTPClient+ServerSentEvents.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/10/26.
//

import Foundation

// MARK: - Server Sent Events

public extension HTTPClient {
    
    @available(iOS 18.0, *)
    func getEventStreamWithJSONData<JSONDataType: Decodable>(
        with request: URLRequest?
    ) async throws -> any AsyncSequence<ServerSentEventWithJSONData<JSONDataType>, Error> {
        guard let request else {
            throw HTTPClientError<String?>(type: .invalidRequest)
        }

        if settings.isLoggingRequestEnabled { printRequest(request) }
        
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw HTTPClientError<String?>(type: .invalidResponse)
        }

        if self.settings.isLoggingResponseEnabled { self.printResponse(httpResponse) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()

        return asyncBytes
            .chunkedSSERawEvents()
            .printResponse(
                isLoggingResponseEnabled: settings.isLoggingResponseEnabled,
                isLoggingResponsePrivacyPublic: settings.isLoggingResponsePrivacyPublic,
                response: httpResponse,
                logger: logger
            )
            .asDecodedServerSentEventsWithJSONData(of: JSONDataType.self, decoder: decoder)
    }
    
    @available(iOS 15.0, *)
    func getEventStreamWithJSONData<JSONDataType: Decodable>(
        with request: URLRequest?
    ) async throws -> AsyncThrowingStream<ServerSentEventWithJSONData<JSONDataType>, Error> {
        guard let request else {
            throw HTTPClientError<String?>(type: .invalidRequest)
        }

        if settings.isLoggingRequestEnabled { printRequest(request) }
        
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw HTTPClientError<String?>(type: .invalidResponse)
        }

        if self.settings.isLoggingResponseEnabled { self.printResponse(httpResponse) }
        
        let decoder = settings.customJSONDecoder ?? JSONDecoder()

        return asyncBytes
            .chunkedSSERawEvents()
            .printResponse(
                isLoggingResponseEnabled: settings.isLoggingResponseEnabled,
                isLoggingResponsePrivacyPublic: settings.isLoggingResponsePrivacyPublic,
                response: httpResponse,
                logger: logger
            )
            .asDecodedServerSentEventsWithJSONData(of: JSONDataType.self, decoder: decoder)
            .asAsyncThrowingStream()
    }
}
