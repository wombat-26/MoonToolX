import WidgetKit
import SwiftUI

@main
struct MoonToolXWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoonDistanceWidget()
    }
}

struct MoonDistanceWidget: Widget {
    let kind = "MoonToolXDistance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoonProvider()) { entry in
            MoonWidgetView(entry: entry)
                .containerBackground(for: .widget) { SkyBackground() }
        }
        .configurationDisplayName("MoonToolX")
        .description("Entfernung Erde–Mond, sekundengenau berechnet, mit aktueller Mondphase.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}

// MARK: - Timeline

struct MoonEntry: TimelineEntry {
    let date: Date
    let state: MoonState?
    let context: MoonContext?
    /// Mondbild mit Phase und Libration, vom Erdmittelpunkt aus (das Widget kennt keinen Standort)
    let moonImage: CGImage?
}

/// WidgetKit zeichnet nicht jede Sekunde neu. Deshalb berechnet der Provider im Sekundenraster
/// voraus, wann die angezeigte km-Zahl umspringt, und legt genau dort einen Eintrag an
/// (spätestens alle 60 s ein Eintrag für Phase und Beleuchtung).
/// WidgetKit rendert und archiviert alle Einträge vorab; das Archiv einer Timeline ist begrenzt.
/// Deshalb endet eine Timeline nach höchstens 60 Minuten oder `maxEntries` Einträgen.
/// Das Mondbild wird je Timeline einmal berechnet, für ihre Mitte: In 30 Minuten ändern sich
/// Phase und Libration um höchstens etwa 0,3°.
struct MoonProvider: TimelineProvider {
    static let horizon = 3600
    static let maxEntries = 100

    func placeholder(in context: Context) -> MoonEntry {
        let calculator = MoonCalculator()
        return Self.entry(at: Date(), calculator: calculator, context: nil,
                          image: Self.moonImage(at: Date(), calculator: calculator))
    }

    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        let now = Date()
        let calculator = MoonCalculator()
        completion(Self.entry(at: now, calculator: calculator, context: calculator?.context(around: now),
                              image: Self.moonImage(at: now, calculator: calculator)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        guard let calculator = MoonCalculator() else {
            completion(Timeline(entries: [MoonEntry(date: start, state: nil, context: nil, moonImage: nil)],
                                policy: .after(start.addingTimeInterval(3600))))
            return
        }
        let moonContext = calculator.context(around: start)
        let image = Self.moonImage(at: start.addingTimeInterval(TimeInterval(Self.horizon / 2)), calculator: calculator)
        var entries: [MoonEntry] = []
        var lastKm: Int?
        var lastEntry = start
        var end = start.addingTimeInterval(TimeInterval(Self.horizon))

        for second in 0...Self.horizon {
            let date = start.addingTimeInterval(TimeInterval(second))
            guard let km = calculator.distance(at: date).map({ Int($0.rounded()) }) else { break }
            if km != lastKm || date.timeIntervalSince(lastEntry) >= 60 {
                if entries.count == Self.maxEntries { end = date; break }
                entries.append(Self.entry(at: date, calculator: calculator, context: moonContext, image: image))
                lastKm = km
                lastEntry = date
            }
        }
        completion(Timeline(entries: entries, policy: .after(end)))
    }

    static func entry(at date: Date, calculator: MoonCalculator?, context: MoonContext?, image: CGImage?) -> MoonEntry {
        MoonEntry(date: date, state: calculator?.state(at: date), context: context, moonImage: image)
    }

    static func moonImage(at date: Date, calculator: MoonCalculator?) -> CGImage? {
        calculator?.aspect(at: date).flatMap {
            MoonRenderer.shared?.image(aspect: $0, size: MoonRenderer.widgetImageSize)
        }
    }

    /// Eintrag für die Xcode-Vorschau
    static func previewEntry() -> MoonEntry {
        let calculator = MoonCalculator()
        return entry(at: .now, calculator: calculator, context: calculator?.context(around: .now),
                     image: moonImage(at: .now, calculator: calculator))
    }
}

// MARK: - Ansichten

struct MoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoonEntry

    var body: some View {
        if let state = entry.state {
            Group {
                switch family {
                case .systemSmall: SmallMoonView(state: state, context: entry.context)
                case .systemMedium: MediumMoonView(state: state, context: entry.context)
                default: LargeMoonView(state: state, context: entry.context)
                }
            }
            .environment(\.moonImage, entry.moonImage)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.title)
                Text("Ephemeride nicht verfügbar (gültig 2020–2099)")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Klein", as: .systemSmall) {
    MoonDistanceWidget()
} timeline: {
    MoonProvider.previewEntry()
}

#Preview("Mittel", as: .systemMedium) {
    MoonDistanceWidget()
} timeline: {
    MoonProvider.previewEntry()
}

#Preview("Groß", as: .systemLarge) {
    MoonDistanceWidget()
} timeline: {
    MoonProvider.previewEntry()
}
