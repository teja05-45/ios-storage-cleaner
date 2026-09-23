# 12 — Submission Checklist

Use this before declaring the assignment complete. Each item should be checked against real evidence (a passing test, a recorded measurement, a screenshot), not assumed.

## Documents (Phase 1)
- [ ] All 12 documents in `/docs` exist and are internally consistent (no contradictions between, e.g., Document 01's requirements and Document 06's actual algorithm scope)
- [ ] Every claim about detection accuracy/AI is traceable to an actual algorithm described in Document 06 — nothing oversold
- [ ] Documents reviewed once as a set for gaps before implementation begins, per the assignment's explicit instruction

## Build
- [ ] Clean build from a fresh checkout, no manual project fixes required
- [ ] No compiler warnings in app code (third-party/system warnings, if any, documented)
- [ ] No crash on cold launch, with and without prior permissions granted

## Core Flow
- [ ] Dashboard → Permission → Scan → Results → Selection → Review → Confirmation → Cleanup → Result works end-to-end on simulator
- [ ] Same flow verified on a physical iPhone

## Safety (non-negotiable — see Document 08 §4)
- [ ] Deletion cannot occur without explicit confirmation (structurally, not just via disabled button)
- [ ] Cancelling confirmation performs zero deletions
- [ ] Deselected assets are never deleted (verified with a mixed-selection group)
- [ ] Displayed selection count matches actual deletion count, or discrepancies are shown as explicit failures
- [ ] Displayed freed storage matches the byte sum of selected resources, recomputed independently in tests
- [ ] Denied/restricted permissions never crash the app; all screens remain usable
- [ ] Empty selection cannot be confirmed at either the UI or use-case layer

## Real Device Testing
- [ ] Real photos including genuine duplicates and similar bursts
- [ ] Real screenshots
- [ ] Real large videos, preview playback confirmed working
- [ ] Real contact list with genuine duplicates (exact and probable both represented)
- [ ] Denied permission state tested
- [ ] Limited photo library state tested
- [ ] Empty-state screens tested (not just happy path)

## Large Library Performance
- [ ] Scan duration recorded against 10,000+/1,000+/500+ composition
- [ ] Memory behavior recorded (Instruments Allocations/Leaks)
- [ ] UI responsiveness confirmed (no main-thread hangs during scan)
- [ ] Result accuracy spot-checked against a known-correct subset

## Polish
- [ ] Spacing, typography, icons consistent with Document 02
- [ ] Loading/empty/error/permission states implemented for every screen listed in Document 02 §4
- [ ] Haptics present only where specified, not overused
- [ ] VoiceOver walkthrough of full core loop is coherent
- [ ] Dynamic Type tested at accessibility sizes
- [ ] Dark and light appearance both look intentional
- [ ] Destructive actions are unambiguously styled (red, explicit copy) everywhere they appear

## Privacy Verification
- [ ] Zero network traffic confirmed via Instruments during a full scan + cleanup session
- [ ] No third-party dependencies present in the project
- [ ] Usage description strings are specific and accurate, not boilerplate

## Final Submission Package
- [ ] README.md complete per the required outline (Product, Features, Architecture, Detection Algorithms, Privacy, Testing, Performance, Tradeoffs, AI Usage, Known Limitations, Setup)
- [ ] Submission note (<150 words) written
- [ ] Demo recorded or demo-ready per Document 11
- [ ] Git history reflects logical, meaningfully-scoped commits (Document 10 phases), not one giant commit
