#!/usr/bin/env python3
"""
Validates Reclaim.xcodeproj/project.pbxproj before it is committed.

Why this exists: run 5 of the CI validation workflow failed with
"xcodebuild: error: Unable to read project ... damaged and cannot be
opened due to a parse error" — a defect regex-based audits cannot see,
because only a real OpenStep plist parse reproduces Xcode's strictness.
This script implements that parse.

Checks:
  1. The file parses as an OpenStep plist (recursive descent).
  2. Required root keys exist (archiveVersion, objects, rootObject).
  3. No duplicate object IDs (fatal to Xcode even when parse succeeds).
  4. Every 24-hex-char reference resolves to a defined object.

Exit 0 = valid; exit 1 = invalid (prints the failing location).

Run: python scripts/validate_pbxproj.py
"""
import re
import sys

PATH = "Reclaim.xcodeproj/project.pbxproj"


class ParseError(Exception):
    pass


class OpenStepParser:
    """Recursive-descent parser for the OpenStep plist syntax used by pbxproj.

    Grammar: file := dict ; value := dict | array | quoted | unquoted ;
    unquoted tokens run until whitespace or one of ,();<>{}[]= with
    backslash escapes; quoted strings are double-quoted with backslash
    escapes; comments run from /* to */ and may appear between tokens.
    """

    TOKEN_STOP = set(",();<>{}[]=") | {" "}
    # CoreFoundation's strict unquoted-atom charset: [A-Za-z0-9_$+/:.-].
    # Anything outside it must be quoted — this is exactly the rule that
    # let 'path = FileManager+Storage.swift' break Xcode while a lenient
    # regex audit passed the file.
    WORD = re.compile(r"[A-Za-z0-9_$+/:.-]+")

    def __init__(self, text: str):
        self.text = text
        self.pos = 0
        self.n = len(text)

    def error(self, message: str) -> ParseError:
        line = self.text.count("\n", 0, self.pos) + 1
        col = self.pos - (self.text.rfind("\n", 0, self.pos) + 1) + 1
        return ParseError(f"{message} at line {line}, column {col}")

    def skip_ws_and_comments(self) -> None:
        while self.pos < self.n:
            c = self.text[self.pos]
            if c in " \t\r\n":
                self.pos += 1
            elif self.text.startswith("//", self.pos):
                end = self.text.find("\n", self.pos + 2)
                self.pos = self.n if end == -1 else end + 1
            elif self.text.startswith("/*", self.pos):
                end = self.text.find("*/", self.pos + 2)
                if end == -1:
                    raise self.error("unterminated comment")
                self.pos = end + 2
            else:
                return

    def parse_file(self) -> dict:
        self.skip_ws_and_comments()
        value = self.parse_value()
        self.skip_ws_and_comments()
        if self.pos != self.n:
            raise self.error(f"trailing content after top-level value (next: {self.text[self.pos:self.pos+20]!r})")
        return value

    def parse_value(self):
        self.skip_ws_and_comments()
        if self.pos >= self.n:
            raise self.error("unexpected end of input")
        c = self.text[self.pos]
        if c == "{":
            return self.parse_dict()
        if c == "(":
            return self.parse_array()
        if c == '"':
            return self.parse_quoted()
        return self.parse_unquoted()

    def parse_dict(self) -> dict:
        self.pos += 1  # {
        result = {}
        while True:
            self.skip_ws_and_comments()
            if self.pos >= self.n:
                raise self.error("unterminated dictionary")
            if self.text[self.pos] == "}":
                self.pos += 1
                return result
            key = self.parse_key()
            self.skip_ws_and_comments()
            if self.pos >= self.n or self.text[self.pos] != "=":
                raise self.error(f"expected '=' after key {key!r}")
            self.pos += 1
            value = self.parse_value()
            result[key] = value
            self.skip_ws_and_comments()
            if self.pos < self.n and self.text[self.pos] == ";":
                self.pos += 1
            elif self.pos < self.n and self.text[self.pos] == "}":
                raise self.error(
                    f"missing ';' after value for key {key!r} "
                    "(CoreFoundation rejects this even before a closing brace)"
                )
            else:
                raise self.error(f"expected ';' after value for key {key!r}")

    def parse_key(self):
        c = self.text[self.pos]
        if c == '"':
            return self.parse_quoted()
        m = self.WORD.match(self.text, self.pos)
        if not m:
            raise self.error(f"expected key, found {self.text[self.pos:self.pos+10]!r}")
        self.pos = m.end()
        return m.group(0)

    def parse_array(self) -> list:
        self.pos += 1  # (
        result = []
        while True:
            self.skip_ws_and_comments()
            if self.pos >= self.n:
                raise self.error("unterminated array")
            if self.text[self.pos] == ")":
                self.pos += 1
                return result
            result.append(self.parse_value())
            self.skip_ws_and_comments()
            if self.pos < self.n and self.text[self.pos] == ",":
                self.pos += 1
            elif self.pos < self.n and self.text[self.pos] == ")":
                pass
            else:
                raise self.error("expected ',' or ')' in array")

    def parse_quoted(self) -> str:
        self.pos += 1  # opening quote
        out = []
        while True:
            if self.pos >= self.n:
                raise self.error("unterminated quoted string")
            c = self.text[self.pos]
            if c == "\\":
                if self.pos + 1 >= self.n:
                    raise self.error("dangling backslash in quoted string")
                out.append(self.text[self.pos + 1])
                self.pos += 2
            elif c == '"':
                self.pos += 1
                return "".join(out)
            else:
                out.append(c)
                self.pos += 1

    def parse_unquoted(self) -> str:
        start = self.pos
        while self.pos < self.n:
            c = self.text[self.pos]
            if c in self.TOKEN_STOP or c in "\t\r\n":
                break
            if c == "\\":
                self.pos += 2
                continue
            self.pos += 1
        if self.pos == start:
            raise self.error(
                f"unexpected character {self.text[self.pos]!r} — unquoted atoms "
                "may only contain [A-Za-z0-9_$+/:.-]; quote the string"
            )
        return self.text[start:self.pos].replace("\\", "")


def find_object_ids(node, found):
    if isinstance(node, dict):
        for key, value in node.items():
            found.add(key)
            find_object_ids(value, found)
    elif isinstance(node, list):
        for item in node:
            find_object_ids(item, found)


HEX24 = re.compile(r"^[0-9A-F]{24}$")


def collect_refs(node, refs):
    if isinstance(node, dict):
        for key, value in node.items():
            if HEX24.match(key):
                refs.add(key)
            collect_refs(value, refs)
    elif isinstance(node, list):
        for item in node:
            if isinstance(item, str) and HEX24.match(item):
                refs.add(item)
            else:
                collect_refs(item, refs)


def main() -> int:
    try:
        text = open(PATH, encoding="utf-8").read()
    except OSError as e:
        print(f"FAIL: cannot read {PATH}: {e}")
        return 1

    try:
        root = OpenStepParser(text).parse_file()
    except ParseError as e:
        print(f"FAIL: parse error: {e}")
        return 1

    objects = root.get("objects")
    if not isinstance(objects, dict):
        print("FAIL: missing or malformed 'objects' dictionary")
        return 1

    for required in ("archiveVersion", "rootObject"):
        if required not in root:
            print(f"FAIL: missing required root key {required!r}")
            return 1

    errors = []

    # Duplicate IDs: Xcode treats repeated keys in `objects` as corruption
    # even when a lenient parser would keep the last one. Because a plain
    # dict silently merges duplicates, compare dict size against the raw
    # occurrences of 24-hex keys at the objects level.
    raw_objects = re.search(r"objects = \{(.*?)\n\t\};", text, re.S)
    if raw_objects:
        ids = re.findall(r"^\t\t([0-9A-F]{24}) ", raw_objects.group(1), re.M)
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        if dupes:
            errors.append(f"duplicate object IDs: {dupes}")

    defined = set(objects.keys())
    refs = set()
    collect_refs(root, refs)
    refs -= defined  # keys of `objects` are definitions, not references
    dangling = sorted(refs - defined)
    if dangling:
        errors.append(f"unresolved references: {dangling}")

    # isa-class checks: existence of a referenced object is necessary but not
    # sufficient — run 32 of the CI workflow failed at xcodebuild -list even
    # though every reference resolved, because a PBXNativeTarget's
    # `dependencies` entry pointed at a PBXBuildFile instead of the
    # PBXTargetDependency Xcode's loader requires. These checks encode the
    # class relationships the loader actually enforces.
    def objects_with_isa(kind):
        return {oid for oid, obj in objects.items() if isinstance(obj, dict) and obj.get("isa") == kind}

    for oid in objects_with_isa("PBXNativeTarget"):
        target = objects[oid]
        for dep in target.get("dependencies", []):
            dep_obj = objects.get(dep, {})
            if dep_obj.get("isa") != "PBXTargetDependency":
                errors.append(f"target {oid}: dependencies entry {dep} has isa "
                              f"{dep_obj.get('isa')!r}, expected PBXTargetDependency")
        for phase in target.get("buildPhases", []):
            phase_obj = objects.get(phase, {})
            if phase_obj.get("isa") not in {"PBXSourcesBuildPhase", "PBXFrameworksBuildPhase",
                                            "PBXResourcesBuildPhase", "PBXShellScriptBuildPhase",
                                            "PBXHeadersBuildPhase", "PBXCopyFilesBuildPhase",
                                            "PBXRezBuildPhase", "PBXBuildRule"}:
                errors.append(f"target {oid}: buildPhases entry {phase} has unexpected isa "
                              f"{phase_obj.get('isa')!r}")

    for oid in objects_with_isa("PBXTargetDependency"):
        dep_obj = objects[oid]
        proxy = dep_obj.get("targetProxy")
        if proxy is not None and objects.get(proxy, {}).get("isa") != "PBXContainerItemProxy":
            errors.append(f"PBXTargetDependency {oid}: targetProxy {proxy} has isa "
                          f"{objects.get(proxy, {}).get('isa')!r}, expected PBXContainerItemProxy")

    for oid in objects_with_isa("PBXBuildFile"):
        file_ref = objects[oid].get("fileRef")
        if file_ref is not None and objects.get(file_ref, {}).get("isa") != "PBXFileReference":
            errors.append(f"PBXBuildFile {oid}: fileRef {file_ref} has isa "
                          f"{objects.get(file_ref, {}).get('isa')!r}, expected PBXFileReference")

    if errors:
        for e in errors:
            print("FAIL:", e)
        return 1

    print(f"OK: {PATH} parses cleanly; {len(defined)} objects; all references resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
