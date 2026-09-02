import CodeScanner
import SwiftData
import SwiftUI

class QRPauseTimerBlockingStrategy: BlockingStrategy {
  static var id: String = "QRPauseTimerBlockingStrategy"

  var name: String = "QR/Barcode + Pause Timer"
  var description: String =
    "Choose how long a pause should last. Scan a QR code or barcode once to pause. Scan it again during the pause to fully stop."
  var iconAssetName: String = "QRPauseSticker"
  var color: Color = .indigo
  var pickerCategory: BlockingStrategyPickerCategory = .forever
  
  var usesNFC: Bool = false
  var hasTimer: Bool = false
  var startsManually: Bool = false
  var requiresSameCodeToStop: Bool = false
  var allowsTimedBreaks: Bool = true
  var isBeta: Bool = false
  var startViewPresentationDetents: Set<PresentationDetent> = [.medium, .large]

  var usesQRCode: Bool = true
  var hasPauseMode: Bool = true

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return QRPauseTimerBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    if !profile.shouldAskForStartSettings {
      startPauseTimerSession(
        context: context,
        profile: profile,
        forceStart: forceStart ?? false
      )
      return nil
    }

    let pauseTimerData = StrategyPauseTimerData.toStrategyPauseTimerData(
      from: profile.strategyData
    )

    return PauseDurationView(
      profileName: profile.name,
      initialDurationMinutes: pauseTimerData.pauseDurationInMinutes,
      onDurationSelected: { pauseDurationMinutes in
        // Save the pause duration to the profile
        let pauseTimerData = StrategyPauseTimerData(
          pauseDurationInMinutes: pauseDurationMinutes)
        if let data = StrategyPauseTimerData.toData(from: pauseTimerData) {
          profile.strategyData = data
          profile.updatedAt = Date()
          BlockedProfiles.updateSnapshot(for: profile)
          try? context.save()
        }

        self.startPauseTimerSession(
          context: context,
          profile: profile,
          forceStart: forceStart ?? false
        )
      }
    )
  }

  private func startPauseTimerSession(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool
  ) {
    appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession = BlockedProfileSession.createSession(
      in: context,
      withTag: Self.id,
      withProfile: profile,
      forceStart: forceStart
    )

    onSessionCreation?(.started(activeSession))
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession,
    purpose: PhysicalUnblockItem.PhysicalUnblockPurpose? = nil
  ) -> (any View)? {
    let isPauseActive = session.isPauseActive
    let unblockPurpose: PhysicalUnblockItem.PhysicalUnblockPurpose = purpose ?? (isPauseActive ? .stop : .pause)
    let heading = unblockPurpose == .stop ? "Scan to stop" : "Scan to pause"
    let subtitle =
      unblockPurpose == .stop
      ? "Point your camera at a QR code to fully stop this profile."
      : "Point your camera at a QR code to temporarily pause this profile."

    return LabeledCodeScannerView(
      heading: heading,
      subtitle: subtitle
    ) { result in
      switch result {
      case .success(let result):
        let tag = result.string

        // Check strict mode - if physical unblock is set, it must match
        if session.blockedProfile.hasPhysicalUnblockItem(ofType: .qrCode, purpose: unblockPurpose)
          && !session.blockedProfile.canUnblock(
            withCode: tag, type: .qrCode, purpose: unblockPurpose)
        {
          if unblockPurpose == .stop {
            self.onErrorMessage?(
              "This QR code is not allowed to stop this profile. Physical unblock setting is on for this profile"
            )
          } else {
            self.onErrorMessage?(
              "This QR code is not allowed to pause this profile. Physical pause setting is on for this profile"
            )
          }
          return
        }
        
        if unblockPurpose == .stop {
          // Pause is active - user wants to fully stop the session
          DeviceActivityCenterUtil.removePauseTimerActivity(for: session.blockedProfile)
          session.endSession()
          try? context.save()
          self.appBlocker.deactivateRestrictions()
          self.onSessionCreation?(.ended(session.blockedProfile))
        } else {
          // No pause active - initiate pause mode
          DeviceActivityCenterUtil.startPauseTimerActivity(for: session.blockedProfile)

          self.onSessionCreation?(.paused)
        }
        
      case .failure(let error):
        self.onErrorMessage?(error.localizedDescription)
      }
    }
  }
}
