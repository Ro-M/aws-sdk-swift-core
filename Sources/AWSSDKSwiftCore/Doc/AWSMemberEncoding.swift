//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Structure defining how to serialize member of AWSShape.
/// Below is the list of possible encodings and how they are setup
/// - Encode in header (label set to member name in json model, location set to .header(header name))
/// - Encode as part of uri (label set to member name in json model, location set to .uri(uri part to replace))
/// - Encode as uri query (label set to member name in json model, location set to .querystring(query string name))
/// - While encoding a Collection as XML or query string define additional element names (label set to member name in json model,
///     shapeEncoding set to one of collection encoding types, if codingkey is different to label then set it to .body(codingkey))
/// - When encoding payload data blob (label set to member name in json model, shapeEncoding set to .blob)
public struct AWSMemberEncoding {
    
    /// Location of AWSMemberEncoding.
    public enum Location {
        case uri(locationName: String)
        case querystring(locationName: String)
        case header(locationName: String)
        case statusCode
        case body(locationName: String)
    }
    
    /// How the AWSMemberEncoding is serialized in XML and Query formats. Used for collection elements.
    public enum ShapeEncoding {
        /// default case, flat arrays and serializing dictionaries like all other codable structures
        case `default`
        /// shape is stored as data blob in body
        case blob
    }
    
    /// name of member
    public let label: String
    /// where to find or place member
    public let location: Location?
    /// How shape is serialized
    public let shapeEncoding: ShapeEncoding

    public init(label: String, location: Location? = nil, encoding: ShapeEncoding = .default) {
        self.label = label
        self.location = location
        self.shapeEncoding = encoding
    }
}
