# 02 — UX Design Specification

## 1. Product Name

**Reclaim**

Rationale: names the outcome (getting space back), not the mechanism ("cleaner," "booster"), avoids the crowded "X Cleanup / X Cleaner" naming pattern in the App Store, and supports a calm, confident tone rather than an alarmist one ("Storage Alert!", "Junk Found!").

Tagline: *"See it. Review it. Reclaim it."* — encodes the trust-before-cleanup principle directly into the brand line.

## 2. Visual Identity

### 2.1 Design philosophy

Reclaim should feel like a precision instrument, not a gimmick. The closest reference points are Apple's own Settings/Files/Health apps: restrained color, generous whitespace, information hierarchy that never requires the user to guess what's tappable. Destructive intent is telegraphed by color and copy, never by animation flourish.

### 2.2 Color

- **Base:** System background colors (`Color(.systemBackground)`, `Color(.secondarySystemBackground)`) — full light/dark support via semantic colors only, no hardcoded hex on backgrounds.
- **Brand accent — "Reclaim Teal"**: `#0E7C7B` (light) / `#3FD4C6` (dark-adjusted). Used for primary actions, selected states, progress indicators. Chosen because it reads as "clean/calm," is distinct from Apple's system blue (avoids implying a system feature), and passes WCAG AA contrast on both backgrounds.
- **Destructive — system red** (`Color(.systemRed)`), used *exclusively* for delete/confirm-delete affordances. Never used decoratively, so its meaning stays unambiguous.
- **Category colors** (used only as small icon tints, never full-surface fills): Photos — teal, Screenshots — indigo, Videos — orange, Contacts — purple. Chosen for AA-compliant contrast in both appearances and easy differentiation for color-vision-deficient users (paired with distinct SF Symbols, never color-only).
- No gradients on functional UI. A single, subtle radial gradient is permitted only on the dashboard's hero storage ring, matching Apple's own Storage settings visual language.

### 2.3 Typography

- SF Pro (system font) throughout — full Dynamic Type support, no fixed point sizes on body text.
- Hierarchy: `.largeTitle` (screen titles) → `.title2`/`.headline` (section headers, e.g., "Similar Photos") → `.body` (primary content) → `.footnote`/`.caption` (metadata: dates, sizes, confidence).
- Numbers that matter (storage totals, item counts) use `.largeTitle.bold()` with monospaced digit variant (`.monospacedDigit()`) so values don't jitter in width as they update live during selection.

### 2.4 Iconography

SF Symbols exclusively — no custom icon set, both for consistency and to guarantee correct rendering across Dynamic Type/accessibility settings. Category icons: `photo.on.rectangle.angled` (Similar Photos), `camera.viewfinder` (Screenshots), `video.fill` (Large Videos), `person.crop.circle.badge.exclamationmark` (Duplicate Contacts).

### 2.5 Spacing, radius, cards

- 8pt base spacing grid (8/16/24/32).
- Cards: 16pt corner radius, `Color(.secondarySystemGroupedBackground)` fill, no drop shadow in light mode heavier than system default grouped-list shadow; subtle 1px hairline border in dark mode instead of shadow.
- Standard screen margin: 16pt horizontal.
- Touch targets minimum 44×44pt (Apple HIG minimum), enforced even inside dense grids (selection checkmarks get a full-cell tap target, not just the icon).

### 2.6 Buttons

- Primary action: filled, full-width or trailing-aligned capsule button, brand teal, white label, `.headline` weight.
- Secondary: bordered, tinted teal outline.
- Destructive confirm: filled, system red, requires the word "Delete" or "Confirm & Clean Up" in the label — never an icon-only destructive button on the final confirmation step.
- Disabled state: 40% opacity + disabled interaction, used when selection is empty (e.g., "Confirm & Clean Up" is disabled until ≥1 item selected).

### 2.7 Empty / error / loading states

- **Empty (nothing found):** friendly confirmation, not an apology — e.g., "No similar photos found. Your library looks tidy here." with the category icon at low opacity. Never implies failure.
- **Error (scan failed / resource unavailable):** short, specific message + a "Try Again" action. No stack traces, no generic "Something went wrong" without a next step.
- **Permission-denied:** explains exactly what's unavailable and why, with a single "Open Settings" button (`UIApplication.openSettingsURLString`). Rest of app remains navigable.
- **Loading/scanning:** determinate progress bar + current phase label (e.g., "Analyzing photos — 1,204 / 8,300") whenever a count is knowable; indeterminate only for sub-second operations. Cancel button always present during scans longer than ~2 seconds.

### 2.8 Motion & haptics

- Animations are functional, not decorative: selection toggle (spring, 0.2s), progress updates (linear), screen transitions (standard SwiftUI push/sheet — no custom transitions).
- Haptics: light impact on item selection toggle, medium impact on "Confirm & Clean Up" tap, success notification haptic on cleanup completion. No haptics on passive navigation.

## 3. Information Architecture

Evaluated structure (tab-based) vs. the assignment's suggested tree — a flat tab bar is chosen over deep navigation because the core loop (scan → review → confirm) must never be more than 2 taps from any category, and users comparing "which category to tackle first" benefit from siblings being visible, not nested.

**Chosen structure — 2-level, tab-bar rooted:**

```
Tab Bar
├── Dashboard (root/home)
│     → entry point for permission flow, storage overview,
│       category summary cards, "Scan" / "Rescan" action
├── Clean Up (single scrollable hub)
│     ├── Similar Photos       (push → detail/group view)
│     ├── Screenshots          (push → grid view)
│     ├── Large Videos         (push → list view)
│     └── Duplicate Contacts   (push → group view)
└── Review  (badge shows total pending-selection count)
      → aggregated cross-category confirmation screen
```

Rationale for deviating from the assignment's illustrative tree: putting Photos/Videos/Contacts as three separate top-level tabs would fragment the "how much can I free up in total" mental model and bury the Review screen. A single "Clean Up" hub keeps categories as siblings (matches how users think: "what's eating my space," not "which framework provides this data"), while "Review" as its own persistent tab reinforces that confirmation is a first-class, always-reachable step — never something buried at the bottom of a long scroll.

## 4. Screen-by-Screen Specification

### 4.1 Dashboard

- **Purpose:** Orient the user — how full is my phone, what can Reclaim likely help with, what's the state of my last scan.
- **Entry point:** App launch (default tab).
- **Components:** Storage ring (used/available, OS-reported), 4 category summary cards (icon, label, item count or "—" if not scanned, recoverable size), primary CTA ("Scan Now" / "Rescan"), last-scanned timestamp, permission status banner if relevant.
- **Data required:** `FileManager` volume capacity keys; cached `ScanResult` if one exists.
- **User actions:** Start scan, tap a category card (navigates to Clean Up hub, scrolled/deep-linked to that section), tap Review if pending selections exist.
- **Loading state:** Storage ring animates in from 0; category cards show skeleton shimmer until first scan completes.
- **Empty state:** Pre-first-scan: cards show "Not scanned yet" with a single "Scan Now" CTA — no fabricated zeros.
- **Error state:** Scan failure banner with retry; storage ring still shows (it doesn't depend on scan).
- **Permission state:** If Photos and/or Contacts denied, banner explains exactly which categories are unavailable; unaffected categories still function.
- **Accessibility:** Storage ring has an `accessibilityLabel` stating the numbers in words ("62 gigabytes used of 128 gigabytes"), not just a visual ring. Cards are single accessibility elements combining icon+label+count.
- **Destructive behavior:** None on this screen — informational only.

### 4.2 Clean Up Hub

- **Purpose:** Single scrollable entry into all four detection categories.
- **Entry point:** Tab bar, or deep link from Dashboard card tap.
- **Components:** Four sections/cards, each summarizing category state and linking to its detail screen.
- **Data required:** Latest `ScanResult` per category.
- **User actions:** Tap into any category.
- **Loading/empty/error/permission states:** Mirror Dashboard cards, but each section states its own status independently (e.g., Photos authorized+scanned, Contacts denied).
- **Accessibility:** Each section is a clearly labeled navigation link with state announced ("Similar Photos, 312 items, 1.2 gigabytes recoverable").

### 4.3 Similar Photos — Group List

- **Purpose:** Show all detected groups of duplicate/similar photos.
- **Entry point:** Clean Up hub.
- **Components:** List of `PhotoGroup` rows — stacked thumbnail preview (top 3 photos), item count, recommended-keep note, recoverable size for that group.
- **User actions:** Tap group → Group Detail; "Select All Recommended" bulk action (selects every group's non-recommended photos across all groups — the *only* bulk action that pre-selects anything, and it is explicit, opt-in, and reviewable, never automatic).
- **Loading state:** Per-phase progress during scan (see Document 09).
- **Empty state:** "No similar photos found."
- **Destructive behavior:** None here — selection only; nothing is deleted until Review.

### 4.4 Similar Photos — Group Detail

- **Purpose:** Let the user inspect one group closely and decide what to keep.
- **Components:** Grid of full thumbnails, recommended photo badged ("Suggested keep — sharpest, highest resolution"), tap-to-preview (full screen, pinch zoom), checkbox selection per photo, group recoverable-size total.
- **User actions:** Override recommended keep (tap a different photo's "Keep this instead"), select/deselect individual photos, select whole group except keep.
- **Accessibility:** Each photo cell exposes state via `accessibilityLabel`/`accessibilityValue` ("Photo 3 of 5, selected for deletion, taken June 2, 2.1 megabytes") — never relies on a visual checkmark alone.
- **Destructive behavior:** Selecting marks for review; no deletion occurs on this screen.

### 4.5 Screenshots

- **Purpose:** Fast flat-grid review of all screenshots.
- **Components:** Grid (3-up), thumbnail, capture date on long-press/tap, Select All / Deselect All toolbar, running recoverable-size counter.
- **Destructive behavior:** Selection only.

### 4.6 Large Videos

- **Purpose:** Ranked list to help decide what's worth the space.
- **Components:** List sorted by size desc; row shows thumbnail, duration badge, resolution, file size, date; tap thumbnail/row opens full preview player (`AVPlayer`) before selecting.
- **User actions:** Play preview, select/deselect.
- **Destructive behavior:** Selection only; preview never modifies or deletes.

### 4.7 Duplicate Contacts

- **Purpose:** Review contact groups split into Exact and Probable tabs/segments.
- **Components:** Segmented control (Exact / Probable), group rows showing merged-preview avatar stack, names, differing-field indicator ("1 has an extra email").
- **User actions:** Tap group → per-field merge/delete preview screen showing which record + fields would remain vs. be removed; confirm per group or batch into Review.
- **Destructive behavior:** Selection/preview only here.

### 4.8 Review

- **Purpose:** The single mandatory checkpoint before any deletion.
- **Components:** Per-category collapsible sections listing every selected item (thumbnail grid for photos/screenshots/videos, name list for contacts), grand total item count, grand total recoverable storage, "Confirm & Clean Up" (red, disabled until non-empty), "Cancel"/"Back to editing".
- **User actions:** Expand any section to re-inspect, remove an item directly from Review (updates totals live), confirm.
- **Destructive behavior:** This is where the *request* to delete is made — and only after this screen's explicit confirm tap, followed by the OS's own native delete confirmation for Photos.

### 4.9 Cleanup Result

- **Purpose:** Honest confirmation of what actually happened.
- **Components:** Success state showing actual freed storage (recomputed from OS-reported values pre/post, not just the pre-computed estimate) and counts of items actually removed per category; if any deletions failed/were partially denied by the OS, that is shown explicitly, not silently dropped.
- **User actions:** Return to Dashboard (refreshed).
- **Destructive behavior:** None — this is a report.
