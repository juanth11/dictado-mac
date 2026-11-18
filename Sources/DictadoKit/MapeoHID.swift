import Foundation

/// Mapeo de teclas del sistema HID para Hyper (Bloq Mayús → F18): la parte pura, sin IOKit. Lo que lee y escribe
/// el sistema vive en `MapeoHyper` (app).
public enum MapeoHID {
    public static let bloqMayus: Int64 = 0x7_0000_0039
    public static let f18: Int64 = 0x7_0000_006D
    public struct Par: Equatable, Sendable {
        public var origen: Int64
        public var destino: Int64
        public init(origen: Int64, destino: Int64) { self.origen = origen; self.destino = destino }
    }

    public static let propio = Par(origen: bloqMayus, destino: f18)

    /// El mapeo con hyper y qué guardar para restaurar. Si Bloq Mayús ya tenía un mapeo tuyo (por ejemplo a
    /// Control), se guarda para devolverlo al quitar hyper. Si el mapeo ya era nuestro, se conserva lo guardado.
    public static func conHyper(_ actual: [Par], guardado: Par?, yaAplicado: Bool) -> (mapeo: [Par], previo: Par?) {
        let previo = yaAplicado ? guardado : actual.first { $0.origen == bloqMayus }
        return (actual.filter { $0.origen != bloqMayus } + [propio], previo)
    }

    /// El mapeo sin hyper: lo demás intacto y, si lo había, el mapeo previo de Bloq Mayús de vuelta.
    public static func sinHyper(_ actual: [Par], previo: Par?) -> [Par] {
        actual.filter { $0.origen != bloqMayus } + (previo.map { [$0] } ?? [])
    }

    /// JSON para `hidutil property --set` (números en decimal).
    public static func json(_ mapeo: [Par]) -> String {
        let pares = mapeo.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.origen),\"HIDKeyboardModifierMappingDst\":\($0.destino)}" }
        return "{\"UserKeyMapping\":[\(pares.joined(separator: ","))]}"
    }
}
