// Prüft die Swift-Implementierung gegen Referenzwerte aus JPL DE440 (jplephem, de440s.bsp).
// Aufruf: swiftc -O Shared/Astronomy.swift Tools/main.swift -o /tmp/moonverify && /tmp/moonverify
import Foundation

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

// Entfernung vom Standort und Mondhöhe gegen JPL Horizons (topozentrische Vektoren bzw. AZ/EL, DE441)
let topoRefs: [(String, Double, Double, Double, String, Double, Double)] = [
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-24T19:55:00Z", 355747.8258, 45.663),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T02:00:00Z", 354840.0811, 52.437),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T08:00:00Z", 359683.3063, -1.023),
    ("Muenchen", 48.13, 11.5, 530.0, "2026-11-25T13:30:00Z", 360785.6044, -12.565),
    ("Muenchen", 48.13, 11.5, 530.0, "2030-03-01T12:00:00Z", 379374.7143, 15.633),
    ("Muenchen", 48.13, 11.5, 530.0, "2050-06-15T21:00:00Z", 381256.9373, -25.706),
    ("Muenchen", 48.13, 11.5, 530.0, "2099-12-31T00:00:00Z", 368582.8122, 45.988),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-24T19:55:00Z", 362031.6298, -16.020),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T02:00:00Z", 366234.8264, -82.756),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T08:00:00Z", 361723.4135, -19.896),
    ("Sydney", -33.87, 151.21, 50.0, "2026-11-25T13:30:00Z", 356594.6692, 25.844),
    ("Sydney", -33.87, 151.21, 50.0, "2030-03-01T12:00:00Z", 385385.8776, -41.787),
    ("Sydney", -33.87, 151.21, 50.0, "2050-06-15T21:00:00Z", 375109.6497, 31.801),
    ("Sydney", -33.87, 151.21, 50.0, "2099-12-31T00:00:00Z", 375479.4969, -21.468),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-24T19:55:00Z", 356243.0206, 39.547),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T02:00:00Z", 355899.6386, 38.660),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T08:00:00Z", 358285.7047, 11.629),
    ("Tromsoe", 69.65, 18.96, 100.0, "2026-11-25T13:30:00Z", 358442.4398, 8.588),
    ("Tromsoe", 69.65, 18.96, 100.0, "2030-03-01T12:00:00Z", 381359.6944, -2.409),
    ("Tromsoe", 69.65, 18.96, 100.0, "2050-06-15T21:00:00Z", 378927.9768, -4.040),
    ("Tromsoe", 69.65, 18.96, 100.0, "2099-12-31T00:00:00Z", 369716.3443, 32.661),
]
var worstD = 0.0, worstH = 0.0
for (_, lat, lon, alt, s, km, el) in topoRefs {
    let t = calc.topocentric(at: iso.date(from: s)!, observer: Observer(latitude: lat, longitude: lon, altitudeM: alt))!
    worstD = max(worstD, abs(t.distanceKm - km)); worstH = max(worstH, abs(t.altitudeDeg - el))
}
print(String(format: "Standort (%d Fälle, München/Sydney/Tromsø): max. Abweichung Entfernung %.3f km, Höhe %.4f°",
             topoRefs.count, worstD, worstH))
