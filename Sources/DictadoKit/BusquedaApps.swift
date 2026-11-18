import Foundation

/// Una app instalada tal como la ve el lanzador: nombre que se muestra, ruta del `.app` e identificador del paquete.
public struct EntradaApp: Equatable, Hashable, Sendable, Identifiable {
    public var nombre: String
    public var ruta: String
    public var bundleID: String?

    /// El identificador del paquete; si la app no lo trae, su ruta.
    public var id: String { bundleID ?? ruta }

    public init(nombre: String, ruta: String, bundleID: String? = nil) {
        self.nombre = nombre
        self.ruta = ruta
        self.bundleID = bundleID
    }
}

/// Orden, depuración y búsqueda de las apps del lanzador.
public enum BusquedaApps {
    /// Minúsculas, sin tildes y con los espacios colapsados: "  Cálculo  Rápido " → "calculo rapido".
    public static func normalizar(_ texto: String) -> String {
        let plano = texto.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return plano.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Quita las repetidas (mismo identificador de paquete; sin él, misma ruta) y ordena por nombre. Gana la primera que
    /// aparece: quien llama pasa las carpetas en orden de prioridad (/Applications antes que ~/Applications).
    public static func depurar(_ entradas: [EntradaApp]) -> [EntradaApp] {
        var vistos = Set<String>()
        var unicas: [EntradaApp] = []
        for e in entradas where !e.nombre.isEmpty && vistos.insert(e.id).inserted { unicas.append(e) }
        return unicas
            .map { (clave: normalizar($0.nombre), entrada: $0) }
            .sorted { a, b in
                if a.clave != b.clave { return a.clave < b.clave }
                if a.entrada.nombre != b.entrada.nombre { return a.entrada.nombre < b.entrada.nombre }
                return a.entrada.ruta < b.entrada.ruta
            }
            .map(\.entrada)
    }

    /// Sin las que el usuario ocultó (por identificador).
    public static func sinOcultas(_ entradas: [EntradaApp], ocultas: Set<String>) -> [EntradaApp] {
        ocultas.isEmpty ? entradas : entradas.filter { !ocultas.contains($0.id) }
    }

    /// Cómo coincide el nombre con la consulta; menor es mejor. nil = no coincide.
    /// 0 empieza por la consulta · 1 una palabra empieza por ella (o cada palabra de la consulta abre una palabra) ·
    /// 2 la contiene en medio de una palabra.
    public static func puntaje(nombre: String, consulta: String) -> Int? {
        let q = normalizar(consulta)
        guard !q.isEmpty else { return nil }
        let n = normalizar(nombre)
        if n.hasPrefix(q) { return 0 }
        let palabras = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if palabras.contains(where: { $0.hasPrefix(q) }) { return 1 }
        if enPalabras(q, palabras) { return 1 }
        return n.contains(q) ? 2 : nil
    }

    /// Las apps que coinciden, mejores primero; dentro de cada grupo se conserva el orden de entrada (alfabético).
    public static func filtrar(_ entradas: [EntradaApp], consulta: String) -> [EntradaApp] {
        guard !normalizar(consulta).isEmpty else { return entradas }
        var puntuadas: [(Int, Int, EntradaApp)] = []
        for (i, e) in entradas.enumerated() {
            if let p = puntaje(nombre: e.nombre, consulta: consulta) { puntuadas.append((p, i, e)) }
        }
        return puntuadas.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { $0.2 }
    }

    /// Los nombres (atajos, por ejemplo) que coinciden con la consulta, mejores primero; sin consulta no hay ninguno.
    public static func filtrarNombres(_ nombres: [String], consulta: String) -> [String] {
        var puntuados: [(Int, Int, String)] = []
        for (i, n) in nombres.enumerated() {
            if let p = puntaje(nombre: n, consulta: consulta) { puntuados.append((p, i, n)) }
        }
        return puntuados.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { $0.2 }
    }

    /// "goo chr" abre "Google Chrome": cada palabra de la consulta abre una palabra distinta, en orden.
    private static func enPalabras(_ consulta: String, _ palabras: [String]) -> Bool {
        let partes = consulta.split(separator: " ").map(String.init)
        guard partes.count > 1 else { return false }
        var desde = 0
        for parte in partes {
            guard let i = palabras[desde...].firstIndex(where: { $0.hasPrefix(parte) }) else { return false }
            desde = i + 1
        }
        return true
    }
}
