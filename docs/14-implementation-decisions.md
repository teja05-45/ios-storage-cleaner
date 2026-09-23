# 14 — Implementation Decisions

Architecture Decision Record log. Written before/during implementation. Each entry records a real decision made because the base specification either left it open (per Document 13 §3.4) or because API verification (§0 below) surfaced something the spec assumed incorrectly.

---

## 0. API Verification Summary (Gate 2)

Verified against current Apple Developer Documentation before writing dependent code, per the assignment's explicit "do not assume an API exists" instruction.

| API | Verified behavior | Matches spec? |
|---|---|---|
| `PHPhotoLibrary.authorizationStatus(for: .readWrite)` → `PHAuthorizationStatus` | Confirmed current API (iOS 14+, our iOS 17+ floor is well within support). Cases: `.notDetermined`, `.restricted`, `.denied`, `.authorized`, `.limited`. Async variant: `await PHPhotoLibrary.requestAuthorization(for: .readWrite)`. | Yes — matches Doc 01 §3.7 exactly |
| `PHPhotoLibrary.presentLimitedLibraryPicker(from:)` | Confirmed current, `@MainActor`, takes a hosting `UIViewController` | Yes — needs `UIViewControllerRepresentable` bridge as Doc 03 §2 anticipated |
| `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` | Confirmed current Foundation API. Apple's own guidance: use this key (over the plain `.volumeAvailableCapacityKey`) specifically for "data based on a user request" — which is exactly our case (the user asked us to scan/report storage) | Refines Doc 01 §3.1 — see ADR-03 below |
| `PHAssetResource.value(forKey: "fileSize")` | **Confirmed NOT a documented public property.** It is accessed via the genuinely public `NSObject.value(forKey:)` KVC method, so it is not a private *symbol*, but Apple's own DTS engineers have stated on the developer forums that this key is undocumented, unsupported, and could silently stop working in a future OS release. Widely used in production, and apps using it have passed App Review — but it is explicitly not a guaranteed-stable API. | Base spec (Doc 06 §5) uses this without flagging the risk — **addressed in ADR-01 below** |
| `PHAssetResourceManager.requestData(for:options:dataReceivedHandler:completionHandler:)` | Confirmed current, supports progressive/streamed delivery — this is the fully-documented way to get resource bytes (and, by extension, an authoritative size) | Yes — matches Doc 09 §2's streaming requirement |
| `CNContactStore` / `CNSaveRequest` deletion | Confirmed current; `CNSaveRequest.delete(_:)` takes a `CNMutableContact`, executed via `CNContactStore.execute(_:)`, synchronous, throws | Yes — matches Doc 01 §3.5 |
| `AVPlayerViewController` in SwiftUI | Confirmed standard `UIViewControllerRepresentable` bridging pattern, no lifecycle conflicts documented for `NavigationStack` hosting | Yes — matches Doc 03 §2 |

---

## ADR-01 — PhotoKit Resource Size: KVC Fast Path with Streamed Fallback

**Decision:** Compute an asset's byte size primarily via `PHAssetResource.value(forKey: "fileSize")`, treating a `nil`/unexpected-type result as a signal to fall back to a streamed read via `PHAssetResourceManager.requestData`, summing received chunk lengths without ever holding the full resource in memory.

**Context:** The base spec (Document 06 §5) specifies this KVC key directly as the primary path with an `AVURLAsset`-based fallback, without flagging that the KVC key is undocumented. API verification (§0 above) confirmed Apple's own developer relations engineers explicitly warn against relying on it, while also confirming it is real public-API access (not a private framework/symbol) and is in widespread, App-Review-approved production use for exactly this purpose (there is no fully public, documented, cheap alternative — the only "guaranteed forever" method is to read the resource's actual byte stream, which is far more expensive at 10,000+ photo / 1,000+ video scale).

**Alternatives considered:**
1. Always stream and count bytes via `PHAssetResourceManager.requestData` — fully documented, zero KVC risk, but requires reading every byte of every photo/video resource just to sort a list by size. At 1,000+ videos (some multiple GB in 4K), this is a serious, measurable performance and battery cost that directly conflicts with Document 09's performance targets.
2. Use `AVURLAsset` file-size resource values after exporting — requires an export step per asset, similarly expensive, and Document 06 §5 itself only proposes this as a fallback, not a primary path, for the same reason.

**Why:** The KVC path is fast (metadata-only, no I/O), matches real-world production practice, and is not App-Store-review-risky. The streamed fallback exists specifically so the app degrades gracefully (slower, but still correct) if a future OS release removes the KVC key, rather than crashing or silently reporting a wrong size.

**Tradeoff:** The app depends on undocumented behavior for its fast path. This is disclosed explicitly in the README's Known Limitations, exactly as Document 06 §6 already discloses the phone-normalization heuristic — consistent with the product's stated "never silently assume" principle. `PhotoLibraryService` isolates this behind a single `resourceByteSize(for:)` method so a future OS change requires touching one function, not every call site.

**Impact on implementation:** `PhotoLibraryService.resourceByteSize(for:)` implements the fast-path/fallback logic described above. `PhotoScanner`, `VideoScanner`, and `DuplicateDetector` all call this one method rather than touching `PHAssetResource` directly.

---

## ADR-02 — Contact Duplicate Handling: Review + Explicit Delete (No Automated Merge)

**Decision:** Ship a full merge-*preview* screen (per-field diff, which record would survive vs. be removed) but do not implement automated merge execution (construct a `CNMutableContact` combining fields, save, then delete the original) in this build pass. The only destructive action available for contacts is explicit per-contact deletion, always shown against the full preview of what would be lost.

**Context:** The base spec (Document 01 §3.5) requires the merge/delete preview UI but does not mandate that automated merge-and-delete-original actually execute — Document 06 §6 and this build's own instructions explicitly pre-authorize falling back to review+delete if true merge proves too risky for the timeline, calling a reliable delete workflow "preferable to a dangerous merge workflow." Document 13 §3.1/§3.4 flagged this as an open decision.

**Alternatives considered:**
1. Implement full merge: build `CNMutableContact`, copy the surviving fields, `CNSaveRequest.add`/`update`, then delete the original only after confirmed success. This is technically well-specified (Document 01 §3.5, this build's §12 safety steps) but introduces a second class of destructive, hard-to-reverse operation (a botched merge can silently drop a field with no OS-level undo, unlike PhotoKit deletion which has a Recently Deleted grace period) — a meaningfully larger safety surface for the same review timeline.
2. Ship neither preview nor delete, contacts view-only — rejected, this would fail the assignment's explicit Duplicate Contacts requirement (Document 01 §3.5) entirely.

**Why:** The field-diff preview is what actually prevents data loss (the user sees exactly what's about to disappear before confirming), and it's required either way. Automated merge adds construction/save/delete choreography with its own failure modes (partial merge, save succeeds but delete fails leaving two records, etc.) that would need its own dedicated safety-test suite in addition to the existing one — a scope increase the base spec itself says to avoid if it's risky within the timeline.

**Tradeoff:** A user with two duplicate contacts who each hold a unique field (e.g., one has an email, the other a work phone) must manually copy the field they want to keep into the surviving contact before deleting the other — the app shows them exactly what they'd lose (satisfying Document 01 §3.5's disclosure requirement) but doesn't do the copy for them. Documented explicitly in the README's Known Limitations as a deliberate, disclosed scope decision, not a silent gap.

**Impact on implementation:** `ContactService` exposes `delete(contactIDs:)` but no `merge(primary:secondary:)` method. `ContactGroupDetailView`'s preview shows the field diff and a single "Delete duplicate" action per non-primary member, feeding into the same `ReviewStore`/`CleanupSelection` path as every other category — no parallel/special-cased deletion pathway for contacts.

---

## ADR-03 — Storage Measurement: `volumeAvailableCapacityForImportantUsageKey`

**Decision:** Use `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` for "available" storage (not the plain `.volumeAvailableCapacityKey`), and `.volumeTotalCapacityKey` for total capacity. "Used" is derived as `total - available` rather than queried directly, since iOS exposes no direct "used bytes" resource key.

**Context:** Document 01 §3.1 said "must use `UIDevice`/`FileManager` volume capacity keys" without naming the specific key. API verification (§0) found Apple's own guidance is to use the "important usage" variant specifically for storage decisions made in response to a user request — which is exactly this app's scenario (the user opened the Dashboard and asked to see their storage).

**Alternatives considered:** `.volumeAvailableCapacityKey` (the plain/legacy key) — still valid, but Apple's current documentation positions the "important usage" key as the more accurate one for this exact use case on modern iOS, since it accounts for space the system may reserve.

**Why:** Matches current first-party guidance precisely, and "used bytes" as a derived value (rather than an invented category) keeps faith with Document 01 §3.1's "never invented" constraint — it's arithmetic on two real OS-reported numbers, not a third number iOS doesn't expose.

**Tradeoff:** None meaningful — this is a straightforward, low-risk key selection once verified.

**Impact on implementation:** `StorageService.currentSummary()` queries exactly these two keys against a file URL in the app's own container (e.g., `NSHomeDirectory()`), computes `used = total - available`, and never queries or invents any other storage category.

---

## ADR-04 — Limited-Library Behavior

**Decision:** `.limited` is treated as a first-class, fully-functional authorization state distinct from `.authorized` throughout the Service and ViewModel layers — never collapsed into a boolean "has access." Every screen that shows scan results also exposes whether the underlying authorization was `.limited`, and the Dashboard/Clean Up hub renders a persistent (dismissible-per-session, non-blocking) banner in that case with a button that calls `PHPhotoLibrary.presentLimitedLibraryPicker(from:)`.

**Reason:** Directly required by Document 01 §3.7 and Document 07 §6, and this is a common source of real-world bugs (developers frequently write `status == .authorized` and silently treat `.limited` as denied, or the reverse — silently treat it as full access and mislead the user about scan completeness). Modeled as its own case in `PermissionState`, not inferred from a boolean.

**Alternatives considered:** Two-state model (`hasAccess: Bool`) with a separate `isLimited` flag bolted on — rejected because it's exactly the kind of representation that invites the collapsing bug described above; a single enum with an explicit `.limited` case makes the illegal state (limited-but-treated-as-full) structurally harder to write.

**Tradeoff:** Slightly more exhaustive `switch` handling at every call site that branches on permission state. Accepted — this is precisely the kind of correctness Document 01 §3.7 treats as non-negotiable ("never crash, hang, or silently show an empty state indistinguishable from 'you have nothing to clean'").

**Impact on implementation:** `PermissionState` enum: `.notDetermined`, `.restricted`, `.denied`, `.authorized`, `.limited`. `PhotoLibraryService` maps `PHAuthorizationStatus` to this 1:1. Every scan-triggering call site checks for `.limited` explicitly and threads a `scannedWithLimitedAccess: Bool` flag into `ScanResult`/`StorageSummary` so the UI can honestly state "only your selected photos were scanned" rather than implying a full-library scan.

---

## ADR-05 — Stale-Selection Revalidation

**Decision:** `PerformCleanupUseCase.execute(_:)` performs an explicit revalidation pass as its first step, before calling `CleanupService`: for each selected photo/video/screenshot ID, re-fetch the `PHAsset` by local identifier and drop any ID that no longer resolves; for each selected contact ID, re-fetch the `CNContact` by identifier (with the app's minimal key-fetch set) and drop any that no longer resolves. Authorization status is also re-checked at this point (not assumed valid from when the scan ran). The use case proceeds only with the revalidated subset, and any ID dropped at this stage is recorded as a `CleanupFailure` with a `.staleAsset`/`.staleContact` reason in the final `CleanupSummary` — never silently omitted.

**Context:** Document 04's module map has no named component for this step (flagged as an architecture gap in Document 13 §3.1/§4.1). This build's own instructions (§8) make the sequence explicit ("re-check current authorization... revalidate every selected asset/contact... remove stale/nonexistent entries from the executable set") — this ADR is where that requirement gets a concrete home in the architecture.

**Alternatives considered:** Revalidate inside `CleanupService` itself, right before the OS delete call — rejected as the sole location, because `CleanupService`'s job (per Document 04) is to execute an *already-validated* `CleanupSelection` against Photo/Contact services; putting revalidation there would blur that boundary and make `CleanupService` harder to test in isolation (it would need PhotoKit/Contacts fetch behavior, not just delete behavior, faked in every test). Keeping revalidation in the use case, upstream of the service, keeps `CleanupService` a pure "given a validated set, execute deletion and report results" component.

**Why:** This is exactly the gap the assignment's safety requirements call out by name ("stale photo assets," "stale contacts," "changed permissions," "changed selection," "missing assets"). Giving it a named, explicit, tested step closes the one place Document 13 identified as implicit rather than architected.

**Tradeoff:** One extra full pass of `PHAsset`/`CNContact` re-fetches at confirm time, proportional to selection size (typically small — dozens to low hundreds of items, not the whole library), which is a negligible cost against the safety guarantee it buys.

**Impact on implementation:** `PerformCleanupUseCase` gains a private `revalidate(_ selection: CleanupSelection) async -> (valid: CleanupSelection, staleFailures: [CleanupFailure])` step, called before `CleanupService.execute`. Safety test `test_staleAssetIsSafelySkippedAndReported` targets this directly.

---

## ADR-06 — Concurrency Strategy for Similarity Analysis

**Decision:** A `ScanCoordinator` actor owns scan-phase sequencing. Per-bucket similarity work (thumbnail fetch → normalize → hash) is parallelized via `TaskGroup` bounded to `min(ProcessInfo.processInfo.activeProcessorCount, 4)` concurrent child tasks — a fixed, conservative cap rather than one task per bucket — to avoid thermal throttling and PHImageManager request-queue contention on a real device at 10,000+ photo scale.

**Context:** Document 09 §5 specifies "bounded concurrency... a fixed-size TaskGroup limited to a small multiple of active core count" without pinning an exact number.

**Alternatives considered:** Unbounded `TaskGroup` (one task per bucket) — rejected outright per Document 09/this build's explicit prohibition on "thousands of unrestricted concurrent Tasks." A single serial loop — rejected as leaving meaningful performance on the table for a multi-core device with no memory/thermal justification once bounded concurrency is available.

**Why:** `activeProcessorCount` scales the cap to the device rather than hardcoding a number that's wrong on both very old and very new hardware; the `min(..., 4)` ceiling keeps memory pressure (each in-flight bucket holds a handful of small thumbnails, not full-resolution images) bounded even on high-core-count devices, since PhotoKit thumbnail requests themselves have real memory cost at volume.

**Tradeoff:** A hardcoded ceiling (4) is a guess pending real Instruments data (Document 13 §5 flags that this environment cannot produce that data) — documented as a tunable constant in `ScanCoordinator`, explicitly named for revisiting once profiled on a physical device, not buried as a magic number.

**Impact on implementation:** `ScanCoordinator.maxConcurrentBuckets` is a named, documented constant. Performance profiling (Document 10 Phase 13 / this build's Gate 9) is the point at which this value gets tuned against real measurements rather than left as an initial estimate.

---

## ADR-07 — Scan Cache Strategy

**Decision:** `ScanCache` persists exactly: `localIdentifier`, `modificationDate` (for change detection), computed `perceptualHash` (photos only), `byteSize`, group-membership IDs, and `cacheSchemaVersion` — as JSON in the app's Application Support directory. On rescan, an asset is only re-processed (re-hashed) if it's new or its `modificationDate` differs from the cached value. Contacts are explicitly **not** cached across launches (re-scanned fresh each session), per Document 07 §4's own stated reasoning that contact libraries are cheap to re-scan and caching them adds privacy-relevant persistence for no meaningful performance benefit.

**Context:** Directly specified by Document 04 ADR-04, Document 05 §7, Document 07 §4, Document 09 §6 — this is one of the most precisely pre-specified decisions in the base package. Recorded here mainly to confirm no deviation was needed and to make the "contacts are not cached" asymmetry an explicit, intentional decision rather than something a reader has to infer.

**Alternatives considered:** Always full rescan (simplicity) — rejected per Document 04 ADR-04's own reasoning (10,000+ photo scale makes this feel slow every launch, working against the trust goal).

**Why/Tradeoff:** As stated in Document 04 ADR-04 — accepted as-is.

**Impact on implementation:** `Infrastructure/ScanCache.swift` implements exactly this shape; `cacheSchemaVersion` is bumped any time hashing/threshold logic changes, forcing a full rescan rather than mixing hash semantics silently.

---

## ADR-08 — Deletion Semantics

**Decision:** Photo/video/screenshot deletion is requested via `PHPhotoLibrary.performChanges { PHAssetChangeRequest.deleteAssets(assetsToDelete as NSFastEnumeration) }`, which triggers iOS's own native "Delete X Photos" confirmation as an OS-level second safety net. Contact deletion is requested via a `CNSaveRequest` with `.delete(mutableContact)` calls, executed via `CNContactStore.execute(_:)`, with **no** OS-level secondary confirmation (none exists for this API) — which is exactly why ADR-02's field-diff preview and the shared Review-screen confirm tap carry the full safety weight for that category, as Document 07 §7 states explicitly.

**Context:** Confirmed against current API documentation (§0). Matches Document 01 §3.6, Document 05 §9–10, Document 07 §7 precisely — no deviation from base spec needed here, recorded for completeness since it's the single most safety-critical mechanism in the app.

**Impact on implementation:** `CleanupService.deletePhotos(ids:)` and `CleanupService.deleteContacts(ids:)` are the only two call sites in the entire codebase that invoke a deletion API. Enforced structurally (no other type imports `PHAssetChangeRequest` or `CNSaveRequest`) and verified by the safety test `test_deletionRequiresExplicitConfirmation`.

---

## Summary Table

| # | Decision | Driven by |
|---|---|---|
| ADR-01 | KVC fast path + streamed fallback for resource byte size | API verification finding |
| ADR-02 | Review + explicit delete for contacts, no automated merge | Open decision, resolved per spec's own pre-authorized fallback |
| ADR-03 | `volumeAvailableCapacityForImportantUsageKey` for storage | API verification finding |
| ADR-04 | `.limited` as first-class `PermissionState` case | Base spec requirement, made explicit |
| ADR-05 | Explicit revalidation step inside `PerformCleanupUseCase` | Architecture gap identified in Doc 13 |
| ADR-06 | Bounded `TaskGroup`, capped at `min(cores, 4)` | Base spec requirement, concrete value chosen |
| ADR-07 | `ScanCache` shape, contacts never cached across launches | Base spec, confirmed as specified |
| ADR-08 | Two, and only two, deletion call sites in the codebase | Base spec, confirmed as specified |
