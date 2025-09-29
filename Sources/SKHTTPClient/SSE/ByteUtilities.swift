//
//  ASCII.swift
//  SKHTTPClient
//
//  Created by Kostis Stefanou on 26/9/25.
//

/// A namespace of utilities for byte parsers and serializers.
enum ASCII {

    /// The dash `-` character.
    static let dash: UInt8 = 0x2d

    /// The carriage return `<CR>` character.
    static let cr: UInt8 = 0x0d

    /// The line feed `<LF>` character.
    static let lf: UInt8 = 0x0a

    /// The record separator `<RS>` character.
    static let rs: UInt8 = 0x1e

    /// The colon `:` character.
    static let colon: UInt8 = 0x3a

    /// The space ` ` character.
    static let space: UInt8 = 0x20

    /// The horizontal tab `<TAB>` character.
    static let tab: UInt8 = 0x09

    /// Two dash characters.
    static let dashes: [UInt8] = [dash, dash]

    /// The `<CR>` character followed by the `<LF>` character.
    static let crlf: [UInt8] = [cr, lf]

    /// The colon character followed by the space character.
    static let colonSpace: [UInt8] = [colon, space]

    /// The characters that represent optional whitespace (OWS).
    static let optionalWhitespace: Set<UInt8> = [space, tab]

    /// Checks whether the provided byte can appear in a header field name.
    /// - Parameter byte: The byte to check.
    /// - Returns: A Boolean value; `true` if the byte is valid in a header field
    ///   name, `false` otherwise.
    static func isValidHeaderFieldNameByte(_ byte: UInt8) -> Bool {
        // Copied from swift-http-types, because we create HTTPField.Name from these anyway later.
        switch byte {
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E: return true
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:  // DIGHT, ALPHA
            return true
        default: return false
        }
    }
}

/// A value returned by the `matchOfOneOf` method.
enum MatchOfOneOfResult<C: RandomAccessCollection> {

    /// No match found at any position in self.
    case noMatch

    /// The first option matched.
    case first(C.Index)

    /// The second option matched.
    case second(C.Index)
}

extension RandomAccessCollection where Element: Equatable {
    /// Returns the index of the first match of one of two elements.
    /// - Parameters:
    ///   - first: The first element to match.
    ///   - second: The second element to match.
    /// - Returns: The result.
    func matchOfOneOf(first: Element, second: Element) -> MatchOfOneOfResult<Self> {
        var index = startIndex
        while index < endIndex {
            let element = self[index]
            if element == first { return .first(index) }
            if element == second { return .second(index) }
            formIndex(after: &index)
        }
        return .noMatch
    }
}
