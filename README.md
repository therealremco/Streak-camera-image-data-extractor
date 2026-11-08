# Streak-camera TIFF data extractor

A lightweight native macOS app written in Swift/SwiftUI. No Python runtime,
web server, or third-party dependencies are required.

## Run

Requires macOS 14 or newer and Xcode Command Line Tools (Swift 5.9 or newer).
Install the tools with `xcode-select --install` if needed, then:

```sh
swift run StreakExtractor
```

Click **Open Image…** (Command-O) and select a TIFF or a raw PC-TA `.img` file,
for example `docs/examples/12OKTR2.TIF` or `docs/examples/12OKTR2.IMG`.

- The image is on the left; its sampled brightness profile is on the right.
- Click or drag vertically on the image to move the red sampling line.
- The slider and Up/Down arrow keys also select rows, one pixel at a time.
- Rows are numbered from **0 at the top**. Each line samples the entire width.
- Click **Save…** (Command-S) to choose a destination. The default filename
  includes the source image name and selected row. Existing files require
  confirmation before replacement.
- Open and Save remember their last successfully used folders **separately**,
  including across app restarts. Before the first save, Save starts in the
  source image's folder. Cancelling a dialog does not change either preference.

## Export and image support

Export is UTF-8 text with **two tab-separated columns, no header**, one sample
per line: `X Y`. X is the zero-based horizontal pixel index; Y is the original
pixel value. Decimal numbers use a period, irrespective of your system locale.

Single-page, unsigned 8-bit and 16-bit grayscale TIFFs are supported, as are
8-bit and 16-bit RGB TIFFs without alpha. For RGB, brightness is
`0.2126 R + 0.7152 G + 0.0722 B` in the original numeric scale, not a
gamma-corrected physical intensity. Other formats produce an explicit error.
TIFF orientation is applied consistently to both the preview and sampled data.

### PC-TA `.img` files

The raw files from the streak camera's PC-TA acquisition software (`.img`,
any letter case) are read directly. Prefer them over their TIFF conversions:

- Values are the original **12-bit** data (0–4095), already background-subtracted,
  so the background can be slightly **negative**. Negative values are exported as is.
- The TIFFs made with `TATOTIFF.EXE` hold `max(0, ⌊value · 255 / 4096⌋)`: 16 times
  coarser, with every negative value clipped to 0.
- The status line shows the date and time from the file header. This is the
  acquisition PC's clock and is blank in some files.

The format is undocumented; the layout used here (a 256-byte header, then signed
16-bit little-endian pixels, 512 × 480 in a 512 × 512 frame) was worked out from
the 1998 measurements and is described in `Sources/StreakData/PCTAImage.swift`.

The preview stretches the image's minimum/maximum brightness to black/white
to make faint streaks visible. **This never modifies exported values.**
The plot automatically scales its Y axis for the current row.

## Build a standalone macOS app

```sh
./scripts/build-app.sh
open dist/StreakExtractor.app
```

The app bundle can be moved to Applications and opened without running Swift.
This local build is ad-hoc signed, not notarized for distribution to other Macs.

## Tests

```sh
swift test
```
