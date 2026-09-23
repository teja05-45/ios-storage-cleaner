# 03 — Technical Requirements

## 1. Platform & Toolchain

- **Language:** Swift 5.10+
- **UI:** SwiftUI (no UIKit except where a native wrapper is strictly required — e.g., `PHPickerViewController`/limited-library picker presentation, `AVPlayerViewController` for full-featured video preview via `UIViewControllerRepresentable`)
- **Minimum deployment target:** iOS 17.0
- **Xcode:** 15+
- **Devices:** iPhone only; Universal build not targeted for this assignment
- **Concurrency:** Swift Concurrency (`async`/`await`, `actor`, `Task`) throughout — no completion-handler-based custom code in new services; framework callbacks are bridged into `async` at the service boundary.

## 2. Apple Frameworks Used

| Framework | Purpose |
|---|---|
| PhotoKit (`Photos`) | Enumerate/fetch photo & video assets, resources, thumbnails, deletion requests, limited-library UI |
| Contacts (`Contacts`) | Fetch, compare, and delete contact records |
| AVFoundation | Video metadata (duration, resolution via `AVAsset`), video preview playback |
| Accelerate / CoreImage | Perceptual hash computation (downsampling, grayscale, DCT/average-hash pipeline) — CPU/GPU-efficient image processing without ML model dependencies |
| Foundation | `FileManager` volume capacity keys, `ByteCountFormatter`, normalization utilities |
| UIKit (minimal) | `UIApplication.openSettingsURLString`, representable wrappers only |

**Explicitly not used:** CoreML/Vision face-detection models (would inflate scope and make "AI" claims we cannot fully substantiate/tune within this assignment — see Document 06 for the honest scope of "best photo" scoring), any third-party dependency, any networking library (the app makes zero network calls).

## 3. Third-Party Dependencies

**None**, by design. Rationale: every requirement in this assignment (perceptual hashing, contact normalization, image scoring) is implementable with native frameworks at a quality bar appropriate for a demo-ready but honest product. Adding a dependency (e.g., a phash library, a fuzzy-matching library) would trade a small amount of implementation time for supply-chain risk, black-box behavior in a privacy-sensitive app, and slower App Store review — all against this product's stated values. If a future iteration needed libphonenumber-grade phone parsing, that would be the one candidate worth reconsidering, called out explicitly in Document 06's contact section as a known limitation.

## 4. Architecture Constraints

Layered, unidirectional dependency flow:

```
Presentation (SwiftUI Views)
      ↓ (reads @Observable state, sends intents)
ViewModels / State (per-feature, @Observable, MainActor)
      ↓ (calls async use cases)
Use Cases (plain Swift types — orchestrate services, contain no framework imports beyond Foundation)
      ↓
Services (PhotoLibraryService, ContactService, StorageService, etc. — own all PhotoKit/Contacts/AVFoundation calls)
      ↓
Apple Frameworks
```

**Hard rule:** SwiftUI `View` types never import `Photos`, `Contacts`, or `AVFoundation` directly, and never call a service directly — only through a ViewModel. This is enforced by code review checklist (Document 08) and keeps every scanning/deletion code path unit-testable without a Photos/Contacts entitlement or simulator library.

Services are protocol-first (`PhotoLibraryServiceProtocol`, `ContactServiceProtocol`, …) so ViewModels/UseCases can be tested against fakes/mocks with no dependency on the real device photo library or contacts store.

## 5. State Management

- `@Observable` (Observation framework, iOS 17+) for all ViewModels — chosen over `ObservableObject`/`@Published` because it's the modern, lower-boilerplate, more granular-invalidation approach and iOS 17 is the stated minimum target, so there is no compatibility reason to use the older pattern.
- Navigation via `NavigationStack` with typed `NavigationPath` per tab — no third-party coordinator library.
- Cross-category selection state (for the Review screen) lives in a single `ReviewStore` (`@Observable`, app-scoped, injected via SwiftUI `Environment`) that each category ViewModel writes into — avoids duplicating "what's selected" state and prevents drift between a category screen's count and the Review screen's count (a safety requirement, not just a convenience).

## 6. Persistence

- No database. Two things are persisted locally, both via `FileManager` app-support directory as small JSON, or `UserDefaults` for primitives — never `Photos`/`Contacts` payloads themselves:
  - **ScanCache**: lightweight metadata (asset local identifiers, computed hashes, group membership, last-scan timestamp) so a rescan can be incremental rather than full, and so the Dashboard can show "last scan" results without re-running PhotoKit fetches on every launch.
  - **User preferences**: none required for v1 beyond scan-cache housekeeping.
- **Never persisted:** actual image bytes, thumbnails beyond the in-memory/disk `NSCache`-backed thumbnail cache (which is treated as purely disposable and can be invalidated at any time), or any contact field value beyond what's needed transiently to render the current screen.

## 7. Error Handling

- All service methods that touch PhotoKit/Contacts/AVFoundation are `throws`/`async throws` and surface typed errors (`enum ReclaimError`) rather than `NSError` passthrough, so ViewModels can present specific, actionable messaging (Document 02 §2.7) instead of generic failure text.
- Deletion requests report **partial failure** explicitly: if the OS reports N of M assets were deleted (e.g., user declined the native confirmation, or an asset became unavailable mid-flight), the Cleanup Result screen reflects the real N, not the requested M.

## 8. Build & Signing

- Standard Xcode automatic signing for development; no special entitlements beyond `NSPhotoLibraryUsageDescription`, `NSContactsUsageDescription`, and `NSPhotoLibraryAddUsageDescription` (not required unless the app ever writes — confirm at implementation time whether needed) in `Info.plist`.
- No push notifications, no background modes, no App Groups, no keychain sharing — none of the app's requirements need them.

## 9. Compiler Hygiene

- Swift Concurrency strict checking enabled where feasible; `@MainActor` isolation explicit on all UI-facing state.
- Target: zero compiler warnings in app code at completion (third-party/system-generated warnings, if any, are documented rather than suppressed blindly).
