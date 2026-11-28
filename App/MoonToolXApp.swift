import SwiftUI
import WidgetKit

@main
struct MoonToolXApp: App {
    var body: some Scene {
        WindowGroup("MoonToolX") {
            ContentView()
                .frame(width: 920, height: 720)     // feste Fenstergröße, Platz für Vorschau mit Supermond-Plakette
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) { HelpMenuButton() }
        }

        Window("MoonToolX Quick Guide", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        // Hilfe nicht über dem Hauptfenster öffnen (Human Interface Guidelines), sondern daneben –
        // bei jedem Öffnen neu, auch wenn das Hauptfenster inzwischen verschoben wurde
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { content, context in
            // feste Größe statt sizeThatFits: die ScrollView meldet sonst eine viel zu große Breite
            let size = HelpView.windowSize
            let main = MainActor.assumeIsolated { SideWindowPlacement.mainWindowFrame() }
            return WindowPlacement(SideWindowPlacement.position(for: size, beside: main,
                                                                 in: context.defaultDisplay.visibleRect),
                                   size: size)
        }

        Window("Widget Preview", id: "widget-preview") {
            WidgetPreview()
        }
        .windowResizability(.contentSize)
    }
}

/// Startposition für Nebenfenster (Kurzanleitung): neben dem Hauptfenster statt darüber.
/// Rechts daneben, sonst links daneben, sonst am rechten Bildschirmrand; oben bündig mit dem Hauptfenster.
/// Koordinaten wie bei SwiftUI-Fensterplatzierung: Ursprung oben links.
enum SideWindowPlacement {
    static let gap: CGFloat = 16

    /// Rahmen des Hauptfensters in Bildschirmkoordinaten mit Ursprung oben links
    @MainActor
    static func mainWindowFrame() -> CGRect? {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "MoonToolX" }),
              let primary = NSScreen.screens.first else { return nil }
        let f = window.frame
        return CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
    }

    static func position(for size: CGSize, beside main: CGRect?, in screen: CGRect) -> CGPoint {
        guard let main else {
            return CGPoint(x: screen.maxX - size.width - gap, y: screen.minY + gap)
        }
        let x: CGFloat
        if main.maxX + gap + size.width <= screen.maxX {
            x = main.maxX + gap                                  // rechts daneben
        } else if main.minX - gap - size.width >= screen.minX {
            x = main.minX - gap - size.width                     // links daneben
        } else {
            x = screen.maxX - size.width                         // am rechten Rand, möglichst wenig Überdeckung
        }
        let y = min(max(main.minY, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}

/// Startpunkt für Sekundentakt, an der vollen Sekunde ausgerichtet.
private var nextFullSecond: Date { Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970)) }

// MARK: - Hauptfenster
// Performance: Nur die Zahlen laufen im Sekundentakt (kleine Textansicht).
// Mondbild, Diagramm und Termine werden einmal pro Minute neu aufgebaut.

/// Per Klick ins Diagramm gewählter Zeitpunkt, für 3 Sekunden angezeigt.
struct PreviewSelection: Equatable {
    let date: Date
    let until: Date

    /// Klick links von „jetzt“ ist ein Rückblick, rechts davon eine Vorschau.
    var isPast: Bool { date < until.addingTimeInterval(-3) }
    var title: String { isPast ? String(localized: "Look Back") : String(localized: "Preview") }
    var symbol: String { isPast ? "clock.arrow.circlepath" : "eye" }
}

struct ContentView: View {
    private let calculator = MoonCalculator()
    @State private var context: MoonContext?
    @State private var preview: PreviewSelection?
    @State private var location = LocationModel()

    var body: some View {
        ZStack {
            SkyBackground().ignoresSafeArea()
            if let calculator {
                TimelineView(.everyMinute) { minute in
                    if let state = calculator.state(at: minute.date) {
                        Dashboard(calculator: calculator, location: location, minuteState: state, context: context, preview: preview) { date in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                preview = PreviewSelection(date: date, until: Date().addingTimeInterval(3))
                            }
                        }
                    } else {
                        ContentUnavailableView("Outside the ephemeris range",
                                               systemImage: "calendar.badge.exclamationmark",
                                               description: Text("The built-in JPL ephemeris covers 2020 to 2099."))
                    }
                }
                .task { location.start() }
                .task {
                    // nach einem Update laufen sonst evtl. noch Timelines der alten Widget-Erweiterung
                    WidgetCenter.shared.reloadAllTimelines()
                    while !Task.isCancelled {
                        context = calculator.context(around: Date())
                        try? await Task.sleep(for: .seconds(600))
                    }
                }
                .task(id: preview) {
                    // jeder neue Klick startet die 3 Sekunden neu
                    guard preview != nil else { return }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { preview = nil }
                }
            } else {
                ContentUnavailableView("Ephemeris missing", systemImage: "exclamationmark.triangle",
                                       description: Text("moon_de440.bin is not in the app bundle."))
            }
        }
    }
}

private struct Dashboard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Mondbild „Norden oben“ (false) oder „Wie am Himmel“ mit Zenit oben (true)
    @AppStorage("moonSkyView") private var skyView = false
    let calculator: MoonCalculator
    let location: LocationModel
    /// Zustand zur vollen Minute: für Bild, Phase, Diagramm und Termine
    let minuteState: MoonState
    let context: MoonContext?
    let preview: PreviewSelection?
    let onSelect: (Date) -> Void

    /// Angezeigter Zustand: Vorschau, sonst aktuell
    private var shown: MoonState {
        preview.flatMap { calculator.state(at: $0.date) } ?? minuteState
    }

    var body: some View {
        let shown = shown
        HStack(alignment: .top, spacing: 32) {
            VStack(spacing: 14) {
                let topo = location.observer.flatMap { calculator.topocentric(at: shown.date, observer: $0) }
                let sky = skyView ? topo : nil
                ZStack {
                    // Phase und Libration vom Standort aus, ohne Standort vom Erdmittelpunkt aus
                    LiveMoonDisc(aspect: calculator.aspect(at: shown.date, observer: location.observer),
                                 glow: 0.28, distanceKm: shown.distanceKm)
                        .animation(.easeInOut(duration: 0.35), value: shown.distanceKm)
                    if sky != nil {
                        // Markierung am Mond-Nordpol, dreht mit
                        Text("N")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.marker(scheme))
                            .offset(y: -(150 * CGFloat(min(1, 356_000 / shown.distanceKm)) + 4))
                            .transition(.opacity)
                    }
                }
                .frame(width: 300, height: 300)
                .rotationEffect(.degrees(-(sky?.skyRotationDeg ?? 0)))
                .opacity((sky?.altitudeDeg ?? 1) < 0 ? 0.5 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: skyView)
                .accessibilityLabel(sky.map { String(localized: "Moon as in the sky, rotated \(Int(abs($0.skyRotationDeg).rounded())) degrees") } ?? String(localized: "Moon, north up"))
                if topo != nil {
                    Picker("View", selection: $skyView) {
                        Text("North Up").tag(false)
                        Text("As in the Sky").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()            // feste Eigengröße: Segmente springen nicht bei Vorschau/Neuzeichnen
                    .help("“As in the Sky” rotates the moon image the way you see the Moon from your location: zenith up.")
                }
                Label(shown.phase.name, systemImage: shown.phase.symbolName)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text(subtitle(for: shown))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let sky {
                    Text(skyCaption(sky))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if let observer = location.observer, let pass = calculator.moonPass(at: shown.date, observer: observer) {
                    MoonPassView(pass: pass, now: shown.date)
                }
                Text("Apparent diameter: \(Fmt.arcmin(MoonCalculator.apparentDiameterArcmin(distanceKm: topo?.distanceKm ?? shown.distanceKm))) arcminutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help(topo != nil ? Text("Seen from your location") : Text("Seen from Earth’s center"))
                if let magnitude = calculator.apparentMagnitude(at: shown.date, observer: location.observer) {
                    Text("Brightness: \(Fmt.magnitude(magnitude)) mag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Apparent brightness in magnitudes, without dimming by the atmosphere. The smaller the number, the brighter: full moon about −12.7 mag, half moon about −10 mag.")
                }
                if let label = context?.distanceLabel(for: shown) {
                    DistanceBadge(label: label)
                        .transition(.opacity)
                }
                if let preview {
                    Label("\(preview.title): \(Fmt.eventDate(preview.date))", systemImage: preview.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.preview(scheme))
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 16) {
                LiveDistancePanel(calculator: calculator, location: location, preview: preview)

                if let context {
                    // Box nach HIG: Titel darüber (Satzschreibung), ruhige Fläche je nach Hell/Dunkel
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                        DistanceChart(samples: context.samples,
                                      apsides: context.apsides(in: (context.samples.first?.date ?? minuteState.date)...(context.samples.last?.date ?? minuteState.date)),
                                      now: minuteState.date,
                                      currentKm: minuteState.distanceKm,
                                      highlight: preview?.date,
                                      highlightKm: preview.flatMap { calculator.distance(at: $0.date) },
                                      onSelect: onSelect)
                            .frame(height: 220)
                        ChartLegend()
                        }
                        .padding(4)
                    } label: {
                        Text("Distance, ±14 days")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            event(context.next(.newMoon, after: minuteState.date))
                            event(context.next(.firstQuarter, after: minuteState.date))
                            event(context.next(.perigee, after: minuteState.date), distance: true)
                        }
                        GridRow {
                            event(context.next(.fullMoon, after: minuteState.date))
                            event(context.next(.lastQuarter, after: minuteState.date))
                            event(context.next(.apogee, after: minuteState.date), distance: true)
                        }
                    }
                }

                Spacer(minLength: 0)
                Text("Ephemeris: JPL DE440 (2020–2099) · Moon image: NASA SVS, LRO/LROC · Times in local time")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
    }

    private func skyCaption(_ t: TopocentricMoon) -> String {
        let angle = Int(abs(t.skyRotationDeg).rounded())
        // „unter dem Horizont“ steht bereits in der Sichtbarkeitszeile
        return String(localized: "Zenith up · rotated \(angle)° from “North Up”")
    }

    private func subtitle(for state: MoonState) -> String {
        var parts = [String(localized: "\(Fmt.percent(state.illuminatedFraction)) illuminated")]
        if let age = context?.age(at: state.date) {
            parts.append(String(localized: "Moon age \(Fmt.days(age)) days"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func event(_ e: MoonEvent?, distance: Bool = false) -> some View {
        if let e {
            EventRow(event: e, showDistance: distance, font: .callout)
        } else {
            Text("–")
        }
    }
}

/// Auf- und Untergang am Standort, höchster Stand und Sichtbarkeit
private struct MoonPassView: View {
    let pass: MoonPass
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(visibility)
                .font(.callout.weight(.medium))
                .monospacedDigit()
            if !(pass.noRiseOrSet && !pass.isUp) {
                Grid(horizontalSpacing: 18, verticalSpacing: 1) {
                    GridRow {
                        Text("Moonrise"); Text("Highest"); Text("Moonset")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    GridRow {
                        Text(time(pass.rise)); Text(time(pass.transit)); Text(time(pass.set))
                    }
                    .font(.callout)
                    GridRow {
                        Text(direction(pass.riseAzimuthDeg))
                        Text(pass.transitAltitudeDeg.map { "\(Fmt.altitude($0)) · \(direction(pass.transitAzimuthDeg))" } ?? "–")
                        Text(direction(pass.setAzimuthDeg))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
        }
    }

    private var visibility: String {
        if pass.isUp {
            if let set = pass.set { return String(localized: "Visible, \(duration(set.timeIntervalSince(now))) left") }
            return String(localized: "Visible, won’t set for now")
        }
        if let rise = pass.rise { return String(localized: "Below the horizon, rises in \(duration(rise.timeIntervalSince(now)))") }
        return String(localized: "Stays below the horizon for now")
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? String(localized: "\(minutes / 60) hr \(minutes % 60) min") : String(localized: "\(minutes) min")
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "–" }
        return Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func direction(_ azimuth: Double?) -> String {
        azimuth.map { Fmt.compass($0) } ?? "–"
    }
}

/// Legende des Entfernungsdiagramms mit Klick-Hilfe
private struct ChartLegend: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Passt der Klick-Hinweis nicht neben die Legende (längere Sprachen), steht er darunter
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                items
                Spacer(minLength: 8)
                hint
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 14) { items }
                hint
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder private var items: some View {
        item("Distance") { Capsule().fill(Palette.line(scheme)).frame(width: 14, height: 2.5) }
        item("Now") { Circle().fill(Palette.marker(scheme)).frame(width: 7, height: 7) }
        item("Perigee / apogee") { Circle().fill(.secondary).frame(width: 5, height: 5) }
    }

    private var hint: some View {
        Text("Click to show that moment for 3 seconds").fixedSize()
    }

    private func item<Swatch: View>(_ title: LocalizedStringKey, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 14)
            Text(title)
        }
    }
}

/// Kennzeichnung Supermond / Mikromond (nur bei Vollmond oder Neumond)
private struct DistanceBadge: View {
    @Environment(\.colorScheme) private var scheme
    let label: DistanceLabel

    var body: some View {
        let tint: Color = label.isSuper ? (scheme == .dark ? .orange : Color(red: 0.80, green: 0.38, blue: 0.0))
                                        : (scheme == .dark ? .cyan : Color(red: 0.0, green: 0.45, blue: 0.60))
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 2) {
            Label("\(label.title) · \(Fmt.km(label.syzygy.distanceKm)) km", systemImage: label.symbolName)
                .font(.callout.weight(.semibold))
            Text("\(label.syzygy.kind.title) \(Fmt.eventDate(label.syzygy.date))")
                .font(.caption.weight(.medium))
                .opacity(0.85)
        }
        .monospacedDigit()
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(shape.fill(tint.opacity(0.14)))
        .overlay(shape.strokeBorder(tint.opacity(0.35)))
            .help("\(label.explanation), \(Fmt.eventDate(label.syzygy.date)). Definition by Richard Nolle.")
    }
}

/// Der einzige Teil des Hauptfensters, der jede Sekunde neu gezeichnet wird.
private struct LiveDistancePanel: View {
    @Environment(\.colorScheme) private var scheme
    let calculator: MoonCalculator
    let location: LocationModel
    let preview: PreviewSelection?

    var body: some View {
        TimelineView(.periodic(from: nextFullSecond, by: 1)) { timeline in
            if let state = calculator.state(at: preview?.date ?? timeline.date) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Earth–Moon distance (centers)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .bottom, spacing: 10) {
                            SplitFlapBoard(text: Fmt.kmMeters(state.distanceKm))
                            Text("km")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                        .padding(.vertical, 4)
                        if let preview {
                            let left = max(1, Int(ceil(preview.until.timeIntervalSince(timeline.date))))
                            Text("\(preview.title) \(Fmt.eventDate(preview.date)) · back to now in \(left) s")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Palette.preview(scheme))
                                .monospacedDigit()
                        } else {
                            Text("As of \(state.date.formatted(.dateTime.hour().minute().second())) · rounded \(Fmt.km(state.distanceKm)) km")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        row("Change", String(localized: "\(Fmt.trend(state)) at \(Fmt.speed(state.radialVelocityKmS))"), symbol: Fmt.trendSymbol(state))
                        row("Light travel time", Fmt.seconds(state.lightTimeSeconds), symbol: "light.beacon.max")
                        row("Surface to surface", String(localized: "\(Fmt.km(state.surfaceDistanceKm)) km (mean radii)"), symbol: "ruler")
                        observerRows(at: state.date)
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// Entfernung vom Standort und Mondhöhe, sobald der Mac-Standort bekannt ist.
    @ViewBuilder
    private func observerRows(at date: Date) -> some View {
        let title: LocalizedStringKey = "Distance from your location"
        if let observer = location.observer, let topo = calculator.topocentric(at: date, observer: observer) {
            row(title, "\(Fmt.km(topo.distanceKm)) km", symbol: "location")
                .help("Distance from your Mac’s location to the center of the Moon. The higher the Moon, the smaller it is compared with the distance between the centers, by up to one Earth radius (about 6,400 km).")
            row("Altitude · direction",
                "\(Fmt.altitude(topo.altitudeDeg)) · \(Fmt.compass(topo.azimuthDeg)) (\(Int(topo.azimuthDeg.rounded()) % 360)°)") {
                HorizonArrow(up: topo.altitudeDeg >= 0)
            }
                .help("Altitude of the Moon’s center above (+) or below (−) the horizon at your Mac’s location, without atmospheric refraction, and compass direction with azimuth (from north through east).")
        } else if location.status == .denied {
            row(title, String(localized: "No access to Location Services"), symbol: "location.slash")
                .help("Allow MoonToolX access in System Settings under Privacy & Security › Location Services.")
        } else {
            row(title, String(localized: "Determining location…"), symbol: "location")
        }
    }

    /// Icon in fester Breite, damit alle Beschriftungen bündig dahinter beginnen
    private func row<Icon: View>(_ title: LocalizedStringKey, _ value: String, @ViewBuilder icon: () -> Icon) -> some View {
        GridRow {
            HStack(spacing: 6) {
                icon().frame(width: 18, alignment: .center)
                Text(title)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String, symbol: String) -> some View {
        row(title, value) { Image(systemName: symbol) }
    }
}

/// Pfeil vom Strich weg, Strich = Horizont: ↥ Mond über dem Horizont, ↧ darunter.
/// Selbst gezeichnet, weil SF Symbols keine „Pfeil vom Strich weg“-Variante für oben/unten hat.
private struct HorizonArrow: View {
    let up: Bool

    var body: some View {
        ArrowFromBar()
            .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .scaleEffect(x: 1, y: up ? 1 : -1)
            .frame(width: 12, height: 13)
            .accessibilityLabel(up ? Text("above the horizon") : Text("below the horizon"))
    }

    /// ↥: Strich unten, Pfeil nach oben
    private struct ArrowFromBar: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let bar = r.maxY - r.height * 0.06, tip = r.minY + r.height * 0.08
            p.move(to: CGPoint(x: r.minX + r.width * 0.08, y: bar))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.08, y: bar))
            p.move(to: CGPoint(x: r.midX, y: bar))
            p.addLine(to: CGPoint(x: r.midX, y: tip))
            p.move(to: CGPoint(x: r.midX - r.width * 0.32, y: tip + r.height * 0.32))
            p.addLine(to: CGPoint(x: r.midX, y: tip))
            p.addLine(to: CGPoint(x: r.midX + r.width * 0.32, y: tip + r.height * 0.32))
            return p
        }
    }
}

// MARK: - Widget-Vorschau
/// Zeigt die drei Widget-Größen (macOS-Maße: 170×170, 364×170, 364×382 pt).
/// Aktualisiert wie das echte Widget: wenn die angezeigte km-Zahl umspringt, spätestens jede Minute.
struct WidgetPreview: View {
    private let calculator = MoonCalculator()
    @State private var context: MoonContext?
    /// Mondbild wie im Widget: vom Erdmittelpunkt aus, alle zehn Minuten neu
    @State private var moonImage: CGImage?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                tile(width: 170, height: 170) { SmallMoonView(state: $0, context: context) }
                tile(width: 364, height: 170) { MediumMoonView(state: $0, context: context) }
            }
            tile(width: 364, height: 382) { LargeMoonView(state: $0, context: context) }
        }
        .padding(24)
        .background(.background.secondary)
        .environment(\.moonImage, moonImage)
        .task {
            while !Task.isCancelled, let calculator {
                context = calculator.context(around: Date())
                if let aspect = calculator.aspect(at: Date()) {
                    moonImage = await Task.detached {
                        MoonRenderer.shared?.image(aspect: aspect, size: MoonRenderer.widgetImageSize)
                    }.value
                }
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    private func tile<Content: View>(width: CGFloat, height: CGFloat,
                                     @ViewBuilder content: @escaping (MoonState) -> Content) -> some View {
        ZStack {
            SkyBackground()
            if let calculator {
                TimelineView(KilometerTickSchedule(calculator: calculator)) { timeline in
                    if let state = calculator.state(at: timeline.date) {
                        content(state).padding(16)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Zeitplan wie im Widget: Einträge nur, wenn die gerundete km-Zahl wechselt, sonst jede Minute.
struct KilometerTickSchedule: TimelineSchedule {
    let calculator: MoonCalculator

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var t = floor(startDate.timeIntervalSince1970)
        var lastKm = calculator.distance(at: Date(timeIntervalSince1970: t)).map { Int($0.rounded()) }
        var lastEntry = t
        var first = true
        return AnyIterator {
            if first { first = false; return Date(timeIntervalSince1970: t) }
            while true {
                t += 1
                let km = calculator.distance(at: Date(timeIntervalSince1970: t)).map { Int($0.rounded()) }
                if km != lastKm || t - lastEntry >= 60 {
                    lastKm = km
                    lastEntry = t
                    return Date(timeIntervalSince1970: t)
                }
            }
        }
    }
}
