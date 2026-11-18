import Foundation

/// Detector de "sacudida" del cursor: varios cambios de dirección horizontales en poco tiempo. Es lógica pura:
/// recibe puntos con su marca de tiempo y dice si ya hubo una sacudida. No sabe nada de eventos del sistema.
///
/// Un cambio de dirección cuenta solo si el trazo que se revierte recorrió al menos `recorridoMinimo` puntos y
/// fue más horizontal que vertical (hasta `inclinacionMaxima`); así no disparan los movimientos rápidos en una
/// sola dirección, los arrastres, los círculos ni un solo vaivén.
public struct DetectorSacudida: Sendable {
    public struct Config: Equatable, Sendable {
        /// Cambios de dirección que hacen falta.
        public var inversiones: Int
        /// Todos tienen que caber en esta ventana (segundos).
        public var ventana: Double
        /// Lo mínimo que tiene que recorrer cada trazo (puntos).
        public var recorridoMinimo: Double
        /// Silencio después de disparar (segundos).
        public var enfriamiento: Double
        /// Una pausa más larga que esto entre dos puntos empieza de cero (segundos).
        public var pausaMaxima: Double
        /// Cuánto puede subir o bajar un trazo respecto a lo que avanza de lado (1 = hasta 45°).
        public var inclinacionMaxima: Double

        public init(inversiones: Int = 4, ventana: Double = 0.6, recorridoMinimo: Double = 60, enfriamiento: Double = 1.0,
                    pausaMaxima: Double = 0.25, inclinacionMaxima: Double = 1.0) {
            self.inversiones = inversiones
            self.ventana = ventana
            self.recorridoMinimo = recorridoMinimo
            self.enfriamiento = enfriamiento
            self.pausaMaxima = pausaMaxima
            self.inclinacionMaxima = inclinacionMaxima
        }

        /// Sensibilidad de 0 (exige mucho) a 1 (se dispara con poco): recorrido de 110 a 35 puntos y ventana de 0,5 a 0,8 s.
        public static func sensibilidad(_ s: Double) -> Config {
            let k = min(max(s, 0), 1)
            return Config(ventana: 0.5 + 0.3 * k, recorridoMinimo: 110 - 75 * k)
        }
    }

    public var config: Config
    /// Dónde empezó el trazo actual.
    private var anclaX = 0.0, anclaY = 0.0
    /// +1 hacia la derecha, -1 hacia la izquierda, 0 sin definir.
    private var direccion = 0
    /// El punto más lejano del trazo actual en su dirección.
    private var extremoX = 0.0, extremoY = 0.0
    private var hayAncla = false
    private var ultimoT = -Double.infinity
    private var inversiones: [Double] = []
    private var silencioHasta = -Double.infinity

    public init(config: Config = Config()) { self.config = config }

    public mutating func reiniciar() {
        hayAncla = false
        direccion = 0
        inversiones.removeAll(keepingCapacity: true)
    }

    private mutating func anclar(_ x: Double, _ y: Double) {
        hayAncla = true
        direccion = 0
        anclaX = x
        anclaY = y
        extremoX = x
        extremoY = y
    }

    /// true en el punto que completa la sacudida.
    public mutating func alimentar(x: Double, y: Double, t: Double) -> Bool {
        defer { ultimoT = t }
        if t < silencioHasta { return false }
        if !hayAncla || t - ultimoT > config.pausaMaxima || t < ultimoT {
            reiniciar()
            anclar(x, y)
            return false
        }
        let minimo = config.recorridoMinimo
        if direccion == 0 {
            let dx = x - anclaX
            if abs(dx) >= minimo {
                direccion = dx > 0 ? 1 : -1
                extremoX = x
                extremoY = y
            } else if abs(y - anclaY) >= minimo {
                anclar(x, y)  // se fue hacia arriba o abajo: el punto de partida ya no sirve
            }
            return false
        }
        if (x - extremoX) * Double(direccion) > 0 {  // sigue avanzando en su dirección
            extremoX = x
            extremoY = y
            return false
        }
        guard (extremoX - x) * Double(direccion) >= minimo else { return false }  // todavía no revierte lo suficiente
        let largo = abs(extremoX - anclaX)
        let altura = abs(extremoY - anclaY)
        if altura > largo * config.inclinacionMaxima {
            reiniciar()  // trazo muy inclinado: no es una sacudida horizontal
            anclar(x, y)
            return false
        }
        inversiones.append(t)
        inversiones.removeAll { t - $0 > config.ventana }
        if inversiones.count >= config.inversiones {
            silencioHasta = t + config.enfriamiento
            reiniciar()
            return true
        }
        anclaX = extremoX
        anclaY = extremoY
        direccion = -direccion
        extremoX = x
        extremoY = y
        return false
    }
}
