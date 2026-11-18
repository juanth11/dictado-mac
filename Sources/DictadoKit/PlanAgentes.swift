import Foundation

/// Una fila de la tarjeta de agentes del lanzador: una sesión de Claude, una corrida del Tablero o un agente remoto.
public struct FilaTarjetaAgentes: Equatable, Sendable, Identifiable {
    /// De más a menos urgente.
    public enum Estado: Int, Sendable { case espera, alerta, trabaja, quieto, termino }

    public var id: String
    public var nombre: String
    public var estado: Estado
    /// Desde cuándo está en ese estado.
    public var desde: Date?
    /// Lo último que hizo o lo que pide: "Editando Isla.swift", "Necesita tu permiso: swift build".
    public var paso: String

    public init(id: String, nombre: String, estado: Estado, desde: Date? = nil, paso: String = "") {
        self.id = id
        self.nombre = nombre
        self.estado = estado
        self.desde = desde
        self.paso = paso
    }

    /// El estado en una palabra.
    public var rotulo: String {
        switch estado {
        case .espera: return "Espera tu respuesta"
        case .alerta: return "Con alerta"
        case .trabaja: return "Trabajando"
        case .quieto: return "En calma"
        case .termino: return "Terminó"
        }
    }

    /// Lo que hace el botón de la fila.
    public var accion: String {
        switch estado {
        case .espera: return "Responder"
        case .alerta, .termino: return "Revisar"
        case .trabaja, .quieto: return "Abrir"
        }
    }
}

public enum PlanAgentes {
    /// Lo que pide tu respuesta primero, luego alertas, lo que trabaja, lo quieto y lo terminado; dentro de cada grupo, lo más reciente.
    public static func ordenar(_ filas: [FilaTarjetaAgentes]) -> [FilaTarjetaAgentes] {
        filas.enumerated().sorted { a, b in
            if a.element.estado != b.element.estado { return a.element.estado.rawValue < b.element.estado.rawValue }
            let da = a.element.desde ?? .distantPast, db = b.element.desde ?? .distantPast
            return da != db ? da > db : a.offset < b.offset
        }.map(\.element)
    }

    /// Las que caben y cuántas quedan fuera.
    public static func visibles(_ filas: [FilaTarjetaAgentes], maximo: Int) -> (filas: [FilaTarjetaAgentes], ocultas: Int) {
        let o = ordenar(filas)
        return (Array(o.prefix(maximo)), max(0, o.count - maximo))
    }

    /// La cabecera: el número que manda (los que esperan, si los hay; si no, los que trabajan) y su leyenda.
    public static func cabecera(_ filas: [FilaTarjetaAgentes]) -> (numero: Int, leyenda: String) {
        let espera = filas.filter { $0.estado == .espera || $0.estado == .alerta }.count
        if espera > 0 { return (espera, espera == 1 ? "espera tu sí" : "esperan tu sí") }
        let trabaja = filas.filter { $0.estado == .trabaja }.count
        if trabaja > 0 { return (trabaja, trabaja == 1 ? "trabajando" : "trabajando") }
        return (0, "en calma")
    }

    /// "ahora", "3 min", "2 h", "1 h 05", "4 d".
    public static func duracion(desde: Date, hasta ahora: Date) -> String {
        let s = max(0, Int(ahora.timeIntervalSince(desde)))
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 6 * 3600 { let m = (s % 3600) / 60; return m == 0 ? "\(s / 3600) h" : String(format: "%d h %02d", s / 3600, m) }
        if s < 48 * 3600 { return "\(s / 3600) h" }
        return "\(s / 86_400) d"
    }
}
