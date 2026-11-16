#!/bin/bash
# Download every public video/Short from a YouTube channel, then copy to Google Drive.
#
# Usage:  ./download.sh "https://www.youtube.com/@somehandle"  ["Folder Name"]
#
# Videos land in ~/Downloads/YouTube Downloads/<Folder Name>
# and are copied to Google Drive under "YouTube Downloads/<Folder Name>".
# Re-running skips anything already downloaded.

set -uo pipefail

CHANNEL="${1:-}"
if [ -z "$CHANNEL" ]; then
  echo "Give me a channel URL, e.g.  ./download.sh \"https://www.youtube.com/@nora_connects\""
  exit 1
fi

# Folder name: second argument, or the @handle from the URL.
NAME="${2:-$(echo "$CHANNEL" | sed -E 's#.*/@?([^/?]+).*#\1#')}"

LOCAL_DIR="$HOME/Downloads/YouTube Downloads/$NAME"
DRIVE_DIR="YouTube Downloads/$NAME"
mkdir -p "$LOCAL_DIR"

echo "==> Downloading \"$NAME\" to: $LOCAL_DIR"

# --write-info-json saves each video's stats next to it, which the manifest reads below.
yt-dlp \
  --ignore-errors \
  --no-warnings \
  --restrict-filenames \
  --write-info-json \
  --download-archive "$LOCAL_DIR/.already-downloaded.txt" \
  -f "bv*+ba/b" \
  --merge-output-format mp4 \
  -o "$LOCAL_DIR/%(upload_date)s_%(title).70B_%(id)s.%(ext)s" \
  "$CHANNEL"

# Build a spreadsheet of the channel from the saved stats (handy for reference/scouting).
echo "==> Writing manifest.csv"
python3 -I - "$LOCAL_DIR" <<'PY' > "$LOCAL_DIR/manifest.csv"
import csv, glob, json, os, sys
rows = []
for path in glob.glob(os.path.join(sys.argv[1], "*.info.json")):
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except Exception:
        continue
    if d.get("_type") == "playlist":   # the channel-level file, not a video
        continue
    raw = d.get("upload_date") or ""
    date = f"{raw[:4]}-{raw[4:6]}-{raw[6:]}" if len(raw) == 8 else ""
    rows.append({
        "title": d.get("title", ""),
        "upload_date": date,
        "views": d.get("view_count", ""),
        "likes": d.get("like_count", ""),
        "comments": d.get("comment_count", ""),
        "duration_seconds": d.get("duration", ""),
        "link": f"https://youtu.be/{d.get('id','')}",
        "file": os.path.basename(d.get("_filename", "")),
    })
rows.sort(key=lambda r: r["upload_date"], reverse=True)
cols = ["title","upload_date","views","likes","comments","duration_seconds","link","file"]
w = csv.DictWriter(sys.stdout, fieldnames=cols)
w.writeheader()
w.writerows(rows)
PY

COUNT=$(find "$LOCAL_DIR" -maxdepth 1 -name '*.mp4' | wc -l | tr -d ' ')
echo "==> $COUNT video file(s) in $LOCAL_DIR"

echo "==> Copying to Google Drive: $DRIVE_DIR"
rclone copy "$LOCAL_DIR" "gdrive:$DRIVE_DIR" \
  --exclude ".already-downloaded.txt" \
  --exclude "*.info.json" \
  --progress --transfers 4

echo "==> Done. Google Drive folder: $DRIVE_DIR"
