"""
EXE Link Scanner
================
Scans a folder of .lnk shortcut files pointing to .exe files,
then checks D:\, E:\, and F:\ for exe-containing folders that
have NO corresponding shortcut in your links folder.

Requirements:
    pip install pywin32

Usage:
    python exe_link_scanner.py --links "C:\Users\You\Links"
    python exe_link_scanner.py --links "C:\Users\You\Links" --depth 3 --output report.txt
    python exe_link_scanner.py --links "C:\Users\You\Links" --csv missing.csv
"""

import os
import sys
import argparse
import csv
import datetime

# pywin32 is required to resolve Windows .lnk shortcut files
try:
    import win32com.client
    SHELL_AVAILABLE = True
except ImportError:
    SHELL_AVAILABLE = False


# ──────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────

DRIVES_TO_SCAN = ["D:\\", "E:\\", "F:\\"]

# Folders to skip entirely (system/noise directories)
SKIP_DIRS = {
    "$recycle.bin", "system volume information", "windows",
    "programdata", "$winretools", "$windows.~bt", "$windows.~ws",
    "recovery", "boot", "efi"
}

# How deep to recurse into each drive when looking for .exe files
DEFAULT_SCAN_DEPTH = 4


# ──────────────────────────────────────────────
# SHORTCUT RESOLUTION
# ──────────────────────────────────────────────

def resolve_lnk(lnk_path: str) -> str | None:
    """Return the target path of a .lnk file, or None on failure."""
    if not SHELL_AVAILABLE:
        return None
    try:
        shell = win32com.client.Dispatch("WScript.Shell")
        shortcut = shell.CreateShortcut(lnk_path)
        target = shortcut.TargetPath
        return target if target else None
    except Exception:
        return None


def load_links_folder(links_folder: str) -> dict[str, str]:
    """
    Walk the links folder and resolve every .lnk → target exe.

    Returns:
        {shortcut_name: resolved_exe_path}
        Only entries where the target ends in .exe are included.
    """
    results = {}
    if not os.path.isdir(links_folder):
        print(f"[ERROR] Links folder not found: {links_folder}")
        sys.exit(1)

    for entry in os.scandir(links_folder):
        if entry.is_file() and entry.name.lower().endswith(".lnk"):
            target = resolve_lnk(entry.path)
            if target and target.lower().endswith(".exe"):
                results[entry.name] = target

    return results


# ──────────────────────────────────────────────
# DRIVE SCANNING
# ──────────────────────────────────────────────

def scan_drive_for_exe_folders(drive: str, max_depth: int) -> dict[str, list[str]]:
    """
    Walk `drive` up to `max_depth` levels deep.

    Returns:
        {folder_path: [exe_filename, ...]}
        Only folders that contain at least one .exe are included.
    """
    found = {}
    drive = os.path.normpath(drive) + os.sep

    if not os.path.exists(drive):
        return found  # Drive not mounted / doesn't exist

    def _recurse(path: str, depth: int):
        if depth > max_depth:
            return
        try:
            with os.scandir(path) as it:
                exes = []
                subdirs = []
                for entry in it:
                    try:
                        if entry.is_file(follow_symlinks=False) and entry.name.lower().endswith(".exe"):
                            exes.append(entry.name)
                        elif entry.is_dir(follow_symlinks=False):
                            if entry.name.lower() not in SKIP_DIRS:
                                subdirs.append(entry.path)
                    except PermissionError:
                        pass
                if exes:
                    found[path] = exes
                for sub in subdirs:
                    _recurse(sub, depth + 1)
        except PermissionError:
            pass

    _recurse(drive, 0)
    return found


# ──────────────────────────────────────────────
# COMPARISON LOGIC
# ──────────────────────────────────────────────

def analyse(links: dict[str, str], exe_folders: dict[str, list[str]]) -> dict:
    """
    Cross-reference resolved shortcut targets with discovered exe folders.

    Returns a structured report dict.
    """
    # Normalise all resolved shortcut targets to lowercase for comparison
    linked_exe_paths = {os.path.normpath(v).lower() for v in links.values()}
    linked_exe_dirs  = {os.path.dirname(p) for p in linked_exe_paths}

    # Shortcuts whose target exe doesn't actually exist on disk
    broken_shortcuts = {}
    for lnk, target in links.items():
        if not os.path.isfile(target):
            broken_shortcuts[lnk] = target

    # Folders that contain .exe files but have NO shortcut pointing into them
    unlinked_folders = {}
    for folder, exes in exe_folders.items():
        folder_norm = os.path.normpath(folder).lower()
        # Check whether any linked exe lives in this exact folder
        if folder_norm not in linked_exe_dirs:
            unlinked_folders[folder] = exes

    # Shortcuts that DO have a valid, matching folder
    covered_folders = {}
    for folder, exes in exe_folders.items():
        folder_norm = os.path.normpath(folder).lower()
        if folder_norm in linked_exe_dirs:
            covered_folders[folder] = exes

    return {
        "total_shortcuts":      len(links),
        "broken_shortcuts":     broken_shortcuts,
        "total_exe_folders":    len(exe_folders),
        "covered_folders":      covered_folders,
        "unlinked_folders":     unlinked_folders,
    }


# ──────────────────────────────────────────────
# REPORTING
# ──────────────────────────────────────────────

def build_report(links: dict, report: dict, scan_depth: int) -> str:
    lines = []
    sep  = "=" * 70
    sep2 = "-" * 70

    lines.append(sep)
    lines.append("  EXE LINK SCANNER — REPORT")
    lines.append(f"  Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"  Drives scanned: {', '.join(DRIVES_TO_SCAN)}")
    lines.append(f"  Scan depth: {scan_depth}")
    lines.append(sep)

    # ── Summary ──
    lines.append("\n[ SUMMARY ]")
    lines.append(f"  Shortcuts (.lnk) found in links folder : {report['total_shortcuts']}")
    lines.append(f"  Broken shortcuts (target missing)      : {len(report['broken_shortcuts'])}")
    lines.append(f"  Exe-containing folders found on drives : {report['total_exe_folders']}")
    lines.append(f"  Folders COVERED by a shortcut          : {len(report['covered_folders'])}")
    lines.append(f"  Folders NOT covered (no shortcut)      : {len(report['unlinked_folders'])}")

    # ── All shortcuts ──
    lines.append(f"\n{sep2}")
    lines.append("[ ALL SHORTCUTS & THEIR TARGETS ]")
    lines.append(sep2)
    if links:
        for lnk, target in sorted(links.items()):
            status = "OK" if os.path.isfile(target) else "BROKEN"
            lines.append(f"  [{status:6}]  {lnk}")
            lines.append(f"             → {target}")
    else:
        lines.append("  (none found)")

    # ── Broken shortcuts ──
    lines.append(f"\n{sep2}")
    lines.append("[ BROKEN SHORTCUTS — target .exe no longer exists ]")
    lines.append(sep2)
    if report["broken_shortcuts"]:
        for lnk, target in sorted(report["broken_shortcuts"].items()):
            lines.append(f"  {lnk}")
            lines.append(f"    Missing target: {target}")
    else:
        lines.append("  ✓ None — all shortcuts point to existing files.")

    # ── Unlinked folders ──
    lines.append(f"\n{sep2}")
    lines.append("[ UNLINKED FOLDERS — exe files with NO shortcut in your links folder ]")
    lines.append(sep2)
    if report["unlinked_folders"]:
        for folder, exes in sorted(report["unlinked_folders"].items()):
            lines.append(f"  {folder}")
            for exe in sorted(exes):
                lines.append(f"    • {exe}")
    else:
        lines.append("  ✓ None — every exe folder is represented by a shortcut.")

    # ── Covered folders ──
    lines.append(f"\n{sep2}")
    lines.append("[ COVERED FOLDERS — have a matching shortcut ]")
    lines.append(sep2)
    if report["covered_folders"]:
        for folder, exes in sorted(report["covered_folders"].items()):
            lines.append(f"  ✓ {folder}")
    else:
        lines.append("  (none)")

    lines.append(f"\n{sep}")
    lines.append("  END OF REPORT")
    lines.append(sep)

    return "\n".join(lines)


# ──────────────────────────────────────────────
# CSV EXPORT
# ──────────────────────────────────────────────

def write_csv(report: dict, csv_path: str):
    """
    Write two sheets into a single CSV file, separated by a blank row:

    Section 1 — UNLINKED FOLDERS (folders with .exe but no shortcut)
        Drive | Folder Path | EXE Filename | Full EXE Path

    Section 2 — BROKEN SHORTCUTS (.lnk files whose target is missing)
        Shortcut Name | Expected EXE Path
    """
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)

        # ── Section 1: Unlinked folders ──
        writer.writerow([
            "SECTION",
            "Drive",
            "Folder Path",
            "EXE Filename",
            "Full EXE Path"
        ])

        unlinked = report["unlinked_folders"]
        if unlinked:
            for folder, exes in sorted(unlinked.items()):
                drive = os.path.splitdrive(folder)[0] + "\\"
                for exe in sorted(exes):
                    full_path = os.path.join(folder, exe)
                    writer.writerow([
                        "UNLINKED FOLDER",
                        drive,
                        folder,
                        exe,
                        full_path
                    ])
        else:
            writer.writerow(["UNLINKED FOLDER", "", "No unlinked folders found.", "", ""])

        # ── Blank separator row ──
        writer.writerow([])

        # ── Section 2: Broken shortcuts ──
        writer.writerow([
            "SECTION",
            "Shortcut Filename (.lnk)",
            "Expected EXE Path (missing)",
            "",
            ""
        ])

        broken = report["broken_shortcuts"]
        if broken:
            for lnk, target in sorted(broken.items()):
                writer.writerow([
                    "BROKEN SHORTCUT",
                    lnk,
                    target,
                    "",
                    ""
                ])
        else:
            writer.writerow(["BROKEN SHORTCUT", "No broken shortcuts found.", "", "", ""])


# ──────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Scan a links folder and find exe folders with no shortcut."
    )
    parser.add_argument(
        "--links", required=True,
        help='Path to the folder containing your .lnk shortcut files. E.g. "C:\\Users\\You\\AppLinks"'
    )
    parser.add_argument(
        "--depth", type=int, default=DEFAULT_SCAN_DEPTH,
        help=f"How many directory levels deep to scan each drive (default: {DEFAULT_SCAN_DEPTH})"
    )
    parser.add_argument(
        "--output", default=None,
        help="Optional path to write the full report as a .txt file."
    )
    parser.add_argument(
        "--csv", default=None,
        help='Optional path to write missing-folder results as a .csv file. '
             'If omitted, a CSV is auto-saved next to the script as "missing_links_<timestamp>.csv".'
    )
    args = parser.parse_args()

    if not SHELL_AVAILABLE:
        print("[ERROR] pywin32 is not installed. Run:  pip install pywin32")
        sys.exit(1)

    print(f"[1/3] Loading shortcuts from: {args.links}")
    links = load_links_folder(args.links)
    print(f"      Found {len(links)} valid shortcut(s) pointing to .exe files.")

    print(f"[2/3] Scanning drives {DRIVES_TO_SCAN} (depth={args.depth}) …")
    all_exe_folders = {}
    for drive in DRIVES_TO_SCAN:
        print(f"      Scanning {drive} …", end=" ", flush=True)
        folders = scan_drive_for_exe_folders(drive, args.depth)
        print(f"{len(folders)} exe-folder(s) found.")
        all_exe_folders.update(folders)

    print(f"[3/3] Analysing results …")
    report = analyse(links, all_exe_folders)

    output_text = build_report(links, report, args.depth)
    print("\n" + output_text)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_text)
        print(f"\n[SAVED] Report written to: {args.output}")

    # ── CSV output (always generated unless user explicitly passes --csv "") ──
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = args.csv if args.csv else os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        f"missing_links_{timestamp}.csv"
    )
    write_csv(report, csv_path)
    print(f"\n[SAVED] CSV report written to: {csv_path}")
    print(f"        {len(report['unlinked_folders'])} unlinked folder row(s), "
          f"{len(report['broken_shortcuts'])} broken shortcut row(s).")


if __name__ == "__main__":
    main()
