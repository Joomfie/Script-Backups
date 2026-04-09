import shutil
import subprocess
import threading
import time
import logging
from pathlib import Path
from datetime import datetime

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

CONFIG = {
    # Full path to gallery-dl.exe
    "GALLERY_DL_PATH": r"Path\To\gallery-dl.exe",

    # Full path to List.txt — one source URL per line, # to comment a line out
    "LIST_FILE": r"Path\To\List.txt",

    # Temporary processing folders — downloads land here first before being moved.
    # Set any slot to "" or None to disable it; the slot will be skipped entirely.
    "PROCESSING_DIRS": [
        r"Path\To\Folder",
        "",
        None,
    ],

    # Final destination folders — files are moved here after a download finishes.
    # Pairs 1-to-1 with PROCESSING_DIRS. Set to "" or None to leave files in processing.
    "DESTINATION_DIRS": [
        r"Path\To\Folder",
        r"Path\To\Folder",
        r"Path\To\Folder",
        "",
        None,
    ],

    # How many downloads can run at the same time
    "MAX_CONCURRENT_DOWNLOADS": 3,

    # Seconds to wait between starting each download thread
    "DOWNLOAD_STAGGER_DELAY": 2,

    # Flags passed to every gallery-dl call. Cookies are pulled from Firefox automatically.
    "GALLERY_DL_FLAGS": [
        "--cookies-from-browser", "firefox",
        "--write-metadata",
        "--no-mtime",
    ],

    # Log file path. Set to None to print to console only.
    "LOG_FILE": r"Path\To\scraper.log",
}

# ─────────────────────────────────────────────────────────────────────────────
#  END CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

def setup_logging():
    handlers = [logging.StreamHandler()]
    if CONFIG["LOG_FILE"]:
        Path(CONFIG["LOG_FILE"]).parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(CONFIG["LOG_FILE"], encoding="utf-8"))
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=handlers,
    )

log = logging.getLogger(__name__)


def check_for_updates():
    log.info("=" * 60)
    log.info("Checking for gallery-dl updates...")
    gdl = CONFIG["GALLERY_DL_PATH"]

    if not Path(gdl).is_file():
        log.error(f"gallery-dl not found at: {gdl}")
        raise FileNotFoundError(f"gallery-dl not found: {gdl}")

    try:
        result = subprocess.run(
            [gdl, "--update"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        output = (result.stdout + result.stderr).strip()
        if output:
            for line in output.splitlines():
                log.info(f"  [update] {line}")
        log.info("Update check complete.")
    except subprocess.TimeoutExpired:
        log.warning("Update check timed out — continuing.")
    except Exception as exc:
        log.warning(f"Update check failed: {exc} — continuing.")

    log.info("=" * 60)


def load_sources():
    list_file = Path(CONFIG["LIST_FILE"])
    if not list_file.is_file():
        log.error(f"List file not found: {list_file}")
        raise FileNotFoundError(f"List file not found: {list_file}")

    sources = []
    with list_file.open(encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line and not line.startswith("#"):
                sources.append(line)

    log.info(f"Loaded {len(sources)} source(s) from {list_file}")
    return sources


def get_active_slots():
    slots = []
    proc_dirs = CONFIG["PROCESSING_DIRS"]
    dest_dirs = CONFIG["DESTINATION_DIRS"]

    for i, proc in enumerate(proc_dirs):
        if not proc:
            continue

        proc_path = Path(proc)
        proc_path.mkdir(parents=True, exist_ok=True)

        dest = dest_dirs[i] if i < len(dest_dirs) else None
        dest_path = Path(dest) if dest else None
        if dest_path:
            dest_path.mkdir(parents=True, exist_ok=True)

        slots.append({
            "index": i,
            "processing_dir": proc_path,
            "destination_dir": dest_path,
        })

    log.info(f"Active slots: {len(slots)}")
    return slots


def move_completed(slot):
    proc_dir = slot["processing_dir"]
    dest_dir = slot["destination_dir"]

    if not dest_dir:
        log.info(f"[Slot {slot['index']}] No destination set — files remain in {proc_dir}")
        return

    items = list(proc_dir.iterdir())
    if not items:
        log.info(f"[Slot {slot['index']}] Nothing to move.")
        return

    log.info(f"[Slot {slot['index']}] Moving {len(items)} item(s) to {dest_dir}")
    moved, skipped = 0, 0

    for item in items:
        target = dest_dir / item.name
        if target.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            target = dest_dir / f"{item.stem}_{timestamp}{item.suffix}"
        try:
            shutil.move(str(item), str(target))
            moved += 1
        except Exception as exc:
            log.warning(f"  Could not move {item.name}: {exc}")
            skipped += 1

    log.info(f"[Slot {slot['index']}] Moved: {moved}  Skipped: {skipped}")


def download_worker(source, slot, semaphore):
    with semaphore:
        slot_idx = slot["index"]
        proc_dir = slot["processing_dir"]

        log.info(f"[Slot {slot_idx}] START → {source}")

        cmd = [
            CONFIG["GALLERY_DL_PATH"],
            *CONFIG["GALLERY_DL_FLAGS"],
            "--destination", str(proc_dir),
            source,
        ]

        try:
            result = subprocess.run(cmd, text=True, timeout=3600)
            if result.returncode == 0:
                log.info(f"[Slot {slot_idx}] DONE ✓ {source}")
            else:
                log.warning(f"[Slot {slot_idx}] Exited {result.returncode} — {source}")
        except subprocess.TimeoutExpired:
            log.error(f"[Slot {slot_idx}] TIMEOUT — {source}")
        except Exception as exc:
            log.error(f"[Slot {slot_idx}] ERROR — {source}: {exc}")
        finally:
            move_completed(slot)


def main():
    setup_logging()
    log.info("╔══════════════════════════════════════════╗")
    log.info("║         Image Scraper — gallery-dl       ║")
    log.info("╚══════════════════════════════════════════╝")

    check_for_updates()

    sources = load_sources()
    if not sources:
        log.error("No sources found in List.txt — exiting.")
        return

    slots = get_active_slots()
    if not slots:
        log.error("No active processing slots — exiting.")
        return

    slot_pool = [slots[i % len(slots)] for i in range(len(sources))]
    max_concurrent = min(CONFIG["MAX_CONCURRENT_DOWNLOADS"], len(slots))
    semaphore = threading.Semaphore(max_concurrent)
    stagger = CONFIG["DOWNLOAD_STAGGER_DELAY"]

    log.info(f"Max concurrent downloads: {max_concurrent}")

    threads = []
    for i, (source, slot) in enumerate(zip(sources, slot_pool)):
        t = threading.Thread(
            target=download_worker,
            args=(source, slot, semaphore),
            daemon=True,
        )
        threads.append(t)
        t.start()
        if i < len(sources) - 1:
            time.sleep(stagger)

    for t in threads:
        t.join()

    log.info("=" * 60)
    log.info("All downloads complete.")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
