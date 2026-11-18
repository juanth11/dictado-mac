import Foundation

/// Reparto de las sesiones de la pestaña Agentes: la que trabaja más reciente va como tarjeta grande y el resto (otras en marcha y las
/// terminadas) forma una pila de filas compactas. Lógica pura, probada con `swift test`.
public enum PilaAgentes {
    public enum Estado: Sendable, Equatable { case espera, trabaja, lista }

    /// Cuántas filas caben en la pila (la franja mide 178 pt).
    public static let filasVisibles = 3
    /// Tokens de contexto que llenan la barra de progreso al 100 %.
    public static let contextoMaximo = 1_000_000

    /// Índices (sobre la lista recibida, en su orden) de la sesión grande y de la pila. Las que esperan tu respuesta no entran: tienen su
    /// propia tarjeta. La grande es la primera que trabaja; la pila pone primero lo que trabaja y luego lo terminado.
    public static func repartir(_ estados: [Estado]) -> (grande: Int?, pila: [Int]) {
        let grande = estados.firstIndex(of: .trabaja)
        let resto = estados.indices.filter { estados[$0] != .espera && $0 != grande }
        let trabajan = resto.filter { estados[$0] == .trabaja }
        let listas = resto.filter { estados[$0] == .lista }
        return (grande, trabajan + listas)
    }

    /// El contexto usado como fracción de 0 a 1 (tope en 1; negativos como 0).
    public static func progreso(contexto: Int) -> Double {
        min(1, max(0, Double(contexto) / Double(contextoMaximo)))
    }

    /// "41 %" para la barra.
    public static func porcentaje(contexto: Int) -> String { "\(Int((progreso(contexto: contexto) * 100).rounded())) %" }

    /// Cuántas quedan fuera de la vista.
    public static func ocultas(total: Int) -> Int { max(0, total - filasVisibles) }
}
