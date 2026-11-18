import Foundation

/// Un día de la semana como una barra de ocupado: cuántos eventos tiene y qué tramos del horario laboral ocupan.
public struct BarraDia: Equatable, Sendable {
    public var dia: Date
    /// "lun 16".
    public var etiqueta: String
    public var eventos: Int
    /// Tramos ocupados en fracciones (0 a 1) del horario laboral.
    public var ocupado: [LineaDelDia.Tramo]
    public var esHoy: Bool
}

public enum SemanaBarras {
    private static let cortos = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    /// Los días laborales (de `config.dias`) de la semana de lunes a domingo que contiene `ahora`, con sus barras.
    /// `eventos` son solo los que bloquean (sin los de todo el día ni los marcados como "libre").
    public static func armar(eventos: [Intervalo], ahora: Date, config: ConfigHuecos = .porOmision,
                             calendario: Calendar = .current) -> [BarraDia] {
        var cal = calendario
        cal.firstWeekday = 2
        guard let lunes = cal.dateInterval(of: .weekOfYear, for: ahora)?.start else { return [] }
        let desde = config.inicioMin / 60, hasta = max(desde + 1, (config.finMin + 59) / 60)
        var salida: [BarraDia] = []
        for n in 0..<7 {
            guard let dia = cal.date(byAdding: .day, value: n, to: lunes),
                  config.dias.contains(cal.component(.weekday, from: dia)) else { continue }
            let fin = cal.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86_400)
            let delDia = eventos.filter { $0.inicio < fin && $0.fin > dia }
            let linea = LineaDelDia.armar(dia: dia, eventos: delDia, libre: nil, ahora: ahora, inicioHora: desde, finHora: hasta,
                                          calendario: cal)
            let c = cal.dateComponents([.weekday, .day], from: dia)
            salida.append(BarraDia(dia: dia, etiqueta: "\(cortos[(c.weekday ?? 1) - 1]) \(c.day ?? 0)", eventos: delDia.count,
                                   ocupado: linea.eventos, esHoy: cal.isDate(dia, inSameDayAs: ahora)))
        }
        return salida
    }
}
