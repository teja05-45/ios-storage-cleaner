#!/usr/bin/env python3
"""
Generates Reclaim.xcodeproj/project.pbxproj programmatically.

Parseability contract: CoreFoundation's OpenStep plist parser only treats
[A-Za-z0-9_$+/:.-] atoms as bare (unquoted) strings — Xcode quotes any path
outside that set, and so does this generator via pbx_atom(). A missing entry
semicolon is also fatal (Xcode refuses the whole file), which is why every
emitted line ends with ';' and why scripts/validate_pbxproj.py parses the
result with the strict grammar before it is committed.

Written this way deliberately: hand-authoring ~50 file entries' worth of
PBXFileReference/PBXBuildFile/PBXGroup UUIDs by typing is exactly the kind
of task where a single typo produces a project Xcode silently can't open
correctly. A generator with deterministic, hash-derived UUIDs removes that
class of risk. This script's OUTPUT (the .pbxproj) is the deliverable;
this script itself is a build tool, not part of the app.

Run from anywhere; always operates on the repository root (the directory
containing this script's 'scripts/' folder) and always writes to
<repo-root>/Reclaim.xcodeproj/project.pbxproj.

Fail-loud contract: if zero Swift files are found in Reclaim/ or
ReclaimTests/, the script exits non-zero instead of silently emitting an
empty project (a silent empty project previously went unnoticed and
invalidated the 'regenerate to verify' story).

STILL UNVERIFIED: no Xcode was available to open the result and confirm it
loads. This is disclosed explicitly in the README and Document 15.
"""
import hashlib
import os
import sys

# This file lives in <repo-root>/scripts/, so the repo root is one level up
# from the script's own directory. (Previously this resolved to scripts/,
# which made the generator walk zero source files and write a stray project
# into scripts/.)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_SRC_DIR = os.path.join(ROOT, "Reclaim")
TEST_SRC_DIR = os.path.join(ROOT, "ReclaimTests")
PROJECT_NAME = "Reclaim"


def uuid_for(key: str) -> str:
    """Deterministic 24-hex-char UUID in Xcode's PBX style."""
    h = hashlib.md5(key.encode("utf-8")).hexdigest().upper()
    return h[:24]


def pbx_atom(value: str) -> str:
    """Quote a plist string unless it is a bare CoreFoundation atom.

    CoreFoundation's OpenStep parser accepts unquoted keys/values only in
    [A-Za-z0-9_$+/:.-]. Anything else (spaces, plus signs in the middle of
    a name like 'FileManager+Storage.swift', non-ASCII, etc.) must be
    double-quoted. Xcode emits quotes for such paths; so does this
    generator.
    """
    import re

    if re.fullmatch(r"[A-Za-z0-9_$/:.-]+", value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def pbx_atom_comment(value: str) -> str:
    """Comment text after /* */ is prose, not an atom: only '*/' can break it."""
    return value.replace("*/", "* /")


def collect_swift_files(base_dir):
    """Returns list of (abs_path, rel_path_from_base, folder_rel_path)."""
    results = []
    for dirpath, _dirnames, filenames in os.walk(base_dir):
        for f in sorted(filenames):
            if f.endswith(".swift"):
                abs_path = os.path.join(dirpath, f)
                rel_from_base = os.path.relpath(abs_path, base_dir)
                results.append((abs_path, rel_from_base))
    return sorted(results, key=lambda t: t[1])


app_files = collect_swift_files(APP_SRC_DIR)
test_files = collect_swift_files(TEST_SRC_DIR)
info_plist_rel = "Resources/Info.plist"

# The asset catalog must live in the Resources COPY phase (unlike Info.plist,
# which Xcode processes via INFOPLIST_FILE): actool compiles Assets.xcassets
# into Assets.car at build time, and that only happens for catalogs listed in
# the Resources build phase. Without it the app ships with no icon and no
# accent color despite ASSETCATALOG_COMPILER_APPICON_NAME being set.
asset_catalog_rel = os.path.join("Resources", "Assets.xcassets")
asset_catalog_abs = os.path.join(APP_SRC_DIR, asset_catalog_rel)
has_asset_catalog = os.path.isdir(asset_catalog_abs)

if not app_files:
    sys.exit(
        f"ERROR: no Swift sources found under {APP_SRC_DIR}. "
        "Refusing to generate an empty project. Run this script from the "
        "repository checkout (the folder that contains Reclaim/)."
    )
if not test_files:
    sys.exit(
        f"ERROR: no Swift test sources found under {TEST_SRC_DIR}. "
        "Refusing to generate a project with an empty test target."
    )

# --- Build group tree (mirrors folder structure) ---

class Group:
    def __init__(self, name, path_key):
        self.name = name
        self.uuid = uuid_for("group:" + path_key)
        self.children_groups = {}  # name -> Group
        self.file_refs = []  # list of (uuid, name)

def build_tree(files, root_name, key_prefix):
    root = Group(root_name, key_prefix)
    for abs_path, rel_from_base in files:
        parts = rel_from_base.split(os.sep)
        folders, filename = parts[:-1], parts[-1]
        node = root
        accumulated_key = key_prefix
        for folder in folders:
            accumulated_key += "/" + folder
            if folder not in node.children_groups:
                node.children_groups[folder] = Group(folder, accumulated_key)
            node = node.children_groups[folder]
        file_key = key_prefix + "/" + rel_from_base
        file_uuid = uuid_for("fileref:" + file_key)
        node.file_refs.append((file_uuid, filename, rel_from_base))
    return root

app_tree = build_tree(app_files, PROJECT_NAME, PROJECT_NAME)
test_tree = build_tree(test_files, "ReclaimTests", "ReclaimTests")

# --- Emit PBX text ---

file_ref_lines = []
build_file_lines_app = []
build_file_lines_test = []
group_lines = []
all_app_source_build_uuids = []
all_test_source_build_uuids = []

def emit_group(group: Group, is_test_tree: bool):
    child_entries = []
    for folder_name in sorted(group.children_groups.keys()):
        child = group.children_groups[folder_name]
        emit_group(child, is_test_tree)
        child_entries.append(f'\t\t\t\t{child.uuid} /* {pbx_atom_comment(child.name)} */,')
    for (file_uuid, filename, rel_from_base) in sorted(group.file_refs, key=lambda x: x[1]):
        file_ref_lines.append(
            f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {pbx_atom(filename)}; sourceTree = "<group>"; }};'
        )
        build_uuid = uuid_for("buildfile:" + rel_from_base + (":test" if is_test_tree else ":app"))
        build_line = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        if is_test_tree:
            build_file_lines_test.append(build_line)
            all_test_source_build_uuids.append((build_uuid, filename))
        else:
            build_file_lines_app.append(build_line)
            all_app_source_build_uuids.append((build_uuid, filename))
        child_entries.append(f'\t\t\t\t{file_uuid} /* {filename} */,')

    group_lines.append(f'\t\t{group.uuid} /* {group.name} */ = {{')
    group_lines.append('\t\t\tisa = PBXGroup;')
    group_lines.append('\t\t\tchildren = (')
    for entry in child_entries:
        group_lines.append(entry)
    group_lines.append('\t\t\t);')
    group_lines.append(f'\t\t\tpath = {group.name};')
    group_lines.append('\t\t\tsourceTree = "<group>";')
    group_lines.append('\t\t};')

emit_group(app_tree, is_test_tree=False)
emit_group(test_tree, is_test_tree=True)

# Info.plist file reference. NOTE: the Info.plist is NOT included in the
# Resources copy phase — Xcode processes INFOPLIST_FILE at build time and
# copies the processed plist into the bundle itself; adding it to the
# Resources phase as well produces an IBTOOL/plist duplicate-output
# warning at build time. It is referenced by the project navigator only.

# Info.plist file reference (project navigator entry, not a copied resource)
info_plist_uuid = uuid_for("fileref:Info.plist")
file_ref_lines.append(
    f'\t\t{info_plist_uuid} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};'
)

# Asset catalog file reference. Unlike Info.plist, the catalog IS a copied
# resource (actool compiles it to Assets.car during the Resources phase).
asset_catalog_uuid = uuid_for("fileref:Assets.xcassets")
file_ref_lines.append(
    f'\t\t{asset_catalog_uuid} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};'
)
asset_catalog_build_uuid = uuid_for("buildfile:Assets.xcassets")

# App product + test product
app_product_uuid = uuid_for("product:Reclaim.app")
test_product_uuid = uuid_for("product:ReclaimTests.xctest")
file_ref_lines.append(
    f'\t\t{app_product_uuid} /* Reclaim.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Reclaim.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
)
file_ref_lines.append(
    f'\t\t{test_product_uuid} /* ReclaimTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ReclaimTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};'
)

# Top-level groups
main_group_uuid = uuid_for("group:MAIN")
products_group_uuid = uuid_for("group:PRODUCTS")
resources_ref_group_uuid = uuid_for("group:Resources-toplevel")

resources_group_children = [
    f'\t\t\t\t{info_plist_uuid} /* Info.plist */,',
]
if has_asset_catalog:
    resources_group_children.append(
        f'\t\t\t\t{asset_catalog_uuid} /* Assets.xcassets */,'
    )

resources_group_lines = [
    f'\t\t{resources_ref_group_uuid} /* Resources */ = {{',
    '\t\t\tisa = PBXGroup;',
    '\t\t\tchildren = (',
    *resources_group_children,
    '\t\t\t);',
    '\t\t\tname = Resources;',
    '\t\t\tpath = Reclaim/Resources;',
    '\t\t\tsourceTree = "<group>";',
    '\t\t};',
]

products_group_lines = [
    f'\t\t{products_group_uuid} /* Products */ = {{',
    '\t\t\tisa = PBXGroup;',
    '\t\t\tchildren = (',
    f'\t\t\t\t{app_product_uuid} /* Reclaim.app */,',
    f'\t\t\t\t{test_product_uuid} /* ReclaimTests.xctest */,',
    '\t\t\t);',
    '\t\t\tname = Products;',
    '\t\t\tsourceTree = "<group>";',
    '\t\t};',
]


main_group_children = [
    f'\t\t\t\t{app_tree.uuid} /* {app_tree.name} */,',
    f'\t\t\t\t{resources_ref_group_uuid} /* Resources */,',
    f'\t\t\t\t{test_tree.uuid} /* ReclaimTests */,',
    f'\t\t\t\t{products_group_uuid} /* Products */,',
]

main_group_lines = [
    f'\t\t{main_group_uuid} = {{',
    '\t\t\tisa = PBXGroup;',
    '\t\t\tchildren = (',
]
main_group_lines += main_group_children
main_group_lines += [
    '\t\t\t);',
    '\t\t\tsourceTree = "<group>";',
    '\t\t};',
]

# --- Targets ---
app_target_uuid = uuid_for("target:Reclaim")
test_target_uuid = uuid_for("target:ReclaimTests")

app_sources_phase_uuid = uuid_for("phase:app-sources")
app_frameworks_phase_uuid = uuid_for("phase:app-frameworks")
app_resources_phase_uuid = uuid_for("phase:app-resources")
test_sources_phase_uuid = uuid_for("phase:test-sources")
test_frameworks_phase_uuid = uuid_for("phase:test-frameworks")

test_dependency_uuid = uuid_for("dependency:test-on-app")
test_target_proxy_uuid = uuid_for("proxy:test-on-app")

app_debug_config_uuid = uuid_for("config:app-debug")
app_release_config_uuid = uuid_for("config:app-release")
test_debug_config_uuid = uuid_for("config:test-debug")
test_release_config_uuid = uuid_for("config:test-release")
project_debug_config_uuid = uuid_for("config:project-debug")
project_release_config_uuid = uuid_for("config:project-release")
app_config_list_uuid = uuid_for("configlist:app")
test_config_list_uuid = uuid_for("configlist:test")
project_config_list_uuid = uuid_for("configlist:project")

project_uuid = uuid_for("project:root")

app_sources_build_phase_lines = "\n".join(
    f'\t\t\t\t{u} /* {n} in Sources */,' for (u, n) in all_app_source_build_uuids
)
test_sources_build_phase_lines = "\n".join(
    f'\t\t\t\t{u} /* {n} in Sources */,' for (u, n) in all_test_source_build_uuids
)

# Info.plist: intentionally NOT in the Resources copy phase (see the note
# above its file reference) — Xcode copies the processed INFOPLIST_FILE into
# the bundle itself. The asset catalog, however, MUST be in the Resources
# phase for actool to compile it (see the note above its file reference).
resources_phase_line = (
    f'\t\t\t\t{asset_catalog_build_uuid} /* Assets.xcassets in Resources */,'
    if has_asset_catalog
    else ""
)

# The catalog's PBXBuildFile entry, empty when there is no catalog so the
# PBXBuildFile section stays syntactically valid either way.
asset_catalog_buildfile_line = (
    f'\n\t\t{asset_catalog_build_uuid} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_catalog_uuid} /* Assets.xcassets */; }};'
    if has_asset_catalog
    else ""
)

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_lines_app)}
{chr(10).join(build_file_lines_test)}{asset_catalog_buildfile_line}
\t\t{test_dependency_uuid} /* Reclaim.app in Frameworks */ = {{isa = PBXBuildFile; fileRef = {app_product_uuid} /* Reclaim.app */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{test_target_proxy_uuid} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_uuid} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {app_target_uuid};
\t\t\tremoteInfo = Reclaim;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{app_frameworks_phase_uuid} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_frameworks_phase_uuid} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{test_dependency_uuid} /* Reclaim.app in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_lines)}
{chr(10).join(resources_group_lines)}
{chr(10).join(products_group_lines)}
{chr(10).join(main_group_lines)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{app_target_uuid} /* Reclaim */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {app_config_list_uuid} /* Build configuration list for PBXNativeTarget "Reclaim" */;
\t\t\tbuildPhases = (
\t\t\t\t{app_sources_phase_uuid} /* Sources */,
\t\t\t\t{app_frameworks_phase_uuid} /* Frameworks */,
\t\t\t\t{app_resources_phase_uuid} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Reclaim;
\t\t\tproductName = Reclaim;
\t\t\tproductReference = {app_product_uuid} /* Reclaim.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{test_target_uuid} /* ReclaimTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {test_config_list_uuid} /* Build configuration list for PBXNativeTarget "ReclaimTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{test_sources_phase_uuid} /* Sources */,
\t\t\t\t{test_frameworks_phase_uuid} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{uuid_for("targetdep:test-on-app")} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = ReclaimTests;
\t\t\tproductName = ReclaimTests;
\t\t\tproductReference = {test_product_uuid} /* ReclaimTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_uuid} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1520;
\t\t\t\tLastUpgradeCheck = 1520;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{app_target_uuid} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t}};
\t\t\t\t\t{test_target_uuid} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t\tTestTargetID = {app_target_uuid};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list_uuid} /* Build configuration list for PBXProject "Reclaim" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_uuid};
\t\t\tproductRefGroup = {products_group_uuid} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{app_target_uuid} /* Reclaim */,
\t\t\t\t{test_target_uuid} /* ReclaimTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{app_resources_phase_uuid} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resources_phase_line}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{app_sources_phase_uuid} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_sources_build_phase_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_sources_phase_uuid} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_sources_build_phase_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{uuid_for("targetdep:test-on-app")} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {app_target_uuid} /* Reclaim */;
\t\t\ttargetProxy = {test_target_proxy_uuid} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{project_debug_config_uuid} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{project_release_config_uuid} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{app_debug_config_uuid} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Reclaim/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = NO;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.reclaim.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{app_release_config_uuid} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Reclaim/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = NO;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.reclaim.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{test_debug_config_uuid} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.reclaim.app.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Reclaim.app/Reclaim";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{test_release_config_uuid} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.reclaim.app.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Reclaim.app/Reclaim";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_config_list_uuid} /* Build configuration list for PBXProject "Reclaim" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug_config_uuid} /* Debug */,
\t\t\t\t{project_release_config_uuid} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{app_config_list_uuid} /* Build configuration list for PBXNativeTarget "Reclaim" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{app_debug_config_uuid} /* Debug */,
\t\t\t\t{app_release_config_uuid} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{test_config_list_uuid} /* Build configuration list for PBXNativeTarget "ReclaimTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{test_debug_config_uuid} /* Debug */,
\t\t\t\t{test_release_config_uuid} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_uuid} /* Project object */;
}}
"""

os.makedirs(os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj"), exist_ok=True)
out_path = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj", "project.pbxproj")
with open(out_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(pbxproj)

# The bundle needs more than project.pbxproj to look like a project Xcode
# made: the workspace metadata and a shared scheme (checked in, so
# xcodebuild -scheme Reclaim is deterministic and does not depend on
# headless scheme auto-creation).
ws_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj", "project.xcworkspace")
os.makedirs(ws_dir, exist_ok=True)
with open(os.path.join(ws_dir, "contents.xcworkspacedata"), "w", encoding="utf-8", newline="\n") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<Workspace\n'
            '   version = "1.0">\n'
            '   <FileRef\n'
            '      location = "self:">\n'
            '   </FileRef>\n'
            '</Workspace>\n')

schemes_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj", "xcshareddata", "xcschemes")
os.makedirs(schemes_dir, exist_ok=True)
with open(os.path.join(schemes_dir, f"{PROJECT_NAME}.xcscheme"), "w", encoding="utf-8", newline="\n") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target_uuid}"
               BuildableName = "Reclaim.app"
               BlueprintName = "Reclaim"
               ReferencedContainer = "container:Reclaim.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_uuid}"
               BuildableName = "ReclaimTests.xctest"
               BlueprintName = "ReclaimTests"
               ReferencedContainer = "container:Reclaim.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_uuid}"
            BuildableName = "Reclaim.app"
            BlueprintName = "Reclaim"
            ReferencedContainer = "container:Reclaim.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES"
      runnableDebuggingMode = "0">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_uuid}"
            BuildableName = "Reclaim.app"
            BlueprintName = "Reclaim"
            ReferencedContainer = "container:Reclaim.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')

print(f"Wrote {out_path}")
print(f"App files: {len(app_files)}, Test files: {len(test_files)}")
