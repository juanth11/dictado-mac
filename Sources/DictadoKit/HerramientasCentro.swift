import Foundation

// La sección Herramientas del Centro (`python3 -m centro herramientas --json`): los MCP, las skills y los plugins de Claude Code con
// cuántas veces se usó cada uno en 7 y 30 días. Resalta lo que está activo y nunca se usa. De los MCP solo llegan nombre, tipo y
// programa o host: nunca argumentos, entorno ni cabeceras.

public struct UsoHerramienta: Equatable, Sendable {
    public var usos7: Int
    public var usos30: Int
    public var ultimoUso: Date?
    /// Las herramientas más usadas de un MCP (nombre y veces).
    public var herramientas: [(nombre: String, usos: Int)]

    public init(usos7: Int = 0, usos30: Int = 0, ultimoUso: Date? = nil, herramientas: [(nombre: String, usos: Int)] = []) {
        self.usos7 = usos7
        self.usos30 = usos30
        self.ultimoUso = ultimoUso
        self.herramientas = herramientas
    }

    public static func == (a: UsoHerramienta, b: UsoHerramienta) -> Bool {
        a.usos7 == b.usos7 && a.usos30 == b.usos30 && a.ultimoUso == b.ultimoUso
            && a.herramientas.map { "\($0.nombre):\($0.usos)" } == b.herramientas.map { "\($0.nombre):\($0.usos)" }
    }
}

public struct ServidorMCP: Equatable, Sendable, Identifiable {
    public var nombre: String
    /// "usuario", "proyecto: x", "plugin: x" o "integrado" (lo trae la app y no está en tu configuración).
    public var alcance: String
    public var activo: Bool
    public var tipo: String
    public var destino: String
    public var pideAutorizar: Bool
    public var uso: UsoHerramienta
    public var id: String { nombre + "|" + alcance }

    public init(nombre: String, alcance: String = "usuario", activo: Bool = true, tipo: String = "", destino: String = "", pideAutorizar: Bool = false,
                uso: UsoHerramienta = UsoHerramienta()) {
        self.nombre = nombre
        self.alcance = alcance
        self.activo = activo
        self.tipo = tipo
        self.destino = destino
        self.pideAutorizar = pideAutorizar
        self.uso = uso
    }

    public var integrado: Bool { alcance == "integrado" }
}

public struct SkillInstalada: Equatable, Sendable, Identifiable {
    public var nombre: String
    public var origen: String
    public var descripcion: String
    public var activa: Bool
    public var uso: UsoHerramienta
    public var id: String { nombre }

    public init(nombre: String, origen: String = "usuario", descripcion: String = "", activa: Bool = true, uso: UsoHerramienta = UsoHerramienta()) {
        self.nombre = nombre
        self.origen = origen
        self.descripcion = descripcion
        self.activa = activa
        self.uso = uso
    }
}

public struct PluginInstalado: Equatable, Sendable, Identifiable {
    public var nombre: String
    public var origen: String
    public var version: String?
    public var activo: Bool
    public var id: String { nombre + "@" + origen }

    public init(nombre: String, origen: String = "", version: String? = nil, activo: Bool = true) {
        self.nombre = nombre
        self.origen = origen
        self.version = version
        self.activo = activo
    }
}

public struct HerramientasHermes: Equatable, Sendable {
    public var mcp: [(nombre: String, activo: Bool, usos30: Int)]
    public var skillsTotal: Int
    public var herramientas: [(nombre: String, usos: Int)]
    public var leido: Date?

    public init(mcp: [(nombre: String, activo: Bool, usos30: Int)] = [], skillsTotal: Int = 0, herramientas: [(nombre: String, usos: Int)] = [], leido: Date? = nil) {
        self.mcp = mcp
        self.skillsTotal = skillsTotal
        self.herramientas = herramientas
        self.leido = leido
    }

    public static func == (a: HerramientasHermes, b: HerramientasHermes) -> Bool {
        a.skillsTotal == b.skillsTotal && a.leido == b.leido && a.mcp.map { "\($0.nombre)\($0.activo)\($0.usos30)" } == b.mcp.map { "\($0.nombre)\($0.activo)\($0.usos30)" }
            && a.herramientas.map { "\($0.nombre)\($0.usos)" } == b.herramientas.map { "\($0.nombre)\($0.usos)" }
    }
}

public struct Herramientas: Equatable, Sendable {
    public var generado: Date?
    /// Desde cuándo hay registro de uso ("2026-10-15"): antes de eso, "sin uso" no significa nada.
    public var usoDesde: String?
    public var servidores: [ServidorMCP]
    public var integrados: [ServidorMCP]
    public var skills: [SkillInstalada]
    public var skillsEnReserva: Int
    public var plugins: [PluginInstalado]
    public var hermes: HerramientasHermes?

    public init(generado: Date? = nil, usoDesde: String? = nil, servidores: [ServidorMCP] = [], integrados: [ServidorMCP] = [], skills: [SkillInstalada] = [],
                skillsEnReserva: Int = 0, plugins: [PluginInstalado] = [], hermes: HerramientasHermes? = nil) {
        self.generado = generado
        self.usoDesde = usoDesde
        self.servidores = servidores
        self.integrados = integrados
        self.skills = skills
        self.skillsEnReserva = skillsEnReserva
        self.plugins = plugins
        self.hermes = hermes
    }
}

public enum HerramientasCentro {
    public enum Filtro: String, CaseIterable, Sendable {
        case todo, usadas, sinUso

        public var titulo: String {
            switch self {
            case .todo: return "Todo"
            case .usadas: return "Usadas"
            case .sinUso: return "Sin uso"
            }
        }
    }

    // MARK: Lectura

    public static func decodificar(_ datos: Data) -> Herramientas? {
        guard let d = LecturaJSON.objeto(datos), let version = LecturaJSON.entero(d["version"]), version >= 1, let mcp = d["mcp"] as? [String: Any],
              let skills = d["skills"] as? [String: Any] else { return nil }
        func uso(_ x: [String: Any]) -> UsoHerramienta {
            UsoHerramienta(usos7: LecturaJSON.entero(x["usos_7"]) ?? 0, usos30: LecturaJSON.entero(x["usos_30"]) ?? 0, ultimoUso: LecturaJSON.fecha(x["ultimo_uso"]),
                           herramientas: (x["herramientas"] as? [[String: Any]] ?? []).compactMap { h in
                               guard let n = LecturaJSON.texto(h["nombre"]) else { return nil }
                               return (n, LecturaJSON.entero(h["usos"]) ?? 0)
                           })
        }
        func servidor(_ x: [String: Any]) -> ServidorMCP? {
            guard let n = LecturaJSON.texto(x["nombre"]) else { return nil }
            return ServidorMCP(nombre: n, alcance: LecturaJSON.texto(x["alcance"]) ?? "usuario", activo: LecturaJSON.booleano(x["activo"]) ?? true,
                               tipo: LecturaJSON.texto(x["tipo"]) ?? "", destino: LecturaJSON.texto(x["destino"]) ?? "",
                               pideAutorizar: LecturaJSON.booleano(x["pide_autorizar"]) ?? false, uso: uso(x))
        }
        var hermes: HerramientasHermes?
        if let h = d["hermes"] as? [String: Any] {
            hermes = HerramientasHermes(
                mcp: (h["mcp"] as? [[String: Any]] ?? []).compactMap { m in
                    guard let n = LecturaJSON.texto(m["nombre"]) else { return nil }
                    return (n, LecturaJSON.booleano(m["activo"]) ?? true, LecturaJSON.entero(m["usos_30"]) ?? 0)
                },
                skillsTotal: LecturaJSON.entero(h["skills_total"]) ?? 0,
                herramientas: (h["herramientas"] as? [[String: Any]] ?? []).compactMap { x in
                    guard let n = LecturaJSON.texto(x["nombre"]) else { return nil }
                    return (n, LecturaJSON.entero(x["usos"]) ?? 0)
                },
                leido: LecturaJSON.fecha(h["leido"]))
        }
        return Herramientas(
            generado: LecturaJSON.fecha(d["generado"]), usoDesde: LecturaJSON.texto(d["uso_desde"]),
            servidores: (mcp["servidores"] as? [[String: Any]] ?? []).compactMap(servidor),
            integrados: (mcp["integrados"] as? [[String: Any]] ?? []).compactMap(servidor),
            skills: (skills["items"] as? [[String: Any]] ?? []).compactMap { x in
                guard let n = LecturaJSON.texto(x["nombre"]) else { return nil }
                return SkillInstalada(nombre: n, origen: LecturaJSON.texto(x["origen"]) ?? "usuario", descripcion: LecturaJSON.texto(x["descripcion"]) ?? "",
                                      activa: LecturaJSON.booleano(x["activa"]) ?? true, uso: uso(x))
            },
            skillsEnReserva: LecturaJSON.entero(skills["en_reserva"]) ?? 0,
            plugins: (d["plugins"] as? [[String: Any]] ?? []).compactMap { x in
                guard let n = LecturaJSON.texto(x["nombre"]) else { return nil }
                return PluginInstalado(nombre: n, origen: LecturaJSON.texto(x["origen"]) ?? "", version: LecturaJSON.texto(x["version"]),
                                       activo: LecturaJSON.booleano(x["activo"]) ?? true)
            },
            hermes: hermes)
    }

    // MARK: Cuentas

    /// Lo que está activo y no se usó en 30 días (lo que sobra o se olvidó).
    public static func sinUso(_ servidores: [ServidorMCP]) -> [ServidorMCP] { servidores.filter { $0.activo && $0.uso.usos30 == 0 } }
    public static func sinUso(_ skills: [SkillInstalada]) -> [SkillInstalada] { skills.filter { $0.activa && $0.uso.usos30 == 0 } }

    public static func filtrar(_ servidores: [ServidorMCP], _ f: Filtro) -> [ServidorMCP] {
        switch f {
        case .todo: return servidores
        case .usadas: return servidores.filter { $0.uso.usos30 > 0 }
        case .sinUso: return sinUso(servidores)
        }
    }

    public static func filtrar(_ skills: [SkillInstalada], _ f: Filtro) -> [SkillInstalada] {
        switch f {
        case .todo: return skills
        case .usadas: return skills.filter { $0.uso.usos30 > 0 }
        case .sinUso: return sinUso(skills)
        }
    }

    /// La fracción (0 a 1) del uso de 30 días respecto al más usado de la lista, para la barra fina de cada fila.
    public static func fraccionUso(_ usos: Int, mayor: Int) -> Double { mayor > 0 ? min(1, max(Double(usos) / Double(mayor), usos > 0 ? 0.03 : 0)) : 0 }

    /// "hoy", "hace 3 d" o "nunca" (en la ventana que se mide).
    public static func ultimoUso(_ uso: UsoHerramienta, ahora: Date) -> String {
        guard let f = uso.ultimoUso else { return "sin uso" }
        return Calendar.current.isDate(f, inSameDayAs: ahora) ? "hoy" : TextoTiempo.hace(f, ahora)
    }

    /// El texto del tipo y destino de un MCP: "stdio · uv", "http · mcp.firecrawl.dev".
    public static func conexion(_ s: ServidorMCP) -> String {
        [s.tipo, s.destino].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
