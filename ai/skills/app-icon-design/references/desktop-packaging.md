# Desktop icon packaging

All assets derive from the 1024x1024 master SVG, rendered once to a big
PNG by a verified rasterizer (see SKILL.md phase 3), then resized with
ImageMagick. Two shapes of source PNG exist and they are not
interchangeable:

- **Full-bleed tile**: the rounded square touching the canvas edges.
  Used by Windows, Linux, and in-app displays.
- **Margined tile (macOS only)**: the tile scaled to 824/1024 (~80%) and
  centered on a transparent 1024 canvas. Apple's icon grid leaves this
  breathing room; a full-bleed icns looks oversized and amateurish next
  to every other dock icon.

```bash
# margined master from the full-bleed render
magick tile-1024.png -resize 824x824 -background none -gravity center \
  -extent 1024x1024 mac-1024.png
```

## macOS: icon.icns

Build an `.iconset` directory from the margined master and compile it.
All ten entries are required; macOS picks per context (dock, Finder,
Spotlight, alt-tab):

```bash
mkdir icon.iconset
for entry in 16x16:16 16x16@2x:32 32x32:32 32x32@2x:64 128x128:128 \
             128x128@2x:256 256x256:256 256x256@2x:512 512x512:512 512x512@2x:1024; do
  name="${entry%%:*}"; size="${entry##*:}"
  magick mac-1024.png -resize "${size}x${size}" "icon.iconset/icon_${name}.png"
done
iconutil -c icns icon.iconset -o icon.icns
```

Verify by round-tripping: `iconutil -c iconset icon.icns -o verify.iconset`
and confirm all ten files exist. On non-Mac hosts, `png2icns` or
ImageMagick's ICNS writer work but produce fewer entries; note that
tradeoff to the user.

An icns holds one appearance, so ship the tile polarity matching the
product's primary theme. (Native macOS apps can ship light/dark/tinted
appearance variants via Icon Composer `.icon` bundles, but that path
needs Xcode assets and does not apply to portable icns packaging; the
flat-test mono variant is what keeps the icon ready for tinted modes.)

## Windows: icon.ico

One `.ico` containing full-bleed frames at 256, 128, 64, 48, 32, 16.
The 256 frame stays PNG-compressed inside the ico (normal and expected;
Vista+ supports it). No margin: Windows taskbars expect edge-to-edge.

```bash
for s in 256 128 64 48 32 16; do
  magick tile-1024.png -resize "${s}x${s}" "ico-${s}.png"
done
magick ico-256.png ico-128.png ico-64.png ico-48.png ico-32.png ico-16.png icon.ico
magick identify icon.ico   # confirm exactly these 6 frames, nothing invented
```

ImageMagick sometimes auto-generates frame sets you did not ask for;
always `identify` the result and check the frame list.

## Linux

A single full-bleed PNG at 512 or 1024. Desktop environments composite
it as-is; transparency in the corners is respected.

## Electron wiring

Two directories with different jobs:

- `build/` at the app package root: `icon.icns`, `icon.ico`, `icon.png`
  (1024, full-bleed). electron-builder picks these up by convention with
  zero config the day packaging is added, so create them even if the
  project does not package yet.
- `resources/` at the app package root: `icon.png` (512, full-bleed) and
  the master `icon.svg`. These are referenced at runtime.

Main process (electron-vite projects support `?asset` imports; add
`"electron-vite/node"` to the tsconfig `types` array so it typechecks):

```ts
import icon from "../../resources/icon.png?asset";

// Windows/Linux take the window and taskbar icon from the window itself;
// macOS uses the bundle's icns instead.
new BrowserWindow({
  ...(process.platform !== "darwin" ? { icon } : {}),
});

// In development the macOS dock shows Electron's default logo; packaged
// builds get build/icon.icns automatically.
void app.whenReady().then(() => {
  if (!app.isPackaged && process.platform === "darwin") {
    app.dock?.setIcon(icon);
  }
  // ...
});
```

`app.dock` is typed `Dock | undefined`, so use optional chaining. Verify
the wiring by launching the app (dev mode or the e2e harness) and looking
at the dock/taskbar, and screenshot any in-app usage of the mark.

## macOS document icons (file type icons)

Document icons are a different template from app tiles, and Finder makes
every deviation obvious. The native look has three properties:

- A portrait page (aspect ~0.77) spanning ~90% of the canvas height,
  with a small corner radius (~6% of page width) and a folded top-right
  corner about a quarter of the page width.
- A soft drop shadow under the page baked into the artwork (this is why
  native icons read as physical cards in Quick Look), plus a tighter
  contact shadow under the fold flap.
- The app's mark sits on the page in the light-surface palette.

Keep the SVG master flat (no filters) and add the shadows in raster,
where ImageMagick can do true gaussians from the alpha channel:

```bash
# render the page(+mark) layer and the flap layer separately, then:
magick flap.png -alpha extract -blur 0x7 fsa.png
magick -size 1024x1024 xc:black fsa.png -alpha off -compose CopyOpacity \
  -composite -channel A -evaluate multiply 0.32 +channel fshadow.png
magick -size 1024x1024 xc:none fshadow.png -geometry +0+7 -composite foff.png
magick foff.png page.png -compose DstIn -composite fclip.png   # only on the page
magick page.png fclip.png -composite t1.png
magick t1.png flap.png -composite art.png
# card shadow under everything (sigma ~14, offset +10, ~30% black)
magick art.png -alpha extract -blur 0x14 psa.png
magick -size 1024x1024 xc:black psa.png -alpha off -compose CopyOpacity \
  -composite -channel A -evaluate multiply 0.30 +channel pshadow.png
magick -size 1024x1024 xc:none pshadow.png -geometry +0+10 -composite \
  art.png -composite final-1024.png
```

Clip the flap's shadow to the page alpha (the DstIn step) or it halos
outside the fold. Verify corners stay transparent afterward. Name the
outputs `<ext>.icns` / `<ext>.ico` so electron-builder's fileAssociations
find them by convention, and build the icns from the full canvas (the
page's own margins replace the app-tile 824/1024 margin step).

## Tauri

`tauri icon path/to/icon-1024.png` generates every platform format from
one full-bleed 1024 PNG. Feed it the rendered tile and review its macOS
output; older versions do not add the Apple margin, in which case feed
it the margined master for a mac-only build instead.

## Size reference

| Asset                | Shape       | Sizes                          |
| -------------------- | ----------- | ------------------------------ |
| icon.icns            | margined    | 16-1024, ten iconset entries   |
| icon.ico             | full-bleed  | 256, 128, 64, 48, 32, 16       |
| build/icon.png       | full-bleed  | 1024                           |
| resources/icon.png   | full-bleed  | 512                            |
