import Foundation

/// Un día festivo: año, mes y día del calendario gregoriano, y cómo se llama.
public struct Festivo: Equatable, Sendable {
    public var año: Int
    public var mes: Int
    public var dia: Int
    public var nombre: String

    public init(año: Int, mes: Int, dia: Int, nombre: String) {
        self.año = año
        self.mes = mes
        self.dia = dia
        self.nombre = nombre
    }

    /// "2026-11-16", para comparar y para las pruebas.
    public var clave: String { Festivos.clave(año: año, mes: mes, dia: dia) }
}

/// Los festivos de un país, calculados aquí (sin red). Hoy solo Colombia; con otro país no hay lista incorporada.
public enum Festivos {
    public static func clave(año: Int, mes: Int, dia: Int) -> String {
        String(format: "%04d-%02d-%02d", año, mes, dia)
    }

    /// Los festivos del año para ese país (código ISO: "CO"). Un país sin lista da `[]`.
    public static func de(pais: String, año: Int) -> [Festivo] {
        switch pais.uppercased() {
        case "CO": return colombia(año: año)
        default: return []
        }
    }

    // MARK: Colombia (Ley 51 de 1983, "Ley Emiliani", y el calendario de Semana Santa)

    /// Los 18 festivos de Colombia:
    /// - fijos: 1 de enero, 1 de mayo, 20 de julio, 7 de agosto, 8 de diciembre y 25 de diciembre;
    /// - trasladados al lunes siguiente (si no caen en lunes): Reyes (6 de enero), San José (19 de marzo), San Pedro y San
    ///   Pablo (29 de junio), Asunción (15 de agosto), Día de la Raza (12 de octubre), Todos los Santos (1 de noviembre) e
    ///   Independencia de Cartagena (11 de noviembre);
    /// - según la Pascua: Jueves y Viernes Santo (Pascua −3 y −2, no se trasladan) y, al lunes, la Ascensión (Pascua + 43
    ///   días), Corpus Christi (+ 64) y el Sagrado Corazón (+ 71).
    public static func colombia(año: Int) -> [Festivo] {
        var lista: [Festivo] = []
        func fijo(_ m: Int, _ d: Int, _ nombre: String) { lista.append(Festivo(año: año, mes: m, dia: d, nombre: nombre)) }
        func lunes(_ m: Int, _ d: Int, _ nombre: String) {
            let n = diasDesdeEpoca(año: año, mes: m, dia: d)
            let (a, mm, dd) = civil(desdeEpoca: n + (8 - diaDeSemana(n)) % 7)
            lista.append(Festivo(año: a, mes: mm, dia: dd, nombre: nombre))
        }
        func pascua(_ desfase: Int, _ nombre: String) {
            let (m, d) = domingoDePascua(año: año)
            let (a, mm, dd) = civil(desdeEpoca: diasDesdeEpoca(año: año, mes: m, dia: d) + desfase)
            lista.append(Festivo(año: a, mes: mm, dia: dd, nombre: nombre))
        }
        fijo(1, 1, "Año Nuevo")
        lunes(1, 6, "Reyes Magos")
        lunes(3, 19, "San José")
        pascua(-3, "Jueves Santo")
        pascua(-2, "Viernes Santo")
        fijo(5, 1, "Día del Trabajo")
        pascua(43, "Ascensión del Señor")
        pascua(64, "Corpus Christi")
        pascua(71, "Sagrado Corazón")
        lunes(6, 29, "San Pedro y San Pablo")
        fijo(7, 20, "Día de la Independencia")
        fijo(8, 7, "Batalla de Boyacá")
        lunes(8, 15, "Asunción de la Virgen")
        lunes(10, 12, "Día de la Raza")
        lunes(11, 1, "Todos los Santos")
        lunes(11, 11, "Independencia de Cartagena")
        fijo(12, 8, "Inmaculada Concepción")
        fijo(12, 25, "Navidad")
        return lista.sorted { $0.clave < $1.clave }
    }

    /// El domingo de Pascua (mes, día) por el cómputo gregoriano (algoritmo anónimo de Meeus/Jones/Butcher).
    public static func domingoDePascua(año: Int) -> (mes: Int, dia: Int) {
        let a = año % 19, b = año / 100, c = año % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let mes = (h + l - 7 * m + 114) / 31
        let dia = (h + l - 7 * m + 114) % 31 + 1
        return (mes, dia)
    }

    // MARK: Aritmética de fechas sin `Calendar` (días desde 1970-01-01, 0 = jueves)

    static func diasDesdeEpoca(año: Int, mes: Int, dia: Int) -> Int {
        let y = mes <= 2 ? año - 1 : año
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (mes + (mes > 2 ? -3 : 9)) + 2) / 5 + dia - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(desdeEpoca z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// 1 = lunes … 7 = domingo.
    static func diaDeSemana(_ n: Int) -> Int { ((n % 7) + 7 + 3) % 7 + 1 }
}

/// Los festivos puestos sobre fechas reales: un diccionario por inicio de día.
public enum DiasFestivos {
    /// `[inicio del día: nombre]` de todos los festivos entre `desde` y `hasta` (inclusive por día).
    public static func entre(_ desde: Date, _ hasta: Date, pais: String, calendario: Calendar = .current) -> [Date: String] {
        let a = calendario.component(.year, from: desde), b = calendario.component(.year, from: hasta)
        guard b >= a, b - a < 20 else { return [:] }
        var salida: [Date: String] = [:]
        for año in a...b {
            for f in Festivos.de(pais: pais, año: año) {
                guard let dia = calendario.date(from: DateComponents(year: f.año, month: f.mes, day: f.dia)) else { continue }
                let inicio = calendario.startOfDay(for: dia)
                if inicio >= calendario.startOfDay(for: desde), inicio <= hasta { salida[inicio] = f.nombre }
            }
        }
        return salida
    }

    /// Une el calendario de festivos que hay en Calendario (títulos de eventos de todo el día) con la lista incorporada;
    /// si el Mac ya trae festivos, mandan esos (traen los trasladados del país donde vives).
    public static func combinar(delCalendario: [Date: String], incorporados: [Date: String]) -> [Date: String] {
        delCalendario.isEmpty ? incorporados : delCalendario
    }

    /// ¿El título de un calendario parece de festivos? ("Festivos en Colombia", "Holidays in Colombia", "Días feriados").
    public static func pareceDeFestivos(_ titulo: String, nombreExplicito: String? = nil) -> Bool {
        let t = titulo.lowercased()
        if let n = nombreExplicito?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty { return t == n }
        return ["festivo", "holiday", "feriado", "días festivos", "dias festivos", "fêtes"].contains { t.contains($0) }
    }
}
