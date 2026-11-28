import SwiftUI

/// Menüpunkt Hilfe › MoonToolX-Kurzanleitung (⌘?)
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("MoonToolX Quick Guide") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

/// Kurzanleitung für Benutzer
struct HelpView: View {
    static let windowSize = CGSize(width: 560, height: 640)

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MoonToolX").font(.title.weight(.semibold))
                        Text("Quick Guide · \(version)").foregroundStyle(.secondary)
                    }
                }

                section("What MoonToolX shows", symbol: "moon.stars") {
                    Text("MoonToolX calculates the current distance between the center of the Earth and the center of the Moon to the second and shows the moon phase.")
                }

                section("The main window", symbol: "macwindow") {
                    item("Split-flap display", "Distance in kilometers with meters, recalculated every second.")
                    item("Change", "Whether the Moon is currently approaching or receding, and how fast, in meters per second with one decimal place.")
                    item("Light travel time", "How long light takes to travel from the Moon to the Earth.")
                    item("Surface to surface", "Distance minus the mean radii of the Earth and the Moon.")
                    item("Distance from your location", "Distance from your Mac’s location to the center of the Moon. When the Moon is high in the sky, it is up to one Earth radius (about 6,400 km) less than the distance between the centers; at moonrise and moonset, both are almost the same. The first time you open MoonToolX, macOS asks whether it may use your location. Your location stays on your Mac.")
                    item("Altitude · direction", "Altitude of the Moon’s center above the horizon at your location, without atmospheric refraction: + above the horizon, − below it. Also the compass direction (N, NNE, NE … NNW) and the azimuth in degrees, counted from north through east (east = 90°, south = 180°). When the Moon is below the horizon, the direction shows where it is below the horizon.")
                    item("Moon image", "Current phase, north up, as the Moon appears from the Northern Hemisphere. With **As in the Sky** below the image, MoonToolX rotates the Moon the way you see it from your location: zenith up, and the orange N marks the Moon’s north pole. Depending on latitude and time of day, the Moon is tilted or, in the Southern Hemisphere, nearly upside down. When it is below the horizon, it appears faded. The size follows the distance: near perigee the Moon appears larger, near apogee smaller, in the same ratio as in the sky.")
                    item("Moonrise and moonset", "Below the moon image: whether the Moon is visible now and for how long, or when it rises; plus moonrise, highest point (meridian transit with altitude), and moonset at your location, with compass direction. Rise and set times refer to the Moon’s upper limb with atmospheric refraction, as is usual in calendars, and are accurate to about one minute.")
                    item("Apparent diameter", "How large the Moon appears in the sky, in arcminutes (60 arcminutes = 1 degree), seen from your location.")
                    item("Brightness", "Apparent brightness in magnitudes (mag), seen from your location and without dimming by the atmosphere. The smaller the number, the brighter: full moon about −12.7 mag, half moon about −10 mag. Near new moon, the value is only approximate.")
                    item("Supermoon and micromoon", "When a full or new moon occurs near perigee, MoonToolX shows “Supermoon” or “Super New Moon”; near apogee, “Micromoon” or “Micro New Moon”. It uses Richard Nolle’s definition: within 10% of the range between perigee and apogee of the current orbit. The badge shows the time (local time) and distance of that full or new moon, not the current distance.")
                    item("Dates", "Next principal phases plus perigee (closest point to Earth) and apogee (farthest point from Earth), in local time.")
                }

                section("Look back and preview in the chart", symbol: "cursorarrow.click") {
                    Text("The chart shows the distance 14 days back and 14 days ahead. Click a point in the chart: MoonToolX shows the moon image, phase, and distance for that moment for 3 seconds, then returns to the current view. Left of the dashed line (now) this is a **Look Back**, right of it a **Preview**. Another click restarts the 3 seconds.")
                }

                section("Add the widget", symbol: "square.grid.2x2") {
                    step(1, "Drag MoonToolX to the **Applications** folder and open the app once.")
                    step(2, "Control-click the desktop, then choose **Edit Widgets…**.")
                    step(3, "Search for **MoonToolX**, choose a size (small, medium, or large), and drag the widget to where you want it.")
                    Text("The widget updates exactly when the displayed number of kilometers changes, at least every minute. To see what the three sizes look like, choose **Window › Widget Preview**.")
                        .foregroundStyle(.secondary)
                }

                section("Appearance", symbol: "circle.lefthalf.filled") {
                    Text("MoonToolX follows the macOS appearance (light or dark). If **Reduce motion** is turned on in System Settings under **Accessibility › Motion**, the split-flap display changes without animation.")
                }

                section("Accuracy and data", symbol: "scope") {
                    item("Ephemeris", "JPL DE440 (NASA Jet Propulsion Laboratory), valid from 2020 to 2099. The calculation is far more precise than the meters displayed.")
                    item("Location", "Distance from your location is accurate to better than 0.1 km, altitude and direction to better than 0.001° (checked against JPL Horizons). You can allow or revoke access in System Settings under **Privacy & Security › Location Services**.")
                    item("Phase times", "Accurate to about one minute.")
                    item("Moon images", "Calculated for each moment from the LRO/LROC lunar map (NASA Scientific Visualization Studio). They also show libration, the Moon’s slight wobble: in the main window as seen from your location, in the widget as seen from the center of the Earth.")
                    item("Times", "All times use the time zone set in macOS.")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6, content: content)
                .padding(.leading, 30)
        }
    }

    private func item(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        Text("\(Text(title).bold()): \(Text(text))")
            .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().monospacedDigit()
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
