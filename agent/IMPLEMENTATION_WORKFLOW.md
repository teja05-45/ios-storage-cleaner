# Implementation Workflow

## Gate 1 — Understand
Read every specification and the senior implementation prompt.

## Gate 2 — Verify
Verify iOS APIs before depending on them.

## Gate 3 — Decide
Record architectural decisions in `docs/14-implementation-decisions.md`.

## Gate 4 — Bootstrap
Create the SwiftUI iOS 17+ project and build the empty application.

## Gate 5 — Vertical Slice
Dashboard → permissions → photo enumeration.

## Gate 6 — Safety Slice
Selection → ReviewStore → confirmation → revalidation → cleanup → result.

## Gate 7 — Expand
Similar photos → screenshots → videos → contacts.

## Gate 8 — Harden
Unit tests, safety tests, cancellation, stale assets, permission changes.

## Gate 9 — Profile
Physical-device performance profiling with Instruments.

## Gate 10 — Polish
Accessibility, empty states, animations, haptics, visual consistency.

## Gate 11 — Submit
README, demo recording, known limitations, actual validation results, repository cleanup.
