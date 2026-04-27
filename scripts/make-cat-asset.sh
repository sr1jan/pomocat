#!/usr/bin/env bash
# make-cat-asset.sh — Build Assets/cat.mov from a YouTube clip or local file.
#
# Usage:
#   scripts/make-cat-asset.sh <youtube_url> <start> <end>
#   scripts/make-cat-asset.sh <local_video_file>
#
# Examples:
#   scripts/make-cat-asset.sh "https://youtu.be/abc123" "0:30" "0:42"
#   scripts/make-cat-asset.sh /tmp/cat_candidates/pexels_brit.mp4
#
# Dependencies:
#   - yt-dlp     (brew install yt-dlp)              — only for YouTube
#   - ffmpeg     (brew install ffmpeg)
#   - rembg      (uv tool install "rembg[cpu]")
#
# Output: Assets/cat.mov (HEVC + alpha channel)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage:"                                                            >&2
  echo "  $0 <youtube_url> <start> <end>"                                  >&2
  echo "  $0 <local_video_file>"                                           >&2
  exit 1
fi

INPUT="$1"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Assets

# Clean any previous run
rm -rf raw_clip.mp4 frames masked
mkdir -p frames masked

if [[ -f "$INPUT" ]]; then
  echo "==> [1/5] copying local file"
  cp "$INPUT" raw_clip.mp4
elif [[ "$INPUT" =~ ^https?:// ]]; then
  if [[ $# -ne 3 ]]; then
    echo "ERROR: YouTube URL requires <start> <end>" >&2
    exit 1
  fi
  START="$2"
  END="$3"
  echo "==> [1/5] yt-dlp: downloading clip ${START}-${END}"
  yt-dlp -f "bv[height<=1080][ext=mp4]" \
    --download-sections "*${START}-${END}" \
    -o raw_clip.mp4 "$INPUT"
else
  echo "ERROR: input must be a URL or an existing file: $INPUT" >&2
  exit 1
fi

echo "==> [2/5] ffmpeg: extracting frames at 30fps"
ffmpeg -loglevel error -i raw_clip.mp4 -r 30 frames/%04d.png

echo "==> [3/5] rembg: removing background from each frame"
for f in frames/*.png; do
  rembg i "$f" "masked/$(basename "$f")"
done

echo "==> [4/5] ffmpeg: encoding ProRes 4444 with alpha (half-res for smaller file)"
# We tried hevc_videotoolbox and libvpx-vp9 first — both silently dropped alpha
# in this homebrew ffmpeg 7.1 build despite advertising support. ProRes 4444 is
# the universally-supported "alpha video on macOS" codec. Half-resolution
# (540x960) keeps the file size sane while still looking sharp at fullscreen
# (the overlay is letterboxed/scaled by AVPlayerView anyway).
ffmpeg -loglevel error -y -framerate 30 -i masked/%04d.png \
  -vf "scale=540:960" \
  -c:v prores_ks -profile:v 4 -qscale:v 18 \
  -pix_fmt yuva444p10le \
  Assets/cat.mov

echo "==> [5/5] verifying alpha channel"
PIX=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=nw=1:nk=1 Assets/cat.mov)
# ffmpeg writes yuva444p10le, ffprobe reports it as yuva444p12le (12-bit container envelope)
if [[ ! "$PIX" =~ ^yuva ]]; then
  echo "ERROR: expected pix_fmt yuva* but got '$PIX' — alpha channel missing!" >&2
  exit 1
fi

echo "Done. Assets/cat.mov created with alpha. ($(ls -lh Assets/cat.mov | awk '{print $5}'))"
