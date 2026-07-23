---
name: app-icon-design
description: >-
  Design production-quality app icons, logo marks, and favicons, then package
  them for every target: macOS .icns, Windows .ico, Linux PNG, Electron
  wiring, and web favicon/PWA sets, including light and dark variants and
  flat two-color (monochrome/themed-icon) reductions. Encodes exact
  technical specs (corner radius, palette construction, gradient-based
  shading instead of SVG filters, small-size legibility rules) plus a
  mandatory render-and-look iteration loop. Use this whenever the user asks
  for an app icon, logo, brand mark, favicon, dock or taskbar icon, .icns
  or .ico generation, a monochrome or themed icon variant, or a
  splash-screen logo, even if they just say "make an icon for my app" or
  "we need a logo".
disable-model-invocation: true
---

# App Icon Design

App icons fail for three predictable reasons. The concept tries to say too
much and turns into clip-art soup. The details are tuned at 1024px and die
at 16px. Or the tooling silently mangles the SVG during rasterization and
nobody looks closely enough to notice. This skill prevents all three:
a one-sentence concept, geometry rules derived from what survives
downscaling, and a loop where you render actual PNGs and look at them
before shipping anything.

Follow the phases in order. Do not skip phase 4 (render and look); the
first attempt is never the one to ship.

## Phase 1: Find the concept

Write one sentence connecting the product's core story to a geometric
image before drawing anything. Good concepts are about what the product
*does to its material*, not what category it is in:

- "Tapestry weaves video segments from many sources into one archive" >
  a weave: three timeline bars with a thread passing over-under-over.
- "Ledger app balances money flowing between accounts" > two stacked
  shapes in equilibrium, not a dollar sign.
- A camera app does not need a camera glyph; ask what *this* camera app
  uniquely does.

Constraints that keep the concept honest:

- 4 or fewer distinct shapes. Every shape must be explainable by the
  sentence.
- No text or letters. Wordmarks are illegible at icon sizes, and monograms
  are a last resort, not a default.
- If the concept needs a caption to make sense, simplify until the shapes
  alone carry it.

## Phase 2: Build the master SVG

Work on a 1024x1024 canvas. One SVG is the single source of truth; every
raster asset is rendered from it. All numbers below are for the 1024
canvas; treat them as percentages if you change canvas size.

### The tile (background)

- Full-bleed rounded square, corner radius 22 to 23 percent of the edge
  (rx="234" at 1024). This matches the Apple icon-grid curvature so the
  icon sits naturally in a macOS dock, and looks intentional everywhere
  else. Transparent outside the corners.
- Fill with a subtle vertical linear gradient, not a flat color: roughly
  8 percent lightness difference top to bottom, lighter stop on top
  (dark tile: #1c1c1c to #0a0a0a; light tile: #fafafa to #e7e7e7). Flat
  fills look like placeholders; loud gradients look like 2010.
- Optional but effective: a radial glow behind the mark in the brand hue,
  peaking at 12 to 20 percent opacity on a dark tile and fading to 0 at
  the tile edge. Halve the opacity on a light tile; color casts show
  much more against light fills. It lifts the mark off the background at
  large sizes and disappears harmlessly at small ones.
- Optional: an inset border stroke about 10/1024 wide: white at 5 to 8
  percent opacity on a dark tile, black at 4 to 6 percent on a light
  one. It separates the tile from a same-polarity dock or tab bar.

Pick the tile polarity (dark or light) from the brand, then build the
other polarity as a variant of the SAME geometry: identical shapes and
positions, only the fills change. Identical geometry is what keeps the
two variants reading as one brand. Favicons swap between them
automatically (see the web reference); desktop formats ship one
canonical polarity, so pick the one matching the product's primary
theme.

### The mark (foreground)

- The mark occupies 55 to 65 percent of the tile width, optically
  centered. More than that feels cramped; less feels timid.
- Minimum element thickness: 9 percent of the canvas (96/1024). At 16px
  that is ~1.4px, the thinnest line that still reads. Anything thinner
  vanishes in a browser tab or menu bar.
- Minimum gap between elements: 7 percent (72/1024). Gaps close up faster
  than strokes thin out when downscaling.
- Round the ends of bars and strokes fully (rx = half the thickness).
  Hard rectangle ends read as unfinished at large sizes and as noise at
  small ones.
- Filled shapes only. No outline-style strokes, no detail smaller than
  3 percent of the canvas.

### Color

- Build the palette from one hue ramp, the brand color's family. Use 3
  or 4 steps of the ramp for the main shapes (for a Tailwind-style ramp:
  the 400/500/600 steps) plus one very light step (100 or 200) reserved
  for the single hero element of the story.
- The lightest element is the protagonist. In a weave, the thread; in a
  layer stack, the top layer. One bright element gives instant hierarchy;
  two compete.
- On a LIGHT tile, invert the value logic: shapes come from the deeper
  half of the ramp (500/600/700) and the hero is the deepest or most
  saturated step, not the lightest. Light-on-light has no hierarchy.
- Never use pure #ffffff or #000000; tint them toward the hue (e.g.
  #d1fae5 instead of white on an emerald icon). Pure white reads as a
  hole, pure black as a void.
- Adjacent shapes must sit at least one ramp step apart or be separated
  by background gaps, or they merge into one blob at 32px.

### Depth: gradients, never filters

Do not use SVG filters (feGaussianBlur, feDropShadow). Non-browser
rasterizers (ImageMagick's internal renderer, various icon tools) drop or
mangle them, and the failure is silent. Linear gradients render correctly
everywhere. Fake the shadows:

- Where shape A passes over shape B, draw the occlusion on B: a rectangle
  flush against each edge of A, about 3.5 percent of canvas wide (36/1024),
  filled with a linear gradient from black at ~0.38 opacity (at A's edge)
  to transparent. This reads as soft ambient occlusion. On a light tile
  drop the peak opacity to ~0.20; full-strength shadows read as smudges
  on light fills.
- Place occlusion strips only over the straight middle of B, away from
  B's rounded ends, and they need no clipPath at all. If a strip must
  cross a rounded end, clip it with a clipPath copy of B's shape.
- Draw order encodes over/under: paint B, paint the occlusion strips,
  paint A on top. For a weave (A over B but under C), paint B, strips,
  A, strips-on-A, then C.

Minimal complete example, one bar crossed by a thread:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1c1c1c"/><stop offset="1" stop-color="#0a0a0a"/>
    </linearGradient>
    <linearGradient id="ao-l" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity="0.38"/>
    </linearGradient>
    <linearGradient id="ao-r" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="0.38"/>
      <stop offset="1" stop-color="#000" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="234" fill="url(#bg)"/>
  <!-- bar (under) -->
  <rect x="200" y="464" width="624" height="96" rx="48" fill="#10b981"/>
  <!-- occlusion flanking where the thread will cross -->
  <rect x="428" y="464" width="36" height="96" fill="url(#ao-l)"/>
  <rect x="560" y="464" width="36" height="96" fill="url(#ao-r)"/>
  <!-- thread (over) -->
  <rect x="464" y="232" width="96" height="560" rx="48" fill="#d1fae5"/>
</svg>
```

### Design for two-color reduction (the flat test)

Sooner or later the icon gets flattened to one mark color on one
background color: Android themed icons (manifest `purpose:
"monochrome"`), iOS tinted mode, Safari pinned tabs, laser-etched swag,
stickers. A design survives that only if its structure lives in
silhouette and gaps, never in hue steps or shading. Design for this
from the start:

- Produce a `mono.svg` variant alongside the master: every mark shape
  gets the same single fill (use `currentColor` so consumers can
  recolor it), on a solid background or transparent canvas. Same
  geometry as the master except for the crossings rule below.
- At crossings, cut the weave notch: wherever shape A passes over shape
  B, the mono variant splits or shortens B so a background-colored gap
  of 4 to 5 percent of canvas separates it from A on each side. This is
  the classic woven-knot line-art trick; the occlusion gradients did
  this job in the full-color version, and the notch replaces them.
- Never notch the hero element, even where the full-color version has
  something passing over it. Keep the hero's silhouette continuous and
  notch every other shape around it instead. Faithfully alternating the
  over-under fragments the protagonist, and the fragments recombine
  into false glyphs: a thread split by a bar becomes dot-bar-dot, which
  reads as a division sign. In silhouette form, one whole hero with
  everything else yielding tells the story better than literal
  alternation.
- If two same-colored shapes touch and blob together, either merge them
  into one deliberate silhouette or open a gap. Never let two shapes be
  distinguishable only by their fill colors, or the flat version will
  lie about the design.
- Elements below the 9 percent thickness floor are even less forgivable
  here; there is no color contrast left to rescue them.

## Phase 3: Pick a rasterizer that you have verified

SVG-to-PNG quality varies wildly by tool, and the bad ones fail silently.
Check what is installed, in this order of preference:

1. `rsvg-convert` (librsvg): fast and faithful.
2. `cairosvg` via Python (`pip install cairosvg` or `uvx`): faithful,
   easy to install anywhere.
3. A headless Chromium you already have: if the project has Playwright,
   Puppeteer, or Electron installed, screenshot an `<img>` pointing at
   the SVG with a transparent background. Pixel-perfect. Two traps:
   Retina screenshots often come out at 2x the CSS size, so check the
   output dimensions and downscale with `magick in.png -resize 1024x1024
   out.png` rather than fighting device pixel ratios. And the harness
   page itself must have no authored background: `omitBackground` only
   strips the browser's default white, so a body background you set for
   visual comfort gets baked under every transparent region of the
   asset. After rendering, verify a corner pixel is actually
   transparent: `magick out.png -format '%[pixel:p{2,2}]' info:` must
   report alpha 0, not a color.
4. Inkscape CLI.
5. ImageMagick directly on the SVG, ONLY as a last resort and only after
   probing it: `magick -list configure | grep -i delegates` and look for
   `rsvg`. Without that delegate, ImageMagick uses its internal MSVG
   renderer, which mishandles clipPaths and gradient stops. If you must
   use it, render one probe PNG and inspect it against the SVG before
   trusting anything.

Downscaling raster-to-raster with ImageMagick is always safe; it is only
SVG *rasterization* that needs a verified tool. So a good pipeline is:
verified tool renders one big PNG (1024 or 2048), ImageMagick derives
every smaller size from it.

## Phase 4: Render, look, iterate (mandatory)

Never ship the first design. The loop:

1. Render 512px and small sizes (64, 32, 16).
2. Upscale the small ones with point filtering so you can actually see
   the pixels: `magick icon-16.png -filter point -resize 1600% zoom.png`.
3. Look at the renders (open or Read the image files, do not just check
   that they exist). Check: does the concept still read at 64? Is
   anything mushy at 16? Do adjacent colors still separate?
4. Produce 2 or 3 deliberate variants (different palette weighting,
   different element the hero, geometry nudges) and montage them
   side by side: `magick montage a.png b.png c.png -tile 3x1 -geometry
   +10+10 -background '#505050' sheet.png`. Compare on a mid-gray
   background so neither light nor dark docks bias you, then check the
   winner against both a light and a dark backdrop.
5. Run the flat test: render the mono variant (all mark shapes one
   color on the background color) at 512 and 32 and look at it. If the
   design only reads in full color, fix the geometry (gaps, notches,
   merged silhouettes), not the palette. Ask the false-glyph question
   here too: fragments plus gaps can recombine into division signs,
   crosses, or letters that the full-color version never suggested.
6. If shipping light and dark variants, render them side by side and on
   each other's backgrounds; both must read, and the mark geometry must
   be pixel-identical between them.
7. Pick one on stated grounds (hierarchy, small-size read, brand fit),
   fold in anything the losers did better, and re-render.

Common verdicts and fixes: too pastel overall means the mid tones need
one ramp step deeper; hero element not popping means lighten it one step
or darken everything else; shapes merging at 32 means widen gaps, not
elements; icon reads as a different glyph (a hashtag, a dollar sign, a
cross) means stagger lengths or break the symmetry that causes it.

## Phase 5: Package for the target platform

Read the reference for the target before generating files, the details
(margins, opacity, frame sets) differ per platform and getting them wrong
is invisible until someone's dock or home screen makes it obvious:

- Desktop app (macOS .icns, Windows .ico, Linux PNG, Electron and Tauri
  wiring): read `references/desktop-packaging.md`.
- Website, browser tab, or PWA (SVG favicon, favicon.ico,
  apple-touch-icon, maskable icons, HTML head snippet): read
  `references/web-favicons.md`.
- Both targets share the same master SVG; only the packaging differs.

## Phase 6: Put the mark in the app

Wherever the product shows its own logo (splash, welcome screen, about
dialog), recreate the bare mark (no tile background) as a first-class
component rather than embedding a PNG:

- Inline SVG with a tight viewBox around the mark's bounding box.
- Prefix gradient and clipPath ids (e.g. `tm-ao-l`) because inline SVG
  ids are document-global and will collide with a second instance.
- Give it `role="img"` and an `aria-label`, and note in a comment that
  it mirrors the master SVG so future edits keep them in sync.
- Verify visually: run the app (or its test harness) and look at a
  screenshot, not just the diff.

## Final checklist

- [ ] Concept is one sentence, 4 shapes or fewer, no text
- [ ] Corner radius 22-23%, element thickness >= 9%, gaps >= 7%
- [ ] One hue ramp + one hero element (lightest on dark tiles, deepest
      on light tiles); no pure white or black
- [ ] Shadows are gradient rects; zero SVG filter elements in the file
- [ ] Flat test passed: mono variant (one mark color on the background
      color) still reads, hero silhouette unbroken, other shapes
      notched at crossings, no false-glyph read
- [ ] Light/dark variants (if shipped) share pixel-identical geometry
- [ ] Rasterizer verified before trusting its output
- [ ] Looked at real renders at 512, 64, 32, 16; compared >= 2 variants
- [ ] Platform packaging matches the reference file for the target
- [ ] Mark componentized in-app; app screenshot checked
