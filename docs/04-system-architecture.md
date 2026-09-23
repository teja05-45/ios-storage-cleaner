# 04 — System Architecture

## 1. Module Map

```
Reclaim (App target)
│
├── App/
│   ├── ReclaimApp.swift               — @main, environment wiring
│   ├── RootTabView.swift              — Dashboard / Clean Up / Review tabs
│   └── AppEnvironment.swift           — composition root: builds real services,
│                                         injects into ReviewStore + feature ViewModels
│
├── Core/
│   ├── Models/                        — see Document 05, no framework imports
│   ├── Utilities/
│   │   ├── ByteFormatting.swift
│   │   ├── PerceptualHash.swift       — hashing math (pure, testable, no PhotoKit)
│   │   ├── HammingDistance.swift
│   │   ├── ContactNormalizer.swift    — phone/email/name normalization (pure)
│   │   └── NameSimilarity.swift       — Levenshtein / token overlap scoring
│   └── Extensions/
│       └── FileManager+Storage.swift  — volume capacity key helpers
│
├── Features/
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   └── DashboardViewModel.swift
│   ├── PhotoCleanup/                  — Similar Photos (incl. exact duplicates)
│   │   ├── PhotoGroupListView.swift
│   │   ├── PhotoGroupDetailView.swift
│   │   └── PhotoCleanupViewModel.swift
│   ├── Screenshots/
│   │   ├── ScreenshotsView.swift
│   │   └── ScreenshotsViewModel.swift
│   ├── LargeVideos/
│   │   ├── LargeVideosView.swift
│   │   ├── VideoPreviewView.swift     — AVPlayer wrapper
│   │   └── LargeVideosViewModel.swift
│   ├── Contacts/
│   │   ├── DuplicateContactsView.swift
│   │   ├── ContactGroupDetailView.swift
│   │   └── ContactCleanupViewModel.swift
│   ├── Review/
│   │   ├── ReviewView.swift
│   │   └── ReviewStore.swift          — @Observable, app-scoped selection aggregator
│   └── CleanupResult/
│       ├── CleanupResultView.swift
│       └── CleanupResultViewModel.swift
│
├── UseCases/
│   ├── ScanPhotosUseCase.swift        — orchestrates PhotoScanner + DuplicateDetector + SimilarityDetector
│   ├── ScanScreenshotsUseCase.swift
│   ├── ScanVideosUseCase.swift
│   ├── ScanContactsUseCase.swift
│   ├── ComputeStorageSummaryUseCase.swift
│   └── PerformCleanupUseCase.swift    — takes a CleanupSelection, calls CleanupService, returns CleanupSummary
│
├── Services/
│   ├── PhotoLibraryService.swift      — protocol + impl: auth, fetch assets/resources, thumbnails, delete
│   ├── PhotoScanner.swift             — enumerates PHAssets into PhotoAsset models, batched
│   ├── DuplicateDetector.swift        — exact-duplicate grouping
│   ├── SimilarityDetector.swift       — phash pipeline + clustering (see Document 06)
│   ├── ScreenshotDetector.swift       — thin filter over PhotoScanner output
│   ├── VideoScanner.swift             — video-specific metadata via AVAsset
│   ├── ContactService.swift           — protocol + impl: auth, fetch, delete/merge via CNSaveRequest
│   ├── DuplicateContactDetector.swift — normalization + matching (see Document 06)
│   ├── StorageService.swift           — FileManager volume capacity
│   └── CleanupService.swift           — executes approved CleanupSelection against Photo/Contact services
│
└── Infrastructure/
    ├── ThumbnailCache.swift           — NSCache<NSString, UIImage> wrapper, disposable
    ├── ScanCache.swift                — lightweight local persistence of scan metadata (JSON on disk)
    └── Logging.swift                  — os.Logger wrappers, no PII/media in log messages
```

## 2. Dependency Direction

```
Features  ──depends on──>  UseCases  ──depends on──>  Services  ──depends on──>  Apple Frameworks
   │                             │
   └────────depends on───────────┴──> Core/Models, Core/Utilities
```

- **Core** depends on nothing else in the app (no imports of `Photos`/`Contacts`/`AVFoundation`). This is what makes `PerceptualHash`, `HammingDistance`, `ContactNormalizer`, and byte-size math unit-testable in milliseconds with no simulator library needed.
- **Services** are the *only* layer that imports `Photos`, `Contacts`, or `AVFoundation`. Every service is defined behind a protocol (`PhotoLibraryServiceProtocol`, etc.) so UseCases can be tested against an in-memory fake.
- **UseCases** depend on Service protocols (never concrete types) and on Core models — never on SwiftUI.
- **Features** (Views + ViewModels) depend on UseCases and Core models. Views never import a Service or framework type directly; they read `@Observable` ViewModel state and call ViewModel intents (`func toggleSelection(_:)`, `func startScan()`).
- **ReviewStore** is the one piece of cross-feature shared state. It is owned by `AppEnvironment` and injected into every feature ViewModel that can contribute selections, and read by `ReviewView`. This avoids a circular dependency between features (e.g., PhotoCleanup does not depend on Review; both depend downward on ReviewStore, which lives in Features/Review but exposes only Core-level types in its public API to avoid Features→Features coupling).

No circular dependencies: arrows only ever point downward (Features → UseCases → Services → Frameworks, plus everything → Core). `ReviewStore` is the single deliberate exception and is scoped narrowly (selection aggregation only) to avoid becoming a god-object.

## 3. Composition Root

`AppEnvironment` is constructed once in `ReclaimApp` and is the only place concrete service implementations are instantiated and wired to protocols. This is what allows:

- Preview providers and unit tests to construct an `AppEnvironment` with fake services
- No singleton/global service locators — everything is explicit dependency injection via initializers or SwiftUI `Environment`

## 4. Key Architecture Decisions

### ADR-01: `@Observable` over Combine/`ObservableObject`
**Decision:** Use the Observation framework for all ViewModels.
**Reason:** iOS 17 minimum target removes any compatibility reason to use the older pattern; `@Observable` gives cheaper, property-level invalidation which matters for large grids (thousands of photo cells).
**Alternative considered:** `ObservableObject` + `@Published`.
**Tradeoff:** Slightly less familiar to engineers coming from older SwiftUI codebases; documentation/examples in the wild skew toward the older pattern. Accepted given the target OS floor.

### ADR-02: No third-party dependency for perceptual hashing or fuzzy contact matching
**Decision:** Implement average-hash/dHash-style perceptual hashing and Levenshtein-based name similarity natively using CoreImage/Accelerate and plain Swift.
**Reason:** Keeps the privacy story airtight (auditable, no opaque library reaching into image bytes or contact data), avoids App Store review risk from unmaintained dependencies, and the required accuracy bar for this assignment does not need a production-grade CV/NLP library.
**Alternative considered:** A CocoaPod/SPM phash library; libphonenumber for E.164-grade phone normalization.
**Tradeoff:** Our phone normalization is a best-effort digit-suffix comparison (documented as a known limitation in Document 06/README), not full ITU E.164 parsing. Accepted as an explicit, disclosed tradeoff rather than a hidden gap.

### ADR-03: Single cross-feature `ReviewStore` instead of a shared "global selection" inside each ViewModel
**Decision:** One `@Observable` aggregator, injected everywhere selections can originate.
**Reason:** The Review screen's count *must* equal the sum of real per-category selections at all times — this is a stated safety requirement (Document 08), and having four independently-tracked selection sets risks drift (a bug class we specifically want to make structurally hard to introduce).
**Alternative considered:** Have `ReviewView` re-query each feature ViewModel on appearance.
**Tradeoff:** Slightly more coupling (every feature ViewModel takes a `ReviewStore` dependency) in exchange for a single source of truth. Accepted — correctness here is higher priority than modularity purity.

### ADR-04: Incremental `ScanCache` rather than full rescan on every launch
**Decision:** Persist per-asset hash/metadata keyed by `PHAsset.localIdentifier`, and on rescan only process assets that are new or whose `modificationDate` changed.
**Reason:** Performance at 10,000+ photo scale (Document 09) — full re-hashing on every app open would make the product feel slow and would work against the "trust" goal (a tool that feels laggy feels less trustworthy).
**Alternative considered:** Always full rescan for simplicity/correctness.
**Tradeoff:** Added complexity (cache invalidation logic) and a small risk of stale group membership if hashing logic itself changes between app versions — mitigated by a cache schema version key that forces a full rescan on algorithm changes.
