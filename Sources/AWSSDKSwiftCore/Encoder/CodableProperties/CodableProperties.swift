//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// base protocol for encoder/decoder objects
public protocol CustomCoder {
    associatedtype CodableValue
}

/// Protocol for object that will encode a value
public protocol CustomEncoder: CustomCoder {
    static func encode(value: CodableValue, to encoder: Encoder) throws
}

/// Protocol for object that will decode a value
public protocol CustomDecoder: CustomCoder {
    static func decode(from decoder: Decoder) throws -> CodableValue
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped value
@propertyWrapper public struct Coding<Coder: CustomCoder> {
    var value: Coder.CodableValue

    public init(wrappedValue value: Coder.CodableValue) {
        self.value = value
    }

    public var wrappedValue: Coder.CodableValue {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// add decode functionality if propertyWrapper conforms to `Decodable` and Coder conforms to `CustomDecoder`
extension Coding: Decodable where Coder: CustomDecoder {
    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }
}

/// add encoder functionality if propertyWrapper conforms to `Encodable` and Coder conforms to `CustomEncoder`
extension Coding: Encodable where Coder: CustomEncoder {
    public func encode(to encoder: Encoder) throws {
        try Coder.encode(value: value, to: encoder)
    }
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped optional value
@propertyWrapper public struct OptionalCoding<Coder: CustomCoder> {
    var value: Coder.CodableValue?

    public init(wrappedValue value: Coder.CodableValue?) {
        self.value = value
    }

    public var wrappedValue: Coder.CodableValue? {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// add decode functionality if propertyWrapper conforms to `Decodable` and Coder conforms to `CustomDecoder`
extension OptionalCoding: Decodable where Coder: CustomDecoder {
    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }
}

/// add encoder functionality if propertyWrapper conforms to `Encodable` and Coder conforms to `CustomEncoder`
extension OptionalCoding: Encodable where Coder: CustomEncoder {
    public func encode(to encoder: Encoder) throws {
        guard let value = self.value else { return }
        try Coder.encode(value: value, to: encoder)
    }
}


/// Protocol for a PropertyWrapper to properly handle Coding when the wrappedValue is Optional
public protocol OptionalCodingWrapper {
    associatedtype WrappedType
    var wrappedValue: WrappedType? { get }
    init(wrappedValue: WrappedType?)
}

/// extending `KeyedDecodingContainer` so it will only decode an optional value if it is present
extension KeyedDecodingContainer {
    // This is used to override the default decoding behavior for OptionalCodingWrapper to allow a value to avoid a missing key Error
    public func decode<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> T where T : Decodable, T: OptionalCodingWrapper {
        return try decodeIfPresent(T.self, forKey: key) ?? T(wrappedValue: nil)
    }
}

/// extending `KeyedEncodingContainer` so it will only encode a wrapped value it is non nil
extension KeyedEncodingContainer {
    // Used to make make sure OptionalCodingWrappers encode no value when it's wrappedValue is nil.
    public mutating func encode<T>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: OptionalCodingWrapper {
        guard value.wrappedValue != nil else {return}
        try encodeIfPresent(value, forKey: key)
    }
}

/// extend OptionalCoding so it conforms to OptionalCodingWrapper
extension OptionalCoding: OptionalCodingWrapper {}

/// CodingKey used by Encoder property wrappers
internal struct EncodingWrapperKey : CodingKey {
    public var stringValue: String
    public var intValue: Int?
    
    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
    
    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }
}

