import SwiftUI
import Charts
import WidgetKit

// MARK: - Formatierung (folgt der Systemsprache, z. B. 362.490 km)

enum Fmt {
    static func km(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    static func kmMeters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)).grouping(.automatic))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func speed(_ kmS: Double) -> String {
        "\((abs(kmS) * 1000).formatted(.number.precision(.fractionLength(0)))) m/s"
    }

    static func days(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(1)))
    }

    static func seconds(_ s: Double) -> String {
        "\(s.formatted(.number.precision(.fractionLength(3)))) s"
    }

    static func eventDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).hour().minute())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.twoDigits).hour().minute())
    }

    static func trend(_ state: MoonState) -> String {
        state.radialVelocityKmS >= 0 ? "entfernt sich" : "nähert sich"
    }

    static func trendSymbol(_ state: MoonState) -> String {
        state.radialVelocityKmS >= 0 ? "arrow.up.right" : "arrow.down.right"
    }
}

// MARK: - Hintergrund (folgt dem System-Erscheinungsbild)

struct SkyBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if scheme == .dark { NightSky() } else { DaySky() }
    }
}

struct DaySky: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.78, green: 0.86, blue: 0.97), Color(red: 0.95, green: 0.97, blue: 1.0)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

enum Palette {
    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .cyan : Color(red: 0.10, green: 0.38, blue: 0.78)
    }
    static func marker(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .yellow : .orange
    }
    static func preview(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.80, green: 0.62, blue: 1.0) : .purple
    }
}

struct NightSky: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.20), Color(red: 0.01, green: 0.015, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { context, size in
                var rng = SeededGenerator(seed: 26)
                for _ in 0..<70 {
                    let x = Double.random(in: 0...1, using: &rng) * size.width
                    let y = Double.random(in: 0...1, using: &rng) * size.height
                    let r = Double.random(in: 0.3...1.1, using: &rng)
                    let a = Double.random(in: 0.15...0.6, using: &rng)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                 with: .color(.white.opacity(a)))
                }
            }
        }
    }
}

/// Deterministischer Zufall, damit die Sterne nicht bei jedem Rendern springen.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Mond

/// Vorgerendertes Phasenbild (NASA LRO/LROC-Karte, Lommel-Seeliger-Photometrie, Erdschein).
struct MoonDisc: View {
    @Environment(\.colorScheme) private var scheme
    let imageName: String
    var glow: Double = 0.22
    /// Entfernung in km: Die Scheibe wird wie die scheinbare Größe skaliert (∝ 1/Entfernung).
    var distanceKm: Double? = nil

    /// Volle Rahmengröße bei 356.000 km (nächstmöglicher Vollmond), kleiner bei größerer Entfernung:
    /// mittlere Entfernung ≈ 93 %, Apogäum ≈ 87 %.
    static func scale(for distanceKm: Double) -> CGFloat {
        CGFloat(min(1, 356_000 / distanceKm))
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .widgetAccentedRenderingMode(.fullColor)      // Foto bleibt auch im getönten/Glas-Modus farbig
            .aspectRatio(1, contentMode: .fit)
            .clipShape(Circle())
            .shadow(color: scheme == .dark ? .white.opacity(glow) : .black.opacity(0.28),
                    radius: scheme == .dark ? 10 : 6)
            .scaleEffect(distanceKm.map(Self.scale(for:)) ?? 1)
    }
}

// MARK: - Entfernungsverlauf

struct DistanceChart: View {
    @Environment(\.colorScheme) private var scheme
    let samples: [DistanceSample]
    let apsides: [MoonEvent]
    let now: Date
    let currentKm: Double
    var compact = false
    /// Vorschau-Zeitpunkt, im Diagramm markiert
    var highlight: Date? = nil
    var highlightKm: Double? = nil
    /// Klick ins Diagramm liefert den Zeitpunkt unter dem Mauszeiger
    var onSelect: ((Date) -> Void)? = nil

    var body: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("Zeit", s.date),
                         yStart: .value("Basis", yDomain.lowerBound),
                         yEnd: .value("Entfernung", s.distanceKm / 1000))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Palette.line(scheme).opacity(0.25), Palette.line(scheme).opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Zeit", s.date), y: .value("Entfernung", s.distanceKm / 1000))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Palette.line(scheme))
                    .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2))
            }
            ForEach(apsides) { a in
                PointMark(x: .value("Zeit", a.date), y: .value("Entfernung", a.distanceKm / 1000))
                    .symbolSize(compact ? 14 : 24)
                    .foregroundStyle(.secondary)
                    .annotation(position: a.kind == .perigee ? .bottom : .top, spacing: 2) {
                        Text(Fmt.km(a.distanceKm))
                            .font(.system(size: compact ? 8 : 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
            }
            RuleMark(x: .value("Jetzt", now))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Jetzt", now), y: .value("Entfernung", currentKm / 1000))
                .symbolSize(compact ? 36 : 60)
                .foregroundStyle(Palette.marker(scheme))
            if let highlight, let highlightKm {
                RuleMark(x: .value("Vorschau", highlight))
                    .foregroundStyle(Palette.preview(scheme))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("Vorschau", highlight), y: .value("Entfernung", highlightKm / 1000))
                    .symbolSize(compact ? 40 : 80)
                    .foregroundStyle(Palette.preview(scheme))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let onSelect, let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        onSelect(min(max(date, xDomain.lowerBound), xDomain.upperBound))
                    }
                    .pointerStyle(onSelect == nil ? nil : .link)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) Tsd.").font(.system(size: compact ? 8 : 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                    .font(.system(size: compact ? 8 : 10))
                    .foregroundStyle(Color.secondary)      // .secondary allein erbt hier die Akzentfarbe
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = samples.map { $0.distanceKm / 1000 }
        let lo = (values.min() ?? 356) - 4
        let hi = (values.max() ?? 407) + 4
        return lo...hi
    }

    private var xDomain: ClosedRange<Date> {
        (samples.first?.date ?? now)...(samples.last?.date ?? now)
    }
}

// MARK: - Ereigniszeile

struct EventRow: View {
    let event: MoonEvent
    var showDistance = false
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.kind.symbolName)
                .frame(width: 16)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.kind.title).foregroundStyle(.secondary)
                Text(showDistance ? "\(Fmt.shortDate(event.date)) · \(Fmt.km(event.distanceKm)) km" : Fmt.eventDate(event.date))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Schlanker Verlauf fürs Widget
// Ein einzelner Vektorpfad statt Swift Charts: Das Timeline-Archiv bleibt klein,
// weil WidgetKit jeden Eintrag vorab rendert und speichert.

struct DistanceSparkline: View {
    @Environment(\.colorScheme) private var scheme
    let samples: [DistanceSample]
    let apsides: [MoonEvent]
    let now: Date
    let currentKm: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pts = points(in: size)
            ZStack(alignment: .topLeading) {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Palette.line(scheme).opacity(0.28), Palette.line(scheme).opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }
                    .stroke(Palette.line(scheme), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                Path { p in
                    let x = xPos(now, size)
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                ForEach(apsides) { a in
                    let pt = CGPoint(x: xPos(a.date, size), y: yPos(a.distanceKm, size))
                    Circle().fill(.secondary).frame(width: 4, height: 4).position(pt)
                    Text(Fmt.km(a.distanceKm))
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(pt.x, 22), size.width - 22),
                                  y: a.kind == .perigee ? pt.y + 9 : pt.y - 9)
                }
                Circle()
                    .fill(Palette.marker(scheme))
                    .frame(width: 7, height: 7)
                    .position(x: xPos(now, size), y: yPos(currentKm, size))
            }
        }
    }

    private var range: (lo: Double, hi: Double, t0: Double, t1: Double) {
        let v = samples.map(\.distanceKm)
        return ((v.min() ?? 356_000) - 3_000, (v.max() ?? 407_000) + 3_000,
                samples.first?.date.timeIntervalSince1970 ?? 0, samples.last?.date.timeIntervalSince1970 ?? 1)
    }

    private func xPos(_ d: Date, _ size: CGSize) -> CGFloat {
        let r = range
        return CGFloat((d.timeIntervalSince1970 - r.t0) / max(r.t1 - r.t0, 1)) * size.width
    }

    private func yPos(_ km: Double, _ size: CGSize) -> CGFloat {
        let r = range
        return size.height * (1 - CGFloat((km - r.lo) / (r.hi - r.lo)))
    }

    private func points(in size: CGSize) -> [CGPoint] {
        stride(from: 0, to: samples.count, by: 2).map { i in
            CGPoint(x: xPos(samples[i].date, size), y: yPos(samples[i].distanceKm, size))
        }
    }
}
