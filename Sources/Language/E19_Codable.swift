// Ex 19 — Advanced Codable.

import Foundation

package enum E19 {
    package static let defaultCurrencyKey = CodingUserInfoKey(rawValue: "defaultCurrency")!

    package enum ListingBlock: Equatable, Sendable {
        case text(body: String)
        case photo(url: URL, caption: String?)
        case amenities([String])
        /// Resilience: an unknown `type` doesn't fail the whole payload.
        case unknown(type: String)
    }

    /// Clean domain model; the JSON shape is an implementation detail of Codable.
    package struct ImportedListing: Equatable, Sendable {
        package var id: UUID
        package var title: String
        package var latitude: Double      // flattened from "location"
        package var longitude: Double
        package var price: Decimal        // from a *string* in JSON, no Double precision loss
        package var currency: String
        package var availableFrom: Date   // "yyyy-MM-dd"
        package var updatedAt: Date       // ISO 8601 with time
        package var blocks: [ListingBlock]
    }

    // Formatters are created per call: `DateFormatter` isn't Sendable, and a
    // shared mutable formatter would be a data race under Swift 6.
    static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

extension E19.ImportedListing: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "listing_id", title, location, price
        case availableFrom = "available_from", updatedAt = "updated_at", blocks
    }

    enum LocationKeys: String, CodingKey { case lat, lng }
    enum PriceKeys: String, CodingKey { case amount, currency }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)

        let location = try container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location)
        latitude = try location.decode(Double.self, forKey: .lat)
        longitude = try location.decode(Double.self, forKey: .lng)

        let priceContainer = try container.nestedContainer(keyedBy: PriceKeys.self, forKey: .price)
        let amountText = try priceContainer.decode(String.self, forKey: .amount)
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")),
              amountText.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" })
        else {
            // codingPath of this error: ["price", "amount"]
            throw DecodingError.dataCorruptedError(
                forKey: .amount, in: priceContainer,
                debugDescription: "'\(amountText)' is not a decimal amount"
            )
        }
        price = amount
        let fallbackCurrency = decoder.userInfo[E19.defaultCurrencyKey] as? String ?? "USD"
        currency = try priceContainer.decodeIfPresent(String.self, forKey: .currency) ?? fallbackCurrency

        let dayText = try container.decode(String.self, forKey: .availableFrom)
        guard let day = E19.dayFormatter().date(from: dayText) else {
            throw DecodingError.dataCorruptedError(forKey: .availableFrom, in: container, debugDescription: "expected yyyy-MM-dd")
        }
        availableFrom = day

        let updatedText = try container.decode(String.self, forKey: .updatedAt)
        guard let updated = try? Date(updatedText, strategy: .iso8601) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "expected ISO 8601")
        }
        updatedAt = updated

        blocks = try container.decode([E19.ListingBlock].self, forKey: .blocks)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)

        var location = container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location)
        try location.encode(latitude, forKey: .lat)
        try location.encode(longitude, forKey: .lng)

        var priceContainer = container.nestedContainer(keyedBy: PriceKeys.self, forKey: .price)
        try priceContainer.encode("\(price)", forKey: .amount)
        try priceContainer.encode(currency, forKey: .currency)

        try container.encode(E19.dayFormatter().string(from: availableFrom), forKey: .availableFrom)
        try container.encode(updatedAt.formatted(.iso8601), forKey: .updatedAt)
        try container.encode(blocks, forKey: .blocks)
    }
}

extension E19.ListingBlock: Codable {
    enum CodingKeys: String, CodingKey { case type, body, url, caption, items }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(body: try container.decode(String.self, forKey: .body))
        case "photo":
            self = .photo(
                url: try container.decode(URL.self, forKey: .url),
                caption: try container.decodeIfPresent(String.self, forKey: .caption)
            )
        case "amenities":
            self = .amenities(try container.decode([String].self, forKey: .items))
        default:
            self = .unknown(type: type)
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let body):
            try container.encode("text", forKey: .type)
            try container.encode(body, forKey: .body)
        case let .photo(url, caption):
            try container.encode("photo", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(caption, forKey: .caption)   // keeps `"caption": null`
        case .amenities(let items):
            try container.encode("amenities", forKey: .type)
            try container.encode(items, forKey: .items)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}
