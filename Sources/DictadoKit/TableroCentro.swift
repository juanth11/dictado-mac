import Foundation

// El Tablero del centro (`python3 -m centro tablero --json`): el registro único del trabajo de los agentes. Aquí solo va la
// lectura del JSON versionado (tolerante a claves nuevas y a una `version` mayor que 1) y las cuentas y frases que de ahí salen.

/// Una decisión abierta: una pregunta de un agente que espera tu respuesta.
public struct DecisionTablero: Equatable, Sendable, Identifiable {
    public var id: Int
    public var encargoID: Int?
    public var corridaID: Int?
    public var pregunta: String
    /// Vacío = Sí / No.
    public var opciones: [String]
    public var encargoTitulo: String?
    public var creada: String?

    public init(id: Int, encargoID: Int? = nil, corridaID: Int? = nil, pregunta: String, opciones: [String] = [], encargoTitulo: String? = nil,
                creada: String? = nil) {
        self.id = id
        self.encargoID = encargoID
        self.corridaID = corridaID
        self.pregunta = pregunta
        self.opciones = opciones
        self.encargoTitulo = encargoTitulo
        self.creada = creada
    }

    /// Los botones de la tarjeta: las opciones, o Sí / No si no hay ninguna.
    public var respuestasPosibles: [String] { opciones.isEmpty ? ["Sí", "No"] : opciones }
}

/// Una corrida: un agente trabajando (o que trabajó) en algo.
public struct CorridaTablero: Equatable, Sendable, Identifiable {
    public enum Estado: String, Sendable { case trabajando, espera, termino, fallo }

    public var id: Int
    public var encargoID: Int?
    public var agente: String
    public var sesion: String?
    public var proyecto: String?
    public var titulo: String
    /// ISO 8601 con zona.
    public var inicio: Date?
    public var fin: Date?
    public var estado: Estado
    public var resumen: String?
    public var enlace: URL?
    public var tokensEntrada: Int?
    public var tokensSalida: Int?
    public var modelo: String?
    /// Equivalente API a tarifas oficiales; nil si el modelo no está en la tabla. No es la factura de la suscripción.
    public var costoUSD: Double?

    public init(id: Int, encargoID: Int? = nil, agente: String = "claude-code", sesion: String? = nil, proyecto: String? = nil, titulo: String,
                inicio: Date? = nil, fin: Date? = nil, estado: Estado = .trabajando, resumen: String? = nil, enlace: URL? = nil,
                tokensEntrada: Int? = nil, tokensSalida: Int? = nil, modelo: String? = nil, costoUSD: Double? = nil) {
        self.id = id
        self.encargoID = encargoID
        self.agente = agente
        self.sesion = sesion
        self.proyecto = proyecto
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.estado = estado
        self.resumen = resumen
        self.enlace = enlace
        self.tokensEntrada = tokensEntrada
        self.tokensSalida = tokensSalida
        self.modelo = modelo
        self.costoUSD = costoUSD
    }

    public var tokens: Int? {
        if tokensEntrada == nil && tokensSalida == nil { return nil }
        return (tokensEntrada ?? 0) + (tokensSalida ?? 0)
    }
}

/// Un encargo recién creado (la respuesta de `encargo nuevo --json`): lo que la tarjeta pendiente necesita.
public struct EncargoTablero: Equatable, Sendable, Identifiable {
    public var id: Int
    public var titulo: String
    public var estado: String
    public var nuevo: Bool

    public init(id: Int, titulo: String, estado: String = "pendiente", nuevo: Bool = true) {
        self.id = id
        self.titulo = titulo
        self.estado = estado
        self.nuevo = nuevo
    }
}

public struct ConteosTablero: Equatable, Sendable {
    public var trabajando = 0
    public var esperanTuSi = 0
    public var terminaronHoy = 0
    public var terminaronAnoche = 0

    public init(trabajando: Int = 0, esperanTuSi: Int = 0, terminaronHoy: Int = 0, terminaronAnoche: Int = 0) {
        self.trabajando = trabajando
        self.esperanTuSi = esperanTuSi
        self.terminaronHoy = terminaronHoy
        self.terminaronAnoche = terminaronAnoche
    }
}

public struct Tablero: Equatable, Sendable {
    public var version: Int
    public var generado: Date?
    public var estado: String
    public var conteos: ConteosTablero
    public var decisiones: [DecisionTablero]
    public var enCurso: [CorridaTablero]
    public var ultimas: [CorridaTablero]

    public init(version: Int = 1, generado: Date? = nil, estado: String = "ok", conteos: ConteosTablero = ConteosTablero(),
                decisiones: [DecisionTablero] = [], enCurso: [CorridaTablero] = [], ultimas: [CorridaTablero] = []) {
        self.version = version
        self.generado = generado
        self.estado = estado
        self.conteos = conteos
        self.decisiones = decisiones
        self.enCurso = enCurso
        self.ultimas = ultimas
    }

    /// Lo que trabaja y lo que espera tu sí: de los conteos del centro; si no vinieron, de las listas.
    public var trabajando: Int { conteos.trabajando }
    public var esperan: Int { conteos.esperanTuSi }
}

public enum TableroCentro {
    /// La versión del contrato que esta app entiende por completo. Una mayor se lee igual (solo se agregan claves), pero se anota.
    public static let versionConocida = 1

    // MARK: Lectura

    /// Lee lo que imprime `python3 -m centro tablero --json`. nil si no es un objeto con la forma del tablero (un rechazo
    /// `{"ok": false}`, texto suelto, una lista). Una clave nueva se ignora; una corrida o decisión mal formada se salta y las demás siguen.
    public static func decodificar(_ datos: Data) -> Tablero? {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let d = crudo as? [String: Any] else { return nil }
        if d["ok"] as? Bool == false { return nil }
        guard let version = entero(d["version"]), version >= 1 else { return nil }
        guard d["conteos"] is [String: Any] || d["en_curso"] is [Any] || d["decisiones"] is [Any] else { return nil }

        let c = d["conteos"] as? [String: Any] ?? [:]
        let enCurso = (d["en_curso"] as? [[String: Any]] ?? []).compactMap(corrida)
        let decisiones = (d["decisiones"] as? [[String: Any]] ?? []).compactMap(decision)
        let conteos = ConteosTablero(trabajando: entero(c["trabajando"]) ?? enCurso.filter { $0.estado == .trabajando }.count,
                                     esperanTuSi: entero(c["esperan_tu_si"]) ?? decisiones.count,
                                     terminaronHoy: entero(c["terminaron_hoy"]) ?? 0,
                                     terminaronAnoche: entero(c["terminaron_anoche"]) ?? 0)
        return Tablero(version: version, generado: fecha(d["generado"] as? String), estado: texto(d["estado"]) ?? "ok", conteos: conteos,
                       decisiones: decisiones, enCurso: enCurso, ultimas: (d["ultimas"] as? [[String: Any]] ?? []).compactMap(corrida))
    }

    /// Lo que imprime `corrida listar --estado todas --limite N --json`: una lista de corridas (el historial). nil si no es una lista
    /// (un rechazo `{"ok": false}`, texto suelto); una corrida mal formada se salta y las demás siguen.
    public static func decodificarCorridas(_ datos: Data) -> [CorridaTablero]? {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let lista = crudo as? [[String: Any]] else { return nil }
        return lista.compactMap(corrida)
    }

    /// La respuesta de `encargo nuevo … --json`: el encargo creado. nil si el centro lo rechazó o no devolvió un encargo.
    public static func decodificarEncargo(_ datos: Data) -> EncargoTablero? {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let d = crudo as? [String: Any], d["ok"] as? Bool != false,
              let id = entero(d["id"]), let titulo = texto(d["titulo"]) else { return nil }
        return EncargoTablero(id: id, titulo: titulo, estado: texto(d["estado"]) ?? "pendiente", nuevo: d["nuevo"] as? Bool ?? true)
    }

    /// ¿Aceptó el centro la orden (`decision responder …`)? Sin `"ok": false` y con algo de salida.
    public static func aceptada(_ datos: Data) -> Bool {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let d = crudo as? [String: Any] else { return false }
        return d["ok"] as? Bool != false
    }

    private static func texto(_ valor: Any?) -> String? {
        guard let t = valor as? String else { return nil }
        let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return limpio.isEmpty ? nil : limpio
    }

    private static func entero(_ valor: Any?) -> Int? {
        if let n = valor as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }

    private static func decimal(_ valor: Any?) -> Double? {
        if let n = valor as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        return nil
    }

    private static func fecha(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime]
        if let d = a.date(from: iso) { return d }
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return a.date(from: iso)
    }

    private static func corrida(_ d: [String: Any]) -> CorridaTablero? {
        guard let id = entero(d["id"]), let titulo = texto(d["titulo"]) else { return nil }
        let estado = texto(d["estado"]).flatMap(CorridaTablero.Estado.init(rawValue:)) ?? .trabajando
        return CorridaTablero(id: id, encargoID: entero(d["encargo_id"]), agente: texto(d["agente"]) ?? "agente", sesion: texto(d["sesion"]),
                              proyecto: texto(d["proyecto"]), titulo: titulo, inicio: fecha(d["inicio"] as? String), fin: fecha(d["fin"] as? String),
                              estado: estado, resumen: texto(d["resumen"]), enlace: texto(d["enlace"]).flatMap(enlaceSeguro),
                              tokensEntrada: entero(d["tokens_entrada"]), tokensSalida: entero(d["tokens_salida"]), modelo: texto(d["modelo"]),
                              costoUSD: decimal(d["costo_usd"]))
    }

    private static func decision(_ d: [String: Any]) -> DecisionTablero? {
        guard let id = entero(d["id"]), let pregunta = texto(d["pregunta"]) else { return nil }
        if d["respuesta"] is String, texto(d["respuesta"]) != nil { return nil }   // ya respondida: no es una decisión abierta
        let opciones = (d["opciones"] as? [Any] ?? []).compactMap(texto)
        return DecisionTablero(id: id, encargoID: entero(d["encargo_id"]), corridaID: entero(d["corrida_id"]), pregunta: pregunta, opciones: opciones,
                               encargoTitulo: texto(d["encargo_titulo"]), creada: texto(d["creada"]))
    }

    /// Solo enlaces que la app puede abrir sin sorpresas: web o `claude://`.
    public static func enlaceSeguro(_ texto: String) -> URL? {
        guard let url = URL(string: texto), let esquema = url.scheme?.lowercased(), ["https", "http", "claude"].contains(esquema) else { return nil }
        return url
    }

    // MARK: Cuentas y frases

    /// Cuánto tiempo vale una lectura: pasado esto, las vistas que no la refrescan (la isla compacta) vuelven a lo que ven directo.
    public static let vigencia: TimeInterval = 10 * 60
    /// Cada cuánto como mucho se vuelve a pedir.
    public static let frecuencia: TimeInterval = 60

    /// ¿Toca pedir de nuevo? Sí si nunca se pidió o ya pasó la frecuencia.
    public static func tocaPedir(ultima: Date?, ahora: Date, frecuencia: TimeInterval = TableroCentro.frecuencia) -> Bool {
        guard let ultima else { return true }
        return ahora.timeIntervalSince(ultima) >= frecuencia
    }

    /// Lo que trabaja y lo que espera: del Tablero si hay una lectura vigente; si no, de lo que se ve directo (las sesiones de Claude).
    /// `esperanVivas`: lo que espera tu sí y el Tablero no ve (sesiones que piden un permiso, agentes remotos con alerta); se suma a las decisiones.
    public static func cuentas(tablero: Tablero?, leido: Date?, ahora: Date, directoTrabajando: Int, directoEsperan: Int, esperanVivas: Int = 0,
                               vigencia: TimeInterval = TableroCentro.vigencia) -> (trabajando: Int, esperan: Int, deTablero: Bool) {
        if let tablero, let leido, ahora.timeIntervalSince(leido) <= vigencia {
            return (tablero.trabajando, tablero.esperan + esperanVivas, true)
        }
        return (directoTrabajando, directoEsperan, false)
    }

    /// "US$ 0,41 equivalente"; nil si no hay costo (la tarjeta no lo muestra). Menos de un centavo, "menos de US$ 0,01 equivalente".
    public static func costo(_ usd: Double?) -> String? {
        guard let usd, usd.isFinite, usd >= 0 else { return nil }
        if usd > 0 && usd < 0.005 { return "menos de US$ 0,01 equivalente" }
        let centavos = Int((usd * 100).rounded())
        let enteros = centavos / 100
        var grupos = ""
        for (i, c) in String(enteros).reversed().enumerated() {
            if i > 0, i % 3 == 0 { grupos.append(".") }
            grupos.append(c)
        }
        grupos = String(grupos.reversed())
        return "US$ \(grupos),\(String(format: "%02d", centavos % 100)) equivalente"
    }

    /// "1,2 M" / "340 k" / "812": tokens en pocas letras.
    public static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000:
            let k = Double(n) / 1_000
            return k < 10 ? String(format: "%.1f k", k).replacingOccurrences(of: ".", with: ",") : "\(Int(k.rounded())) k"
        default:
            let m = Double(n) / 1_000_000
            return m < 10 ? String(format: "%.1f M", m).replacingOccurrences(of: ".", with: ",") : "\(Int(m.rounded())) M"
        }
    }

    /// "42 min", "2 h 05 min": lo que lleva una corrida en marcha.
    public static func transcurrido(desde inicio: Date?, hasta ahora: Date) -> String? {
        guard let inicio else { return nil }
        let minutos = max(0, Int(ahora.timeIntervalSince(inicio)) / 60)
        if minutos < 60 { return "\(minutos) min" }
        if minutos < 24 * 60 { return String(format: "%d h %02d min", minutos / 60, minutos % 60) }
        return "\(minutos / (24 * 60)) d"
    }

    /// Una corrida que sigue viva en el Mac: su `sesion` coincide con una sesión de Claude Code que la app ve abierta.
    public static func sesionViva(_ corrida: CorridaTablero, entre ids: [String]) -> String? {
        guard let s = corrida.sesion, !s.isEmpty else { return nil }
        return ids.first { $0 == s }
    }

    /// Lo que termina desde anoche, sin repetir lo que sigue en curso, lo más reciente primero. Máximo `limite`.
    public static func terminadas(_ t: Tablero, limite: Int = 6) -> [CorridaTablero] {
        let enCurso = Set(t.enCurso.map(\.id))
        return t.ultimas.filter { ($0.estado == .termino || $0.estado == .fallo) && !enCurso.contains($0.id) }
            .sorted { ($0.fin ?? $0.inicio ?? .distantPast) > ($1.fin ?? $1.inicio ?? .distantPast) }
            .prefix(limite).map { $0 }
    }

    /// El título del encargo que se crea al dictar: las primeras 80 letras (cortando en una palabra si se puede) y, si se cortó, puntos suspensivos.
    public static func tituloDeEncargo(_ texto: String, maximo: Int = 80) -> String {
        let limpio = texto.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard limpio.count > maximo else { return limpio }
        let corte = String(limpio.prefix(maximo))
        let hastaPalabra = corte.lastIndex(of: " ").map { String(corte[..<$0]) } ?? corte
        let base = hastaPalabra.count >= maximo / 2 ? hastaPalabra : corte
        return base.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Los argumentos de `python3 -m centro encargo nuevo …` para un dictado.
    public static func argumentosEncargo(_ texto: String) -> [String] {
        let pedido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["encargo", "nuevo", tituloDeEncargo(pedido), "--pedido", pedido, "--origen", "dictado", "--json"]
    }

    /// Los argumentos de `decision responder ID RESPUESTA --json`.
    public static func argumentosRespuesta(decision: Int, respuesta: String) -> [String] {
        ["decision", "responder", String(decision), respuesta, "--json"]
    }

    /// La rotulación de dónde sale lo que se ve (el rótulo pequeño de la pestaña Agentes).
    public static func rotuloDeFuente(deTablero: Bool) -> String {
        deTablero ? "Tablero del centro" : "Sesiones de Claude (el Tablero no está disponible)"
    }
}
