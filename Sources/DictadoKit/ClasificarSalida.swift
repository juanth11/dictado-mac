import Foundation

/// Qué dispositivos de CoreAudio se ofrecen como salida de sonido en la isla. Lógica pura (sin CoreAudio): recibe el tipo de transporte
/// como código de cuatro letras (`'grup'`, `'virt'`…) y los indicadores del dispositivo.
public enum ClasificarSalida {
    public enum Tipo: Sendable, Equatable {
        /// Altavoces, audífonos, pantallas, AirPlay…
        case fisica
        /// Salida múltiple o dispositivo agregado de Configuración de Audio MIDI (p. ej. «MacBook + Echo»).
        case multiple
        /// Virtual de una app (Zoom, Teams, BlackHole…): no se ofrece.
        case virtual
    }

    public static func codigo(_ texto: String) -> UInt32 {
        texto.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static let agregado = codigo("grup")
    public static let virtual = codigo("virt")

    public static func tipo(transporte: UInt32) -> Tipo {
        if transporte == agregado { return .multiple }
        if transporte == virtual { return .virtual }
        return .fisica
    }

    /// ¿Se ofrece como salida? Debe tener canales de salida, no estar oculto (los agregados privados de las apps lo están) y no ser virtual.
    public static func seOfrece(tieneSalida: Bool, oculto: Bool, transporte: UInt32) -> Bool {
        tieneSalida && !oculto && tipo(transporte: transporte) != .virtual
    }

    /// Físicas primero y las salidas múltiples después, cada grupo por nombre (estable entre lecturas).
    public static func orden(_ a: (nombre: String, multiple: Bool), _ b: (nombre: String, multiple: Bool)) -> Bool {
        if a.multiple != b.multiple { return !a.multiple }
        return a.nombre.localizedCaseInsensitiveCompare(b.nombre) == .orderedAscending
    }
}
