import os
import re
import csv
import sys
import json
import shutil
import argparse
from pathlib import Path

try:
    import win32com.client
except ImportError:
    print("Missing dependency. Run:  pip install pywin32")
    sys.exit(1)


DEFAULT_FOLDER = r"PATH\TO\FILE"
DEFAULT_OUTPUT = r"PATH\TO\FILE\game_results.csv"
GAME_EXTENSIONS = {".exe", ".lnk", ".url", ".desktop"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def format_bytes(num_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num_bytes < 1024:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.2f} PB"


def resolve_lnk(lnk_path: Path) -> Path | None:
    """Resolve a .lnk shortcut to its target path."""
    try:
        shell  = win32com.client.Dispatch("WScript.Shell")
        link   = shell.CreateShortcut(str(lnk_path))
        target = link.TargetPath
        if target:
            return Path(target)
    except Exception:
        pass
    return None


def resolve_url(url_path: Path) -> Path | None:
    """Parse a .url shortcut file for a local file:// target."""
    try:
        with open(url_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.lower().startswith("url=file:///"):
                    local = line[len("url=file:///"):].replace("/", "\\")
                    return Path(local)
    except Exception:
        pass
    return None


def folder_size(path: Path) -> int:
    total = 0
    try:
        for dirpath, _dirs, files in os.walk(path):
            for f in files:
                try:
                    total += (Path(dirpath) / f).stat().st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total


def drive_used(path: Path) -> str:
    """Return how much space is used on the drive the path lives on."""
    try:
        usage = shutil.disk_usage(path)
        return format_bytes(usage.used)
    except OSError:
        return "N/A"


def clean_game_name(name: str) -> str:
    name = Path(name).stem if "." in name else name
    noise = re.compile(
        r"\b(setup|install|launcher|v\d[\d.]*|x64|x86|64bit|32bit|"
        r"\d{4,}|retail|gog|steam|epic|itch|repack|crack|codex|gog[\-_]rip|"
        r"windows|win\d*|pc)\b",
        re.IGNORECASE,
    )
    name = noise.sub(" ", name)
    name = re.sub(r"[_\-\.]+", " ", name)
    name = re.sub(r"\s{2,}", " ", name).strip()
    return name

def scan_folder(root: Path) -> list[dict]:
    entries = []

    try:
        children = sorted(root.iterdir())
    except OSError as e:
        print(f"Cannot read folder: {e}")
        sys.exit(1)

    for child in children:
        # --- Subfolders: the game IS here ---
        if child.is_dir():
            install_path = child
            game_name    = clean_game_name(child.name)
            primary_exe  = find_primary_exe(install_path)

        # --- Shortcut / .lnk: resolve to actual install ---
        elif child.is_file() and child.suffix.lower() == ".lnk":
            target = resolve_lnk(child)
            if not target or not target.exists():
                print(f"  [!] Could not resolve: {child.name}")
                continue
            install_path = target if target.is_dir() else target.parent
            game_name    = clean_game_name(child.name)
            primary_exe  = str(target) if target.is_file() else find_primary_exe(install_path)

        # --- .url shortcut ---
        elif child.is_file() and child.suffix.lower() == ".url":
            target = resolve_url(child)
            if not target or not target.exists():
                print(f"  [!] Could not resolve: {child.name}")
                continue
            install_path = target if target.is_dir() else target.parent
            game_name    = clean_game_name(child.name)
            primary_exe  = str(target) if target.is_file() else find_primary_exe(install_path)

        # --- Bare .exe sitting in root ---
        elif child.is_file() and child.suffix.lower() == ".exe":
            install_path = child.parent
            game_name    = clean_game_name(child.name)
            primary_exe  = str(child)

        else:
            continue

        size_bytes  = folder_size(install_path) if install_path.is_dir() else install_path.stat().st_size
        drive       = str(Path(install_path.anchor))
        drive_space = drive_used(install_path)

        entries.append({
            "game_name":        game_name,
            "install_location": str(install_path),
            "primary_exe":      primary_exe,
            "install_size":     format_bytes(size_bytes),
            "drive":            drive,
            "drive_used":       drive_space,
        })

    return entries


def find_primary_exe(folder: Path) -> str:
    """Find the most likely main executable in a folder (shallowest path)."""
    candidates = [
        str(Path(dp) / f)
        for dp, _, files in os.walk(folder)
        for f in files
        if Path(f).suffix.lower() == ".exe"
    ]
    return min(candidates, key=len) if candidates else "N/A"

def print_report(entries: list[dict]):
    sep = "─" * 72
    for e in entries:
        print(sep)
        print(f"  Game             : {e['game_name']}")
        print(f"  Install location : {e['install_location']}")
        print(f"  Primary exe      : {e['primary_exe']}")
        print(f"  Install size     : {e['install_size']}")
        print(f"  Drive            : {e['drive']}  (used: {e['drive_used']})")
    print(sep)
    print(f"\n  Total games: {len(entries)}")


def write_csv(entries: list[dict], output_path: str):
    fieldnames = [
        "game_name", "install_location", "primary_exe",
        "install_size", "drive", "drive_used",
    ]
    with open(output_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(entries)
    print(f"\n  CSV saved → {output_path}")


def write_json(entries: list[dict], output_path: str):
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(entries, fh, indent=2, ensure_ascii=False)
    print(f"  JSON saved → {output_path}")

def main():
    parser = argparse.ArgumentParser(
        description="Scan games folder, resolve shortcuts, log install paths and sizes."
    )
    parser.add_argument("folder",   nargs="?", default=DEFAULT_FOLDER)
    parser.add_argument("--output", "-o",      default=DEFAULT_OUTPUT)
    parser.add_argument("--json",   "-j",      action="store_true")
    args = parser.parse_args()

    folder = Path(args.folder)
    if not folder.exists():
        print(f"\nError: folder not found: {folder}")
        sys.exit(1)

    print(f"\nScanning: {folder}\n")
    entries = scan_folder(folder)

    if not entries:
        print("No games found.")
        sys.exit(0)

    print_report(entries)
    write_csv(entries, args.output)

    if args.json:
        write_json(entries, args.output.replace(".csv", ".json"))


if __name__ == "__main__":
    main()
