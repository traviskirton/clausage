# Bugs

Open bugs to fix. Add new ones at the top.

## 2026-11-10: "0%" label clipped / overlapped

![screenshot](bugs/2026-11-10-zero-percent-label.png)

- **Seen:** a "0%" value in a white rounded chip on the cream background. The chip has no room above the text: its top edge is cut off. A grey circle overlaps the chip's bottom-right corner.
- **Where:** not confirmed; the screenshot is cropped. Likely the popover or a widget where usage is at 0%.
- **Check:** whether it only happens at 0% (narrow text width), and in light and dark.
- **Status:** open, not started.
