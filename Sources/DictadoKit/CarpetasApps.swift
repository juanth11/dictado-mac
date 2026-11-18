import Foundation

/// Una carpeta de apps de Inicio: un nombre y las apps que agrupa (nombres o identificadores de paquete).
public struct CarpetaApps: Equatable, Sendable {
    public var nombre: String
    public var apps: [String]

    public init(nombre: String, apps: [String] = []) {
        self.nombre = nombre
        self.apps = apps
    }
}

/// Carpetas de apps: el archivo `carpetas.txt`, el reparto automático de la primera vez y cómo se resuelven contra las
/// apps instaladas. Lógica pura: lo que toca el disco o Spotlight vive en la app.
public enum CarpetasApps {
    /// El orden de las carpetas automáticas.
    public static let nombresAutomaticos = ["Trabajo", "Comunicación", "Desarrollo", "Juegos", "Sistema"]
    /// Una carpeta automática con menos apps que esto no se crea (no vale la pena para una sola).
    public static let minimoAutomatico = 2
    public static let maximoPorCarpeta = 60

    /// Lee el archivo. Formato:
    ///   [Nombre]
    ///   apps: Mail, com.apple.Notes   (se puede repetir; se juntan)
    public static func leer(_ texto: String) -> [CarpetaApps] {
        var carpetas: [CarpetaApps] = []
        for cruda in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            let linea = cruda.trimmingCharacters(in: .whitespaces)
            if linea.isEmpty || linea.hasPrefix("#") { continue }
            if linea.hasPrefix("["), linea.hasSuffix("]") {
                let nombre = String(linea.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !nombre.isEmpty { carpetas.append(CarpetaApps(nombre: nombre)) }
                continue
            }
            guard !carpetas.isEmpty, let dos = linea.firstIndex(of: ":") else { continue }
            let clave = BusquedaApps.normalizar(String(linea[..<dos]))
            guard clave == "apps" || clave == "app" else { continue }
            let lista = linea[linea.index(after: dos)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            carpetas[carpetas.count - 1].apps += lista
        }
        return carpetas
    }

    public static let cabecera = """
    # Carpetas de Inicio (la isla): agrupan tus apps en un solo mosaico.
    # Cada carpeta empieza con [Nombre] y sigue con líneas "apps:" con nombres de app (Mail) o identificadores
    # (com.apple.Notes), separados por coma. Puedes repetir "apps:"; se juntan. El orden de aquí es el de Inicio.
    # Los cambios valen la próxima vez que abras la isla.
    """

    /// El texto del archivo a partir de las carpetas (la primera vez, con la cabecera).
    public static func texto(_ carpetas: [CarpetaApps]) -> String {
        var s = cabecera + "\n"
        for c in carpetas {
            s += "\n[\(c.nombre)]\n"
            var resto = c.apps[...]
            while !resto.isEmpty {   // líneas de ocho en ocho para que se lea
                s += "apps: " + resto.prefix(8).joined(separator: ", ") + "\n"
                resto = resto.dropFirst(8)
            }
        }
        return s
    }

    /// A qué carpeta automática va una app según su `LSApplicationCategoryType` (y, en pocas apps de mensajería, su
    /// identificador). nil: queda suelta.
    public static func carpetaAutomatica(categoria: String?, bundleID: String?) -> String? {
        if let id = bundleID?.lowercased(),
           mensajeria.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) { return "Comunicación" }
        guard let c = categoria?.lowercased(), !c.isEmpty else { return nil }
        let corta = c.replacingOccurrences(of: "public.app-category.", with: "")
        if corta.hasSuffix("games") || corta == "games" { return "Juegos" }
        switch corta {
        case "productivity", "business", "finance", "education", "reference", "graphics-design", "news", "medical", "lifestyle":
            return "Trabajo"
        case "social-networking": return "Comunicación"
        case "developer-tools": return "Desarrollo"
        case "utilities": return "Sistema"
        default: return nil
        }
    }

    private static let mensajeria = ["com.apple.mail", "com.apple.mobilesms", "com.apple.facetime", "net.whatsapp.whatsapp", "com.tinyspeck.slackmacgap",
                                     "us.zoom.xos", "com.hnc.discord", "ru.keepcoder.telegram", "com.microsoft.teams2", "com.microsoft.teams",
                                     "com.microsoft.outlook", "com.google.chrome.app.meet", "com.apple.ical"]

    /// El reparto automático de la primera vez: una carpeta por tema (solo con `minimoAutomatico` apps o más). Cada app se
    /// guarda por su identificador (o su nombre si no trae) y las apps van por nombre.
    public static func agrupar(_ apps: [(app: EntradaApp, categoria: String?)]) -> [CarpetaApps] {
        var porCarpeta: [String: [EntradaApp]] = [:]
        for par in apps {
            guard let c = carpetaAutomatica(categoria: par.categoria, bundleID: par.app.bundleID) else { continue }
            porCarpeta[c, default: []].append(par.app)
        }
        return nombresAutomaticos.compactMap { nombre in
            guard let lista = porCarpeta[nombre], lista.count >= minimoAutomatico else { return nil }
            let ordenadas = lista.sorted { BusquedaApps.normalizar($0.nombre) < BusquedaApps.normalizar($1.nombre) }.prefix(maximoPorCarpeta)
            return CarpetaApps(nombre: nombre, apps: ordenadas.map { $0.bundleID ?? $0.nombre })
        }
    }

    /// Las apps instaladas de una carpeta, en el orden del archivo: cada entrada coincide por identificador (exacto) o por
    /// nombre (sin tildes ni mayúsculas). Las que no están instaladas se saltan; sin repetir.
    public static func resolver(_ carpeta: CarpetaApps, instaladas: [EntradaApp]) -> [EntradaApp] {
        var vistas = Set<String>()
        var salida: [EntradaApp] = []
        for entrada in carpeta.apps {
            let n = BusquedaApps.normalizar(entrada)
            guard let app = instaladas.first(where: { $0.bundleID == entrada })
                    ?? instaladas.first(where: { BusquedaApps.normalizar($0.nombre) == n }) else { continue }
            if vistas.insert(app.id).inserted { salida.append(app) }
        }
        return salida
    }
}

/// Qué va primero en Inicio según el espacio: lo que el espacio nombra, en su orden; el resto, como estaba.
public enum PrioridadInicio {
    /// `claves`: las cadenas con las que se puede nombrar a un elemento (su nombre, su identificador…).
    public static func ordenar<T>(_ elementos: [T], claves: (T) -> [String], primero: [String]) -> [T] {
        let pedidos = primero.map(BusquedaApps.normalizar).filter { !$0.isEmpty }
        guard !pedidos.isEmpty else { return elementos }
        func rango(_ e: T) -> Int {
            let propias = claves(e).map(BusquedaApps.normalizar)
            return pedidos.firstIndex { p in propias.contains(p) } ?? Int.max
        }
        let indexados = elementos.enumerated().map { (i: $0.offset, r: rango($0.element), e: $0.element) }
        return indexados.sorted { $0.r != $1.r ? $0.r < $1.r : $0.i < $1.i }.map(\.e)
    }
}

/// Las páginas de una rejilla de Inicio.
public enum PaginasInicio {
    public static func cantidad(total: Int, porPagina: Int) -> Int {
        guard total > 0, porPagina > 0 else { return 1 }
        return (total + porPagina - 1) / porPagina
    }

    /// Lo que cae en la página (empezando en 0); una página fuera de rango se lleva a la última.
    public static func rango(pagina: Int, total: Int, porPagina: Int) -> Range<Int> {
        guard total > 0, porPagina > 0 else { return 0..<0 }
        let p = min(max(pagina, 0), cantidad(total: total, porPagina: porPagina) - 1)
        return (p * porPagina)..<min(total, (p + 1) * porPagina)
    }
}
