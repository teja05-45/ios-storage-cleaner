# 01 — Product Requirements Document

**Product name:** Reclaim
**Platform:** iOS 17+, iPhone only (Phase 1), SwiftUI
**Status:** Draft v1.0 — for review before implementation begins

---

## 1. Product Vision

### 1.1 Problem

iPhones fill up with storage the user never consciously created: burst-mode near-duplicates, repeated screenshots taken for a moment and never deleted, videos shot in 4K that quietly consume gigabytes, and contact entries duplicated by multiple import sources (SIM, iCloud merges, app imports). Users know they *have* a clutter problem but have no efficient way to:

- see where their storage actually went, in terms they understand
- find duplicate/similar photos without manually swiping through thousands of images
- judge whether a video is worth keeping without reopening it one by one
- clean up contacts without risking loss of a real, unique person

Existing "cleaner" apps in the App Store lean on dark patterns: auto-selecting large swaths of the library, vague "500 issues found!" scare messaging, and deletion flows designed to be clicked through quickly rather than reviewed carefully. That erodes the one thing a storage tool needs most: trust.

### 1.2 Target User

Primary: an iPhone owner who has owned the device 1+ years, has 2,000–20,000+ photos, receives "Storage Almost Full" warnings periodically, and does not want to buy more iCloud storage as the default fix.

Secondary: a user handing down or reselling a device who wants a fast, safe way to review and thin out their library and contacts before doing so.

### 1.3 User Pain Points

| Pain point | Why it matters |
|---|---|
| "I don't know what's taking up space" | iOS Settings → Storage is coarse and not actionable |
| "I have hundreds of near-identical photos from bursts" | Manual comparison across a large library is impractical |
| "I'm afraid I'll delete something I actually wanted" | Prior bad experiences with auto-delete tools |
| "My contacts list has the same person 3 times" | Merged from SIM, iCloud, and manual entry over years |
| "Cleaner apps feel scammy" | Vague claims, paywalls before any real value, auto-checked deletion lists |

### 1.4 Product Promise

Reclaim shows you exactly what is consuming your storage, groups what's genuinely redundant, explains *why* something was flagged, and never deletes anything you did not explicitly select and confirm.

### 1.5 Success Criteria (for this assignment)

- A user can go from cold launch to a completed, safe cleanup in under 3 minutes for a moderately sized library.
- Every deleted item was individually selectable and was shown again, unambiguously, on a final confirmation screen before deletion.
- Zero unintended deletions across the safety test suite (see Document 08).
- Scan of a 10,000+ photo library completes without blocking the UI thread and without a memory crash.
- The app is fully usable (in a degraded but honest way) when Photos or Contacts permission is denied or limited.

### 1.6 Non-Goals (Out of Scope)

Explicitly excluded from this build, per assignment scope:

- Payments, subscriptions, paywalls
- Login / accounts / cloud sync of any kind
- Email inbox cleaning
- Clearing other apps' cached data / offloading apps
- iPad-specific layout (iPhone only; iPad may work incidentally but is not a design target)
- Automatic / scheduled background cleanup
- Any AI/ML claim beyond what is actually implemented (see Document 06 for what "similarity" really means here)
- Cloud or server-side processing of any kind — everything is on-device by hard requirement

---

## 2. Core User Stories

Written in "as a user" form, each maps to acceptance criteria used later in QA (Document 08).

1. **As a user**, I want to see total, used, available, and estimated-recoverable storage on launch, so I understand the scale of the opportunity before I do anything.
2. **As a user**, I want duplicate and similar photos grouped automatically, so I don't have to manually compare hundreds of images.
3. **As a user**, I want the app to recommend which photo in a group to keep, with a visible reason, so I can decide quickly but not blindly.
4. **As a user**, I want to override the app's recommendation and pick a different photo to keep, or keep all of them, so I stay in control.
5. **As a user**, I want to select an entire group or individual items within it, so review scales to my patience level.
6. **As a user**, I want to identify old/redundant screenshots quickly in a dedicated view, since they rarely need individual review.
7. **As a user**, I want to see my largest videos with duration, resolution and size, so I can judge which are worth keeping without guessing.
8. **As a user**, I want to preview (play) a video before deleting it, so I never delete based on a thumbnail alone.
9. **As a user**, I want duplicate contacts identified — separating "exact" from "probable" duplicates — so I don't lose a unique person to an overzealous match.
10. **As a user**, I want a single, final review screen listing exactly what will be deleted and how much space will be freed, so nothing is a surprise.
11. **As a user**, I want to explicitly confirm before anything is deleted — a second, unambiguous tap, not a default toggle — so destructive actions never feel accidental.
12. **As a user**, I want the app to keep working, honestly, if I deny or limit permissions, rather than crash or pretend to have data.

---

## 3. Functional Requirements

### 3.1 Storage Dashboard

**Must show:**
- Total device storage capacity
- Used storage (system-reported)
- Available/free storage
- Estimated recoverable storage (sum of bytes represented by *currently selected* or, before any scan, an "estimated potential" derived from scan results only — never a guess prior to scanning)
- Recoverable storage broken out by category: Similar/Duplicate Photos, Screenshots, Large Videos, Duplicate Contacts (contacts contribute ~0 bytes but a count)
- Scan status: not started / scanning (with phase + progress) / complete / partial (cancelled) / failed
- Last scan timestamp, persisted locally between app launches

**Constraints:**
- Must use `UIDevice`/`FileManager` volume capacity keys for total/used/available storage. These are OS-reported values, not invented.
- Must never claim to know about "junk files," cache, or other-app storage that iOS does not expose to third-party apps. If a number cannot be attributed to a real, inspectable resource, it is not shown.
- "Estimated recoverable" is always derived from actual scanned assets' `PHAssetResource` file sizes — never modeled or approximated from category averages.

### 3.2 Similar Photos (includes Exact Duplicates)

System must:
- Request and use PhotoKit (`PHPhotoLibrary`) access
- Detect **exact duplicates**: byte-identical or asset-identical images (see Document 06 for detection method)
- Detect **visually similar photos**: near-duplicate bursts, minor variations, retakes (see Document 06 for the precise, honest definition of "similar" used — perceptual-hash Hamming distance under a calibrated threshold, not a marketing claim of "AI")
- Group related images into `PhotoGroup`s, each with a recommended "keep" candidate and a stated reason (e.g., "Highest resolution, sharpest")
- Allow manual override of the recommended keep photo within a group
- Allow selecting individual items or an entire group (excluding the recommended-keep item by default — the app never pre-selects the photo it just recommended keeping)
- Calculate recoverable bytes live as selection changes
- Show thumbnails for every asset (from `PHImageManager`, cached, never the full-resolution image unless the user opens a detail/preview view)
- Show useful metadata per photo: capture date, resolution, file size, and (for a group) similarity confidence

### 3.3 Screenshots

- Identify screenshots via `PHAsset.mediaSubtypes.contains(.photoScreenshot)` — the only reliable, documented PhotoKit signal for this category
- Grid view, chronological, most recent first
- Select individual items, Select All, Deselect All
- Live recoverable-size total as selection changes
- No similarity/duplicate logic applied here — screenshots are reviewed as a flat set since duplicate screenshots are rare and not worth a false-positive risk

### 3.4 Large Videos

- List all videos (`PHAsset.mediaType == .video`) sorted by file size, descending
- Show thumbnail, duration, resolution, file size, capture date, selection state
- Allow full in-app preview (playback via `AVPlayer`) before selection/deletion — this is a hard requirement, not optional, because a thumbnail is insufficient evidence for deleting a video
- No transcoding, no compression offered in this scope — deletion only

### 3.5 Duplicate Contacts

- Uses `CNContactStore` with an explicit, minimal key-fetch set
- Detects and separates into two tiers:
  - **Exact duplicates**: identical normalized phone number(s) or identical normalized email(s) AND matching full name
  - **Probable duplicates**: normalized phone/email overlap without full name match, or high name-similarity with partial field overlap (see Document 06 for the exact algorithm and thresholds)
- Never silently merges. The app always presents a **merge/delete preview** showing exactly which fields would survive and which contact record(s) would be removed, and the user must confirm per group (or via the same global review screen as photos/videos)
- Surfaces which fields differ (e.g., one contact has an email the other lacks) so the user can see what could be lost by choosing "delete" over "merge"

### 3.6 Review Before Delete (mandatory checkpoint)

A single **Review** screen aggregates every pending selection across all categories before any deletion request is made:

```
Items to remove
  X photos (similar/duplicate)
  X screenshots
  X videos
  X contacts

Estimated storage to be freed: XX MB / GB

[ Cancel ]                [ Confirm & Clean Up ]
```

Requirements:
- Every item counted here must be individually inspectable (tap to expand / thumbnail grid) before the final confirm tap
- The confirm action requires a second, explicit tap — never a swipe, never a pre-checked toggle, never a timeout-based auto-confirm
- Cancelling this screen performs **zero** deletions and preserves the user's selections (does not silently clear them) so they can return and adjust
- After confirmation, actual deletion is requested through the appropriate OS API (`PHPhotoLibrary.performChanges` deleting assets which shows the native iOS "Delete X Photos" system confirmation as a second, OS-level safety net; `CNSaveRequest` deletes for contacts)

### 3.7 Permissions

The app must gracefully support and visibly communicate every PhotoKit/Contacts authorization state:

| State | Behavior |
|---|---|
| Not determined | Show rationale, then system prompt on first relevant screen entry, never at cold launch before context is given |
| Authorized (full) | Full functionality |
| Limited (Photos only) | Full functionality on the limited set; persistent, non-blocking banner explaining scope is limited, with a link to expand selection via `PHPhotoLibrary.presentLimitedLibraryPicker` |
| Denied | Category screens show a clear empty/error state explaining what's missing and a direct deep link to Settings — dashboard and other categories remain usable |
| Restricted (e.g., parental controls) | Same treatment as denied, with accurate copy (cannot be changed by the user in-app) |

The app must never crash, hang, or silently show an empty state indistinguishable from "you have nothing to clean" when the real cause is a missing permission.
