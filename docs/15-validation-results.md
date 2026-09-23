# 15 — Validation Results

**Status as of this delivery: NOT YET RUN.** Per this project's explicit "never fabricate test results, performance numbers, or supported capabilities" principle, this document records what has and has not actually been verified, rather than presenting placeholder success as if it happened.

## What has been verified

- **API existence and signatures** (Document 14 §0) — checked against current Apple Developer Documentation before writing dependent code. This is real verification, not code review.
- **Structural/logical correctness by inspection** — every file was written, then re-read, against the specification and the ADRs in Document 14. Cross-references between files (protocol conformance, method signatures used at call sites) were checked manually.
- **`.pbxproj` internal consistency** — the generated Xcode project file was checked for balanced braces/parentheses and correct relative group paths after an initial path-nesting bug was caught and fixed (see `generate_pbxproj.py`). This is a syntax-level sanity check, not proof that Xcode can open and build the project.

## What has NOT been verified — required before this can be called a working app

| Item | Why it couldn't be done here | What to do |
|---|---|---|
| **The project compiles** | No Xcode/Swift toolchain in this environment (confirmed: `swift`/`swiftc` not installed, and the network sandbox doesn't allow reaching `download.swift.org` to install one) | Open `Reclaim.xcodeproj` in Xcode 15+, hit Build, fix whatever the compiler finds |
| **The generated `.pbxproj` opens correctly in Xcode** | Same — no Xcode available to open it | First thing to check on a real machine. If it fails to parse, the fallback is to create a fresh Xcode project and drag in the existing `.swift` files (the source itself doesn't depend on the project file being hand-generated) |
| **Unit tests pass** | No Swift test runner available | Run `⌘U` in Xcode once the project builds. The safety-test suite (`SafetyTests/`) and algorithm suite (`CoreTests/`) are both written to run without any PhotoKit/Contacts entitlement or simulator library |
| **PhotoKit/Contacts integration behavior** (real authorization prompts, real limited-library picker, real deletion confirmation dialogs) | No simulator or device | Manual pass on a simulator first, then a physical device |
| **Performance at 10,000+ photos / 1,000+ videos** | No device, no library of that size, no Instruments | Real-device Instruments pass — Time Profiler for the similarity pipeline, Allocations for memory ceiling during scanning |
| **Accessibility** (VoiceOver, Dynamic Type at accessibility sizes) | No simulator/device | Manual pass with VoiceOver enabled and text size at the largest accessibility setting |
| **The demo recording** | No device to record from | Record after the above passes |

## Why this document looks like this

Documents 08 and 09 both specify comprehensive test/performance requirements, and this project's own instructions are explicit: "Do not fabricate test results," "Do not fabricate performance numbers," "Do not consider the project complete because it works in Simulator" (which doesn't even apply here — this hasn't been run in Simulator either). Filling this document with invented numbers or a fake "✅ all tests passing" table would violate that principle more seriously than leaving it honestly incomplete.
