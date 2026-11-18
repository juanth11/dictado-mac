import Foundation

/// La esquina de la pantalla que abre y cierra el lanzador al quedarse el puntero (ajuste `lanzador.esquina`).
public enum EsquinaLanzador: String, CaseIterable, Sendable {
    case ninguna, inferiorDerecha, inferiorIzquierda, superiorDerecha, superiorIzquierda

    public static let porOmision = EsquinaLanzador.inferiorDerecha

    /// El ajuste tal cual; sin él (o con algo desconocido) vale la esquina de siempre.
    public init(ajuste: String?) {
        let n = BusquedaApps.normalizar(ajuste ?? "").replacingOccurrences(of: " ", with: "")
        self = Self.allCases.first { BusquedaApps.normalizar($0.rawValue) == n } ?? Self.porOmision
    }

    /// El cuadrito de la esquina (de `lado` puntos) en coordenadas de AppKit (origen abajo a la izquierda). nil para `ninguna`.
    public func marco(x: Double, y: Double, ancho: Double, alto: Double, lado: Double) -> MarcoEsquina? {
        switch self {
        case .ninguna: return nil
        case .inferiorIzquierda: return MarcoEsquina(x: x, y: y, lado: lado)
        case .inferiorDerecha: return MarcoEsquina(x: x + ancho - lado, y: y, lado: lado)
        case .superiorIzquierda: return MarcoEsquina(x: x, y: y + alto - lado, lado: lado)
        case .superiorDerecha: return MarcoEsquina(x: x + ancho - lado, y: y + alto - lado, lado: lado)
        }
    }
}

public struct MarcoEsquina: Equatable, Sendable {
    public var x: Double, y: Double, lado: Double
    public init(x: Double, y: Double, lado: Double) {
        self.x = x
        self.y = y
        self.lado = lado
    }
}

/// La espera de la esquina, sin ventanas ni cronómetro (lo corre quien la usa): el puntero entra → empieza a contar; si a los
/// `espera` segundos sigue dentro y no hay botones apretados, dispara UNA vez. Hasta que salga no vuelve a disparar. Si entró con un
/// botón apretado (un arrastre) o lo apretó antes de que se cumpliera, esa estancia no dispara nunca.
public struct PoliticaEsquina: Equatable, Sendable {
    public static let espera = 0.3

    public enum Fase: Equatable, Sendable { case reposo, esperando, bloqueada, disparada }
    public private(set) var fase = Fase.reposo

    public init() {}

    /// true: hay que programar la espera.
    public mutating func entra(botonesAbajo: Bool) -> Bool {
        guard fase == .reposo else { return false }
        if botonesAbajo { fase = .bloqueada; return false }
        fase = .esperando
        return true
    }

    public mutating func sale() { fase = .reposo }

    /// Venció la espera: true = abrir o cerrar el lanzador.
    public mutating func vence(botonesAbajo: Bool, punteroDentro: Bool) -> Bool {
        guard fase == .esperando else { return false }
        if botonesAbajo { fase = .bloqueada; return false }
        guard punteroDentro else { fase = .reposo; return false }
        fase = .disparada
        return true
    }
}
