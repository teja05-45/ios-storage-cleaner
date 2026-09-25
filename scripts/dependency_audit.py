#!/usr/bin/env python3
"""
Third-party dependency audit (docs/26 §2).

The app is dependency-free by design (README: "Zero third-party packages").
This script makes that an enforced CI contract instead of prose: it fails if

  1. any SPM/CocoaPods/Carthage manifest appears anywhere in the tree, or
  2. the generated project file references a remote package repository, or
  3. a new Apple-framework import shows up in Services — every framework
     import must be on the reviewed allow-list (privacy: only frameworks
     whose data handling has been audited may be linked).

Exit 0 = audit passes; exit 1 = finding. Windows-compatible (pure stdlib).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_DIRS = ["Reclaim", "ReclaimTests", "ReclaimUITests"]

# Manifests whose mere existence means a third-party dependency was added.
MANIFESTS = [
    "Package.swift",
    "Package.resolved",
    "Podfile",
    "Podfile.lock",
    "Cartfile",
    "Cartfile.resolved",
]

# Apple frameworks allowed to be imported in app code, with the reason each
# is acceptable (docs/26 §2). Anything else must go through review first.
ALLOWED_FRAMEWORKS = {
    "Foundation": "base library",
    "os": "Apple unified logging (os.Logger) — PII-safe Log wrapper",
    "Observation": "iOS 17 @Observable (UI state)",
    "SwiftUI": "UI framework (first-party)",
    "UIKit": "display-scale + settings deep link",
    "CoreGraphics": "image geometry + grayscale bitmaps",
    "CoreImage": "not currently imported — reserved for thumbnail resize per Document 06 §2",
    "Accelerate": "Laplacian sharpness via vImage (on-device DSP)",
    "CryptoKit": "streamed SHA-256 content hashing (local, no network)",
    "Photos": "PhotoKit scanning/deletion (core feature)",
    "PhotosUI": "limited-library picker (PHPhotoLibrary.presentLimitedLibraryPicker)",
    "Contacts": "Contacts scanning/deletion (core feature)",
    "AVKit": "video preview playback",
    "AVFoundation": "not currently imported — reserved for video metadata",
    "XCTest": "test targets only",
}

IMPORT_RE = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)")


def find_manifests():
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", "__pycache__", "DerivedData", ".kilo"}]
        for name in MANIFESTS:
            if name in filenames:
                found.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return found


def check_remote_packages(pbx_path):
    hits = []
    with open(pbx_path, "r", encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            if re.search(r"XCRemoteSwiftPackageReference|XCSwiftPackageProductDependency|repositoryURL", line):
                hits.append((pbx_path, lineno))
    return hits


def check_imports():
    bad = []
    for base in APP_DIRS:
        base_path = os.path.join(ROOT, base)
        for dirpath, _dirnames, filenames in os.walk(base_path):
            for filename in filenames:
                if not filename.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, filename)
                rel = os.path.relpath(path, ROOT)
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for lineno, line in enumerate(fh, 1):
                        m = IMPORT_RE.match(line)
                        if m:
                            mod = m.group(1)
                            if mod not in ALLOWED_FRAMEWORKS:
                                bad.append((rel, lineno, mod))
    return bad


def main():
    problems = []

    manifests = find_manifests()
    for m in manifests:
        problems.append(f"dependency manifest appeared: {m} (app is dependency-free by design — review before adding)")

    pbx = os.path.join(ROOT, "Reclaim.xcodeproj", "project.pbxproj")
    if os.path.isfile(pbx):
        for _path, lineno in check_remote_packages(pbx):
            problems.append(f"remote package reference in project.pbxproj:{lineno}")

    for rel, lineno, mod in check_imports():
        problems.append(f"unreviewed framework import '{mod}' at {rel}:{lineno} "
                        f"(add it to ALLOWED_FRAMEWORKS with a documented reason, or remove)")

    if problems:
        print("DEPENDENCY AUDIT FAILED:")
        for p in problems:
            print(f"  - {p}")
        return 1

    print("DEPENDENCY AUDIT OK: no manifests, no remote package refs, "
          f"all imports within the {len(ALLOWED_FRAMEWORKS)}-framework reviewed allow-list")
    return 0


if __name__ == "__main__":
    sys.exit(main())
