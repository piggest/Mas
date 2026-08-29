---
title: User Guide
layout: default
permalink: /en/user-guide/
---

<p align="right" style="font-size: 12px; color: #86868b;"><a href="/Mas/user-guide/">日本語</a></p>

# Mas User Guide

<p align="center">Scoop up your screen.<br>Precise, effortless screenshots for Mac.</p>

**Mas** (Mac Area Screenshot) is a screenshot capture and editing app for macOS.
It packs the essentials — capture, annotation, GIF and video recording, text recognition, and automated shooting — into a single compact tool.

---

## Installation

### Homebrew (recommended)

```bash
brew tap piggest/mas
brew install --cask mas
```

### Manual install

1. Download the latest `Mas-x.x.x.dmg` from [Releases](https://github.com/piggest/Mas/releases)
2. Open the DMG and drag `Mas.app` to your `/Applications` folder
3. Grant Screen Recording permission on first launch

### System requirements

- macOS 13.0 (Ventura) or later
- Screen Recording permission

---

## Getting started

Mas lives in the menu bar.

**The simplest way to use it: double-click the Mas icon in the menu bar.**

1. Double-click to enter region selection mode
2. Drag to select the area you want — the selection is cropped instantly
3. The editor window opens, ready for annotations

![Editor](/Mas/images/editor.png)

---

## Capture

Each capture method and its default shortcut.

| Method | How | Shortcut |
|------|------|--------------|
| Full screen | Menu → "Full screen" | `⌘⇧3` |
| Region | Menu → "Region" or double-click the icon | `⌘⇧4` |
| Capture frame | Menu → "Show capture frame" | `⌘⇧6` |
| GIF recording | Menu → "GIF recording" | `⌘⇧7` |
| Video recording | Menu → "Video recording" | `⌘⇧8` |
| Open image | Menu → "Open..." | `⌘O` |

The editor window opens automatically after capture.

![Menu](/Mas/images/menu.png)

### Full screen

`⌘⇧3` captures the entire main display.

### Region

1. Press `⌘⇧4` and an overlay covers the screen
2. Drag the mouse to select a region
3. Release to capture
4. `ESC` to cancel

Your last region is remembered and can be reused with the `⌘⇧6` capture frame.

### Capture frame

`⌘⇧6` displays your last region as a frame. Adjust its size and position before shooting — handy when you need the same area repeatedly.

- The window position is remembered when closed and restored next time
- You can switch the frame into capture, GIF recording, or video recording (action button in the top right)

### GIF recording

Record any area of your screen as an animated GIF.

**Steps:**

1. Press `⌘⇧7` to enter region selection
2. Drag to choose the recording area — recording starts immediately
3. A red border surrounds the area and a control panel appears at the top
4. Press stop to generate the GIF file

**Recording specs:**

- Frame rate: 10 FPS
- Format: Animated GIF (infinite loop)
- Save location: Auto-save folder (when configured) or `~/Pictures/Mas`

#### GIF player

After recording finishes, the GIF opens in the editor window. The floating toolbar at the bottom controls playback.

| Action | Description |
|------|------|
| Play / pause | Preview playback |
| Previous / next frame | Step one frame at a time |
| Frame slider | Seek to any frame |
| Playback speed | 0.5x / 1x / 2x |

> The recording control window (red border, stop button) is not captured in the GIF.

### Video recording

Record a screen area as an MP4 video.

**Steps:**

1. Press `⌘⇧8` to enter region selection
2. Drag to choose the recording area — recording starts immediately
3. Press stop to generate the video file

**Recording specs:**

- Frame rate: 20 FPS
- Format: MP4 (H.264)
- Audio: System audio is included when "Record system audio during video recording" is ON in settings
- Save location: Auto-save folder (when configured) or `~/Pictures/Mas`

#### Video player

| Action | Description |
|------|------|
| Play / pause | Preview playback |
| Back 5s / forward 5s | Jump back or forward |
| Previous / next frame | Step one frame at a time |
| Frame slider | Seek to any position |
| Playback speed | 0.5x / 1x / 2x |

#### Trimming video

Use the "Trim" button in the toolbar to cut out a segment.

1. Click "Trim"
2. Set the start and end positions with the slider
3. Click "Confirm" to generate a new video file with just the selected segment

#### Export video as GIF

Click the "GIF" button in the video player toolbar to convert to GIF. If you're trimming, only the trim range is used; otherwise the whole video is converted.

### Open image

`⌘O` opens an existing image file (PNG, JPEG, GIF, MP4, etc.) in the editor.

### Multi-display

Multi-display setups are supported. You can capture each display individually, and region selection works across display boundaries.

---

## Editing (annotations)

The editor's floating toolbar gives you access to all the tools.

### Entering edit mode

Click the pencil icon (✏️) at the bottom left of the editor window, or **right-click the window → Toggle edit mode** to start editing.

### Move

<img src="/Mas/images/tools/move.png" width="20"> Click an annotation to select, drag to move, and use the handles to resize.

### Pen / Marker

| Tool | Icon | Description |
|--------|:-------:|------|
| Pen | <img src="/Mas/images/tools/pen.png" width="20"> | Freehand drawing |
| Marker | <img src="/Mas/images/tools/marker.png" width="20"> | Semi-transparent highlight (3× thickness) |

### Line / Arrow / Arrow with text

| Tool | Description |
|--------|------|
| Line | A simple line with no arrowhead. Resize with the endpoint handles |
| Arrow | A tapered arrow — thin at the tail, thicker toward the tip |
| Arrow with text | Arrow plus callout text. Ideal for labeled instructions |

### Rectangle / Ellipse

Draw rectangles and ellipses. Toggle between outline only and semi-transparent fill.

### Speed lines

Draw manga-style speed lines. **The area you drag becomes the "focus"** — the subject you want to emphasize — and lines converge on it from the edges of the whole image.

- Clicks pass through the focus, so the subject you framed stays clickable
- Only the ring just outside the focus is grabbable — clicking near the image edge won't select the speed lines
- Moving and corner-resizing affect the focus only; the lines follow automatically
- The size slider controls the width of each line — thicker lines mean fewer of them
- Hold `Shift` while dragging to constrain the focus to a square
- Lines use the currently selected color (black works best)
- Turn on the outline option to add a thin streak along one side of each line, keeping the effect visible without changing the line's shape or width. The streak is white, or black when you pick a light color such as white or yellow
- Speed lines sit below other annotations, so arrows and text stay readable
- Place several speed lines and they split the image into Voronoi regions by distance from each focus, so each one draws only within its own territory

### Text

<img src="/Mas/images/tools/text.png" width="20"> Place text on the image. Click to place, then type with the keyboard.

### Blur (mosaic)

<img src="/Mas/images/tools/mosaic.png" width="20"> Apply a pixelation (mosaic) effect to a rectangular region. Useful for masking personal or sensitive information.

### Crop

<img src="/Mas/images/tools/trim.png" width="20"> Cut out a portion of the image.

1. Choose "Crop" from the toolbar
2. Drag to set the crop region
3. Click the confirm button to apply

### Text selection (OCR)

<img src="/Mas/images/tools/ocr.png" width="20"> Recognize text in the screenshot, then select and copy character by character.

1. Choose "Text selection" (magnifier icon) from the toolbar
2. Text regions are highlighted automatically
3. Drag to select **character by character**
4. `⌘C` to copy to the clipboard

Powered by VisionKit Live Text. Recognizes mixed Japanese (including vertical text) and English, plus tables, circled numbers, and handwriting.

### Common options

- **Color** — Choose from a 10-color palette (red, orange, yellow, green, blue, purple, pink, black, white, gray)
- **Width** — Adjust with a slider (1–10 pt). Updates in real time while dragging
- **Stroke** — Toggle on/off. Three-layer rendering (black outer edge → white border → original color) keeps it visible on any background
- **Fill** — Toggle semi-transparent fill for rectangles and ellipses
- **Undo** — Up to 50 levels via the Undo button
- **Delete** — `Delete` key while selected, or the delete button in the toolbar

### Tool groups

Click a button to open the selection menu for that group. The last tool you chose is remembered, so switching back is quick.

| Group | Tools |
|----------|----------------|
| Drawing | Pen / Marker |
| Shapes | Line / Arrow / Arrow with text / Rectangle / Ellipse / Speed lines |

---

## Editor window

The window that opens after capture.

### Buttons

#### Top left

| Button | Description |
|--------|------|
| Close (×) | Close the window |
| Pin (📌) | Pin the window to the top / unpin |

#### Top right

| Button | Condition | Description |
|--------|------|------|
| Pass-through (👆) | Frame-only mode | Lets mouse events pass through to the app behind |
| Capture action | Capture region present | Recapture / GIF recording / video recording (right-click to switch mode) |

The capture action button's icon updates based on shooting mode (screenshot → 📷, GIF → ⏺, video → 🎥).

#### Bottom

| Button | Description |
|--------|------|
| Edit mode (✏️) | Bottom left. Click to toggle edit mode |
| Drag (↗) | Bottom right. Drag the file into another app |

### Basic operations

| Action | Behavior |
|------|------|
| Double-click | Hide the image and show only the frame (double-click again to restore) |
| Right-click | Context menu (close, copy, toggle edit mode, shutter) |

### Pass-through mode

Double-click the editor window and the image disappears, leaving only the frame. Then click the "Pass-through" button in the top right and mouse events pass through to the app behind. The capture region stays as a visual guide while you interact with whatever is underneath.

### Auto-expand

When annotations extend past the image edge, the editor window expands automatically. The content stays anchored to its original screen position while the window grows in the overflowing direction (expand only — never shrink).
If the content can't fit on screen, it scales down so the whole thing stays visible.

### Editor shortcuts

| Shortcut | Function |
|--------------|------|
| `⌘S` | Save image |
| `⌘C` | Copy image to clipboard |
| `⌘Z` | Undo |
| `Delete` / `Backspace` | Delete the selected annotation |

---

## Shutter (automated capture)

Trigger captures automatically based on time or events. Four modes are available.

### Launching shutter

Right-click the editor window → "Shutter" to launch. The shutter panel appears to the right of the editor window and follows it when moved.

> To use it, first display an editor window with a capture frame (`⌘⇧6`) or region selection.

The tabs at the top of the shutter panel switch between the four modes.

### Timer mode (delayed capture)

Capture automatically after a specified delay. Useful for capturing UI states like right-click menus that you can't shoot directly.

1. Select the "Timer" tab
2. Set the delay in seconds (1–30, slider)
3. Click "Start" — capture fires after the countdown

### Interval mode (repeated capture)

Capture repeatedly at a fixed interval. Good for recording changes over time or unattended monitoring.

1. Select the "Interval" tab
2. Set the interval (0.5–60 seconds, slider) and max shots (0–1000, 0 = unlimited)
3. Click "Start"
4. Stops manually or automatically at the maximum

### Change detection mode

Watch a screen region and capture automatically when changes are detected. Perfect for catching dialog appearances or UI state transitions.

1. Select the "Change detection" tab
2. Adjust detection sensitivity (0.1–100%, smaller = more sensitive)
3. Optionally specify a sub-region to monitor (defaults to the whole capture area)
4. Click "Start" — capture fires whenever the monitored area changes
5. The change rate is shown in real time

### Programmable mode

Combine multiple steps to build automated capture sequences. The most flexible mode.

#### Step types

| Step | Description | Parameters |
|---------|------|-----------|
| Capture | Take a capture | — |
| Wait | Wait for a fixed time | Seconds |
| Wait for change | Wait until the monitored area changes | Sensitivity (default 5%) |
| Wait for stable | Wait until the screen is stable (changes below threshold) | Sensitivity |
| Repeat | Loop child steps N times | Count (0 = infinite), child steps |

#### How to use

1. Add a step with the "+" button
2. Configure each step's parameters (inline stepper for numeric input)
3. Drag and drop to reorder steps
4. Click "Start" to run the sequence

The currently running step is highlighted with a cyan border. Repeat blocks are green; wait-for-change steps are purple.

#### Save and load programs

- **Save**: Enter a name and click the save button
- **Load**: Pick from the list of saved programs
- **Last step**: The most recent step configuration is remembered automatically

#### Per-step monitor regions

For "wait for change" and "wait for stable" steps, you can specify a monitor region per step.

1. Click the monitor region button on the step
2. Drag on the editor window to select the region
3. Configured regions are shown with a dashed border; the selected step's region uses a thicker border
4. Toggle visibility with the 👁 icon
5. Re-select or reset regions from the right-click menu

If no monitor region is specified, the whole capture area is monitored.
Wait-for-change and wait-for-stable steps compare against the image from "the most recent capture step".

---

## Library

The window for managing capture history. Choose "Library" from the menu or press `⌘⇧L`.

![Library](/Mas/images/library.png)

### Display and actions

- Grid view with thumbnails of your capture history
- Click to open or close the editor window
- Entries with annotations show a label
- Item count (top right) and a button to open the save folder

### Favorites

- Star icon on each entry marks it as a favorite
- Star button in the header filters between "All" and "Favorites"

### Categories

Tag entries with categories to keep them organized.

- Tag icon in the header filters by category
- Right-click menu or bulk actions assign categories
- Entries without categories are filtered with the "Uncategorized" filter

### Multi-select and bulk delete

- Hold `⌘` / `⇧` to select multiple items
- Selected count is shown, with a button to clear the selection
- Delete selected items in bulk (with a confirmation dialog)
- Assign categories to selected items in bulk

---

## Menu bar

### Menu items

| Item | Shortcut | Description |
|------|-------------|------|
| Show capture frame | `⌘⇧6` | Show the capture frame using the last region |
| Full screen | `⌘⇧3` | Capture the entire main display |
| Region | `⌘⇧4` | Capture a region selected by dragging |
| GIF recording | `⌘⇧7` | Record a screen area as GIF |
| Video recording | `⌘⇧8` | Record a screen area as MP4 |
| Open... | `⌘O` | Open an existing image file in the editor |
| Library | `⌘⇧L` | Show capture history |
| Open windows | — | List of editor windows (thumbnail, pin toggle, close) |
| Close all | — | Close every editor window at once |
| Settings... | `⌘,` | Open the settings window |
| Quit | `⌘Q` | Quit the app |

The "Open windows" section shows a thumbnail, pin state toggle, size info, and filename for each window, and lets you close them directly.

### Icon actions

| Action | Behavior |
|------|------|
| Single click | Toggle the menu |
| Double-click | Start region selection capture |

---

## Settings

Open the settings window from the menu's "Settings..." (`⌘,`). Five tabs.

![Settings](/Mas/images/settings.png)

### General tab

#### Capture

| Setting | Description |
|---------|------|
| Copy to clipboard | Automatically copy after capture |
| Save to file | Automatically save after capture |
| Save location | Choose the destination folder ("Change..." to pick) |
| Save format | PNG / JPEG |
| JPEG quality | 10–100% (shown when JPEG is selected) |

#### Other

| Setting | Description |
|---------|------|
| Include mouse cursor | Include the cursor in captures |
| Play sound on capture | Play a sound when capturing |
| Record system audio during video recording | Include system audio when recording video |
| Launch at login | Start Mas automatically at login |
| Developer mode | Reveals the "Developer" tab when ON |

#### Updates

| Setting | Description |
|---------|------|
| Auto-update | Automatically detect and install the latest version from GitHub Releases |
| Check now | Manually check for updates (with status display) |

### Display tab

#### Window

| Setting | Description |
|---------|------|
| Pin (always on top) | Always ON / Latest only ON / Default OFF |
| Close on successful drag | Close the window when drag-and-drop succeeds |

#### Menu bar

| Setting | Description |
|---------|------|
| Icon | Mas / Monochrome / Camera / Frame (4 styles) |

### Shortcuts tab

Customize the key binding for every action.

| Function | Default |
|-----|-----------|
| Full screen capture | `⌘⇧3` |
| Region | `⌘⇧4` |
| Show capture frame | `⌘⇧6` |
| GIF recording | `⌘⇧7` |
| Video recording | `⌘⇧8` |
| Library | `⌘⇧L` |

- Changes apply immediately
- Duplicate keys are warned automatically
- The "Reset to default" button resets one shortcut; "Reset all to defaults" resets every one

### Developer tab (only when developer mode is on)

Visible when "Developer mode" is turned ON in the General tab.

| Section | Content |
|-----------|------|
| Data | View the app data folder, open it in Finder |
| Capture | Include own UI in capture (Mas's own windows show up in screenshots) |
| Delayed capture | Full screen or region capture after a 1–10 second delay (for testing) |

Normally, Mas's windows (editor, toolbar, overlays, etc.) are excluded from screen captures automatically. With "Include own UI in capture" ON, Mas's windows also become capture targets — useful when you need to shoot menus, the library, or other UI elements that are normally hard to capture.

### Info tab

Shows the app name, version, description, and copyright.

---

## Auto-save and output

### Clipboard

The capture is automatically copied to the clipboard (can be turned OFF in settings). After editing, you can also copy manually with right-click → Copy.

### Save to file

- **Auto-save**: Save to your chosen folder as PNG or JPEG (default is `~/Pictures/Mas`)
- **Manual save**: `⌘S` or right-click → Save to choose a destination from the dialog
- **Drag & drop**: Drop the editor's image directly into another app (from the drag icon at the bottom right)

### Filename

Auto-saved files use the format `Screenshot_YYYY-MM-DD_HH-mm-ss.png`.

---

## Auto-update

Turn on "Auto-update" in Settings → General → Updates to automatically detect, download, and install the latest version from GitHub Releases. The "Check now" button runs a manual check.

When a new version is found, it downloads and installs automatically and prompts you to restart the app.

---

## Global shortcuts

| Shortcut | Function |
|--------------|------|
| `⌘⇧3` | Full screen capture |
| `⌘⇧4` | Region capture |
| `⌘⇧6` | Show capture frame |
| `⌘⇧7` | GIF recording |
| `⌘⇧8` | Video recording |
| `⌘⇧L` | Library |
| `⌘O` | Open image file |
| `⌘,` | Open settings |
| `⌘Q` | Quit |

> Shortcuts are customizable from the Settings window.

---

**Related docs:**

- [CLI Reference](../cli/) — Operations from the command line

> For power users: the [CLI Reference](../cli/) lets you capture, annotate, run OCR, and change settings from the command line.
