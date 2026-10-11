import Foundation

/// The API is inconsistent about scalar types (e.g. `sho_type` is an Int on rails but a String on
/// continue-watching items, `video_duration` is a String, flags are 0/1 or true/false).
/// These helpers decode such fields leniently and treat malformed values as absent.
extension KeyedDecodingContainer {
    nonisolated func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespaces)) ?? Double(value).flatMap { $0.isFinite ? Int($0) : nil }
        }
        return nil
    }

    nonisolated func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite {
            return number
        }
        return nil
    }

    nonisolated func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    nonisolated func lenientString(_ key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Decodes an optional value, treating a type mismatch as absent rather than failing the parent.
    nonisolated func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Decodes an array, dropping elements that fail to decode instead of failing the whole array.
    nonisolated func lossyArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (try? decodeIfPresent(LossyArray<T>.self, forKey: key))??.elements ?? []
    }
}

nonisolated struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    /// Consumes one element of any shape without reading it.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(Skip.self)) == nil {
                break
            }
        }
        self.elements = elements
    }
}

/// Text that is either a plain string or a `{ "en": "…", … }` translation map
/// (e.g. rail titles from `home/all`, bulk-purchase labels).
nonisolated struct LocalizedText: Decodable, Sendable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        let translations = try container.decode([String: String?].self).compactMapValues { $0 }
        let preferred = AppLanguage.current.rawValue
        value = translations[preferred]
            ?? translations["en"]
            ?? translations.sorted { $0.key < $1.key }.first(where: { !$0.value.isEmpty })?.value
            ?? ""
    }
}
