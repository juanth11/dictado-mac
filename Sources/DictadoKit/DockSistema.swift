import Foundation

/// Los dos ajustes del Dock del sistema (`com.apple.dock`) que usa "Ocultar el Dock del sistema": ocultarlo solo (`autohide`) y
/// cuánto tarda en salir (`autohide-delay`). `nil` quiere decir que la clave NO existe (el valor de fábrica): se guarda y se
/// devuelve tal cual, para que restaurar deje el Dock exactamente como estaba.
public struct AjusteDockSistema: Equatable, Sendable {
    public var autohide: Bool?
    public var retardo: Double?

    public init(autohide: Bool?, retardo: Double?) {
        self.autohide = autohide
        self.retardo = retardo
    }

    /// Lo que escribe la app: se oculta solo y su retardo es tan largo que nunca sale.
    public static let ocultoPorLaApp = AjusteDockSistema(autohide: true, retardo: 1000)
    /// Las dos claves ausentes: el Dock de fábrica.
    public static let defecto = AjusteDockSistema(autohide: nil, retardo: nil)
    /// Desde cuántos segundos de retardo se cuenta como "oculto de verdad".
    public static let retardoMinimoOculto = 100.0

    /// ¿Está el Dock oculto como lo deja la app (o a mano con los mismos valores)? Autohide encendido y un retardo muy largo.
    public var estaOculto: Bool { autohide == true && (retardo ?? 0) >= Self.retardoMinimoOculto }

    /// Para guardarlo en los ajustes de la app: "autohide=true;retardo=1000", con "-" donde la clave no existe.
    public var texto: String {
        "autohide=" + (autohide.map { $0 ? "true" : "false" } ?? "-") + ";retardo=" + (retardo.map { String($0) } ?? "-")
    }

    public init?(texto: String) {
        var a: Bool?, r: Double?, vistos = 0
        for parte in texto.split(separator: ";") {
            let kv = parte.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { return nil }
            switch kv[0] {
            case "autohide":
                if kv[1] == "-" { a = nil } else if kv[1] == "true" { a = true } else if kv[1] == "false" { a = false } else { return nil }
                vistos += 1
            case "retardo":
                if kv[1] == "-" { r = nil } else if let v = Double(kv[1]) { r = v } else { return nil }
                vistos += 1
            default: return nil
            }
        }
        guard vistos == 2 else { return nil }
        self.init(autohide: a, retardo: r)
    }
}

/// Lo que toca el sistema: leer y escribir los ajustes del Dock y reiniciar su proceso. Es un protocolo para probar la lógica con uno
/// falso; el verdadero vive en la app.
public protocol AjustesDockSistema: AnyObject {
    func leer() -> AjusteDockSistema
    /// Escribe los dos valores; un `nil` BORRA la clave.
    func escribir(_ ajuste: AjusteDockSistema)
    func reiniciarDock()
}

/// Dónde recuerda la app el interruptor y el estado de antes (sus propios ajustes, no los del sistema).
public protocol AlmacenDockSistema: AnyObject {
    var interruptor: Bool { get set }
    var previo: AjusteDockSistema? { get set }
}

public enum ResultadoDockSistema: Equatable, Sendable {
    /// Nada que hacer (ya estaba así).
    case nada
    /// Escribió los ajustes y reinició el Dock.
    case cambiado
    /// Al arrancar encontró el Dock ya oculto sin estado guardado: lo adopta como encendido y recuerda "de fábrica".
    case adoptado
}

/// El interruptor "Ocultar el Dock del sistema": qué guardar, qué escribir y cómo volver, sin tocar el sistema directamente.
///   · Encender guarda el estado de ahora (con "clave ausente" incluida), pone autohide y un retardo larguísimo y reinicia el Dock.
///     Encender de nuevo mientras ya está encendido no pisa lo guardado.
///   · Apagar (o quitar la función, o `--restaurar-dock`) escribe lo guardado tal cual y borra las claves que no existían. Sin nada
///     guardado, devuelve el Dock de fábrica SOLO si está oculto como lo deja la app; si no, no toca nada.
///   · Reiniciar el Dock solo ocurre si algo cambió de verdad.
public final class ControlDockSistema {
    private let sistema: AjustesDockSistema
    private let almacen: AlmacenDockSistema

    public init(sistema: AjustesDockSistema, almacen: AlmacenDockSistema) {
        self.sistema = sistema
        self.almacen = almacen
    }

    public var encendido: Bool { almacen.interruptor }

    @discardableResult
    public func encender() -> ResultadoDockSistema {
        let actual = sistema.leer()
        if !(almacen.interruptor && almacen.previo != nil) {
            // Si ya estaba oculto a mano, "antes" es el Dock de fábrica: así apagar lo devuelve a la vista.
            almacen.previo = actual.estaOculto ? .defecto : actual
        }
        almacen.interruptor = true
        guard !actual.estaOculto else { return .nada }
        sistema.escribir(.ocultoPorLaApp)
        sistema.reiniciarDock()
        return .cambiado
    }

    @discardableResult
    public func restaurar() -> ResultadoDockSistema {
        let actual = sistema.leer()
        let destino = almacen.previo ?? (actual.estaOculto ? AjusteDockSistema.defecto : nil)
        almacen.previo = nil
        almacen.interruptor = false
        guard let destino, destino != actual else { return .nada }
        sistema.escribir(destino)
        sistema.reiniciarDock()
        return .cambiado
    }

    /// Al arrancar la app con el Dock propio encendido: pone el interruptor de acuerdo con lo que hay.
    ///   · Oculto y sin estado guardado (lo hiciste a mano): se adopta como encendido y "antes" = de fábrica.
    ///   · Oculto y con estado guardado: el interruptor queda encendido.
    ///   · Interruptor encendido pero el Dock a la vista (algo lo deshizo): se vuelve a ocultar y lo que hay pasa a ser "antes".
    @discardableResult
    public func alArrancar() -> ResultadoDockSistema {
        let actual = sistema.leer()
        if actual.estaOculto {
            if almacen.previo == nil {
                almacen.previo = .defecto
                almacen.interruptor = true
                return .adoptado
            }
            almacen.interruptor = true
            return .nada
        }
        guard almacen.interruptor else { return .nada }
        almacen.previo = actual
        sistema.escribir(.ocultoPorLaApp)
        sistema.reiniciarDock()
        return .cambiado
    }
}
