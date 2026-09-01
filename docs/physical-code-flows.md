# Physical Code Flows (NFC + QR)

How Foqos reads, writes, stores, and compares NFC tags and QR/barcodes.
Every node below names the file that owns it, so this doubles as a map of where to edit.

---

## 1. The pattern in one picture

The whole feature is the **Strategy pattern** with two swappable I/O adapters
underneath it, plus a **normalize-then-compare** value object for the codes.

```mermaid
flowchart TB
    subgraph UI["UI layer"]
        HV["HomeView<br/><i>Views/HomeView.swift</i>"]
        BPV["BlockedProfileView<br/><i>Views/BlockedProfileView.swift</i>"]
        SEL["PhysicalUnblockSelector<br/><i>Components/BlockedProfileView/<br/>BlockedProfilePhysicalUnblockSelector.swift</i>"]
    end

    subgraph COORD["Coordinator"]
        SM["StrategyManager<br/><i>Utils/StrategyManager.swift</i><br/>owns activeSession, routes start/stop"]
    end

    subgraph STRAT["Strategy layer — protocol BlockingStrategy"]
        direction LR
        NFCS["NFC* strategies<br/>Blocking / Timer / Manual /<br/>PauseTimer / SoftUnblock"]
        QRS["QR* strategies<br/>Code / Timer / Manual /<br/>PauseTimer / SoftUnblock"]
    end

    subgraph IO["I/O adapters — the only code touching hardware"]
        NFCR["NFCScannerUtil<br/><i>Utils/NFCScannerUtil.swift</i><br/>read"]
        NFCW["NFCWriter<br/><i>Utils/NFCWriter.swift</i><br/>write"]
        QRR["LabeledCodeScannerView<br/><i>Components/Strategy/QRCodeScanner.swift</i><br/>read"]
        QRG["QRCodeView<br/><i>Components/Strategy/QRCodeView.swift</i><br/>generate"]
        PR["PhysicalReader<br/><i>Utils/PhysicalReader.swift</i><br/>façade over both, used by profile editing"]
    end

    subgraph MODEL["Model layer — SwiftData"]
        PUI["PhysicalUnblockItem<br/><i>Models/PhysicalUnblockItem.swift</i><br/>value object + normalization"]
        BP["BlockedProfiles<br/><i>Models/BlockedProfiles.swift</i><br/>physicalUnblockItems, canUnblock"]
        SESS["BlockedProfileSession<br/><i>Models/BlockedProfileSessions.swift</i><br/>tag, forceStarted"]
    end

    HV --> SM
    BPV --> NFCW
    BPV --> QRG
    SEL --> PR
    PR --> NFCR
    PR --> QRR
    SM --> STRAT
    NFCS --> NFCR
    QRS --> QRR
    STRAT --> SESS
    STRAT --> BP
    SEL --> PUI
    BP --> PUI
    SESS --> BP
```

**The contract that makes it swappable** — `Models/Strategies/BlockingStrategy.swift`:

```swift
func startBlocking(context:profile:forceStart:) -> (any View)?
func stopBlocking(context:session:)             -> (any View)?
```

Returning `View?` is the key design decision. QR strategies return a scanner view that
`StrategyManager.presentCustomStrategyView` puts on screen; NFC strategies return `nil`
because CoreNFC presents its own system sheet. Same call site, two very different UIs.

---

## 2. Read paths — where a "code" comes from

```mermaid
flowchart LR
    subgraph NFC["NFC — Utils/NFCScannerUtil.swift"]
        A["NFCTagReaderSession<br/>.iso14443 + .iso15693"] --> B{"tag type"}
        B -->|miFare / iso15693| C["readNDEF"]
        B -->|iso7816| E
        C -->|success| D["updateWithNDEFMessageURL<br/>keep URI records where<br/>scheme==https AND host==foqos.app<br/>and exactly one matches"]
        C -->|"error or nil — non-fatal"| E["identifier.hexEncodedString<br/>uppercase hex UID"]
        D --> F["NFCResult id: UID, url: URL?"]
        E --> F
    end

    subgraph QR["QR — Components/Strategy/QRCodeScanner.swift"]
        G["CodeScannerView<br/>qr, aztec, pdf417, dataMatrix,<br/>code39/93/128, ean8/13, itf14, upce"] --> H["ScanResult.string"]
    end

    F --> I["url ?? id"]
    H --> J["raw string"]
    I --> K(["code value"])
    J --> K
```

Two things worth knowing before you edit here:

- `result.url ?? result.id` — **a foqos.app URL always beats the hardware UID.** Same
  physical tag yields a different code value before vs. after you write a profile to it.
- The QR side is a superset of QR: barcodes are accepted everywhere QR is.

---

## 3. Write / generate path

```mermaid
flowchart LR
    P["BlockedProfiles.getProfileDeepLink<br/><i>Models/BlockedProfiles.swift:380</i><br/>https://foqos.app/profile/UUID"]
    P --> W["NFCWriter.writeURL<br/>queryNDEFStatus → reject notSupported/readOnly<br/>reject iso7816/feliCa<br/>check message.length ≤ capacity"]
    P --> G["QRCodeView.generateQRCode<br/>CIFilter.qrCodeGenerator, level M, 10×"]
    W --> T(["NDEF URI payload on tag"])
    G --> Q(["on-screen QR image"])
```

`NFCScannerUtil.writeURL` is a **dead second implementation** using `NFCNDEFReaderSession`;
nothing wires to it. Delete it or keep it in mind so you don't edit the wrong one.

---

## 4. Storage — two stores, easy to conflate

```mermaid
classDiagram
    class BlockedProfileSession {
        +String tag
        +Bool forceStarted
        "the code that STARTED this session"
    }
    class BlockedProfiles {
        +physicalUnblockItems: [PhysicalUnblockItem]?
        +canUnblock(withCode, type) Bool
        +hasPhysicalUnblockItem(ofType) Bool
        "the allow-list of codes that may STOP it"
        --deprecated--
        +physicalUnblockNFCTagId: String?
        +physicalUnblockQRCodeId: String?
    }
    class PhysicalUnblockItem {
        +UUID id
        +String name
        +PhysicalUnblockType type
        +String codeValue
        +normalizedCodeValue(_, type)$ String
        +resolvedItems(...)$ [PhysicalUnblockItem]?
    }
    BlockedProfileSession --> BlockedProfiles
    BlockedProfiles --> PhysicalUnblockItem
```

- **Session tag** is written once at `createSession(in:withTag:…)`, **unnormalized**.
- **Allow-list** is normalized on the way in *and* on every comparison.
  `normalizedCodeValue` trims always; for `.qrCode` only, it lowercases scheme + host and
  drops a bare trailing `/`. NFC values get trimming only.
- Legacy single-code fields are folded into the array on launch by
  `Models/Migrations/BlockedProfilesMigration.swift`, then nil'd.

---

## 5. Stop-time comparison — the rule every strategy repeats

```mermaid
flowchart TD
    S(["scanned code"]) --> A{"profile.hasPhysicalUnblockItem<br/>ofType: nfc / qrCode ?"}
    A -->|yes| B{"canUnblock withCode:type: ?<br/>normalize both sides,<br/>exact match, type must match"}
    B -->|yes| OK(["endSession + deactivateRestrictions"])
    B -->|no| E1(["error: not allowed to unblock<br/>this profile"])
    A -->|no| C{"session.forceStarted ?"}
    C -->|yes| OK
    C -->|no| D{"session.tag == code ?<br/>raw equality, no normalization"}
    D -->|yes| OK
    D -->|no| E2(["error: must scan the original tag"])
```

Consequences to keep in mind when editing:

- An allow-list **replaces** the same-code rule for that type. Any listed code stops the
  session; the original session tag stops mattering.
- The two branches use different equality: normalized in the allow-list branch, raw in
  the fallback branch.
- `forceStarted` — set by deep-link and background/Shortcut starts — skips the check entirely.

This block is duplicated in all ten strategies. If you change the rule, change it in each
of `Models/Strategies/{NFC,QR}*BlockingStrategy.swift`, or hoist it into
`BlockingStrategy`'s protocol extension first.

---

## 6. The tap-to-toggle path bypasses all of the above

```mermaid
sequenceDiagram
    participant Tag as "NFC tag / QR camera"
    participant iOS
    participant App as "foqosApp.swift:60"
    participant Nav as "NavigationManager"
    participant Home as "HomeView.swift:215"
    participant SM as "StrategyManager"

    Tag->>iOS: universal link https://foqos.app/profile/UUID
    iOS->>App: onOpenURL / onContinueUserActivity
    App->>Nav: handleLink
    Nav->>Nav: split path → "profile/UUID" or "navigate/UUID"
    Nav-->>Home: @Published profileId
    Home->>SM: toggleSessionFromDeeplink
    SM->>SM: findProfile byID
    alt active session exists
        SM->>SM: refuse if disableBackgroundStops
        SM->>SM: ManualBlockingStrategy.stopBlocking
        SM->>SM: start other profile if different, forceStart true
    else no active session
        SM->>SM: ManualBlockingStrategy.startBlocking, forceStart true
    end
```

No scanner and **no code comparison** runs here — possession of the URL is the entire
authorization, and the session it creates is `forceStarted`, so it is later exempt from
the same-code rule too.

---

## 7. File map

| Concern | File |
| --- | --- |
| NFC read | `Foqos/Utils/NFCScannerUtil.swift` |
| NFC write | `Foqos/Utils/NFCWriter.swift` |
| QR/barcode read | `Foqos/Components/Strategy/QRCodeScanner.swift` |
| QR generate | `Foqos/Components/Strategy/QRCodeView.swift` |
| Read façade for profile editing | `Foqos/Utils/PhysicalReader.swift` |
| Strategy contract | `Foqos/Models/Strategies/BlockingStrategy.swift` |
| Strategy implementations | `Foqos/Models/Strategies/{NFC,QR}*.swift` |
| Routing / active session | `Foqos/Utils/StrategyManager.swift` |
| Code value + normalization | `Foqos/Models/PhysicalUnblockItem.swift` |
| Allow-list + `canUnblock` | `Foqos/Models/BlockedProfiles.swift` |
| Session tag + `forceStarted` | `Foqos/Models/BlockedProfileSessions.swift` |
| Legacy field migration | `Foqos/Models/Migrations/BlockedProfilesMigration.swift` |
| Allow-list editing UI | `Foqos/Components/BlockedProfileView/BlockedProfilePhysicalUnblockSelector.swift` |
| Deep-link entry | `Foqos/foqosApp.swift`, `Foqos/Utils/NavigationManager.swift` |
