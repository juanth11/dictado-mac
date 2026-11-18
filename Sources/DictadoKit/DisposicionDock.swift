import Foundation

/// Una pieza del Dock (la barra de abajo): lo que dice la línea `dock:` de un espacio.
public enum PiezaDock: Equatable, Hashable, Sendable {
    case reloj, agenda, agentes, tareas, dictar, foco, musica, mac, bateria, fecha, papelera, clima, lanzador
    /// El plan de Mañana: lo de hoy y lo de la semana, y un botón para dejar trabajando a los agentes.
    case plan
    /// Las apps abiertas que no están fijas en el Dock: una pila que al tocarla muestra las que corren.
    case abiertas
    /// Las carpetas que tienes abiertas en el Finder: ocupa el lugar de cada una mientras su ventana siga abierta (sin ventanas, nada).
    case finder
    /// Una app por nombre o identificador de paquete.
    case app(String)
    /// Un grupo de apps: el nombre de una carpeta de `carpetas.txt` (3 × 3 iconos que se despliegan hacia arriba).
    case grupo(String)
    /// Una carpeta del Finder, con la ruta ya expandida (`~` resuelto).
    case carpeta(String)
    /// Un hueco pequeño entre bloques (el `|` del archivo).
    case hueco

    var esApp: Bool { if case .app = self { return true } else { return false } }
}

/// Cómo se dibuja una pieza: entera o en su versión angosta (cuando la pantalla no da para todo).
public enum ModoPieza: Equatable, Sendable { case completa, compacta }

public struct PiezaColocada: Equatable, Sendable {
    public var pieza: PiezaDock
    public var modo: ModoPieza
    public var ancho: Double

    public init(pieza: PiezaDock, modo: ModoPieza, ancho: Double) {
        self.pieza = pieza
        self.modo = modo
        self.ancho = ancho
    }
}

/// Lo que el Dock dibuja: las piezas con su modo y su ancho, el ancho total de la barra y lo que no cupo.
public struct DisposicionDock: Equatable, Sendable {
    public var piezas: [PiezaColocada]
    public var ancho: Double
    public var compactadas: [PiezaDock]
    public var soltadas: [PiezaDock]
}

/// Las medidas del Dock (puntos). La vista y el reparto usan los mismos números.
public enum MedidasDock {
    public static let alto: Double = 92
    public static let radio: Double = 23
    public static let margenInferior: Double = 12
    public static let relleno: Double = 9
    public static let alturaPieza: Double = 72
    public static let separacion: Double = 10
    public static let hueco: Double = 4
    /// Lo que se deja libre a cada lado de la pantalla.
    public static let margenLateral: Double = 24

    public static func ancho(_ pieza: PiezaDock, _ modo: ModoPieza = .completa) -> Double {
        let c = modo == .compacta
        switch pieza {
        case .reloj: return 142
        case .fecha: return 86
        case .bateria: return 76
        case .mac: return 172
        case .tareas: return 124
        case .plan: return 252
        case .dictar: return 128
        case .foco: return c ? 126 : 214
        case .agentes: return c ? 84 : 212
        case .agenda: return c ? 236 : 396
        case .musica: return c ? 150 : 322
        case .app, .grupo: return 72
        case .carpeta: return 66
        case .papelera: return 62
        case .clima: return 168
        case .lanzador: return 72
        case .abiertas: return 72
        case .finder: return 0
        case .hueco: return hueco
        }
    }

    public static let selectorAlto: Double = 40
    public static let selectorChip: Double = 30
    public static let selectorSeparacion: Double = 10

    /// El ancho del selector de espacios: una cápsula con un círculo de 30 por espacio (3 entre ellos y 5 de relleno a cada
    /// lado), 7 de aire y el "+" de 40. Sin espacios, solo el "+".
    public static func anchoSelector(espacios n: Int) -> Double {
        guard n > 0 else { return selectorAlto }
        return Double(n) * selectorChip + Double(n - 1) * 3 + 2 * 5 + 7 + selectorAlto
    }

    /// ¿Tiene versión angosta?
    public static func tieneCompacta(_ pieza: PiezaDock) -> Bool {
        switch pieza {
        case .musica, .agenda, .foco, .agentes: return true
        default: return false
        }
    }

    /// El ancho de la barra con estas piezas: sus anchos, 10 entre cada una (y alrededor de un hueco, 10 también) y el
    /// relleno de los lados.
    public static func anchoBarra(_ piezas: [PiezaColocada]) -> Double {
        guard !piezas.isEmpty else { return 2 * relleno }
        return piezas.reduce(0) { $0 + $1.ancho } + Double(piezas.count - 1) * separacion + 2 * relleno
    }
}

public enum DisposicionDockReparto {
    /// Orden en que las piezas pasan a su versión angosta cuando la barra no cabe (primera: la música).
    public static let ordenCompactar: [PiezaDock] = [.musica, .agenda, .foco, .agentes]

    /// Orden en que se sueltan piezas si ni compactando cabe: la primera que se va es la menos importante. Las carpetas,
    /// los grupos y las apps se sueltan de la última a la primera. La papelera nunca se suelta.
    public static let ordenSoltar: [Categoria] = [.bateria, .fecha, .mac, .tareas, .clima, .foco, .musica, .agentes, .carpetas, .abiertas, .grupos, .apps,
                                                  .agenda, .dictar, .reloj, .lanzador]

    public enum Categoria: Sendable { case bateria, fecha, mac, tareas, clima, foco, musica, agentes, carpetas, grupos, apps, agenda, dictar, reloj, lanzador, abiertas }

    static func categoria(_ p: PiezaDock) -> Categoria? {
        switch p {
        case .bateria: return .bateria
        case .fecha: return .fecha
        case .mac: return .mac
        case .tareas, .plan: return .tareas
        case .foco: return .foco
        case .musica: return .musica
        case .agentes: return .agentes
        case .carpeta: return .carpetas
        case .grupo: return .grupos
        case .app: return .apps
        case .agenda: return .agenda
        case .dictar: return .dictar
        case .reloj: return .reloj
        case .clima: return .clima
        case .lanzador: return .lanzador
        case .abiertas: return .abiertas
        case .papelera, .hueco, .finder: return nil
        }
    }
}

public enum ReglasDock {
    // MARK: La línea `dock:`

    /// Lee la línea `dock:` de un espacio: piezas separadas por coma y `|` para un hueco.
    ///   reloj, agenda, agentes, tareas, dictar, foco, musica, mac, bateria, fecha, papelera, clima, lanzador
    ///   Claude, com.apple.Safari      (apps por nombre o identificador; `app:Foco` fuerza una app que se llama como una pieza)
    ///   grupo:Trabajo                 (una carpeta de carpetas.txt)
    ///   carpeta:~/Downloads           (una carpeta del Finder)
    /// Lo que sobra o está repetido (huecos al principio, al final o seguidos) se limpia.
    public static func analizar(_ linea: String, home: String = NSHomeDirectory()) -> [PiezaDock] {
        let separada = linea.replacingOccurrences(of: "|", with: ",|,")
        var salida: [PiezaDock] = []
        for cruda in separada.split(separator: ",", omittingEmptySubsequences: true) {
            let token = cruda.trimmingCharacters(in: .whitespaces)
            if token.isEmpty { continue }
            if token == "|" { salida.append(.hueco); continue }
            if let p = pieza(token, home: home) { salida.append(p) }
        }
        return limpiarHuecos(salida)
    }

    static func pieza(_ token: String, home: String) -> PiezaDock? {
        if let dos = token.firstIndex(of: ":") {
            let clave = BusquedaApps.normalizar(String(token[..<dos]))
            let valor = token[token.index(after: dos)...].trimmingCharacters(in: .whitespaces)
            guard !valor.isEmpty else { return nil }
            switch clave {
            case "carpeta": return .carpeta(expandir(valor, home: home))
            case "grupo": return .grupo(valor)
            case "app": return .app(valor)
            default: break
            }
        }
        switch BusquedaApps.normalizar(token) {
        case "reloj": return .reloj
        case "agenda": return .agenda
        case "agentes": return .agentes
        case "tareas": return .tareas
        case "plan", "manana", "pendientes": return .plan
        case "dictar": return .dictar
        case "foco": return .foco
        case "musica": return .musica
        case "mac": return .mac
        case "bateria": return .bateria
        case "fecha": return .fecha
        case "papelera": return .papelera
        case "clima", "tiempo": return .clima
        case "lanzador", "apps": return .lanzador
        case "abiertas", "abiertos", "ejecutando": return .abiertas
        case "finder", "carpetas abiertas": return .finder
        default: return .app(token)
        }
    }

    /// `~` y `~/algo` con la carpeta personal; lo demás, igual.
    public static func expandir(_ ruta: String, home: String = NSHomeDirectory()) -> String {
        if ruta == "~" { return home }
        if ruta.hasPrefix("~/") { return home + String(ruta.dropFirst(1)) }
        return ruta
    }

    /// Quita los huecos al principio, al final y los seguidos.
    public static func limpiarHuecos(_ piezas: [PiezaDock]) -> [PiezaDock] {
        var salida: [PiezaDock] = []
        for p in piezas {
            if p == .hueco, salida.last == .hueco || salida.isEmpty { continue }
            salida.append(p)
        }
        while salida.last == .hueco { salida.removeLast() }
        return salida
    }

    /// Lo que lleva un espacio sin línea `dock:`: el lanzador, reloj, clima, agenda, agentes y dictar; las seis apps más usadas;
    /// Descargas y la papelera.
    public static func porOmision(masUsadas: [String], home: String = NSHomeDirectory()) -> [PiezaDock] {
        var p: [PiezaDock] = [.lanzador, .reloj, .clima, .agenda, .agentes, .dictar]
        if !masUsadas.isEmpty { p.append(.hueco); p += masUsadas.prefix(6).map { .app($0) } }
        p += [.abiertas, .hueco, .carpeta(home + "/Downloads"), .finder, .papelera]
        return p
    }

    // MARK: Reparto del ancho

    /// Reparte las piezas en `anchoDisponible` (el ancho de la pantalla menos los márgenes). Si no caben:
    ///  1. pasan a su versión angosta, de una en una, en este orden: música, agenda, foco, agentes;
    ///  2. si aún no cabe, se sueltan piezas en este orden: batería, fecha, Mac, tareas, foco, música, agentes, carpetas,
    ///     grupos, apps (de la última a la primera dentro de cada tipo), agenda, dictar y reloj. La papelera se queda.
    /// Los huecos que quedan al principio, al final o seguidos se quitan. El resultado es siempre el mismo para las mismas
    /// entradas.
    public static func colocar(_ piezas: [PiezaDock], anchoDisponible: Double) -> DisposicionDock {
        var actuales: [PiezaColocada] = limpiarHuecos(piezas).map { PiezaColocada(pieza: $0, modo: .completa, ancho: MedidasDock.ancho($0)) }
        var compactadas: [PiezaDock] = []
        var soltadas: [PiezaDock] = []
        func cabe() -> Bool { MedidasDock.anchoBarra(actuales) <= anchoDisponible }

        // 1. Compactar: todas las piezas de un tipo a la vez, y se revisa si ya cabe.
        if !cabe() {
            for tipo in DisposicionDockReparto.ordenCompactar {
                var hubo = false
                for i in actuales.indices where actuales[i].pieza == tipo {
                    actuales[i].modo = .compacta
                    actuales[i].ancho = MedidasDock.ancho(tipo, .compacta)
                    hubo = true
                }
                if hubo { compactadas.append(tipo) }
                if cabe() { break }
            }
        }
        // 2. Soltar, de la última a la primera dentro de cada tipo.
        if !cabe() {
            outer: for cat in DisposicionDockReparto.ordenSoltar {
                while let i = actuales.lastIndex(where: { DisposicionDockReparto.categoria($0.pieza) == cat }) {
                    soltadas.append(actuales[i].pieza)
                    actuales.remove(at: i)
                    // Un hueco que queda al borde o junto a otro se va.
                    var limpias: [PiezaColocada] = []
                    for p in actuales {
                        if p.pieza == .hueco, limpias.isEmpty || limpias.last?.pieza == .hueco { continue }
                        limpias.append(p)
                    }
                    while limpias.last?.pieza == .hueco { limpias.removeLast() }
                    actuales = limpias
                    if cabe() { break outer }
                }
            }
        }
        return DisposicionDock(piezas: actuales, ancho: MedidasDock.anchoBarra(actuales), compactadas: compactadas, soltadas: soltadas)
    }
}
