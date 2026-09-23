# 09 — Performance Strategy

## 1. Design Target

Reclaim must feel responsive on a library of **10,000+ photos, 1,000+ videos, 500+ screenshots**, on a mid-range physical iPhone (the assumed baseline device for demo/testing, not the newest Pro model), without freezing the UI thread or exceeding a reasonable memory footprint.

## 2. Guiding Principles

- **The main thread never does PhotoKit/Contacts/image-processing work.** All scanning, hashing, and fetching happens off `@MainActor`, in dedicated `Task`s/actors; only final, small, UI-ready results cross back to the main actor.
- **No O(n²) full-library comparison.** The similarity pipeline's expensive step (Hamming distance comparison) is restricted to small metadata-bucketed groups, not the whole library (Document 06 §2) — this is the single biggest algorithmic performance decision in the product.
- **Thumbnails, never full-resolution images, for anything analytical.** Perceptual hashing, sharpness scoring, and exposure scoring all operate on small (e.g., 64×64–128×128) thumbnails via `PHImageManager`'s fast-delivery options — full-resolution image data is only ever requested when the user explicitly opens a single-photo preview.
- **Streamed, not fully-buffered, I/O for large resources.** Exact-duplicate content hashing (Document 06 §1) reads resource data in chunks (`PHAssetResourceManager` progressive delivery) and feeds an incremental hash (`CryptoKit`'s `SHA256` supports incremental updates), so a large video/photo resource never requires holding its entire byte content in memory at once.
- **Autorelease pools around tight per-asset loops.** Batch processing loops (e.g., iterating thousands of `PHAsset`s to build `PhotoAsset` models) wrap each batch in `autoreleasepool { }` to prevent Foundation/UIKit-bridged temporary objects (esp. `UIImage`/`CGImage` from thumbnail requests) from accumulating across a long-running scan.

## 3. Scan Phases

Scanning is broken into explicit, independently-progress-reported phases rather than one opaque "Scanning…" spinner — this supports both the performance story (progressive results) and the trust story (the user can see what's happening, not just wait blindly):

1. **Enumeration** — fast metadata-only fetch of all relevant `PHAsset`/`CNContact` records into lightweight model instances (`PhotoAsset`/`VideoAsset`/`ContactCandidate`), no thumbnails, no hashing. This phase alone is enough to populate Screenshots and Large Videos screens (they need no further analysis), so those categories can show results almost immediately while photo-similarity analysis continues in the background.
2. **Exact-duplicate bucketing & hashing** — cheap metadata grouping first (near-instant), then content-hash verification only within candidate buckets (Document 06 §1).
3. **Similarity analysis** — metadata bucketing, then thumbnail fetch + dHash computation + Hamming clustering per bucket (Document 06 §2), run in batches with periodic UI checkpoints so progress can be reported as "N / total analyzed."
4. **Best-photo scoring** — sharpness/exposure scoring runs only on members of groups that were actually formed (never on the whole library), keeping this phase's cost proportional to duplicate volume, not library size.
5. **Contact matching** — normalization + bucketed matching (Document 06 §6); contact libraries are typically small (hundreds, not tens of thousands) so this phase is not a primary performance concern but still runs off-main-thread for consistency.

Each phase reports `(phaseName, completed, total)` to the `ScanStatus.scanning` case consumed by the Dashboard/Clean Up progress UI (Document 02 §2.7).

## 4. Progressive Results

Rather than blocking all UI until the entire scan finishes, category screens subscribe to phase-level completion: Screenshots and Large Videos become interactive right after Phase 1; Similar Photos populates incrementally as Phase 3 completes bucket-by-bucket (each finished bucket's groups are appended to the visible list, not held back until every bucket is done). This means a user with a very large library sees useful, real results within seconds rather than waiting for a multi-minute scan to fully complete before doing anything.

## 5. Concurrency Model

- A `ScanCoordinator` actor owns the scan lifecycle and phase sequencing, using `TaskGroup` to parallelize independent per-bucket similarity work (bounded concurrency — e.g., a fixed-size `TaskGroup` limited to a small multiple of active core count, not unbounded, to avoid thermal throttling and memory spikes from too many simultaneous thumbnail requests in flight).
- `PHImageManager` requests are batched and their concurrency is additionally bounded by PhotoKit's own request queue behavior, respected rather than fought.
- Hash computation (CPU-bound, `vImage`/Accelerate) is dispatched onto a limited-concurrency queue separate from I/O-bound thumbnail fetches, so CPU-heavy and I/O-heavy work don't starve each other.

## 6. Caching

- `ScanCache` (Document 04 §6, Document 05 §7) persists per-asset hashes and group membership keyed by `localIdentifier` + `modificationDate`. On a rescan, only new or modified assets are re-enumerated and re-hashed — an incremental rescan of a 10,000-photo library where 50 photos were added since the last scan should cost roughly proportional to 50 assets, not 10,000.
- `ThumbnailCache` is a bounded `NSCache` (both count and total-cost limits configured based on typical thumbnail memory footprint) so repeated scrolling through a large grid doesn't unbounded-grow memory; eviction under memory pressure is expected and handled gracefully (re-fetch on demand, never a crash from a missing cache entry).
- Cache schema is versioned (`cacheSchemaVersion` in `ScanResult`) so a future change to the hashing algorithm or thresholds invalidates old cached hashes rather than silently mixing old and new hash semantics.

## 7. Memory Limits

- No full-resolution image or full video is ever loaded into memory during scanning — only during explicit user-initiated preview (single photo detail view, video player), and even then only one at a time, released when the preview is dismissed.
- Batch sizes for enumeration/hashing loops are chosen empirically during implementation and validated against Instruments' Memory Graph/Allocations during the large-library manual test pass (Document 08 §5), with a target of staying well under the OS's per-app memory limit with headroom, rather than targeting the limit itself.

## 8. Cancellation & Retry

- Every scan phase checks `Task.isCancelled` at each batch boundary; the Dashboard/Clean Up UI exposes a Cancel action during any scan phase longer than ~2 seconds (Document 02 §2.7).
- Cancelling preserves whatever partial results were already produced (`ScanStatus.cancelled` is a distinct, non-error state) — the user keeps whatever categories finished, rather than losing all progress.
- A failed phase (e.g., a transient PhotoKit resource-fetch error on one asset) does not abort the entire scan — errors are collected per-asset and the phase continues, with a summary error state surfaced only if a meaningful proportion of the phase failed, alongside a "Retry" action scoped to just the failed phase where feasible.

## 9. How Performance Will Be Measured

Recorded manually during the Document 10 Phase 15 / Document 08 §5 real-device pass, using Instruments:

- **Scan duration** — wall-clock time per phase and total, against the 10,000+/1,000+/500+ target library composition, logged and reported in the README's Performance section (Document "Final Submission Package").
- **Memory behavior** — peak resident memory during each scan phase via the Allocations/VM Tracker instruments, watched specifically during Phase 3 (similarity analysis, the most thumbnail-heavy phase).
- **UI responsiveness** — Core Animation/Hangs instrument during an active scan, confirming no main-thread hangs above the standard responsiveness threshold while scrolling or interacting with any screen during a background scan.
- **Result accuracy** — cross-checked against a manually curated subset of the seeded/real test library where the "correct" duplicate groups and screenshot/video sets are known ahead of time, to confirm the pipeline's real-world precision (not just its unit-test fixture correctness).
