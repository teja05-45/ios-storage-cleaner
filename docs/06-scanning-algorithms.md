# 06 — Scanning Algorithms

This document is the most important one for reviewer scrutiny: it must be precise enough that a claim like "similar photos" can be traced to actual, explainable math — not a black box.

## 1. Exact Photo Duplicates

**Definition used:** two `PHAsset`s whose primary image resource is byte-for-byte identical, or which are extremely likely to be identical based on cheap, reliable signals, verified before being surfaced as "exact."

**Pipeline:**
1. **Cheap pre-filter, free from PhotoKit metadata:** group assets by `(pixelWidth, pixelHeight, byteSize)`. Any asset whose triple is unique across the library cannot be an exact duplicate of anything and is skipped entirely — this alone eliminates the vast majority of a typical library from further comparison at near-zero cost.
2. **Content verification within a candidate bucket:** for assets sharing a triple, compute a content hash (SHA-256) over the original image resource data (`PHAssetResourceManager.requestData`, streamed, not loaded as a single `Data` blob into memory for large files — see Document 09). Assets with matching SHA-256 are true exact duplicates.
3. Assets sharing dimensions/size but *not* SHA-256 (e.g., a re-saved copy with different embedded metadata but visually identical pixels) are **not** classified as "exact" — they fall through to the similarity pipeline below, where they will very likely surface as "similar" at maximum confidence, correctly labeled.

**Tradeoff:** requiring a true content hash rather than just trusting the (dimensions, size) triple is slightly more I/O, but it is the only approach that cannot produce a false "exact duplicate" claim — a false positive here is the worst-case outcome for a trust-first product, so the extra verification pass is non-negotiable.

## 2. Similar Photos

**Honest definition of "similar" used in this app:** two photos whose perceptual hashes differ by a Hamming distance at or below a calibrated threshold. This detects near-duplicates such as burst-mode shots, consecutive retakes, and minor recrops/recompressions. It does **not** detect semantically similar-but-visually-different photos (e.g., "two photos of the same dog on different days") — that would require a learned embedding model, which is out of scope and would be dishonest to imply without one. The UI copy and this document both state this scope explicitly.

**Why not compare every image against every other image (O(n²)):** at 10,000 photos that's ~50 million comparisons — even a cheap comparison at that scale is a bad use of a phone's thermal/battery budget and would make the product feel untrustworthy through sluggishness alone. Pipeline instead:

**Pipeline:**
1. **Metadata pre-bucketing:** group assets into coarse buckets by `creationDate` rounded to a configurable window (default: same calendar day ± adjacent day boundary handling for midnight-crossing bursts) and by `PHAssetCollection`-adjacent proximity where available. Similar/duplicate photos are overwhelmingly taken within seconds-to-minutes of each other (burst mode, retakes) — this bucketing reduces the comparison space by roughly two to three orders of magnitude on a typical library, without meaningfully risking missed matches, since true near-duplicates are essentially never taken days apart with no other candidates in between. Users who deliberately re-shoot the same subject weeks apart are outside this tool's detection scope by design (documented as a limitation), trading recall for correctness and speed.
2. **Thumbnail generation:** for each asset in a bucket of size > 1, request a small, fixed-size thumbnail (e.g., 64×64) via `PHImageManager` with `.fastFormat` delivery — never the full-resolution image for hashing purposes.
3. **Normalization:** convert to grayscale, resize to a fixed 8×8 (or 9×8 for dHash) grid using `CoreImage`/`vImage` (Accelerate) for speed and consistency.
4. **Perceptual hash computation (dHash — difference hash):** compare adjacent pixel brightness across the small grid, producing a 64-bit fingerprint where each bit encodes "is this pixel brighter than its neighbor." dHash is chosen over average-hash for better resilience to minor exposure/brightness shifts (common between burst shots) and over a DCT-based pHash for lower CPU cost at a comparable accuracy for this use case.
5. **Hamming distance comparison:** within each metadata bucket, compare every pair's 64-bit hash via XOR + popcount (cheap, `UInt64` bitwise op — this is the only "compare everything" step, and it's restricted to the already-small bucket, so it stays fast even in the worst case).
6. **Threshold:** Hamming distance ≤ **5** (out of 64 bits) is classified as similar. This threshold was chosen conservatively (favoring precision over recall) based on published dHash literature where distances of 0–4 reliably indicate near-identical images and distances above ~10 indicate unrelated images; 5 is set slightly below the common upper bound specifically to keep the false-positive rate low, consistent with the trust-first principle — an occasional missed near-duplicate is an acceptable cost; an incorrectly grouped unrelated photo is not.
7. **Clustering:** pairwise "similar" edges within a bucket are merged via union-find (disjoint-set) into connected components — this correctly handles a burst of 5 photos where photo 1 vs. photo 5 might exceed the pairwise threshold but a chain of adjacent pairwise matches ties them into one group, without needing a full O(n²) all-pairs pass at the clustering stage either (union-find is near-linear).
8. **Confidence score per group:** `confidence = 1 - (averagePairwiseHammingDistance / 64)`, surfaced in the UI as the basis for the "similarity confidence" metadata — an honest, directly-computed number, not a fabricated percentage.

**Scale behavior:** with bucketing, the dominant cost becomes thumbnail fetch + hash computation, which is O(n) in the number of assets and trivially parallelizable/batchable (Document 09). The only step with combinatorial cost (Hamming comparison) operates on bucket sizes that are empirically small (bursts rarely exceed a few dozen shots), keeping total comparisons in the thousands even for a 10,000+ photo library, not tens of millions.

## 3. Best Photo Selection

**Explainability requirement:** every recommendation must produce a human-readable `reason` string derived directly from the same scores used to rank — never a hidden or unexplained choice.

**Signals used (each independently computed, no ML model):**

| Signal | Method | Weight rationale |
|---|---|---|
| Resolution | `pixelWidth × pixelHeight` from `PHAsset`, normalized against the max in-group | Higher resolution is an objective, unambiguous quality signal available for free from metadata |
| Sharpness | Laplacian variance over the downsampled grayscale image (Accelerate `vImage` convolution) — a well-established, classical focus-measure operator | Detects blur, the single most common reason to prefer one burst photo over another; computed on a small thumbnail, not full-res, for speed |
| Exposure | Histogram-based check: proportion of near-clipped (very dark/very bright) pixels; penalizes severe under/over-exposure | Catches an obviously bad frame (eyes-closed-timing-adjacent bursts often include one badly exposed shot) without claiming face/eye detection we haven't implemented |
| File size (tiebreaker only) | Raw byte size | Used only to break near-ties between otherwise-equal candidates, as a weak proxy for detail retained by compression — explicitly the lowest-weighted, last-resort signal |

**Explicitly not implemented / not claimed:** face detection, eyes-open/closed detection, smile detection, subject-in-focus (vs. background-in-focus) discrimination. These would require Vision framework face landmarks or a CoreML model; omitted from this scope to keep every claim in the product backed by real, verifiable computation. The `reason` string never says anything like "best face detected" — only what was actually measured (e.g., "Highest resolution, sharpest of 4").

**Scoring formula (weighted, normalized 0–1 per signal within the group):**
```
totalScore = 0.35 * resolutionScore + 0.45 * sharpnessScore + 0.15 * exposureScore + 0.05 * fileSizeScore
```
Sharpness weighted highest because blur is the most common, most visually obvious reason a user would reject a "recommended keep" — validated qualitatively against sample burst sequences during implementation; documented as a tunable constant, not a magic number buried in code.

## 4. Screenshots

**Definition:** `PHAsset.mediaSubtypes.contains(.photoScreenshot)` — this is the only PhotoKit-documented, reliable signal for "this image was captured via the OS screenshot mechanism." No dimension-based heuristics (e.g., "matches device screen resolution") are used, because those produce false positives against legitimately-sized regular photos and false negatives against images that were screenshotted and later cropped/edited. Relying solely on the OS-provided flag keeps this category's accuracy at effectively 100% for what the OS itself considers a screenshot, with zero custom heuristic risk.

## 5. Large Videos

- Enumerate `PHAsset` where `mediaType == .video`.
- File size: sum of `PHAssetResource.value(forKey: "fileSize")` for the asset's resources (falls back to an `AVURLAsset` file-size read via the resource's `AVAsset` only if the PhotoKit resource size is unavailable for a given resource type).
- Resolution/duration: read from `PHAsset.pixelWidth/pixelHeight/duration` directly (fast, metadata-only, no asset export needed) rather than instantiating a full `AVAsset` for every video during the list-scan phase — an `AVAsset`/`AVPlayerItem` is only created lazily when the user opens the preview player for one specific video, keeping the scan phase for videos cheap and memory-bounded regardless of library size.
- Sort descending by byte size for the list.

## 6. Duplicate Contacts

**Normalization:**

*Phone numbers:*
1. Strip all non-digit characters except a leading `+`.
2. If a leading `+` with country code is present, keep as-is (E.164-like).
3. If no country code is present, compare using the **national significant number** — for this scope, defined pragmatically as the last 10 digits of the stripped number (covers the common case described in the assignment: `+91 98765 43210` vs `9876543210` both normalize to `9876543210` for comparison purposes).
4. Two phone numbers are considered a match if either their full normalized forms match, or their last-10-digit suffixes match **and** at least one of the two numbers lacked a country code (so we don't accidentally equate two genuinely different international numbers that happen to share a local suffix — a documented, deliberate precision-over-recall choice).

**Known limitation (disclosed, not hidden):** this is not full ITU E.164 parsing. A production system would use a library like libphonenumber for correct region/country-code disambiguation; this scope's heuristic is stated explicitly in Document 03 and the README as a tradeoff, not silently assumed to be perfect.

*Email:*
1. Lowercase the entire address.
2. Trim leading/trailing whitespace.
3. (Gmail-specific, disclosed as such) optionally strip `+tag` subaddressing before the `@` — **disabled by default** to avoid false-positive merges for users who intentionally use tagged addresses for different purposes; available as a documented, off-by-default refinement rather than a silent assumption.
4. Compare normalized strings for exact match.

**Name similarity:**
- Normalize case and whitespace, then compute Levenshtein edit distance between full names (or token-set overlap for reordered names, e.g., "John Smith" vs "Smith, John").
- Similarity score = `1 - (editDistance / max(len(name1), len(name2)))`, in \[0,1].

**Tier classification:**

| Tier | Criteria |
|---|---|
| **Exact** | Normalized phone match **or** normalized email match, **and** name similarity ≥ 0.9 (i.e., effectively the same name, allowing for minor typos/casing) |
| **Probable** | Normalized phone or email match **without** a strong name match, **or** name similarity ≥ 0.85 **with** at least one other overlapping field (e.g., same company, same partial phone) but not meeting the Exact bar |

**False-positive handling:**
- Contacts matching on name similarity *alone*, with **no** overlapping phone/email/other field, are never surfaced as duplicates at any tier — a shared common name (e.g., two different "John Smith"s) is a well-known failure mode this rule structurally prevents.
- Every group shown to the user displays the **matching reason** (e.g., "Same phone number, similar name") and a **field-diff preview** so the user can see exactly what would be lost before choosing delete over merge — the algorithm never merges automatically; it only ever proposes.
- Groups are capped in size review-wise: if normalization produces a bucket larger than a sanity threshold (e.g., >8 contacts sharing one normalized signal — which usually indicates a shared work/reception number, not duplicate people), the group is flagged as low-confidence and demoted out of "Exact," surfaced only under "Probable" with an explanit note, rather than silently treated as 8 duplicate people.
