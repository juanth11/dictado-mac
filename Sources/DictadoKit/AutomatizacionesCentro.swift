import Foundation

// La sección Automatizaciones del Centro (`python3 -m centro automatizaciones --json`): todo lo programado (LaunchAgents, crontab, tareas
// de Claude, trabajos y cron de Hermes en el VPS, feeders, agentes del Tablero) con qué hace, cuándo corre, su última corrida, el
// resultado y, si lleva días sin correr, desde cuándo está parado. Solo lectura.

public enum EstadoAutomatizacion: String, Sendable, CaseIterable {
    case fallo, parado, atrasado, alDia = "al_dia", sinDato = "sin_dato", apagado

    public var texto: String {
        switch self {
        case .fallo: return "Falló"
        case .parado: return "Parado"
        case .atrasado: return "Atrasado"
        case .alDia: return "Al día"
        case .sinDato: return "Sin dato"
        case .apagado: return "Apagado"
        }
    }

    /// Lo que pide mirar.
    public var pideAtencion: Bool { self == .fallo || self == .parado || self == .atrasado }
}

public struct ItemAutomatizacion: Equatable, Sendable, Identifiable {
    public var id: String
    /// launchagent, crontab, claude, hermes, vps-cron, feeders, tablero.
    public var origen: String
    public var nombre: String
    public var queHace: String
    public var horario: String
    public var activo: Bool
    public var ultima: Date?
    public var proxima: Date?
    public var resultado: String
    public var detalle: String
    public var estado: EstadoAutomatizacion
    public var paradoDesde: Date?
    public var diasParado: Int?
    /// false para lo de terceros (Google, Steam…).
    public var propio: Bool

    public init(id: String, origen: String, nombre: String, queHace: String = "", horario: String = "", activo: Bool = true, ultima: Date? = nil,
                proxima: Date? = nil, resultado: String = "sin_dato", detalle: String = "", estado: EstadoAutomatizacion = .sinDato, paradoDesde: Date? = nil,
                diasParado: Int? = nil, propio: Bool = true) {
        self.id = id
        self.origen = origen
        self.nombre = nombre
        self.queHace = queHace
        self.horario = horario
        self.activo = activo
        self.ultima = ultima
        self.proxima = proxima
        self.resultado = resultado
        self.detalle = detalle
        self.estado = estado
        self.paradoDesde = paradoDesde
        self.diasParado = diasParado
        self.propio = propio
    }
}

public struct FuenteAutomatizacion: Equatable, Sendable, Identifiable {
    public var id: String
    public var nombre: String
    public var total: Int
    /// Por qué está vacía ("sin entradas en el crontab").
    public var nota: String

    public init(id: String, nombre: String, total: Int, nota: String = "") {
        self.id = id
        self.nombre = nombre
        self.total = total
        self.nota = nota
    }
}

public struct ResumenAutomatizaciones: Equatable, Sendable {
    public var total = 0
    public var fallo = 0, parado = 0, atrasado = 0, alDia = 0, sinDato = 0, apagado = 0

    public init(total: Int = 0, fallo: Int = 0, parado: Int = 0, atrasado: Int = 0, alDia: Int = 0, sinDato: Int = 0, apagado: Int = 0) {
        self.total = total
        self.fallo = fallo
        self.parado = parado
        self.atrasado = atrasado
        self.alDia = alDia
        self.sinDato = sinDato
        self.apagado = apagado
    }

    public var pidenAtencion: Int { fallo + parado + atrasado }
}

public struct Automatizaciones: Equatable, Sendable {
    public var generado: Date?
    public var resumen: ResumenAutomatizaciones
    public var fuentes: [FuenteAutomatizacion]
    public var items: [ItemAutomatizacion]
    public var vpsLeido: Date?
    public var vpsDesactualizado: Bool
    public var vpsError: String?

    public init(generado: Date? = nil, resumen: ResumenAutomatizaciones = ResumenAutomatizaciones(), fuentes: [FuenteAutomatizacion] = [],
                items: [ItemAutomatizacion] = [], vpsLeido: Date? = nil, vpsDesactualizado: Bool = false, vpsError: String? = nil) {
        self.generado = generado
        self.resumen = resumen
        self.fuentes = fuentes
        self.items = items
        self.vpsLeido = vpsLeido
        self.vpsDesactualizado = vpsDesactualizado
        self.vpsError = vpsError
    }
}

public enum AutomatizacionesCentro {
    public static func decodificar(_ datos: Data) -> Automatizaciones? {
        guard let d = LecturaJSON.objeto(datos), let version = LecturaJSON.entero(d["version"]), version >= 1, d["items"] is [Any] else { return nil }
        let items: [ItemAutomatizacion] = (d["items"] as? [[String: Any]] ?? []).compactMap { x in
            guard let id = LecturaJSON.texto(x["id"]), let nombre = LecturaJSON.texto(x["nombre"]) else { return nil }
            return ItemAutomatizacion(
                id: id, origen: LecturaJSON.texto(x["origen"]) ?? "", nombre: nombre, queHace: LecturaJSON.texto(x["que_hace"]) ?? "",
                horario: LecturaJSON.texto(x["horario"]) ?? "", activo: LecturaJSON.booleano(x["activo"]) ?? true, ultima: LecturaJSON.fecha(x["ultima"]),
                proxima: LecturaJSON.fecha(x["proxima"]), resultado: LecturaJSON.texto(x["resultado"]) ?? "sin_dato", detalle: LecturaJSON.texto(x["detalle"]) ?? "",
                estado: LecturaJSON.texto(x["estado"]).flatMap(EstadoAutomatizacion.init(rawValue:)) ?? .sinDato, paradoDesde: LecturaJSON.fecha(x["parado_desde"]),
                diasParado: LecturaJSON.entero(x["dias_parado"]), propio: LecturaJSON.booleano(x["propio"]) ?? true)
        }
        let r = d["resumen"] as? [String: Any] ?? [:]
        let vps = d["vps"] as? [String: Any] ?? [:]
        return Automatizaciones(
            generado: LecturaJSON.fecha(d["generado"]),
            resumen: ResumenAutomatizaciones(total: LecturaJSON.entero(r["total"]) ?? items.count, fallo: LecturaJSON.entero(r["fallo"]) ?? 0,
                                             parado: LecturaJSON.entero(r["parado"]) ?? 0, atrasado: LecturaJSON.entero(r["atrasado"]) ?? 0,
                                             alDia: LecturaJSON.entero(r["al_dia"]) ?? 0, sinDato: LecturaJSON.entero(r["sin_dato"]) ?? 0,
                                             apagado: LecturaJSON.entero(r["apagado"]) ?? 0),
            fuentes: (d["fuentes"] as? [[String: Any]] ?? []).compactMap { x in
                guard let id = LecturaJSON.texto(x["id"]), let n = LecturaJSON.texto(x["nombre"]) else { return nil }
                return FuenteAutomatizacion(id: id, nombre: n, total: LecturaJSON.entero(x["total"]) ?? 0, nota: LecturaJSON.texto(x["nota"]) ?? "")
            },
            items: items, vpsLeido: LecturaJSON.fecha(vps["leido"]), vpsDesactualizado: LecturaJSON.booleano(vps["desactualizado"]) ?? false,
            vpsError: LecturaJSON.texto(vps["error"]))
    }

    // MARK: Textos

    /// "Parado desde el 6 jul · hace 133 días" para lo parado o atrasado; "En pausa desde el 7 sep" para lo apagado con fecha; nil si no aplica.
    public static func textoParado(_ i: ItemAutomatizacion, ahora: Date, calendario: Calendar = .current) -> String? {
        guard let desde = i.paradoDesde else { return nil }
        let dia = TextoTiempo.diaCorto(desde, calendario: calendario)
        let dias = i.diasParado.map { $0 == 1 ? "hace 1 día" : "hace \($0) días" } ?? TextoTiempo.hace(desde, ahora)
        switch i.estado {
        case .parado: return "Parado desde el \(dia) · \(dias)"
        case .atrasado: return "Se saltó una corrida · la última fue el \(dia)"
        case .apagado: return "Apagado desde el \(dia)"
        default: return nil
        }
    }

    /// "ayer 05:30", "hoy 07:00", "16 nov 12:36" o "sin dato".
    public static func textoMomento(_ f: Date?, ahora: Date, calendario: Calendar = .current) -> String {
        guard let f else { return "sin dato" }
        let hora = TextoTiempo.hora(f, calendario: calendario)
        if calendario.isDate(f, inSameDayAs: ahora) { return "hoy \(hora)" }
        if let ayer = calendario.date(byAdding: .day, value: -1, to: ahora), calendario.isDate(f, inSameDayAs: ayer) { return "ayer \(hora)" }
        if let manana = calendario.date(byAdding: .day, value: 1, to: ahora), calendario.isDate(f, inSameDayAs: manana) { return "mañana \(hora)" }
        return "\(TextoTiempo.diaCorto(f, calendario: calendario)) \(hora)"
    }

    /// El nombre de dónde corre, para el rótulo de la fila.
    public static func lugar(_ origen: String) -> String {
        switch origen {
        case "launchagent": return "Mac · LaunchAgent"
        case "crontab": return "Mac · crontab"
        case "claude": return "Mac · tarea de Claude"
        case "feeders": return "Mac · feeders"
        case "tablero": return "Mac · Tablero"
        case "hermes": return "VPS · Hermes"
        case "vps-cron": return "VPS · cron"
        default: return origen
        }
    }

    /// Lo que pide mirar (falló, parado, atrasado), luego lo propio al día, luego lo demás, y al final lo apagado y lo de terceros.
    public static func grupos(_ items: [ItemAutomatizacion]) -> (atencion: [ItemAutomatizacion], activos: [ItemAutomatizacion], apagados: [ItemAutomatizacion]) {
        (items.filter { $0.estado.pideAtencion }, items.filter { !$0.estado.pideAtencion && $0.estado != .apagado }, items.filter { $0.estado == .apagado })
    }

    /// "3 piden atención · 16 al día · 16 apagados"; "Todo al día" si nada pide atención.
    public static func frase(_ r: ResumenAutomatizaciones) -> String {
        var partes: [String] = []
        if r.pidenAtencion > 0 { partes.append(r.pidenAtencion == 1 ? "1 pide atención" : "\(r.pidenAtencion) piden atención") }
        if r.alDia > 0 { partes.append("\(r.alDia) al día") }
        if r.sinDato > 0 { partes.append("\(r.sinDato) sin dato") }
        if r.apagado > 0 { partes.append(r.apagado == 1 ? "1 apagado" : "\(r.apagado) apagados") }
        return partes.isEmpty ? "Nada programado" : partes.joined(separator: " · ")
    }
}
