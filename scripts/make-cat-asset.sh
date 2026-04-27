#!/usr/bin/env bash
# make-cat-asset.sh — Build Assets/cat.mov from a YouTube clip.
#
# Usage:
#   scripts/make-cat-asset.sh <youtube_url> <start> <end>
# Example:
#   scripts/make-cat-asset.sh "https://youtu.be/abc123" "0:30" "0:42"
#
# Dependencies:
#   - yt-dlp     (brew install yt-dlp)
#   - ffmpeg     (brew install ffmpeg)
#   - rembg      (pipx install rembg)
#
# Output: Assets/cat.mov (HEVC + alpha channel)

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <youtube_url> <start> <end>" >&2
  echo "example: $0 'https://youtu.be/abc123' '0:30' '0:42'" >&2
  exit 1
fi

URL="$1"
START="$2"
END="$3"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Assets

# Clean any previous run
rm -rf raw_clip.mp4 frames masked
mkdir -p frames masked

echo "==> [1/5] yt-dlp: downloading clip ${START}-${END}"
yt-dlp -f "bv[height<=1080][ext=mp4]" \
  --download-sections "*${START}-${END}" \
  -o raw_clip.mp4 "$URL"

echo "==> [2/5] ffmpeg: extracting frames at 30fps"
ffmpeg -loglevel error -i raw_clip.mp4 -r 30 frames/%04d.png

echo "==> [3/5] rembg: removing background from each frame"
for f in frames/*.png; do
  rembg i "$f" "masked/$(basename "$f")"
done

echo "==> [4/5] ffmpeg: encoding HEVC with alpha"
ffmpeg -loglevel error -y -framerate 30 -i masked/%04d.png \
  -c:v hevc_videotoolbox \
  -alpha_quality 0.75 \
  -tag:v hvc1 \
  -pix_fmt yuva420p \
  Assets/cat.mov

echo "==> [5/5] verifying alpha channel"
PIX=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=nw=1:nk=1 Assets/cat.mov)
if [[ "$PIX" != "yuva420p" ]]; then
  echo "ERROR: expected pix_fmt=yuva420p but got '$PIX' — alpha channel missing!" >&2
  exit 1
fi

echo "Done. Assets/cat.mov created with alpha. ($(ls -lh Assets/cat.mov | awk '{print $5}'))"
