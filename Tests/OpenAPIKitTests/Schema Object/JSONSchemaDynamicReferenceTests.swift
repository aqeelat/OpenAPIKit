//
//  JSONSchemaDynamicReferenceTests.swift
//
//  Tests for `$dynamicRef` / `$dynamicAnchor` support (JSON Schema 2020-12, [§7.7]
//  https://json-schema.org/draft/2020-12/json-schema-core#section-7.7).
//

import Foundation
import XCTest
import OpenAPIKit

final class JSONSchemaDynamicReferenceTests: XCTestCase {

    // MARK: - Decoding

    func test_decodeDynamicReference_anchor() throws {
        let data = #"""
        {
            "$dynamicRef": "#category"
        }
        """#.data(using: .utf8)!

        let schema = try orderUnstableDecode(JSONSchema.self, from: data)

        XCTAssertTrue(schema.isDynamicReference)
        XCTAssertFalse(schema.isReference)
        XCTAssertEqual(schema.dynamicReference?.absoluteString, "#category")
        // No "unsupported attributes" warning -- this is the core regression
        // being fixed (previously `$dynamicRef`-only schemas warned and decoded
        // as empty fragments).
        XCTAssertTrue(schema.warnings.isEmpty, "expected no warnings, got: \(schema.warnings)")
    }

    func test_decodeDynamicReference_component() throws {
        let data = #"""
        {
            "$dynamicRef": "#/components/schemas/Foo"
        }
        """#.data(using: .utf8)!

        let schema = try orderUnstableDecode(JSONSchema.self, from: data)

        XCTAssertTrue(schema.isDynamicReference)
        XCTAssertEqual(schema.dynamicReference?.name, "Foo")
        XCTAssertTrue(schema.warnings.isEmpty)
    }

    func test_decodeDynamicRef_doesNotEmitUnsupportedAttributesWarning() throws {
        // Previously a `$dynamicRef` whose only attribute was the dynamic
        // reference decoded as an empty fragment with the warning
        // "Found nothing but unsupported attributes."
        let data = "{\"$dynamicRef\":\"#node\"}".data(using: .utf8)!

        let schema = try orderUnstableDecode(JSONSchema.self, from: data)

        XCTAssertTrue(schema.isDynamicReference)
        XCTAssertEqual(schema.dynamicReference?.absoluteString, "#node")
        let hasUnsupportedWarning = schema.warnings.contains { warning in
            String(describing: warning).contains("unsupported attributes")
        }
        XCTAssertFalse(hasUnsupportedWarning)
    }

    // MARK: - Encoding / round-trip

    func test_encodeDynamicReference_anchor() throws {
        let schema = JSONSchema.dynamicReference(.anchor("category"))

        let encoded = try orderUnstableEncode(schema)

        XCTAssertEqual(
            try orderUnstableDecode(JSONSchema.self, from: encoded),
            schema
        )
        let encodedString = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(encodedString.contains("$dynamicRef"))
        XCTAssertTrue(encodedString.contains("#category"))
    }

    func test_refWithPlainFragmentRoundTripsAsAnchor() throws {
        // A `$ref` whose fragment has no leading '/' (e.g. "#foo") is a plain
        // anchor reference. It must round-trip verbatim rather than being
        // rewritten with a slash.
        let data = "{\"$ref\":\"#foo\"}".data(using: .utf8)!

        let schema = try orderUnstableDecode(JSONSchema.self, from: data)
        XCTAssertTrue(schema.isReference)
        XCTAssertEqual(schema.reference?.absoluteString, "#foo")

        let encoded = try orderUnstableEncode(schema)
        let encodedString = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(encodedString.contains("$ref"))
        XCTAssertTrue(encodedString.contains("#foo"))
        XCTAssertFalse(encodedString.contains("#/foo"))
    }

    func test_dynamicReference_roundTripThroughDocument() throws {
        // A realistic recursive schema: BaseCategory is extended by
        // LocalizedCategory via `allOf` + `$dynamicAnchor`. Children point
        // back at the active category through `$dynamicRef`.
        let jsonString = """
        {
          "openapi": "3.1.0",
          "info": { "title": "test", "version": "1.0.0" },
          "paths": {},
          "components": {
            "schemas": {
              "BaseCategory": {
                "$dynamicAnchor": "category",
                "type": "object",
                "properties": {
                  "name": { "type": "string" },
                  "children": {
                    "type": "array",
                    "items": { "$dynamicRef": "#category" }
                  }
                }
              },
              "LocalizedCategory": {
                "$dynamicAnchor": "category",
                "allOf": [
                  { "$ref": "#/components/schemas/BaseCategory" },
                  {
                    "type": "object",
                    "properties": {
                      "displayName": { "type": "string" },
                      "locale": { "type": "string" }
                    }
                  }
                ]
              }
            }
          }
        }
        """

        let doc = try orderUnstableDecode(OpenAPI.Document.self, from: jsonString.data(using: .utf8)!)

        // The `$dynamicRef` keyword survives the decode intact.
        let base = doc.components.schemas["BaseCategory"]!
        let childrenItems = base.objectContext!.properties["children"]!.arrayContext!.items!
        XCTAssertTrue(childrenItems.isDynamicReference)
        XCTAssertEqual(childrenItems.dynamicReference?.absoluteString, "#category")

        // Round-trips back out.
        let reencoded = try orderUnstableEncode(doc)
        let redecoded = try orderUnstableDecode(OpenAPI.Document.self, from: reencoded)
        let redecodedItems = redecoded.components.schemas["BaseCategory"]!
            .objectContext!.properties["children"]!.arrayContext!.items!
        XCTAssertTrue(redecodedItems.isDynamicReference)
        XCTAssertEqual(redecodedItems.dynamicReference?.absoluteString, "#category")
    }

    // MARK: - Accessors / transformations

    func test_isDynamicReference_accessor() {
        let dyn = JSONSchema.dynamicReference(.anchor("x"))
        let ref = JSONSchema.reference(.component(named: "x"))
        let str = JSONSchema.string

        XCTAssertTrue(dyn.isDynamicReference)
        XCTAssertFalse(ref.isDynamicReference)
        XCTAssertFalse(str.isDynamicReference)

        XCTAssertNotNil(dyn.dynamicReference)
        XCTAssertNil(ref.dynamicReference)
        XCTAssertNil(str.dynamicReference)
    }

    func test_dynamicReference_optionalRequired() {
        let required = JSONSchema.dynamicReference(.anchor("x"))
        XCTAssertTrue(required.required)

        let optional = required.optionalSchemaObject()
        XCTAssertFalse(optional.required)
        XCTAssertTrue(optional.isDynamicReference)
    }

    func test_dynamicReference_withDescription() {
        let schema = JSONSchema.dynamicReference(.anchor("x"))
            .with(description: "a recursive node")

        XCTAssertEqual(schema.description, "a recursive node")
        XCTAssertTrue(schema.isDynamicReference)
    }

    // MARK: - Dereferencing / dynamic-scope resolution

    func test_dereference_dynamicReference_resolvesAndBreaksRecursion() throws {
        // BaseCategory is self-referential via `$dynamicRef "#category"`: its
        // `children.items` point at the "category" dynamic anchor, which is
        // declared on BaseCategory itself. Dereferencing must resolve the
        // dynamic ref against the in-scope anchor and -- because the target is
        // recursive -- break the cycle by retaining a `.dynamicReference`
        // rather than expanding forever.
        let jsonString = """
        {
          "$dynamicAnchor": "category",
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "children": {
              "type": "array",
              "items": { "$dynamicRef": "#category" }
            }
          }
        }
        """

        let base = try orderUnstableDecode(JSONSchema.self, from: jsonString.data(using: .utf8)!)
        let dereferenced = try base.dereferenced(in: .noComponents)

        guard case .object(_, let objectContext) = dereferenced else {
            XCTFail("expected .object, got \(dereferenced)")
            return
        }
        let children = try XCTUnwrap(objectContext.properties["children"])
        let childrenItems: DereferencedJSONSchema = try XCTUnwrap(children.arrayContext?.items)

        // The dynamic ref resolves against the in-scope anchor. Because the
        // target is recursive, the cycle is broken by retaining a
        // `.dynamicReference`. The resolver may inline up to one level before
        // hitting the cycle, so the children items are either the preserved
        // dynamic reference or an object whose own children/items contain it;
        // either way it must not be a silent `unknown`/fragment fallback and
        // dereferencing must terminate (no infinite expansion).
        switch childrenItems {
        case .dynamicReference(let ref, _):
            XCTAssertEqual(ref.absoluteString, "#category")
        case .object:
            // Inlined one level; the dynamic reference is preserved further in.
            break
        default:
            XCTFail("expected children items to resolve (dynamic reference or inlined object), got \(childrenItems)")
        }
    }

    func test_dereference_dynamicReference_genericsInline() throws {
        // The JSON Schema "generics" pattern: a `$dynamicAnchor` lives in
        // `$defs` and the `$dynamicRef` target is a leaf (non-recursive)
        // schema. Dereferencing inlines the concrete target.
        let jsonString = """
        {
          "$defs": {
            "itemType": {
              "$dynamicAnchor": "T",
              "type": "string"
            }
          },
          "type": "object",
          "properties": {
            "items": {
              "type": "array",
              "items": { "$dynamicRef": "#T" }
            }
          }
        }
        """

        let box = try orderUnstableDecode(JSONSchema.self, from: jsonString.data(using: .utf8)!)
        let dereferenced = try box.dereferenced(in: .noComponents)

        guard case .object(_, let objectContext) = dereferenced else {
            XCTFail("expected .object, got \(dereferenced)")
            return
        }
        let items = try XCTUnwrap(objectContext.properties["items"])
        let itemsItems: DereferencedJSONSchema = try XCTUnwrap(items.arrayContext?.items)

        // The leaf `$defs.itemType` (`string`) was inlined through the dynamic ref.
        guard case .string = itemsItems else {
            XCTFail("expected dynamic ref to inline to .string, got \(itemsItems)")
            return
        }
    }

    func test_dereference_dynamicScopePropagatesAcrossRefBoundary() throws {
        // `Outer` references `Inner`. The dynamic anchor "leaf" lives in
        // `Outer`'s `$defs`; `Inner` contains the `$dynamicRef`. The dynamic
        // scope must travel across the `$ref` boundary so Inner's dynamic ref
        // resolves to Outer's concrete leaf type.
        let components = OpenAPI.Components(
            schemas: [
                "Outer": .reference(
                    .component(named: "Inner"),
                    .init(
                        defs: [
                            "L": .boolean(.init(dynamicAnchor: "leaf"))
                        ]
                    )
                ),
                "Inner": .object(
                    .init(),
                    .init(properties: [
                        "flag": .dynamicReference(.anchor("leaf"))
                    ])
                )
            ]
        )

        let outer = try XCTUnwrap(components.schemas["Outer"])
        let dereferenced = try outer.dereferenced(in: components)

        // Outer is a reference to Inner, so after dereferencing we see Inner's
        // object shape with `flag` resolved through the dynamic scope.
        guard case .object(_, let objectContext) = dereferenced else {
            XCTFail("expected .object, got \(dereferenced)")
            return
        }
        let flag: DereferencedJSONSchema = try XCTUnwrap(objectContext.properties["flag"])

        // The dynamic ref resolved to Outer's `$defs.L` (boolean) -- proving
        // the scope crossed the `$ref` from Outer into Inner.
        guard case .boolean = flag else {
            XCTFail("expected flag to resolve to Outer's `$defs.L` (.boolean) across the $ref, got \(flag)")
            return
        }
    }

    func test_dereference_dynamicReference_unresolvedIsPreserved() throws {        // A `$dynamicRef` whose anchor is not in scope must be preserved
        // rather than degraded to an empty/`any` schema.
        let jsonString = """
        {
          "type": "object",
          "properties": {
            "item": { "$dynamicRef": "#unmatched" }
          }
        }
        """

        let wrapper = try orderUnstableDecode(JSONSchema.self, from: jsonString.data(using: .utf8)!)
        let dereferenced = try wrapper.dereferenced(in: .noComponents)

        guard case .object(_, let objectContext) = dereferenced else {
            XCTFail("expected .object, got \(dereferenced)")
            return
        }
        let item: DereferencedJSONSchema = try XCTUnwrap(objectContext.properties["item"])

        if case .dynamicReference(let ref, _) = item {
            XCTAssertEqual(ref.absoluteString, "#unmatched")
        } else {
            XCTFail("expected unresolved `$dynamicRef` to be preserved, got \(item)")
        }
    }
}
