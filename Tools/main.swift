// Prüft die Swift-Implementierung gegen Referenzwerte aus JPL DE440 (jplephem, de440s.bsp).
// Aufruf: swiftc -O Shared/Astronomy.swift Tools/main.swift -o /tmp/moonverify && /tmp/moonverify
import Foundation
import simd

let eph = MoonEphemeris(url: URL(fileURLWithPath: "Shared/moon_de440.bin"))!
let calc = MoonCalculator(ephemeris: eph)!
let iso = ISO8601DateFormatter()
let refs: [(String, Double, Double)] = [
    ("2026-11-24T10:00:00Z", 361259.1987, -30.093),
    ("2026-11-24T10:00:01Z", 361259.1687, -30.093),
    ("2027-01-01T00:00:00Z", 391499.3938, 57.765),
    ("2050-06-15T12:34:56Z", 377515.0006, 32.479),
    ("2099-12-31T23:59:59Z", 371710.2319, -13.727),
]
var worst = 0.0
for (s, km, vr) in refs {
    let st = calc.state(at: iso.date(from: s)!)!
    let dkm = st.distanceKm - km
    worst = max(worst, abs(dkm))
    print(String(format: "%@  %.4f km (Δ %.1f m)  vr %.3f m/s (Ref %.3f)  Phase %.1f° %@ %.1f %%",
                 s, st.distanceKm, dkm * 1000, st.radialVelocityKmS * 1000, vr, st.phaseAngleDeg,
                 st.phase.name, st.illuminatedFraction * 100))
}
print(String(format: "Max. Abweichung: %.2f m", worst * 1000))

let now = iso.date(from: "2026-11-24T10:00:00Z")!
let ctx = calc.context(around: now)
let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"; df.timeZone = TimeZone(identifier: "UTC")
for e in ctx.events where e.date > now.addingTimeInterval(-10 * 86400) && e.date < now.addingTimeInterval(35 * 86400) {
    print(e.kind.title.padding(toLength: 15, withPad: " ", startingAt: 0), df.string(from: e.date), String(format: "%.1f km", e.distanceKm))
}

// Timeline-Simulation wie im Widget
var lastKm: Int? = nil; var n = 0
let t0 = Date()
for s in 0...3600 {
    let d = now.addingTimeInterval(Double(s))
    let km = Int(calc.distance(at: d)!.rounded())
    if km != lastKm || Int(d.timeIntervalSince1970) % 60 == 0 { n += 1; lastKm = km }
}
print("Timeline-Einträge für 60 min:", n, String(format: "(%.1f ms)", Date().timeIntervalSince(t0) * 1000))

// Supermond / Mikromond an bekannten Syzygien
for s in ["2026-11-24T14:53:38Z", "2026-12-09T00:52:03Z", "2026-12-24T01:28:26Z", "2026-11-17T11:47:39Z"] {
    let d = iso.date(from: s)!
    let st = calc.state(at: d)!
    let label = calc.context(around: d).distanceLabel(for: st)
    print(s, st.phase.name, "→", label?.title ?? "–", label.map { String(format: "%.1f km", $0.syzygy.distanceKm) } ?? "")
}

// Entfernung vom Standort, Mondhöhe und Azimut gegen JPL Horizons (topozentrische Vektoren bzw. AZ/EL, DE441)
let topoRefs: [(String, Double, Double, Double, String, Double, Double, Double)] = [
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-24T19:55:00Z", 355747.8258, 45.663, 102.517),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T02:00:00Z", 354840.0811, 52.437, 248.513),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T08:00:00Z", 359683.3063, -1.023, 313.004),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T13:30:00Z", 360785.6044, -12.565, 21.310),
    ("Muenchen", 48.13, 11.5, 530.0, "2030-03-01T12:00:00Z", 379374.7143, 15.633, 222.544),
    ("Muenchen", 48.13, 11.5, 530.0, "2050-06-15T21:00:00Z", 381256.9373, -25.706, 11.673),
    ("Muenchen", 48.13, 11.5, 530.0, "2099-12-31T00:00:00Z", 368582.8122, 45.988, 125.937),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-24T19:55:00Z", 362031.6298, -16.020, 291.543),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T02:00:00Z", 366234.8264, -82.756, 190.950),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T08:00:00Z", 361723.4135, -19.896, 69.568),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T13:30:00Z", 356594.6692, 25.844, 16.561),
    ("Sydney", -33.87, 151.21, 50.0, "2030-03-01T12:00:00Z", 385385.8776, -41.787, 177.620),
    ("Sydney", -33.87, 151.21, 50.0, "2050-06-15T21:00:00Z", 375109.6497, 31.801, 33.855),
    ("Sydney", -33.87, 151.21, 50.0, "2099-12-31T00:00:00Z", 375479.4969, -21.468, 275.688),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-24T19:55:00Z", 356243.0206, 39.547, 129.210),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T02:00:00Z", 355899.6386, 38.660, 236.661),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T08:00:00Z", 358285.7047, 11.629, 317.507),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T13:30:00Z", 358442.4398, 8.588, 27.720),
    ("Tromsoe", 69.65, 18.96, 100.0, "2030-03-01T12:00:00Z", 381359.6944, -2.409, 227.379),
    ("Tromsoe", 69.65, 18.96, 100.0, "2050-06-15T21:00:00Z", 378927.9768, -4.040, 17.748),
    ("Tromsoe", 69.65, 18.96, 100.0, "2099-12-31T00:00:00Z", 369716.3443, 32.661, 147.434),
]
var worstD = 0.0, worstH = 0.0, worstA = 0.0
for (_, lat, lon, alt, s, km, el, az) in topoRefs {
    let t = calc.topocentric(at: iso.date(from: s)!, observer: Observer(latitude: lat, longitude: lon, altitudeM: alt))!
    worstD = max(worstD, abs(t.distanceKm - km)); worstH = max(worstH, abs(t.altitudeDeg - el))
    worstA = max(worstA, abs(remainder(t.azimuthDeg - az, 360)))
}
print(String(format: "Standort (%d Fälle, München/Sydney/Tromsø): max. Abweichung Entfernung %.3f km, Höhe %.4f°, Azimut %.4f°",
             topoRefs.count, worstD, worstH, worstA))

// Ausrichtung am Himmel: Mondachse P gegen JPL Horizons (NP.ang), parallaktischer Winkel q gegen Vektorrechnung
let axisRefs: [(String, Double, Double, Double, String, Double, Double)] = [
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T13:30:00Z", 353.5866, -12.564857),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-26T21:00:00Z", 2.0847, 35.404731),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-27T03:00:00Z", 3.2840, 62.295479),
    ("Muenchen", 48.13, 11.5, 530.0, "2027-03-01T12:00:00Z", 3.5207, -18.893197),
    ("Muenchen", 48.13, 11.5, 530.0, "2030-07-01T20:00:00Z", 6.9803, -4.988039),
    ("Muenchen", 48.13, 11.5, 530.0, "2050-06-15T21:00:00Z", 340.7345, -25.706320),
    ("Muenchen", 48.13, 11.5, 530.0, "2099-12-31T00:00:00Z", 18.1185, 45.988003),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T13:30:00Z", 353.5556, 25.844172),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-26T21:00:00Z", 1.4783, -4.455848),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-27T03:00:00Z", 3.2773, -72.336322),
    ("Sydney", -33.87, 151.21, 50.0, "2027-03-01T12:00:00Z", 3.0265, -15.355993),
    ("Sydney", -33.87, 151.21, 50.0, "2030-07-01T20:00:00Z", 7.4919, -19.827626),
    ("Sydney", -33.87, 151.21, 50.0, "2050-06-15T21:00:00Z", 340.8046, 31.801244),
    ("Sydney", -33.87, 151.21, 50.0, "2099-12-31T00:00:00Z", 17.8602, -21.468225),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T13:30:00Z", 353.5510, 8.587542),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-26T21:00:00Z", 1.9492, 35.527300),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-27T03:00:00Z", 3.3154, 43.022718),
    ("Tromsoe", 69.65, 18.96, 100.0, "2027-03-01T12:00:00Z", 3.3980, -27.974641),
    ("Tromsoe", 69.65, 18.96, 100.0, "2030-07-01T20:00:00Z", 7.0946, 5.160824),
    ("Tromsoe", 69.65, 18.96, 100.0, "2050-06-15T21:00:00Z", 340.7301, -4.039659),
    ("Tromsoe", 69.65, 18.96, 100.0, "2099-12-31T00:00:00Z", 18.0640, 32.661258),
    ("Quito", -0.18, -78.47, 2850.0, "2026-11-25T13:30:00Z", 353.0873, -21.915932),
    ("Quito", -0.18, -78.47, 2850.0, "2026-11-26T21:00:00Z", 2.0033, -54.452792),
    ("Quito", -0.18, -78.47, 2850.0, "2026-11-27T03:00:00Z", 3.7898, 17.909765),
    ("Quito", -0.18, -78.47, 2850.0, "2027-03-01T12:00:00Z", 3.2376, 61.864719),
    ("Quito", -0.18, -78.47, 2850.0, "2030-07-01T20:00:00Z", 6.9992, 54.564403),
    ("Quito", -0.18, -78.47, 2850.0, "2050-06-15T21:00:00Z", 340.4390, -11.606946),
    ("Quito", -0.18, -78.47, 2850.0, "2099-12-31T00:00:00Z", 18.2192, -34.589774),
]
var worstP = 0.0, worstQ = 0.0
for (_, lat, lon, alt, s, np, _) in axisRefs {
    let date = iso.date(from: s)!
    let obs = Observer(latitude: lat, longitude: lon, altitudeM: alt)
    let t = calc.topocentric(at: date, observer: obs)!
    let (m, _) = eph.state(jdTT: AstroTime.julianDayTT(date))!
    let o = EarthOrientation.trueOfDate(date: date)
    let site = EarthOrientation.observer(obs, gast: o.gast)
    let u = simd_normalize(o.matrix * m - site.position)
    let k = SIMD3<Double>(0, 0, 1)
    let n = simd_normalize(k - simd_dot(k, u) * u), e = simd_normalize(simd_cross(k, u))
    let zp = site.up - simd_dot(site.up, u) * u
    let qVec = atan2(simd_dot(zp, e), simd_dot(zp, n)) * 180 / .pi
    worstP = max(worstP, abs(remainder(t.axisDeg - np, 360)))
    worstQ = max(worstQ, abs(remainder(t.parallacticDeg - qVec, 360)))
}
print(String(format: "Ausrichtung (%d Fälle, München/Sydney/Tromsø/Quito): max. Abweichung Mondachse %.3f°, parallaktischer Winkel %.4f°",
             axisRefs.count, worstP, worstQ))

// Auf- und Untergang, Meridiandurchgang gegen JPL Horizons (R_T_S_ONLY=TVH, Höhe 0 m, Zeiten auf ganze Minuten)
let rtsRefs: [(String, Double, Double, String, String, Double, Double)] = [
    ("Muenchen", 48.13, 11.5, "2026-11-26T00:25:00Z", "t", 180.256184, 69.156264),
    ("Muenchen", 48.13, 11.5, "2026-11-26T09:09:00Z", "s", 313.629901, -0.855036),
    ("Muenchen", 48.13, 11.5, "2026-11-26T16:50:00Z", "r", 47.050367, -0.774147),
    ("Muenchen", 48.13, 11.5, "2026-11-27T10:03:00Z", "s", 310.601561, -0.902322),
    ("Muenchen", 48.13, 11.5, "2026-11-27T18:11:00Z", "r", 51.330010, -0.773744),
    ("Muenchen", 48.13, 11.5, "2026-11-28T02:35:00Z", "t", 180.441775, 65.062847),
    ("Muenchen", 48.13, 11.5, "2026-11-28T10:42:00Z", "s", 304.534596, -0.964439),
    ("Muenchen", 48.13, 11.5, "2026-11-28T19:37:00Z", "r", 58.552234, -0.711622),
    ("Muenchen", 48.13, 11.5, "2035-06-10T08:18:00Z", "r", 69.529314, -0.705940),
    ("Muenchen", 48.13, 11.5, "2035-06-10T15:36:00Z", "t", 180.278906, 54.004748),
    ("Muenchen", 48.13, 11.5, "2035-06-10T22:44:00Z", "s", 287.662352, -0.986180),
    ("Muenchen", 48.13, 11.5, "2035-06-11T09:29:00Z", "r", 75.127837, -0.749947),
    ("Muenchen", 48.13, 11.5, "2035-06-11T16:28:00Z", "t", 180.213441, 50.166598),
    ("Muenchen", 48.13, 11.5, "2035-06-11T23:16:00Z", "s", 281.675643, -0.910060),
    ("Muenchen", 48.13, 11.5, "2035-06-12T10:38:00Z", "r", 81.307797, -0.814178),
    ("Muenchen", 48.13, 11.5, "2035-06-12T17:17:00Z", "t", 180.188707, 45.969376),
    ("Muenchen", 48.13, 11.5, "2035-06-12T23:45:00Z", "s", 275.441270, -0.919037),
    ("Sydney", -33.87, 151.21, "2026-11-26T10:57:00Z", "r", 56.029686, -0.788131),
    ("Sydney", -33.87, 151.21, "2026-11-26T15:47:00Z", "t", 359.924249, 27.932764),
    ("Sydney", -33.87, 151.21, "2026-11-26T20:39:00Z", "s", 303.233890, -0.932643),
    ("Sydney", -33.87, 151.21, "2026-11-27T11:56:00Z", "r", 58.358512, -0.678897),
    ("Sydney", -33.87, 151.21, "2026-11-27T16:52:00Z", "t", 359.854143, 30.249179),
    ("Sydney", -33.87, 151.21, "2026-11-27T21:53:00Z", "s", 299.769908, -0.961389),
    ("Sydney", -33.87, 151.21, "2026-11-28T12:43:00Z", "r", 63.179354, -0.827813),
    ("Sydney", -33.87, 151.21, "2026-11-28T17:52:00Z", "t", 359.816412, 34.366816),
    ("Sydney", -33.87, 151.21, "2026-11-28T23:07:00Z", "s", 294.206107, -0.999505),
    ("Sydney", -33.87, 151.21, "2035-06-10T00:25:00Z", "r", 71.989072, -0.716303),
    ("Sydney", -33.87, 151.21, "2035-06-10T05:56:00Z", "t", 359.775059, 41.367181),
    ("Sydney", -33.87, 151.21, "2035-06-10T11:31:00Z", "s", 286.077171, -0.953262),
    ("Sydney", -33.87, 151.21, "2035-06-11T01:09:00Z", "r", 76.165903, -0.729575),
    ("Sydney", -33.87, 151.21, "2035-06-11T06:49:00Z", "t", 359.922500, 44.998417),
    ("Sydney", -33.87, 151.21, "2035-06-11T12:35:00Z", "s", 281.478448, -1.012428),
    ("Sydney", -33.87, 151.21, "2035-06-12T01:48:00Z", "r", 81.008874, -0.819932),
    ("Sydney", -33.87, 151.21, "2035-06-12T07:39:00Z", "t", 359.968739, 49.107927),
    ("Sydney", -33.87, 151.21, "2035-06-12T13:36:00Z", "s", 276.491131, -0.952591),
    ("Quito", -0.18, -78.47, "2026-11-26T00:26:00Z", "r", 62.354271, -0.772610),
    ("Quito", -0.18, -78.47, "2026-11-26T06:42:00Z", "t", 359.651853, 61.731035),
    ("Quito", -0.18, -78.47, "2026-11-26T12:57:00Z", "s", 297.429521, -0.896656),
    ("Quito", -0.18, -78.47, "2026-11-27T01:33:00Z", "r", 63.344379, -0.661205),
    ("Quito", -0.18, -78.47, "2026-11-27T07:48:00Z", "t", 359.597662, 63.292593),
    ("Quito", -0.18, -78.47, "2026-11-27T14:02:00Z", "s", 295.370123, -0.848400),
    ("Quito", -0.18, -78.47, "2026-11-28T02:36:00Z", "r", 66.387331, -0.647034),
    ("Quito", -0.18, -78.47, "2026-11-28T08:50:00Z", "t", 359.430763, 66.839039),
    ("Quito", -0.18, -78.47, "2026-11-28T15:03:00Z", "s", 291.472855, -0.927441),
    ("Quito", -0.18, -78.47, "2035-06-10T03:07:00Z", "s", 284.384019, -0.852635),
    ("Quito", -0.18, -78.47, "2035-06-10T15:36:00Z", "r", 77.289998, -0.832418),
    ("Quito", -0.18, -78.47, "2035-06-10T21:49:00Z", "t", 359.482852, 77.801942),
    ("Quito", -0.18, -78.47, "2035-06-11T04:01:00Z", "s", 280.878060, -0.849124),
    ("Quito", -0.18, -78.47, "2035-06-11T16:29:00Z", "r", 81.088101, -0.592710),
    ("Quito", -0.18, -78.47, "2035-06-11T22:40:00Z", "t", 359.710103, 81.783354),
    ("Quito", -0.18, -78.47, "2035-06-12T04:52:00Z", "s", 276.866073, -0.942007),
    ("Quito", -0.18, -78.47, "2035-06-12T17:17:00Z", "r", 85.241283, -0.808249),
    ("Quito", -0.18, -78.47, "2035-06-12T23:29:00Z", "t", 357.153265, 86.056441),
]
var worstRTS = 0.0, nRTS = 0
for (_, lat, lon, s, flag, _, el) in rtsRefs {
    if flag == "t" && el < 0 { continue }
    let ev = iso.date(from: s)!
    guard let p = calc.moonPass(at: ev.addingTimeInterval(-1800), observer: Observer(latitude: lat, longitude: lon)) else { continue }
    guard let mine = flag == "r" ? p.rise : flag == "s" ? p.set : p.transit else { continue }
    worstRTS = max(worstRTS, abs(mine.timeIntervalSince(ev)) / 60); nRTS += 1
}
print(String(format: "Auf-/Untergang (%d Ereignisse, München/Sydney/Quito): max. Abweichung %.2f min", nRTS, worstRTS))

