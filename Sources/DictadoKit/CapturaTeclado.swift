import Foundation

// "Mi teclado": el sonido de tu teclado real, hecho de una grabación corta. Todo el procesado es puro (sin audio ni disco):
// recibe las muestras del micrófono y las horas de cada tecla (solo bajó/subió y su clase), y devuelve los sonidos ya cortados.
// Del audio no se guarda nada salvo esos recortes.

/// Las clases de tecla que se distinguen. Nunca se guarda qué tecla exacta fue.
public enum ClaseTecla: String, CaseIterable, Codable, Sendable {
    case normal, espacio, intro, retroceso

    public var nombre: String {
        switch self {
        case .normal: return "teclas normales"
        case .espacio: return "espacio"
        case .intro: return "intro"
        case .retroceso: return "retroceso"
        }
    }

    /// Las que suenan más pesadas (estabilizador).
    public var pesada: Bool { self != .normal }
}

/// Una tecla que bajó o subió, a los `t` segundos de empezar la grabación. Es todo lo que se guarda de cada tecla.
public struct EventoTecla: Codable, Equatable, Sendable {
    public var t: Double
    public var abajo: Bool
    public var clase: ClaseTecla

    public init(t: Double, abajo: Bool, clase: ClaseTecla) {
        self.t = t
        self.abajo = abajo
        self.clase = clase
    }
}

/// Un golpe que se oyó en la grabación.
public struct Golpe: Equatable, Sendable {
    /// Muestra donde empieza el golpe.
    public var muestra: Int
    public var tiempo: Double
    /// Qué tan fuerte saltó el espectro (relativo al fondo).
    public var fuerza: Double

    public init(muestra: Int, tiempo: Double, fuerza: Double) {
        self.muestra = muestra
        self.tiempo = tiempo
        self.fuerza = fuerza
    }
}

// MARK: - Detección

public enum DetectorGolpes {
    static let ventana = 256
    static let salto = 128

    /// Los golpes de la grabación: flujo espectral en las frecuencias medias y altas (donde suena el clic de una tecla) con un
    /// umbral que se adapta al ruido de alrededor (media + `k` desviaciones en ±0,4 s). Dos golpes más cerca que `separacion`
    /// segundos cuentan como uno (el más fuerte).
    public static func detectar(_ x: [Float], tasa: Double = SintesisTeclas.tasa, k: Double = 4, separacion: Double = 0.025,
                                minimoPico: Float = 0.006) -> [Golpe] {
        let n = ventana
        guard x.count > n * 4 else { return [] }
        let cuadros = (x.count - n) / salto
        guard cuadros > 8 else { return [] }
        let desde = max(1, Int(1500 / (tasa / Double(n)))), hasta = min(n / 2 - 1, Int(16_000 / (tasa / Double(n))))
        var hann = [Double](repeating: 0, count: n)
        for i in 0..<n { hann[i] = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1)) }
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        var previo = [Double](repeating: 0, count: n / 2)
        var actual = [Double](repeating: 0, count: n / 2)
        var flujo = [Double](repeating: 0, count: cuadros)
        for c in 0..<cuadros {
            let base = c * salto
            for i in 0..<n { re[i] = Double(x[base + i]) * hann[i]; im[i] = 0 }
            AnalisisAudio.fft(&re, &im)
            var f = 0.0
            for b in desde...hasta {
                let m = log(1 + 30 * (re[b] * re[b] + im[b] * im[b]).squareRoot())
                actual[b] = m
                f += max(0, m - previo[b])
            }
            swap(&previo, &actual)
            flujo[c] = c == 0 ? 0 : f
        }
        // Media y desviación móviles con sumas acumuladas.
        var s = [Double](repeating: 0, count: cuadros + 1), s2 = s
        for i in 0..<cuadros {
            s[i + 1] = s[i] + flujo[i]
            s2[i + 1] = s2[i] + flujo[i] * flujo[i]
        }
        let medio = max(4, Int(0.4 * tasa / Double(salto)))
        func umbral(_ i: Int) -> Double {
            let a = max(0, i - medio), b = min(cuadros, i + medio + 1)
            let m = Double(b - a)
            let mu = (s[b] - s[a]) / m
            let sd = max(0, (s2[b] - s2[a]) / m - mu * mu).squareRoot()
            return mu + k * sd
        }
        var candidatos: [(i: Int, f: Double)] = []
        for i in 1..<(cuadros - 1) where flujo[i] >= flujo[i - 1] && flujo[i] > flujo[i + 1] && flujo[i] > umbral(i) {
            candidatos.append((i, flujo[i]))
        }
        // El más fuerte gana; los vecinos más cerca que `separacion` se descartan.
        let paso = max(1, Int(separacion * tasa / Double(salto)))
        var elegidos: [(i: Int, f: Double)] = []
        for c in candidatos.sorted(by: { $0.f > $1.f }) where !elegidos.contains(where: { abs($0.i - c.i) < paso }) { elegidos.append(c) }
        var golpes: [Golpe] = []
        for c in elegidos.sorted(by: { $0.i < $1.i }) {
            let ini = c.i * salto
            let fin = min(x.count, ini + 3 * n)
            var pico: Float = 0
            for j in ini..<fin { pico = max(pico, abs(x[j])) }
            guard pico >= minimoPico else { continue }
            // El golpe empieza en la primera muestra que pasa de un cuarto del pico, un poco antes del cuadro.
            var m = max(0, ini - n / 2)
            while m < fin, abs(x[m]) < pico * 0.25 { m += 1 }
            golpes.append(Golpe(muestra: m, tiempo: Double(m) / tasa, fuerza: c.f))
        }
        return golpes
    }
}

// MARK: - Emparejar teclas y golpes

public enum EmparejadorTeclas {
    /// El desfase constante (segundos) entre el reloj de las teclas y el de la grabación: el que hace coincidir más golpes con
    /// teclas. Se prueba de −`rango` a +`rango` en pasos de `paso`; gana el de más aciertos (a igual, el más chico).
    public static func alinear(golpes: [Double], eventos: [Double], rango: Double = 0.6, paso: Double = 0.002,
                               tolerancia: Double = 0.03) -> Double {
        guard !golpes.isEmpty, !eventos.isEmpty else { return 0 }
        let g = golpes.sorted()
        func aciertos(_ d: Double) -> Int {
            var n = 0
            for e in eventos {
                if let h = primeroDespues(g, e + d - tolerancia), h <= e + d + tolerancia { n += 1 }
            }
            return n
        }
        var mejor = 0.0, puntaje = -1
        var d = -rango
        while d <= rango + 1e-9 {
            let p = aciertos(d)
            if p > puntaje || (p == puntaje && abs(d) < abs(mejor)) { puntaje = p; mejor = d }
            d += paso
        }
        // Afina: la mediana de lo que sobra entre cada tecla y su golpe.
        var residuos: [Double] = []
        for e in eventos {
            if let h = primeroDespues(g, e + mejor - tolerancia), h <= e + mejor + tolerancia { residuos.append(h - (e + mejor)) }
        }
        guard !residuos.isEmpty else { return mejor }
        residuos.sort()
        return mejor + residuos[residuos.count / 2]
    }

    /// El primer valor de `g` (ordenado) que es ≥ `t`.
    static func primeroDespues(_ g: [Double], _ t: Double) -> Double? {
        var a = 0, b = g.count
        while a < b {
            let m = (a + b) / 2
            if g[m] < t { a = m + 1 } else { b = m }
        }
        return a < g.count ? g[a] : nil
    }

    /// A cada tecla le toca el primer golpe que cae entre −15 ms y `ventana` después de su hora (ya con el desfase); un golpe no
    /// sirve a dos teclas. Devuelve, por tecla, el índice del golpe (nil: esa tecla no se oyó).
    public static func emparejar(golpes: [Golpe], eventos: [EventoTecla], desfase: Double, ventana: Double = 0.06) -> [Int?] {
        var usados = Set<Int>()
        var salida = [Int?](repeating: nil, count: eventos.count)
        for (j, e) in eventos.enumerated().sorted(by: { $0.element.t < $1.element.t }) {
            let t = e.t + desfase
            if let i = golpes.indices.first(where: { !usados.contains($0) && golpes[$0].tiempo >= t - 0.015 && golpes[$0].tiempo <= t + ventana }) {
                usados.insert(i)
                salida[j] = i
            }
        }
        return salida
    }
}

// MARK: - Recortar y elegir

public struct ConfigRecorte: Sendable {
    public var tasa = SintesisTeclas.tasa
    public var antesMs = 3.0
    /// Duración del recorte por tipo (segundos): pulsar normal, pulsar pesada, soltar normal, soltar pesada.
    public var abajo = 0.100
    public var abajoPesada = 0.150
    public var arriba = 0.060
    public var arribaPesada = 0.090
    /// Otro golpe dentro de este margen antes lo ensucia (queda la cola del anterior).
    public var margenAntes = 0.040
    /// Si el siguiente golpe llega antes de que acabe el recorte (soltar la tecla suena ~90 ms después de pulsarla), el recorte se
    /// corta ahí; si queda de menos de `largoMinimo`, se rechaza por solapado.
    public var largoMinimo = 0.040
    /// Relación pico/ruido mínima, en dB.
    public var snrMinimoDB = 12.0
    public var topeRecorte = 0.985
    public var rmsObjetivo = 0.18
    public var maxPorClase = [ClaseTecla.normal: 24, .espacio: 10, .intro: 10, .retroceso: 10]
    public var minimoNormal = 12
    public init() {}

    func duracion(abajo a: Bool, pesada: Bool) -> Double {
        a ? (pesada ? abajoPesada : abajo) : (pesada ? arribaPesada : arriba)
    }
}

/// Los sonidos de un teclado, por clase: lo que suena al pulsar y al soltar.
public struct JuegoTeclado: Equatable, Sendable {
    public struct Par: Equatable, Sendable {
        public var abajo: [[Float]] = []
        public var arriba: [[Float]] = []
        public init(abajo: [[Float]] = [], arriba: [[Float]] = []) {
            self.abajo = abajo
            self.arriba = arriba
        }
    }

    public var clases: [ClaseTecla: Par] = [:]
    public init(clases: [ClaseTecla: Par] = [:]) { self.clases = clases }

    public func par(_ c: ClaseTecla) -> Par { clases[c] ?? Par() }
    public var total: Int { clases.values.reduce(0) { $0 + $1.abajo.count + $1.arriba.count } }
}

public struct InformeCaptura: Equatable, Sendable {
    public var golpesDetectados = 0
    public var teclas = 0
    public var emparejadas = 0
    public var desfase = 0.0
    public var rechazadas: [String: Int] = [:]
    /// "normal-abajo": 14.
    public var elegidas: [String: Int] = [:]
    public var picoGrabacion = 0.0
    public var rmsRuido = 0.0

    public init() {}

    /// Lo que se le dice a la persona.
    public func mensaje(minimoNormal: Int = 12) -> String {
        let a = elegidas["normal-abajo"] ?? 0, u = elegidas["normal-arriba"] ?? 0
        if picoGrabacion < 0.004 { return "Casi no se oyó nada: revisa que el micrófono sea el de tu Mac y vuelve a intentarlo." }
        if a >= minimoNormal && u >= minimoNormal { return "Listo: \(a) sonidos al pulsar y \(u) al soltar." }
        if golpesDetectados < 10 { return "Se oyeron muy pocas teclas: acerca el teclado al micrófono y vuelve a grabar." }
        return "Salieron solo \(a) sonidos al pulsar y \(u) al soltar de \(minimoNormal) necesarios: escribe con calma, sin pulsar dos teclas a la vez, y repite."
    }

    public func suficiente(minimoNormal: Int = 12) -> Bool {
        (elegidas["normal-abajo"] ?? 0) >= minimoNormal && (elegidas["normal-arriba"] ?? 0) >= minimoNormal
    }

    /// El resumen numérico (para la línea de comandos).
    public var reporte: String {
        var l = ["golpes oídos: \(golpesDetectados)", "teclas registradas: \(teclas)", "teclas con su golpe: \(emparejadas)",
                 String(format: "desfase: %.1f ms", desfase * 1000), String(format: "pico de la grabación: %.3f · ruido (RMS): %.4f", picoGrabacion, rmsRuido)]
        l.append("rechazadas: " + (rechazadas.isEmpty ? "ninguna" : rechazadas.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))
        l.append("elegidas: " + (elegidas.isEmpty ? "ninguna" : elegidas.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))
        return l.joined(separator: "\n")
    }
}

public enum CapturaTeclado {
    struct Candidato {
        var datos: [Float]
        var puntaje: Double
        var rms: Double
    }

    /// De una grabación (`x`, mono a la tasa de `config`) y las horas de las teclas, saca los mejores sonidos de cada clase.
    /// `desfase` fijo: sin él se calcula alineando golpes y teclas.
    public static func procesar(_ x: [Float], eventos: [EventoTecla], config: ConfigRecorte = ConfigRecorte(),
                                desfase fijo: Double? = nil) -> (JuegoTeclado, InformeCaptura) {
        var informe = InformeCaptura()
        informe.picoGrabacion = AnalisisAudio.pico(x)
        informe.teclas = eventos.count
        let golpes = DetectorGolpes.detectar(x, tasa: config.tasa)
        informe.golpesDetectados = golpes.count
        informe.rmsRuido = ruido(x)
        guard !golpes.isEmpty, !eventos.isEmpty else { return (JuegoTeclado(), informe) }
        let desfase = fijo ?? EmparejadorTeclas.alinear(golpes: golpes.map(\.tiempo), eventos: eventos.map(\.t))
        informe.desfase = desfase
        let pares = EmparejadorTeclas.emparejar(golpes: golpes, eventos: eventos, desfase: desfase)
        informe.emparejadas = pares.compactMap { $0 }.count
        func rechazar(_ motivo: String) { informe.rechazadas[motivo, default: 0] += 1 }

        var buenos: [String: [Candidato]] = [:]
        var claseDe: [String: (ClaseTecla, Bool)] = [:]
        let tasa = config.tasa
        for (j, e) in eventos.enumerated() {
            guard let gi = pares[j] else { rechazar("sin-golpe"); continue }
            let g = golpes[gi]
            var dur = config.duracion(abajo: e.abajo, pesada: e.clase.pesada)
            // Otro golpe justo antes ensucia el recorte; uno después lo acorta (con sus 4 ms de aire para salir suave).
            let sucio = golpes.indices.contains { k in
                guard k != gi else { return false }
                let d = golpes[k].tiempo - g.tiempo
                return d < 0 && d > -config.margenAntes
            }
            if sucio { rechazar("solapada"); continue }
            if let siguiente = golpes.indices.compactMap({ k -> Double? in
                let d = golpes[k].tiempo - g.tiempo
                return k != gi && d > 0.002 ? d : nil
            }).min(), siguiente - 0.004 < dur {
                dur = siguiente - 0.004
            }
            if dur < config.largoMinimo { rechazar("solapada"); continue }
            let ini = g.muestra - Int(config.antesMs / 1000 * tasa)
            let n = Int(dur * tasa)
            guard ini >= 0, ini + n <= x.count else { rechazar("borde"); continue }
            let corte = Array(x[ini..<(ini + n)])
            if AnalisisAudio.pico(corte) >= config.topeRecorte { rechazar("saturada"); continue }
            // Ruido de antes del golpe.
            let a = max(0, g.muestra - Int(0.040 * tasa)), b = max(a, g.muestra - Int(0.005 * tasa))
            let fondo = max(1e-5, AnalisisAudio.rms(Array(x[a..<b])))
            let snr = 20 * log10(AnalisisAudio.pico(corte) / fondo)
            if snr < config.snrMinimoDB { rechazar("ruidosa"); continue }
            // Quita la continua, entra y sale suave.
            var s = corte
            let media = Float(s.prefix(Int(config.antesMs / 1000 * tasa)).reduce(0, +)) / Float(max(1, Int(config.antesMs / 1000 * tasa)))
            for i in s.indices { s[i] -= media }
            let entra = Int(0.002 * tasa), sale = Int(0.008 * tasa)
            for i in 0..<min(entra, s.count) { s[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(entra))) }
            for i in 0..<min(sale, s.count) { s[s.count - 1 - i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(sale))) }
            // Cola limpia: lo que queda al final comparado con el pico (menos es mejor).
            let cola = AnalisisAudio.rms(Array(s.suffix(max(1, n / 4)))) / max(1e-9, AnalisisAudio.pico(s))
            let clave = e.clase.rawValue + (e.abajo ? "-abajo" : "-arriba")
            claseDe[clave] = (e.clase, e.abajo)
            buenos[clave, default: []].append(Candidato(datos: s, puntaje: snr - 30 * cola, rms: rmsInicial(s, tasa: tasa)))
        }

        // Volumen parejo: pulsar al objetivo; soltar, en la proporción natural (entre 0,3 y 0,8 de pulsar).
        func mediana(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.sorted()[v.count / 2] }
        var juego = JuegoTeclado()
        for clase in ClaseTecla.allCases {
            let bajan = buenos[clase.rawValue + "-abajo"] ?? [], suben = buenos[clase.rawValue + "-arriba"] ?? []
            let razon = bajan.isEmpty || suben.isEmpty ? 0.5 : min(0.8, max(0.3, mediana(suben.map(\.rms)) / mediana(bajan.map(\.rms))))
            let tope = config.maxPorClase[clase] ?? 10
            func elegir(_ v: [Candidato], objetivo: Double) -> [[Float]] {
                v.sorted { $0.puntaje > $1.puntaje }.prefix(tope).map { normalizar($0.datos, rms: $0.rms, objetivo: objetivo) }
            }
            let par = JuegoTeclado.Par(abajo: elegir(bajan, objetivo: config.rmsObjetivo), arriba: elegir(suben, objetivo: config.rmsObjetivo * razon))
            if !par.abajo.isEmpty || !par.arriba.isEmpty { juego.clases[clase] = par }
            if !par.abajo.isEmpty { informe.elegidas[clase.rawValue + "-abajo"] = par.abajo.count }
            if !par.arriba.isEmpty { informe.elegidas[clase.rawValue + "-arriba"] = par.arriba.count }
        }
        return (juego, informe)
    }

    /// RMS de los primeros 40 ms (lo que pesa al oído), igual que la síntesis.
    public static func rmsInicial(_ s: [Float], tasa: Double) -> Double {
        AnalisisAudio.rms(Array(s.prefix(min(s.count, Int(0.04 * tasa)))))
    }

    static func normalizar(_ s: [Float], rms: Double, objetivo: Double) -> [Float] {
        guard rms > 1e-9 else { return s }
        var g = objetivo / rms
        let pico = AnalisisAudio.pico(s)
        if pico * g > 0.95 { g = 0.95 / pico }
        return s.map { Float(Double($0) * g) }
    }

    /// El ruido de fondo: el RMS del 20 % más callado de la grabación (por tramos de 50 ms).
    static func ruido(_ x: [Float], tasa: Double = SintesisTeclas.tasa) -> Double {
        let paso = max(1, Int(0.05 * tasa))
        var v: [Double] = []
        var i = 0
        while i + paso <= x.count {
            v.append(AnalisisAudio.rms(Array(x[i..<(i + paso)])))
            i += paso
        }
        guard !v.isEmpty else { return 0 }
        v.sort()
        return v[min(v.count - 1, v.count / 5)]
    }
}

// MARK: - WAV y disco

public enum LectorWAV {
    /// Lee un WAV (PCM de 16, 24 o 32 bits, o float de 32), lo pasa a mono y a la tasa de las teclas.
    public static func leer(_ d: Data, tasaDestino: Double = SintesisTeclas.tasa) -> [Float]? {
        let b = [UInt8](d)
        guard b.count > 44, String(decoding: b[0..<4], as: UTF8.self) == "RIFF", String(decoding: b[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var formato = 1, canales = 1, tasa = 44_100, bits = 16
        var i = 12
        var datos: Range<Int>?
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<(i + 4)], as: UTF8.self)
            let largo = u32(i + 4)
            let cuerpo = i + 8
            if id == "fmt ", cuerpo + 16 <= b.count {
                formato = u16(cuerpo)
                canales = max(1, u16(cuerpo + 2))
                tasa = u32(cuerpo + 4)
                bits = u16(cuerpo + 14)
                if formato == 0xFFFE, cuerpo + 26 <= b.count { formato = u16(cuerpo + 24) }
            } else if id == "data" {
                datos = cuerpo..<min(b.count, cuerpo + largo)
                break
            }
            i = cuerpo + largo + (largo & 1)
        }
        guard let datos, formato == 1 || formato == 3, [16, 24, 32].contains(bits) else { return nil }
        let bytes = bits / 8
        let marcos = datos.count / (bytes * canales)
        var mono = [Float](repeating: 0, count: marcos)
        for m in 0..<marcos {
            var suma: Float = 0
            for c in 0..<canales {
                let o = datos.lowerBound + (m * canales + c) * bytes
                let v: Float
                switch (formato, bits) {
                case (3, 32): v = Float(bitPattern: UInt32(u32(o)))
                case (1, 16): v = Float(Int16(bitPattern: UInt16(u16(o)))) / 32768
                case (1, 24):
                    var e = Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16
                    if e & 0x80_0000 != 0 { e -= 0x100_0000 }
                    v = Float(e) / 8_388_608
                default: v = Float(Int32(bitPattern: UInt32(u32(o)))) / 2_147_483_648
                }
                suma += v
            }
            mono[m] = suma / Float(canales)
        }
        return abs(Double(tasa) - tasaDestino) < 1 ? mono : SintesisTeclas.conTono(mono, razon: Double(tasa) / tasaDestino)
    }
}

/// Dónde vive "Mi teclado" y cómo se guarda: un WAV por sonido, `normal-abajo-01.wav`.
public enum AlmacenTeclado {
    public static func carpetaPorOmision() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictado/teclas/mi-teclado", isDirectory: true)
    }

    public static func guardar(_ juego: JuegoTeclado, en carpeta: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: carpeta)
        try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        for (clase, par) in juego.clases {
            for (dir, lista) in [("abajo", par.abajo), ("arriba", par.arriba)] {
                for (i, s) in lista.enumerated() {
                    try AnalisisAudio.datosWAV(s).write(to: carpeta.appendingPathComponent(String(format: "%@-%@-%02d.wav", clase.rawValue, dir, i + 1)), options: .atomic)
                }
            }
        }
    }

    public static func cargar(desde carpeta: URL) -> JuegoTeclado? {
        let fm = FileManager.default
        guard let nombres = try? fm.contentsOfDirectory(atPath: carpeta.path) else { return nil }
        var juego = JuegoTeclado()
        for nombre in nombres.sorted() where nombre.hasSuffix(".wav") {
            let partes = nombre.dropLast(4).split(separator: "-")
            guard partes.count == 3, let clase = ClaseTecla(rawValue: String(partes[0])),
                  let datos = try? Data(contentsOf: carpeta.appendingPathComponent(nombre)), let s = LectorWAV.leer(datos) else { continue }
            var par = juego.clases[clase] ?? JuegoTeclado.Par()
            if partes[1] == "abajo" { par.abajo.append(s) } else if partes[1] == "arriba" { par.arriba.append(s) } else { continue }
            juego.clases[clase] = par
        }
        let normal = juego.par(.normal)
        return normal.abajo.isEmpty ? nil : juego
    }

    public static func existe(en carpeta: URL = carpetaPorOmision()) -> Bool {
        guard let n = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return false }
        return n.contains { $0.hasPrefix("normal-abajo-") }
    }

    /// Borra todo lo de "Mi teclado".
    public static func borrar(en carpeta: URL = carpetaPorOmision()) {
        try? FileManager.default.removeItem(at: carpeta)
    }
}
