import SwiftUI

struct BlockedProfilePhysicalUnblockSelector: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @ScaledMetric(relativeTo: .subheadline) private var itemRowVerticalPadding: CGFloat = 16

  @Binding var physicalUnblockItems: [PhysicalUnblockItem]
  var disabled: Bool = false
  var disabledText: String?

  /// Whether the selected strategy distinguishes pausing from stopping. Only the pause-timer
  /// strategies do, so everywhere else the purpose controls stay hidden.
  var supportsPurposes: Bool = false

  @State private var showingQRCodeScanner = false
  @State private var showingRenamePrompt = false
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var renameItemName = ""
  @State private var renameItemID: UUID?

  private let physicalReader = PhysicalReader()

  private var nfcItems: [PhysicalUnblockItem] {
    physicalUnblockItems.filter { $0.type == .nfc }
  }

  private var qrItems: [PhysicalUnblockItem] {
    physicalUnblockItems.filter { $0.type == .qrCode }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 20) {
        physicalUnblockSection(
          title: "NFC Tags",
          description: "Add NFC tags that can unlock this profile while a session is active.",
          systemImage: "wave.3.right.circle.fill",
          assetImage: "NFCStickerLogo",
          items: nfcItems,
          emptyButtonTitle: "Set",
          addButtonTitle: "Add Tag",
          onAdd: addNFCTag
        )

        physicalUnblockSection(
          title: "QR/Barcode",
          description:
            "Add QR codes or barcodes that can unlock this profile while a session is active.",
          systemImage: "qrcode.viewfinder",
          assetImage: "QRStickerLogo",
          items: qrItems,
          emptyButtonTitle: "Set",
          addButtonTitle: "Add Code",
          onAdd: { showingQRCodeScanner = true }
        )
      }.padding(0)

      if let disabledText = disabledText, disabled {
        Text(disabledText)
          .foregroundStyle(.red)
          .font(.caption)
      }
    }
    .background(
      TextFieldAlert(
        isPresented: $showingRenamePrompt,
        title: "Rename Item",
        message: nil,
        text: $renameItemName,
        placeholder: "Item Name",
        confirmTitle: "Save",
        cancelTitle: "Cancel",
        onConfirm: { _ in
          applyRename()
        }
      )
    )
    .alert("Error", isPresented: $showingError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
    .sheet(isPresented: $showingQRCodeScanner) {
      BlockingStrategyActionView(
        customView: physicalReader.readQRCode(
          onSuccess: { codeValue in
            showingQRCodeScanner = false
            addItem(codeValue: codeValue, type: .qrCode)
          },
          onFailure: { _ in
            showingQRCodeScanner = false
            showError("Failed to read QR code, please try again or use a different code.")
          }
        )
      )
    }
  }

  /// One full-width section per code type, stacked rather than sat side by side, so each row
  /// has the width for a name, a purpose picker and a delete control on a single line.
  @ViewBuilder
  private func physicalUnblockSection(
    title: String,
    description: String,
    systemImage: String,
    assetImage: String? = nil,
    items: [PhysicalUnblockItem],
    emptyButtonTitle: String,
    addButtonTitle: String,
    onAdd: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        typeIcon(systemImage: systemImage, assetImage: assetImage, size: 28)

        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        if !items.isEmpty {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(themeManager.themeColor)
            .font(.caption)
        }

        Spacer(minLength: 0)
      }

      Text(description)
        .font(.caption2)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 10) {
        if items.isEmpty {
          addButton(title: emptyButtonTitle, action: onAdd)
        } else {
          ForEach(items) { item in
            physicalUnblockItemRow(item: item)
          }

          addButton(title: addButtonTitle, action: onAdd)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .opacity(disabled ? 0.5 : 1)
  }

  @ViewBuilder
  private func typeIcon(
    systemImage: String,
    assetImage: String?,
    size: CGFloat
  ) -> some View {
    if let assetImage {
      Image(assetImage)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundColor(.gray)
        .frame(width: size, height: size)
    }
  }

  @ViewBuilder
  private func physicalUnblockItemRow(item: PhysicalUnblockItem) -> some View {
    HStack(spacing: 10) {
      typeIcon(
        systemImage: item.type == .nfc ? "wave.3.right.circle.fill" : "qrcode.viewfinder",
        assetImage: item.type == .nfc ? "NFCStickerLogo" : "QRStickerLogo",
        size: 26
      )

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(item.name)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(1)

          Button {
            renameItemName = item.name
            renameItemID = item.id
            showingRenamePrompt = true
          } label: {
            Image(systemName: "pencil")
              .font(.caption)
              .foregroundStyle(themeManager.themeColor)
          }
          .buttonStyle(.plain)
          .disabled(disabled)
          .accessibilityLabel("Rename \(item.name)")
        }

        Text(shortCodeValue(item.codeValue))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      if supportsPurposes {
        purposePicker(for: item)
      }

      Button(role: .destructive) {
        removeItem(item.id)
      } label: {
        Image(systemName: "trash")
          .font(.subheadline)
          .foregroundStyle(.red)
      }
      .buttonStyle(.plain)
      .disabled(disabled)
      .accessibilityLabel("Delete \(item.name)")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, itemRowVerticalPadding)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.thinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
    )
  }

  /// Three-way purpose control. `PhysicalUnblockItem.purposes` is a list, but only three of its
  /// combinations are reachable - an empty list matches nothing in `governingItems(for:)`, so it
  /// is not offered here and cannot be selected into.
  @ViewBuilder
  private func purposePicker(for item: PhysicalUnblockItem) -> some View {
    // The segments are written out rather than looped because `.segmented` only honours
    // concrete `Text` and `Image` children - a computed `some View` returning a switch becomes
    // `_ConditionalContent` and the style can render it blank.
    //
    // Pause and stop glyphs normally reach views through `BlockingStrategySessionAction`. This
    // is a profile setting rather than a session action, so it has no action to read from and
    // names the symbols directly, matching `BlockingStrategy.activeSessionAction`.
    Picker("Used for", selection: purposeSelection(for: item)) {
      Image(systemName: "pause.fill")
        .accessibilityLabel(PurposeSelection.pause.title)
        .tag(PurposeSelection.pause)

      Image(systemName: "stop.fill")
        .accessibilityLabel(PurposeSelection.stop.title)
        .tag(PurposeSelection.stop)

      Text(PurposeSelection.both.title)
        .tag(PurposeSelection.both)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
    .disabled(disabled)
  }

  @ViewBuilder
  private func addButton(title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "plus")
          .font(.system(size: 16, weight: .medium))
        Text(title)
          .fontWeight(.semibold)
          .font(.subheadline)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(.thinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 16)
              .stroke(Color.primary.opacity(0.2), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? .secondary : .primary)
    .disabled(disabled)
  }

  private func addNFCTag() {
    physicalReader.readNFCTag(
      onSuccess: { codeValue in
        addItem(codeValue: codeValue, type: .nfc)
      },
      onFailure: { message in
        // Without this the default no-op closure swallows the message, so a device that cannot
        // read NFC makes this button look broken rather than unavailable.
        showError(message)
      }
    )
  }

  private func addItem(codeValue: String, type: PhysicalUnblockItem.PhysicalUnblockType) {
    let normalizedCodeValue = PhysicalUnblockItem.normalizedCodeValue(codeValue, type: type)

    guard !normalizedCodeValue.isEmpty else {
      showError("The scanned code was empty.")
      return
    }

    guard
      !physicalUnblockItems.contains(where: {
        $0.type == type && $0.codeValue == normalizedCodeValue
      })
    else {
      showError("That \(type.displayName.lowercased()) is already in this list.")
      return
    }

    physicalUnblockItems.append(
      PhysicalUnblockItem(
        name: defaultName(for: type),
        type: type,
        purposes: PhysicalUnblockItem.PhysicalUnblockPurpose.allCases,
        codeValue: normalizedCodeValue
      )
    )
  }

  private func removeItem(_ id: UUID) {
    physicalUnblockItems.removeAll { $0.id == id }
  }

  private func applyRename() {
    guard let renameItemID,
      let itemIndex = physicalUnblockItems.firstIndex(where: { $0.id == renameItemID })
    else {
      return
    }

    let trimmedName = renameItemName.trimmingCharacters(in: .whitespacesAndNewlines)
    physicalUnblockItems[itemIndex].name =
      trimmedName.isEmpty ? physicalUnblockItems[itemIndex].type.displayName : trimmedName

    self.renameItemID = nil
  }

  private func defaultName(for type: PhysicalUnblockItem.PhysicalUnblockType) -> String {
    let nextIndex = physicalUnblockItems.filter { $0.type == type }.count + 1
    return "\(type.displayName) \(nextIndex)"
  }


  private func purposeSelection(
    for item: PhysicalUnblockItem
  ) -> Binding<PurposeSelection> {
    Binding(
      get: { PurposeSelection(purposes: item.purposes) },
      set: { selection in
        guard
          let itemIndex = physicalUnblockItems.firstIndex(where: { $0.id == item.id })
        else {
          return
        }

        physicalUnblockItems[itemIndex].purposes = selection.purposes
      }
    )
  }

  private func shortCodeValue(_ codeValue: String) -> String {
    guard codeValue.count > 28 else { return codeValue }

    let prefix = codeValue.prefix(12)
    let suffix = codeValue.suffix(8)
    return "\(prefix)...\(suffix)"
  }

  private func showError(_ message: String) {
    errorMessage = message
    showingError = true
  }
}

#Preview {
  @Previewable @State var physicalUnblockItems: [PhysicalUnblockItem] = [
    PhysicalUnblockItem(
      name: "Tag 1", type: .nfc, purposes: [.stop], codeValue: "04AABBCC11223344"),
    PhysicalUnblockItem(
      name: "Tag 2", type: .nfc, purposes: [.pause], codeValue: "https://foqos.app/profile/tag-2"),
    PhysicalUnblockItem(
      name: "Office QR", type: .qrCode, purposes: PhysicalUnblockItem.PhysicalUnblockPurpose.allCases,
      codeValue: "https://foqos.app/profile/office"),
  ]

  NavigationStack {
    Form {
      BlockedProfilePhysicalUnblockSelector(
        physicalUnblockItems: $physicalUnblockItems
      )
    }
  }
  .environmentObject(ThemeManager())
}

/// The reachable purpose combinations for a physical unblock code, as one picker value.
private enum PurposeSelection {
  case pause
  case stop
  case both

  /// Also supplies the VoiceOver labels for the two icon segments, so the three names stay
  /// defined in one place.
  var title: String {
    switch self {
    case .pause: return "Pause"
    case .stop: return "Stop"
    case .both: return "Both"
    }
  }

  var purposes: [PhysicalUnblockItem.PhysicalUnblockPurpose] {
    switch self {
    case .pause: return [.pause]
    case .stop: return [.stop]
    case .both: return PhysicalUnblockItem.PhysicalUnblockPurpose.allCases
    }
  }

  /// Anything that is not exactly one purpose reads as "both", so a legacy item carrying every
  /// purpose - the decode default for codes stored before purposes existed - lands there too.
  init(purposes: [PhysicalUnblockItem.PhysicalUnblockPurpose]) {
    switch purposes.count {
    case 1 where purposes.contains(.pause): self = .pause
    case 1 where purposes.contains(.stop): self = .stop
    default: self = .both
    }
  }
}
