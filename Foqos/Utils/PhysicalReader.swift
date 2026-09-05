import CodeScanner
import CoreNFC
import SwiftUI

class PhysicalReader {
  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()

  /// Distinct synthetic values per call so the selector's duplicate guard does not reject the
  /// second code you add while testing. Returns nil off-simulator, where the real hardware runs.
  static func simulatedQRCodeValue() -> String? {
    #if targetEnvironment(simulator)
      return "https://foqos.app/profile/\(UUID().uuidString)"
    #else
      return nil
    #endif
  }

  static func simulatedNFCTagId() -> String {
    return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).uppercased()
  }

  func readNFCTag(
    onSuccess: @escaping (String) -> Void,
    onFailure: @escaping (String) -> Void = { _ in }
  ) {
    #if targetEnvironment(simulator)
      // CoreNFC has no simulator support at all, so `readingAvailable` is always false and the
      // real path can only ever report an error. Hand back a synthetic tag id instead so the
      // rest of the flow - registering codes, assigning purposes - stays exercisable.
      onSuccess(PhysicalReader.simulatedNFCTagId())
    #else
      nfcScanner.onTagScanned = { result in
        let tagId = result.url ?? result.id
        onSuccess(tagId)
      }
      nfcScanner.onError = onFailure

      nfcScanner.scan(profileName: "")
    #endif
  }

  func readQRCode(
    onSuccess: @escaping (String) -> Void,
    onFailure: @escaping (String) -> Void
  ) -> some View {
    return LabeledCodeScannerView(
      heading: "Scan to set",
      subtitle: "Point your camera at a QR/Barcode code to set a physical unblock.",
      simulatedData: PhysicalReader.simulatedQRCodeValue()
    ) { result in
      switch result {
      case .success(let scanResult):
        onSuccess(scanResult.string)
      case .failure(let error):
        onFailure(error.localizedDescription)
      }
    }
  }
}
