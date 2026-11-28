
# MoonToolX

macOS 27 widget and app: Earth–Moon distance (center to center), calculated to the second, with the Moon's phase.

*Deutsch: [README.de.md](README.de.md)*

![MoonToolX main window with split-flap display of the distance, Moon image with supermoon badge, and distance chart over ±14 days](docs/MoonTool.png)

**Download:** [MoonToolX 1.0 (notarized DMG)](https://github.com/wombat-26/MoonToolX/releases/latest)

- **Ephemeris:** JPL DE440 (2021, current JPL planetary and lunar ephemeris), geocentric Moon as
  Chebyshev series (`Shared/moon_de440.bin`, 2020–2099). Computational deviation from DE440 below 1 mm; UTC → TT with 69.184 s.
  Cross-checked with JPL Horizons (DE441, vector table, Earth center to Moon center): deviation below 1 m.
- **Moon as in the sky:** toggle below the Moon image; rotates the image by P − q (position angle of the lunar axis after
  Meeus ch. 53 minus parallactic angle), so the zenith is at the top. Checked against JPL Horizons (NP.ang, four locations,
  2026–2099): P within 0.05°; q checked against an independent vector calculation.
- **Rise and set:** upper limb with 34′ refraction, highest point as meridian transit; search in 10-minute steps,
  bisection to 1 s. Checked against JPL Horizons (R_T_S, three locations, 2026 and 2035, 53 events): at most 1 minute.
  Also visibility ("Visible, … left" / "Rises in …") and apparent diameter in minutes of arc.
- **Distance from your location:** the Mac's location (CoreLocation, local only) as a WGS84 point, rotated into the
  ephemeris reference frame via apparent sidereal time, nutation (main terms) and precession (IAU 1976); plus the Moon's
  altitude and compass direction (azimuth). Checked against JPL Horizons (topocentric vectors, three locations, 2026–2099):
  distance within 0.1 km, altitude and azimuth within 0.001°.
- **Sun:** Meeus ch. 25 (≈ 0.01°) for phase, illumination and phase times (accurate to the minute).
- **Widget:** timeline entries exactly at the seconds when the km display changes, plus one entry per minute.
  One timeline covers 60 minutes (24 reloads per day).
- **Moon images:** rendered at runtime (`Shared/MoonRenderer.swift`) from the NASA SVS LRO/LROC map (CGI Moon Kit,
  public domain), Lunar-Lambert photometry, earthshine; lunar north pole up, continuous phase, with libration.
  The app renders from your location (4096 × 2048 map), the widget from the Earth's center (2048 × 1024 map,
  one image per timeline).
- **Brightness:** apparent visual magnitude after Allen (V = 0.23 + 5 lg(r·Δ) + 0.026 α + 4·10⁻⁹ α⁴), from your location,
  without atmosphere. Checked against JPL Horizons (APmag, full moon to new moon): deviation below 0.002 mag.
- **Libration:** lunar orientation after IAU/WGCCRE 2009 including physical libration (`Shared/MoonAspect.swift`).
  Checked against JPL Horizons (disk center, subsolar point, position angle of the axis; geocentric and Munich,
  2026–2031): deviation below 0.01°.

## Tools
- `Tools/main.swift`: cross-check against DE440 reference values:
  `swiftc -O Shared/Astronomy.swift Shared/MoonAspect.swift Tools/main.swift -o /tmp/moonverify && /tmp/moonverify`
- `Tools/make_ephem.py`: regenerates the ephemeris.
- Moon maps `Shared/moon_map_4k.jpg` and `Shared/moon_map_2k.jpg`: made from `lroc_color_poles_4k.tif` and
  `lroc_color_poles_2k.tif` (NASA SVS, CGI Moon Kit) with
  `sips -s format jpeg -s formatOptions 88 lroc_color_poles_4k.tif --out Shared/moon_map_4k.jpg` (2k: quality 90).
- `Tools/make_icon.py`: generates the layers of the Liquid Glass icon `App/AppIcon.icon` (Icon Composer).
- `Tools/make_dmg_background.py`: generates the DMG background `Config/dmg/background*.png` (layout in `Config/dmg/settings.py`).

### When do the tools need to run?
None of the tools is part of the normal build. The generated files are in the repository; the scripts only run
when their source changes.

| Tool | When | How often |
|---|---|---|
| `Tools/main.swift` | after every change to `Shared/Astronomy.swift` or `Shared/MoonAspect.swift` (ephemeris, phases, supermoon logic, libration) and before every release as a safety check | as needed, before every release |
| `Tools/make_ephem.py` | when the time span or accuracy of the ephemeris data should change; the data covers a limited time span and must be regenerated afterwards | practically once, later when the time span ends |
| `Tools/make_icon.py` | when the icon design changes | rarely |
| `Tools/make_dmg_background.py` | when the DMG design or layout changes (then also check `Config/dmg/settings.py`) | rarely |

The bundled ephemeris (`Shared/moon_de440.bin`) is valid from **December 31, 2019 to January 4, 2100**. Outside this span
the calculation returns no values. For a different span, adjust `start_jd` and `end_jd` in `Tools/make_ephem.py` and run the script again:
`python3 Tools/make_ephem.py de440s.bsp Shared/moon_de440.bin` (requires `jplephem` and `numpy`). The source file
[`de440s.bsp`](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp) from JPL/NAIF (32 MB, not in the
repository) covers 1849 to 2150.

`Tools/bump_build.sh` (on every build, as a pre-action in the scheme) and `Tools/release.sh` (once per release) run automatically.

## Languages
English (development and fallback language), German, Spanish, French, Italian, Dutch and Japanese, through String
Catalogs: `Shared/Localizable.xcstrings` for the app and widget, `App/InfoPlist.xcstrings` for the location prompt and
the display name. New strings are written in English in the code; Xcode adds them to the catalog during the build, and
the translations are added there. Numbers, dates and times follow the system's region automatically.

Terms that also appear in macOS follow Apple's own translations (compared with the system's localization tables):
Moon phases, moonrise and moonset, illumination (Weather app), "Edit Widgets…" (Notification Center), Location Services,
Privacy & Security, Reduce motion (System Settings) and the Window menu. One exception: the German phase names stay
astronomical ("Zunehmende Sichel", "Erstes Viertel" …), because Apple's Weather app counts the phases differently.
French uses no-break spaces before ":", "?" and "›".

The install DMG is language-neutral: its background contains no text, only an arrow and icons, and the shortcut is
named "Applications".

## Version and build number
Version and build are set in `Config/Version.xcconfig`. Every build through the **MoonToolX** scheme (Xcode or
`xcodebuild -scheme MoonToolX`) increments `CURRENT_PROJECT_VERSION` by 1 in a pre-action (`Tools/bump_build.sh`);
the app and widget get the same number.

## Distribution outside the App Store
`zsh Tools/release.sh` archives, signs with Developer ID, has Apple notarize the app, staples the ticket and
creates `build/release/MoonToolX-<version>-<build>.dmg` (with an "Applications" shortcut to the Applications folder)
and a ZIP. After changing the DMG background, delete `Config/dmg/background.tiff`; the script recreates it from the PNGs.
Optionally the script also notarizes the DMG itself if the notarytool profile `MoonToolX-notary` is in the keychain
(once: `xcrun notarytool store-credentials MoonToolX-notary --apple-id <Apple ID> --team-id 76X3T92345`).
Requirement: signed in under Xcode › Settings › Accounts. Export options: `Config/ExportOptions-DeveloperID.plist`.

November 2026, Matthias Eckardt
