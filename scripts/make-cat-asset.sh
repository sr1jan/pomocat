#!/usr/bin/env bash
# make-cat-asset.sh — Build Assets/cat.mov from a green-screen source video.
#
# Usage:
#   scripts/make-cat-asset.sh <youtube_url> <start> <end>
#   scripts/make-cat-asset.sh <local_video_file>
#
# Examples:
#   scripts/make-cat-asset.sh "https://youtu.be/abc123" "0:30" "0:42"
#   scripts/make-cat-asset.sh /tmp/cat_candidates/pexels_brit.mp4
#
# Output: Assets/cat.mov (HEVC-with-alpha)
#
# The matting itself is done by the make-cat-asset SwiftPM target, which uses
# Apple's Vision framework (VNGenerateForegroundInstanceMaskRequest) — same
# engine as iOS Photos' "lift subject from background." This script is just a
# thin wrapper that handles the download step.
#
# Dependencies:
#   - yt-dlp  (brew install yt-dlp)  — only when the input is a URL

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

SOURCE_VIDEO=""
CLEANUP=""

if [[ -f "$INPUT" ]]; then
  echo "==> [1/2] using local source: $INPUT"
  SOURCE_VIDEO="$INPUT"
elif [[ "$INPUT" =~ ^https?:// ]]; then
  if [[ $# -ne 3 ]]; then
    echo "ERROR: URL input requires <start> <end>" >&2
    exit 1
  fi
  START="$2"
  END="$3"
  SOURCE_VIDEO="$(mktemp -t pomocat_src.XXXXXX).mp4"
  CLEANUP="$SOURCE_VIDEO"
  echo "==> [1/2] yt-dlp: downloading clip ${START}-${END}"
  yt-dlp -f "bv[height<=1080][ext=mp4]" \
    --download-sections "*${START}-${END}" \
    -o "$SOURCE_VIDEO" "$INPUT"
else
  echo "ERROR: input must be a URL or an existing file: $INPUT" >&2
  exit 1
fi

trap '[[ -n "$CLEANUP" ]] && rm -f "$CLEANUP"' EXIT

echo "==> [2/2] make-cat-asset: Vision matting → Assets/cat.mov"
swift run -c release make-cat-asset "$SOURCE_VIDEO" Assets/cat.mov

echo "Done. $(ls -lh Assets/cat.mov | awk '{print $5}') HEVC-with-alpha."
