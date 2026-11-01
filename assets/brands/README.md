# Project brands

The final app bundles `liberon-tech-white.svg` and
`khrestenkov-co-white.svg`. Neither has a background rectangle, filter,
shadow or glow. Liberon has white lettering/frame and a solid white cloud
with the original black facial details and outline. Both are scalable paths.

Sources checked 2026-10-30:
- Liberon: original five-path inline SVG at https://khrestenkov.com/es/liberon/.
  Original paths retained; colours changed, with the cloud/tag exterior
  contours supplying the white interior under the original black mascot.
- KhD: the website's original Newsreader 500 monogram, converted from the
  website font to path outlines. Exact text: `KhD`. The square background
  and the `KHRESTENKOV & CO` caption are omitted, as requested by the owner.
  Font: https://khrestenkov.com/fonts/newsreader-500-normal-latin.woff2.
- `liberon-tech.png` and `khrestenkov-co.png`: unchanged screenshots supplied
  by the owner, retained as references and not bundled in the app.

The built-in imagegen tool was tried for background extraction. Those outputs
had unwanted glow/texture and were discarded. The final graphics use the
original editable brand paths instead. Final edit specification: preserve
lettering, proportions and mascot expression; transparent background; white
wordmarks and frame; white mascot body with black auxiliary facial details;
no glow, gradient, distress, shadows or background.

About copy is summarized in Spanish from:
- https://khrestenkov.com/es/
- https://khrestenkov.com/es/liberon/
- https://khrestenkov.com/es/mvd-transporte/

The app description follows the current app features where the website still
describes the older WebView and balance widget. The About page is bundled
and opens offline. Only its explicit website links open the system browser.

The shared Flutter logo row aligns Liberon left and centers KhD in the right
half. The vertical divider sits exactly halfway across the visible gap between
the right edge of the Liberon artwork and the left edge of the KhD square.
KhD is wrapped by a white square outline with no fill, so its interior uses
the surrounding surface colour (including About).
