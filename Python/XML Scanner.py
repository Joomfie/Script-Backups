# XML Keyword Scanner
# Scans through hundreds of .XML files, searches for specific tags/keywords,
# and outputs matches to a .csv file.
# This has not been tested and will be tested for later to see if this fixes issues with the old script.

import os
import re
import xml.etree.ElementTree as ET
import pandas as pd
from collections import defaultdict

# === USER INPUT ===
KEYWORDS = ["tag1", "tag2"]   # not case-sensitive, ALL must be present in the same video block
XML_FOLDER = r"C:\PATH\TO\FOLDER"
OUTPUT_FILE = "keyword_matches.csv"
OVERWRITE_OUTPUT = True        # set to False to abort if output file already exists
# ==================

# --- Validate output file ---
if not OVERWRITE_OUTPUT and os.path.exists(OUTPUT_FILE):
    raise SystemExit(f"Output file '{OUTPUT_FILE}' already exists. Set OVERWRITE_OUTPUT=True to overwrite.")

# --- Normalize and validate keywords ---
# Warn if any keyword contains a comma (common accidental mistake)
for raw_kw in KEYWORDS:
    if "," in raw_kw:
        print(f"[WARNING] Keyword '{raw_kw}' contains a comma — did you mean to split it into separate keywords?")

keywords = [k.strip().lower() for k in KEYWORDS if k and k.strip()]
if not keywords:
    raise SystemExit("No keywords provided in KEYWORDS list.")

print(f"Searching for ALL of: {keywords}")

# --- Container tag names that represent a single 'video/entry' block ---
# De-duplicated and expanded from original
BLOCK_TAG_NAMES = {"url", "video", "videoplaylist", "entry", "item"}

# --- Tag-like child element names to extract explicit tags/keywords from ---
TAG_ELEMENT_NAMES = {
    "tag", "tags", "video_tag", "keyword", "keywords",
    "media:keywords", "category"
}


def local_name(tag: str) -> str:
    """Strip XML namespace and return lowercase local name."""
    return tag.split("}")[-1].lower()


def extract_number(url) -> int | None:
    """
    Extract a numeric ID from a URL.
    Tries multiple common patterns:
      - trailing /123 or -123
      - query param id=123
      - parenthesised (123)
    Returns the first match found, or None.
    """
    if not isinstance(url, str):
        return None
    patterns = [
        r'[/\-](\d+)(?:[/\-?#]|$)',   # /123 or -123 at boundary
        r'[?&]id=(\d+)',                # ?id=123 or &id=123
        r'\((\d+)\)',                   # (123)
        r'(\d+)',                       # any number as last resort
    ]
    for pat in patterns:
        m = re.search(pat, url)
        if m:
            return int(m.group(1))
    return None


def iter_candidate_blocks(root: ET.Element):
    """
    Yield top-level candidate blocks without double-counting nested containers.
    Strategy: walk the tree and yield an element the first time we hit a block-
    tag, then skip its entire subtree (so nested <video> inside <url> is not
    yielded separately).
    """
    def _walk(elem, inside_block=False):
        is_block = local_name(elem.tag) in BLOCK_TAG_NAMES
        if is_block and not inside_block:
            yield elem
            # recurse but mark that we're inside a block now
            for child in elem:
                yield from _walk(child, inside_block=True)
        elif not is_block:
            for child in elem:
                yield from _walk(child, inside_block)
        # if is_block AND inside_block: skip (don't yield nested blocks)

    for child in root:
        yield from _walk(child)


def parse_xml_safe(filepath: str):
    """
    Parse an XML file, trying UTF-8 first then falling back to latin-1.
    Returns an ElementTree root, or raises on failure.
    """
    try:
        tree = ET.parse(filepath)
        return tree.getroot()
    except ET.ParseError:
        # Some files declare a different encoding — try forcing latin-1
        try:
            with open(filepath, "r", encoding="latin-1", errors="replace") as fh:
                content = fh.read()
            return ET.fromstring(content)
        except Exception:
            raise  # re-raise so caller logs it


def extract_block_data(block: ET.Element) -> tuple[str, set, str | None]:
    """
    Returns (combined_text, tag_set, first_url_found) for a block element.
    """
    texts = []
    tag_set = set()
    url = None

    for e in block.iter():
        ln = local_name(e.tag)

        # Collect text and attribute values for broad text search
        if e.text and e.text.strip():
            texts.append(e.text.strip())
        for attr_val in e.attrib.values():
            if attr_val and attr_val.strip():
                texts.append(attr_val.strip())

        # Collect explicit tag/keyword values
        if ln in TAG_ELEMENT_NAMES:
            raw = (e.text or "").strip()
            if raw:
                for part in re.split(r'[,|/;]\s*', raw):
                    part = part.strip().lower()
                    if part:
                        tag_set.add(part)

        # Grab the first URL-like element
        if url is None and ln in ("loc", "link", "locurl", "video_url"):
            if e.text and e.text.strip():
                url = e.text.strip()

    combined_text = " ".join(texts).lower()
    return combined_text, tag_set, url


def keyword_matches(keywords: list[str], combined_text: str, tag_set: set) -> bool:
    """
    Returns True if ALL keywords are satisfied.
    A keyword is satisfied if:
      - it exactly equals a tag in tag_set, OR it is a substring of a tag (whole-word boundary check)
      - OR it appears anywhere in the combined text
    Avoids the original bug of `kw in t` matching 'cat' inside 'category'.
    """
    def kw_in_tags(kw: str) -> bool:
        for t in tag_set:
            # exact match
            if kw == t:
                return True
            # whole-word substring (e.g. 'cat' won't match 'category')
            if re.search(r'\b' + re.escape(kw) + r'\b', t):
                return True
        return False

    for kw in keywords:
        in_tags = kw_in_tags(kw) if tag_set else False
        in_text = kw in combined_text
        if not in_tags and not in_text:
            return False
    return True


# --- Main scan loop ---
results = []
errors = []
matched_count = 0
processed_files = 0
seen_urls = set()  # deduplicate results by url+file combo

for root_dir, _, files in os.walk(XML_FOLDER):
    for file in sorted(files):
        if not file.lower().endswith(".xml"):
            continue

        processed_files += 1
        filepath = os.path.join(root_dir, file)

        try:
            root_elem = parse_xml_safe(filepath)
        except Exception as e:
            errors.append((file, str(e)))
            print(f"[ERROR] Parsing {file}: {e}")
            continue

        candidate_blocks = list(iter_candidate_blocks(root_elem))

        # Fallback: if the heuristic found nothing, treat direct children as blocks
        if not candidate_blocks:
            candidate_blocks = list(root_elem)

        for block in candidate_blocks:
            combined_text, tag_set, url = extract_block_data(block)

            if not keyword_matches(keywords, combined_text, tag_set):
                continue

            # Deduplicate: same file + same url shouldn't appear twice
            dedup_key = (file, url)
            if dedup_key in seen_urls:
                continue
            seen_urls.add(dedup_key)

            matched_tags = ", ".join(sorted(tag_set)) if tag_set else ""
            snippet = (combined_text[:400] + "...") if len(combined_text) > 400 else combined_text

            results.append({
                "file": file,
                "url": url,
                "matched_keywords_required": ", ".join(keywords),
                "matched_tags_found": matched_tags,
                "matched_text_snippet": snippet,
            })
            matched_count += 1

# --- Save results ---
if results:
    df = pd.DataFrame(results)
    df["number"] = df["url"].apply(extract_number)
    df = df.sort_values(by=["number"], na_position="first")
    df.to_csv(OUTPUT_FILE, index=False, encoding="utf-8-sig")  # utf-8-sig for Excel compatibility
    print(f"\nDone. Processed {processed_files} XML files, "
          f"found {matched_count} matching blocks. Results -> {OUTPUT_FILE}")
else:
    print(f"\nProcessed {processed_files} XML files. "
          f"No matches found for ALL keywords: {keywords}")

if errors:
    print(f"\n{len(errors)} file(s) had parse errors:")
    for f, msg in errors[:10]:
        print(f"  - {f}: {msg}")
    if len(errors) > 10:
        print(f"  ... and {len(errors) - 10} more.")
