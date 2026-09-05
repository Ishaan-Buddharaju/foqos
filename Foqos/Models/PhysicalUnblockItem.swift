import Foundation

/// Represents a physical NFC tag or QR code that can unblock a profile
/// Supports having multiple NFC tags and/or QR codes per profile
struct PhysicalUnblockItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var type: PhysicalUnblockType
  var purposes: [PhysicalUnblockPurpose] = PhysicalUnblockPurpose.allCases
  var codeValue: String

  enum PhysicalUnblockType: String, Codable, CaseIterable, Sendable {
    case nfc = "nfc"
    case qrCode = "qrCode"

    var displayName: String {
      switch self {
      case .nfc: return "NFC Tag"
      case .qrCode: return "QR Code"
      }
    }
  }

  /// What a code may be presented for. `.stop` ends a session, `.pause` starts a pause.
  enum PhysicalUnblockPurpose: String, Codable, CaseIterable, Sendable {
    case stop
    case pause

    var displayName: String {
      switch self {
      case .stop: return "Stopping"
      case .pause: return "Pausing"
      }
    }

    /// Label for a code restricted to this single purpose, shown under the code value.
    var restrictedDisplayName: String {
      switch self {
      case .stop: return "Stop only"
      case .pause: return "Pause only"
      }
    }
  }

  init(
    id: UUID = UUID(),
    name: String,
    type: PhysicalUnblockType,
    purposes: [PhysicalUnblockPurpose] = PhysicalUnblockPurpose.allCases,
    codeValue: String
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.purposes = purposes
    self.codeValue = codeValue
  }

  /// Decodes tolerantly so values persisted before `purposes` existed stay readable.
  ///
  /// Synthesized `Codable` ignores property defaults and throws on a missing key. Both the
  /// SwiftData blob and the app-group `ProfileSnapshot` JSON predate this field, and the
  /// snapshot decode swallows failures with `?? [:]` - so without this every stored snapshot
  /// would silently vanish from the widget and shield extensions on upgrade.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    type = try container.decode(PhysicalUnblockType.self, forKey: .type)
    codeValue = try container.decode(String.self, forKey: .codeValue)

    let decodedPurposes = try container.decodeIfPresent(
      [PhysicalUnblockPurpose].self,
      forKey: .purposes
    )
    purposes =
      (decodedPurposes?.isEmpty ?? true) ? PhysicalUnblockPurpose.allCases : decodedPurposes!
  }

  static func resolvedItems(
    physicalUnblockItems: [PhysicalUnblockItem]?,
    legacyNFCTagId: String? = nil,
    legacyQRCodeId: String? = nil
  ) -> [PhysicalUnblockItem]? {
    if let physicalUnblockItems {
      return normalizedItems(physicalUnblockItems)
    }

    var items: [PhysicalUnblockItem] = []

    if let legacyNFCTagId, !legacyNFCTagId.isEmpty {
      items.append(
        PhysicalUnblockItem(
          name: "NFC Tag",
          type: .nfc,
          purposes: PhysicalUnblockPurpose.allCases,
          codeValue: legacyNFCTagId
        )
      )
    }

    if let legacyQRCodeId, !legacyQRCodeId.isEmpty {
      items.append(
        PhysicalUnblockItem(
          name: "QR Code",
          type: .qrCode,
          purposes: PhysicalUnblockPurpose.allCases,
          codeValue: legacyQRCodeId
        )
      )
    }

    return normalizedItems(items)
  }

  static func normalizedItems(_ items: [PhysicalUnblockItem]?) -> [PhysicalUnblockItem]? {
    guard let items else { return nil }

    let normalizedItems = items.compactMap { item -> PhysicalUnblockItem? in
      let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedCodeValue = normalizedCodeValue(item.codeValue, type: item.type)

      guard !normalizedCodeValue.isEmpty else { return nil }

      return PhysicalUnblockItem(
        id: item.id,
        name: trimmedName.isEmpty ? item.type.displayName : trimmedName,
        type: item.type,
        purposes: item.purposes.isEmpty ? PhysicalUnblockPurpose.allCases : item.purposes,
        codeValue: normalizedCodeValue
      )
    }

    return normalizedItems.isEmpty ? nil : normalizedItems
  }

  static func normalizedCodeValue(
    _ codeValue: String,
    type: PhysicalUnblockType
  ) -> String {
    let trimmedCodeValue = codeValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard type == .qrCode,
      var components = URLComponents(string: trimmedCodeValue),
      components.scheme != nil,
      components.host != nil
    else {
      return trimmedCodeValue
    }

    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()

    if components.path == "/" && components.query == nil && components.fragment == nil {
      components.path = ""
    }

    return components.string ?? trimmedCodeValue
  }
}
