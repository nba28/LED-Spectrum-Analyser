# LED Spectrum Analyser for Apple Music and iTunes

A hi-fi style LED spectrum analyser visualizer, originally written by Graham Cox (Apptree, 1999–2014). This fork
rebuilds it as a **64-bit, universal (Apple Silicon + Intel)** visualizer plug-in that recreates the look and behaviour
of Graham's last release, **3.0.7**, for:

- **Apple Music** on current macOS, running natively on Apple Silicon (arm64) or Intel
- **iTunes 10.4 and later**, including the iTunes 10.7 that [Retroactive](https://github.com/cormiertyshawn895/Retroactive)
  installs (x86_64, under Rosetta on Apple Silicon)

## Install

1. Download `LED-Spectrum-Analyser.zip` from this repository's Actions artifacts or Releases, or build it (below).
2. Quit Music / iTunes.
3. Copy `LED Spectrum Analyser.bundle` to `~/Library/iTunes/iTunes Plug-ins/` (Music uses the same folder). **Remove
   any older LED Spectrum Analyser bundle from that folder first**, since both would offer the same name.
4. If the download was quarantined: `xattr -dr com.apple.quarantine ~/Library/iTunes/iTunes\ Plug-ins/LED\ Spectrum\ Analyser.bundle`
5. Open Music, show the visualizer (Window › Visualizer) and choose LED Spectrum Analyser in the Visualizer menu.

Type `d` (or right-click) for the options; `=` shows diagnostics. The full manual, including every keyboard shortcut,
is in [`resources/manual.html`](resources/manual.html) and opens from the right-click menu.

## Screenshots

Rendered by the test harness on CI ([`tests/host_harness.mm`](tests/host_harness.mm)). The CI machines have no GPU,
so these are software renders: they show no perspective tilt, and where reflections are on (the cover art background
shot) they are drawn solid instead of faded. In Music and iTunes the panels get 3.0.7's perspective and faded
reflections, both on by default.

| | |
|---|---|
| ![Side by side](docs/screenshots/01-side-by-side.jpg) | ![Back to back](docs/screenshots/02-back-to-back.jpg) |
| Side by side (default layout) | Back to back |
| ![Analogue VU](docs/screenshots/03-analogue-vu.jpg) | ![31 bands, text above](docs/screenshots/04-31-bands-text-above.jpg) |
| Analogue VU meters | 31 bands, track info above |
| ![Cover art](docs/screenshots/09-cover-art-centred.jpg) | ![Cover art background](docs/screenshots/10-cover-art-background.jpg) |
| Cover art at the start of a track | …then as the background, with its colours |
| ![Options](docs/screenshots/06-options-layout.jpg) | ![Diagnostics](docs/screenshots/05-diagnostics.jpg) |
| Options window | `=` diagnostics |

## What this is, and how it relates to the originals

Two versions of the original exist:

| | Source | Binary | Technology |
|---|---|---|---|
| 2.0.6 (2006) | in [`legacy/`](legacy/) | ppc + i386 | Carbon, QuickDraw, 32-bit only |
| 3.0.7 (2014) | **never published** | i386 + x86_64 | Cocoa, Core Animation |

The 2.0.6 source can't be made 64-bit: QuickDraw and the Carbon UI it is built on don't exist in 64-bit macOS, and
Rosetta 2 runs neither ppc nor i386 code. 3.0.7 is the version people actually run (it is x86_64, which is why it works
under Rosetta), but only its binary survived. So this is a new implementation that:

- **matches 3.0.7's look** – layout proportions measured from the screenshots in Graham's 3.0 manual: perspective,
  reflections, glowing track info, progress bar, cover art and analogue VU meters. The VU meter is redrawn in code
  rather than copied from 3.0.7's artwork.
- **matches 3.0.7's behaviour** – the same options (Layout / Appearance / Advanced, with 3.0.7's ranges and defaults),
  the same keyboard shortcuts and on-screen messages, presets, and the same preference names.
- **reuses Graham's analysis** – the band mapping is his 2.0.6 code, and 3.0.7 uses the same calibration constant
  (78.047 Hz per spectrum entry), so bars respond to frequencies exactly as before.

## Apple Music vs iTunes

Both apps speak the same plug-in API (Apple's iTunes Visual SDK 2.0, message version 10.7), and the plug-in handles
both identically. If the bars look different in Music than in iTunes 10.7, it is the data the host sends that differs.
Apple has never documented that data, so this version gives you the means to measure and correct it:

- **`=` diagnostics overlay** – pulse rate, audio format, spectrum and waveform levels, and the loudest spectrum
  entry, as the host actually delivers them. Play the same track in both apps and compare.
- **Spectrum Gain** (Options › Advanced) – scales the host's spectrum data. Settings are kept per app, so Music and
  iTunes can each have their own (presets are shared).
- **Paused playback** – Music keeps sending its last block of audio data while it is paused, which held the bars
  (and 3.0.7's) frozen near the top. Data that stops changing is now treated as silence, so the meters fall and the
  plug-in goes idle when you pause.
- The VU meters use the waveform data when the host supplies it (falling back to the spectrum otherwise), and have
  their own Gain knob, as in 3.0.7.

## Building

Requires Xcode command line tools (`xcode-select --install`). No Xcode project is needed.

```sh
make               # universal bundle in build/
make ARCHS=arm64   # Apple Silicon only (Music only, no iTunes 10.7)
make install       # copy to ~/Library/iTunes/iTunes Plug-ins
make test          # core unit tests (works on Linux too)
make harness       # run the plug-in inside a fake iTunes host and save screenshots to build/screenshots
make zip           # build/LED-Spectrum-Analyser.zip
```

The bundle is ad-hoc signed, which Apple Silicon requires and which is sufficient for a plug-in you install yourself.

## Layout of the source

| Path | |
|---|---|
| `src/core/` | Platform-neutral C++: settings, band mapping and ballistics, layout, track text, colours, presets and keyboard commands. Unit tested in `tests/core_tests.cpp`. |
| `src/mac/` | The plug-in: SDK message handling (`PlugInMain.mm`), Core Animation renderer, procedurally drawn artwork, options window. |
| `sdk/` | Apple's iTunes Visual Plug-in SDK 2.0 headers. |
| `tests/host_harness.mm` | A fake host that loads the bundle like Music / iTunes and drives it. |
| `legacy/` | Graham Cox's original 2.0.6 source, unchanged, for reference. |

Rendering uses Core Animation, which composites on the GPU (through Metal on current macOS). Every LED bar is a few
layers built from shared, pixel-aligned images. Per frame, only the heights of the lit parts, the peak markers and
the VU needles change, so a frame costs a fraction of a millisecond of CPU time.

## History

This iTunes visualizer was originally developed by Graham Cox of Apptree software. Graham let [his website](http://apptree.net)'s
domain registration expire, and doesn't plan to continue updating or supporting this project. Before the domain
expired, he open sourced the plug-in's code (2.0.6). It was archived on GitHub by Isaac Halvorson, whose repository this
is forked from, along with Graham's final 3.0.7 binary. The 64-bit rebuild is not affiliated with Graham Cox.
