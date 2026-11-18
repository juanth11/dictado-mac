import Foundation

/// Dónde está cada tecla en un teclado Mac estándar (ANSI/ISO), para mover el sonido de izquierda a derecha.
/// Solo se usa el código de tecla: nunca el carácter.
public enum MapaTeclas {
    /// Ancho del teclado en unidades de tecla.
    public static let ancho = 15.0

    /// Centro horizontal de cada tecla (en unidades de tecla desde el borde izquierdo), por código virtual.
    static let columnas: [Int: Double] = {
        var m: [Int: Double] = [:]
        // Fila de números: ` 1 2 3 4 5 6 7 8 9 0 - = ⌫
        for (i, c) in [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24].enumerated() { m[c] = 0.5 + Double(i) }
        m[51] = 14.0
        // Fila Q: ⇥ q w e r t y u i o p [ ] \
        m[48] = 0.75
        for (i, c) in [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30].enumerated() { m[c] = 2.0 + Double(i) }
        m[42] = 14.25
        // Fila A: a s d f g h j k l ; ' ↩ (Bloq Mayús, 57, ocupa 1,75 a la izquierda)
        m[57] = 0.875
        for (i, c) in [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39].enumerated() { m[c] = 2.25 + Double(i) }
        m[36] = 13.875
        m[76] = 14.5  // intro del teclado numérico
        // Fila Z: ⇧ z x c v b n m , . / ⇧
        m[56] = 1.125
        for (i, c) in [6, 7, 8, 9, 11, 45, 46, 43, 47, 44].enumerated() { m[c] = 2.75 + Double(i) }
        m[60] = 13.875
        // Fila inferior: ⌃ ⌥ ⌘ espacio ⌘ ⌥ y las flechas
        m[59] = 0.625; m[58] = 1.875; m[55] = 3.125; m[49] = 6.875
        m[54] = 10.625; m[61] = 11.875
        m[123] = 13.25; m[125] = 14.0; m[126] = 14.0; m[124] = 14.75
        // Esc y teclas de función repartidas a lo ancho
        m[53] = 0.5
        for (i, c) in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].enumerated() { m[c] = 1.75 + Double(i) * 0.95 }
        return m
    }()

    /// Posición de 0 (izquierda) a 1 (derecha); 0,5 si el código no está en el mapa.
    public static func posicion(codigo: Int) -> Double {
        guard let c = columnas[codigo] else { return 0.5 }
        return min(max(c / ancho, 0), 1)
    }

    /// Paneo estéreo de -1 a 1; `amplitud` limita cuánto se aleja del centro (0,7: nunca todo a un oído).
    public static func paneo(codigo: Int, amplitud: Double = 0.7) -> Double {
        (posicion(codigo: codigo) - 0.5) * 2 * min(max(amplitud, 0), 1)
    }

    /// Espacio, Intro, Retroceso y Tab suenan más pesados (los estabilizadores).
    public static func esGrande(codigo: Int) -> Bool {
        [49, 36, 76, 51, 117].contains(codigo)
    }

    /// Teclas que no suenan: modificadores solos, F18 (la tecla hyper) y Bloq Mayús.
    public static func silenciosa(codigo: Int) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 79].contains(codigo)
    }

    /// La clase de una tecla para "Mi teclado": solo estas cuatro se distinguen (nunca se guarda qué tecla fue).
    public static func clase(codigo: Int) -> ClaseTecla {
        switch codigo {
        case 49: return .espacio
        case 36, 76: return .intro
        case 51: return .retroceso
        default: return .normal
        }
    }
}
