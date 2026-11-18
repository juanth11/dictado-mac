import Foundation

/// El efecto lupa del Dock: dada la posición del puntero, cuánto crece cada pieza y cuánto se aparta. Es matemática pura (se
/// prueba sin ventanas) y se recalcula en cada movimiento del puntero.
///
/// El crecimiento sigue un coseno al cuadrado: 1,5 × en la pieza que está bajo el puntero y vuelve a 1 a `radio` puntos. Las piezas
/// crecen sobre su base (hacia arriba) y las vecinas se apartan lo justo para no solaparse; el punto del Dock que está bajo el
/// puntero no se mueve, así el icono que vas a pulsar no se escapa de debajo del cursor.
public enum LupaDock {
    /// La escala de la pieza que está justo bajo el puntero.
    public static let escalaMaxima = 1.5
    /// A qué distancia (en puntos) del puntero vuelve a 1.
    public static let radio = 150.0

    /// Una pieza en reposo: su borde izquierdo, su ancho y si crece (los widgets de datos no crecen: solo se apartan).
    public struct Pieza: Equatable, Sendable {
        public var izquierda: Double
        public var ancho: Double
        public var crece: Bool
        public init(izquierda: Double, ancho: Double, crece: Bool = true) {
            self.izquierda = izquierda
            self.ancho = ancho
            self.crece = crece
        }
        public var centro: Double { izquierda + ancho / 2 }
        public var derecha: Double { izquierda + ancho }
    }

    public struct Efecto: Equatable, Sendable {
        /// Escala sobre la base de la pieza (1 = reposo).
        public var escala: Double
        /// Cuánto se corre en horizontal respecto a su sitio en reposo (puntos, positivo = a la derecha).
        public var desplazamiento: Double
        public static let reposo = Efecto(escala: 1, desplazamiento: 0)
    }

    public struct Resultado: Equatable, Sendable {
        public var efectos: [Efecto]
        /// Cuánto se ensancha la barra por cada lado (puntos, nunca negativo).
        public var crecimientoIzquierda: Double
        public var crecimientoDerecha: Double
        public static func reposo(_ cuantas: Int) -> Resultado { Resultado(efectos: Array(repeating: .reposo, count: cuantas), crecimientoIzquierda: 0, crecimientoDerecha: 0) }
    }

    /// El perfil: 1 bajo el puntero y 0 a `radio` o más, suave (coseno al cuadrado).
    public static func perfil(_ distancia: Double, radio: Double = LupaDock.radio) -> Double {
        let d = abs(distancia)
        guard radio > 0, d < radio else { return 0 }
        let c = cos(Double.pi * d / (2 * radio))
        return c * c
    }

    public static func escala(distancia: Double, maxima: Double = LupaDock.escalaMaxima, radio: Double = LupaDock.radio) -> Double {
        1 + (maxima - 1) * perfil(distancia, radio: radio)
    }

    /// Sin puntero (nil) todo queda en reposo. Las piezas van de izquierda a derecha y sin solaparse.
    public static func calcular(_ piezas: [Pieza], puntero: Double?, maxima: Double = LupaDock.escalaMaxima, radio: Double = LupaDock.radio) -> Resultado {
        guard let p = puntero, !piezas.isEmpty, maxima > 1 else { return .reposo(piezas.count) }
        let escalas = piezas.map { $0.crece ? escala(distancia: p - $0.centro, maxima: maxima, radio: radio) : 1 }
        // Posición escalada de cada pieza, apilada desde la izquierda con los mismos huecos del reposo.
        var izquierdas: [Double] = []
        var x = piezas[0].izquierda
        for (i, pieza) in piezas.enumerated() {
            izquierdas.append(x)
            x += pieza.ancho * escalas[i]
            if i + 1 < piezas.count { x += max(0, piezas[i + 1].izquierda - pieza.derecha) }
        }
        let finEscalado = x
        // El punto que está bajo el puntero no se mueve: se busca su posición escalada.
        let k = piezas.lastIndex { $0.izquierda <= p } ?? 0
        let pieza = piezas[k]
        let ancho = pieza.ancho * escalas[k]
        let escaladoBajoPuntero: Double
        if p >= pieza.derecha {   // en el hueco de después de la pieza (o más allá del final): lo que pasa de la pieza no se escala
            escaladoBajoPuntero = izquierdas[k] + ancho + (p - pieza.derecha)
        } else {
            escaladoBajoPuntero = izquierdas[k] + (pieza.ancho > 0 ? (p - pieza.izquierda) / pieza.ancho : 0) * ancho
        }
        let corrimiento = p - escaladoBajoPuntero
        var efectos: [Efecto] = []
        for (i, pieza) in piezas.enumerated() {
            let centroNuevo = izquierdas[i] + corrimiento + pieza.ancho * escalas[i] / 2
            efectos.append(Efecto(escala: escalas[i], desplazamiento: centroNuevo - pieza.centro))
        }
        let izq = max(0, -corrimiento)
        let der = max(0, finEscalado + corrimiento - piezas[piezas.count - 1].derecha)
        return Resultado(efectos: efectos, crecimientoIzquierda: izq, crecimientoDerecha: der)
    }
}
