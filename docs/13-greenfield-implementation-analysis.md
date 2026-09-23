# 13 — Greenfield Implementation Analysis

**Status:** Pre-implementation. Written before any application code exists.
**Correction layer:** `00-senior-review-and-required-changes.md` was requested but not supplied for this build. This document is therefore based solely on Documents 01–12. If a senior review document is provided later, this file must be re-diffed against it before implementation continues, since any conflict it raises is designated to take precedence over the base spec.

---

## 1. Existing State

> No application codebase exists. Implementation starts from scratch.

There is no `.xcodeproj`, no `Package.swift`, no Swift source files, no test target, no `Info.plist`, and no `README.md` in this repository yet. Everything referenced below (`AppEnvironment`, `PhotoLibraryService`, `ReviewStore`, etc.) exists only as a name inside Documents 04/05/10 — none of it has been written. This analysis is a planning artifact, not a code diff.

What *does* exist and is usable as-is:
- 12 planning documents (`01`–`12`), read in full, cross-checked for internal consistency.
- No contradictions were found between documents during this pass (e.g., Document 01 §3.2's "similar photos" claim matches Document 06 §2's actual dHash/Hamming-distance implementation; Document 05's `CleanupSelection.isEmpty` guard matches Document 08's safety test `test_emptySelectionCannotBeConfirmed`; Document 07's "zero network calls" claim matches Document 03 §3's "no networking library" constraint).

---

## 2. Requirements Inventory

Status is uniformly **NOT STARTED** for every item (greenfield). Complexity/risk/testing columns are what differentiate build order and effort, which is what this inventory is for.

### 2.1 Foundation & Cross-Cutting

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| Xcode project scaffold, folder structure (Doc 04) | Low | None | Wrong Swift/deployment-target settings block everything downstream | Smoke build only |
| Design system (colors, typography, reusable components — Doc 02) | Low–Med | Project scaffold | Hardcoded colors instead of semantic ones break dark mode; non-Dynamic-Type text breaks accessibility | SwiftUI preview coverage per component state |
| `@Observable` ViewModel pattern + `NavigationStack` per tab | Low | Project scaffold | None significant — well-trodden iOS 17 pattern | N/A structurally, covered by feature tests |
| `AppEnvironment` composition root (DI) | Low | Project scaffold | Accidental singleton/service-locator creep defeats testability goal | Unit test: fake `AppEnvironment` builds without touching real Photos/Contacts |
| `ReviewStore` (cross-feature selection aggregator) | Med | Data model | This is the single most safety-critical piece of shared state in the app — a bug here silently breaks the "Review count == real selection count" invariant | Dedicated unit test suite; this is effectively Doc 08 §1 "Selection logic" |
| Core models (`PhotoAsset`, `PhotoGroup`, `VideoAsset`, `ContactCandidate`, `ContactGroup`, `ScanResult`, `StorageSummary`, `CleanupSelection`, `CleanupSummary`) | Low | None (Foundation-only) | Accidentally importing `Photos`/`Contacts` into Core breaks the testability architecture (Doc 04 §2) | Full unit coverage since these are cheap, no-framework types |
| `ScanCache` persistence (JSON, `FileManager` app-support dir) | Med | Core models | Schema versioning bug could silently mix hash semantics across algorithm changes | Unit test: cache round-trip; schema-version bump forces rescan |
| `ThumbnailCache` (`NSCache`) | Low | None | Treating cache as source of truth instead of disposable (would violate Doc 07 §4) | Unit test: cache eviction doesn't crash re-fetch path |
| `Logging.swift` (PII-safe logging) | Low | None | Accidentally logging a model instance instead of primitives leaks private data into logs | Unit test / compile-time constraint: logging API only accepts primitives |

### 2.2 Permissions

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| PhotoKit authorization (`PHPhotoLibrary.authorizationStatus(for: .readWrite)`) mapped to 5-state UI (Doc 01 §3.7) | Med | Core models | `.readWrite` vs `.addOnly` distinction is easy to get wrong; `.limited` is a distinct case from `.authorized` that's easy to collapse by mistake | Unit test: auth-state → `PermissionState` mapping via fake service, all 5 states |
| Contacts authorization (`CNContactStore.authorizationStatus`) | Low–Med | Core models | Requesting at the wrong screen entry point (must be Contacts-screen-specific per Doc 07 §5, not bundled with Photos prompt) | Unit test: mapping; manual test of prompt timing |
| Limited Library banner + `presentLimitedLibraryPicker` | Med | Permission mapping | UIKit bridging via `UIViewControllerRepresentable` needed since this is not a native SwiftUI API; must not present it more than once per session (non-nagging requirement) | Manual test: picker opens, selection expands correctly |
| Settings deep link (`UIApplication.openSettingsURLString`) | Low | Permission mapping | None significant | Manual test only (can't fully simulate Settings app) |
| Mid-session permission revocation re-check on foreground | Med | Permission mapping | Easy to skip — requires a foreground-lifecycle hook (`scenePhase`), not just a cold-launch check; this is explicitly called out in Doc 07 §8 as a required behavior, not an edge case | Safety test: revoke mid-session, foreground, verify no stale-permission API call |

### 2.3 Storage Dashboard

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `StorageService` via `FileManager`/`URLResourceKey` volume capacity keys | Low–Med | None | **API risk, flagged for Phase 4 verification** — the exact correct key set (`.volumeAvailableCapacityForImportantUsageKey` vs `.volumeAvailableCapacityKey` vs `.volumeTotalCapacityKey`) must be verified against current iOS 17 behavior before implementation, not assumed from memory | Only partially unit-testable (device-dependent); documented as device-verified |
| Category summary cards (pre-scan "Not scanned yet" vs post-scan state) | Low | `ScanResult` model | Fabricating a zero instead of an honest "not scanned" state — spec explicitly forbids this (Doc 02 §4.1) | UI test: pre-scan empty state shows no fabricated numbers |
| "Estimated recoverable" derivation rule | Low | `ScanResult`, `CleanupSelection` | Must never be modeled/approximated — always summed from real `PHAssetResource` sizes (Doc 01 §3.1) | Unit test: recoverable bytes = sum of selected asset byte sizes, cross-category |
| Last-scan timestamp persistence | Low | `ScanCache` | None significant | Unit test |

### 2.4 Photo Scanning — Enumeration & Exact Duplicates

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `PhotoScanner` — batched `PHAsset` enumeration into `PhotoAsset`/`VideoAsset` | Med | Permissions, Core models | Doing this on the main actor kills responsiveness at 10k+ scale (Doc 09 §2); must use `autoreleasepool` per batch | Integration test against seeded library; unit test for batching behavior |
| `DuplicateDetector` — (dimensions, size) bucketing + SHA-256 verification (streamed) | Med–High | PhotoScanner | Loading full resource data into memory instead of streaming defeats the memory goal (Doc 09 §2); must use `PHAssetResourceManager.requestData` incrementally with `CryptoKit`'s incremental `SHA256` | Unit tests per Doc 08 §1 (bucketing correctness, SHA-256 match/no-match cases) |

### 2.5 Similar Photos & Best-Photo Scoring

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| Metadata pre-bucketing (creation-date window) | Med | PhotoScanner | Midnight-crossing burst edge case explicitly called out in Doc 06 §2 — needs deliberate window-boundary handling, not naive same-calendar-day grouping | Unit test: burst spanning midnight still buckets together |
| `PerceptualHash` (dHash, 64-bit) via CoreImage/Accelerate | High | Thumbnail fetch | Getting the resize/grayscale/bit-encoding pipeline subtly wrong produces silently-wrong hashes that still "work" on trivial cases but fail on real photos — needs fixture-based testing against real image pairs, not just synthetic data | Unit tests per Doc 08 §1: determinism, identical→0, known-near-dup→≤5, known-dissimilar→>5 |
| `HammingDistance` (XOR + popcount) | Low | PerceptualHash | None significant — simple bitwise op | Unit test: known distance values |
| Union-find clustering | Med | HammingDistance | Transitive-chain bug (A~B~C merges correctly even if A vs C exceeds threshold) is the one correctness property explicitly required by Doc 06 §2 step 7 | Unit test: transitive chain fixture |
| Confidence score (`1 - avgPairwiseDistance/64`) | Low | Clustering | None significant | Unit test against fixture distances |
| Best-photo scoring (resolution/sharpness/exposure/file-size weighted) | High | Clustering | Laplacian-variance sharpness via `vImage` convolution is the most implementation-risky single algorithm in the whole app — getting the convolution kernel or normalization wrong produces a scoring function that looks plausible but ranks incorrectly on real bursts | Unit test: known fixture ranks correctly; qualitative validation against real sample bursts before treating as done |
| `reason` string generation | Low | Best-photo scoring | Must never claim an unimplemented signal (face detection etc. — hard prohibition, Doc 06 §3) | Unit test: reason string only references implemented signals |

### 2.6 Screenshots

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `ScreenshotDetector` — `mediaSubtypes.contains(.photoScreenshot)` filter | Low | PhotoScanner | Near-zero risk; this is explicitly the simplest category by design (Doc 06 §4) | Unit test: filter predicate on fixture assets |
| Grid UI, Select All/Deselect All, live running total | Low–Med | ScreenshotDetector, ReviewStore | None significant | UI test: select-all/deselect-all + running total accuracy |

### 2.7 Large Videos

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `VideoScanner` — metadata-only enumeration (`pixelWidth/Height/duration` from `PHAsset`, not `AVAsset`, during list phase) | Med | PhotoScanner | Instantiating `AVAsset` per video during the scan phase (instead of lazily on preview open) would silently violate the Doc 06 §5 / Doc 09 performance requirement — easy mistake if a dev reaches for `AVAsset` out of habit | Unit test: sort order on fixtures; Instruments-verified (Phase 13) that no `AVAsset` is created during scan |
| `VideoPreviewView` (`AVPlayerViewController` via `UIViewControllerRepresentable`) | Med | VideoScanner | Must actually play, not just render a static player chrome — this is a **hard requirement**, not optional (Doc 01 §3.4) | Manual test: real seeded video plays |
| File-size fallback to `AVURLAsset` when `PHAssetResource` size unavailable | Low–Med | VideoScanner | Edge case that's easy to skip and only surfaces on certain asset origin types | Unit test with a fixture forcing the fallback path |

### 2.8 Duplicate Contacts

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `ContactNormalizer` (phone/email normalization) | Med | None (Foundation-only) | Phone normalization is explicitly a documented, disclosed heuristic (last-10-digit suffix), not full E.164 — the risk isn't the code, it's *forgetting to disclose the limitation* in the README | Unit tests per Doc 08 §1: phone suffix matching, country-code precision-over-recall case, email case/whitespace, `+tag` stripping (off by default) |
| `NameSimilarity` (Levenshtein / token overlap) | Med | None | Reordered-name case ("Smith, John" vs "John Smith") is an explicit test requirement, easy to miss in a naive Levenshtein-only implementation | Unit test: reordered name fixtures |
| `DuplicateContactDetector` — Exact/Probable tier classification | High | Normalizer, NameSimilarity | **The single highest product-risk algorithm in the app.** The false-positive guard (name-similarity-alone, zero field overlap → never surfaced) is explicitly called the most important unit test in Doc 08 §1 — getting this wrong risks a user losing a real, unique contact | Unit tests per Doc 08 §1, especially the false-positive guard and the >8-contact oversized-bucket demotion rule |
| `ContactService` fetch (minimal key-fetch set) | Low–Med | Permissions | Over-fetching keys beyond the documented minimal set violates Doc 07 §5's minimal-permission-footprint spirit even though it's not a hard API violation | Integration test: verify only requested keys are fetched |
| Contact deletion via `CNSaveRequest` | Med | ContactService | No OS-level secondary confirmation exists for contacts (unlike PhotoKit) — this is explicitly why Doc 07 §7 assigns the *full* safety weight to the in-app review screen for this category; a bug here has no OS safety net | Safety test: only selected contacts deleted, others verifiably untouched |
| Merge preview (field-diff, which record survives) | High | ContactGroup model | Spec explicitly forbids fake/automatic merging (Doc 01 §3.5) — if true merge (construct merged `CNMutableContact`, save, then delete original) proves too risky for the timeline, the spec itself pre-authorizes falling back to a review+delete-only workflow, documented as a limitation | Manual test: field-diff preview accurately reflects real `CNContact` field differences |

### 2.9 Review & Cleanup

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| `ReviewView` — aggregated cross-category selection | Med | ReviewStore, all category ViewModels | Count drift between a category screen and Review is a named risk in ADR-03 (Doc 04) — mitigated architecturally by single-source-of-truth `ReviewStore`, but only if every category ViewModel actually writes through it (a single ViewModel that maintains local-only selection state would silently reintroduce the exact bug the architecture was designed to prevent) | Safety test: Review count == sum of real per-category selections at all times |
| `PerformCleanupUseCase` | High | ReviewStore, CleanupSelection | **This is the single most safety-critical function in the entire app.** Must be the *only* code path that can trigger deletion; must throw on empty selection; must revalidate selected IDs are still valid before executing (staleness guard) | The entire Doc 08 §4 safety test suite targets this function directly |
| `CleanupService` — `PHPhotoLibrary.performChanges` / `CNSaveRequest` execution | High | PerformCleanupUseCase | Partial-failure handling (N of M deleted) is a hard requirement — a naive implementation that assumes "requested == deleted" silently violates Doc 05 §10's `CleanupSummary` contract | Safety test: mixed success/failure fixture reports accurate `failures` array |
| Stale-selection revalidation before delete | High | CleanupService | Explicitly required by the assignment framing (stale assets/contacts, changed permissions, changed selection) but not spelled out as its own named component in Doc 04 — **this is a gap the architecture doc leaves implicit; it should be an explicit step inside `PerformCleanupUseCase`, not assumed to fall out of existing code** | Safety test: fixture where an asset ID has become invalid between Review and Confirm → safely skipped, reported, not crashed |
| `CleanupResultView` — real pre/post `StorageSummary` diff | Med | StorageService, CleanupService | Reporting the pre-computed estimate instead of a real recomputed post-cleanup value would violate the single most repeated honesty requirement in the whole spec (Doc 01 §3.6, Doc 02 §4.9, Doc 05 §10, Doc 07 §7) | Safety test: `bytesFreed` independently recomputed in test, not trusted from the same code path that produced the UI value |

### 2.10 Testing & Performance (cross-cutting, not a single feature)

| Requirement | Complexity | Dependencies | Major Risks | Testing Requirements |
|---|---|---|---|---|
| Full Doc 08 §4 safety suite | High | All of §2.9 above | If written *after* everything else instead of alongside each phase (per Doc 10's own phase-by-phase testing mandate), safety regressions become expensive to trace | Itself is the requirement |
| Instruments-verified performance pass (10k+/1k+/500+) | High | Feature-complete pipeline | Requires physical device access — cannot be fully satisfied in this environment (see §5 Risk Register) | Manual, recorded measurements only — never fabricated numbers |
| Zero-network-traffic verification | Low | Feature-complete app | Easy to verify, easy to forget to actually run and record | Instruments Network instrument during a full session |

---

## 3. Architecture Readiness

**Overall assessment: the specification contains enough information to begin implementation.** Documents 03–05 in particular are unusually precise — down to actor isolation rules, dependency-direction diagrams, and exact model field lists — which is atypical for a planning package at this stage and substantially de-risks the build. That said, a few points need resolution before or during early implementation rather than being silently assumed.

### 3.1 Ambiguities

1. **Stale-selection revalidation is required by policy (this prompt, Doc 09 §8 partially) but has no named component in Doc 04's module map.** The architecture lists `PerformCleanupUseCase` and `CleanupService` but doesn't say *where* the "is this asset ID still valid / still selected / still authorized" check lives. Recommendation: make it an explicit first step inside `PerformCleanupUseCase.execute`, re-querying `PhotoLibraryService`/`ContactService` for current existence/authorization before calling `CleanupService`, and document this as an addendum to Doc 04.
2. **Contact "true merge" vs. "review + delete" is explicitly left as a build-time decision** ("If this becomes too risky for the five-day deadline... document merge as a limitation" — this prompt; Doc 01 §3.5 describes merge-preview UI without mandating that a `CNMutableContact` merge-then-delete actually executes). This needs to be decided *before* Phase 10 implementation begins, not discovered mid-build, since the UI (merge/delete preview) is designed to accommodate either outcome but the `ContactService` API surface differs (does it need a `merge(primary:into:)` method or only `delete(ids:)`?).
3. **`NSPhotoLibraryAddUsageDescription` necessity is explicitly flagged as unconfirmed** in Doc 03 §8 ("confirm at implementation time whether needed"). Since the app only ever deletes (never adds/saves) photos, this key is very likely unnecessary — but this should be confirmed against actual `PHPhotoLibrary.performChanges`-for-deletion behavior in Phase 4 API verification, not left as a TODO that ships either an unnecessary permission string or a missing one.
4. **Exact volume-capacity `URLResourceKey` set is named generically** ("volume capacity keys") rather than pinned to specific keys. iOS has multiple related keys (`.volumeAvailableCapacityKey`, `.volumeAvailableCapacityForImportantUsageKey`, `.volumeAvailableCapacityForOpportunisticUsageKey`, `.volumeTotalCapacityKey`) with different semantics (the "important usage" key is generally the more accurate "storage settings"-matching value on modern iOS). This must be verified against current API behavior in Phase 4, not guessed.

### 3.2 Contradictory Requirements

None found. The spec is unusually disciplined about not contradicting itself — every honesty/safety claim in one document is reinforced, not undermined, by the others (verified specifically: Doc 01 §1.6 non-goals vs. Doc 07 §9 "what this app cannot do" vs. Doc 03 §3 dependency exclusions all agree; Doc 06's algorithm descriptions match what Doc 08's unit tests actually assert).

### 3.3 Unsupported / Unverified iOS Assumptions

Flagged for mandatory Phase 4 API verification (per the assignment's explicit instruction not to assume an API exists):

- `PHPhotoLibrary.authorizationStatus(for:)` with `.readWrite` access level and its exact five-case mapping (`.notDetermined`, `.restricted`, `.denied`, `.authorized`, `.limited`) — confirm this is still the correct enum surface on the targeted iOS 17+ SDK.
- `PHPhotoLibrary.presentLimitedLibraryPicker(from:)` — confirm current signature and that it requires a `UIViewController` host (SwiftUI bridging needed).
- `PHAssetResourceManager.requestData(for:options:dataReceivedHandler:completionHandler:)` streaming signature, for both exact-duplicate SHA-256 hashing and large-file resource reads.
- `PHAssetResource.value(forKey: "fileSize")` — this is a private/undocumented-style KVC access pattern referenced in Doc 06 §5; confirm whether a public, documented alternative exists on iOS 17 (e.g., a proper `PHAssetResource` property) before relying on string-keyed KVC, which is exactly the kind of "assume an API exists" risk this prompt calls out.
- `PHPhotoLibrary.performChanges` deletion behavior and exactly how partial-failure/user-declined-native-dialog is reported back to the caller (needed for `CleanupSummary.failures`).
- `CNContactStore` key-fetch minimality and `CNSaveRequest` delete semantics/error surface.
- `AVPlayerViewController` via `UIViewControllerRepresentable` in a `NavigationStack`-based SwiftUI app (confirm no lifecycle conflicts).
- Exact `URLResourceKey` set for volume capacity (§3.1 point 4 above).

None of these are exotic — they're all real, current Apple APIs — but per this prompt's explicit instruction, each must be confirmed against documentation/current behavior before code is written that depends on it, not written from memory.

### 3.4 Decisions Needed Before Coding Begins

1. Contact merge vs. review-and-delete-only (§3.1 point 2) — **recommend deciding this now: implement review + delete only for v1**, with the merge *preview* UI still built (since it's valuable and required by Doc 01 §3.5 regardless — the preview is what prevents silent data loss even without an automated merge action), but the actual merge-execution button either omitted or explicitly labeled as a documented limitation. This keeps the five-day-equivalent build scope safe without breaking any UI requirement, since Doc 01 §3.5 requires the *preview* to exist, not that automated merge specifically ship.
2. Confirm `NSPhotoLibraryAddUsageDescription` necessity (§3.1 point 3) during Phase 4, before `Info.plist` is finalized.
3. Confirm which `URLResourceKey`s to use for storage (§3.1 point 4) during Phase 4, before `StorageService` is implemented.
4. Pin the stale-revalidation step's exact location in `PerformCleanupUseCase` (§3.1 point 1) as an explicit addendum to Doc 04's module map before Phase 11.

---

## 4. Implementation Dependencies

### 4.1 Photo/Video Pipeline

```
Project Foundation
        ↓
Design System
        ↓
Photos Permission System
        ↓
PhotoKit Enumeration (PhotoScanner)
        ↓
        ├──────────────────────────┬───────────────────────┐
        ↓                          ↓                        ↓
Exact Duplicate Detection   Screenshot Detection    Large Video Scanning
        ↓                          │                        │
Similar-Photo Detection             │                        │
(bucketing → hash → cluster)        │                        │
        ↓                          │                        │
Best-Photo Scoring                  │                        │
        ↓                          │                        │
        └──────────────────────────┴───────────────────────┘
                                    ↓
                              Selection (ReviewStore)
                                    ↓
                                 Review
                                    ↓
                          Safe Cleanup (revalidate → delete)
                                    ↓
                              Cleanup Result
```

Note: Screenshot Detection and Large Video Scanning both depend only on the enumeration phase (Phase 1 of scanning, Doc 09 §3), not on duplicate/similarity detection — this is why Doc 09 §4 (Progressive Results) can surface Screenshots and Videos before Similar Photos finishes analyzing. This dependency graph is a direct architectural consequence of that performance decision, not an independent choice.

### 4.2 Contacts Pipeline

```
Project Foundation
        ↓
Design System
        ↓
Contacts Permission System (independent of Photos permission — requested separately)
        ↓
Contact Enumeration (minimal key-fetch)
        ↓
Normalization (phone/email/name)
        ↓
Duplicate Grouping (Exact/Probable tiers + false-positive guard)
        ↓
Review (per-group field-diff preview)
        ↓
Safe Cleanup (revalidate → delete via CNSaveRequest)
        ↓
Cleanup Result
```

This pipeline is fully independent of the photo/video pipeline until both converge at the shared `ReviewStore`/Review screen — meaning it can be built in parallel with, not strictly after, the photo pipeline if desired, since neither imports the other.

### 4.3 Cross-Cutting Dependency

Both pipelines depend on:
- Core Models (no framework imports) — buildable and testable before any permission/framework work starts.
- `ReviewStore` — must exist before either pipeline's "selection" stage can be meaningfully wired up, even though it's architecturally "owned" by the Review feature.
- `PerformCleanupUseCase`/`CleanupService` — the single convergence point; cannot be meaningfully tested end-to-end until at least one category from each pipeline (e.g., Screenshots + Duplicate Contacts, the two structurally simplest categories) produces real selectable items.

---

## 5. Risk Register

| Risk | Likelihood | Impact | Mitigation (per spec, or recommended) |
|---|---|---|---|
| **PhotoKit limited access mishandled** (e.g., app claims full-library results while only limited was granted) | Med | High (trust violation, explicit non-negotiable in Doc 01/02/07) | `.limited` must be a structurally distinct case from `.authorized`, not collapsed; banner + `presentLimitedLibraryPicker` per Doc 07 §6; covered by permission-mapping unit tests |
| **Large-library performance** (10k+ photos causing UI hangs or OOM) | Med–High | High (explicit success criterion, Doc 01 §1.5) | Bucketing (Doc 06 §2), off-main-actor scanning, bounded `TaskGroup` concurrency, `autoreleasepool` batching (Doc 09) — all specified, none yet implemented; must be profiled with Instruments on a physical device, not assumed correct from code inspection alone |
| **Memory usage** (thumbnail/hash pipeline accumulating retained images) | Med | Med–High | `autoreleasepool`, bounded `NSCache`, streamed resource reads (Doc 09 §2, §7) — again, specified but unverified until built and profiled |
| **Perceptual-similarity false positives** (unrelated photos grouped as "similar") | Low–Med | High (directly erodes trust — the stated core product risk) | Conservative Hamming threshold (≤5/64, chosen to favor precision, Doc 06 §2 step 6); must be validated against real fixture image pairs, not just synthetic bit-flip test data, since real-world dHash behavior on actual photos is what the threshold was calibrated against in the literature the spec cites |
| **Stale assets/contacts between scan and cleanup** | Med | High (could attempt to delete something that no longer exists, or silently skip something the user expects gone) | Must be an explicit revalidation step in `PerformCleanupUseCase` (§3.1 point 1) — currently a named risk with no explicit architectural home; must be resolved before Phase 11 |
| **Destructive deletion without confirmation** (the single worst possible regression) | Low (well-guarded by design) | Critical | Structural guard: `CleanupSelection` is the only type that can trigger deletion (Doc 05 §9); `PerformCleanupUseCase` throws on empty selection; native OS confirmation as a second, independent safety net for photos (Doc 07 §7). This is the most heavily specified area in the whole package and should be the most heavily tested (Doc 08 §4) |
| **Contacts merge semantics** (fake/lossy merge presented as safe) | Med | High (real, unique-person data loss) | Spec pre-authorizes falling back to review+delete-only if true merge is too risky (§3.1 point 2, decided above) — recommend taking that fallback for v1 |
| **Storage estimation overclaiming** (implying selected-bytes == guaranteed device free-space delta) | Low (spec is explicit about this) | Med (misleading, not destructive) | Doc 01 §3.1 and Doc 05 §10 both require pre/post `StorageSummary` recomputation for the *actual* freed number shown on Cleanup Result, distinct from the pre-cleanup estimate |
| **Cancellation mid-scan** | Low–Med | Med (partial/stale state if mishandled) | `Task.isCancelled` checks at batch boundaries, `ScanStatus.cancelled` as a distinct non-error state preserving partial results (Doc 09 §8) |
| **Background processing / app suspension mid-scan** | Low | Med | Not explicitly addressed in Doc 09 — scans are expected to run while the app is foregrounded; no background task extension is specified or required (consistent with Doc 03 §8's "no background modes" constraint). Recommend documenting explicitly that a backgrounded app pauses/cancels the scan rather than attempting to continue, since iOS would suspend the process regardless |
| **Real-device testing infeasibility in this build environment** | High (structural) | High for final validation, none for code correctness | This container has no physical iPhone, no Xcode/simulator, and no ability to run Instruments. Everything in Doc 08 §5, Doc 09 §9, and this prompt's "Real Device" section **cannot be executed here**. Code can be written to the spec and unit/logic-tested where framework-independent (Core/Utilities per Doc 03 §4), but PhotoKit/Contacts integration behavior, Instruments measurements, and the on-device demo recording require a Mac + physical iPhone outside this environment. This must be disclosed plainly in the README's Known Limitations, not glossed over |

---

## 6. Recommended MVP Boundary

Given the five-day-equivalent scope this package was written for, and given the constraint above (this build environment cannot compile/run Swift/Xcode or access a physical device), the MVP boundary below optimizes for **what makes the core loop demonstrably correct and safe when read and reasoned about as code**, deferring anything that only pays off with device access.

### Must complete (core loop, per this prompt's own Implementation Order Phases 1–13):
1. Project foundation + design system
2. Permission handling (all 5 states mapped, structurally guarded at the service layer)
3. Storage dashboard (real `FileManager` volume keys, honest pre-scan state)
4. Photo enumeration
5. Exact duplicate detection
6. Similar-photo detection + best-photo scoring
7. Screenshot detection
8. Large-video scanning + preview
9. Duplicate contact detection (Exact/Probable tiers, false-positive guard) — **as review + delete, not automated merge**, per the decision in §3.4
10. Review screen (cross-category aggregation via `ReviewStore`)
11. Safe cleanup (`PerformCleanupUseCase` with explicit stale-selection revalidation)
12. Cleanup result (real pre/post storage diff, honest partial-failure reporting)
13. The full Doc 08 §4 safety test suite — non-negotiable, written alongside each phase above, not deferred

### Explicitly deferred / out of scope for this build pass:
- Instruments-measured performance numbers against a real 10,000+/1,000+/500+ library — **cannot be produced without a physical device**; the README will document the *design* for this (bucketing, bounded concurrency, streaming) and state plainly that measured numbers are pending real-device validation, rather than fabricating figures.
- Physical-device manual test matrix (Doc 08 §5) and the 2–3 minute demo recording (Doc 11) — same constraint; documented as a pending step for whoever has device access, with exact test steps handed off.
- Automated contact merge execution — deferred per §3.4's decision; review + delete ships, merge-preview UI ships, automated merge-and-delete-original is documented as a known limitation with the reasoning from Doc 06/this prompt.
- Any bonus feature — not considered until the above is complete and tested, per this prompt's explicit instruction.

### What this means concretely for how I'll proceed:
I can write the full Xcode project, every service/use-case/ViewModel/View, and the framework-independent unit test suite (Core/Utilities — perceptual hash, Hamming distance, contact normalization, clustering, scoring, storage math, selection invariants) entirely in this environment, since those don't require compilation against a live PhotoKit/Contacts store. What I cannot do here is compile the project, run it in Simulator, execute PhotoKit/Contacts integration tests against a seeded library, or produce real Instruments measurements — those require Xcode and, for the full manual matrix, a physical iPhone. I will flag every such item explicitly rather than claiming it was done.

---

*This document should be revisited if `00-senior-review-and-required-changes.md` is later supplied, since any conflict it raises takes precedence over what's written here.*
