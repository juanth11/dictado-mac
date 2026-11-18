import Foundation

/// Cuándo se ve la barra del Dock.
public enum ModoVisibilidadDock: String, Sendable, CaseIterable {
    /// Siempre en pantalla.
    case siempre
    /// Oculta hasta que el puntero se queda un momento en el borde de abajo.
    case alTocarBorde
}

/// Dónde puede estar el puntero para que el Dock siga a la vista.
public enum ZonaDock: Hashable, Sendable { case barra, selector, panel }

/// Lo que la ventana tiene que hacer después de un aviso.
public enum AccionDock: Equatable, Sendable {
    case ninguna
    case mostrar
    case ocultar
    /// Revisar en tantos segundos si ya se puede ocultar.
    case programarOcultar(Double)
    case cancelarOcultar
}

/// La política de aparecer y esconderse, sin ventanas: recibe lo que pasó (el puntero se quedó en el borde, entró o salió,
/// se abrió un menú, el atajo) y dice qué hacer. Así se prueba entera.
///   · Al borde, el puntero tiene que quedarse `esperaBorde` (0,25 s) para que aparezca (lo cronometra quien la usa).
///   · Se queda mientras el puntero esté sobre la barra o sobre un panel de carpeta, o haya un menú abierto.
///   · Al salir, se oculta `esperaOcultar` (0,6 s) después, si nada cambió.
///   · El atajo la deja fija (sin ocultarse sola) o la esconde.
public struct PoliticaDock: Equatable, Sendable {
    public static let esperaBorde = 0.25
    public static let esperaOcultar = 0.6

    public var modo: ModoVisibilidadDock
    public private(set) var visible: Bool
    public private(set) var zonas: Set<ZonaDock> = []
    public private(set) var menuAbierto = false
    /// La mostró el atajo: no se oculta sola hasta que lo pulses otra vez.
    public private(set) var fija = false
    /// En modo siempre: el atajo la escondió.
    public private(set) var escondida = false
    /// El lanzador a pantalla completa está abierto: la barra se queda a la vista debajo de él.
    public private(set) var retenida = false

    public init(modo: ModoVisibilidadDock) {
        self.modo = modo
        visible = modo == .siempre
    }

    private var ocupada: Bool { !zonas.isEmpty || menuAbierto || fija || retenida }

    public mutating func cambiarModo(_ nuevo: ModoVisibilidadDock) -> AccionDock {
        guard nuevo != modo else { return .ninguna }
        modo = nuevo
        escondida = false
        fija = false
        if nuevo == .siempre {
            visible = true
            return .mostrar
        }
        if !ocupada, visible {
            return .programarOcultar(Self.esperaOcultar)
        }
        return .ninguna
    }

    /// El puntero se quedó en el borde de abajo el tiempo de espera.
    public mutating func bordeSostenido() -> AccionDock {
        guard modo == .alTocarBorde, !visible else { return .ninguna }
        visible = true
        return .mostrar
    }

    public mutating func punteroEntra(_ zona: ZonaDock) -> AccionDock {
        zonas.insert(zona)
        return .cancelarOcultar
    }

    public mutating func punteroSale(_ zona: ZonaDock) -> AccionDock {
        zonas.remove(zona)
        return evaluarSalida()
    }

    public mutating func menu(abierto: Bool) -> AccionDock {
        menuAbierto = abierto
        return abierto ? .cancelarOcultar : evaluarSalida()
    }

    private func evaluarSalida() -> AccionDock {
        guard modo == .alTocarBorde, visible, !ocupada else { return .ninguna }
        return .programarOcultar(Self.esperaOcultar)
    }

    /// Venció la espera de ocultar: se oculta si nada cambió mientras tanto.
    public mutating func venceOcultar() -> AccionDock {
        guard modo == .alTocarBorde, visible, !ocupada else { return .ninguna }
        visible = false
        return .ocultar
    }

    /// El lanzador se abre (true) o se cierra (false). Abierto, la barra se muestra aunque estuviera oculta (por el modo o por el atajo) y
    /// no se esconde sola; al cerrarse vuelve a lo que decía la política (si solo estaba por el lanzador, se oculta después de la espera).
    public mutating func retener(_ si: Bool) -> AccionDock {
        guard si != retenida else { return .ninguna }
        retenida = si
        if si {
            guard !visible else { return .cancelarOcultar }
            visible = true
            return .mostrar
        }
        if modo == .siempre {
            guard escondida, visible else { return .ninguna }
            visible = false
            return .ocultar
        }
        return evaluarSalida()
    }

    /// Hyper + atajo: la muestra y la deja fija, o la esconde.
    public mutating func alternarAtajo() -> AccionDock {
        if modo == .siempre {
            escondida.toggle()
            visible = !escondida
            return visible ? .mostrar : .ocultar
        }
        if visible {
            fija = false
            visible = false
            zonas = []
            return .ocultar
        }
        fija = true
        visible = true
        return .mostrar
    }
}
