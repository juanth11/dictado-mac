import Foundation

// La Semana del Centro: siete columnas (de lunes a domingo) con los eventos como bloques sobre una línea de tiempo vertical, los
// huecos libres, la marca de ahora y las tareas abiertas bajo el día en que vencen. Todo en fracciones de 0 a 1 del alto de la
// columna: la vista solo multiplica. Sin SwiftUI ni EventKit: los eventos llegan como `EventoSemana`.

public struct EventoSemana: Equatable, Sendable {
    public var id: String
    public var titulo: String
    public var inicio: Date
    public var fin: Date
    /// "4 personas · Meet".
    public var detalle: String?

    public init(id: String, titulo: String, inicio: Date, fin: Date, detalle: String? = nil) {
        self.id = id
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.detalle = detalle
    }
}

public struct TareaSemana: Equatable, Sendable, Identifiable {
    public var id: String
    public var texto: String
    /// AAAA-MM-DD; nil = sin fecha.
    public var vence: String?
    public var vencida = false

    public init(id: String, texto: String, vence: String? = nil) {
        self.id = id
        self.texto = texto
        self.vence = vence
    }
}

public struct BloqueSemana: Equatable, Sendable, Identifiable {
    public var id: String
    public var titulo: String
    public var detalle: String?
    public var inicio: Date
    public var fin: Date
    /// Fracciones del alto de la columna.
    public var arriba: Double
    public var alto: Double
    /// Si se encima con otros: en qué carril va y cuántos carriles hay en su grupo (el ancho es 1/carriles).
    public var carril: Int
    public var carriles: Int
}

public struct TramoVertical: Equatable, Sendable {
    public var arriba: Double
    public var alto: Double
    public var inicio: Date
    public var fin: Date
}

public struct DiaSemana: Equatable, Sendable, Identifiable {
    public var id: Date { dia }
    public var dia: Date
    /// "lun".
    public var etiqueta: String
    public var numero: Int
    public var esHoy: Bool
    public var bloques: [BloqueSemana]
    public var huecos: [TramoVertical]
    /// La marca roja de ahora (fracción del alto); nil si no es hoy o cae fuera de la ventana.
    public var ahora: Double?
    public var todoElDia: [String]
    public var tareas: [TareaSemana]
}

public struct VistaSemanal: Equatable, Sendable {
    public var dias: [DiaSemana]
    public var horaDesde: Int
    public var horaHasta: Int
    public var sinFecha: [TareaSemana]
    /// "16 – 22 nov" o "30 nov – 6 dic".
    public var titulo: String
    /// Las horas de la regla: desde, cada dos, hasta (con su fracción).
    public var marcas: [(hora: Int, fraccion: Double)] {
        let n = max(1, horaHasta - horaDesde)
        return stride(from: horaDesde, through: horaHasta, by: 2).map { ($0, Double($0 - horaDesde) / Double(n)) }
    }

    public static func == (a: VistaSemanal, b: VistaSemanal) -> Bool {
        a.dias == b.dias && a.horaDesde == b.horaDesde && a.horaHasta == b.horaHasta && a.sinFecha == b.sinFecha && a.titulo == b.titulo
    }
}

public enum SemanaCentro {
    /// El lunes de la semana que contiene `fecha`.
    public static func lunes(de fecha: Date, calendario: Calendar = .current) -> Date {
        var cal = calendario
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: fecha)?.start ?? cal.startOfDay(for: fecha)
    }

    /// Arma la semana `desplazamiento` (0 = esta, 1 = la que viene). `eventos` son los que bloquean y `huecos` los libres (los mismos
    /// de la isla, con el horizonte que se quiera); `tareas` las abiertas.
    public static func armar(desplazamiento: Int, eventos: [EventoSemana], todoElDia: [(dia: Date, titulo: String)] = [], huecos: [Intervalo],
                             tareas: [TareaSemana], ahora: Date, config: ConfigHuecos = .porOmision, calendario: Calendar = .current) -> VistaSemanal {
        var cal = calendario
        cal.firstWeekday = 2
        let inicioSemana = cal.date(byAdding: .day, value: 7 * desplazamiento, to: lunes(de: ahora, calendario: cal)) ?? ahora
        let hoy = cal.startOfDay(for: ahora)
        let dias: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: inicioSemana) }
        let finSemana = cal.date(byAdding: .day, value: 7, to: inicioSemana) ?? inicioSemana

        // La ventana de horas: el horario laboral, ampliado si algún evento de la semana cae fuera. La misma para las siete columnas.
        var desde = max(0, min(config.inicioMin / 60, 23)), hasta = min(24, max(desde + 1, (config.finMin + 59) / 60))
        for e in eventos where e.inicio < finSemana && e.fin > inicioSemana {
            let dia = cal.startOfDay(for: max(e.inicio, inicioSemana))
            let a = Int(max(e.inicio, dia).timeIntervalSince(dia) / 3600)
            let b = Int((min(e.fin, cal.date(byAdding: .day, value: 1, to: dia) ?? e.fin).timeIntervalSince(dia) / 3600).rounded(.up))
            desde = min(desde, a)
            hasta = max(hasta, min(24, b))
        }
        if hasta - desde < 6 { hasta = min(24, desde + 6); desde = max(0, hasta - 6) }

        func clasificar(_ t: TareaSemana) -> Date? {
            guard let v = t.vence, let d = dia(v, cal) else { return nil }
            return d
        }
        var porDia: [Date: [TareaSemana]] = [:]
        var sinFecha: [TareaSemana] = []
        for var t in tareas {
            guard let d = clasificar(t) else {
                if t.vence == nil { sinFecha.append(t) }
                continue
            }
            if dias.contains(d) {
                porDia[d, default: []].append(t)
            } else if d < hoy, dias.contains(hoy) {   // vencida: se ve hoy, marcada
                t.vencida = true
                porDia[hoy, default: []].append(t)
            }
        }

        let armados = dias.map { dia -> DiaSemana in
            let abre = cal.date(byAdding: .hour, value: desde, to: dia) ?? dia
            let cierra = cal.date(byAdding: .hour, value: hasta, to: dia) ?? dia
            let largo = max(1, cierra.timeIntervalSince(abre))
            func tramo(_ i: Intervalo) -> (Double, Double)? {
                let a = max(i.inicio, abre), b = min(i.fin, cierra)
                guard b > a else { return nil }
                return (a.timeIntervalSince(abre) / largo, b.timeIntervalSince(a) / largo)
            }
            let delDia = eventos.filter { $0.fin > abre && $0.inicio < cierra }.sorted { ($0.inicio, $0.id) < ($1.inicio, $1.id) }
            let c = cal.dateComponents([.weekday, .day], from: dia)
            return DiaSemana(
                dia: dia, etiqueta: NombresFecha.diasCortos[((c.weekday ?? 1) - 1) % 7].lowercased(), numero: c.day ?? 1, esHoy: dia == hoy,
                bloques: carriles(delDia, abre: abre, cierra: cierra),
                huecos: huecos.compactMap { h -> TramoVertical? in
                    guard cal.isDate(h.inicio, inSameDayAs: dia), let (a, l) = tramo(h) else { return nil }
                    return TramoVertical(arriba: a, alto: l, inicio: max(h.inicio, abre), fin: min(h.fin, cierra))
                },
                ahora: dia == hoy && ahora >= abre && ahora <= cierra ? ahora.timeIntervalSince(abre) / largo : nil,
                todoElDia: todoElDia.filter { cal.isDate($0.dia, inSameDayAs: dia) }.map(\.titulo),
                tareas: (porDia[dia] ?? []).sorted { ($0.vencida ? 0 : 1, $0.id) < ($1.vencida ? 0 : 1, $1.id) })
        }
        return VistaSemanal(dias: armados, horaDesde: desde, horaHasta: hasta, sinFecha: sinFecha, titulo: titulo(inicioSemana, cal))
    }

    /// Los eventos de un día en carriles: los que se encimen se reparten el ancho de la columna.
    static func carriles(_ eventos: [EventoSemana], abre: Date, cierra: Date) -> [BloqueSemana] {
        let largo = max(1, cierra.timeIntervalSince(abre))
        var salida: [BloqueSemana] = []
        var grupo: [(e: EventoSemana, carril: Int)] = []
        var finGrupo = Date.distantPast
        var finCarril: [Date] = []
        func cerrarGrupo() {
            let n = max(1, finCarril.count)
            for (e, carril) in grupo {
                let a = max(e.inicio, abre), b = min(e.fin, cierra)
                salida.append(BloqueSemana(id: e.id, titulo: e.titulo, detalle: e.detalle, inicio: e.inicio, fin: e.fin,
                                           arriba: a.timeIntervalSince(abre) / largo, alto: max(0.012, b.timeIntervalSince(a) / largo), carril: carril, carriles: n))
            }
            grupo = []
            finCarril = []
        }
        for e in eventos {
            if e.inicio >= finGrupo { cerrarGrupo() }
            let libre = finCarril.firstIndex { $0 <= e.inicio } ?? finCarril.count
            if libre == finCarril.count { finCarril.append(e.fin) } else { finCarril[libre] = e.fin }
            grupo.append((e, libre))
            finGrupo = max(finGrupo, e.fin)
        }
        cerrarGrupo()
        return salida
    }

    /// Las tareas de hoy: las que vencen hoy o antes y las que no tienen fecha (como el documento `tablero` del centro).
    public static func tareasDeHoy(_ tareas: [TareaSemana], ahora: Date, calendario: Calendar = .current) -> Int {
        let hoy = calendario.startOfDay(for: ahora)
        return tareas.filter { t in
            guard let v = t.vence else { return true }
            guard let d = dia(v, calendario) else { return false }
            return d <= hoy
        }.count
    }

    static func dia(_ s: String, _ cal: Calendar) -> Date? {
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// "16 – 22 nov", "30 nov – 6 dic".
    static func titulo(_ lunes: Date, _ cal: Calendar) -> String {
        let domingo = cal.date(byAdding: .day, value: 6, to: lunes) ?? lunes
        let a = cal.dateComponents([.day, .month], from: lunes), b = cal.dateComponents([.day, .month], from: domingo)
        func mes(_ c: DateComponents) -> String { NombresFecha.mesesCortos[((c.month ?? 1) - 1) % 12].lowercased() }
        return a.month == b.month ? "\(a.day ?? 1) – \(b.day ?? 1) \(mes(b))" : "\(a.day ?? 1) \(mes(a)) – \(b.day ?? 1) \(mes(b))"
    }
}
