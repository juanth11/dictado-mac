import Foundation

/// La preferencia de tema del lanzador (y del fondo del Centro): `automatico` deja que decida la luminancia del fondo.
public enum PreferenciaTema: String, Sendable {
    case automatico, oscuro, claro, sistema

    /// El botón del tema da la vuelta: automático (según el fondo) → oscuro → claro.
    public var siguiente: PreferenciaTema {
        switch self {
        case .automatico, .sistema: return .oscuro
        case .oscuro: return .claro
        case .claro: return .automatico
        }
    }

    public var nombre: String {
        switch self {
        case .automatico: return "Automático"
        case .oscuro: return "Oscuro"
        case .claro: return "Claro"
        case .sistema: return "Como el Mac"
        }
    }
}

/// Las reglas puras del fondo de escritorio que comparten el lanzador y el Centro: qué tema pide y cuánto velo necesita.
public enum TemaDelFondo {
    /// ¿Pide tema claro? Forzado por la preferencia; "sistema" sigue al Mac; en automático decide la luminancia del fondo
    /// (las paletas propias son oscuras; sin imagen todavía, oscuro).
    public static func esClaro(preferencia: PreferenciaTema, fondo: FondoLanzador, luminanciaClara: Bool?, sistemaOscuro: Bool) -> Bool {
        switch preferencia {
        case .oscuro: return false
        case .claro: return true
        case .sistema: return !sistemaOscuro
        case .automatico:
            if case .paleta = fondo { return false }
            return luminanciaClara == true
        }
    }

    /// Cuánto oscurece de más el Centro un fondo claro (0 a `maximo`) para que el texto blanco de sus tarjetas siga pasando AA:
    /// nada hasta el 35 % de luminancia y de ahí sube en línea recta hasta `maximo` en el blanco. Sin luminancia conocida, nada.
    public static let refuerzoMaximo = 0.30
    public static let refuerzoDesde = 0.35

    public static func refuerzoDeVelo(luminancia: Double?) -> Double {
        guard let l = luminancia else { return 0 }
        let t = (min(max(l, 0), 1) - refuerzoDesde) / (1 - refuerzoDesde)
        return max(0, t) * refuerzoMaximo
    }
}
