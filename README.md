# MoonToolX

macOS-27-Widget und App: Entfernung Erde–Mond (Mittelpunkte), sekundengenau berechnet, mit Mondphase.

- **Ephemeride:** JPL DE421, geozentrischer Mond als Tschebyschow-Reihen (`Shared/moon_de421.bin`, 2020–2099).
  Rechnerische Abweichung zur DE421 unter 1 mm; UTC → TT mit 69,184 s.
- **Sonne:** Meeus Kap. 25 (≈ 0,01°) für Phase, Beleuchtung und Phasenzeiten (Minutengenauigkeit).
- **Widget:** Timeline-Einträge genau zu den Sekunden, in denen die km-Anzeige umspringt, plus ein Eintrag pro Minute.
  Eine Timeline reicht 60 Minuten (24 Reloads/Tag).
- **Mondbilder:** 180 Phasen (2°-Raster) aus der NASA-SVS-Karte LRO/LROC (CGI Moon Kit, gemeinfrei),
  Lunar-Lambert-Photometrie, Erdschein; Norden oben, Blick von der Nordhalbkugel, mittlere Libration.

## Werkzeuge
- `Tools/main.swift` – Gegenprüfung gegen DE421-Referenzwerte:
  `swiftc -O Shared/Astronomy.swift Tools/main.swift -o /tmp/moonverify && /tmp/moonverify`
- `Tools/make_ephem.py`, `Tools/render_moon.py`, `Tools/make_assets.py` – erzeugen Ephemeride, Phasenbilder und Assets neu.
- `Tools/make_icon.py` – erzeugt die Ebenen des Liquid-Glass-Icons `App/AppIcon.icon` (Icon Composer).
- `Tools/make_dmg_background.py` – erzeugt den DMG-Hintergrund `Config/dmg/background*.png` (Layout in `Config/dmg/settings.py`).

## Version und Build-Nummer
Version und Build stehen in `Config/Version.xcconfig`. Jeder Build über das Schema **MoonToolX** (Xcode oder
`xcodebuild -scheme MoonToolX`) zählt `CURRENT_PROJECT_VERSION` per Pre-Action (`Tools/bump_build.sh`) um 1 hoch;
App und Widget erhalten dieselbe Nummer.

## Weitergabe außerhalb des App Store
`zsh Tools/release.sh` archiviert, signiert mit Developer ID, lässt die App von Apple notarisieren, heftet das Ticket an
und erzeugt `build/release/MoonToolX-<Version>-<Build>.dmg` (mit Alias auf den Ordner Programme) sowie ein ZIP.
Voraussetzung: in Xcode › Einstellungen › Accounts angemeldet. Exportoptionen: `Config/ExportOptions-DeveloperID.plist`.
