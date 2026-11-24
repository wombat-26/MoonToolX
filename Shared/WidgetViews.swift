import SwiftUI
import WidgetKit

// Widget-Ansichten (auch von der App für die Widget-Vorschau genutzt)

/// Phasenname; bei Vollmond oder Neumond in Erdnähe/-ferne stattdessen Supermond, Mikromond usw.
func phaseTitle(_ state: MoonState, _ context: MoonContext?) -> String {
    context?.distanceLabel(for: state)?.title ?? state.phase.name
}

struct WidgetMoon: View {
    let state: MoonState
    var body: some View {
        MoonDisc(imageName: state.imageName, distanceKm: state.distanceKm)
    }
}

struct DistanceText: View {
    let state: MoonState
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(Fmt.km(state.distanceKm))
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text("km")
                .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct TrendText: View {
    let state: MoonState
    var body: some View {
        Label {
            Text("\(Fmt.trend(state)) · \(Fmt.speed(state.radialVelocityKmS))")
        } icon: {
            Image(systemName: Fmt.trendSymbol(state))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

struct SmallMoonView: View {
    let state: MoonState
    var context: MoonContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                WidgetMoon(state: state)
                    .frame(width: 66, height: 66)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.percent(state.illuminatedFraction))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(phaseTitle(state, context))
                        .font(.system(size: 10, weight: context?.distanceLabel(for: state) == nil ? .regular : .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 2)
            SectionLabel(text: "Entfernung")
            DistanceText(state: state, size: 25)
            TrendText(state: state)
                .font(.system(size: 9.5))
        }
    }
}

struct MediumMoonView: View {
    let state: MoonState
    let context: MoonContext?

    var body: some View {
        HStack(spacing: 14) {
            WidgetMoon(state: state)
                .frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "Entfernung Erde–Mond")
                DistanceText(state: state, size: 32)
                TrendText(state: state)
                    .font(.system(size: 11))
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Image(systemName: state.phase.symbolName)
                    Text("\(phaseTitle(state, context)) · \(Fmt.percent(state.illuminatedFraction))")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                if let next = context?.nextPrincipalPhase(after: state.date) {
                    Text("\(next.kind.title): \(Fmt.eventDate(next.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}

struct LargeMoonView: View {
    let state: MoonState
    let context: MoonContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                WidgetMoon(state: state)
                    .frame(width: 124, height: 124)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Entfernung Erde–Mond")
                    DistanceText(state: state, size: 34)
                    TrendText(state: state)
                        .font(.system(size: 11))
                    Spacer(minLength: 2)
                    HStack(spacing: 5) {
                        Image(systemName: state.phase.symbolName)
                        Text("\(phaseTitle(state, context)) · \(Fmt.percent(state.illuminatedFraction))")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    Group {
                        if let age = context?.age(at: state.date) {
                            Text("Mondalter \(Fmt.days(age)) Tage · Licht \(Fmt.seconds(state.lightTimeSeconds))")
                        } else {
                            Text("Lichtlaufzeit \(Fmt.seconds(state.lightTimeSeconds))")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            if let context {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Verlauf ±14 Tage")
                    DistanceSparkline(samples: context.samples,
                                      apsides: context.apsides(in: (context.samples.first?.date ?? state.date)...(context.samples.last?.date ?? state.date)),
                                      now: state.date,
                                      currentKm: state.distanceKm)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: .infinity)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        cell(context.next(.fullMoon, after: state.date), distance: false)
                        cell(context.next(.newMoon, after: state.date), distance: false)
                    }
                    GridRow {
                        cell(context.next(.perigee, after: state.date), distance: true)
                        cell(context.next(.apogee, after: state.date), distance: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ event: MoonEvent?, distance: Bool) -> some View {
        if let event {
            EventRow(event: event, showDistance: distance, font: .system(size: 10.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
