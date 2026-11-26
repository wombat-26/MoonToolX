import Foundation
import simd

// MARK: - Ansicht der Mondkugel (Libration)

/// Welcher Teil der Mondkugel dem Beobachter und der Sonne zugewandt ist.
/// Die selenografische Länge und Breite des Scheibenmittelpunkts ist die Libration.
struct MoonAspect: Hashable, Sendable {
    /// Selenografische Länge des Scheibenmittelpunkts (Grad, Ost positiv, −180…180) = Libration in Länge
    let subObserverLonDeg: Double
    /// Selenografische Breite des Scheibenmittelpunkts (Grad, Nord positiv) = Libration in Breite
    let subObserverLatDeg: Double
    /// Selenografische Länge des Punkts mit der Sonne im Zenit (Grad, Ost positiv, −180…180)
    let subSolarLonDeg: Double
    /// Selenografische Breite des Punkts mit der Sonne im Zenit (Grad)
    let subSolarLatDeg: Double
    /// Positionswinkel der Mondachse (Grad, vom Himmelsnordpol des Datums über Ost)
    let axisPositionAngleDeg: Double

    /// Richtung (Einheitsvektor) im mondfesten System: x zum Nullmeridian am Äquator, z zum Nordpol.
    static func direction(lonDeg: Double, latDeg: Double) -> SIMD3<Double> {
        let l = lonDeg * .pi / 180, b = latDeg * .pi / 180
        return SIMD3(cos(b) * cos(l), cos(b) * sin(l), sin(b))
    }

    /// Winkel Sonne – Mond – Beobachter (Grad)
    var phaseAngleDeg: Double {
        let c = simd_dot(Self.direction(lonDeg: subObserverLonDeg, latDeg: subObserverLatDeg),
                         Self.direction(lonDeg: subSolarLonDeg, latDeg: subSolarLatDeg))
        return acos(min(max(c, -1), 1)) * 180 / .pi
    }

    /// Auf 0,1° gerundet: so fein wird neu gezeichnet (am Bildrand weniger als ein Pixel).
    var rounded: MoonAspect {
        func r(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        return MoonAspect(subObserverLonDeg: r(subObserverLonDeg), subObserverLatDeg: r(subObserverLatDeg),
                          subSolarLonDeg: r(subSolarLonDeg), subSolarLatDeg: r(subSolarLatDeg),
                          axisPositionAngleDeg: r(axisPositionAngleDeg))
    }

    /// Schlüssel für Zwischenspeicher und Bildwechsel (ohne Achswinkel, der das Bild nicht ändert)
    var imageKey: String {
        let a = rounded
        return String(format: "%.1f_%.1f_%.1f_%.1f", a.subObserverLonDeg, a.subObserverLatDeg,
                      a.subSolarLonDeg, a.subSolarLatDeg)
    }
}

/// Orientierung des Mondes nach IAU/WGCCRE 2009 (Archinal et al. 2011): Pol und Nullmeridian
/// einschließlich der physischen Libration, im System „Mean Earth/Polar Axis“ der Mondkarten.
/// Abgleich mit JPL Horizons siehe Tools/main.swift.
enum MoonOrientation {
    private static let deg = Double.pi / 180

    /// Rektaszension und Deklination des Nordpols sowie Nullmeridianwinkel W (rad, ICRF).
    static func poleAndMeridian(jdTT jd: Double) -> (alpha: Double, delta: Double, w: Double) {
        let d = jd - 2_451_545.0
        let t = d / 36_525
        let e: [Double] = [
            0,
            125.045 - 0.0529921 * d,
            250.089 - 0.1059842 * d,
            260.008 + 13.0120009 * d,
            176.625 + 13.3407154 * d,
            357.529 + 0.9856003 * d,
            311.589 + 26.4057084 * d,
            134.963 + 13.0649930 * d,
            276.617 + 0.3287146 * d,
            34.226 + 1.7484877 * d,
            15.134 - 0.1589763 * d,
            119.743 + 0.0036096 * d,
            239.961 + 0.1643573 * d,
            25.053 + 12.9590088 * d,
        ].map { $0 * deg }

        let alpha = 269.9949 + 0.0031 * t
            - 3.8787 * sin(e[1]) - 0.1204 * sin(e[2]) + 0.0700 * sin(e[3]) - 0.0172 * sin(e[4])
            + 0.0072 * sin(e[6]) - 0.0052 * sin(e[10]) + 0.0043 * sin(e[13])
        let delta = 66.5392 + 0.0130 * t
            + 1.5419 * cos(e[1]) + 0.0239 * cos(e[2]) - 0.0278 * cos(e[3]) + 0.0068 * cos(e[4])
            - 0.0029 * cos(e[6]) + 0.0009 * cos(e[7]) + 0.0008 * cos(e[10]) - 0.0009 * cos(e[13])
        let w = 38.3213 + 13.17635815 * d - 1.4e-12 * d * d
            + 3.5610 * sin(e[1]) + 0.1208 * sin(e[2]) - 0.0642 * sin(e[3]) + 0.0158 * sin(e[4])
            + 0.0252 * sin(e[5]) - 0.0066 * sin(e[6]) - 0.0047 * sin(e[7]) - 0.0046 * sin(e[8])
            + 0.0028 * sin(e[9]) + 0.0052 * sin(e[10]) + 0.0040 * sin(e[11]) + 0.0019 * sin(e[12])
            - 0.0044 * sin(e[13])
        return (alpha * deg, delta * deg, w.truncatingRemainder(dividingBy: 360) * deg)
    }

    /// Matrix ICRF → mondfestes System.
    static func bodyFromICRF(jdTT jd: Double) -> simd_double3x3 {
        let (alpha, delta, w) = poleAndMeridian(jdTT: jd)
        func r1(_ a: Double) -> simd_double3x3 {
            simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cos(a), sin(a)), SIMD3(0, -sin(a), cos(a))])
        }
        func r3(_ a: Double) -> simd_double3x3 {
            simd_double3x3(rows: [SIMD3(cos(a), sin(a), 0), SIMD3(-sin(a), cos(a), 0), SIMD3(0, 0, 1)])
        }
        return r3(w) * r1(.pi / 2 - delta) * r3(.pi / 2 + alpha)
    }
}

extension MoonCalculator {
    /// Ansicht der Mondkugel vom Standort aus; ohne Standort vom Erdmittelpunkt aus.
    /// Die Lichtlaufzeit (1,3 s) ist vernachlässigt, der Fehler liegt unter 0,001°.
    func aspect(at date: Date, observer: Observer? = nil) -> MoonAspect? {
        let jd = AstroTime.julianDayTT(date)
        guard let (moon, _) = ephemeris.state(jdTT: jd) else { return nil }
        let sun = SunModel.position(jdTT: jd).vector
        let (trueOfDate, gast, _, _) = EarthOrientation.trueOfDate(date: date)
        let toICRF = trueOfDate.transpose
        let site = observer.map { toICRF * EarthOrientation.observer($0, gast: gast).position } ?? .zero

        let body = MoonOrientation.bodyFromICRF(jdTT: jd)
        func lonLat(_ v: SIMD3<Double>) -> (Double, Double) {
            let u = simd_normalize(body * v)
            return (atan2(u.y, u.x) * 180 / .pi, asin(min(max(u.z, -1), 1)) * 180 / .pi)
        }
        let (obsLon, obsLat) = lonLat(site - moon)
        let (sunLon, sunLat) = lonLat(sun - moon)

        // Positionswinkel der Mondachse am Himmel, bezogen auf den Himmelsnordpol des Datums
        let sight = simd_normalize(moon - site)
        let celestialNorth = toICRF * SIMD3(0, 0, 1)
        let pole = body.transpose * SIMD3(0, 0, 1)
        let east = simd_normalize(simd_cross(celestialNorth, sight))
        let north = simd_cross(sight, east)
        let axis = atan2(simd_dot(pole, east), simd_dot(pole, north)) * 180 / .pi

        return MoonAspect(subObserverLonDeg: obsLon, subObserverLatDeg: obsLat,
                          subSolarLonDeg: sunLon, subSolarLatDeg: sunLat, axisPositionAngleDeg: axis)
    }

    /// Scheinbare visuelle Helligkeit des Mondes (mag) vom Standort aus; ohne Standort vom Erdmittelpunkt aus.
    /// Formel nach Allen, Astrophysical Quantities: V = 0,23 + 5 lg(r·Δ) + 0,026 α + 4·10⁻⁹ α⁴
    /// (r Sonne–Mond und Δ Beobachter–Mond in AE, α Phasenwinkel in Grad), ohne Abschwächung durch die Atmosphäre.
    /// Mit der Konstante 0,23 stimmt der Wert auf 0,001 mag mit JPL Horizons überein (Tools/main.swift).
    /// Nahe Neumond ist er nur ein Richtwert; nahe Vollmond ist der Mond etwa 0,1 mag heller (Oppositionseffekt).
    func apparentMagnitude(at date: Date, observer: Observer? = nil) -> Double? {
        let jd = AstroTime.julianDayTT(date)
        guard let (moon, _) = ephemeris.state(jdTT: jd) else { return nil }
        let (trueOfDate, gast, _, _) = EarthOrientation.trueOfDate(date: date)
        let site = observer.map { trueOfDate.transpose * EarthOrientation.observer($0, gast: gast).position } ?? .zero
        let toSun = SunModel.position(jdTT: jd).vector - moon
        let toObserver = site - moon
        let r = simd_length(toSun), delta = simd_length(toObserver)
        let alpha = acos(min(max(simd_dot(toSun, toObserver) / (r * delta), -1), 1)) * 180 / .pi
        let au = SunModel.astronomicalUnit
        return 0.23 + 5 * log10(r / au * delta / au) + 0.026 * alpha + 4e-9 * alpha * alpha * alpha * alpha
    }
}
