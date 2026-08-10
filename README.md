# Petskii Maze

A C64/PETSCII-style screensaver for macOS — random forward-slash/backslash
glyphs print left-to-right and scroll upward, forming an ever-growing maze
pattern. Rendered natively with Metal (instanced quads + a glyph atlas
texture) instead of software drawing, for a fast, crisp, retro feel.

Ported from the original browser version in [`index.html`](index.html).

## Requirements

- macOS 12 (Monterey) or later
- A Metal-capable Mac (basically anything since 2012)

## Building

Open `petskii-maze.xcodeproj` in Xcode and build (`⌘B`).

For a build to actually install/share (not just test locally), build the
**Release** configuration targeting a generic destination, so both Apple
Silicon and Intel Macs are supported:

```bash
xcodebuild -scheme petskii-maze -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Plain `⌘B`/Debug builds only produce a binary for your Mac's own architecture
(fast for local iteration) — the `-destination 'generic/platform=macOS'`
Release build above is what actually produces a universal `arm64 + x86_64`
binary that runs on both Apple Silicon and Intel Macs.

## Installing

Double-click the built `Petskii Maze.saver` — this opens System Settings'
Screen Saver pane with it selected and previewing. Choose it from the list
to use it as your screen saver.

## Project structure

```
petskii-maze/
  PetskiiMazeView.swift   # ScreenSaverView subclass; hosts a CAMetalLayer
                          # and drives rendering with a CVDisplayLink
  Renderer.swift          # grid state, timing, and all Metal setup/drawing
  Shaders.metal           # vertex/fragment shaders (instanced quads, glyph atlas)
petskii-maze.xcodeproj/  # Xcode project
index.html               # original browser version this was ported from
```
