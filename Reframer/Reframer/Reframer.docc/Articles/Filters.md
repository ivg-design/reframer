# Filters

Apply real-time video filters to enhance your reference material.

## Overview

Reframer includes a variety of video filters that can be applied in real-time. The filter system has two tiers:

- **Quick Filter**: A single filter selected from the toolbar dropdown, controlled by the toolbar slider
- **Advanced Filters**: Multiple filters that can be stacked together in the Advanced Filters panel

## Two-Tier Filter System

### Quick Filter (Toolbar)

The quick filter provides fast access to simple, single-parameter filters:

1. **Hold** the filter button in the toolbar for 300ms (or right-click)
2. A menu appears with simple filters (single slider parameter)
3. Select **one** filter - this becomes your quick filter
4. The toolbar slider now controls that filter's intensity
5. The filter icon in the toolbar changes to match the selected filter

Quick filters are mutually exclusive - selecting a new one replaces the previous. Select "None" to clear the quick filter.

**Simple filters available in quick menu:**
- Brightness, Contrast, Saturation, Exposure
- Edges, Sharpen, Invert, Noir

### Advanced Filters (Panel)

For complex filters and filter stacking:

1. **Click** the filter button to open the Advanced Filters panel
2. Toggle multiple filters on/off using the switches
3. Adjust each filter's parameters with dedicated sliders
4. Filters are applied in a consistent order when stacked

The Advanced Filters panel gives access to **all** filters including multi-parameter filters not available in the quick menu.

## Available Filters

### Simple Filters (Single Parameter)

| Filter | Range | Description |
|--------|-------|-------------|
| **Brightness** | -1 to +1 | Lightens or darkens the image |
| **Contrast** | 0.25 to 4 | Increases or decreases tonal range |
| **Saturation** | 0 to 2 | 0 = grayscale, 1 = normal, 2 = vibrant |
| **Exposure** | -3 to +3 EV | Simulates camera exposure adjustment |
| **Edges** | 0 to 10 | Edge detection intensity for tracing |
| **Sharpen** | 0 to 2 | Enhances edge sharpness |
| **Invert** | On/Off | Inverts all colors |
| **Noir** | On/Off | Black and white film effect |

### Multi-Parameter Filters

These filters have multiple adjustable parameters and are only available in the Advanced Filters panel.

#### Unsharp Mask
Professional-grade sharpening used in photo editing.

| Parameter | Range | Description |
|-----------|-------|-------------|
| **Radius** | 0 to 10 | Size of the area used to calculate sharpness. Higher values affect larger details. |
| **Intensity** | 0 to 2 | Strength of the sharpening effect. Start low (0.5) and increase as needed. |

#### Monochrome
Converts the image to a single color tone (sepia, tinted effects).

| Parameter | Range | Description |
|-----------|-------|-------------|
| **Red** | 0 to 1 | Red component of the tint color |
| **Green** | 0 to 1 | Green component of the tint color |
| **Blue** | 0 to 1 | Blue component of the tint color |
| **Intensity** | 0 to 1 | How much of the color effect to apply (0 = original, 1 = full effect) |

**Preset ideas:**
- Sepia: R=0.6, G=0.45, B=0.3
- Cold blue: R=0.2, G=0.4, B=0.7
- Warm gold: R=0.8, G=0.6, B=0.2

#### Line Art
Creates a line drawing effect from the video. Note: This replaces the video with line art (it does not overlay lines on the original).

| Parameter | Range | Description |
|-----------|-------|-------------|
| **Sensitivity** | 0.1 to 200 | Edge detection sensitivity. Higher values detect more edges. |
| **Threshold** | 0 to 1 | Minimum brightness difference to detect as an edge. Lower = more lines. |
| **Darkness** | 1 to 200 | Line darkness/contrast. Higher values create bolder lines. |

**Tips for Line Art:**
- For clean, strong lines: Sensitivity=50, Threshold=0.1, Darkness=50
- For subtle sketchy lines: Sensitivity=100, Threshold=0.3, Darkness=25
- Experiment with small threshold changes - the effect is sensitive

## Combining Filters

Both quick filter and advanced filters can be active simultaneously. The quick filter is applied first, then advanced filters in order.

Example combinations using Advanced Filters:
- **Edges + High Contrast** creates bold, visible outlines
- **Sharpen + Saturation (0)** creates a crisp grayscale reference
- **Unsharp Mask + Exposure (+1)** enhances detail in dark footage
- **Noir + Exposure (-0.5)** creates dramatic dark B&W

## Menu Bar

Access filters through the **Filter** menu:
- Toggle individual advanced filters
- Clear All Filters (clears advanced filters only)
- Open Advanced Filters panel
- Reset filter parameters to defaults

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `F` | Toggle Advanced Filters panel |
| `Escape` | Close panel |

## Tips

- The filter button turns **blue** when a quick filter is active
- The toolbar slider label shows the percentage (0-100%) of the filter effect
- Use **Clear All** in the panel to quickly disable all advanced filters
- Quick filter and advanced filters are independent - clearing one doesn't affect the other
- Filter settings are preserved even when filters are toggled off
