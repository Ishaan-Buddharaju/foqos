import SwiftData
import SwiftUI

class NFCPauseTimerBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCPauseTimerBlockingStrategy"

  var name: String = "NFC + Pause Timer"
  var description: String =
    "Choose how long a pause should last. Scan an NFC tag once to pause. Scan it again during the pause to fully stop."
  var iconAssetName: String = "NFCPauseSticker"
  var color: Color = .orange
  var pickerCategory: BlockingStrategyPickerCategory = .forever

  var usesNFC: Bool = true
  var hasPauseMode: Bool = true

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return NFCPauseTimerBlockingStrategy.id
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

    // A caller with explicit intent wins; otherwise the session state decides, so an
    // un-paused session pauses first and a paused one stops.
    let unblockPurpose: PhysicalUnblockItem.PhysicalUnblockPurpose =
      purpose ?? (isPauseActive ? .stop : .pause)

    nfcScanner.onTagScanned = { tag in
      let tagId = tag.url ?? tag.id

      // Check strict mode - if physical unblock is set, it must match
      if session.blockedProfile.hasPhysicalUnblockItem(ofType: .nfc, purpose: unblockPurpose)
        && !session.blockedProfile.canUnblock(
          withCode: tagId, type: .nfc, purpose: unblockPurpose)
      {
        if unblockPurpose == .stop {
          self.onErrorMessage?(
            "This NFC tag is not allowed to stop this profile. Physical unblock setting is on for this profile"
          )
        } else {
          self.onErrorMessage?(
            "This NFC tag is not allowed to pause this profile. Physical pause setting is on for this profile"
          )
        }
        return
      }

      if unblockPurpose == .stop {
        // Fully stop the session
        DeviceActivityCenterUtil.removePauseTimerActivity(for: session.blockedProfile)
        session.endSession()
        try? context.save()
        self.appBlocker.deactivateRestrictions()
        self.onSessionCreation?(.ended(session.blockedProfile))
      } else {
        // Initiate pause mode
        DeviceActivityCenterUtil.startPauseTimerActivity(for: session.blockedProfile)

        self.onSessionCreation?(.paused)
      }
    }

    if unblockPurpose == .stop {
      nfcScanner.scan(profileName: session.blockedProfile.name)
    } else {
      nfcScanner.scan(profileName: "\(session.blockedProfile.name) - Pause")
    }

    return nil
  }
}
