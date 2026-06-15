//
//  JSONDynamicReference.swift
//
//
//  Created by Mathew Polzin on 3/19/24.
//

import OpenAPIKitCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A `JSONDynamicReference` represents a JSON Schema `$dynamicRef`
/// (JSON Schema 2020-12, [§7.7](https://json-schema.org/draft/2020-12/json-schema-core#section-7.7)).
///
/// Like `JSONReference`, a dynamic reference can point either to a component
/// in the Components Object, to another location within the same document
/// (including a `$dynamicAnchor`), or to another file.
///
/// OpenAPIKit parses and round-trips `$dynamicRef`; it does not perform
/// dynamic-scope evaluation, which is a runtime concern belonging to JSON
/// Schema validators rather than the OpenAPI document model. Local
/// dereferencing (`locallyDereferenced()`) resolves a `$dynamicRef` to the
/// outermost in-scope `$dynamicAnchor` where the dynamic scope can be
/// determined from the document's static structure; on cycles and
/// unresolvable references the dynamic reference is preserved as-is.
@dynamicMemberLookup
public struct JSONDynamicReference: Equatable, Hashable, Sendable {
    public let jsonReference: JSONReference<JSONSchema>

    public init(_ reference: JSONReference<JSONSchema>) {
        self.jsonReference = reference
    }

    public subscript<T>(dynamicMember path: KeyPath<JSONReference<JSONSchema>, T>) -> T {
        return jsonReference[keyPath: path]
    }

    /// Reference a component of type `JSONSchema` in the
    /// Components Object.
    ///
    /// Example:
    ///
    ///     JSONDynamicReference.component(named: "greetings")
    ///     // encoded string: "#/components/schemas/greetings"
    ///     // Swift: `document.components.schemas["greetings"]`
    public static func component(named name: String) -> Self {
        return .init(.internal(.component(name: name)))
    }

    /// Reference a `$dynamicAnchor` (or `$anchor`) local to this document.
    ///
    /// - Important: `anchor` does not contain a leading '#'.
    public static func anchor(_ anchor: String) -> Self {
        return .init(.internal(.anchor(anchor)))
    }

    /// Reference a path internal to this file but not within the Components Object.
    public static func `internal`(path: JSONReference<JSONSchema>.Path) -> Self {
        return .init(.internal(.path(path)))
    }

    /// Reference an external URL.
    public static func external(_ url: URL) -> Self {
        return .init(.external(url))
    }

    /// `true` for internal references, `false` for
    /// external references (i.e. to another file).
    public var isInternal: Bool {
        return jsonReference.isInternal
    }

    /// `true` for external references, `false` for
    /// internal references.
    public var isExternal: Bool {
        return jsonReference.isExternal
    }

    /// Get the name of the referenced object. This method returns optional
    /// because a reference to an external file might not have any path if the
    /// file itself is the referenced component.
    public var name: String? {
        return jsonReference.name
    }

    /// The absolute value of an external reference's
    /// URL or the path fragment string for a local
    /// reference as defined in [RFC 3986](https://tools.ietf.org/html/rfc3986).
    public var absoluteString: String {
        return jsonReference.absoluteString
    }
}

public extension JSONReference where ReferenceType == JSONSchema {
    /// Create a `JSONDynamicReference` from this `JSONReference`.
    var dynamicReference: JSONDynamicReference {
        JSONDynamicReference(self)
    }
}

// MARK: - Codable

extension JSONDynamicReference {
    private enum CodingKeys: String, CodingKey {
        case dynamicRef = "$dynamicRef"
    }
}

extension JSONDynamicReference: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch jsonReference {
        case .internal(let reference):
            try container.encode(reference.rawValue, forKey: .dynamicRef)
        case .external(let url):
            try container.encode(url.absoluteString, forKey: .dynamicRef)
        }
    }
}

extension JSONDynamicReference: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let referenceString = try container.decode(String.self, forKey: .dynamicRef)

        guard referenceString.count > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .dynamicRef, in: container, debugDescription: "Expected a reference string, but found an empty string instead.")
        }

        if referenceString.first == "#" {
            guard let internalReference = JSONReference<JSONSchema>.InternalReference(rawValue: referenceString) else {
                throw GenericError(
                    subjectName: "JSON Dynamic Reference",
                    details: "Failed to parse a JSON Dynamic Reference from '\(referenceString)'",
                    codingPath: container.codingPath
                )
            }
            self = .init(.internal(internalReference))
        } else {
            let externalReference: URL?
            #if canImport(FoundationEssentials)
            externalReference = URL(string: referenceString, encodingInvalidCharacters: false)
            #elseif os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
                externalReference = URL(string: referenceString, encodingInvalidCharacters: false)
            } else {
                externalReference = URL(string: referenceString)
            }
            #else
            externalReference = URL(string: referenceString)
            #endif
            guard let externalReference else {
                throw GenericError(
                    subjectName: "JSON Dynamic Reference",
                    details: "Failed to parse a valid URI for a JSON Dynamic Reference from '\(referenceString)'",
                    codingPath: container.codingPath
                )
            }
            self = .init(.external(externalReference))
        }
    }
}

extension JSONDynamicReference: Validatable {}
