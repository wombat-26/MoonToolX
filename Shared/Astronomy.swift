import Foundation
import simd

// MARK: - Zeit

/// Zeitskalen für die Ephemeride.
/// TT − UTC = 32,184 s + (TAI − UTC). TAI − UTC beträgt seit 01.01.2017 37 s
/// (bis heute keine weitere Schaltsekunde angekündigt). TDB weicht von TT um weniger als 2 ms ab.
enum AstroTime {
    static let ttMinusUTC: Double = 69.184
    static let jdUnixEpoch: Double = 2_440_587.5

    /// Julianisches Datum in TT (≈ TDB).
    static func julianDayTT(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + jdUnixEpoch + ttMinusUTC / 86_400
    }
}

// MARK: - Mond-Ephemeride (JPL DE421)

/// Geozentrischer Mond aus JPL DE421 als Tschebyschow-Reihen (ICRF, km).
/// Datei `moon_de421.bin`: 32 Byte Kopf, danach `setCount × 3 × coefficientCount` Doubles (little endian).
/// Abdeckung 01.01.2020 – 01.01.2100, Intervalle zu 4 Tagen mit je 13 Koeffizienten.
final class MoonEphemeris: Sendable {
    static let shared: MoonEphemeris? = MoonEphemeris()

    let jdStart: Double
    let daysPerSet: Double
    let setCount: Int
    let coefficientCount: Int
    private let coefficients: [Double]

    var jdEnd: Double { jdStart + Double(setCount) * daysPerSet }

    convenience init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "moon_de421", withExtension: "bin") else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 32 else { return nil }

        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        guard magic == 0x3158_544D else { return nil }          // "MTX1"

        let jd0 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Double.self) }
        let dps = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: Double.self) }
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self) })
        let nc = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) })
        let n = count * 3 * nc
        guard nc >= 2, count > 0, data.count >= 32 + n * 8 else { return nil }

        jdStart = jd0
        daysPerSet = dps
        setCount = count
        coefficientCount = nc
        coefficients = data.withUnsafeBytes { raw in
            (0..<n).map { raw.loadUnaligned(fromByteOffset: 32 + $0 * 8, as: Double.self) }
        }
    }

    func covers(jdTT jd: Double) -> Bool { jd >= jdStart && jd < jdEnd }

    /// Geozentrische Position (km) und Geschwindigkeit (km/s) im ICRF.
    func state(jdTT jd: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard covers(jdTT: jd) else { return nil }
        let offset = jd - jdStart
        let k = min(max(Int(offset / daysPerSet), 0), setCount - 1)
        let t = 2 * (offset - Double(k) * daysPerSet) / daysPerSet - 1
        let nc = coefficientCount

        return coefficients.withUnsafeBufferPointer { c in
            var pos = SIMD3<Double>.zero
            var vel = SIMD3<Double>.zero
            let base = k * 3 * nc
            for axis in 0..<3 {
                let b = base + axis * nc
                // Tschebyschow-Polynome T_n(t) und Ableitungen T'_n(t)
                var t0 = 1.0, t1 = t
                var d0 = 0.0, d1 = 1.0
                var p = c[b] + c[b + 1] * t
                var v = c[b + 1]
                for i in 2..<nc {
                    let t2 = 2 * t * t1 - t0
                    let d2 = 2 * t1 + 2 * t * d1 - d0
                    p += c[b + i] * t2
                    v += c[b + i] * d2
                    t0 = t1; t1 = t2
                    d0 = d1; d1 = d2
                }
                pos[axis] = p
                vel[axis] = v
            }
            // dt/dJD = 2 / Intervalllänge; km/Tag → km/s
            return (pos, vel * (2 / daysPerSet) / 86_400)
        }
    }
}

// MARK: - Sonne (Meeus, Kap. 25, Genauigkeit ≈ 0,01°)

enum SunModel {
    static let obliquityJ2000 = 23.439_291_1 * Double.pi / 180
    static let astronomicalUnit = 149_597_870.7

    /// Geozentrische Sonne: geometrischer Vektor (km, J2000-Äquator) und
    /// aberrationskorrigierte ekliptikale Länge (rad, Äquinoktium J2000).
    static func position(jdTT jd: Double) -> (vector: SIMD3<Double>, apparentLongitude: Double) {
        let deg = Double.pi / 180
        let T = (jd - 2_451_545.0) / 36_525
        let L0 = 280.466_46 + 36_000.769_83 * T + 0.000_303_2 * T * T
        let M = (357.529_11 + 35_999.050_29 * T - 0.000_153_7 * T * T) * deg
        let e = 0.016_708_634 - 0.000_042_037 * T - 0.000_000_126_7 * T * T
        let C = (1.914_602 - 0.004_817 * T - 0.000_014 * T * T) * sin(M)
            + (0.019_993 - 0.000_101 * T) * sin(2 * M)
            + 0.000_289 * sin(3 * M)
        let trueLongitudeOfDate = L0 + C
        let nu = M + C * deg
        let R = 1.000_001_018 * (1 - e * e) / (1 + e * cos(nu))            // AE
        let longitudeJ2000 = (trueLongitudeOfDate - 1.396_971_4 * T) * deg  // allgemeine Präzession
        let aberration = (20.4898 / 3600) * deg / R

        let r = R * astronomicalUnit
        let x = r * cos(longitudeJ2000)
        let y = r * sin(longitudeJ2000)
        let eq = SIMD3(x, y * cos(obliquityJ2000), y * sin(obliquityJ2000))
        return (eq, longitudeJ2000 - aberration)
    }

    /// Ekliptikale Länge (rad, J2000) eines Vektors im J2000-Äquatorsystem.
    static func eclipticLongitude(of v: SIMD3<Double>) -> Double {
        let y = v.y * cos(obliquityJ2000) + v.z * sin(obliquityJ2000)
        return atan2(y, v.x)
    }
}

// MARK: - Mondzustand

enum MoonPhase: Int, Sendable, CaseIterable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous, fullMoon, waningGibbous, lastQuarter, waningCrescent

    /// Hauptphasen gelten ±6,1° Elongation (≈ ±12 Stunden) um den exakten Zeitpunkt.
    init(elongation e: Double) {
        let w = 6.1
        switch e {
        case ..<w, (360 - w)...: self = .newMoon
        case ..<(90 - w): self = .waxingCrescent
        case ..<(90 + w): self = .firstQuarter
        case ..<(180 - w): self = .waxingGibbous
        case ..<(180 + w): self = .fullMoon
        case ..<(270 - w): self = .waningGibbous
        case ..<(270 + w): self = .lastQuarter
        default: self = .waningCrescent
        }
    }

    var name: String {
        switch self {
        case .newMoon: "Neumond"
        case .waxingCrescent: "Zunehmende Sichel"
        case .firstQuarter: "Erstes Viertel"
        case .waxingGibbous: "Zunehmender Mond"
        case .fullMoon: "Vollmond"
        case .waningGibbous: "Abnehmender Mond"
        case .lastQuarter: "Letztes Viertel"
        case .waningCrescent: "Abnehmende Sichel"
        }
    }

    var symbolName: String {
        switch self {
        case .newMoon: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .fullMoon: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

struct MoonState: Hashable, Sendable {
    let date: Date
    /// Abstand Erdmittelpunkt – Mondmittelpunkt (km)
    let distanceKm: Double
    /// Änderung des Abstands (km/s); positiv = Mond entfernt sich
    let radialVelocityKmS: Double
    /// Winkel Sonne – Mond – Erde (Grad)
    let phaseAngleDeg: Double
    /// Elongation Mond – Sonne in ekliptikaler Länge (0 = Neumond, 180 = Vollmond)
    let elongationDeg: Double

    static let earthRadiusKm = 6_371.0
    static let moonRadiusKm = 1_737.4
    static let speedOfLight = 299_792.458

    var illuminatedFraction: Double { (1 + cos(phaseAngleDeg * .pi / 180)) / 2 }
    var isWaxing: Bool { elongationDeg < 180 }
    var phase: MoonPhase { MoonPhase(elongation: elongationDeg) }
    var lightTimeSeconds: Double { distanceKm / Self.speedOfLight }
    var surfaceDistanceKm: Double { distanceKm - Self.earthRadiusKm - Self.moonRadiusKm }

    /// Name des vorgerenderten Phasenbilds (2°-Raster, ohne Libration).
    var imageName: String {
        let e = isWaxing ? 180 - phaseAngleDeg : 180 + phaseAngleDeg
        let step = Int((e / 2).rounded()) % 180
        return String(format: "moon_%03d", step * 2)
    }
}

struct MoonEvent: Hashable, Sendable, Identifiable {
    enum Kind: Int, Sendable {
        case newMoon, firstQuarter, fullMoon, lastQuarter, perigee, apogee

        var title: String {
            switch self {
            case .newMoon: "Neumond"
            case .firstQuarter: "Erstes Viertel"
            case .fullMoon: "Vollmond"
            case .lastQuarter: "Letztes Viertel"
            case .perigee: "Perigäum"
            case .apogee: "Apogäum"
            }
        }

        var symbolName: String {
            switch self {
            case .newMoon: "moonphase.new.moon"
            case .firstQuarter: "moonphase.first.quarter"
            case .fullMoon: "moonphase.full.moon"
            case .lastQuarter: "moonphase.last.quarter"
            case .perigee: "arrow.down.to.line.compact"
            case .apogee: "arrow.up.to.line.compact"
            }
        }
    }

    let kind: Kind
    let date: Date
    let distanceKm: Double
    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
}

struct DistanceSample: Hashable, Sendable, Identifiable {
    let date: Date
    let distanceKm: Double
    var id: Date { date }
}

/// Langsam veränderliche Zusatzdaten, einmal pro Timeline bzw. alle paar Minuten berechnet.
struct MoonContext: Sendable {
    let computedAt: Date
    let events: [MoonEvent]
    let samples: [DistanceSample]

    func next(_ kind: MoonEvent.Kind, after date: Date) -> MoonEvent? {
        events.first { $0.kind == kind && $0.date > date }
    }

    func last(_ kind: MoonEvent.Kind, before date: Date) -> MoonEvent? {
        events.last { $0.kind == kind && $0.date <= date }
    }

    /// Mondalter in Tagen seit dem letzten Neumond.
    func age(at date: Date) -> Double? {
        last(.newMoon, before: date).map { date.timeIntervalSince($0.date) / 86_400 }
    }

    /// Nächste Hauptphase (Neumond, Viertel, Vollmond) nach `date`.
    func nextPrincipalPhase(after date: Date) -> MoonEvent? {
        events.first { $0.date > date && $0.kind.rawValue <= MoonEvent.Kind.lastQuarter.rawValue }
    }

    func apsides(in range: ClosedRange<Date>) -> [MoonEvent] {
        events.filter { ($0.kind == .perigee || $0.kind == .apogee) && range.contains($0.date) }
    }

    private func nearest(_ kind: MoonEvent.Kind, to date: Date) -> MoonEvent? {
        events.filter { $0.kind == kind }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// Supermond oder Mikromond, aber nur während der Phase Vollmond oder Neumond.
    /// Definition nach Richard Nolle (1979): Die Syzygie liegt innerhalb von 10 % der Spanne
    /// zwischen Perigäum und Apogäum des laufenden Umlaufs am erdnächsten bzw. erdfernsten Punkt.
    func distanceLabel(for state: MoonState) -> DistanceLabel? {
        let kind: MoonEvent.Kind
        switch state.phase {
        case .fullMoon: kind = .fullMoon
        case .newMoon: kind = .newMoon
        default: return nil
        }
        guard let syzygy = nearest(kind, to: state.date),
              abs(syzygy.date.timeIntervalSince(state.date)) < 86_400,
              let perigee = nearest(.perigee, to: syzygy.date),
              let apogee = nearest(.apogee, to: syzygy.date) else { return nil }
        let span = apogee.distanceKm - perigee.distanceKm
        guard span > 0 else { return nil }
        if syzygy.distanceKm <= perigee.distanceKm + 0.1 * span {
            return DistanceLabel(isSuper: true, isFullMoon: kind == .fullMoon, syzygy: syzygy)
        }
        if syzygy.distanceKm >= apogee.distanceKm - 0.1 * span {
            return DistanceLabel(isSuper: false, isFullMoon: kind == .fullMoon, syzygy: syzygy)
        }
        return nil
    }
}

/// Supermond, Mikromond, Super-Neumond oder Mikro-Neumond
struct DistanceLabel: Hashable, Sendable {
    let isSuper: Bool
    let isFullMoon: Bool
    /// Der exakte Voll- oder Neumond, auf den sich die Einordnung bezieht
    let syzygy: MoonEvent

    var title: String {
        switch (isSuper, isFullMoon) {
        case (true, true): "Supermond"
        case (false, true): "Mikromond"
        case (true, false): "Super-Neumond"
        case (false, false): "Mikro-Neumond"
        }
    }

    var explanation: String {
        let phase = isFullMoon ? "Vollmond" : "Neumond"
        return isSuper ? "\(phase) nahe dem Perigäum (erdnächster Punkt)" : "\(phase) nahe dem Apogäum (erdfernster Punkt)"
    }

    var symbolName: String {
        isSuper ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
    }
}

// MARK: - Rechner

struct MoonCalculator: Sendable {
    let ephemeris: MoonEphemeris

    init?(ephemeris: MoonEphemeris? = MoonEphemeris.shared) {
        guard let ephemeris else { return nil }
        self.ephemeris = ephemeris
    }

    func distance(at date: Date) -> Double? {
        ephemeris.state(jdTT: AstroTime.julianDayTT(date)).map { simd_length($0.position) }
    }

    func state(at date: Date) -> MoonState? {
        let jd = AstroTime.julianDayTT(date)
        guard let (m, v) = ephemeris.state(jdTT: jd) else { return nil }
        let r = simd_length(m)
        let sun = SunModel.position(jdTT: jd)
        let toSun = sun.vector - m
        let cosAlpha = simd_dot(toSun, -m) / (simd_length(toSun) * r)
        let alpha = acos(min(max(cosAlpha, -1), 1)) * 180 / .pi
        return MoonState(
            date: date,
            distanceKm: r,
            radialVelocityKmS: simd_dot(m, v) / r,
            phaseAngleDeg: alpha,
            elongationDeg: elongation(moon: m, sunLongitude: sun.apparentLongitude)
        )
    }

    private func elongation(moon m: SIMD3<Double>, sunLongitude: Double) -> Double {
        let d = (SunModel.eclipticLongitude(of: m) - sunLongitude) * 180 / .pi
        return d - 360 * floor(d / 360)
    }

    private func elongation(at date: Date) -> Double? {
        let jd = AstroTime.julianDayTT(date)
        guard let (m, _) = ephemeris.state(jdTT: jd) else { return nil }
        return elongation(moon: m, sunLongitude: SunModel.position(jdTT: jd).apparentLongitude)
    }

    private func radialVelocity(at date: Date) -> Double? {
        ephemeris.state(jdTT: AstroTime.julianDayTT(date)).map { simd_dot($0.position, $0.velocity) / simd_length($0.position) }
    }

    /// Hauptphasen im Zeitraum, auf Bruchteile einer Sekunde eingegrenzt.
    func phaseEvents(from start: Date, to end: Date) -> [MoonEvent] {
        let targets: [(Double, MoonEvent.Kind)] = [(0, .newMoon), (90, .firstQuarter), (180, .fullMoon), (270, .lastQuarter)]
        let step: TimeInterval = 6 * 3600
        var result: [MoonEvent] = []
        var t0 = start
        guard var e0 = elongation(at: t0) else { return [] }
        while t0 < end {
            let t1 = t0.addingTimeInterval(step)
            guard let e1 = elongation(at: t1) else { break }
            for (target, kind) in targets {
                let f0 = wrap180(e0 - target), f1 = wrap180(e1 - target)
                if f0 < 0, f1 >= 0, f1 - f0 < 90,
                   let t = bisect(t0, t1, { self.elongation(at: $0).map { wrap180($0 - target) } }),
                   let d = distance(at: t) {
                    result.append(MoonEvent(kind: kind, date: t, distanceKm: d))
                }
            }
            t0 = t1; e0 = e1
        }
        return result
    }

    /// Perigäen und Apogäen (Nullstellen der Radialgeschwindigkeit).
    func apsides(from start: Date, to end: Date) -> [MoonEvent] {
        let step: TimeInterval = 6 * 3600
        var result: [MoonEvent] = []
        var t0 = start
        guard var v0 = radialVelocity(at: t0) else { return [] }
        while t0 < end {
            let t1 = t0.addingTimeInterval(step)
            guard let v1 = radialVelocity(at: t1) else { break }
            if (v0 < 0) != (v1 < 0) {
                let sign: Double = v0 < 0 ? 1 : -1          // f muss von negativ nach positiv laufen
                if let t = bisect(t0, t1, { self.radialVelocity(at: $0).map { $0 * sign } }),
                   let d = distance(at: t) {
                    result.append(MoonEvent(kind: v0 < 0 ? .perigee : .apogee, date: t, distanceKm: d))
                }
            }
            t0 = t1; v0 = v1
        }
        return result
    }

    func distanceSeries(from start: Date, to end: Date, step: TimeInterval) -> [DistanceSample] {
        stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: step).compactMap { t in
            let date = Date(timeIntervalSince1970: t)
            return distance(at: date).map { DistanceSample(date: date, distanceKm: $0) }
        }
    }

    func context(around date: Date) -> MoonContext {
        let events = (phaseEvents(from: date.addingTimeInterval(-32 * 86_400), to: date.addingTimeInterval(40 * 86_400))
                      + apsides(from: date.addingTimeInterval(-32 * 86_400), to: date.addingTimeInterval(40 * 86_400)))
            .sorted { $0.date < $1.date }
        let samples = distanceSeries(from: date.addingTimeInterval(-14 * 86_400),
                                     to: date.addingTimeInterval(14 * 86_400),
                                     step: 4 * 3600)
        return MoonContext(computedAt: date, events: events, samples: samples)
    }

    // MARK: Hilfsfunktionen

    /// Sucht die Nullstelle von f zwischen a und b (f(a) < 0 ≤ f(b)) auf < 1 ms genau.
    private func bisect(_ a: Date, _ b: Date, _ f: (Date) -> Double?) -> Date? {
        var lo = a.timeIntervalSince1970, hi = b.timeIntervalSince1970
        for _ in 0..<40 where hi - lo > 0.001 {
            let mid = (lo + hi) / 2
            guard let v = f(Date(timeIntervalSince1970: mid)) else { return nil }
            if v < 0 { lo = mid } else { hi = mid }
        }
        return Date(timeIntervalSince1970: (lo + hi) / 2)
    }

    private func wrap180(_ x: Double) -> Double { x - 360 * floor((x + 180) / 360) }
}
