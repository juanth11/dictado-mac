import Foundation

/// Nombres en español, fijos: no dependen del idioma del Mac ni de ICU (y se prueban igual en cualquier máquina).
public enum NombresFecha {
    public static let diasCortos = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]   // 1 = domingo, como `Calendar`
    public static let mesesCortos = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
    public static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                               "octubre", "noviembre", "diciembre"]
}

/// Lo que dice el widget Fecha: "Dom Nov" y el número del día.
public struct PartesFecha: Equatable, Sendable {
    public var diaSemana: String
    public var mes: String
    public var dia: Int

    public init(_ fecha: Date, calendario: Calendar = .current) {
        let c = calendario.dateComponents([.weekday, .month, .day], from: fecha)
        diaSemana = NombresFecha.diasCortos[((c.weekday ?? 1) - 1) % 7]
        mes = NombresFecha.mesesCortos[((c.month ?? 1) - 1) % 12]
        dia = c.day ?? 1
    }
}

/// El widget Mes en puntos: un punto por día; los pasados (hoy incluido) van tenues y los que quedan, plenos.
public struct MesEnPuntos: Equatable, Sendable {
    public var nombreMes: String
    public var dias: Int
    public var hoy: Int

    public init(_ fecha: Date, calendario: Calendar = .current) {
        let c = calendario.dateComponents([.month, .day], from: fecha)
        nombreMes = NombresFecha.meses[((c.month ?? 1) - 1) % 12]
        dias = calendario.range(of: .day, in: .month, for: fecha)?.count ?? 30
        hoy = min(max(c.day ?? 1, 1), dias)
    }

    /// Días que faltan para acabar el mes (hoy no cuenta).
    public var restantes: Int { dias - hoy }

    /// `true` = ya pasó (tenue), en orden del 1 al último día.
    public var pasados: [Bool] { (1...dias).map { $0 <= hoy } }

    /// "NOVIEMBRE · 15 DÍAS". El último día: "NOVIEMBRE · ÚLTIMO DÍA".
    public var rotulo: String {
        let cola = restantes == 0 ? "ÚLTIMO DÍA" : (restantes == 1 ? "1 DÍA" : "\(restantes) DÍAS")
        return nombreMes.uppercased() + " · " + cola
    }
}
