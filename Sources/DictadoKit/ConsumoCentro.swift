import Foundation

// La sección Consumo del Centro (`python3 -m centro consumo --json`): tokens y costo equivalente API por día, modelo y proyecto, de
// Claude Code y de Hermes. Aquí solo va la lectura del JSON y las cuentas que la vista necesita (barras, reparto, tendencia). El costo
// es el equivalente a las tarifas oficiales, no la factura de la suscripción; un modelo fuera de la tabla marca `costoIncompleto` en
// vez de inventar una cifra.

public struct CifrasConsumo: Equatable, Sendable {
    public var mensajes = 0
    public var entrada = 0
    public var salida = 0
    public var cacheLectura = 0
    public var cacheEscritura = 0
    public var tokens = 0
    public var costoUSD = 0.0
    public var costoIncompleto = false

    public init(mensajes: Int = 0, entrada: Int = 0, salida: Int = 0, cacheLectura: Int = 0, cacheEscritura: Int = 0, tokens: Int? = nil,
                costoUSD: Double = 0, costoIncompleto: Bool = false) {
        self.mensajes = mensajes
        self.entrada = entrada
        self.salida = salida
        self.cacheLectura = cacheLectura
        self.cacheEscritura = cacheEscritura
        self.tokens = tokens ?? (entrada + salida + cacheLectura + cacheEscritura)
        self.costoUSD = costoUSD
        self.costoIncompleto = costoIncompleto
    }

    /// ¿Hubo algo? (Un día sin mensajes no se dibuja como una barra.)
    public var vacia: Bool { mensajes == 0 && tokens == 0 }
}

public struct DiaConsumo: Equatable, Sendable, Identifiable {
    /// "AAAA-MM-DD", en la zona del centro.
    public var dia: String
    public var cifras: CifrasConsumo
    public var id: String { dia }

    public init(dia: String, cifras: CifrasConsumo) {
        self.dia = dia
        self.cifras = cifras
    }
}

public struct ItemConsumo: Equatable, Sendable, Identifiable {
    public var nombre: String
    public var cifras: CifrasConsumo
    public var id: String { nombre }

    public init(nombre: String, cifras: CifrasConsumo) {
        self.nombre = nombre
        self.cifras = cifras
    }
}

public struct FuenteConsumo: Equatable, Sendable {
    public var disponible: Bool
    public var primerDia: String?
    public var dias: [DiaConsumo]
    public var modelos: [ItemConsumo]
    public var proyectos: [ItemConsumo]
    public var hoy: CifrasConsumo
    public var ayer: CifrasConsumo?
    public var sieteDias: CifrasConsumo
    public var treintaDias: CifrasConsumo
    public var fuente: String
    public var costoFuente: String?
    public var leido: Date?
    public var desactualizado: Bool
    /// Por qué no hay datos (la sección lo dice en una línea).
    public var motivo: String?
    public var incluyeSubagentes: Bool

    public init(disponible: Bool = false, primerDia: String? = nil, dias: [DiaConsumo] = [], modelos: [ItemConsumo] = [], proyectos: [ItemConsumo] = [],
                hoy: CifrasConsumo = CifrasConsumo(), ayer: CifrasConsumo? = nil, sieteDias: CifrasConsumo = CifrasConsumo(),
                treintaDias: CifrasConsumo = CifrasConsumo(), fuente: String = "", costoFuente: String? = nil, leido: Date? = nil,
                desactualizado: Bool = false, motivo: String? = nil, incluyeSubagentes: Bool = false) {
        self.disponible = disponible
        self.primerDia = primerDia
        self.dias = dias
        self.modelos = modelos
        self.proyectos = proyectos
        self.hoy = hoy
        self.ayer = ayer
        self.sieteDias = sieteDias
        self.treintaDias = treintaDias
        self.fuente = fuente
        self.costoFuente = costoFuente
        self.leido = leido
        self.desactualizado = desactualizado
        self.motivo = motivo
        self.incluyeSubagentes = incluyeSubagentes
    }
}

public struct Consumo: Equatable, Sendable {
    public var version: Int
    public var generado: Date?
    public var pricingVersion: String?
    /// false si el indexado no alcanzó a leer todo (se completa en la próxima lectura).
    public var completo: Bool
    public var pendientes: Int
    public var claudeCode: FuenteConsumo
    public var hermes: FuenteConsumo

    public init(version: Int = 1, generado: Date? = nil, pricingVersion: String? = nil, completo: Bool = true, pendientes: Int = 0,
                claudeCode: FuenteConsumo = FuenteConsumo(), hermes: FuenteConsumo = FuenteConsumo()) {
        self.version = version
        self.generado = generado
        self.pricingVersion = pricingVersion
        self.completo = completo
        self.pendientes = pendientes
        self.claudeCode = claudeCode
        self.hermes = hermes
    }
}

public enum ConsumoCentro {
    public enum Medida: Sendable { case costo, tokens }

    // MARK: Lectura

    /// Lee lo que imprime `python3 -m centro consumo --json`. nil si no es un objeto con las dos fuentes (un rechazo `{"ok": false}`, texto
    /// suelto). Un día o un modelo mal formado se salta y los demás siguen.
    public static func decodificar(_ datos: Data) -> Consumo? {
        guard let d = LecturaJSON.objeto(datos), let version = LecturaJSON.entero(d["version"]), version >= 1,
              let cc = d["claude_code"] as? [String: Any], let h = d["hermes"] as? [String: Any] else { return nil }
        return Consumo(version: version, generado: LecturaJSON.fecha(d["generado"]), pricingVersion: LecturaJSON.texto(d["pricing_version"]),
                       completo: LecturaJSON.booleano(d["completo"]) ?? true, pendientes: LecturaJSON.entero(d["pendientes"]) ?? 0,
                       claudeCode: fuente(cc), hermes: fuente(h))
    }

    static func cifras(_ d: [String: Any]) -> CifrasConsumo {
        CifrasConsumo(mensajes: LecturaJSON.entero(d["mensajes"]) ?? 0, entrada: LecturaJSON.entero(d["entrada"]) ?? 0,
                      salida: LecturaJSON.entero(d["salida"]) ?? 0, cacheLectura: LecturaJSON.entero(d["cache_lectura"]) ?? 0,
                      cacheEscritura: LecturaJSON.entero(d["cache_escritura"]) ?? 0, tokens: LecturaJSON.entero(d["tokens"]),
                      costoUSD: LecturaJSON.decimal(d["costo_usd"]) ?? 0, costoIncompleto: LecturaJSON.booleano(d["costo_incompleto"]) ?? false)
    }

    private static func fuente(_ d: [String: Any]) -> FuenteConsumo {
        let t = d["totales"] as? [String: Any] ?? [:]
        func total(_ k: String) -> CifrasConsumo? { (t[k] as? [String: Any]).map(cifras) }
        let dias: [DiaConsumo] = (d["dias"] as? [[String: Any]] ?? []).compactMap { x in
            guard let dia = LecturaJSON.texto(x["dia"]) else { return nil }
            return DiaConsumo(dia: dia, cifras: cifras(x))
        }
        func items(_ clave: String, _ nombre: String) -> [ItemConsumo] {
            (d[clave] as? [[String: Any]] ?? []).compactMap { x in
                guard let n = LecturaJSON.texto(x[nombre]) else { return nil }
                return ItemConsumo(nombre: n, cifras: cifras(x))
            }
        }
        return FuenteConsumo(disponible: LecturaJSON.booleano(d["disponible"]) ?? false, primerDia: LecturaJSON.texto(d["primer_dia"]), dias: dias,
                             modelos: items("modelos", "modelo"), proyectos: items("proyectos", "proyecto"), hoy: total("hoy") ?? CifrasConsumo(),
                             ayer: total("ayer"), sieteDias: total("siete_dias") ?? CifrasConsumo(), treintaDias: total("treinta_dias") ?? CifrasConsumo(),
                             fuente: LecturaJSON.texto(d["fuente"]) ?? "", costoFuente: LecturaJSON.texto(d["costo_fuente"]),
                             leido: LecturaJSON.fecha(d["leido"]), desactualizado: LecturaJSON.booleano(d["desactualizado"]) ?? false,
                             motivo: LecturaJSON.texto(d["motivo"]), incluyeSubagentes: LecturaJSON.booleano(d["incluye_subagentes"]) ?? false)
    }

    // MARK: Cuentas para las gráficas

    public static func valor(_ c: CifrasConsumo, _ m: Medida) -> Double { m == .costo ? c.costoUSD : Double(c.tokens) }

    /// El alto de cada barra como fracción (0 a 1) del día más alto. Un día sin nada es 0; uno con algo nunca baja de `minimo` para
    /// que se vea. Si ningún día tiene datos, todo es 0.
    public static func fracciones(_ dias: [DiaConsumo], por m: Medida, minimo: Double = 0.03) -> [Double] {
        let mayor = dias.map { valor($0.cifras, m) }.max() ?? 0
        guard mayor > 0 else { return dias.map { _ in 0 } }
        return dias.map { d in
            let v = valor(d.cifras, m)
            return v <= 0 ? 0 : max(minimo, v / mayor)
        }
    }

    /// Deja a lo más `maximo` filas: las primeras `maximo - 1` y, si sobran, una sola "Otros" con la suma del resto (incluido un "Otros" que ya
    /// viniera del centro). El orden de entrada se respeta.
    public static func agrupar(_ items: [ItemConsumo], maximo: Int) -> [ItemConsumo] {
        let propios = items.filter { $0.nombre != "Otros" }
        let otros = items.filter { $0.nombre == "Otros" }
        guard propios.count + (otros.isEmpty ? 0 : 1) > maximo, maximo >= 2 else { return items }
        let resto = Array(propios.dropFirst(maximo - 1)) + otros
        var suma = CifrasConsumo()
        for r in resto {
            suma.mensajes += r.cifras.mensajes
            suma.entrada += r.cifras.entrada
            suma.salida += r.cifras.salida
            suma.cacheLectura += r.cifras.cacheLectura
            suma.cacheEscritura += r.cifras.cacheEscritura
            suma.tokens += r.cifras.tokens
            suma.costoUSD += r.cifras.costoUSD
            suma.costoIncompleto = suma.costoIncompleto || r.cifras.costoIncompleto
        }
        return Array(propios.prefix(maximo - 1)) + [ItemConsumo(nombre: "Otros", cifras: suma)]
    }

    /// El día más alto (nil si ninguno tiene datos).
    public static func diaMasAlto(_ dias: [DiaConsumo], por m: Medida) -> DiaConsumo? {
        let con = dias.filter { valor($0.cifras, m) > 0 }
        return con.max { valor($0.cifras, m) < valor($1.cifras, m) }
    }

    /// La parte de cada elemento sobre el total (suman 1). Vacío si no hay nada.
    public static func reparto(_ items: [ItemConsumo], por m: Medida) -> [(item: ItemConsumo, fraccion: Double)] {
        let total = items.reduce(0) { $0 + valor($1.cifras, m) }
        guard total > 0 else { return [] }
        return items.map { ($0, valor($0.cifras, m) / total) }
    }

    /// Lo que cambió la última semana frente a la anterior (0,25 = 25 % más). nil si no hay 14 días o la anterior fue cero.
    public static func variacionSemanal(_ dias: [DiaConsumo], por m: Medida) -> Double? {
        guard dias.count >= 14 else { return nil }
        let ultima = dias.suffix(7).reduce(0) { $0 + valor($1.cifras, m) }
        let previa = dias.dropLast(7).suffix(7).reduce(0) { $0 + valor($1.cifras, m) }
        guard previa > 0 else { return nil }
        return (ultima - previa) / previa
    }

    /// El promedio de los últimos `n` días que tuvieron datos (un día sin nada no baja el promedio). nil si ninguno.
    public static func promedioDiario(_ dias: [DiaConsumo], ultimos n: Int = 7, por m: Medida) -> Double? {
        let con = dias.suffix(n).filter { valor($0.cifras, m) > 0 }
        guard !con.isEmpty else { return nil }
        return con.reduce(0) { $0 + valor($1.cifras, m) } / Double(con.count)
    }

    /// "+25 %" / "−8 %" / "igual".
    public static func textoVariacion(_ v: Double) -> String {
        let p = Int((v * 100).rounded())
        return p == 0 ? "igual" : (p > 0 ? "+\(p) %" : "−\(-p) %")
    }

    /// La etiqueta de un día de la gráfica: "lun 16".
    public static func etiqueta(dia: String, calendario: Calendar = .current) -> String {
        guard let f = LecturaJSON.dia(dia, calendario: calendario) else { return dia }
        return TextoTiempo.diaSemana(f, calendario: calendario)
    }

    /// El costo en una línea ("US$ 39,17"), con "+" si faltan modelos sin tarifa conocida.
    public static func textoCosto(_ c: CifrasConsumo) -> String {
        "US$ " + HistorialCentro.costo(c.costoUSD).numero + (c.costoIncompleto ? "+" : "")
    }
}
