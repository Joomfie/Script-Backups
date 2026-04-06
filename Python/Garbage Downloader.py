"""
yt-dlp Batch Downloader
=======================
Reads URLs from List.txt, downloads with Firefox cookies,
moves files through a processing stage, logs errors, and
sleeps between downloads to avoid rate limiting.

Requirements:
    - Python 3.10+
    - yt-dlp installed and available on system PATH
    - Firefox installed with an active logged-in session
"""

import subprocess
import sys
import os
import shutil
import time
import datetime


# ==============================================================
#  CONFIGURATION
#  Fill in the paths below before running the script.
# ==============================================================

# Folder that contains List.txt.
# Example: r"C:\Users\YourName\Downloads\ytdlp"
BASE_DIR = r""

# Folder where files are staged during download (processing area).
# Example: r"C:\Users\YourName\Downloads\ytdlp\processing"
PROCESSING_DIR = r""

# Folder where completed downloads are moved after finishing.
# Example: r"C:\Users\YourName\Downloads\ytdlp\output"
OUTPUT_DIR = r""

# Folder where error logs are written.
# Example: r"C:\Users\YourName\Downloads\ytdlp\logs"
LOG_DIR = r""

# Seconds to wait between each successful download.
SLEEP_BETWEEN = 15

# Seconds to wait after a failed download before continuing.
SLEEP_ON_ERROR = 30

# ==============================================================
#  END CONFIGURATION
# ==============================================================


LIST_FILE       = os.path.join(BASE_DIR, "List.txt")
OUTPUT_TEMPLATE = os.path.join(PROCESSING_DIR, "%(title)s.%(ext)s")


def validate_config() -> None:
    """Exit early with a clear message if any config path was left blank."""
    fields = {
        "BASE_DIR":       BASE_DIR,
        "PROCESSING_DIR": PROCESSING_DIR,
        "OUTPUT_DIR":     OUTPUT_DIR,
        "LOG_DIR":        LOG_DIR,
    }
    missing = [name for name, val in fields.items() if not val.strip()]
    if missing:
        print("ERROR: The following paths have not been set in the CONFIGURATION block:")
        for name in missing:
            print(f"  {name}")
        print("Open the script and fill in the missing paths before running.")
        sys.exit(1)


def ensure_dirs() -> None:
    """Create working directories if they do not already exist."""
    for d in (PROCESSING_DIR, OUTPUT_DIR, LOG_DIR):
        os.makedirs(d, exist_ok=True)


def log_error(url: str, message: str) -> None:
    """Append an error entry to the daily error log."""
    today     = datetime.date.today().strftime("%Y-%m-%d")
    log_path  = os.path.join(LOG_DIR, f"errors_{today}.log")
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] URL: {url}\n{message}\n{'-' * 60}\n")
    print(f"Error logged: {log_path}")


def check_and_update_ytdlp() -> None:
    """
    Run 'yt-dlp -U'. If an update is available it will be downloaded
    and installed automatically. If already up to date, nothing changes
    and the script continues normally.
    """
    print("-" * 60)
    print("Checking for yt-dlp updates...")
    print("-" * 60)
    result = subprocess.run(["yt-dlp", "-U"], text=True)
    if result.returncode != 0:
        print("WARNING: yt-dlp update check returned a non-zero exit code.")
        print("Continuing with the existing installation.")
    print()


def load_urls(list_file: str) -> list[str]:
    """Read URLs from List.txt, skipping blank lines and comment lines."""
    if not os.path.isfile(list_file):
        print(f"ERROR: List file not found: {list_file}")
        sys.exit(1)

    urls = []
    with open(list_file, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line and not line.startswith("#"):
                urls.append(line)

    if not urls:
        print("List.txt contains no URLs. Nothing to do.")
        sys.exit(0)

    return urls


def move_to_output() -> list[str]:
    """
    Move every completed file from PROCESSING_DIR into OUTPUT_DIR.
    If a filename already exists in the output folder, a counter is
    appended to avoid overwriting.
    Returns a list of the filenames that were moved.
    """
    moved = []
    for fname in os.listdir(PROCESSING_DIR):
        src  = os.path.join(PROCESSING_DIR, fname)
        dest = os.path.join(OUTPUT_DIR, fname)
        if os.path.isfile(src):
            base, ext = os.path.splitext(fname)
            counter   = 1
            while os.path.exists(dest):
                dest    = os.path.join(OUTPUT_DIR, f"{base}_{counter}{ext}")
                counter += 1
            shutil.move(src, dest)
            moved.append(os.path.basename(dest))
    return moved


def download(url: str, index: int, total: int) -> bool:
    """
    Invoke yt-dlp for a single URL.
    Progress is streamed directly to the terminal.
    Returns True on success, False on failure.
    """
    print()
    print("-" * 60)
    print(f"[{index}/{total}] {url}")
    print("-" * 60)

    cmd = [
        "yt-dlp",
        "--cookies-from-browser", "firefox",
        "--output",               OUTPUT_TEMPLATE,
        "--newline",
        "--no-part",
        url,
    ]

    try:
        result = subprocess.run(cmd, text=True)
        if result.returncode == 0:
            print("Download finished.")
            return True
        else:
            msg = f"yt-dlp exited with code {result.returncode}"
            print(f"Download failed: {msg}")
            log_error(url, msg)
            return False

    except FileNotFoundError:
        msg = "yt-dlp executable not found. Confirm it is installed and on PATH."
        print(f"ERROR: {msg}")
        log_error(url, msg)
        return False
    except Exception as exc:
        msg = str(exc)
        print(f"ERROR: {msg}")
        log_error(url, msg)
        return False


def main() -> None:
    validate_config()
    ensure_dirs()

    print()
    print("-" * 60)
    print("yt-dlp Batch Downloader")
    print("-" * 60)

    check_and_update_ytdlp()

    urls  = load_urls(LIST_FILE)
    total = len(urls)
    print(f"Found {total} URL(s) in {LIST_FILE}")

    success_count = 0
    fail_count    = 0

    for idx, url in enumerate(urls, start=1):
        ok = download(url, idx, total)

        if ok:
            moved = move_to_output()
            if moved:
                print(f"Moved to output: {', '.join(moved)}")
            success_count += 1
        else:
            fail_count += 1

        if idx < total:
            pause = SLEEP_BETWEEN if ok else SLEEP_ON_ERROR
            print(f"Sleeping {pause}s before next download...")
            time.sleep(pause)

    print()
    print("-" * 60)
    print(f"Done. {success_count} succeeded, {fail_count} failed.")
    if fail_count:
        today    = datetime.date.today().strftime("%Y-%m-%d")
        log_path = os.path.join(LOG_DIR, f"errors_{today}.log")
        print(f"See error log: {log_path}")
    print("-" * 60)


if __name__ == "__main__":
    main()
