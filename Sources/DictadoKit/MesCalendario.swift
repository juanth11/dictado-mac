import Foundation

/// Un día del mes en la cuadrícula: cuánto está ocupado y si es festivo u hoy.
public struct DiaMes: Equatable, Sendable, Identifiable {
    public var dia: Date
    public var numero: Int
    /// Pertenece al mes que se mira (los de relleno de las semanas de los bordes van tenues).
    public var delMes: Bool
    public var esHoy: Bool
    /// Sábado o domingo (o un día que no está en `config.dias`).
    public var finDeSemana: Bool
    public var festivo: String?
    public var eventos: Int
    /// Minutos ocupados dentro del horario laboral.
    public var minutosOcupados: Int
    /// 0 a 1: lo ocupado del horario laboral, para el color de la celda.
    public var densidad: Double
    public var id: Date { dia }
}

public struct VistaMes: Equatable, Sendable {
    /// "noviembre 2026".
    public var titulo: String
    /// El primer día del mes.
    public var mes: Date
    /// Seis filas como máximo, de lunes a domingo.
    public var semanas: [[DiaMes]]
}

public enum MesCalendario {
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                                "noviembre", "diciembre"]
    public static let inicialesDias = ["L", "M", "M", "J", "V", "S", "D"]

    /// El primer día del mes de `fecha`.
    public static func primero(de fecha: Date, calendario: Calendar = .current) -> Date {
        calendario.date(from: calendario.dateComponents([.year, .month], from: fecha)) ?? calendario.startOfDay(for: fecha)
    }

    /// Mes anterior (-1) o siguiente (+1).
    public static func desplazar(_ mes: Date, por n: Int, calendario: Calendar = .current) -> Date {
        primero(de: calendario.date(byAdding: .month, value: n, to: primero(de: mes, calendario: calendario)) ?? mes, calendario: calendario)
    }

    /// Desde el lunes de la primera semana hasta el domingo de la última: lo que hay que pedirle a Calendario para pintar el mes.
    public static func ventana(de mes: Date, calendario: Calendar = .current) -> DateInterval {
        var cal = calendario
        cal.firstWeekday = 2
        let primero = Self.primero(de: mes, calendario: cal)
        let lunes = cal.dateInterval(of: .weekOfYear, for: primero)?.start ?? primero
        let siguiente = cal.date(byAdding: .month, value: 1, to: primero) ?? primero.addingTimeInterval(31 * 86_400)
        let ultimo = cal.date(byAdding: .day, value: -1, to: siguiente) ?? siguiente
        let fin = cal.dateInterval(of: .weekOfYear, for: ultimo)?.end ?? siguiente
        return DateInterval(start: lunes, end: max(fin, lunes.addingTimeInterval(86_400)))
    }

    /// La cuadrícula del mes (lunes primero). `eventos` son solo los que bloquean (sin los de todo el día ni los "libre").
    public static func armar(mes: Date, eventos: [Intervalo], festivos: [Date: String] = [:], ahora: Date,
                             config: ConfigHuecos = .porOmision, calendario: Calendar = .current) -> VistaMes {
        var cal = calendario
        cal.firstWeekday = 2
        let primero = Self.primero(de: mes, calendario: cal)
        let v = ventana(de: primero, calendario: cal)
        let mesDe = cal.component(.month, from: primero)
        let anio = cal.component(.year, from: primero)
        var semanas: [[DiaMes]] = []
        var dia = v.start
        var fila: [DiaMes] = []
        for _ in 0..<42 {
            guard dia < v.end else { break }
            let sig = cal.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86_400)
            let abre = cal.date(byAdding: .minute, value: config.inicioMin, to: dia) ?? dia
            let cierra = cal.date(byAdding: .minute, value: config.finMin, to: dia) ?? sig
            let delDia = eventos.filter { $0.inicio < sig && $0.fin > dia }
            var ocupado = 0.0
            for b in Huecos.unir(delDia) {
                let a = max(b.inicio, abre), z = min(b.fin, cierra)
                if z > a { ocupado += z.timeIntervalSince(a) / 60 }
            }
            let laboral = max(1, Double(config.finMin - config.inicioMin))
            let semana = cal.component(.weekday, from: dia)
            fila.append(DiaMes(dia: dia, numero: cal.component(.day, from: dia), delMes: cal.component(.month, from: dia) == mesDe,
                               esHoy: cal.isDate(dia, inSameDayAs: ahora), finDeSemana: !config.dias.contains(semana),
                               festivo: festivos[dia], eventos: delDia.count, minutosOcupados: Int(ocupado.rounded()),
                               densidad: min(1, ocupado / laboral)))
            if fila.count == 7 {
                semanas.append(fila)
                fila = []
            }
            dia = sig
        }
        if !fila.isEmpty { semanas.append(fila) }
        return VistaMes(titulo: "\(meses[mesDe - 1]) \(anio)", mes: primero, semanas: semanas)
    }

    /// Los huecos libres de un día concreto del mes: con el mismo horario y largo mínimo de siempre; un festivo o un día
    /// fuera de `config.dias` no tiene huecos.
    public static func huecosDelDia(_ dia: Date, ocupados: [Intervalo], config: ConfigHuecos = .porOmision, ahora: Date? = nil,
                                    festivos: Set<Date> = [], calendario: Calendar = .current) -> [Intervalo] {
        let inicio = calendario.startOfDay(for: dia)
        let fin = calendario.date(byAdding: .day, value: 1, to: inicio) ?? inicio.addingTimeInterval(86_400)
        guard config.dias.contains(calendario.component(.weekday, from: inicio)) else { return [] }
        var c = config
        c.diasHorizonte = 1
        c.dias = [calendario.component(.weekday, from: inicio)]
        if ahora == nil { c.redondeoMin = 1 }
        // Mirando desde las 0:00 del día (o desde ahora, si es hoy), el único día laboral del horizonte es ese.
        return Huecos.libres(ocupados: ocupados, desde: max(inicio, ahora ?? inicio), config: c, excluyendo: festivos, calendario: calendario)
            .filter { $0.inicio >= inicio && $0.fin <= fin }
    }
}
