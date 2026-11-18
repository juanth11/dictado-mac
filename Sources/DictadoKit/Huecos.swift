import Foundation

/// Un tramo de tiempo [inicio, fin).
public struct Intervalo: Equatable, Sendable {
    public var inicio: Date
    public var fin: Date

    public init(inicio: Date, fin: Date) {
        self.inicio = inicio
        self.fin = fin
    }

    public var minutos: Double { fin.timeIntervalSince(inicio) / 60 }
}

/// Cuándo se puede agendar: horario laboral, largo mínimo y cuántos días laborales mirar.
public struct ConfigHuecos: Equatable, Sendable {
    /// Minutos desde la medianoche (8:00 → 480).
    public var inicioMin: Int
    public var finMin: Int
    /// Días de la semana en la numeración de `Calendar` (1 = domingo … 7 = sábado). Por omisión lunes a viernes.
    public var dias: Set<Int>
    public var minimoMin: Int
    /// Cuántos días laborales (contando hoy, si lo es) se revisan.
    public var diasHorizonte: Int
    /// El hueco de hoy no empieza antes de "ahora" redondeado hacia arriba a este múltiplo (15 → 3:07 pasa a 3:15).
    public var redondeoMin: Int

    public init(inicioMin: Int = 8 * 60, finMin: Int = 18 * 60, dias: Set<Int> = [2, 3, 4, 5, 6],
                minimoMin: Int = 30, diasHorizonte: Int = 5, redondeoMin: Int = 15) {
        self.inicioMin = inicioMin
        self.finMin = finMin
        self.dias = dias
        self.minimoMin = minimoMin
        self.diasHorizonte = diasHorizonte
        self.redondeoMin = redondeoMin
    }

    public static let porOmision = ConfigHuecos()
}

public enum Huecos {
    /// Une los tramos que se tocan o se encimen y los deja ordenados. Los vacíos o al revés se descartan.
    public static func unir(_ tramos: [Intervalo]) -> [Intervalo] {
        var salida: [Intervalo] = []
        for t in tramos.filter({ $0.fin > $0.inicio }).sorted(by: { $0.inicio < $1.inicio }) {
            if let ultimo = salida.last, t.inicio <= ultimo.fin {
                salida[salida.count - 1].fin = max(ultimo.fin, t.fin)
            } else {
                salida.append(t)
            }
        }
        return salida
    }

    /// Los huecos libres del horario laboral. `ocupados` son solo los eventos que bloquean (sin los de todo el día,
    /// los rechazados ni los marcados como "libre"); pueden encimarse y cruzar la medianoche.
    /// `excluyendo` son inicios de día que no se ofrecen (festivos): no cuentan como día laboral del horizonte.
    public static func libres(ocupados: [Intervalo], desde ahora: Date, config: ConfigHuecos = .porOmision,
                              excluyendo: Set<Date> = [], calendario: Calendar = .current) -> [Intervalo] {
        guard config.finMin > config.inicioMin, config.diasHorizonte > 0, !config.dias.isEmpty else { return [] }
        let minimo = Double(max(1, config.minimoMin)) * 60
        let bloques = unir(ocupados)
        let desdeAhora = redondear(ahora, a: config.redondeoMin, calendario: calendario)
        var salida: [Intervalo] = []
        var dia = calendario.startOfDay(for: ahora)
        var laborales = 0
        // Tope de 60 días por si los días elegidos no existieran: el bucle siempre termina.
        for _ in 0..<60 where laborales < config.diasHorizonte {
            defer { dia = calendario.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86_400) }
            guard config.dias.contains(calendario.component(.weekday, from: dia)), !excluyendo.contains(dia),
                  let abre = calendario.date(byAdding: .minute, value: config.inicioMin, to: dia),
                  let cierra = calendario.date(byAdding: .minute, value: config.finMin, to: dia) else { continue }
            if cierra <= desdeAhora { continue }  // hoy ya cerró: no cuenta como uno de los días del horizonte
            laborales += 1
            var cursor = max(abre, desdeAhora)
            for b in bloques where b.fin > cursor && b.inicio < cierra {
                if b.inicio > cursor, b.inicio.timeIntervalSince(cursor) >= minimo {
                    salida.append(Intervalo(inicio: cursor, fin: min(b.inicio, cierra)))
                }
                cursor = max(cursor, b.fin)
                if cursor >= cierra { break }
            }
            if cierra.timeIntervalSince(cursor) >= minimo { salida.append(Intervalo(inicio: cursor, fin: cierra)) }
        }
        return salida
    }

    private static func redondear(_ fecha: Date, a minutos: Int, calendario: Calendar) -> Date {
        guard minutos > 1 else { return fecha }
        let inicioDia = calendario.startOfDay(for: fecha)
        let paso = Double(minutos) * 60
        let transcurrido = fecha.timeIntervalSince(inicioDia)
        return inicioDia.addingTimeInterval((transcurrido / paso).rounded(.up) * paso)
    }
}
