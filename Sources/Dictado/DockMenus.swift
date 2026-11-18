import AppKit
import DictadoKit
import SwiftUI

// El menú de clic derecho de una app del Dock, como el del Dock original: Abrir / Salir (con Opción, Forzar salida), Ocultar o
// Mostrar, Mostrar en Finder y Opciones (mantener en el Dock o quitarlo). Es un NSMenu de verdad porque solo AppKit sabe de las
// alternativas con Opción; el clic derecho lo abre `ClicDerechoMenu`. Salir y Forzar salida solo ocurren por acción explícita.

/// Un elemento de menú que corre un cierre.
final class ItemAccion: NSMenuItem {
    private let cierre: () -> Void

    init(_ titulo: String, marcado: Bool = false, _ cierre: @escaping () -> Void) {
        self.cierre = cierre
        super.init(title: titulo, action: #selector(disparar), keyEquivalent: "")
        target = self
        state = marcado ? .on : .off
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func disparar() { cierre() }
}

@MainActor
enum MenuAppDock {
    static func construir(_ app: EntradaApp, estado: EstadoDock) -> NSMenu {
        let menu = NSMenu(title: app.nombre)
        menu.autoenablesItems = false
        let ejecutando = AppsAbiertasDock.ejecutando(app)
        if let ejecutando {
            menu.addItem(ItemAccion("Abrir") { AppsAbiertasDock.abrir(app) })
            menu.addItem(.separator())
            menu.addItem(ItemAccion("Ventanas") { estado.acciones.ventanasProgramar(app, estado.anclasApp[app.id] ?? 0, true) })
            menu.addItem(ItemAccion(ejecutando.isHidden ? "Mostrar" : "Ocultar") { if ejecutando.isHidden { ejecutando.unhide() } else { ejecutando.hide() } })
            menu.addItem(ItemAccion("Salir") { ejecutando.terminate() })
            let forzar = ItemAccion("Forzar salida") { ejecutando.forceTerminate() }
            forzar.isAlternate = true
            forzar.keyEquivalentModifierMask = .option
            menu.addItem(forzar)
        } else {
            menu.addItem(ItemAccion("Abrir") { AppsAbiertasDock.abrir(app) })
        }
        menu.addItem(.separator())
        let opciones = NSMenu(title: "Opciones")
        opciones.autoenablesItems = false
        let fija = estado.estaFija(app)
        opciones.addItem(ItemAccion(fija ? "Quitar del Dock" : "Mantener en el Dock") { estado.alternarFija(app) })
        let padre = NSMenuItem(title: "Opciones", action: nil, keyEquivalent: "")
        padre.submenu = opciones
        menu.addItem(padre)
        menu.addItem(ItemAccion("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.ruta)]) })
        return menu
    }
}

/// Una capa encima de una vista de SwiftUI que solo atiende el clic derecho (y Control + clic): abre el menú que arma `menu`. Los
/// demás clics y el puntero pasan a lo de abajo.
struct ClicDerechoMenu: NSViewRepresentable {
    let menu: @MainActor () -> NSMenu

    func makeNSView(context: Context) -> VistaClicDerecho { VistaClicDerecho() }

    func updateNSView(_ v: VistaClicDerecho, context: Context) { v.armar = menu }

    final class VistaClicDerecho: NSView {
        var armar: (@MainActor () -> NSMenu)?

        override func hitTest(_ punto: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let derecho = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return derecho ? super.hitTest(punto) : nil
        }

        override func rightMouseDown(with event: NSEvent) { abrir(event) }
        override func mouseDown(with event: NSEvent) { abrir(event) }

        private func abrir(_ evento: NSEvent) {
            guard let m = armar else { return }
            NSMenu.popUpContextMenu(MainActor.assumeIsolated { m() }, with: evento, for: self)
        }
    }
}

/// Pone la capa del menú, salvo en los renders (ImageRenderer no dibuja vistas de AppKit y pinta un cartel de prohibido).
private struct CapaMenuApp: ViewModifier {
    let app: EntradaApp
    let estado: EstadoDock
    @Environment(\.vidrioSimulado) private var simulado

    func body(content: Content) -> some View {
        content.overlay { if !simulado { ClicDerechoMenu(menu: { MenuAppDock.construir(app, estado: estado) }) } }
    }
}

extension View {
    /// El menú de una app del Dock con Opción para Forzar salida.
    @MainActor func menuAppDock(_ app: EntradaApp, estado: EstadoDock) -> some View {
        modifier(CapaMenuApp(app: app, estado: estado))
    }
}
