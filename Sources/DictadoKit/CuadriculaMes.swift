import Foundation

/// Un día de la cuadrícula del widget de calendario del lanzador.
public struct CeldaMes: Equatable, Sendable, Identifiable {
    public var dia: Date
    public var numero: Int
    /// Del mes que se muestra; los de relleno de las semanas de los bordes no se dibujan.
    public var delMes: Bool
    public var esHoy: Bool
    /// Sábado o domingo.
    public var finDeSemana: Bool
    public var conEventos: Bool
    public var id: Date { dia }
}

/// El mes completo para el widget Fecha: título, iniciales de los días (lunes primero) y de 4 a 6 semanas de 7 celdas.
public struct CuadriculaMes: Equatable, Sendable {
    /// "Noviembre".
    public var mes: String
    public var anio: Int
    public var semanas: [[CeldaMes]]

    public static let iniciales = MesCalendario.inicialesDias

    /// `diasConEventos` son días (cualquier hora) en los que hay algo en la agenda; se comparan por día, no por instante.
    public static func armar(_ fecha: Date, diasConEventos: Set<Date> = [], ahora: Date, calendario: Calendar = .current) -> CuadriculaMes {
        var cal = calendario
        cal.firstWeekday = 2
        let primero = MesCalendario.primero(de: fecha, calendario: cal)
        let ventana = MesCalendario.ventana(de: primero, calendario: cal)
        let mesNumero = cal.component(.month, from: primero)
        let marcados = Set(diasConEventos.map { cal.startOfDay(for: $0) })
        var semanas: [[CeldaMes]] = []
        var fila: [CeldaMes] = []
        var dia = ventana.start
        for _ in 0..<42 where dia < ventana.end {
            let c = cal.dateComponents([.month, .day, .weekday], from: dia)
            fila.append(CeldaMes(dia: dia, numero: c.day ?? 1, delMes: c.month == mesNumero, esHoy: cal.isDate(dia, inSameDayAs: ahora),
                                 finDeSemana: c.weekday == 1 || c.weekday == 7, conEventos: marcados.contains(dia)))
            if fila.count == 7 {
                semanas.append(fila)
                fila = []
            }
            dia = cal.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86_400)
        }
        if !fila.isEmpty { semanas.append(fila) }
        let nombre = NombresFecha.meses[(mesNumero - 1) % 12]
        return CuadriculaMes(mes: nombre.prefix(1).uppercased() + nombre.dropFirst(), anio: cal.component(.year, from: primero), semanas: semanas)
    }

    /// Los días (a las 0:00) que toca cada intervalo; uno sin duración cuenta en el día en que empieza. Sirve para eventos de varios días
    /// y de todo el día (su fin cae el último día o a las 0:00 del siguiente: ese instante exacto no se cuenta).
    public static func dias(de intervalos: [Intervalo], calendario: Calendar = .current) -> Set<Date> {
        var salida = Set<Date>()
        for i in intervalos {
            var d = calendario.startOfDay(for: i.inicio)
            let fin = max(i.fin, i.inicio)
            repeat {
                salida.insert(d)
                d = calendario.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
            } while d < fin
        }
        return salida
    }

    /// El enlace que abre Calendario en ese día (sin permisos de automatización): `calshow:` + segundos desde 2001.
    public static func enlaceCalendario(_ dia: Date, calendario: Calendar = .current) -> URL? {
        URL(string: "calshow:\(Int(calendario.startOfDay(for: dia).timeIntervalSinceReferenceDate))")
    }
}
