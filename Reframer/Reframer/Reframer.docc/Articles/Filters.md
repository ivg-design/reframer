# Filters

Apply real-time video filters to enhance your reference material.

## Overview

Reframer includes a variety of video filters that can be applied in real-time. Unlike traditional single-filter applications, Reframer allows you to **combine multiple filters** to create exactly the effect you need.

## Available Filters

| Filter | Description |
|--------|-------------|
| **Brightness** | Adjust image brightness (-1 to +1) |
| **Contrast** | Adjust image contrast (0.25 to 4) |
| **Saturation** | Adjust color intensity (0 = grayscale, 2 = vibrant) |
| **Exposure** | Adjust exposure in EV stops (-3 to +3) |
| **Edges** | Edge detection, useful for tracing outlines |
| **Sharpen** | Increases image sharpness and detail |
| **Unsharp Mask** | Professional sharpening with radius control |
| **Monochrome** | Converts to sepia/tinted tones |
| **Invert** | Inverts all colors |
| **Line Overlay** | Creates a line-art effect |
| **Noir** | Black and white film effect |

## Using Filters

### Quick Access Menu

1. **Hold** the filter button (checkerboard icon) in the toolbar for 300ms
2. A menu appears with all available filters
3. **Toggle** individual filters on/off using the checkmarks
4. Multiple filters can be active simultaneously

### Filter Settings Panel

1. **Click** the filter button (checkerboard icon) to open the settings panel
2. Use checkboxes to enable/disable filters
3. Adjust filter parameters using the sliders

### Menu Bar

Access filters through the **Filter** menu:
- Toggle individual filters
- Clear All Filters
- Open Filter Settings panel
- Reset filter parameters to defaults

## Combining Filters

Filters are applied in a consistent order when combined. For example:
- **Edges + High Contrast** creates bold, visible outlines
- **Sharpen + Saturation (0)** creates a crisp grayscale reference
- **Unsharp Mask + Exposure (+1)** enhances detail in dark footage
- **Noir + Exposure (-0.5)** creates dramatic dark B&W

## Keyboard Shortcut

| Shortcut | Action |
|----------|--------|
| `F` | Toggle filter settings panel |
| `Escape` | Close filter panel |

## Tips

- The filter button turns **blue** when any filter is active
- Hover over the filter button to see which filters are currently applied
- Use **Clear All** to quickly disable all filters
- Filter settings are independent of which filters are active
