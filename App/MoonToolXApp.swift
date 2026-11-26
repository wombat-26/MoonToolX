import SwiftUI
import WidgetKit

@main
struct MoonToolXApp: App {
    var body: some Scene {
        WindowGroup("MoonToolX") {
            ContentView()
                .frame(width: 920, height: 640)     // feste Fenstergröße
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) { HelpMenuButton() }
        }

        Window("MoonToolX-Kurzanleitung", id: "help") {
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

        Window("Widget-Vorschau", id: "widget-preview") {
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
    var title: String { isPast ? "Rückblick" : "Vorschau" }
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
                        ContentUnavailableView("Außerhalb der Ephemeride",
                                               systemImage: "calendar.badge.exclamationmark",
                                               description: Text("Die eingebaute JPL-Ephemeride deckt 2020 bis 2099 ab."))
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
                ContentUnavailableView("Ephemeride fehlt", systemImage: "exclamationmark.triangle",
                                       description: Text("moon_de440.bin ist nicht im App-Bundle."))
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
                .accessibilityLabel(sky.map { "Mond wie am Himmel, um \(Int(abs($0.skyRotationDeg).rounded())) Grad gedreht" } ?? "Mond, Norden oben")
                if topo != nil {
                    Picker("Ansicht", selection: $skyView) {
                        Text("Norden oben").tag(false)
                        Text("Wie am Himmel").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()            // feste Eigengröße: Segmente springen nicht bei Vorschau/Neuzeichnen
                    .help("„Wie am Himmel“ dreht das Mondbild so, wie Sie den Mond an Ihrem Standort sehen: Zenit oben.")
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
                Text("Scheinbarer Durchmesser: \(Fmt.arcmin(MoonCalculator.apparentDiameterArcmin(distanceKm: topo?.distanceKm ?? shown.distanceKm))) Bogenminuten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help(topo != nil ? "Vom Standort aus gesehen" : "Vom Erdmittelpunkt aus gesehen")
                if let magnitude = calculator.apparentMagnitude(at: shown.date, observer: location.observer) {
                    Text("Helligkeit: \(Fmt.magnitude(magnitude)) mag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Scheinbare Helligkeit in Magnituden, ohne Abschwächung durch die Atmosphäre. Je kleiner die Zahl, desto heller: Vollmond etwa −12,7 mag, Halbmond etwa −10 mag.")
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
                            .frame(height: 150)
                        ChartLegend()
                        }
                        .padding(4)
                    } label: {
                        Text("Verlauf ±14 Tage")
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
                Text("Ephemeride: JPL DE440 (2020–2099) · Mondbild: NASA SVS, LRO/LROC · Zeiten in Ortszeit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
    }

    private func skyCaption(_ t: TopocentricMoon) -> String {
        let angle = Int(abs(t.skyRotationDeg).rounded())
        // „unter dem Horizont“ steht bereits in der Sichtbarkeitszeile
        return "Zenit oben · gegenüber „Norden oben“ um \(angle)° gedreht"
    }

    private func subtitle(for state: MoonState) -> String {
        var parts = ["\(Fmt.percent(state.illuminatedFraction)) beleuchtet"]
        if let age = context?.age(at: state.date) {
            parts.append("Mondalter \(Fmt.days(age)) Tage")
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
                        Text("Aufgang"); Text("Höchster Stand"); Text("Untergang")
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
            if let set = pass.set { return "Sichtbar, noch \(duration(set.timeIntervalSince(now)))" }
            return "Sichtbar, geht vorerst nicht unter"
        }
        if let rise = pass.rise { return "Unter dem Horizont, Aufgang in \(duration(rise.timeIntervalSince(now)))" }
        return "Bleibt vorerst unter dem Horizont"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
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
        HStack(spacing: 14) {
            item("Entfernung") { Capsule().fill(Palette.line(scheme)).frame(width: 14, height: 2.5) }
            item("Jetzt") { Circle().fill(Palette.marker(scheme)).frame(width: 7, height: 7) }
            item("Perigäum / Apogäum") { Circle().fill(.secondary).frame(width: 5, height: 5) }
            Spacer(minLength: 8)
            Text("Klick zeigt den Tag für 3 Sekunden")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
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
            .help("\(label.explanation), \(Fmt.eventDate(label.syzygy.date)). Definition nach Richard Nolle.")
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
                        Text("Entfernung Erde–Mond (Mittelpunkte)")
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
                            Text("\(preview.title) \(Fmt.eventDate(preview.date)) · zurück zu jetzt in \(left) s")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Palette.preview(scheme))
                                .monospacedDigit()
                        } else {
                            Text("Stand \(state.date.formatted(.dateTime.hour().minute().second())) · gerundet \(Fmt.km(state.distanceKm)) km")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        row("Änderung", "\(Fmt.trend(state)) mit \(Fmt.speed(state.radialVelocityKmS))", symbol: Fmt.trendSymbol(state))
                        row("Lichtlaufzeit", Fmt.seconds(state.lightTimeSeconds), symbol: "light.beacon.max")
                        row("Oberfläche – Oberfläche", "\(Fmt.km(state.surfaceDistanceKm)) km (mittlere Radien)", symbol: "ruler")
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
        let title = "Entfernung von Ihrem Standort"
        if let observer = location.observer, let topo = calculator.topocentric(at: date, observer: observer) {
            row(title, "\(Fmt.km(topo.distanceKm)) km", symbol: "location")
                .help("Abstand vom Mac-Standort zum Mondmittelpunkt. Je höher der Mond steht, desto kleiner ist er im Vergleich zum Abstand der Mittelpunkte, um bis zu einen Erdradius (etwa 6.400 km).")
            row("Mondhöhe · Richtung",
                "\(Fmt.altitude(topo.altitudeDeg)) · \(Fmt.compass(topo.azimuthDeg)) (\(Int(topo.azimuthDeg.rounded()) % 360)°)") {
                HorizonArrow(up: topo.altitudeDeg >= 0)
            }
                .help("Höhe des Mondmittelpunkts über (+) oder unter (−) dem Horizont am Mac-Standort, ohne Lichtbrechung der Atmosphäre, und Himmelsrichtung mit Azimut (von Nord über Ost).")
        } else if location.status == .denied {
            row(title, "kein Zugriff auf die Ortungsdienste", symbol: "location.slash")
                .help("Erlauben Sie MoonToolX den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit › Ortungsdienste.")
        } else {
            row(title, "Standort wird ermittelt …", symbol: "location")
        }
    }

    /// Icon in fester Breite, damit alle Beschriftungen bündig dahinter beginnen
    private func row<Icon: View>(_ title: String, _ value: String, @ViewBuilder icon: () -> Icon) -> some View {
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

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
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
            .accessibilityLabel(up ? "über dem Horizont" : "unter dem Horizont")
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
