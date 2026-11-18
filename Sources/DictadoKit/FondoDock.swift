import Foundation

/// Los tres tonos del acabado del Dock sacados del fondo de pantalla: la base (el tono más hondo, muy oscuro) y los dos
/// colores de la franja de luz. Valores 0xRRGGBB.
public struct TonosFondo: Equatable, Sendable {
    public var hondo: UInt32
    public var c1: UInt32
    public var c2: UInt32

    public init(hondo: UInt32, c1: UInt32, c2: UInt32) {
        self.hondo = hondo
        self.c1 = c1
        self.c2 = c2
    }
}

public struct MuestraColor: Equatable, Sendable {
    public var r: Double, g: Double, b: Double   // 0 a 1
    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Saca los tonos del Dock de unos pocos píxeles (una miniatura del fondo): lógica pura, sin leer ninguna imagen.
public enum AnalisisFondo {
    /// El brillo más alto que puede tener la base (el Dock se queda oscuro aunque el fondo sea claro).
    public static let brilloMaximoBase = 0.20
    public static let brilloMinimoBase = 0.05

    static func hsv(_ m: MuestraColor) -> (h: Double, s: Double, v: Double) {
        let mx = max(m.r, m.g, m.b), mn = min(m.r, m.g, m.b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == m.r { h = ((m.g - m.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == m.g { h = (m.b - m.r) / d + 2 }
            else { h = (m.r - m.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func rgb(h: Double, s: Double, v: Double) -> MuestraColor {
        let hh = (h - h.rounded(.down)) * 6, i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return MuestraColor(r: v, g: t, b: p)
        case 1: return MuestraColor(r: q, g: v, b: p)
        case 2: return MuestraColor(r: p, g: v, b: t)
        case 3: return MuestraColor(r: p, g: q, b: v)
        case 4: return MuestraColor(r: t, g: p, b: v)
        default: return MuestraColor(r: v, g: p, b: q)
        }
    }

    public static func hex(_ m: MuestraColor) -> UInt32 {
        func c(_ x: Double) -> UInt32 { UInt32((max(0, min(1, x)) * 255).rounded()) }
        return (c(m.r) << 16) | (c(m.g) << 8) | c(m.b)
    }

    static func luminancia(_ m: MuestraColor) -> Double { 0.2126 * m.r + 0.7152 * m.g + 0.0722 * m.b }

    /// nil si no hay muestras.
    ///  · Base: el promedio del cuarto más oscuro, llevado a un brillo entre 5 % y 20 % (se conserva el tono).
    ///  · Primer color: el de más viveza (saturación × brillo).
    ///  · Segundo color: el vivo de tono más lejano al primero; si el fondo es de un solo tono, el primero aclarado.
    public static func derivar(_ muestras: [MuestraColor]) -> TonosFondo? {
        guard !muestras.isEmpty else { return nil }
        let porBrillo = muestras.sorted { luminancia($0) < luminancia($1) }
        let n = max(1, porBrillo.count / 4)
        let oscuras = porBrillo.prefix(n)
        let medio = MuestraColor(r: oscuras.map(\.r).reduce(0, +) / Double(n), g: oscuras.map(\.g).reduce(0, +) / Double(n),
                                 b: oscuras.map(\.b).reduce(0, +) / Double(n))
        let hm = hsv(medio)
        let base = rgb(h: hm.h, s: min(1, max(0.25, hm.s)), v: min(brilloMaximoBase, max(brilloMinimoBase, hm.v)))

        func viveza(_ m: MuestraColor) -> Double { let x = hsv(m); return x.s * x.v }
        let vivas = muestras.filter { hsv($0).s > 0.2 }
        let primera = (vivas.isEmpty ? muestras : vivas).max { viveza($0) < viveza($1) } ?? medio
        let h1 = hsv(primera)
        let c1 = rgb(h: h1.h, s: min(1, max(0.35, h1.s)), v: min(1, max(0.6, h1.v)))
        func distancia(_ a: Double, _ b: Double) -> Double { let d = abs(a - b); return min(d, 1 - d) }
        let lejana = vivas.filter { viveza($0) > 0.25 }.max { distancia(hsv($0).h, h1.h) < distancia(hsv($1).h, h1.h) }
        var c2 = c1
        if let lejana, distancia(hsv(lejana).h, h1.h) > 0.08 {
            let h2 = hsv(lejana)
            c2 = rgb(h: h2.h, s: min(1, max(0.35, h2.s)), v: min(1, max(0.6, h2.v)))
        } else {
            c2 = rgb(h: h1.h, s: max(0.2, h1.s * 0.6), v: 1)
        }
        return TonosFondo(hondo: hex(base), c1: hex(c1), c2: hex(c2))
    }
}
