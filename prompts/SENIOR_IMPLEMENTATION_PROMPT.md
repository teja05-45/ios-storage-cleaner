# AppFactory Storage Cleaner — Senior 15+ YOE Implementation Prompt

## Role

Act as a Principal iOS Engineer, Mobile Architect, Product Engineer, Performance Engineer, Security Engineer, and QA Lead with 15+ years of production experience.

You are implementing the AppFactory Storage Cleaner selection assignment as a GREENFIELD iOS application.

The goal is not to generate a demo or a collection of screens. Build a trustworthy, performant, polished, shippable iPhone product.

Primary principle:

> TRUST BEFORE CLEANUP

The application must make every destructive action explicit, reviewable, revalidated, and safe.

---

# 0. SOURCE OF TRUTH

Before coding, read every planning document under `/docs`.

Required order:

1. `01-product-requirements.md`
2. `02-ux-design-spec.md`
3. `03-technical-requirements.md`
4. `04-system-architecture.md`
5. `05-data-model.md`
6. `06-scanning-algorithms.md`
7. `07-security-privacy.md`
8. `08-testing-strategy.md`
9. `09-performance-strategy.md`
10. `10-implementation-plan.md`
11. `11-demo-script.md`
12. `12-submission-checklist.md`
13. `13-greenfield-implementation-analysis.md`
14. `00-senior-review-and-required-changes.md` if present

If a senior-review document exists, it overrides conflicting base-spec decisions.

Never invent a requirement, test result, API capability, performance number, or existing implementation.

---

# 1. GREENFIELD RULE

There is intentionally no existing Xcode project.

Do not ask for an existing repository.

Create the application from scratch.

Before implementation, create:

`docs/14-implementation-decisions.md`

Record decisions for:
- contact merge scope
- PhotoKit resource selection
- storage measurement
- limited-library behavior
- stale-selection revalidation
- concurrency strategy
- scan cache strategy
- deletion semantics

For each:

Decision
Reason
Alternatives
Tradeoff

---

# 2. VERIFY APPLE APIS FIRST

Before building framework-dependent code, verify actual iOS 17+ APIs.

Verify:

## Photos
- PHPhotoLibrary
- PHAuthorizationStatus
- PHFetchResult
- PHAsset
- PHAssetResource
- PHAssetResourceManager
- PHImageManager
- PHCachingImageManager
- PHPhotoLibrary.performChanges
- PHAssetChangeRequest
- limited-library APIs

## Contacts
- CNContactStore
- CNAuthorizationStatus
- CNContact
- CNMutableContact
- CNSaveRequest

## Video
- AVAsset
- AVURLAsset
- AVAssetImageGenerator
- AVPlayerViewController

## Storage
- FileManager
- URLResourceKey storage/capacity APIs

If the planning docs reference an API incorrectly or rely on private/KVC behavior, do not blindly implement it. Find the public supported alternative and update the documentation.

---

# 3. ARCHITECTURE

Use Swift + SwiftUI + iOS 17+.

Prefer native Apple frameworks.

Avoid unnecessary third-party dependencies.

Use a clear dependency direction:

UI
↓
ViewModels / Feature State
↓
Use Cases
↓
Services
↓
Apple Frameworks

Core models must not import PhotoKit or Contacts.

Recommended structure:

StorageCleaner/
├── App/
├── Core/
│   ├── Models/
│   ├── Errors/
│   ├── Utilities/
│   ├── Algorithms/
│   └── Extensions/
├── Features/
│   ├── Dashboard/
│   ├── Photos/
│   ├── Screenshots/
│   ├── Videos/
│   ├── Contacts/
│   ├── Review/
│   └── CleanupResult/
├── Services/
│   ├── Permissions/
│   ├── PhotoLibrary/
│   ├── PhotoScanning/
│   ├── Similarity/
│   ├── VideoScanning/
│   ├── Contacts/
│   ├── Storage/
│   └── Cleanup/
├── UI/
│   ├── Components/
│   ├── Theme/
│   └── Modifiers/
├── Resources/
└── Tests/

You may improve this structure when there is a concrete architectural reason.

Do not over-engineer.

---

# 4. CORE PRODUCT LOOP

Build this before bonus features:

DASHBOARD
→ PERMISSION
→ SCAN
→ RESULTS
→ SELECT
→ REVIEW
→ EXPLICIT CONFIRMATION
→ REVALIDATE
→ CLEANUP
→ RESULT

The application must never have a direct:

SCAN → DELETE

or:

SELECT → DELETE

path.

Only the cleanup use case may initiate destructive operations.

---

# 5. APP FEATURES

Implement all core requirements.

## Dashboard

Show:
- actual device storage information where supported
- used/free capacity
- scan status
- last scan
- estimated recoverable media by category

Never fabricate pre-scan numbers.

Distinguish:

- device storage
- estimated recoverable size
- verified post-cleanup device storage change

Do not claim that selected media bytes are guaranteed to equal the immediate device free-space increase.

---

## Similar / Duplicate Photos

Build a staged pipeline:

1. Enumerate authorized PhotoKit assets.
2. Extract lightweight metadata.
3. Create candidate buckets.
4. Detect exact duplicates using a safe deterministic resource strategy.
5. Generate thumbnails for similarity analysis.
6. Compute perceptual hashes.
7. Compare candidate hashes.
8. Cluster similar images.
9. Score candidates.
10. Recommend a keep candidate.
11. Allow manual override.
12. Feed selection into ReviewStore.

Avoid O(n²) full-library comparisons.

Use bounded concurrency.

Do not load full-resolution images unnecessarily.

Do not call the feature AI-powered unless a real ML model is implemented.

---

## Exact Duplicates

Use dimensions/resource metadata as cheap prefilters.

Then verify exact equality with a robust content hash where appropriate.

Stream large resources instead of loading entire files into memory.

Do not use a thumbnail hash as proof of exact duplication.

---

## Similar Photos

Use an explainable perceptual similarity approach.

Recommended:
- normalized thumbnail
- grayscale/resize
- dHash or equivalent documented perceptual hash
- Hamming distance
- threshold
- clustering

Keep thresholds centralized/configurable.

Create real fixture tests.

Test:
- identical
- near duplicate
- unrelated
- burst sequence
- transitive similarity chain

---

## Best-Photo Recommendation

Use only signals actually implemented.

Potential signals:
- resolution
- sharpness
- exposure
- file size

Do not claim face detection, ML quality scoring, or other signals unless implemented.

Use language:

"Recommended to keep"

rather than:

"Best photo"

Always allow manual override.

---

## Screenshots

Detect screenshots using PhotoKit metadata/subtype.

Support:
- grid
- multi-select
- select all
- deselect all
- running estimated total

---

## Large Videos

List videos from largest to smallest.

Show:
- thumbnail
- duration
- resolution
- file size
- date
- selection state

Do not instantiate expensive AVAsset objects for every video during the initial enumeration unless required.

Load video preview lazily.

Video preview must actually play.

---

## Duplicate Contacts

Build:

Contact enumeration
→ normalization
→ candidate grouping
→ exact/probable classification
→ review

Normalize:
- phone
- email
- names

Protect against false positives.

A name similarity alone must never be sufficient to surface a destructive duplicate candidate.

If automated merge is unsafe within the assignment timeline:

ship review + explicit delete

and document merge as a limitation.

Never fake merge behavior.

---

# 6. PERMISSIONS

Handle every relevant state.

Photos:
- not determined
- restricted
- denied
- limited
- authorized

Contacts:
- not determined
- denied/restricted
- authorized

Limited Photos access is not an error.

The UI must clearly tell the user that only the authorized subset is being scanned.

Allow the user to expand access where supported.

Re-check authorization when the application returns to the foreground.

Never silently continue using stale authorization assumptions.

---

# 7. REVIEW STORE

Use a single source of truth for selection.

All category screens write selection through ReviewStore.

Review screen must calculate:

- total items
- category counts
- estimated media size
- selected contacts
- selected videos
- selected photos

Never maintain independent hidden selection state that can drift from ReviewStore.

Test:

Review count == sum of real category selections.

---

# 8. SAFE CLEANUP

Create one destructive entry point:

`PerformCleanupUseCase`

No other class should directly perform deletion.

Before deletion:

1. Confirm selection is non-empty.
2. Verify the user explicitly confirmed.
3. Re-check current authorization.
4. Revalidate every selected asset/contact.
5. Remove stale/nonexistent entries from the executable set.
6. Perform deletion.
7. Capture per-item/per-operation failures.
8. Produce accurate CleanupSummary.
9. Recompute post-cleanup storage.
10. Show the result.

Handle partial failures honestly.

Never report an item as successfully deleted if the operation failed.

---

# 9. STORAGE RESULT HONESTY

Before cleanup:

`estimatedRecoverableBytes`

After cleanup:

recompute storage independently.

Do not simply display the previous estimate as "space freed."

If actual device free-space change cannot be reliably established, say so.

Never fabricate metrics.

---

# 10. PERFORMANCE

Target:

- 10,000+ photos
- 1,000+ videos
- 500+ screenshots

Requirements:

- no expensive work on MainActor
- bounded concurrency
- batching
- autoreleasepool where appropriate
- thumbnail caching
- streaming large resources
- progressive results
- cancellation
- minimal persistent data

Scanning should expose:

- phase
- progress
- completed count
- total count
- cancellation

Do not use thousands of concurrent tasks.

---

# 11. SCAN CACHING

Cache only derived data.

Cache examples:
- hash
- lightweight metadata
- scan timestamp
- schema version

PhotoKit/Contacts remain the source of truth.

Never use cache as proof that an asset still exists.

Before deletion, revalidate against current framework state.

If algorithm semantics change, invalidate incompatible cached hashes.

---

# 12. PRIVACY

Everything runs on-device.

Do not add:
- cloud image APIs
- external AI inference
- analytics containing media
- contact uploads
- remote synchronization

Do not persist private media unnecessarily.

Do not log:
- contact names
- phone numbers
- emails
- asset identifiers
- private filenames
- image metadata

Use PII-safe logging.

---

# 13. UX QUALITY

Build an original product identity.

Do not copy the reference app's:
- branding
- text
- artwork
- colors
- exact screen layouts

Use:
- SwiftUI
- SF Symbols
- semantic colors
- Dynamic Type
- VoiceOver
- clear hierarchy
- subtle animation
- appropriate haptics
- excellent empty/loading/error states

The product should look intentional and premium without becoming visually noisy.

---

# 14. TESTING

Write tests alongside implementation.

## Unit tests

Test:
- storage calculations
- selection invariants
- dHash
- Hamming distance
- clustering
- recommendation scoring
- screenshot detection
- phone normalization
- email normalization
- name similarity
- duplicate classification

## Safety tests

Prove:

- empty selection cannot be confirmed
- no confirmation = no deletion
- cancelled confirmation = no deletion
- deselection = no deletion
- stale asset = safe handling
- revoked permission = safe handling
- partial failure = accurate result
- Review count remains correct

## Integration tests

Where possible test:
- PhotoKit service
- Contacts service
- cleanup service

Do not claim framework integration tests passed unless they actually ran on a suitable environment.

---

# 15. REAL DEVICE VALIDATION

A Simulator-only completion is not acceptable for final submission.

On a physical iPhone test:

- real library
- exact duplicates
- similar photos
- screenshots
- large videos
- duplicate contacts
- limited photo permission
- denied permissions
- cancellation
- stale assets
- cleanup
- post-cleanup result

Use private/test media for recording.

Do not include private photos in the repository or screen recording.

---

# 16. PERFORMANCE PROFILING

After the core loop works:

Use Instruments on a real device.

Measure actual:
- scan time
- peak memory
- CPU behavior
- UI responsiveness
- cleanup duration

Do not invent measurements.

Put only measured results in README/documentation.

---

# 17. DEVELOPMENT METHOD

Implement vertical slices.

### Slice 1
Project
→ design system
→ permissions
→ dashboard
→ PhotoKit enumeration

### Slice 2
Photo enumeration
→ exact duplicates
→ selection
→ ReviewStore

### Slice 3
Review
→ confirmation
→ cleanup
→ result

### Slice 4
Similar photos

### Slice 5
Screenshots

### Slice 6
Large videos

### Slice 7
Contacts

### Slice 8
Performance + polish

This ensures there is a working core loop early.

---

# 18. CODE QUALITY

Use:
- clear naming
- small focused types
- dependency injection
- protocols where useful
- structured concurrency
- `@MainActor` only for UI state
- `Sendable` where appropriate
- explicit error types
- no force unwraps in production paths unless justified
- no magic numbers for algorithm thresholds
- no duplicated business logic

Do not create abstractions without a real need.

---

# 19. DOCUMENTATION

Maintain:

`README.md`

Include:
- product overview
- architecture
- algorithms
- privacy
- testing
- performance
- limitations
- setup
- AI usage

Also maintain:

`docs/14-implementation-decisions.md`
`docs/15-validation-results.md`

Do not fill validation results with placeholders that look like completed measurements.

---

# 20. GIT

Use meaningful commits.

Examples:

feat: bootstrap iOS project
feat: implement permission coordinator
feat: add storage dashboard
feat: implement PhotoKit enumeration
feat: implement exact duplicate detection
feat: add ReviewStore
feat: implement cleanup safety boundary
feat: add similar photo detection
feat: add screenshot detection
feat: add large video scanner
feat: add duplicate contact detection
test: add scanner unit tests
test: add cleanup safety tests
perf: optimize photo scanning
ui: polish review workflow
docs: document architecture

Do not create fake commits to inflate commit count.

---

# 21. FIVE-DAY SCOPE CONTROL

Do not implement bonuses until every core feature works.

Core priority:

1. Safety
2. Core loop
3. Correctness
4. Performance
5. UX polish
6. Testing
7. Documentation
8. Bonus features

If time becomes constrained, reduce bonus scope rather than reducing safety/testing.

---

# 22. FINAL ACCEPTANCE GATE

Do not declare "complete" until the following are true or explicitly marked pending because the environment cannot perform them.

### Product
- dashboard
- photos
- screenshots
- videos
- contacts
- review
- confirmation
- cleanup
- result

### Safety
- explicit confirmation
- stale revalidation
- accurate failures
- no accidental deletion

### Performance
- bounded concurrency
- cancellation
- large-library architecture
- Instruments validation where environment permits

### Privacy
- on-device processing
- no private-data network calls
- PII-safe logs

### Accessibility
- Dynamic Type
- VoiceOver
- semantic labels

### Documentation
- README
- architecture
- decisions
- tests
- limitations
- actual validation results

---

# 23. FINAL DELIVERABLE QUALITY BAR

The finished repository should communicate:

"I can take an ambiguous product requirement, make engineering decisions, build a real iOS application, reason about safety and privacy, optimize a large-data workflow, test it, and ship it."

Do not optimize for the largest feature count.

Optimize for a trustworthy product.

Start now:

1. Read the specification.
2. Produce the greenfield implementation analysis.
3. Verify API assumptions.
4. Create the Xcode project.
5. Build the first vertical slice.
6. Test continuously.
7. Proceed feature by feature.
