import Foundation

/// Las medidas del panel abierto de la isla (Aurora, sección 9): una sola fuente para el dibujo y para el tamaño de la
/// ventana, que se calcula con ellas en `Isla.swift`.
public enum MedidasNotch {
    public static let anchoIdeal: Double = 968
    /// El panel no se achica de aquí aunque la pantalla sea más angosta: las tarjetas se comprimen hasta ahí.
    public static let anchoMinimo: Double = 800
    public static let relleno: Double = 14
    public static let aireSuperior: Double = 4
    public static let alturaPestanas: Double = 26
    public static let separacion: Double = 10
    public static let alturaTarjetas: Double = 178
    public static let radioInferior: Double = 26

    /// Ancho del panel en una pantalla de `pantalla` puntos: el ideal si cabe con el aire de la sombra a cada lado y,
    /// si no, lo que quede (sin bajar del mínimo).
    public static func ancho(pantalla: Double, margenSombra: Double = 26, aire: Double = 12) -> Double {
        guard pantalla.isFinite, pantalla > 0 else { return anchoIdeal }
        return min(anchoIdeal, max(anchoMinimo, pantalla - 2 * (margenSombra + aire)))
    }

    /// Alto del panel: la zona del notch, un respiro, las pestañas, la fila de tarjetas y el pie.
    public static func alto(notch: Double) -> Double {
        notch + aireSuperior + alturaPestanas + separacion + alturaTarjetas + relleno
    }
}
