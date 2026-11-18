import Foundation

/// Perfiles de interruptor, todos sintetizados: ruido filtrado + resonancias amortiguadas. Nada grabado.
public enum PerfilTeclas: String, CaseIterable, Sendable {
    case thock, clack, crema, burbuja

    public var nombre: String {
        switch self {
        case .thock: return "Thock (grave y seco)"
        case .clack: return "Clack (agudo y nítido)"
        case .crema: return "Crema (suave)"
        case .burbuja: return "Burbuja (redondo)"
        }
    }

    fileprivate struct Resonancia { var f: Double; var tau: Double; var a: Double }

    fileprivate struct Parametros {
        var cuerpo: [Resonancia]
        /// El tono arranca esto más alto (proporción) y baja al normal: el "golpe".
        var caida: Double
        var caidaTau: Double
        var rudoF: Double, rudoQ: Double, rudoTau: Double, rudoA: Double
        var timbre: Resonancia?
        var brillo: Double
        var ataque: Double
        var duracion: Double
    }

    /// Los agudos pesan más al oído: el clack baja un poco para sonar tan fuerte como los demás.
    fileprivate var nivel: Double { self == .clack ? 0.6 : 1.0 }

    fileprivate var parametros: Parametros {
        switch self {
        case .thock:
            // Más cuerpo (un grave a 110 Hz), menos chasquido (el ruido baja y se filtra más) y una cola corta.
            return Parametros(cuerpo: [.init(f: 165, tau: 0.034, a: 1.0), .init(f: 110, tau: 0.030, a: 0.7), .init(f: 330, tau: 0.016, a: 0.28)],
                              caida: 0.35, caidaTau: 0.006,
                              rudoF: 1300, rudoQ: 0.9, rudoTau: 0.005, rudoA: 0.26, timbre: nil, brillo: 2800, ataque: 0.0010, duracion: 0.115)
        case .clack:
            return Parametros(cuerpo: [.init(f: 520, tau: 0.012, a: 0.5), .init(f: 1100, tau: 0.008, a: 0.25)], caida: 0.1, caidaTau: 0.004,
                              rudoF: 3400, rudoQ: 1.2, rudoTau: 0.006, rudoA: 0.8, timbre: .init(f: 2800, tau: 0.008, a: 0.35),
                              brillo: 5200, ataque: 0.0004, duracion: 0.08)
        case .crema:
            return Parametros(cuerpo: [.init(f: 235, tau: 0.032, a: 1.0), .init(f: 470, tau: 0.015, a: 0.2)], caida: 0.15, caidaTau: 0.008,
                              rudoF: 900, rudoQ: 0.7, rudoTau: 0.008, rudoA: 0.20, timbre: nil, brillo: 1800, ataque: 0.0015, duracion: 0.11)
        case .burbuja:
            return Parametros(cuerpo: [.init(f: 880, tau: 0.045, a: 1.0), .init(f: 1760, tau: 0.018, a: 0.12)], caida: 0.9, caidaTau: 0.012,
                              rudoF: 2600, rudoQ: 2.0, rudoTau: 0.003, rudoA: 0.08, timbre: nil, brillo: 3200, ataque: 0.0006, duracion: 0.14)
        }
    }
}

public enum SintesisTeclas {
    public static let tasa = 44100.0
    /// Volumen medio de cada sonido (RMS de sus primeros 40 ms) para que ningún perfil suene más fuerte que otro.
    static let rmsObjetivo = 0.18
    static let limite = 0.95

    /// Un sonido de tecla: `abajo` (pulsar) o su versión más ligera al soltar; `grande` para espacio, intro y retroceso.
    public static func generar(_ perfil: PerfilTeclas, abajo: Bool, grande: Bool) -> [Float] {
        let p = perfil.parametros
        let factorF = (abajo ? 1.0 : 1.25) * (grande ? 0.72 : 1.0)
        let factorTau = (abajo ? 1.0 : 0.5) * (grande ? 1.35 : 1.0)
        let nivel = abajo ? 1.0 : 0.45
        let n = Int(p.duracion * factorTau.squareRoot() * (abajo ? 1 : 0.8) * tasa)
        let indice = UInt64(PerfilTeclas.allCases.firstIndex(of: perfil) ?? 0)
        var azar = Azar(semilla: indice &* 977 &+ (abajo ? 7 : 11) &+ (grande ? 101 : 0))
        var filtro = PasaBanda(f: p.rudoF * factorF, q: p.rudoQ)
        var fases = [Double](repeating: 0, count: p.cuerpo.count + 1)
        var salida = [Double](repeating: 0, count: n)
        let dt = 1 / tasa
        // Traqueteo del estabilizador en las teclas grandes: un segundo golpe de ruido agudo, unos 11 ms después.
        let retardoTraqueteo = 0.011
        var filtroTraqueteo = PasaBanda(f: 4200, q: 1.5)
        for i in 0..<n {
            let t = Double(i) * dt
            let glide = 1 + p.caida * exp(-t / p.caidaTau)
            var v = 0.0
            for (k, r) in p.cuerpo.enumerated() {
                fases[k] += 2 * .pi * r.f * factorF * glide * dt
                v += r.a * exp(-t / (r.tau * factorTau)) * sin(fases[k])
            }
            if let m = p.timbre {
                fases[p.cuerpo.count] += 2 * .pi * m.f * factorF * dt
                v += m.a * exp(-t / (m.tau * factorTau)) * sin(fases[p.cuerpo.count])
            }
            v += p.rudoA * exp(-t / (p.rudoTau * factorTau)) * filtro.paso(azar.siguiente())
            if grande, t > retardoTraqueteo {
                v += (abajo ? 0.22 : 0.10) * exp(-(t - retardoTraqueteo) / 0.004) * filtroTraqueteo.paso(azar.siguiente())
            } else if grande {
                _ = filtroTraqueteo.paso(azar.siguiente())
            }
            salida[i] = v * nivel
        }
        // Suaviza los agudos (dos polos: cae más rápido que uno), entra con rampa corta y sale en 6 ms para no hacer clic.
        let rc = 1 / (2 * Double.pi * p.brillo)
        let alfa = dt / (rc + dt)
        var previo = 0.0, previo2 = 0.0
        let cola = Int(0.006 * tasa)
        for i in 0..<n {
            previo += alfa * (salida[i] - previo)
            previo2 += alfa * (previo - previo2)
            var v = previo2 * min(1, Double(i) * dt / max(p.ataque, dt))
            if i > n - cola { v *= Double(n - i) / Double(cola) }
            salida[i] = v
        }
        // Volumen parejo: RMS de los primeros 40 ms al objetivo (más bajo al soltar) y tope suave.
        let ventana = min(n, Int(0.04 * tasa))
        let rms = (salida[0..<ventana].reduce(0) { $0 + $1 * $1 } / Double(max(ventana, 1))).squareRoot()
        let ganancia = rms > 0 ? rmsObjetivo * perfil.nivel * (abajo ? 1 : 0.5) / rms : 0
        return salida.map { Float(topeSuave($0 * ganancia)) }
    }

    /// Lineal hasta 0,7 y después se curva hacia `limite`: nunca recorta.
    static func topeSuave(_ x: Double) -> Double {
        let a = abs(x)
        guard a > 0.7 else { return x }
        let y = 0.7 + (limite - 0.7) * tanh((a - 0.7) / (limite - 0.7))
        return x < 0 ? -y : y
    }

    /// El mismo sonido más agudo (razón > 1) o más grave (< 1), por interpolación cúbica. Se calcula al armar el perfil,
    /// no al pulsar.
    public static func conTono(_ x: [Float], razon: Double) -> [Float] {
        guard razon > 0, razon != 1, x.count > 4 else { return x }
        let n = Int(Double(x.count) / razon)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let pos = Double(i) * razon
            let j = Int(pos)
            let f = Float(pos - Double(j))
            let p0 = x[max(j - 1, 0)], p1 = x[min(j, x.count - 1)], p2 = x[min(j + 1, x.count - 1)], p3 = x[min(j + 2, x.count - 1)]
            y[i] = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)))
        }
        return y
    }

    /// Razones de tono precalculadas: de `1 - maximo` a `1 + maximo`, `pasos` impares (el del centro es 1).
    public static func razones(maximo: Double, pasos: Int) -> [Double] {
        let n = max(pasos | 1, 1)
        if n == 1 { return [1] }
        var r: [Double] = []
        for i in 0..<n {
            let k: Double = Double(i) / Double(n - 1) * 2 - 1
            r.append(1 + maximo * k)
        }
        return r
    }
}

// MARK: - Piezas

public struct Azar {
    var estado: UInt64
    public init(semilla: UInt64) { estado = semilla &* 0x9E37_79B9_7F4A_7C15 | 1 }
    /// Ruido blanco en -1...1 (xorshift64*).
    public mutating func siguiente() -> Double {
        estado ^= estado >> 12
        estado ^= estado << 25
        estado ^= estado >> 27
        let r = estado &* 0x2545_F491_4F6C_DD1D
        return Double(Int64(bitPattern: r >> 11)) / Double(1 << 52) - 1
    }
}

/// Filtro pasa banda (biquad, ganancia 1 en el centro).
struct PasaBanda {
    private var b0 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(f: Double, q: Double) {
        let w = 2 * Double.pi * min(f, SintesisTeclas.tasa * 0.45) / SintesisTeclas.tasa
        let alfa = sin(w) / (2 * q)
        let a0 = 1 + alfa
        b0 = alfa / a0
        b2 = -alfa / a0
        a1 = -2 * cos(w) / a0
        a2 = (1 - alfa) / a0
    }

    mutating func paso(_ x: Double) -> Double {
        let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y * 3  // el ruido blanco de un solo banda sale muy bajo: se compensa para que pese lo que dice rudoA
    }
}

// MARK: - Medición

public enum AnalisisAudio {
    public static func pico(_ x: [Float]) -> Double { Double(x.reduce(0) { max($0, abs($1)) }) }

    public static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    public static func duracion(_ x: [Float]) -> Double { Double(x.count) / SintesisTeclas.tasa }

    /// Centroide espectral en Hz (el "brillo" del sonido): promedio de las frecuencias ponderado por su magnitud.
    public static func centroide(_ x: [Float]) -> Double {
        guard x.count > 8 else { return 0 }
        var n = 1
        while n < x.count { n <<= 1 }
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        for i in 0..<x.count { re[i] = Double(x[i]) * (0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(x.count - 1))) }
        fft(&re, &im)
        var suma = 0.0, pesos = 0.0
        for k in 1..<(n / 2) {
            let m = (re[k] * re[k] + im[k] * im[k]).squareRoot()
            suma += m * Double(k) * SintesisTeclas.tasa / Double(n)
            pesos += m
        }
        return pesos > 0 ? suma / pesos : 0
    }

    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var largo = 2
        while largo <= n {
            let ang = -2 * Double.pi / Double(largo)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<(largo / 2) {
                    let a = i + k, b = i + k + largo / 2
                    let tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    (cr, ci) = (cr * wr - ci * wi, cr * wi + ci * wr)
                }
                i += largo
            }
            largo <<= 1
        }
    }

    /// WAV de 16 bits, mono, a la tasa de la síntesis.
    public static func datosWAV(_ x: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(x.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(SintesisTeclas.tasa)); u32(UInt32(SintesisTeclas.tasa) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for v in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32767))) }
        return d
    }
}
