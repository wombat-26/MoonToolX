import Foundation
import CoreGraphics
import ImageIO
import simd

// MARK: - Mondbild zur Laufzeit

/// Zeichnet die Mondscheibe aus der NASA-Karte LRO/LROC (CGI Moon Kit, gemeinfrei) für eine beliebige
/// Ansicht: Phase stufenlos, mit Libration. Lunar-Lambert-Photometrie und Erdschein wie zuvor in
/// Tools/render_moon.py. Bildachsen: Mondnordpol oben, Mondosten (Mare Crisium) rechts.
final class MoonRenderer: @unchecked Sendable {
    /// App: Karte 4096 × 2048. Widget: Karte 2048 × 1024, denn Widget-Erweiterungen haben wenig Speicher.
    static let shared: MoonRenderer? = {
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        return MoonRenderer(resource: isExtension ? "moon_map_2k" : "moon_map_4k")
    }()

    /// Kantenlänge des Widget-Mondbilds in Pixeln (größte Scheibe im Widget: 124 pt, also 248 Pixel)
    static let widgetImageSize = 256

    private let width: Int
    private let height: Int
    /// Karte als RGB, je Kanal 8 Bit, Farbsättigung auf 45 % reduziert
    private let texture: [UInt8]
    /// sRGB-Wert (0…255) → lineare Helligkeit
    private let toLinear: [Float]
    /// lineare Helligkeit (0…1 in 4096 Stufen) → sRGB-Wert
    private let toDisplay: [UInt8]
    /// Belichtung, bei der der Vollmond gerade nicht überstrahlt
    private var fullMoonGain: Float = 1

    private let lock = NSLock()
    private var cache: [(key: String, image: CGImage)] = []

    convenience init?(resource: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: resource, withExtension: "jpg") else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard w >= 64, h >= 32,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let _ = Optional(context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))),
              let data = context.data else { return nil }

        let rgba = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            let r = Float(rgba[i * 4]), g = Float(rgba[i * 4 + 1]), b = Float(rgba[i * 4 + 2])
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            rgb[i * 3] = UInt8(min(max(lum + 0.45 * (r - lum) + 0.5, 0), 255))
            rgb[i * 3 + 1] = UInt8(min(max(lum + 0.45 * (g - lum) + 0.5, 0), 255))
            rgb[i * 3 + 2] = UInt8(min(max(lum + 0.45 * (b - lum) + 0.5, 0), 255))
        }
        width = w
        height = h
        texture = rgb
        toLinear = (0..<256).map { powf(Float($0) / 255, 2.2) }
        toDisplay = (0..<4096).map { UInt8(powf(Float($0) / 4095, 1 / 2.2) * 255 + 0.5) }

        // Vollmond bei mittlerer Libration als Bezug für die Belichtung
        let full = MoonAspect(subObserverLonDeg: 0, subObserverLatDeg: 0, subSolarLonDeg: 0, subSolarLatDeg: 0,
                              axisPositionAngleDeg: 0)
        let raw = rawImage(aspect: full, n: 384)
        fullMoonGain = 0.96 / max(Self.percentile(raw, fraction: 0.997, above: -1, minCount: 0) ?? 1, 1e-6)
    }

    /// Mondbild mit `size` × `size` Pixeln, schwarzer Hintergrund. Ergebnisse werden kurz zwischengespeichert.
    func image(aspect: MoonAspect, size: Int) -> CGImage? {
        let aspect = aspect.rounded
        let key = "\(aspect.imageKey)_\(size)"
        lock.lock()
        if let hit = cache.first(where: { $0.key == key }) {
            lock.unlock()
            return hit.image
        }
        lock.unlock()

        guard let image = render(aspect: aspect, size: size) else { return nil }
        lock.lock()
        cache.append((key, image))
        if cache.count > 6 { cache.removeFirst() }
        lock.unlock()
        return image
    }

    // MARK: Rechnung

    private static func lunarLambert(_ alpha: Float) -> Float {
        min(max(1 - 0.019 * alpha + 2.42e-4 * alpha * alpha - 1.46e-6 * alpha * alpha * alpha, 0), 1)
    }

    /// Lineare Helligkeit vor der Belichtung: n × n Pixel, je drei Kanäle; außerhalb der Scheibe −1.
    private func rawImage(aspect: MoonAspect, n: Int) -> [Float] {
        let toObserver = MoonAspect.direction(lonDeg: aspect.subObserverLonDeg, latDeg: aspect.subObserverLatDeg)
        let toSun = MoonAspect.direction(lonDeg: aspect.subSolarLonDeg, latDeg: aspect.subSolarLatDeg)
        // Bildachsen im mondfesten System: rechts = Osten, oben = Norden, z zum Beobachter
        let east = simd_cross(SIMD3(0, 0, 1), toObserver)
        let right = simd_length(east) > 1e-9 ? simd_normalize(east) : SIMD3(0, 1, 0)
        let up = simd_cross(toObserver, right)

        let alpha = Float(aspect.phaseAngleDeg)
        let lf = max(Self.lunarLambert(alpha), 0.8)             // helle Sichelränder wie im Foto
        let earthFraction = (1 - cos(alpha * .pi / 180)) / 2    // Erdphase vom Mond aus
        let shine = 0.0065 * earthFraction * earthFraction

        let w = width, h = height
        var out = [Float](repeating: -1, count: n * n * 3)
        out.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            texture.withUnsafeBufferPointer { tex in
                toLinear.withUnsafeBufferPointer { lin in
                    let pixels = SendablePointer(base), tex = SendableBuffer(tex), lin = SendableBuffer(lin)
                    DispatchQueue.concurrentPerform(iterations: n) { row in
                        let y = -((Double(row) + 0.5) / Double(n) * 2 - 1)
                        for col in 0..<n {
                            let x = (Double(col) + 0.5) / Double(n) * 2 - 1
                            let r2 = x * x + y * y
                            guard r2 <= 1 else { continue }
                            let z = (1 - r2).squareRoot()
                            let p = x * right + y * up + z * toObserver
                            let lat = asin(min(max(p.z, -1), 1))
                            let lon = atan2(p.y, p.x)

                            // bilinear aus der Karte (Länge −180° am linken Rand, Nordpol oben)
                            let u = (lon / .pi + 1) / 2 * Double(w) - 0.5
                            let v = (0.5 - lat / .pi) * Double(h) - 0.5
                            let uf = u.rounded(.down), vf = v.rounded(.down)
                            let fu = Float(u - uf), fv = Float(v - vf)
                            let u0 = ((Int(uf) % w) + w) % w, u1 = (u0 + 1) % w
                            let v0 = min(max(Int(vf), 0), h - 1), v1 = min(max(Int(vf) + 1, 0), h - 1)

                            let mu0 = Float(simd_dot(p, toSun)), mu = Float(z)
                            let lit = mu0 > 0 ? 2 * lf * mu0 / max(mu0 + mu, 1e-6) + (1 - lf) * mu0 : 0
                            let light = lit + shine
                            let o = (row * n + col) * 3
                            for c in 0..<3 {
                                let a = lin.buffer[Int(tex.buffer[(v0 * w + u0) * 3 + c])]
                                let b = lin.buffer[Int(tex.buffer[(v0 * w + u1) * 3 + c])]
                                let d = lin.buffer[Int(tex.buffer[(v1 * w + u0) * 3 + c])]
                                let e = lin.buffer[Int(tex.buffer[(v1 * w + u1) * 3 + c])]
                                let albedo = (a * (1 - fu) + b * fu) * (1 - fv) + (d * (1 - fu) + e * fu) * fv
                                pixels.pointer[o + c] = albedo * light
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    /// Perzentil des hellsten Kanals über alle Scheibenpixel, die heller als `above` sind.
    private static func percentile(_ raw: [Float], fraction: Double, above: Float, minCount: Int) -> Float? {
        var values: [Float] = []
        values.reserveCapacity(raw.count / 3)
        var i = 0
        while i < raw.count {
            let m = max(raw[i], raw[i + 1], raw[i + 2])
            if m >= 0, m > above { values.append(m) }
            i += 3
        }
        guard values.count > minCount, !values.isEmpty else { return nil }
        // Histogramm statt Sortieren
        let top = max(values.max() ?? 1, 1e-9)
        var bins = [Int](repeating: 0, count: 4096)
        for v in values { bins[min(Int(v / top * 4095), 4095)] += 1 }
        let target = Int((Double(values.count) * fraction).rounded(.up))
        var sum = 0
        for (index, count) in bins.enumerated() {
            sum += count
            if sum >= target { return (Float(index) + 0.5) / 4095 * top }
        }
        return top
    }

    private func render(aspect: MoonAspect, size: Int) -> CGImage? {
        let n = size * 2                                         // zweifach überabgetastet
        let raw = rawImage(aspect: aspect, n: n)

        // Belichtung je Phase: schmale Sicheln heller, höchstens das 2,2-Fache des Vollmonds
        let minCount = n * n / 7200
        let p = Self.percentile(raw, fraction: 0.99, above: 0.02, minCount: minCount) ?? 1
        let gain = min(max(fullMoonGain, 0.8832 / max(p, 1e-6)), fullMoonGain * 2.2)

        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for row in 0..<size {
            for col in 0..<size {
                let o = (row * size + col) * 4
                for c in 0..<3 {
                    var sum: Float = 0
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let v = raw[((row * 2 + dy) * n + col * 2 + dx) * 3 + c]
                            sum += min(max(v * gain, 0), 1)       // außerhalb der Scheibe (−1) schwarz
                        }
                    }
                    bytes[o + c] = toDisplay[Int(sum / 4 * 4095 + 0.5)]
                }
                bytes[o + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Zeiger für die zeilenweise parallele Rechnung: Jede Zeile schreibt nur ihre eigenen Pixel.
private struct SendablePointer: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<Float>
    init(_ pointer: UnsafeMutablePointer<Float>) { self.pointer = pointer }
}

private struct SendableBuffer<T>: @unchecked Sendable {
    let buffer: UnsafeBufferPointer<T>
    init(_ buffer: UnsafeBufferPointer<T>) { self.buffer = buffer }
}
