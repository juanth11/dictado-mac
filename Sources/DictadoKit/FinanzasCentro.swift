import Foundation

// La sección Finanzas del Centro (`python3 -m centro finanzas --json`): el resumen del ledger (la única contabilidad), los últimos meses,
// los próximos pagos y los dos estados viejos de `_sistema/status` (proyección de caja y MRR de Orbita) con la fecha de su fuente. Una
// cifra que no existe llega como null y no se dibuja: nunca un cero inventado. Los montos están en pesos colombianos.

public struct PagoProximo: Equatable, Sendable, Identifiable {
    public var concepto: String
    public var monto: Double
    public var vence: Date?
    public var dias: Int?
    public var critico: Bool
    public var id: String { concepto + "|" + String(vence?.timeIntervalSince1970 ?? 0) }

    public init(concepto: String, monto: Double, vence: Date? = nil, dias: Int? = nil, critico: Bool = false) {
        self.concepto = concepto
        self.monto = monto
        self.vence = vence
        self.dias = dias
        self.critico = critico
    }
}

public struct MesFinanzas: Equatable, Sendable, Identifiable {
    public var mes: String
    public var ingreso: Double
    public var egreso: Double
    public var neto: Double
    public var id: String { mes }

    public init(mes: String, ingreso: Double, egreso: Double, neto: Double) {
        self.mes = mes
        self.ingreso = ingreso
        self.egreso = egreso
        self.neto = neto
    }
}

/// Una fuente con su fecha: lo que muestra "dato de hace 133 días".
public struct FuenteFechada: Equatable, Sendable {
    public var fecha: Date?
    public var dias: Int

    public init(fecha: Date?, dias: Int) {
        self.fecha = fecha
        self.dias = dias
    }
}

public struct Finanzas: Equatable, Sendable {
    public var disponible: Bool
    public var actualizado: Date?
    public var diasSinActualizar: Int?
    public var patrimonio: Double?
    public var delta: Double?
    public var liquidez: Double?
    public var netoMes: Double?
    public var ingresoMes: Double?
    public var egresoMes: Double?
    public var colchon: Double?
    public var colchonPiso: Double?
    public var colchonMeta: Double?
    public var alertas: [String]
    public var historico: [MesFinanzas]
    public var pagos: [PagoProximo]
    /// Caja, burn, runway y escenarios de la proyección personal: nil si la fuente no los trae.
    public var proyeccionDisponible: Bool
    public var proyeccionFuente: FuenteFechada?
    public var caja: Double?
    public var burn: Double?
    public var runwayMeses: Double?
    public var orbitaDisponible: Bool
    public var orbitaFuente: FuenteFechada?
    public var mrr: Double?
    public var enlace: String?

    public init(disponible: Bool = false, actualizado: Date? = nil, diasSinActualizar: Int? = nil, patrimonio: Double? = nil, delta: Double? = nil, liquidez: Double? = nil,
                netoMes: Double? = nil, ingresoMes: Double? = nil, egresoMes: Double? = nil, colchon: Double? = nil, colchonPiso: Double? = nil, colchonMeta: Double? = nil,
                alertas: [String] = [], historico: [MesFinanzas] = [], pagos: [PagoProximo] = [], proyeccionDisponible: Bool = false,
                proyeccionFuente: FuenteFechada? = nil, caja: Double? = nil, burn: Double? = nil, runwayMeses: Double? = nil, orbitaDisponible: Bool = false,
                orbitaFuente: FuenteFechada? = nil, mrr: Double? = nil, enlace: String? = nil) {
        self.disponible = disponible
        self.actualizado = actualizado
        self.diasSinActualizar = diasSinActualizar
        self.patrimonio = patrimonio
        self.delta = delta
        self.liquidez = liquidez
        self.netoMes = netoMes
        self.ingresoMes = ingresoMes
        self.egresoMes = egresoMes
        self.colchon = colchon
        self.colchonPiso = colchonPiso
        self.colchonMeta = colchonMeta
        self.alertas = alertas
        self.historico = historico
        self.pagos = pagos
        self.proyeccionDisponible = proyeccionDisponible
        self.proyeccionFuente = proyeccionFuente
        self.caja = caja
        self.burn = burn
        self.runwayMeses = runwayMeses
        self.orbitaDisponible = orbitaDisponible
        self.orbitaFuente = orbitaFuente
        self.mrr = mrr
        self.enlace = enlace
    }
}

/// Qué tan fresco es un dato: de eso depende cómo se pinta la fecha (callada, avisando o en alerta).
public enum Frescura: Equatable, Sendable {
    case vigente, vieja, muyVieja

    /// Hasta 2 días es vigente; hasta 30, vieja; más, muy vieja.
    public static func de(dias: Int) -> Frescura { dias <= 2 ? .vigente : (dias <= 30 ? .vieja : .muyVieja) }
}

public enum FinanzasCentro {
    public static func decodificar(_ datos: Data) -> Finanzas? {
        guard let d = LecturaJSON.objeto(datos), let version = LecturaJSON.entero(d["version"]), version >= 1, d["disponible"] != nil else { return nil }
        let r = d["resumen"] as? [String: Any]
        let flujo = d["flujo"] as? [String: Any] ?? [:]
        let proy = d["proyeccion_personal"] as? [String: Any] ?? [:]
        let xp = d["orbita"] as? [String: Any] ?? [:]
        func fuente(_ x: Any?) -> FuenteFechada? {
            guard let f = x as? [String: Any], let dias = LecturaJSON.entero(f["dias"]) else { return nil }
            return FuenteFechada(fecha: LecturaJSON.dia(LecturaJSON.texto(f["fecha"])), dias: dias)
        }
        func num(_ x: [String: Any]?, _ k: String) -> Double? { x.flatMap { LecturaJSON.decimal($0[k]) } }
        let pagos: [PagoProximo] = (d["pagos"] as? [[String: Any]] ?? []).compactMap { x in
            guard let c = LecturaJSON.texto(x["concepto"]), let m = LecturaJSON.decimal(x["monto"]) else { return nil }
            return PagoProximo(concepto: c, monto: m, vence: LecturaJSON.dia(LecturaJSON.texto(x["vence"])), dias: LecturaJSON.entero(x["dias"]),
                               critico: LecturaJSON.booleano(x["critico"]) ?? false)
        }
        let meses: [MesFinanzas] = (d["historico"] as? [[String: Any]] ?? []).compactMap { x in
            guard let m = LecturaJSON.texto(x["mes"]), let i = LecturaJSON.decimal(x["ingreso"]), let e = LecturaJSON.decimal(x["egreso"]) else { return nil }
            return MesFinanzas(mes: m, ingreso: i, egreso: e, neto: LecturaJSON.decimal(x["neto"]) ?? i - e)
        }
        return Finanzas(
            disponible: LecturaJSON.booleano(d["disponible"]) ?? false, actualizado: LecturaJSON.dia(LecturaJSON.texto(r?["actualizado"])),
            diasSinActualizar: LecturaJSON.entero(r?["dias_sin_actualizar"]), patrimonio: num(r, "patrimonio"), delta: num(r, "delta"), liquidez: num(r, "liquidez"),
            netoMes: num(flujo, "neto_mes") ?? num(r, "neto_mes"), ingresoMes: num(flujo, "ingreso_mes"), egresoMes: num(flujo, "egreso_mes"),
            colchon: num(r, "colchon"), colchonPiso: num(r, "colchon_piso"), colchonMeta: num(r, "colchon_meta"),
            alertas: (r?["alertas"] as? [Any] ?? []).compactMap(LecturaJSON.texto), historico: meses, pagos: pagos,
            proyeccionDisponible: LecturaJSON.booleano(proy["disponible"]) ?? false, proyeccionFuente: fuente(proy["fuente"]), caja: num(proy, "caja_cop"),
            burn: num(proy, "burn_mes_cop"), runwayMeses: num(proy, "runway_meses") ?? num(flujo, "runway"),
            orbitaDisponible: LecturaJSON.booleano(xp["disponible"]) ?? false, orbitaFuente: fuente(xp["fuente"]), mrr: num(xp, "mrr_cop"),
            enlace: LecturaJSON.texto(r?["enlace"]))
    }

    // MARK: Formato

    /// Pesos en millones: "$ 117 M" (sin decimales si pasa de 100), "$ 10,6 M"; menos de un millón, en miles: "$ 573 k".
    public static func pesos(_ v: Double) -> String {
        let signo = v < 0 ? "−" : ""
        let a = abs(v)
        if a >= 1_000_000 {
            let m = a / 1_000_000
            let t = m >= 100 ? "\(Int(m.rounded()))" : String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",")
            return "\(signo)$ \(t) M"
        }
        if a >= 1_000 { return "\(signo)$ \(Int((a / 1_000).rounded())) k" }
        return "\(signo)$ \(Int(a.rounded()))"
    }

    /// Pesos completos con puntos de miles: "$ 572.436".
    public static func pesosCompletos(_ v: Double) -> String {
        let n = Int(abs(v).rounded())
        var grupos = ""
        for (i, c) in String(n).reversed().enumerated() {
            if i > 0, i % 3 == 0 { grupos.append(".") }
            grupos.append(c)
        }
        return (v < 0 ? "−" : "") + "$ " + String(grupos.reversed())
    }

    /// El texto de la edad de una fuente: "de hoy", "de ayer", "de hace 133 días (6 jul)".
    public static func edad(_ f: FuenteFechada, calendario: Calendar = .current) -> String {
        switch f.dias {
        case 0: return "de hoy"
        case 1: return "de ayer"
        default: return "de hace \(f.dias) días" + (f.fecha.map { " (\(TextoTiempo.diaCorto($0, calendario: calendario)))" } ?? "")
        }
    }

    /// La fracción (0 a 1) del colchón sobre su meta, y la del piso, para la regla. nil si falta la meta.
    public static func regla(actual: Double?, piso: Double?, meta: Double?) -> (actual: Double, piso: Double?)? {
        guard let actual, let meta, meta > 0 else { return nil }
        return (min(1, max(0, actual / meta)), piso.map { min(1, max(0, $0 / meta)) })
    }

    /// El alto de cada barra de los últimos meses (fracción del mayor valor entre ingresos y egresos).
    public static func escalaMeses(_ m: [MesFinanzas]) -> Double {
        max(1, m.flatMap { [$0.ingreso, $0.egreso] }.max() ?? 1)
    }

    /// "nov" para "2026-11".
    public static func nombreMes(_ mes: String) -> String {
        let p = mes.split(separator: "-")
        guard p.count == 2, let n = Int(p[1]), (1...12).contains(n) else { return mes }
        return NombresFecha.mesesCortos[n - 1].lowercased()
    }
}
