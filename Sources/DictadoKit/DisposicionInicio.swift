import Foundation

/// Cómo se reparte el ancho de la fila de Inicio entre la música, el lanzador, la reunión y la tarjeta de la derecha (agentes o foco).
/// Cada pieza tiene un ancho preferido y uno mínimo; si no caben, se achican primero la tarjeta de la derecha, luego la
/// reunión y al final la música y el lanzador nunca baja de `minimoApps`.
public struct DisposicionInicio: Equatable, Sendable {
    public var musica: Double
    public var apps: Double
    public var reunion: Double
    /// Agentes, o el bloque de foco si hay uno en curso.
    public var derecha: Double

    public struct Medidas: Sendable {
        public var musica: ClosedRange<Double> = 250...300
        public var reunion: ClosedRange<Double> = 150...170
        public var agentes: ClosedRange<Double> = 130...150
        public var foco: ClosedRange<Double> = 176...190
        public var minimoApps = 330.0
        public init() {}
    }

    public static func repartir(total: Double, separacion: Double = 10, foco: Bool, medidas m: Medidas = Medidas()) -> DisposicionInicio {
        let disponible = max(0, total - 3 * separacion)
        let der = foco ? m.foco : m.agentes
        var musica = m.musica.upperBound, reunion = m.reunion.upperBound, derecha = der.upperBound
        var exceso = musica + reunion + derecha + m.minimoApps - disponible
        func recortar(_ valor: inout Double, hasta minimo: Double) {
            guard exceso > 0 else { return }
            let quita = min(exceso, valor - minimo)
            valor -= quita
            exceso -= quita
        }
        // Primero se achican la tarjeta de la derecha y la reunión; la música, la principal, es la última.
        recortar(&derecha, hasta: der.lowerBound)
        recortar(&reunion, hasta: m.reunion.lowerBound)
        recortar(&musica, hasta: m.musica.lowerBound)
        // Con una pantalla más ancha, lo que sobra va al lanzador.
        let apps = max(m.minimoApps, disponible - musica - reunion - derecha)
        return DisposicionInicio(musica: musica, apps: apps, reunion: reunion, derecha: derecha)
    }

    public var suma: Double { musica + apps + reunion + derecha }
}
