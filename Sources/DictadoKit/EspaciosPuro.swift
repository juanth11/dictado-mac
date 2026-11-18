import Foundation

// La lógica pura de los espacios (sin AppKit): a qué espacio se va con el teclado, qué acciones corre uno al entrar, qué fondo de
// pantalla lleva, qué pendientes del día y de la semana muestra Mañana y el archivo de los cinco espacios propuestos.

// MARK: - Ir de un espacio a otro

/// Adónde manda el teclado: el espacio número N (Hyper + 1…9), el siguiente o el anterior (Hyper + ] y Hyper + [).
public enum DestinoEspacio: Equatable, Sendable {
    case numero(Int)
    case siguiente
    case anterior
}

extension EspaciosIsla {
    /// El índice del espacio al que lleva `destino` (nil si no existe: no hay espacios o el número se pasa). Siguiente y anterior dan
    /// la vuelta; sin espacio activo, el siguiente es el primero y el anterior el último.
    public static func resolver(_ destino: DestinoEspacio, nombres: [String], actual: String?) -> Int? {
        guard !nombres.isEmpty else { return nil }
        switch destino {
        case .numero(let n):
            return nombres.indices.contains(n - 1) ? n - 1 : nil
        case .siguiente:
            guard let a = actual.flatMap({ nombres.firstIndex(of: $0) }) else { return 0 }
            return (a + 1) % nombres.count
        case .anterior:
            guard let a = actual.flatMap({ nombres.firstIndex(of: $0) }) else { return nombres.count - 1 }
            return (a - 1 + nombres.count) % nombres.count
        }
    }
}

// MARK: - Lo que hace un espacio al entrar

/// Una acción declarativa de `espacios.txt`. Solo corren cuando el dueño elige el espacio.
public enum AccionEntrada: Equatable, Sendable {
    case abrir(String)
    case reproducir(String)
    case atajo(String)
}

public enum ReproducirApp {
    /// El AppleScript que manda "reproducir" a una app conocida. Solo hay una lista corta, así que nada del archivo se mete en el
    /// script; una app que no está en la lista no hace nada (nil).
    public static func script(_ nombre: String) -> String? {
        switch BusquedaApps.normalizar(nombre) {
        case "spotify": return "tell application \"Spotify\" to play"
        case "musica", "music": return "tell application \"Music\" to play"
        default: return nil
        }
    }

    /// El nombre de la app tal como la conoce el sistema (para abrirla antes de mandarle el "reproducir").
    public static func app(_ nombre: String) -> String? {
        switch BusquedaApps.normalizar(nombre) {
        case "spotify": return "Spotify"
        case "musica", "music": return "Music"
        default: return nil
        }
    }
}

extension EspacioIsla {
    /// Lo que corre al entrar, en este orden: abrir apps, reproducir y el atajo de Apple.
    public var accionesAlEntrar: [AccionEntrada] {
        var a = abrir.map(AccionEntrada.abrir)
        if let reproducir, ReproducirApp.script(reproducir) != nil { a.append(.reproducir(reproducir)) }
        if let atajo { a.append(.atajo(atajo)) }
        return a
    }

    /// La ruta de la imagen de fondo de pantalla de este espacio, si la línea `fondo:` apunta a una imagen. `mac` y `paleta:` no
    /// cambian el fondo del Mac (solo el del lanzador).
    public func rutaFondoDePantalla(home: String = NSHomeDirectory()) -> String? {
        guard let fondo, case .imagen(let ruta)? = FondoLanzador(texto: fondo, home: home) else { return nil }
        return ruta
    }
}

// MARK: - Pendientes del día y de la semana (Mañana)

/// Una cosa por hacer, venga de donde venga.
public struct ItemPlan: Equatable, Sendable {
    public enum Origen: String, Sendable { case tarea, recordatorio, meta, hito }

    public var texto: String
    /// Cuándo vence (nil: sin fecha; entonces cuenta como `alcance`).
    public var vence: Date?
    public var origen: Origen
    /// Sin fecha, ¿es de hoy o de la semana?
    public var delDia: Bool
    /// El identificador en su fuente (el del recordatorio en EventKit): con él se puede marcar como hecho. nil: solo lectura.
    public var id: String?

    public init(texto: String, vence: Date? = nil, origen: Origen, delDia: Bool = false, id: String? = nil) {
        self.texto = texto
        self.vence = vence
        self.origen = origen
        self.delDia = delDia
        self.id = id
    }
}

public struct PlanPendientes: Equatable, Sendable {
    /// Lo de hoy y lo vencido, lo más urgente primero.
    public var hoy: [ItemPlan]
    /// Lo que queda de la semana (mañana hasta el domingo), por fecha.
    public var semana: [ItemPlan]

    public init(hoy: [ItemPlan], semana: [ItemPlan]) {
        self.hoy = hoy
        self.semana = semana
    }

    public static let vacio = PlanPendientes(hoy: [], semana: [])
    public var total: Int { hoy.count + semana.count }
}

public enum PlanPendientesCalculo {
    /// Reparte los pendientes: vencidos y de hoy → `hoy`; de mañana al domingo → `semana`; sin fecha, según `delDia`. Lo que vence
    /// después de la semana no se muestra. Sin textos repetidos.
    public static func armar(_ items: [ItemPlan], ahora: Date, calendario: Calendar = .current) -> PlanPendientes {
        var cal = calendario
        cal.firstWeekday = 2   // la semana empieza el lunes
        let inicioHoy = cal.startOfDay(for: ahora)
        guard let inicioManana = cal.date(byAdding: .day, value: 1, to: inicioHoy),
              let semanaSiguiente = cal.dateInterval(of: .weekOfYear, for: ahora)?.end else { return .vacio }
        var vistos = Set<String>()
        var hoy: [ItemPlan] = [], semana: [ItemPlan] = []
        for i in items {
            let clave = BusquedaApps.normalizar(i.texto)
            guard !clave.isEmpty, vistos.insert(clave).inserted else { continue }
            if let v = i.vence {
                if v < inicioManana { hoy.append(i) } else if v < semanaSiguiente { semana.append(i) }
            } else if i.delDia { hoy.append(i) } else { semana.append(i) }
        }
        func porFecha(_ a: ItemPlan, _ b: ItemPlan) -> Bool { (a.vence ?? .distantFuture) < (b.vence ?? .distantFuture) }
        return PlanPendientes(hoy: hoy.sorted(by: porFecha), semana: semana.sorted(by: porFecha))
    }
}

/// Lee las metas del cerebro (`metas/<trimestre>.md`, solo lectura): de la sección "Semana" salen las metas abiertas y de "Hitos" los
/// que tienen fecha.
public enum MetasPlan {
    public static func items(_ texto: String, calendario: Calendar = .current) -> [ItemPlan] {
        var seccion = ""
        var salida: [ItemPlan] = []
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd"
        formato.calendar = calendario
        formato.timeZone = calendario.timeZone
        for cruda in texto.components(separatedBy: "\n") {
            let linea = cruda.trimmingCharacters(in: .whitespaces)
            if linea.hasPrefix("## ") { seccion = BusquedaApps.normalizar(String(linea.dropFirst(3))); continue }
            guard linea.hasPrefix("- ") else { continue }
            let cuerpo = String(linea.dropFirst(2))
            if seccion.hasPrefix("semana") {
                let estado = cuerpo.prefix(3)
                guard estado == "[ ]" || estado == "[~]" else { continue }
                let t = String(cuerpo.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let titulo = t.components(separatedBy: " · ").first ?? t
                if !titulo.isEmpty { salida.append(ItemPlan(texto: titulo, origen: .meta)) }
            } else if seccion.hasPrefix("hitos") {
                let partes = cuerpo.components(separatedBy: " · ")
                guard partes.count >= 2, let f = formato.date(from: partes[0].trimmingCharacters(in: .whitespaces)) else { continue }
                salida.append(ItemPlan(texto: partes[1].trimmingCharacters(in: .whitespaces), vence: f, origen: .hito))
            }
        }
        return salida
    }
}

// MARK: - Los cinco espacios propuestos

extension EspaciosIsla {
    /// Los cinco espacios de ejemplo: Mañana, Trabajo, Foco, Personal y Juego, cada uno con su fondo de pantalla de macOS, su paleta Aurora
    /// y su Dock. Sirve de plantilla del archivo y de muestra para los renders.
    public static let sugeridos = encabezado + """


    [Mañana]
    titulo: Planea el día
    fondo: The Cliffs
    paleta: lagunaDurazno
    primero: com.apple.iCal, com.apple.reminders, com.apple.Notes, com.apple.mail, Comunicación
    dock: lanzador, reloj, clima, agenda, plan, agentes, | com.apple.iCal, com.apple.reminders, com.apple.Notes, com.apple.mail, Claude | finder, carpeta:~/Documents/Proyectos, papelera
    velo: no
    teclas: no

    [Trabajo]
    titulo: A trabajar
    fondo: Pro Black
    paleta: medianocheOro
    primero: Trabajo, Desarrollo
    dock: lanzador, reloj, agenda, agentes, | Claude, Spotify, WhatsApp, Safari, abiertas | finder, carpeta:~/Downloads, carpeta:~/Documents/Proyectos, carpeta:~/Documents/Lumina, papelera
    velo: no
    teclas: no

    [Foco]
    titulo: Una sola cosa
    fondo: aereo:Patagonia
    paleta: bosqueLima
    primero: com.apple.Notes, com.apple.reminders
    dock: reloj, foco, musica, | com.apple.Notes
    velo: ambiente
    teclas: no
    foco: 25

    [Personal]
    titulo: Lo tuyo, sin trabajo
    fondo: Hello Metallic Purple
    paleta: ciruelaCoral
    primero: Spotify, WhatsApp, com.apple.Photos
    dock: lanzador, reloj, clima, musica, | Spotify, WhatsApp, com.apple.Photos | carpeta:~/Documents/Finanzas, papelera
    abrir: Spotify
    reproducir: spotify
    velo: no
    teclas: no

    [Juego]
    titulo: A jugar
    fondo: Radial Sky Blue
    paleta: tintaLavanda
    primero: Steam, GeForceNOW, Discord, Cyberpunk 2077
    dock: lanzador, reloj, musica, | Steam, com.nvidia.gfnpc.mall, Discord, Cyberpunk 2077 | abiertas, papelera
    velo: no
    teclas: no
    """
}
