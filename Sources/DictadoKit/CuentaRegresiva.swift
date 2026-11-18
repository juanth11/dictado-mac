import Foundation

/// Lo que dice la tarjeta de la próxima reunión, calculado aparte de la vista para poder probarlo.
public enum CuentaRegresiva {
    /// La cuenta en números de puntos: con una hora o más, "2:15" y la unidad "h"; con menos, los minutos ("12", "min");
    /// en curso, nil (la tarjeta dice "En curso"). Se redondea hacia arriba: a las 2:59:30 quedan "3 min".
    public static func texto(hasta inicio: Date, desde ahora: Date) -> (texto: String, unidad: String)? {
        let s = inicio.timeIntervalSince(ahora)
        guard s > 0 else { return nil }
        let minutos = Int((s / 60).rounded(.up))
        if minutos >= 60 { return (String(format: "%d:%02d", minutos / 60, minutos % 60), "h") }
        return ("\(minutos)", "min")
    }
}

/// Cuándo cambia lo ocupado por libre (o al revés) en la agenda: la frase de la tarjeta cuando no hay una reunión cerca.
public enum CambioAgenda {
    public struct Estado: Equatable, Sendable {
        /// Hay un evento que bloquea ahora mismo.
        public var ocupadoAhora: Bool
        /// Cuándo cambia: el fin del bloque actual, o el inicio del siguiente. nil si no hay nada más en la agenda.
        public var cambio: Date?
    }

    public static func proximo(ocupados: [Intervalo], ahora: Date) -> Estado {
        let bloques = Huecos.unir(ocupados)
        if let actual = bloques.first(where: { $0.inicio <= ahora && $0.fin > ahora }) {
            return Estado(ocupadoAhora: true, cambio: actual.fin)
        }
        return Estado(ocupadoAhora: false, cambio: bloques.first { $0.inicio > ahora }?.inicio)
    }
}
