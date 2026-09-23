# 11 — Demo Script (2–3 minutes)

Goal: communicate the core loop and the trust-before-cleanup principle, not a feature tour. Recorded on a physical iPhone with a real (or realistically seeded) library.

## Timing Outline

| Time | Beat | What's shown | What's said (paraphrase, not verbatim script) |
|---|---|---|---|
| 0:00–0:15 | The problem | iOS Settings → Storage screen showing "iPhone Storage Almost Full," vague breakdown | "This is where most storage tools stop being useful — you know you're full, but not what to do about it." |
| 0:15–0:30 | Dashboard | Open Reclaim, storage ring, category cards ("Not scanned yet"), tap Scan Now | "Reclaim starts with an honest picture — real numbers from iOS, nothing invented — then scans on-device." |
| 0:30–0:40 | Permission handling | Photos permission prompt appears, grant it | "Permission is asked for exactly when it's needed, with a plain explanation of why." |
| 0:40–0:55 | Scan | Progress UI showing phases (enumeration → duplicate detection → similarity analysis), Screenshots/Videos populating first, Similar Photos filling in progressively | "Nothing blocks on the slowest step — results appear as they're found, even on a large library." |
| 0:55–1:20 | Similar photo grouping | Open a group, show the recommended-keep badge and its stated reason ("Highest resolution, sharpest of 4"), override the recommendation on one group | "It doesn't just say 'duplicate' — it explains its reasoning, and you can always overrule it." |
| 1:20–1:35 | Screenshots | Grid, Select All, running recoverable-size counter | "The low-risk category — flat review, fast bulk action." |
| 1:35–1:55 | Large videos | Sorted list by size, open a preview player before selecting one | "Never delete a video off a thumbnail alone — preview first." |
| 1:55–2:15 | Duplicate contacts | Exact vs. Probable segmented view, open a group's field-diff preview showing what would be lost | "Contacts get an extra layer of care — nothing is auto-merged, and you see exactly what differs before deciding." |
| 2:15–2:35 | Review screen | Aggregated counts across all four categories, expand one section to re-inspect, then tap Confirm & Clean Up | "This is the one mandatory checkpoint — every category, one final look, before anything happens." |
| 2:35–2:45 | Native confirmation + cleanup | iOS's own delete confirmation appears (for photos), confirm | "Even after our review, iOS gives its own safety net." |
| 2:45–2:55 | Result | Cleanup Result screen with real freed-storage number, Dashboard refreshed | "The number shown here is recomputed from real before/after storage — not the estimate repeated back." |
| 2:55–3:00 | Privacy closer | Brief cut to Instruments Network instrument (or a simple stated line) showing zero network traffic during the whole session | "All of that — the scan, the hashing, the matching, the deletion — happened entirely on this device." |

## What the Demo Deliberately Does Not Spend Time On

- Settings screens, code, or Xcode — the loop is the demo.
- Every possible empty/error state — one clean pass through the happy path, with the permission and confirmation moments kept in because they *are* the trust story, not incidental UI.
- Narrating architecture — that's what Documents 01–10 are for; the demo shows outcomes.

## Fallback Plan

If a live device demo isn't feasible for the reviewer's context, a screen recording following this exact script, narrated live or with captions matching the "what's said" column, satisfies the same goals.
