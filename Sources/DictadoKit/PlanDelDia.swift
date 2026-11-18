import Foundation

/// Un evento del día tal como lo necesita la tarjeta de agenda del lanzador (sin colores ni EventKit, para poder probarlo).
public struct ReunionDia: Equatable, Sendable, Identifiable {
    public var id: String
    public var titulo: String
    public var inicio: Date
    public var fin: Date
    /// Nombres de quienes van (sin ti).
    public var invitados: [String]
    /// "Meet", "Zoom"… si hay enlace; nil si no hay videollamada.
    public var servicio: String?
    public var tieneEnlace: Bool
    /// Tiene invitados o enlace; lo demás (almuerzo, ejercicio) es un bloque.
    public var esReunion: Bool

    public init(id: String, titulo: String, inicio: Date, fin: Date, invitados: [String] = [], servicio: String? = nil,
                tieneEnlace: Bool = false, esReunion: Bool = false) {
        self.id = id
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.invitados = invitados
        self.servicio = servicio
        self.tieneEnlace = tieneEnlace
        self.esReunion = esReunion
    }

    public func enCurso(ahora: Date) -> Bool { inicio <= ahora && fin > ahora }
}

/// Lo que dice la tarjeta de agenda del lanzador: la reunión en foco (en curso o la próxima), las que siguen y los huecos libres de hoy.
public struct PlanDelDia: Equatable, Sendable {
    public var foco: ReunionDia?
    public var enCurso: Bool
    public var despues: [ReunionDia]
    public var huecos: [Intervalo]
    /// Cuántas quedan hoy (con la del foco) y cuántas no caben en la lista.
    public var restantes: Int
    public var sinMostrar: Int

    /// `reuniones` pueden venir en cualquier orden y de cualquier día; `huecos` son los libres según el horario de Ajustes.
    public static func armar(reuniones: [ReunionDia], huecos: [Intervalo], ahora: Date, maxDespues: Int = 2, maxHuecos: Int = 1,
                             calendario: Calendar = .current) -> PlanDelDia {
        let pendientes = reuniones
            .filter { $0.fin > ahora && calendario.isDate($0.inicio, inSameDayAs: ahora) }
            .sorted { ($0.inicio, $0.id) < ($1.inicio, $1.id) }
        let foco = pendientes.first(where: \.esReunion) ?? pendientes.first
        let resto = pendientes.filter { $0.id != foco?.id && ($0.inicio >= (foco?.inicio ?? .distantPast)) }
        let hoy = huecos
            .filter { calendario.isDate($0.inicio, inSameDayAs: ahora) && $0.fin > ahora && $0.fin > $0.inicio }
            .sorted { $0.inicio < $1.inicio }
        return PlanDelDia(foco: foco, enCurso: foco?.enCurso(ahora: ahora) ?? false, despues: Array(resto.prefix(maxDespues)),
                          huecos: Array(hoy.prefix(maxHuecos)), restantes: pendientes.count, sinMostrar: max(0, resto.count - maxDespues))
    }

    /// "Lucía, Marcos y 1 más", "Lucía y Marcos", "Lucía"; vacío si no hay nadie. Solo el primer nombre de cada uno.
    public static func quienes(_ nombres: [String], maximo: Int = 2) -> String {
        let cortos = nombres.map { String($0.split(separator: " ").first ?? "") }.filter { !$0.isEmpty }
        guard !cortos.isEmpty else { return "" }
        if cortos.count <= maximo {
            return cortos.count == 1 ? cortos[0] : cortos.dropLast().joined(separator: ", ") + " y " + cortos[cortos.count - 1]
        }
        let resto = cortos.count - maximo
        return cortos.prefix(maximo).joined(separator: ", ") + " y \(resto) más"
    }
}
