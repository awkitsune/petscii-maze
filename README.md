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
