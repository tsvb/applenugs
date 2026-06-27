import Foundation

/// Lightweight dynamic access over nugs's irregular JSON — the Swift port of
/// NugsShape. Field names alternate between camelCase and PascalCase across
/// endpoints and some are pluralized inconsistently, so lookups take a list
/// of candidate spellings. This owns the shape-dependent digging so model
/// and view code stays readable.
///
/// `@unchecked Sendable`: a value type holding a single immutable `let` over the
/// immutable object tree `JSONSerialization` returns (NSDictionary/NSArray/
/// NSString/NSNumber). It is only ever read, never mutated, so it is safe to
/// hand from the `NugsClient` actor back to the main actor.
struct JSON: @unchecked Sendable {
    let raw: Any?

    init(_ raw: Any?) {
        self.raw = raw is NSNull ? nil : raw
    }

    static func parse(_ data: Data) -> JSON {
        JSON(try? JSONSerialization.jsonObject(with: data))
    }

    /// Catalog endpoints typically wrap their payload in a Response object.
    var unwrapped: JSON {
        for key in ["Response", "response"] {
            let v = self[key]
            if v.raw != nil { return v }
        }
        return self
    }

    subscript(_ key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    /// String coercion mirroring NugsShape.Str: strings pass through
    /// (empty → nil), numbers stringify, null/missing → nil.
    var string: String? {
        switch raw {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    var int: Int? {
        switch raw {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    var array: [JSON] {
        (raw as? [Any])?.map(JSON.init) ?? []
    }

    /// First non-null string among candidate key spellings.
    func str(_ keys: String...) -> String? {
        guard let dict = raw as? [String: Any] else { return nil }
        for k in keys {
            let v = JSON(dict[k])
            if let s = v.string { return s }
        }
        return nil
    }

    /// First array among candidate key spellings.
    func arr(_ keys: String...) -> [JSON] {
        guard let dict = raw as? [String: Any] else { return [] }
        for k in keys {
            if let a = dict[k] as? [Any] { return a.map(JSON.init) }
        }
        return []
    }

    /// First non-null int among candidate key spellings.
    func int(_ keys: String...) -> Int? {
        guard let dict = raw as? [String: Any] else { return nil }
        for k in keys {
            if let v = JSON(dict[k]).int { return v }
        }
        return nil
    }
}
