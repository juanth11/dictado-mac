import Foundation

// El historial del Tablero para el Centro a pantalla completa: las corridas de `corrida listar` agrupadas por día (la última
// semana), las cifras de hoy y las frases del encabezado. Todo es cuenta pura sobre `CorridaTablero`; la app solo trae los datos.
//
// Regla de atribución (una sola, para que las filas sumen lo mismo que las cifras): una corrida cuenta en el día en que terminó
// (`fin`); la que sigue en marcha cuenta hoy y, de su duración, solo lo que pasó desde la medianoche; la que no tiene `fin` ni
// `inicio` no se puede ubicar y se salta.

/// Un tramo de la barra de un día: una corrida, con su ancho como fracción del día más cargado de la semana.
public struct SegmentoBarra: Equatable, Sendable {
    public var corridaID: Int
    public var fraccion: Double
    public var estado: CorridaTablero.Estado
}

public struct DiaHistorial: Equatable, Sendable, Identifiable {
    public var id: Date { dia }
    public var dia: Date
    /// "Hoy", "Ayer" o "dom 15".
    public var etiqueta: String
    /// "15 nov".
    public var fecha: String
    public var esHoy: Bool
    /// Las del día, la más reciente primero.
    public var corridas: [CorridaTablero]
    public var terminaron: Int
    public var fallaron: Int
    public var enMarcha: Int
    /// Tiempo de trabajo de los agentes ese día.
    public var segundos: Double
    /// nil si ninguna corrida del día trae tokens.
    public var tokens: Int?
    /// nil si ninguna corrida del día trae costo.
    public var costoUSD: Double?
    public var barra: [SegmentoBarra]
}

/// Los números de arriba del Tablero. Cada uno es nil si el dato no existe (no hay historial, o ninguna corrida lo trae).
public struct CifrasHoy: Equatable, Sendable {
    public var sesiones: Int?
    public var segundos: Double?
    public var tokens: Int?
    public var costoHoy: Double?
    public var costoSemana: Double?

    public init(sesiones: Int? = nil, segundos: Double? = nil, tokens: Int? = nil, costoHoy: Double? = nil, costoSemana: Double? = nil) {
        self.sesiones = sesiones
        self.segundos = segundos
        self.tokens = tokens
        self.costoHoy = costoHoy
        self.costoSemana = costoSemana
    }
}

public enum HistorialCentro {
    public static let diasPorOmision = 7

    /// El día al que pertenece una corrida; nil si no se puede ubicar.
    static func diaDe(_ c: CorridaTablero, ahora: Date, calendario: Calendar) -> Date? {
        if c.estado == .trabajando || c.estado == .espera { return calendario.startOfDay(for: ahora) }
        guard let f = c.fin ?? c.inicio else { return nil }
        return calendario.startOfDay(for: f)
    }

    /// Cuánto trabajó la corrida para el día en que cuenta: lo que dura; la que sigue en marcha, solo desde la medianoche.
    static func duracion(_ c: CorridaTablero, ahora: Date, calendario: Calendar) -> Double {
        guard let inicio = c.inicio else { return 0 }
        if c.estado == .trabajando || c.estado == .espera {
            return max(0, ahora.timeIntervalSince(max(inicio, calendario.startOfDay(for: ahora))))
        }
        guard let fin = c.fin else { return 0 }
        return max(0, fin.timeIntervalSince(inicio))
    }

    private static func suma(_ valores: [Int?]) -> Int? {
        let conocidos = valores.compactMap { $0 }
        return conocidos.isEmpty ? nil : conocidos.reduce(0, +)
    }

    private static func suma(_ valores: [Double?]) -> Double? {
        let conocidos = valores.compactMap { $0 }
        return conocidos.isEmpty ? nil : conocidos.reduce(0, +)
    }

    /// Los últimos `cuantos` días (hoy primero), cada uno con sus corridas, sus totales y su barra. Siempre devuelve los `cuantos` días,
    /// aunque alguno no tenga nada.
    public static func dias(_ corridas: [CorridaTablero], ahora: Date, cuantos: Int = diasPorOmision, calendario: Calendar = .current) -> [DiaHistorial] {
        let hoy = calendario.startOfDay(for: ahora)
        var porDia: [Date: [CorridaTablero]] = [:]
        for c in corridas {
            guard let d = diaDe(c, ahora: ahora, calendario: calendario) else { continue }
            porDia[d, default: []].append(c)
        }
        func orden(_ c: CorridaTablero) -> Date { c.fin ?? c.inicio ?? .distantPast }
        var armados: [(dia: Date, lista: [CorridaTablero], segundos: [Int: Double])] = []
        for n in 0..<max(1, cuantos) {
            guard let dia = calendario.date(byAdding: .day, value: -n, to: hoy) else { continue }
            let lista = (porDia[dia] ?? []).sorted { (orden($0), $0.id) > (orden($1), $1.id) }
            var segundos: [Int: Double] = [:]
            for c in lista { segundos[c.id] = duracion(c, ahora: ahora, calendario: calendario) }
            armados.append((dia, lista, segundos))
        }
        let mayor = max(1, armados.map { $0.segundos.values.reduce(0, +) }.max() ?? 1)
        return armados.map { a in
            let c = calendario.dateComponents([.weekday, .day, .month], from: a.dia)
            let nombre = NombresFecha.diasCortos[((c.weekday ?? 1) - 1) % 7].lowercased()
            let etiqueta = a.dia == hoy ? "Hoy" : (calendario.date(byAdding: .day, value: -1, to: hoy) == a.dia ? "Ayer" : "\(nombre) \(c.day ?? 0)")
            return DiaHistorial(
                dia: a.dia, etiqueta: etiqueta,
                fecha: "\(c.day ?? 0) \(NombresFecha.mesesCortos[((c.month ?? 1) - 1) % 12].lowercased())", esHoy: a.dia == hoy,
                corridas: a.lista,
                terminaron: a.lista.filter { $0.estado == .termino }.count,
                fallaron: a.lista.filter { $0.estado == .fallo }.count,
                enMarcha: a.lista.filter { $0.estado == .trabajando || $0.estado == .espera }.count,
                segundos: a.segundos.values.reduce(0, +),
                tokens: suma(a.lista.map(\.tokens)),
                costoUSD: suma(a.lista.map(\.costoUSD)),
                barra: a.lista.reversed().map { SegmentoBarra(corridaID: $0.id, fraccion: (a.segundos[$0.id] ?? 0) / mayor, estado: $0.estado) })
        }
    }

    /// Las cifras de hoy y el costo de los últimos 7 días. Sin historial (nil), todo es nil y la tira no muestra nada.
    public static func cifras(_ corridas: [CorridaTablero]?, ahora: Date, calendario: Calendar = .current) -> CifrasHoy {
        guard let corridas else { return CifrasHoy() }
        let semana = dias(corridas, ahora: ahora, cuantos: 7, calendario: calendario)
        let hoy = semana.first
        return CifrasHoy(sesiones: hoy?.corridas.count ?? 0, segundos: hoy?.segundos ?? 0, tokens: hoy?.tokens, costoHoy: hoy?.costoUSD,
                         costoSemana: suma(semana.map(\.costoUSD)))
    }

    // MARK: Lo que terminó

    /// Lo que terminó hoy y desde anoche (las 18:00 de ayer, como el conteo del Tablero), lo más reciente primero. Junta las
    /// `ultimas` del Tablero con el historial (el Tablero solo trae unas diez) sin repetir; lo que sigue en marcha no entra.
    public static func terminadasDesdeAnoche(tablero: Tablero?, historial: [CorridaTablero]?, ahora: Date, calendario: Calendar = .current,
                                              limite: Int = 12) -> [CorridaTablero] {
        guard let anoche = calendario.date(byAdding: .day, value: -1, to: calendario.startOfDay(for: ahora)).flatMap({
            calendario.date(bySettingHour: 18, minute: 0, second: 0, of: $0)
        }) else { return [] }
        var vistas = Set<Int>()
        var lista: [CorridaTablero] = []
        for c in (tablero?.ultimas ?? []) + (historial ?? []) {
            guard c.estado == .termino || c.estado == .fallo, let fin = c.fin, fin >= anoche, vistas.insert(c.id).inserted else { continue }
            lista.append(c)
        }
        let enCurso = Set((tablero?.enCurso ?? []).map(\.id))
        return lista.filter { !enCurso.contains($0.id) }.sorted { ($0.fin ?? .distantPast, $0.id) > ($1.fin ?? .distantPast, $1.id) }.prefix(limite).map { $0 }
    }

    // MARK: Formato

    /// "42" + "min", "3,4" + "h".
    public static func horas(_ segundos: Double) -> (numero: String, unidad: String) {
        let minutos = Int((max(0, segundos) / 60).rounded())
        if minutos < 60 { return ("\(minutos)", "min") }
        let h = Double(minutos) / 60
        return (h < 10 ? coma(String(format: "%.1f", h)) : "\(Int(h.rounded()))", "h")
    }

    /// "812" + "tokens", "340" + "k tokens", "1,2" + "M tokens".
    public static func tokens(_ n: Int) -> (numero: String, unidad: String) {
        let t = TableroCentro.tokens(n)
        let partes = t.split(separator: " ", maxSplits: 1).map(String.init)
        return partes.count == 2 ? (partes[0], partes[1] + " tokens") : (t, "tokens")
    }

    /// "20,01" + "US$" (equivalente API, no factura); "<0,01" para lo que no llega al centavo.
    public static func costo(_ usd: Double) -> (numero: String, unidad: String) {
        guard usd.isFinite, usd >= 0 else { return ("0", "US$") }
        if usd > 0 && usd < 0.005 { return ("<0,01", "US$") }
        let centavos = Int((usd * 100).rounded())
        var grupos = ""
        for (i, c) in String(centavos / 100).reversed().enumerated() {
            if i > 0, i % 3 == 0 { grupos.append(".") }
            grupos.append(c)
        }
        return (String(grupos.reversed()) + "," + String(format: "%02d", centavos % 100), "US$")
    }

    private static func coma(_ s: String) -> String { s.replacingOccurrences(of: ".", with: ",") }
}

/// Las frases del encabezado del Centro.
public enum FraseCentro {
    private static let dias = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

    /// "3 trabajando · 2 esperan tu sí · 5 tareas hoy". Lo que es cero no se dice; si todo es cero, "Todo en calma".
    /// `tareasHoy` nil (no se sabe) no se menciona.
    public static func estado(trabajando: Int, esperan: Int, tareasHoy: Int?) -> String {
        var partes: [String] = []
        if trabajando > 0 { partes.append("\(trabajando) trabajando") }
        if esperan > 0 { partes.append(esperan == 1 ? "1 espera tu sí" : "\(esperan) esperan tu sí") }
        if let t = tareasHoy, t > 0 { partes.append(t == 1 ? "1 tarea hoy" : "\(t) tareas hoy") }
        return partes.isEmpty ? "Todo en calma" : partes.joined(separator: " · ")
    }

    /// "lunes 16 de noviembre".
    public static func fecha(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.weekday, .day, .month], from: fecha)
        return "\(dias[((c.weekday ?? 1) - 1) % 7]) \(c.day ?? 1) de \(NombresFecha.meses[((c.month ?? 1) - 1) % 12])"
    }
}

/// Moverse con las flechas en una lista: se queda dentro de los límites y, sin selección, entra por el primero.
public enum ListaFlechas {
    public static func mover(actual: Int?, delta: Int, total: Int) -> Int? {
        guard total > 0 else { return nil }
        guard let actual else { return delta < 0 ? total - 1 : 0 }
        return min(max(actual + delta, 0), total - 1)
    }
}
