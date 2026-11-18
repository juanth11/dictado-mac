import Foundation

/// El giro del disco de vinilo: 33⅓ vueltas por minuto mientras suena. Al pausar se queda en el ángulo que llevaba y al seguir sigue desde ahí
/// (no salta). Valor puro: la vista guarda uno y le pregunta el ángulo en cada cuadro.
public struct GiroDisco: Equatable, Sendable {
    /// 33⅓ rpm = 200 grados por segundo.
    public static let gradosPorSegundo: Double = 200

    private var base: Double = 0
    private var desde: Date?

    public init() {}

    public var girando: Bool { desde != nil }

    /// El ángulo (0 ..< 360) en `ahora`.
    public func angulo(en ahora: Date) -> Double {
        let corrido = desde.map { max(0, ahora.timeIntervalSince($0)) * Self.gradosPorSegundo } ?? 0
        let a = (base + corrido).truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// Empieza o detiene el giro. Pedir lo mismo que ya está no cambia nada.
    public mutating func cambiar(girando nuevo: Bool, ahora: Date) {
        guard nuevo != girando else { return }
        if nuevo {
            desde = ahora
        } else {
            base = angulo(en: ahora)
            desde = nil
        }
    }
}
