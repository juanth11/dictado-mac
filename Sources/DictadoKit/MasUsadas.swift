import Foundation

/// Cuánto se usa una app según Spotlight (`kMDItemUseCount` y `kMDItemLastUsedDate`).
public struct UsoApp: Equatable, Sendable {
    public var bundleID: String
    public var usos: Int
    public var ultimoUso: Date?

    public init(bundleID: String, usos: Int, ultimoUso: Date? = nil) {
        self.bundleID = bundleID
        self.usos = usos
        self.ultimoUso = ultimoUso
    }
}

public enum MasUsadas {
    /// Las `cuantas` apps más usadas, por identificador de paquete. Primero van las que el dueño fijó a mano
    /// (`preferidas`, en su orden); lo que falta se llena con el uso medido: más usos primero, el uso más reciente
    /// desempata y, al final, el identificador (para que el orden sea siempre el mismo). Solo cuentan las instaladas,
    /// sin repetir y sin las de `excluir`; las que Spotlight nunca vio usar (0 usos) no entran.
    public static func ranking(_ usos: [UsoApp], instaladas: Set<String>, excluir: Set<String> = [], preferidas: [String] = [],
                               cuantas: Int = 6) -> [String] {
        guard cuantas > 0 else { return [] }
        var salida: [String] = []
        func agregar(_ id: String) {
            guard salida.count < cuantas, instaladas.contains(id), !excluir.contains(id), !salida.contains(id) else { return }
            salida.append(id)
        }
        preferidas.forEach(agregar)
        // Una misma app puede aparecer dos veces (dos copias): cuenta la que más se usó.
        var mejor: [String: UsoApp] = [:]
        for u in usos where u.usos > 0 {
            if let previo = mejor[u.bundleID], previo.usos >= u.usos { continue }
            mejor[u.bundleID] = u
        }
        let ordenadas = mejor.values.sorted {
            if $0.usos != $1.usos { return $0.usos > $1.usos }
            let a = $0.ultimoUso ?? .distantPast, b = $1.ultimoUso ?? .distantPast
            if a != b { return a > b }
            return $0.bundleID < $1.bundleID
        }
        ordenadas.map(\.bundleID).forEach(agregar)
        return salida
    }

    /// Las apps fijadas de Inicio cuando el dueño no dijo nada: solo Spotify.
    public static let fijasPorOmision = ["com.spotify.client"]

    /// Las fijadas que están instaladas (en su orden, sin repetir) y después el resto, sin las fijadas. Así la pieza fijada va
    /// antes que las más usadas aunque Spotlight nunca la haya visto.
    public static func conFijas(fijas: [String], instaladas: Set<String>, resto: [String]) -> [String] {
        var salida: [String] = []
        for id in fijas where instaladas.contains(id) && !salida.contains(id) { salida.append(id) }
        for id in resto where !salida.contains(id) { salida.append(id) }
        return salida
    }

    /// Fija la app si no lo estaba (al final) o la quita de las fijas si lo estaba.
    public static func alternarFija(_ fijas: [String], id: String) -> [String] {
        fijas.contains(id) ? fijas.filter { $0 != id } : fijas + [id]
    }
}
