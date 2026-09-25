#!/usr/bin/env python3
"""
Deterministic secret + network-code scanner (docs/26 §1).

Scope: application sources, test sources, build tooling, CI workflow, and the
generated project file. Documentation is deliberately out of scope — docs/
discuss security in prose (e.g. "this app has no API keys") and would only
produce false positives.

Contract:
  - Reports pattern ID + file + line number, NEVER the matched text itself,
    so a real secret can never be printed into CI logs by the scanner.
  - Exit 0 = clean; exit 1 = at least one finding. No warnings, no
    suppression flags: the app is small and the patterns are tight.

This is a deterministic pattern scanner, not gitleaks/trufflehog — chosen so
the exact rule set is reviewable in-repo and the scan is reproducible on the
owner's Windows machine as well as in CI. The README/docs disclose this
choice explicitly.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCAN_DIRS = ["Reclaim", "ReclaimTests", "ReclaimUITests", "scripts", ".github"]
SCAN_EXTS = {".swift", ".py", ".yml", ".yaml", ".plist", ".pbxproj", ".sh"}
SCAN_FILES = {"project.pbxproj"}

# (id, compiled regex). Keep patterns tight: every match must be a real
# signal, not style noise. Nothing here should fire on this codebase —
# that is the point: a finding means a real regression to fix.
PATTERNS = [
    ("SECRET_AWS_ACCESS_KEY", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("SECRET_GOOGLE_API_KEY", re.compile(r"AIza[0-9A-Za-z_\-]{35}")),
    ("SECRET_GITHUB_TOKEN", re.compile(r"gh[pousr]_[0-9A-Za-z]{36,}")),
    ("SECRET_SLACK_TOKEN", re.compile(r"xox[baprs]-[0-9A-Za-z\-]{10,}")),
    ("SECRET_PRIVATE_KEY_BLOCK", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("SECRET_P12_OR_MOBILEPROVISION", re.compile(r"\.(p12|mobileprovision|pem|keychain)\b", re.IGNORECASE)),
    ("SECRET_GENERIC_APIKEY_LITERAL", re.compile(r"""(?i)(api[_-]?key|secret|passwd|password)\s*[:=]\s*["'][A-Za-z0-9_\-/.+]{16,}["']""")),
    ("SECRET_BEARER_LITERAL", re.compile(r"(?i)bearer\s+[A-Za-z0-9_\-/.]{20,}")),
    ("NETWORK_URLSESSION", re.compile(r"\bURLSession\b")),
    ("NETWORK_LIBRARY", re.compile(r"\b(Alamofire|Firebase|Mixpanel|Amplitude|Sentry|Crashlytics|Analytics)\b")),
    ("NETWORK_DATA_TASK", re.compile(r"\bdataTask\b|\buploadTask\b|\bdownloadTask\b")),
    ("NETWORK_WEBSOCKET", re.compile(r"\bURLSessionWebSocketTask\b|\bNWConnection\b|\bNWPathMonitor\b")),
    ("NETWORK_HTTP_URL", re.compile(r"""\bhttps?://(?!localhost|127\.0\.0\.1|apple\.com|developer\.apple\.com|help\.apple\.com)[A-Za-z0-9.\-]+""")),
    ("CLOUD_SERVICE", re.compile(r"\b(S3\.|s3\.amazonaws|storage\.googleapis|blob\.core\.windows|dropbox|icloud\.com|cloudkit)\b", re.IGNORECASE)),
]

# The scanner's own source file contains the pattern literals by design and
# is excluded from its own scan — a scanner flagging its rule table is noise,
# not a signal.
SELF_EXCLUDED_FILES = {"security_scan.py"}

# Deliberately allowed, reviewed exceptions — each documented in docs/26.
ALLOWED = {
    # Info.plist's only http URL is the Apple DTD declaration in the
    # plist DOCTYPE — markup boilerplate, not a network call.
    ("NETWORK_HTTP_URL", "Reclaim/Resources/Info.plist"),
}


def should_scan(path):
    parts = path.split(os.sep)
    if any(d in parts for d in SCAN_DIRS):
        ext = os.path.splitext(path)[1]
        return ext in SCAN_EXTS or os.path.basename(path) in SCAN_FILES
    return False


def main():
    findings = []
    for base in SCAN_DIRS:
        base_path = os.path.join(ROOT, base)
        if not os.path.isdir(base_path):
            continue
        for dirpath, dirnames, filenames in os.walk(base_path):
            dirnames[:] = [d for d in dirnames if d not in {"__pycache__", "xcuserdata", ".git"}]
            for filename in filenames:
                if filename in SELF_EXCLUDED_FILES:
                    continue
                path = os.path.join(dirpath, filename)
                if not should_scan(path):
                    continue
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as fh:
                        for lineno, line in enumerate(fh, 1):
                            for pid, pattern in PATTERNS:
                                if pattern.search(line):
                                    # Normalize separators/case so the ALLOWED
                                    # table matches on every OS (Windows emits
                                    # backslashes from os.path.relpath).
                                    rel = os.path.relpath(path, ROOT).replace("\\", "/")
                                    if (pid, rel) in ALLOWED:
                                        continue
                                    findings.append((pid, rel, lineno))
                except OSError:
                    continue

    if findings:
        print(f"SECURITY SCAN FAILED: {len(findings)} finding(s)")
        for pid, rel, lineno in findings:
            # Never print the matched text — only the location and rule ID.
            print(f"  [{pid}] {rel}:{lineno}")
        return 1

    print(f"SECURITY SCAN OK: {len(PATTERNS)} patterns, 0 findings "
          f"(scanned {', '.join(SCAN_DIRS)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
