import Foundation

/// Una fila de la tarjeta del plan de Mañana en el lanzador.
public struct FilaPlan: Equatable, Sendable, Identifiable {
    public var id: String
    public var texto: String
    public var origen: ItemPlan.Origen
    /// "Tarea", "Recordatorio", "Meta" o "Hito".
    public var etiqueta: String
    /// "Vencida", "3:00 p. m.", "jue"… nil si no tiene fecha.
    public var cuando: String?
    public var vencida: Bool
    /// Tiene casilla: solo los recordatorios (EventKit) se pueden marcar; tareas del centro y metas son de solo lectura.
    public var puedeMarcar: Bool
    /// El identificador del recordatorio para marcarlo (nil si no se puede).
    public var idFuente: String?
    public var hecha: Bool
}

public struct SeccionPlan: Equatable, Sendable {
    public var titulo: String
    /// Las filas que caben.
    public var filas: [FilaPlan]
    /// Cuántas más hay sin mostrar (las pendientes que no caben).
    public var ocultas: Int
    /// Pendientes de la sección (sin las ya marcadas).
    public var pendientes: Int
}

/// Lo que dice la tarjeta del plan: las secciones Hoy y Semana, listas para dibujar. Sin Foundation de la app ni EventKit: se prueba en DictadoKit.
public struct TarjetaPlan: Equatable, Sendable {
    public var hoy: SeccionPlan
    public var semana: SeccionPlan
    public var vacio: Bool { hoy.filas.isEmpty && semana.filas.isEmpty && hoy.ocultas == 0 && semana.ocultas == 0 }

    static let dias = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    /// `hechas`: los identificadores (`FilaPlan.id`) que se acaban de marcar y todavía no salen de la lista (se tachan y quedan al final).
    public static func armar(_ plan: PlanPendientes, hechas: Set<String> = [], ahora: Date, maxHoy: Int = 4, maxSemana: Int = 3,
                             calendario: Calendar = .current) -> TarjetaPlan {
        TarjetaPlan(hoy: seccion("Hoy", plan.hoy, hechas, ahora, maxHoy, deHoy: true, calendario),
                    semana: seccion("Semana", plan.semana, hechas, ahora, maxSemana, deHoy: false, calendario))
    }

    private static func seccion(_ titulo: String, _ items: [ItemPlan], _ hechas: Set<String>, _ ahora: Date, _ maximo: Int, deHoy: Bool,
                                _ cal: Calendar) -> SeccionPlan {
        let filas = items.map { fila($0, hechas, ahora, deHoy: deHoy, cal) }
        let pendientes = filas.filter { !$0.hecha }
        let ya = filas.filter(\.hecha)
        // Las pendientes primero; las marcadas se quedan al final, tachadas, hasta que la lista se vuelva a leer.
        let visibles = Array(pendientes.prefix(maximo)) + ya.prefix(max(0, maximo - min(maximo, pendientes.count)))
        return SeccionPlan(titulo: titulo, filas: visibles, ocultas: max(0, pendientes.count - maximo), pendientes: pendientes.count)
    }

    public static func clave(_ i: ItemPlan) -> String { i.id.map { "id:" + $0 } ?? "t:" + i.texto.lowercased() }

    private static func fila(_ i: ItemPlan, _ hechas: Set<String>, _ ahora: Date, deHoy: Bool, _ cal: Calendar) -> FilaPlan {
        let id = clave(i)
        let etiqueta: String
        switch i.origen {
        case .tarea: etiqueta = "Tarea"
        case .recordatorio: etiqueta = "Recordatorio"
        case .meta: etiqueta = "Meta"
        case .hito: etiqueta = "Hito"
        }
        let inicioHoy = cal.startOfDay(for: ahora)
        let vencida = (i.vence.map { $0 < inicioHoy } ?? false) || (deHoy && (i.vence.map { $0 < ahora && cal.isDate($0, inSameDayAs: ahora) && tieneHora($0, cal) } ?? false))
        return FilaPlan(id: id, texto: i.texto, origen: i.origen, etiqueta: etiqueta, cuando: cuando(i.vence, ahora: ahora, deHoy: deHoy, cal),
                        vencida: vencida, puedeMarcar: i.origen == .recordatorio && i.id != nil, idFuente: i.origen == .recordatorio ? i.id : nil,
                        hecha: hechas.contains(id))
    }

    private static func tieneHora(_ d: Date, _ cal: Calendar) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0
    }

    /// Hoy: "Vencida" si es de un día anterior, la hora si la tiene. Semana: el día ("jue") y la hora si la tiene.
    static func cuando(_ vence: Date?, ahora: Date, deHoy: Bool, _ cal: Calendar) -> String? {
        guard let vence else { return nil }
        if vence < cal.startOfDay(for: ahora) { return "Vencida" }
        let hora = tieneHora(vence, cal) ? horaTexto(vence, cal) : nil
        if deHoy { return hora }
        let dia = dias[max(0, min(6, cal.component(.weekday, from: vence) - 1))]
        return [dia, hora].compactMap { $0 }.joined(separator: " ")
    }

    /// "3:00 p. m." (reloj de 12 horas, como el resto de la app).
    static func horaTexto(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let minutos = m < 10 ? "0\(m)" : "\(m)"
        return "\(h12):\(minutos) " + (h < 12 ? "a. m." : "p. m.")
    }
}
