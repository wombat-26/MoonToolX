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

        Window("Widget-Vorschau", id: "widget-preview") {
            WidgetPreview()
        }
        .windowResizability(.contentSize)
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
                ZStack {
                    MoonDisc(imageName: shown.imageName, glow: 0.28, distanceKm: shown.distanceKm)
                        .id(shown.imageName)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: shown.distanceKm)
                }
                .frame(width: 300, height: 300)
                Label(shown.phase.name, systemImage: shown.phase.symbolName)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text(subtitle(for: shown))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("VERLAUF ±14 TAGE · KLICK ZEIGT DEN TAG FÜR 3 SEKUNDEN")
                            .font(.caption.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        DistanceChart(samples: context.samples,
                                      apsides: context.apsides(in: (context.samples.first?.date ?? minuteState.date)...(context.samples.last?.date ?? minuteState.date)),
                                      now: minuteState.date,
                                      currentKm: minuteState.distanceKm,
                                      highlight: preview?.date,
                                      highlightKm: preview.flatMap { calculator.distance(at: $0.date) },
                                      onSelect: onSelect)
                            .frame(height: 170)
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
                        Text("ENTFERNUNG ERDE–MOND (MITTELPUNKTE)")
                            .font(.caption.weight(.semibold))
                            .tracking(1)
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
            row("Mondhöhe", Fmt.altitude(topo.altitudeDeg), symbol: "arrow.up.and.down")
                .help("Höhe des Mondmittelpunkts über dem Horizont am Mac-Standort, ohne Lichtbrechung der Atmosphäre.")
        } else if location.status == .denied {
            row(title, "kein Zugriff auf die Ortungsdienste", symbol: "location.slash")
                .help("Erlauben Sie MoonToolX den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit › Ortungsdienste.")
        } else {
            row(title, "Standort wird ermittelt …", symbol: "location")
        }
    }

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
        GridRow {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }
}

// MARK: - Widget-Vorschau
/// Zeigt die drei Widget-Größen (macOS-Maße: 170×170, 364×170, 364×382 pt).
/// Aktualisiert wie das echte Widget: wenn die angezeigte km-Zahl umspringt, spätestens jede Minute.
struct WidgetPreview: View {
    private let calculator = MoonCalculator()
    @State private var context: MoonContext?

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
        .task {
            while !Task.isCancelled, let calculator {
                context = calculator.context(around: Date())
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
