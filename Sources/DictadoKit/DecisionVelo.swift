import CoreGraphics
import Foundation

/// Una ventana del sistema tal como la entrega la lista de ventanas (de adelante hacia atrás).
public struct VentanaMundo: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var bundle: String?
    public var capa: Int
    public var marco: CGRect
    public var alfa: Double

    public init(id: UInt32, pid: Int32, bundle: String?, capa: Int = 0, marco: CGRect, alfa: Double = 1) {
        self.id = id
        self.pid = pid
        self.bundle = bundle
        self.capa = capa
        self.marco = marco
        self.alfa = alfa
    }
}

/// Lo que el usuario eligió para el velo.
public struct AjustesVelo: Equatable, Sendable {
    /// Mantener nítidas todas las ventanas de la app activa (no solo la enfocada).
    public var todaLaApp: Bool
    /// Conjuntos de apps que se quedan nítidas juntas.
    public var grupos: [Set<String>]
    /// Apps con las que el velo se apaga solo.
    public var ignoradas: Set<String>
    public var ocultarEnPantallaCompleta: Bool

    public init(todaLaApp: Bool = false, grupos: [Set<String>] = [], ignoradas: Set<String> = [], ocultarEnPantallaCompleta: Bool = true) {
        self.todaLaApp = todaLaApp
        self.grupos = grupos
        self.ignoradas = ignoradas
        self.ocultarEnPantallaCompleta = ocultarEnPantallaCompleta
    }
}

/// Lo que se sabe del momento: quién está al frente y qué hay en pantalla.
public struct SituacionVelo: Equatable, Sendable {
    public var bundleAlFrente: String?
    /// Marco de la ventana enfocada según Accesibilidad (si se pudo leer): desempata entre varias ventanas de la app.
    public var marcoEnfocado: CGRect?
    public var pantallaCompleta: Bool
    public var misionControl: Bool

    public init(bundleAlFrente: String?, marcoEnfocado: CGRect? = nil, pantallaCompleta: Bool = false, misionControl: Bool = false) {
        self.bundleAlFrente = bundleAlFrente
        self.marcoEnfocado = marcoEnfocado
        self.pantallaCompleta = pantallaCompleta
        self.misionControl = misionControl
    }
}

public enum MotivoSinVelo: Equatable, Sendable {
    case sinApp, ignorada, misionControl, pantallaCompleta, sinVentana
}

public enum PlanVelo: Equatable, Sendable {
    case ocultar(MotivoSinVelo)
    /// El velo va justo debajo de esta ventana; `marco` es el de la ventana (para elegir la pantalla).
    case debajoDe(id: UInt32, marco: CGRect)
}

public enum DecisionVelo {
    /// Una ventana "de verdad": capa normal, visible y de tamaño de ventana (no menús, avisos ni piezas sueltas).
    public static func esVentanaNormal(_ w: VentanaMundo) -> Bool {
        w.capa == 0 && w.alfa > 0.01 && w.marco.width >= 120 && w.marco.height >= 80
    }

    /// Decide debajo de qué ventana va el velo. `ventanas` viene de adelante hacia atrás y ya sin las del propio velo.
    public static func plan(ventanas: [VentanaMundo], situacion: SituacionVelo, ajustes: AjustesVelo) -> PlanVelo {
        guard let frente = situacion.bundleAlFrente else { return .ocultar(.sinApp) }
        if ajustes.ignoradas.contains(frente) { return .ocultar(.ignorada) }
        if situacion.misionControl { return .ocultar(.misionControl) }
        if situacion.pantallaCompleta && ajustes.ocultarEnPantallaCompleta { return .ocultar(.pantallaCompleta) }

        let normales = ventanas.enumerated().filter { esVentanaNormal($0.element) }
        // La app al frente más sus compañeras de grupo.
        var apps: Set<String> = [frente]
        for g in ajustes.grupos where g.contains(frente) { apps.formUnion(g) }

        func deLaApp(_ b: String) -> [(offset: Int, element: VentanaMundo)] { normales.filter { $0.element.bundle == b } }
        let propias = deLaApp(frente)
        guard !propias.isEmpty else { return .ocultar(.sinVentana) }

        // La ventana activa: la que Accesibilidad dice, o la de más arriba de la app.
        var activa = propias[0]
        if let marco = situacion.marcoEnfocado,
           let igual = propias.first(where: { cercanos($0.element.marco, marco) }) {
            activa = igual
        }
        var masProfunda = activa.offset
        var debajoDe = activa.element
        func considerar(_ w: (offset: Int, element: VentanaMundo)) {
            if w.offset > masProfunda {
                masProfunda = w.offset
                debajoDe = w.element
            }
        }
        if ajustes.todaLaApp { propias.forEach(considerar) }
        for b in apps where b != frente {
            let suyas = deLaApp(b)
            if ajustes.todaLaApp { suyas.forEach(considerar) } else if let primera = suyas.first { considerar(primera) }
        }
        return .debajoDe(id: debajoDe.id, marco: debajoDe.marco)
    }

    private static func cercanos(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 3 && abs(a.minY - b.minY) <= 3 && abs(a.width - b.width) <= 3 && abs(a.height - b.height) <= 3
    }
}
