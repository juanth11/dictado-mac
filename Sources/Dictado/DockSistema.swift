import AppKit
import DictadoKit

// "Ocultar el Dock del sistema" (menú del Dock propio y ajuste `dock.ocultarSistema`, apagado por omisión). La lógica (qué guardar, qué
// escribir, cómo volver) vive en `ControlDockSistema` (DictadoKit, con pruebas); aquí solo está lo que toca el sistema:
//   · leer y escribir `autohide` y `autohide-delay` de `com.apple.dock` con CFPreferences (no usa el comando `defaults`);
//   · reiniciar el proceso del Dock con `/usr/bin/killall Dock`;
//   · recordar el interruptor y el estado de antes en los ajustes de la app (`dock.ocultarSistema`, `dock.ocultarSistema.previo`).
// Solo corre cuando el dueño enciende el interruptor, quita la función del Dock propio o pide `Dictado --restaurar-dock`.
// Nunca se llama al probar la app ni en los renders.

final class AjustesDockReal: AjustesDockSistema {
    private let dominio = "com.apple.dock" as CFString
    private let claveAutohide = "autohide" as CFString
    private let claveRetardo = "autohide-delay" as CFString

    func leer() -> AjusteDockSistema {
        let a = CFPreferencesCopyAppValue(claveAutohide, dominio) as? NSNumber
        let r = CFPreferencesCopyAppValue(claveRetardo, dominio) as? NSNumber
        return AjusteDockSistema(autohide: a?.boolValue, retardo: r?.doubleValue)
    }

    func escribir(_ ajuste: AjusteDockSistema) {
        // Un nil borra la clave: el Dock vuelve a su valor de fábrica, no a uno escrito a mano.
        CFPreferencesSetValue(claveAutohide, ajuste.autohide.map { NSNumber(value: $0) }, dominio, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(claveRetardo, ajuste.retardo.map { NSNumber(value: $0) }, dominio, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(dominio, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func reiniciarDock() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

final class AlmacenDockDefaults: AlmacenDockSistema {
    static let claveInterruptor = "dock.ocultarSistema"
    static let clavePrevio = "dock.ocultarSistema.previo"
    private let d: UserDefaults

    init(_ d: UserDefaults = .dictado) { self.d = d }

    var interruptor: Bool {
        get { d.bool(forKey: Self.claveInterruptor) }
        set { d.set(newValue, forKey: Self.claveInterruptor) }
    }

    var previo: AjusteDockSistema? {
        get { d.string(forKey: Self.clavePrevio).flatMap { AjusteDockSistema(texto: $0) } }
        set {
            if let n = newValue { d.set(n.texto, forKey: Self.clavePrevio) } else { d.removeObject(forKey: Self.clavePrevio) }
        }
    }
}

extension ControlDockSistema {
    /// El control de verdad (sistema y ajustes de la app).
    static func real() -> ControlDockSistema { ControlDockSistema(sistema: AjustesDockReal(), almacen: AlmacenDockDefaults()) }
}

/// `Dictado --restaurar-dock`: devuelve el Dock del sistema a lo guardado (o de fábrica si estaba oculto como lo deja la app). Para el
/// caso de que la app no esté corriendo y el Dock del sistema haya quedado oculto.
func restaurarDockSistemaCLI() -> Int32 {
    let r = ControlDockSistema.real().restaurar()
    print(r == .cambiado ? "Dock del sistema restaurado." : "El Dock del sistema ya estaba como debía: no se tocó nada.")
    return 0
}
