import AppKit
import Carbon.HIToolbox
import DictadoKit
import os
import SwiftUI

private let log = Logger(subsystem: "app.dictado", category: "dock")

// Dock propio (función opcional, apagada por omisión): una barra de Aurora abajo al centro de cada pantalla con piezas que son datos
// reales (hora, agenda, agentes, tareas, dictar, foco, música, Mac, batería), tus apps, grupos y carpetas del Finder, y encima un
// selector de espacios. Convive con el Dock del sistema: no lo oculta, no lo mueve ni toca su configuración.
//
// Ventanas (todas sin bordes y sin tomar el foco; ninguna existe mientras no se ve):
//   · una franja de 3 pt en el borde de abajo que despierta la barra cuando el puntero se queda 0,25 s (modo "al tocar el borde");
//   · la barra y, aparte, el selector de espacios (así lo transparente alrededor es solo el aire de la sombra);
//   · el panel de una carpeta o de un grupo, que se despliega hacia arriba.
// Al esconderse se suelta todo: vistas, miniaturas, modelos y observadores. La política de cuándo aparece y se oculta es lógica
// pura (`PoliticaDock`, con pruebas). Atajo: Hyper + O muestra la barra (fija) o la esconde.
//
// Ajustes (defaults write app.dictado …):
//   dock.visibilidad  borde | siempre         (borde por omisión)
//   dock.pantallas    todas | principal       (todas por omisión)

extension Ajustes {
    static var dockVisibilidad: ModoVisibilidadDock {
        get { UserDefaults.dictado.string(forKey: "dock.visibilidad") == "siempre" ? .siempre : .alTocarBorde }
        set { UserDefaults.dictado.set(newValue == .siempre ? "siempre" : "borde", forKey: "dock.visibilidad") }
    }

    static var dockSoloPrincipal: Bool {
        get { UserDefaults.dictado.string(forKey: "dock.pantallas") == "principal" }
        set { UserDefaults.dictado.set(newValue ? "principal" : "todas", forKey: "dock.pantallas") }
    }
}

/// Detecta que el puntero entra o sale de una ventana (aunque Dictado no sea la app activa). Cubre toda la ventana.
final class SensorDock: NSView {
    var alEntrar: (() -> Void)?
    var alSalir: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { alEntrar?() }
    override func mouseExited(with event: NSEvent) { alSalir?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// El panel de una carpeta o un grupo: sin activar la app, pero puede recibir teclas (flechas, Espacio, Retorno, Esc).
final class PanelPila: NSPanel {
    var alTecla: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if alTecla?(event) != true { super.keyDown(with: event) }
    }
}

/// Una ventana del Dock: sin bordes, sin tomar el foco, sobre las ventanas normales y sin sombra propia (la dibuja la vista).
@MainActor
private func nuevoPanelDock(nivel: Int = 0, teclas: Bool = false) -> NSPanel {
    let p: NSPanel = teclas ? PanelPila(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        : NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.level = NSWindow.Level(rawValue: Dock.nivelBase + nivel)
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.becomesKeyOnlyIfNeeded = !teclas
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    return p
}

@MainActor
final class Dock: NSObject, NSMenuDelegate {
    /// Un panel desplegado (carpeta o grupo) y lo que hay que soltar al cerrarlo.
    @MainActor private final class Desplegado {
        let clave: String
        let panel: NSPanel
        let sensor: SensorDock
        let host: VistaPrimerClic<AnyView>
        let modelo: ModeloCarpeta?
        /// Cuántos elementos tiene (archivos o apps) y cómo se ordenan: de ahí sale el tamaño y el movimiento de las flechas.
        var cuantos: Int
        let seleccion: SeleccionPila
        /// Las apps del panel de un grupo o de las abiertas (vacío en una carpeta).
        var apps: [EntradaApp]
        /// Las ventanas de una app abierta (solo en un panel de ventanas).
        let ventanas: ModeloVentanasApp?

        init(clave: String, panel: NSPanel, sensor: SensorDock, host: VistaPrimerClic<AnyView>, modelo: ModeloCarpeta?, cuantos: Int, seleccion: SeleccionPila, apps: [EntradaApp] = [],
             ventanas: ModeloVentanasApp? = nil) {
            self.ventanas = ventanas
            self.seleccion = seleccion
            self.clave = clave
            self.panel = panel
            self.sensor = sensor
            self.host = host
            self.modelo = modelo
            self.cuantos = cuantos
            self.apps = apps
        }

        var modo: ModoPila { modelo == nil ? .cuadricula : AuroraDock.modoPila(cuantos) }
        var medidas: CGSize { ventanas?.medidas ?? AuroraDock.medidasPanel(modo: modo, cuantos: cuantos) }

        func cerrar() {
            (panel as? PanelPila)?.alTecla = nil
            sensor.alEntrar = nil
            sensor.alSalir = nil
            host.rootView = AnyView(EmptyView())
            host.removeFromSuperview()
            panel.contentView = nil
            panel.orderOut(nil)
            modelo?.soltar()
            ventanas?.soltar()
        }
    }

    /// Una pantalla con su Dock.
    @MainActor private final class Cara {
        let id: CGDirectDisplayID
        var pantalla: NSScreen
        var politica: PoliticaDock
        let datos: PantallaDock
        var barra: NSPanel?
        var selector: NSPanel?
        var sensorBarra: SensorDock?
        var sensorSelector: SensorDock?
        var hostBarra: VistaPrimerClic<AnyView>?
        var hostSelector: VistaPrimerClic<AnyView>?
        var borde: NSPanel?
        var sensorBorde: SensorDock?
        var espera: DispatchWorkItem?
        var ocultar: DispatchWorkItem?
        var fin: DispatchWorkItem?
        var desplegado: Desplegado?

        init(id: CGDirectDisplayID, pantalla: NSScreen, modo: ModoVisibilidadDock) {
            self.id = id
            self.pantalla = pantalla
            politica = PoliticaDock(modo: modo)
            datos = PantallaDock(anchoDisponible: pantalla.frame.width - 2 * CGFloat(MedidasDock.margenLateral))
        }
    }

    // MARK: Estado

    private static var compartido: Dock?
    /// El nivel de las ventanas de la barra: sobre las ventanas normales y, con el lanzador a pantalla completa abierto, por encima de él.
    private(set) static var nivelBase = NSWindow.Level.statusBar.rawValue
    nonisolated static var nivelBaseVisible: Int { MainActor.assumeIsolated { nivelBase } }
    /// Lo pide una pieza que abre algo (la isla, dictar): si el lanzador está abierto, se cierra primero. Lo pone la app.
    static var alAccionar: (() -> Void)?
    private var dockSistema: ControlDockSistema = .real()
    private var observadorAjustes: NSObjectProtocol?
    private var tocandoDockSistema = false

    /// Todo lo que cambia el Dock del sistema pasa por aquí: mientras corre, los avisos de cambio de ajustes no lo vuelven a disparar.
    private func tocarDockSistema(_ hacer: (ControlDockSistema) -> Void) {
        tocandoDockSistema = true
        hacer(dockSistema)
        tocandoDockSistema = false
    }
    private let contexto: ContextoModulos
    private let isla: () -> Isla?
    private var estado: EstadoDock?
    private var caras: [CGDirectDisplayID: Cara] = [:]
    private var encendido = false
    private var observadores: [NSObjectProtocol] = []
    private var monitorClics: Any?
    private var cacheTonos: [String: TonosFondo] = [:]
    private var ultimaCuenta: [String: Int] = [:]
    private static let idAtajo: UInt32 = 70
    private static let menuDock = NSMenu()
    /// El elemento del menú de la barra (con su submenú). Existe desde el arranque; solo se muestra con la función encendida.
    static let itemMenu: NSMenuItem = {
        let i = NSMenuItem(title: "Dock", action: nil, keyEquivalent: "")
        i.submenu = menuDock
        return i
    }()

    static func instalar(_ contexto: ContextoModulos, isla: @escaping () -> Isla?) -> Dock {
        let d = Dock(contexto, isla: isla)
        compartido = d
        return d
    }

    init(_ contexto: ContextoModulos, isla: @escaping () -> Isla?) {
        self.contexto = contexto
        self.isla = isla
        super.init()
        Self.menuDock.delegate = self
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.dock.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        sincronizar()
    }

    private func sincronizar() {
        if Funcion.dock.activa {
            encender()
        } else {
            apagar()
            // Sin el Dock propio, el del sistema no puede quedarse oculto (ni siquiera si la app se abrió ya así).
            if AlmacenDockDefaults().interruptor { tocarDockSistema { _ = $0.restaurar() } }
        }
    }

    // MARK: Encender y apagar

    private func encender() {
        guard !encendido else { return }
        encendido = true
        let hyper = cmdKey | optionKey | controlKey | shiftKey
        if !Atajos.shared.registrar(id: Self.idAtajo, tecla: kVK_ANSI_O, modificadores: hyper, alPresionar: { [weak self] in self?.alternarAtajo() }) {
            contexto.avisar("Hyper + O lo usa otra app", "keyboard.badge.exclamationmark", nil)
        }
        observadores.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.montar()
                for t in ColocacionDock.reintentos.dropFirst() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { self?.reacomodar() } }
                }
            }
        })
        // Otro espacio: el Dock toma su paleta (y, si no la tiene, los tonos del fondo de pantalla cuando ya cambió).
        observadores.append(NotificationCenter.default.addObserver(forName: .espacioCambio, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.caras.values.forEach { self?.refrescarTonos($0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated { self?.caras.values.forEach { self?.refrescarTonos($0) } } }
            }
        })
        // Mientras un menú (el de clic derecho de una carpeta o de una app) está abierto, el Dock no se esconde.
        for nombre in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            let abre = nombre == NSMenu.didBeginTrackingNotification
            observadores.append(NotificationCenter.default.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuCambio(abierto: abre) }
            })
        }
        montar()
        // El Dock del sistema: si ya estaba oculto a mano (o el interruptor está encendido), la app lo adopta; después sigue los ajustes.
        tocarDockSistema { _ = $0.alArrancar() }
        observadorAjustes = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.conciliarDockSistema() }
        }
    }

    /// El ajuste `dock.ocultarSistema` manda: si cambió (a mano con `defaults write` o desde el menú) y no coincide con lo aplicado, se aplica.
    private func conciliarDockSistema() {
        guard encendido, !tocandoDockSistema else { return }
        let almacen = AlmacenDockDefaults()
        let aplicado = almacen.previo != nil
        if almacen.interruptor, !aplicado { tocarDockSistema { _ = $0.encender() } } else if !almacen.interruptor, aplicado { tocarDockSistema { _ = $0.restaurar() } }
    }

    private func apagar() {
        guard encendido else { return }
        encendido = false
        if let o = observadorAjustes { NotificationCenter.default.removeObserver(o) }
        observadorAjustes = nil
        if Self.nivelBase != NSWindow.Level.statusBar.rawValue { Self.nivelBase = NSWindow.Level.statusBar.rawValue }
        Atajos.shared.quitar(id: Self.idAtajo)
        observadores.forEach { NotificationCenter.default.removeObserver($0) }
        observadores = []
        for cara in caras.values { soltar(cara) }
        caras = [:]
        quitarMonitor()
        estado?.alOcultar()
        estado = nil
    }

    // MARK: Pantallas

    /// Lee (sin escribir) cómo tiene el usuario el Dock del sistema: orientación y si se oculta solo.
    private static func dockSistemaAbajoFijo() -> Bool {
        let dominio = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dominio)
        let orientacion = CFPreferencesCopyAppValue("orientation" as CFString, dominio) as? String
        let autohide = (CFPreferencesCopyAppValue("autohide" as CFString, dominio) as? NSNumber)?.boolValue
        return ColocacionDock.dockSistemaAbajoFijo(orientacion: orientacion, autohide: autohide)
    }

    /// Tras un cambio de pantalla el Dock del sistema se reacomoda un momento después del aviso: se vuelve a colocar cada barra.
    private func reacomodar() {
        guard encendido else { return }
        for cara in caras.values {
            if let nueva = NSScreen.screens.first(where: { idDe($0) == cara.id }) { cara.pantalla = nueva }
            cara.datos.anchoDisponible = cara.pantalla.frame.width - 2 * CGFloat(MedidasDock.margenLateral)
            sincronizarBorde(cara)
            if cara.barra != nil { ajustarVentanas(cara) }
        }
    }

    private func pantallasObjetivo() -> [NSScreen] {
        Ajustes.dockSoloPrincipal ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
    }

    private func idDe(_ p: NSScreen) -> CGDirectDisplayID? { p.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }

    /// Una Dock por pantalla elegida. Se vuelve a llamar al conectar, desconectar o reacomodar pantallas.
    private func montar() {
        guard encendido else { return }
        let modo = Ajustes.dockVisibilidad
        var vivas = Set<CGDirectDisplayID>()
        for p in pantallasObjetivo() {
            guard let id = idDe(p) else { continue }
            vivas.insert(id)
            let cara = caras[id] ?? Cara(id: id, pantalla: p, modo: modo)
            caras[id] = cara
            cara.pantalla = p
            cara.datos.anchoDisponible = p.frame.width - 2 * CGFloat(MedidasDock.margenLateral)
            cara.datos.simulado = false
            if cara.politica.modo != modo { aplicar(cara, cara.politica.cambiarModo(modo)) }
            sincronizarBorde(cara)
            if cara.politica.visible, cara.barra == nil { mostrar(cara) } else if cara.barra != nil { ajustarVentanas(cara) }
        }
        for (id, cara) in caras where !vivas.contains(id) {
            soltar(cara)
            caras[id] = nil
        }
    }

    /// La franja del borde solo existe en modo "al tocar el borde".
    private func sincronizarBorde(_ cara: Cara) {
        guard cara.politica.modo == .alTocarBorde else {
            quitarBorde(cara)
            return
        }
        if cara.borde == nil {
            let sensor = SensorDock()
            sensor.alEntrar = { [weak self, weak cara] in if let cara { self?.empezarEspera(cara) } }
            sensor.alSalir = { [weak cara] in cara?.espera?.cancel() }
            let p = nuevoPanelDock()
            p.contentView = sensor
            cara.borde = p
            cara.sensorBorde = sensor
        }
        let marco = cara.pantalla.frame
        let ancho = min(marco.width - 2 * CGFloat(MedidasDock.margenLateral), AuroraDock.bordeAnchoMax)
        cara.borde?.setFrame(NSRect(x: marco.midX - ancho / 2, y: marco.minY, width: ancho, height: AuroraDock.bordeAlto), display: false)
        cara.borde?.orderFrontRegardless()
    }

    private func quitarBorde(_ cara: Cara) {
        cara.espera?.cancel()
        cara.sensorBorde?.alEntrar = nil
        cara.sensorBorde?.alSalir = nil
        cara.borde?.contentView = nil
        cara.borde?.orderOut(nil)
        cara.borde = nil
        cara.sensorBorde = nil
    }

    /// El puntero llegó al borde: si se queda 0,25 s y no hay botones apretados (no es un arrastre), aparece.
    private func empezarEspera(_ cara: Cara) {
        cara.espera?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara, NSEvent.pressedMouseButtons == 0, let borde = cara.borde,
                      NSMouseInRect(NSEvent.mouseLocation, borde.frame.insetBy(dx: 0, dy: -3), false) else { return }
                self.aplicar(cara, cara.politica.bordeSostenido())
            }
        }
        cara.espera = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + PoliticaDock.esperaBorde, execute: tarea)
    }

    // MARK: El lanzador a pantalla completa

    /// El lanzador se abre en esa pantalla: la barra sube por encima de él y se queda a la vista (aunque estuviera escondida).
    /// Devuelve si hay barra en esa pantalla (el lanzador deja el espacio de abajo solo en ese caso).
    @discardableResult
    static func lanzadorAbierto(en pantalla: NSScreen?) -> Bool { compartido?.retener(true, pantalla) ?? false }

    static func lanzadorCerrado() { _ = compartido?.retener(false, nil) }

    /// ¿Lleva el Dock propio una barra en esa pantalla (función encendida y pantalla elegida)?
    static func cubre(_ pantalla: NSScreen?) -> Bool {
        guard let d = compartido, d.encendido, let pantalla, let id = d.idDe(pantalla) else { return false }
        return d.pantallasObjetivo().contains { d.idDe($0) == id }
    }

    private func retener(_ si: Bool, _ pantalla: NSScreen?) -> Bool {
        guard encendido else { return false }
        Self.nivelBase = si ? AuroraLanzador.nivelDock : NSWindow.Level.statusBar.rawValue
        let idObjetivo = pantalla.flatMap { idDe($0) }
        var hay = false
        for cara in caras.values {
            if si, let idObjetivo, cara.id != idObjetivo { continue }
            hay = true
            aplicar(cara, cara.politica.retener(si))
            for (w, extra) in [(cara.barra, 0), (cara.selector, 0), (cara.desplegado?.panel, 1)] { w?.level = NSWindow.Level(rawValue: Self.nivelBase + extra) }
        }
        return hay
    }

    // MARK: Aplicar lo que decide la política

    private func aplicar(_ cara: Cara, _ accion: AccionDock) {
        switch accion {
        case .ninguna: break
        case .mostrar: mostrar(cara)
        case .ocultar: ocultar(cara)
        case .cancelarOcultar: cara.ocultar?.cancel()
        case .programarOcultar(let s): programarOcultar(cara, s)
        }
    }

    private func programarOcultar(_ cara: Cara, _ segundos: Double) {
        cara.ocultar?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara else { return }
                // AppKit a veces avisa una salida falsa al reacomodar las ventanas: si el puntero sigue encima, no se oculta.
                if self.punteroSobre(cara) {
                    _ = cara.politica.punteroEntra(.barra)
                    return
                }
                self.aplicar(cara, cara.politica.venceOcultar())
            }
        }
        cara.ocultar = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: tarea)
    }

    private func punteroSobre(_ cara: Cara) -> Bool {
        let p = NSEvent.mouseLocation
        for w in [cara.barra, cara.selector, cara.desplegado?.panel] {
            if let w, w.isVisible, NSMouseInRect(p, w.frame.insetBy(dx: AuroraDock.margenSombra, dy: 0), false) { return true }
        }
        return false
    }

    private func menuCambio(abierto: Bool) {
        for cara in caras.values where cara.barra != nil { aplicar(cara, cara.politica.menu(abierto: abierto)) }
    }

    // MARK: Hyper + O

    private func caraBajoPuntero() -> Cara? {
        let p = NSEvent.mouseLocation
        return caras.values.first { NSMouseInRect(p, $0.pantalla.frame, false) } ?? caras.values.first
    }

    private func alternarAtajo() {
        guard encendido else { return }
        if Ajustes.dockVisibilidad == .siempre {
            for cara in caras.values { aplicar(cara, cara.politica.alternarAtajo()) }
        } else if let cara = caraBajoPuntero() {
            aplicar(cara, cara.politica.alternarAtajo())
        }
    }

    // MARK: Mostrar

    private func datosVivos() -> EstadoDock? {
        if let estado { return estado }
        guard let i = isla() else { return nil }
        let e = EstadoDock(agenda: i.agenda, musica: i.musica, claude: i.claude, agentes: i.agentes, foco: i.foco, tareas: i.tareas, salud: i.salud.estado,
                           hud: i.hud, estadoIsla: i.estado, lanzador: i.lanzador, apps: i.appsUsadas)
        e.tablero = i.tablero
        e.alCambiarFinder = { [weak self] in self?.reacomodar() }
        e.acciones = AccionesDock(
            abrirPestana: { [weak self] p in self?.abrirPestana(p) },
            dictar: { [weak i] in Dock.alAccionar?(); i?.alDictar?() },
            dictarEncargo: { [weak i] in Dock.alAccionar?(); i?.alDictarEncargo?() },
            unirse: { [weak i] u in Dock.alAccionar?(); i?.unirse(u) },
            desplegar: { [weak self] clave, ancla in self?.desplegar(clave, ancla: ancla) },
            ventanasProgramar: { [weak self] app, ancla, ya in self?.programarVentanas(app, ancla: ancla, ya: ya) },
            ventanasCancelar: { [weak self] in self?.cancelarVentanas() },
            elegirEspacio: { [weak self, weak i] e in
                guard let self, let i, i.lanzador.espacioActual != e.nombre else { return }
                i.lanzador.elegirEspacio(e, foco: i.foco)   // el mismo camino que el lanzador de la isla
                self.caras.values.forEach { self.refrescarTonos($0) }
            },
            masEspacios: {
                Task.detached(priority: .userInitiated) {
                    LanzadorIsla.asegurarEspacios()
                    await MainActor.run { _ = NSWorkspace.shared.open(LanzadorIsla.archivoEspacios) }
                }
            },
            abrirSalud: { [weak i] in Dock.alAccionar?(); i?.abrirSalud() },
            abrirLanzador: { [weak self] in self?.contexto.alternarLanzador() })
        estado = e
        return e
    }

    private func mostrar(_ cara: Cara) {
        cara.fin?.cancel()
        if cara.barra != nil {   // estaba saliendo: vuelve a entrar
            cara.datos.aparecida = true
            return
        }
        guard let e = datosVivos() else {
            _ = cara.politica.alternarAtajo()
            contexto.avisar("El Dock necesita la isla encendida", "dock.rectangle", nil)
            return
        }
        e.alMostrar()
        refrescarTonos(cara)

        // La barra.
        let vistaBarra = VistaPrimerClic(rootView: AnyView(VistaDock(estado: e, pantalla: cara.datos)))
        let sensorBarra = SensorDock()
        sensorBarra.alEntrar = { [weak self, weak cara] in if let cara, let s = self { s.aplicar(cara, cara.politica.punteroEntra(.barra)) } }
        sensorBarra.alSalir = { [weak self, weak cara] in if let cara, let s = self { s.aplicar(cara, cara.politica.punteroSale(.barra)) } }
        vistaBarra.autoresizingMask = [.width, .height]
        sensorBarra.addSubview(vistaBarra)
        let barra = nuevoPanelDock()
        barra.contentView = sensorBarra
        cara.barra = barra
        cara.sensorBarra = sensorBarra
        cara.hostBarra = vistaBarra

        // El selector de espacios.
        let vistaSelector = VistaPrimerClic(rootView: AnyView(VistaSelectorDock(estado: e, pantalla: cara.datos)))
        let sensorSelector = SensorDock()
        sensorSelector.alEntrar = { [weak self, weak cara] in if let cara, let s = self { s.aplicar(cara, cara.politica.punteroEntra(.selector)) } }
        sensorSelector.alSalir = { [weak self, weak cara] in if let cara, let s = self { s.aplicar(cara, cara.politica.punteroSale(.selector)) } }
        vistaSelector.autoresizingMask = [.width, .height]
        sensorSelector.addSubview(vistaSelector)
        let selector = nuevoPanelDock()
        selector.contentView = sensorSelector
        cara.selector = selector
        cara.sensorSelector = sensorSelector
        cara.hostSelector = vistaSelector

        cara.datos.alCambiarAncho = { [weak self, weak cara] _ in if let cara { self?.ajustarVentanas(cara) } }
        cara.datos.aparecida = false
        ajustarVentanas(cara)
        barra.orderFrontRegardless()
        selector.orderFrontRegardless()
        DispatchQueue.main.async { [weak cara] in cara?.datos.aparecida = true }
    }

    /// Posición y tamaño: abajo al centro, encima del Dock del sistema si está abajo (la zona visible de la pantalla).
    private func ajustarVentanas(_ cara: Cara) {
        guard let e = estado, let barra = cara.barra, let selector = cara.selector else { return }
        let disposicion = ReglasDock.colocar(e.piezas, anchoDisponible: cara.datos.anchoDisponible)
        let marco = cara.pantalla.frame
        // Pegada a su margen: la reserva del Dock del sistema solo cuenta si está abajo y fijo (ver `ColocacionDock`).
        let abajo = CGFloat(ColocacionDock.base(frame: marco, visible: cara.pantalla.visibleFrame, dockSistemaAbajoFijo: Self.dockSistemaAbajoFijo()))
        let aire = AuroraDock.margenSombra
        // Con la lupa, la ventana tiene más aire arriba (lo que crece sobresale) y a los lados (la barra se ensancha).
        let lupa = cara.datos.lupa.activa
        let anchoBarra = CGFloat(disposicion.ancho) + 2 * aire + (lupa ? 2 * AuroraDockLupa.aireLado : 0)
        let altoBarra = AuroraDock.alto + AuroraDock.margenInferior + aire + (lupa ? AuroraDockLupa.aireArriba : 0)
        barra.setFrame(NSRect(x: marco.midX - anchoBarra / 2, y: abajo, width: anchoBarra, height: altoBarra), display: true)
        let anchoSelector = CGFloat(MedidasDock.anchoSelector(espacios: e.espacios.count)) + 2 * aire
        let altoSelector = AuroraDock.selectorAlto + 2 * aire
        let yBarraArriba = abajo + AuroraDock.margenInferior + AuroraDock.alto
        selector.setFrame(NSRect(x: marco.midX - anchoSelector / 2, y: yBarraArriba + AuroraDock.selectorSeparacion - aire, width: anchoSelector, height: altoSelector), display: true)
        reajustarDesplegado(cara)
    }

    // MARK: Ocultar

    private func ocultar(_ cara: Cara) {
        cerrarDesplegado(cara)
        cara.datos.aparecida = false
        cara.fin?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara, !cara.politica.visible else { return }
                self.desmontarBarra(cara)
                if !self.caras.values.contains(where: { $0.barra != nil }) { self.estado?.alOcultar() }
            }
        }
        cara.fin = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: tarea)
    }

    /// Suelta todo lo de la barra: las vistas (con su contenido), los sensores, las ventanas y los cierres pendientes.
    private func desmontarBarra(_ cara: Cara) {
        cara.ocultar?.cancel()
        cara.fin?.cancel()
        cerrarDesplegado(cara)
        cara.datos.alCambiarAncho = nil
        for (host, sensor, panel) in [(cara.hostBarra, cara.sensorBarra, cara.barra), (cara.hostSelector, cara.sensorSelector, cara.selector)] {
            host?.rootView = AnyView(EmptyView())
            host?.removeFromSuperview()
            sensor?.alEntrar = nil
            sensor?.alSalir = nil
            panel?.contentView = nil
            panel?.orderOut(nil)
        }
        cara.hostBarra = nil
        cara.hostSelector = nil
        cara.sensorBarra = nil
        cara.sensorSelector = nil
        cara.barra = nil
        cara.selector = nil
        cara.datos.aparecida = false
    }

    private func soltar(_ cara: Cara) {
        desmontarBarra(cara)
        quitarBorde(cara)
    }

    // MARK: Fondo y tonos

    /// Los tonos del acabado: los del fondo de pantalla si se pueden leer (en un hilo aparte) y, mientras tanto o si no, los de la
    /// paleta del espacio.
    private func refrescarTonos(_ cara: Cara) {
        let nombres = estado?.espacios.map(\.nombre) ?? []
        let i = nombres.firstIndex(of: estado?.espacioActual?.nombre ?? "") ?? 0
        let paleta = estado?.espacioActual?.paletaAurora ?? AuroraPaleta.allCases[i % AuroraPaleta.allCases.count]
        cara.datos.tonos = TonosDock.de(paleta: paleta)
        if estado?.espacioActual?.paletaAurora != nil { return }   // el espacio manda: su paleta, no los tonos del fondo
        guard let url = FondoPantalla.url(de: cara.pantalla) else { return }
        let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let clave = url.path + "|\(fecha)"
        if let t = cacheTonos[clave] {
            cara.datos.tonos = TonosDock.de(t)
            return
        }
        Task.detached(priority: .utility) {
            guard let t = FondoPantalla.tonos(en: url) else { return }
            await MainActor.run { [weak self, weak cara] in
                guard let self else { return }
                self.cacheTonos = [clave: t]   // una sola entrada: el fondo actual
                cara?.datos.tonos = TonosDock.de(t)
            }
        }
    }

    // MARK: Abrir la isla en una pestaña

    private func abrirPestana(_ p: EstadoIsla.Pestana) {
        Self.alAccionar?()
        let pantalla = caraBajoPuntero()?.pantalla
        isla()?.abrirPestana(p, en: pantalla)
    }

    // MARK: Paneles que se despliegan

    private func desplegar(_ clave: String, ancla: CGFloat) {
        guard let cara = caraBajoPuntero(), let e = estado, let barra = cara.barra else { return }
        if cara.desplegado?.clave == clave {   // otro clic en el mismo mosaico lo cierra
            cerrarDesplegado(cara)
            return
        }
        cerrarDesplegado(cara)
        let contenido: AnyView
        var modelo: ModeloCarpeta?
        var cuantos = 1
        var apps: [EntradaApp] = []
        var ventanas: ModeloVentanasApp?
        let seleccion = SeleccionPila()
        if clave.hasPrefix("carpeta:") {
            let ruta = String(clave.dropFirst("carpeta:".count))
            let m = ModeloCarpeta(ruta: ruta, escala: cara.pantalla.backingScaleFactor)
            m.alCambiar = { [weak self, weak cara] in
                guard let self, let cara else { return }
                self.ultimaCuenta[ruta] = m.archivos.count
                self.reajustarDesplegado(cara)
            }
            cuantos = ultimaCuenta[ruta] ?? CarpetaDock.columnas * CarpetaDock.filasVisibles
            contenido = AnyView(PanelCarpetaVista(modelo: m, tonos: cara.datos.tonos, seleccion: seleccion))
            m.abrir()
            modelo = m
        } else if clave.hasPrefix("grupo:") || clave == "abiertas" {
            let esAbiertas = clave == "abiertas"
            let nombre = esAbiertas ? "Abiertas" : String(clave.dropFirst("grupo:".count))
            apps = esAbiertas ? e.abiertasNoFijas : e.appsDelGrupo(nombre)
            e.pedirIconos(de: apps)
            cuantos = apps.count
            contenido = AnyView(PanelGrupoVista(nombre: nombre, apps: apps, estado: e, tonos: cara.datos.tonos, seleccion: seleccion,
                                                subtitulo: esAbiertas ? "\(apps.count) abiertas · toca una para traerla al frente" : nil))
        } else if clave.hasPrefix("ventanas:") {
            let id = String(clave.dropFirst("ventanas:".count))
            guard let app = e.appsVisibles.first(where: { $0.id == id }) else { return }
            let m = ModeloVentanasApp(app: app)
            m.alCambiar = { [weak self, weak cara] in if let cara { self?.reajustarDesplegado(cara) } }
            e.pedirIconos(de: [app])
            m.cargar()
            ventanas = m
            contenido = AnyView(PanelVentanasVista(modelo: m, estado: e, tonos: cara.datos.tonos, alElegir: { [weak self, weak cara] in if let cara { self?.cerrarDesplegado(cara) } }))
        } else {
            return
        }
        let host = VistaPrimerClic(rootView: contenido)
        host.autoresizingMask = [.width, .height]
        let sensor = SensorDock()
        sensor.alEntrar = { [weak self, weak cara] in if let cara, let s = self { s.aplicar(cara, cara.politica.punteroEntra(.panel)) } }
        sensor.alSalir = { [weak self, weak cara] in
            guard let cara, let s = self else { return }
            s.aplicar(cara, cara.politica.punteroSale(.panel))
            if clave.hasPrefix("ventanas:") { s.programarCierreVentanas(cara) }
        }
        sensor.addSubview(host)
        let panel = nuevoPanelDock(nivel: 1, teclas: true)
        panel.contentView = sensor
        let d = Desplegado(clave: clave, panel: panel, sensor: sensor, host: host, modelo: modelo, cuantos: cuantos, seleccion: seleccion, apps: apps, ventanas: ventanas)
        cara.desplegado = d
        e.desplegado = clave
        (panel as? PanelPila)?.alTecla = { [weak self, weak cara, weak d] evento in
            guard let self, let cara, let d else { return false }
            return MainActor.assumeIsolated { self.tecla(evento, cara: cara, d: d) }
        }
        colocarDesplegado(cara, d, ancla: ancla, barra: barra)
        panel.orderFrontRegardless()
        panel.makeKey()
        instalarMonitor()
    }

    private var anclaDesplegado: CGFloat = 0
    private var esperaVentanas: DispatchWorkItem?
    private var cierreVentanas: DispatchWorkItem?
    private var appVentanas: (id: String, ancla: CGFloat)?

    // MARK: Ventanas de una app

    /// El puntero llegó a una app abierta: tras `PanelVentanasDock.espera` segundos sin irse, sale su panel (o ya, desde el menú).
    private func programarVentanas(_ app: EntradaApp, ancla: CGFloat, ya: Bool) {
        cierreVentanas?.cancel()
        esperaVentanas?.cancel()
        appVentanas = (app.id, ancla)
        let clave = "ventanas:" + app.id
        guard estado?.desplegado != clave else { return }
        let tarea = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons == 0 || ya else { return }
                self.desplegar(clave, ancla: ancla)
            }
        }
        esperaVentanas = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + (ya ? 0 : PanelVentanasDock.espera), execute: tarea)
    }

    /// El puntero salió del icono: si hay un panel de ventanas abierto, se cierra si tampoco está sobre él.
    private func cancelarVentanas() {
        esperaVentanas?.cancel()
        if let cara = caraBajoPuntero() { programarCierreVentanas(cara) }
    }

    private func programarCierreVentanas(_ cara: Cara) {
        guard let d = cara.desplegado, d.ventanas != nil else { return }
        cierreVentanas?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara, let d = cara.desplegado, d.ventanas != nil, let barra = cara.barra else { return }
                let p = NSEvent.mouseLocation
                let sobrePanel = NSMouseInRect(p, d.panel.frame.insetBy(dx: AuroraDock.panelMargen - 4, dy: AuroraDock.panelMargen - 4), false)
                let tile = NSRect(x: barra.frame.minX + self.anclaDesplegado - 48, y: barra.frame.minY, width: 96, height: barra.frame.height + 20)
                if !sobrePanel && !NSMouseInRect(p, tile, false) { self.cerrarDesplegado(cara) }
            }
        }
        cierreVentanas = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: tarea)
    }

    private func colocarDesplegado(_ cara: Cara, _ d: Desplegado, ancla: CGFloat, barra: NSPanel) {
        anclaDesplegado = ancla
        let aire = AuroraDock.panelMargen
        let medidas = d.medidas
        let ancho = medidas.width + 2 * aire
        let alto = medidas.height + 2 * aire
        let marco = cara.pantalla.frame
        let x = min(max(barra.frame.minX + ancla - ancho / 2, marco.minX + 8 - aire), marco.maxX - ancho - 8 + aire)
        let y = (cara.selector?.frame.maxY ?? barra.frame.maxY) - AuroraDock.margenSombra + 8 - aire
        d.panel.setFrame(NSRect(x: x, y: y, width: ancho, height: min(alto, marco.maxY - y)), display: true)
    }

    /// Cuando cambia la cantidad de elementos (la carpeta se llenó o se vació) el panel cambia de alto, quieto por abajo.
    private func reajustarDesplegado(_ cara: Cara) {
        guard let d = cara.desplegado, let barra = cara.barra else { return }
        if let m = d.modelo { d.cuantos = m.archivos.count }
        colocarDesplegado(cara, d, ancla: anclaDesplegado, barra: barra)
    }

    private func cerrarDesplegado(_ cara: Cara) {
        guard let d = cara.desplegado else { return }
        cara.desplegado = nil
        estado?.desplegado = nil
        VistaRapidaDock.compartida.soltar()
        d.cerrar()
        aplicar(cara, cara.politica.punteroSale(.panel))
        if !caras.values.contains(where: { $0.desplegado != nil }) { quitarMonitor() }
    }

    // MARK: Teclado del panel

    /// Flechas mueven la selección, Espacio abre la Vista rápida, Retorno abre, Esc cierra. Devuelve si la tecla se atendió.
    private func tecla(_ evento: NSEvent, cara: Cara, d: Desplegado) -> Bool {
        let total = d.modelo?.archivos.count ?? d.apps.count
        let columnas = d.modo == .abanico ? 1 : AuroraDock.panelColumnas
        func mover(_ paso: NavegacionPanel.Paso) -> Bool {
            d.seleccion.indice = NavegacionPanel.mover(d.seleccion.indice, paso: paso, total: total, columnas: columnas, abanico: d.modo == .abanico)
            return true
        }
        if d.ventanas != nil { if evento.keyCode == 53 { cerrarDesplegado(cara); return true }; return false }
        switch evento.keyCode {
        case 53:   // Esc
            cerrarDesplegado(cara)
            return true
        case 123: return mover(.izquierda)
        case 124: return mover(.derecha)
        case 125: return mover(.abajo)
        case 126: return mover(.arriba)
        case 49:   // Espacio: Vista rápida del archivo elegido
            guard let m = d.modelo, !m.archivos.isEmpty else { return true }
            if d.seleccion.indice == nil { d.seleccion.indice = 0 }
            let i = d.seleccion.indice ?? 0
            let urls = m.archivos.map { URL(fileURLWithPath: $0.ruta) }
            VistaRapidaDock.compartida.alCerrar = { [weak self, weak d, weak cara] indice in
                MainActor.assumeIsolated {
                    d?.seleccion.indice = indice
                    d?.panel.makeKey()
                    if let cara { self?.aplicar(cara, cara.politica.menu(abierto: false)) }
                }
            }
            if VistaRapidaDock.compartida.visible { VistaRapidaDock.compartida.cerrar() } else {
                aplicar(cara, cara.politica.menu(abierto: true))   // mientras se ve, el Dock no se esconde
                VistaRapidaDock.compartida.mostrar(urls, actual: i)
            }
            return true
        case 36, 76:   // Retorno
            guard let i = d.seleccion.indice else { return true }
            if let m = d.modelo, m.archivos.indices.contains(i) {
                AccionArchivo.abrir(m.archivos[i])
                cerrarDesplegado(cara)
            } else if d.apps.indices.contains(i) {
                AppsAbiertasDock.abrir(d.apps[i])
                cerrarDesplegado(cara)
            }
            return true
        default: return false
        }
    }

    /// Un clic en cualquier otra app cierra el panel desplegado (los clics dentro de nuestras ventanas no llegan a este monitor).
    private func instalarMonitor() {
        guard monitorClics == nil else { return }
        monitorClics = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.caras.values.forEach { self?.cerrarDesplegado($0) } } }
        }
    }

    private func quitarMonitor() {
        if let m = monitorClics { NSEvent.removeMonitor(m) }
        monitorClics = nil
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func agregar(_ titulo: String, _ marcado: Bool, _ accion: Selector) {
            let i = NSMenuItem(title: titulo, action: accion, keyEquivalent: "")
            i.target = self
            i.state = marcado ? .on : .off
            menu.addItem(i)
        }
        let modo = Ajustes.dockVisibilidad
        agregar("Al tocar el borde de abajo", modo == .alTocarBorde, #selector(elegirBorde))
        agregar("Siempre visible", modo == .siempre, #selector(elegirSiempre))
        menu.addItem(.separator())
        agregar("En todas las pantallas", !Ajustes.dockSoloPrincipal, #selector(elegirTodas))
        agregar("Solo en la principal", Ajustes.dockSoloPrincipal, #selector(elegirPrincipal))
        menu.addItem(.separator())
        agregar("Mostrar u ocultar  (Hyper + O)", false, #selector(alternarDesdeMenu))
        menu.addItem(.separator())
        agregar("Ocultar el Dock del sistema", AlmacenDockDefaults().interruptor, #selector(alternarDockSistema))
    }

    @objc private func elegirBorde() { Ajustes.dockVisibilidad = .alTocarBorde; montar() }
    @objc private func elegirSiempre() { Ajustes.dockVisibilidad = .siempre; montar() }
    @objc private func elegirTodas() { Ajustes.dockSoloPrincipal = false; montar() }
    @objc private func elegirPrincipal() { Ajustes.dockSoloPrincipal = true; montar() }
    @objc private func alternarDesdeMenu() { alternarAtajo() }
    /// Ocultar el Dock del sistema (solo con este Dock encendido, que es cuando existe el menú): guarda cómo estaba, lo oculta y lo reinicia;
    /// al apagarlo (o al quitar la función) lo deja exactamente como estaba.
    @objc private func alternarDockSistema() {
        guard encendido else { return }
        let encendidoYa = AlmacenDockDefaults().interruptor
        tocarDockSistema { _ = encendidoYa ? $0.restaurar() : $0.encender() }
    }
}
