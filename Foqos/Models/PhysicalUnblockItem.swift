import Foundation

/// Represents a physical NFC tag or QR code that can unblock a profile
/// Supports having multiple NFC tags and/or QR codes per profile
struct PhysicalUnblockItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var type: PhysicalUnblockType
  var purposes: [PhysicalUnblockPurpose]
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
  
  enum PhysicalUnblockPurpose: String, Codable, CaseIterable, Sendable {
    case stop
    case pause
  }


  init(
    id: UUID = UUID(),
    name: String,
    type: PhysicalUnblockType,
  purposes: [PhysicalUnblockPurpose],
    codeValue: String
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.purposes = purposes
    self.codeValue = codeValue
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
        purposes: item.purposes,
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
