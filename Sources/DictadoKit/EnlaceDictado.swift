import Foundation

// Los enlaces dictado:// (para Atajos de Apple, Siri, Raycast o una terminal): qué orden trae cada uno. Lógica pura, sin AppKit.
//
//   dictado://grabar                 empieza o termina la grabación de la reunión (alterna)
//   dictado://grabar/empezar         empieza solo si no está grabando
//   dictado://grabar/terminar        termina solo si está grabando
//   dictado://espacio/2              va al espacio 2 (por número, como Hyper + 2)
//   dictado://espacio/foco           va al espacio por su nombre (sin importar mayúsculas ni tildes)
//   dictado://espacio/siguiente      el siguiente (y /anterior)
//   dictado://lanzador               abre o cierra el lanzador
//   dictado://centro                 abre o cierra el Centro (también dictado://hoy)
//   dictado://centro/abrir           abre el Centro (si ya está abierto, lo deja)
//   dictado://foco                   empieza o termina un bloque de foco
//   dictado://unirse                 se une a la reunión que está por empezar
//   dictado://ultima-grabacion       muestra en el Finder la transcripción y las notas de la última grabación

/// Lo que pide un enlace dictado://.
public enum OrdenEnlace: Equatable, Sendable {
    public enum Grabar: Equatable, Sendable { case alternar, empezar, terminar }
    /// A qué espacio ir: un destino de teclado o un nombre.
    public enum Espacio: Equatable, Sendable {
        case destino(DestinoEspacio)
        case nombre(String)
    }

    case grabar(Grabar)
    case espacio(Espacio)
    case lanzador
    case centro
    case abrirCentro
    case foco
    case unirse
    case ultimaGrabacion
}

public enum EnlaceDictado {
    public static let esquema = "dictado"

    /// La orden de un enlace, o nil si no es de Dictado o no se entiende. Acepta `dictado://grabar/empezar` y `dictado:grabar/empezar`.
    public static func analizar(_ url: URL) -> OrdenEnlace? {
        guard url.scheme?.lowercased() == esquema else { return nil }
        // En dictado://grabar/empezar el primer tramo es el host; en dictado:grabar/empezar va en la ruta.
        var tramos = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if let host = url.host, !host.isEmpty { tramos.insert(host, at: 0) }
        if tramos.isEmpty, let resto = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, !resto.isEmpty {
            tramos = resto.split(separator: "/").map(String.init)
        }
        guard let primero = tramos.first.map(normalizar) else { return nil }
        let segundo = tramos.dropFirst().first

        switch primero {
        case "grabar", "grabacion", "reunion":
            switch segundo.map(normalizar) {
            case nil, "alternar": return .grabar(.alternar)
            case "empezar", "iniciar", "comenzar": return .grabar(.empezar)
            case "terminar", "parar", "detener": return .grabar(.terminar)
            default: return nil
            }
        case "espacio":
            guard let segundo, !segundo.trimmingCharacters(in: .whitespaces).isEmpty else { return .espacio(.destino(.siguiente)) }
            let s = normalizar(segundo)
            if let n = Int(s), n >= 1 { return .espacio(.destino(.numero(n))) }
            if s == "siguiente" { return .espacio(.destino(.siguiente)) }
            if s == "anterior" { return .espacio(.destino(.anterior)) }
            return .espacio(.nombre(segundo.trimmingCharacters(in: .whitespaces)))
        case "lanzador", "apps": return .lanzador
        case "centro", "hoy", "tablero": return segundo.map(normalizar) == "abrir" ? .abrirCentro : .centro
        case "foco": return .foco
        case "unirse", "unirme": return .unirse
        case "ultima-grabacion", "ultima", "ultimagrabacion": return .ultimaGrabacion
        default: return nil
        }
    }

    /// Lo mismo desde el texto del enlace (nil si no es una URL).
    public static func analizar(texto: String) -> OrdenEnlace? { URL(string: texto).flatMap(analizar) }

    /// El índice del espacio que se llama `nombre` (sin importar mayúsculas, tildes ni espacios sobrantes), o nil.
    public static func indiceDeEspacio(_ nombre: String, en nombres: [String]) -> Int? {
        let buscado = normalizar(nombre)
        return nombres.firstIndex { normalizar($0) == buscado }
    }

    static func normalizar(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
    }
}
