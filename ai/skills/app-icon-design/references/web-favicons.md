# Web favicons and PWA icons

The brutal constraint: a favicon renders at 16 to 32 CSS pixels in a
browser tab. Before packaging, re-check the mark at 16px specifically.
If it goes to mush, make a simplified favicon variant of the master:
drop the occlusion shading, thicken elements toward the 12 percent
floor, and consider dropping the tile so the bare mark fills the canvas
(tabs give you no dock to blend into, so full-canvas marks read bigger).
Keeping a separate `icon-favicon.svg` variant is normal and better than
shipping an illegible faithful one.

## The modern minimal set

Five files cover every browser, device, and PWA context. Generate all of
them from the master(s); each has a non-obvious constraint that breaks
if ignored:

| File                    | Size      | Constraint                                  |
| ----------------------- | --------- | ------------------------------------------- |
| `icon.svg`              | vector    | May adapt to dark mode (see below)          |
| `favicon.ico`           | 32 + 16   | At site root; old browsers and tools ask for `/favicon.ico` unprompted |
| `apple-touch-icon.png`  | 180x180   | FULLY OPAQUE, square corners, full-bleed: iOS composites it on black and applies its own mask, so transparency renders as ugly black corners |
| `icon-192.png`          | 192x192   | PWA manifest, Android home screen           |
| `icon-512.png`          | 512x512   | PWA manifest, splash generation             |
| `icon-mask.png`         | 512x512   | `purpose: "maskable"`: background must fill the whole canvas edge-to-edge, all important content inside the central 80 percent circle (the safe zone), because Android crops it to arbitrary shapes |

Generation from the full-bleed tile render:

```bash
magick tile-1024.png -resize 32x32 f32.png
magick tile-1024.png -resize 16x16 f16.png
magick f32.png f16.png favicon.ico

# apple-touch-icon: flatten corners onto the tile's own background color
magick tile-1024.png -background '#0a0a0a' -alpha remove -alpha off \
  -resize 180x180 apple-touch-icon.png

magick tile-1024.png -resize 192x192 icon-192.png
magick tile-1024.png -resize 512x512 icon-512.png

# maskable: scale the MARK to ~66% and center it on an opaque full-canvas
# background so the tile's rounded corners do not leave transparent edges
magick tile-1024.png -resize 676x676 -background '#0a0a0a' -gravity center \
  -extent 1024x1024 -alpha remove -alpha off -resize 512x512 icon-mask.png
```

Verify the two constraint-heavy ones: `magick identify -format '%A'
apple-touch-icon.png` must not report an alpha channel in use
(`Undefined`/`False` is good), and the maskable icon's content must
survive `magick icon-mask.png -gravity center -crop 80%x80%+0+0` with
nothing important cut off.

## Head snippet and manifest

```html
<link rel="icon" type="image/svg+xml" href="/icon.svg" />
<link rel="icon" href="/favicon.ico" sizes="32x32" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/manifest.webmanifest" />
<meta name="theme-color" content="#0a0a0a" />
```

```json
{
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icon-mask.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

The SVG favicon is listed first because supporting browsers prefer it
and it stays crisp on any display density; the ico line is the fallback
for everything else.

## Dark mode SVG favicon

Browser tabs sit on both light and dark chrome. An SVG favicon can adapt
with a media query inside the file, which only applies when the SVG is
used as a favicon or img (scripts are ignored there, CSS is not):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <style>
    .tile { fill: #0a0a0a; }
    @media (prefers-color-scheme: dark) {
      .tile { fill: #1c1c1c; }
    }
  </style>
  <rect class="tile" width="1024" height="1024" rx="234"/>
  <!-- mark shapes -->
</svg>
```

Use it to nudge contrast (lighter tile on dark chrome, or a
transparent-background mark that swaps its own colors), not to redesign
the icon per theme. If the master has light and dark tile variants, this
media query is exactly where they meet: same geometry, the CSS swaps the
fills.

## Monochrome and themed icons (two-color reductions)

Android's themed icons (Material You) recolor a single-color version of
the mark to match the user's wallpaper; iOS tinted mode does the same
idea natively. Ship the mono variant the skill's flat test already
produced:

```bash
# white mark on transparent, mark inside the same 80% safe zone as maskable
magick mono-white-1024.png -resize 512x512 icon-monochrome.png
```

Manifest entry alongside the others:

```json
{ "src": "/icon-monochrome.png", "sizes": "512x512", "type": "image/png", "purpose": "monochrome" }
```

The monochrome PNG must be a single flat color (white) plus
transparency only; Android supplies the background and tint. Any
gradient or second color survives as muddy alpha, so render it from
`mono.svg`, not from the full-color master. Legacy Safari pinned tabs
take the same artwork as a single-path SVG via
`<link rel="mask-icon" href="/mask.svg" color="#d97706">`; include it
only if the user cares about pinned tabs.
