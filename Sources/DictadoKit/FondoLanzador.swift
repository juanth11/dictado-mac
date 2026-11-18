import Foundation

/// Qué se ve detrás del lanzador: el fondo de pantalla del Mac (por omisión), una de las paletas propias de la app o una imagen que
/// el dueño elige. Se guarda como texto (`mac`, `paleta:lagunaDurazno`, `imagen:/ruta/foto.jpg`) en el ajuste `lanzador.fondo` o,
/// por espacio, en la línea `fondo:` de `espacios.txt`. Además: un fondo de macOS por nombre (`sistema:Sonoma` o `Sonoma` suelto) y un
/// aéreo animado de macOS (`aereo:Patagonia`, por nombre o por identificador).
public enum FondoLanzador: Equatable, Sendable {
    case mac
    case paleta(String)
    case imagen(String)
    /// Un fondo de macOS por su nombre (el de su archivo sin extensión: Sonoma, iMac Orange, Pro Black…).
    case sistema(String)
    /// Un aéreo animado de macOS, por nombre ("Patagonia") o identificador (o su comienzo).
    case aereo(String)

    /// Los nombres de las paletas propias de la app (`AuroraPaleta`): un nombre suelto que esté aquí es paleta; cualquier otro es un fondo
    /// de macOS. Si se agrega una paleta, se agrega aquí.
    public static let paletasConocidas: Set<String> = ["lagunadurazno", "medianocheoro", "ciruelacoral", "bosquelima", "tintalavanda", "terracota"]

    /// nil si el texto está vacío o no dice nada reconocible. Un nombre suelto se toma como paleta.
    public init?(texto: String, home: String = NSHomeDirectory()) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let dos = t.firstIndex(of: ":") {
            let clave = BusquedaApps.normalizar(String(t[..<dos]))
            let valor = t[t.index(after: dos)...].trimmingCharacters(in: .whitespaces)
            switch clave {
            case "paleta":
                guard !valor.isEmpty else { return nil }
                self = .paleta(valor)
                return
            case "imagen", "foto", "archivo":
                guard !valor.isEmpty else { return nil }
                self = .imagen(ReglasDock.expandir(valor, home: home))
                return
            case "sistema", "macos":
                guard !valor.isEmpty else { return nil }
                self = .sistema(valor)
                return
            case "aereo", "aerial", "animado":
                guard !valor.isEmpty else { return nil }
                self = .aereo(valor)
                return
            default: break
            }
        }
        if ["mac", "fondo del mac", "escritorio", "sistema"].contains(BusquedaApps.normalizar(t)) {
            self = .mac
            return
        }
        if t.hasPrefix("/") || t.hasPrefix("~") {
            self = .imagen(ReglasDock.expandir(t, home: home))
            return
        }
        // Un nombre suelto: una paleta propia si lo es; si no, un fondo de macOS ("Sonoma", "iMac Orange").
        self = Self.paletasConocidas.contains(BusquedaApps.normalizar(t)) ? .paleta(t) : .sistema(t)
    }

    public var texto: String {
        switch self {
        case .mac: return "mac"
        case .paleta(let n): return "paleta:" + n
        case .imagen(let r): return "imagen:" + r
        case .sistema(let n): return "sistema:" + n
        case .aereo(let n): return "aereo:" + n
        }
    }

    /// ¿Es un aéreo animado? (Lanzador y Centro lo reproducen en bucle; el escritorio lleva un cuadro fijo.)
    public var esAereo: Bool { if case .aereo = self { return true } else { return false } }

    /// El fondo que vale: el del espacio activo si lo tiene; si no, el global; si no, el fondo del Mac.
    public static func resolver(espacio: String?, global: String?, home: String = NSHomeDirectory()) -> FondoLanzador {
        if let e = espacio.flatMap({ FondoLanzador(texto: $0, home: home) }) { return e }
        if let g = global.flatMap({ FondoLanzador(texto: $0, home: home) }) { return g }
        return .mac
    }
}

/// Si la imagen de fondo pide letra oscura o clara: por su luminancia media (0 negro … 1 blanco). Con el velo del diseño, un
/// fondo más claro que el umbral va con el tema claro.
public enum LuminanciaFondo {
    public static let umbralClaro = 0.62

    /// Luminancia relativa (Rec. 709) de un color sRGB con canales de 0 a 1.
    public static func luminancia(r: Double, g: Double, b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public static func esClaro(_ luminancia: Double) -> Bool { luminancia >= umbralClaro }
}

extension EspaciosIsla {
    /// El texto de `espacios.txt` con la línea `fondo:` de ese espacio puesta (o quitada si `fondo` es nil). Lo demás (comentarios,
    /// orden, otras líneas) queda tal cual. Si el espacio no existe, el texto no cambia.
    public static func conFondo(_ texto: String, espacio: String, fondo: FondoLanzador?) -> String {
        var lineas = texto.components(separatedBy: "\n")
        let buscado = BusquedaApps.normalizar(espacio)
        var inicio: Int?
        for (i, cruda) in lineas.enumerated() {
            let l = cruda.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("["), l.hasSuffix("]") else { continue }
            if BusquedaApps.normalizar(String(l.dropFirst().dropLast())) == buscado { inicio = i; break }
        }
        guard let inicio else { return texto }
        var fin = lineas.count   // hasta la siguiente sección
        for i in (inicio + 1)..<max(lineas.count, inicio + 1) {
            let l = lineas[i].trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("["), l.hasSuffix("]") { fin = i; break }
        }
        var existente: Int?
        var ultimaUtil = inicio
        for i in (inicio + 1)..<max(fin, inicio + 1) {
            let l = lineas[i].trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            if !l.hasPrefix("#") { ultimaUtil = i }
            if let dos = l.firstIndex(of: ":"), BusquedaApps.normalizar(String(l[..<dos])) == "fondo" { existente = i }
        }
        switch (existente, fondo) {
        case (let i?, let f?): lineas[i] = "fondo: " + f.texto
        case (let i?, nil): lineas.remove(at: i)
        case (nil, let f?): lineas.insert("fondo: " + f.texto, at: ultimaUtil + 1)
        case (nil, nil): break
        }
        return lineas.joined(separator: "\n")
    }
}
