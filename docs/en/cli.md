---
title: CLI Reference
layout: default
permalink: /en/cli/
---

<p align="right" style="font-size: 12px; color: #86868b;"><a href="/Mas/cli/">日本語</a></p>

# Mas CLI Reference

`mas-cli` gives you command-line access to every feature of Mas.

## Installation

```bash
# Build
bash CLI/build.sh

# Install to /usr/local/bin
bash CLI/install.sh
```

---

## Capture

### Basic capture

```bash
# Full screen capture
mas-cli capture fullscreen

# Region capture
mas-cli capture region

# Show capture frame
mas-cli capture frame

# Start GIF recording
mas-cli capture gif

# Start video recording
mas-cli capture video

# Delayed capture (useful for capturing right-click menus and other transient UI)
mas-cli capture fullscreen --delay 5
mas-cli capture region --delay 3
```

### UI capture

Display a specific Mas UI element, then capture it.

```bash
# Menu popover
mas-cli capture menu --output menu.png

# Library window
mas-cli capture library --output library.png

# Settings window
mas-cli capture settings --output settings.png

# Editor window
mas-cli capture editor --output editor.png
```

### Window capture

```bash
# List Mas windows
mas-cli capture window

# Capture a window by ID
mas-cli capture window <id> --output window.png
```

### Generic delayed capture

```bash
# Full screen capture after the default 5-second delay
mas-cli capture delayed --output screenshot.png

# Capture after 3 seconds
mas-cli capture delayed --delay 3 --output screenshot.png
```

### Demo image generation

Captures the full screen and lays down a demo of every annotation type (arrow, rectangle, ellipse, text, highlight, mosaic) automatically.

```bash
# Generate a demo image
mas-cli capture demo --output docs/images/annotations-demo.png
```

### Batch capture for documentation

Capture the menu, settings, and library screenshots in one go.

```bash
# Batch capture into docs/images/ (default)
mas-cli capture all-docs

# Specify output directory
mas-cli capture all-docs --output-dir docs/images
```

Files produced:

| File | Contents |
|---------|------|
| `menu.png` | Menu bar popover |
| `settings.png` | Settings window |
| `library.png` | Library window |

---

## Annotations

Add annotations to an image programmatically.

### Arrow

```bash
mas-cli annotate image.png arrow --from 100,200 --to 300,400 --color red --width 3 --output out.png
```

### Rectangle

```bash
# Outline only
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --width 2 --output out.png

# Filled
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --filled --output out.png
```

### Ellipse

```bash
mas-cli annotate image.png ellipse --rect 100,100,200,200 --color green --width 3 --output out.png
```

### Text

```bash
mas-cli annotate image.png text --pos 100,50 --text "Look here" --size 24 --color red --output out.png
```

### Highlight

```bash
mas-cli annotate image.png highlight --rect 50,100,300,30 --color yellow --output out.png
```

### Mosaic

```bash
mas-cli annotate image.png mosaic --rect 100,100,200,50 --pixel-size 15 --output out.png
```

### Common options

| Option | Description | Default |
|-----------|------|----------|
| `--output path` | Output path (overwrites the source when omitted) | Source image |
| `--color name` | Color name or `#RRGGBB` | `red` |
| `--width N` | Line width | `3` |
| `--no-stroke` | No outline | Outline on |
| `--filled` | Filled (rect/ellipse) | Outline only |

### Available color names

`red`, `blue`, `green`, `yellow`, `orange`, `white`, `black`, `purple`, `#RRGGBB`

### Chaining multiple annotations

Apply them sequentially as a pipeline:

```bash
mas-cli annotate image.png rect --rect 50,50,200,100 --color red --output /tmp/step1.png
mas-cli annotate /tmp/step1.png arrow --from 250,100 --to 150,75 --color red --output /tmp/step2.png
mas-cli annotate /tmp/step2.png text --pos 260,90 --text "Look" --size 18 --color red --output final.png
```

---

## Text recognition (OCR)

```bash
# Extract text
mas-cli ocr screenshot.png

# JSON output with coordinate info
mas-cli ocr screenshot.png --json
```

---

## History management

```bash
# List
mas-cli history list

# Favorites only
mas-cli history list --favorites

# JSON output
mas-cli history list --json

# Delete (an ID prefix is enough)
mas-cli history delete a1b2c3d4
```

---

## Settings

```bash
# List
mas-cli settings list

# Get
mas-cli settings get playSound

# Set
mas-cli settings set playSound false
mas-cli settings set defaultFormat JPEG
mas-cli settings set jpegQuality 0.8
mas-cli settings set pinBehavior latestOnly
```

### Setting keys

| Key | Description | Type | Example values |
|-----|------|------|-------|
| `developerMode` | Developer mode | Bool | `true` / `false` |
| `defaultFormat` | Save format | String | `PNG` / `JPEG` |
| `jpegQuality` | JPEG quality | Double | `0.1` – `1.0` |
| `showCursor` | Include mouse cursor | Bool | `true` / `false` |
| `playSound` | Play sound on capture | Bool | `true` / `false` |
| `autoSaveEnabled` | Save to file | Bool | `true` / `false` |
| `autoSaveFolder` | Save folder | String | Path |
| `autoCopyToClipboard` | Copy to clipboard | Bool | `true` / `false` |
| `closeOnDragSuccess` | Close on successful drag | Bool | `true` / `false` |
| `pinBehavior` | Pin behavior | String | `alwaysOn` / `latestOnly` / `off` |

---

## Misc

```bash
# Open an image in the editor
mas-cli open ~/Desktop/screenshot.png

# Show version
mas-cli version

# Check whether the app is running
mas-cli status
```

---

## Examples

### Automating documentation screenshots

```bash
# 1. Batch capture for UI screenshots
mas-cli capture all-docs --output-dir docs/images

# 2. Generate the demo image
mas-cli capture demo --output docs/images/annotations-demo.png

# 3. Capture the editor window (open the editor beforehand)
mas-cli capture editor --output docs/images/editor.png
```

### Generating annotated images automatically

```bash
# Take a screenshot, then add annotations
mas-cli capture delayed --delay 3 --output /tmp/raw.png
mas-cli annotate /tmp/raw.png rect --rect 50,50,200,100 --color red --output /tmp/step1.png
mas-cli annotate /tmp/step1.png arrow --from 250,100 --to 150,75 --color red --output /tmp/step2.png
mas-cli annotate /tmp/step2.png text --pos 260,90 --text "Look" --size 18 --color red --output final.png
```

### Screenshots in CI/CD

```bash
# Change setting → capture → restore setting
mas-cli settings set playSound false
mas-cli capture fullscreen --delay 2
mas-cli settings set playSound true
```

---

## Notes

- Capture commands (`fullscreen`, `region`, `frame`, `gif`) are delivered as notifications to Mas.app. If the app isn't running, it launches automatically.
- OCR, history, settings, and annotation commands work standalone — the app doesn't need to be running.
- `capture menu` / `capture library` / `capture settings` display the target UI and then capture the window.
- `capture demo` runs standalone: full-screen capture followed by annotation.
- `capture all-docs` launches Mas.app automatically and captures each UI in sequence.
