# Filters

Adjust the reference picture with Core Image.

Activate the filter control to open a conventional quick-filter menu. Choose
Brightness, Contrast, Saturation, Exposure, Edges, Sharpen, Invert, or Noir,
then adjust the available value. Choose None to clear the quick filter.

Choose Advanced Filters or press F to open the panel for filter stacking and
the multi-parameter Unsharp Mask, Monochrome, and Line Art effects. Opening the
panel moves keyboard focus into it; Escape closes it and returns focus to the
invoking control.

Filter parameters are clamped and persisted. Replacing a filter composition
cancels stale asynchronous work so an older render cannot overwrite the newer
choice.
