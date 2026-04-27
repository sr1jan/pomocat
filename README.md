# fatcat

Pomodoro break overlay for macOS. After 25 minutes of active work, a fat cat fades in across all your monitors with a 5-minute break countdown.

Inspired by [this tweet](https://x.com/i/status/2048404010789687315).

## Run

### One-off (foreground)

```bash
swift run -c release
```

The app uses `.accessory` activation — no Dock icon, no menu bar. Quit with Ctrl-C in the terminal where you launched it.

### Auto-start at every login (recommended)

Install fatcat as a per-user `launchd` agent. It starts immediately, runs in the background, restarts if it crashes, and starts again at every login.

```bash
scripts/install-launchagent.sh
```

This builds the release binary (if needed), writes a plist to `~/Library/LaunchAgents/com.fatcat.plist`, and `launchctl load`s it. Logs go to `.fatcat.log` in the repo root.

To stop and disable auto-start:

```bash
scripts/uninstall-launchagent.sh
```

Note: because `KeepAlive=true` in the plist, manually `kill`ing the process won't actually stop fatcat — `launchd` respawns it within seconds. Use the uninstall script (or `launchctl unload ~/Library/LaunchAgents/com.fatcat.plist`) for a real stop.

## How it works

- `BreakScheduler` polls `CGEventSource.secondsSinceLastEventType` once per second to track active vs idle time. Active seconds accumulate; idle seconds (>60s without keyboard or mouse input) pause the accumulator.
- When 25 active minutes accumulate, the cat overlay fades in on every attached display: one transparent `NSWindow` per screen at `.screenSaver` level, all driven by a single shared `AVPlayer`.
- The cat is bottom-aligned so the paws sit on the screen "floor" regardless of monitor aspect ratio (extra letterbox space goes above the head, where it's visually neutral).
- `ProcessInfo.beginActivity(.userInitiated)` keeps macOS App Nap from throttling the 1Hz tick during long work intervals.

## Asset pipeline

`Assets/cat.mov` is HEVC-with-alpha, encoded by a Swift tool that uses Apple's Vision framework (`VNGenerateForegroundInstanceMaskRequest`, same engine as iOS Photos' "lift subject from background") to extract the cat from a green-screen source. No chromakey tuning required — the matter is shape-semantic, so non-uniform green floors and edge fringe don't matter.

To rebuild from a green-screen source:

```bash
# YouTube clip + time range
scripts/make-cat-asset.sh "https://youtu.be/0p_LkdfJJR0" "0:24" "0:31"

# or local file
scripts/make-cat-asset.sh /path/to/clip.mp4
```

The current asset is sourced from a CC-BY YouTube green-screen cat compilation (grey British Shorthair, ~7 seconds). `Assets/cat.mov` is committed via git-lfs.

## Requirements

- macOS 14+ (for `VNGenerateForegroundInstanceMaskRequest`)
- Swift 5.9+
- For the asset pipeline only: `yt-dlp` (`brew install yt-dlp`) and `git-lfs` (`brew install git-lfs`)

## Tests

```bash
swift test
```

Six TDD tests cover `BreakScheduler` state transitions (active accumulation, idle pause, break start/tick/end, return-to-work).
