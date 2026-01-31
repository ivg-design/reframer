# Video Overlay - Feature Requirements
liquid glass app design language  DARk MODE FIRST - macOS Tahoe style

## Core Window Behavior
- [x] Transparent, frameless window NO open/close/minimize buttons
- [x] Always-on-top by default (with toggle)
- [x] Resizable window via NATIVE drag handles
- [x] Draggable window via dragging the control bar area OR one handle in the app bottom  corner where there will be a visible handle on hover
- [x] Rounded corners (macOS native appearance)
- [x] Install to /Applications folder

## Video Playback
- [x] Load video files (mp4, webm, mov, avi, mkv, m4v apple prores heevc, av1 etc...
- [x] Play/pause toggle
- [x] Timeline scrubber for seeking without ANY lag - high performacne
- [x] Frame-accurate playback (frame-by-frame stepping) 
- [x] Frame number overlay display-upper left corner
- [x] Frame number input for precise navigation in toolbar with keyboard  incrementing +- frame using arrows and shift modifier for 10 frame jump
- [x] all incremening is auto applied - no need to confirm with enter - BUT enter/esc defocusses input and returns focus to previous app (same for every input/stepper controls - like zoom and opacity)
- [x] Muted by default, volumen control in toolbar minimized

## Zoom & Pan
- [x] Zoom in/out on video using shift +scroll zooom 5% inrements adnd cmd+shift + scrol for fine .1%
- [x] Pan video when zoomed - mouse click+drag 
- [x] Zoom scales from upper-left corner of the video (not not app corner - video corner)
- [x] Zoom percentage overlay display
- [x] Zoom input for precise control in toolbar with keyboard incrementing +- 1% using arrows and shift modifier for 10% jump and cmd modifier for .1% fine control
- [x] Reset view button (zoom/pan to default)

## Opacity
- [x] Adjustable video opacity slider with input for precise control and arrow incrementing +-1% using arrows and shift modifier for 10% jump 
- [x] Range from 2% opacity to 100%

## Lock/Ghost Mode
- [x] Lock mode toggle - makes video area click-through to allow interaction with underlying apps - IMPORTANT NON NEGOTIALBE FEATURE!!!!
- [x] Controls bar and keyboard shortcuts remain interactive when locked - ZOOM/PAN/WINDOW MOVEMENT/WINDOW SIZING IS LOCKED!
- [x] Window dragging / sizing disabled when locked (prevent accidental moves)
- [x] Visual indicator when locked (lock icon change, highlight) (USE ICONS From SF SYMBOLS NOT EMOJIs FOR ALL CONTROLS AND BUTTONS)

## Keyboard Shortcuts (Local) when specific control is focused
- [x] `Left Arrow` - Frame step back
- [x] `Right Arrow` - Frame step forward
- [x] `Shift+Left/Right` - Step 10 frames
- [x] `Up Arrow` - Zoom in (5%)
- [x] `Down Arrow` - Zoom out (5%)
- [x] `Shift+Up/Down` - Zoom faster (10%)
- [x] `+` / `-` - Zoom in/out
- [x] `0` - Reset zoom to 100%
- [x] `R` - Reset view (zoom/pan)
- [x] `L` - Toggle lock mode
- [x] `H` or `?` - Toggle help menu
- [x] `Cmd+O` - Open file dialog
- [x] `Esc/Enter` in inputs - Defocus and return focus to previous app

## Keyboard Shortcuts (Global - work even when locked)
- [x] `Cmd+Shift+L` - Toggle lock mode
- [x] `Cmd+PageUp` - Frame step forward (with Shift for 10 frames)
- [x] `Cmd+PageDown` - Frame step back (with Shift for 10 frames)

## Mouse/Scroll Controls
- [x] Scroll wheel - Frame step forward/back - disabled in lock mode
- [x] Shift+Scroll - Zoom in/out (5% increments) - disabled in lock mode
- [x] Cmd+Shift+Scroll - Fine zoom (0.1% increments) - disabled in lock mode
- [x] Click+drag on video - Pan when zoomed - disabled in lock mode
- [x] Click+drag on top bar - Move window - disabled in lock mode
- [x] Click+drag on edges/corners - Resize window - disabled in lock mode

## UI Elements
- [x] Drop zone for initial state (click or Cmd+O to open)
- [x] macOS Tahoe-style liquid glass design for the entire app and ui elements
- [x] Control bar with all playback controls
- [x] Help modal with all keyboard shortcuts listed
- [x] Minimal, non-intrusive overlays for frame/zoom info

## File Handling
- [x] Open file dialog with video filter
- [x] Support common video formats
- [x] Drag & drop video files 

## Custom App Icon
- [x] Custom application icon
- [x] video playback are is 100% transparent - only video pixels are visible - no background color and video pixels opacity is controlled by opacity setting
