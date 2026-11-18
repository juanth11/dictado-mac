import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictadoKit
import os

private let log = Logger(subsystem: "app.dictado", category: "velo")

// Velo: desenfoca todo menos la ventana que estás usando. No cierra ni mueve nada.
//
// Cómo funciona: una ventana por pantalla (`PanelVelo`), a nivel normal, que se coloca justo DEBAJO de la ventana
// enfocada de la app al frente en el orden global de ventanas (`order(.below, relativeTo:)`). Todo lo que queda por
// debajo (otras ventanas y el escritorio) se ve desenfocado; la ventana activa y lo que esté por encima (menús, Dock,
// avisos) se ve nítido. La decisión de debajo de cuál ventana va (`DecisionVelo`) es lógica pura y se prueba en DictadoKit.
//
// Cuándo se reordena (solo por eventos, sin temporizadores de sondeo): al activarse otra app, al cambiar la ventana
// enfocada o crearse una en la app al frente (observador de Accesibilidad), al ocultarse o cerrarse una app, al cambiar
// de Space y al cambiar la configuración de pantallas. Varios avisos seguidos se juntan en una sola revisión.
//
// Cómo se enciende: ⌃⌥⌘⇧ + B (Hyper + B), el menú o sacudir el ratón (si está activado). Hyper + G cambia de modo.
// Hyper + J (mantenida) o ⇧ + sacudida levanta el velo mientras la mantienes. Por dentro: `Velo.encender(modo:)`,
// `Velo.apagar()`, `Velo.alternar()` y `Velo.estado`, para que otras partes (el bloque de foco, un espacio del Dock) lo usen.
//
// Apagado por defecto (Funciones). Ajustes en el dominio app.dictado:
//   defaults write app.dictado velo.modo ambiente|profundo
//   defaults write app.dictado velo.desenfoque -float 0.8     (0 a 1; sin poner, según el modo)
//   defaults write app.dictado velo.tinte "1B2A4A"            (color RRGGBB; sin poner, negro)
//   defaults write app.dictado velo.opacidadTinte -float 0.3  (0 a 0.8; sin poner, según el modo)
//   defaults write app.dictado velo.grano -float 0.1          (0 a 0.3; sin poner, según el modo)
//   defaults write app.dictado velo.todaLaApp -bool true      (todas las ventanas de la app activa quedan nítidas)
//   defaults write app.dictado velo.grupos -array "com.apple.Safari,com.apple.Notes"   (apps que quedan nítidas juntas)
//   defaults write app.dictado velo.ignoradas -array "com.apple.Spotlight"             (con estas al frente, el velo se apaga)
//   defaults write app.dictado velo.pantallas todas|activa
//   defaults write app.dictado velo.ocultarEnSistema -bool false   (no ocultar en Mission Control ni en pantalla completa)
//   defaults write app.dictado velo.sacudir -bool false            (no encender con la sacudida del ratón)
//   defaults write app.dictado velo.sensibilidad -float 0.5        (0 a 1)
//   defaults write app.dictado velo.duranteFoco -bool true         (encenderlo durante un bloque de foco)

enum ModoVelo: String, CaseIterable {
    case ambiente, profundo

    var nombre: String { self == .ambiente ? "Ambiente (desenfoque suave)" : "Profundo (fuerte, oscuro, con grano)" }
    var siguiente: ModoVelo { self == .ambiente ? .profundo : .ambiente }
}

enum EstadoVelo: Equatable {
    case apagado
    case encendido(ModoVelo)
}

/// Los ajustes del velo, leídos al momento del dominio app.dictado.
struct OpcionesVelo {
    private let d = UserDefaults.dictado

    static let ignoradasDeFabrica = ["com.apple.screencaptureui", "com.apple.loginwindow", "com.apple.Spotlight"]

    var modo: ModoVelo { ModoVelo(rawValue: d.string(forKey: "velo.modo") ?? "") ?? .ambiente }
    func guardar(modo: ModoVelo) { d.set(modo.rawValue, forKey: "velo.modo") }

    private func numero(_ clave: String, _ rango: ClosedRange<Double>) -> Double? {
        guard d.object(forKey: clave) != nil else { return nil }
        return min(max(d.double(forKey: clave), rango.lowerBound), rango.upperBound)
    }

    var desenfoque: Double? { numero("velo.desenfoque", 0...1) }
    var opacidadTinte: Double? { numero("velo.opacidadTinte", 0...0.8) }
    var grano: Double? { numero("velo.grano", 0...0.3) }
    var tinteHex: String { d.string(forKey: "velo.tinte") ?? "000000" }
    var todaLaApp: Bool { d.bool(forKey: "velo.todaLaApp") }
    var soloPantallaActiva: Bool { d.string(forKey: "velo.pantallas") == "activa" }
    var ocultarEnSistema: Bool { d.object(forKey: "velo.ocultarEnSistema") as? Bool ?? true }
    var sacudir: Bool { d.object(forKey: "velo.sacudir") as? Bool ?? true }
    var sensibilidad: Double { numero("velo.sensibilidad", 0...1) ?? 0.5 }
    var duranteFoco: Bool { d.bool(forKey: "velo.duranteFoco") }
    var grupos: [Set<String>] {
        (d.stringArray(forKey: "velo.grupos") ?? []).map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
            .filter { $0.count > 1 }
    }
    var ignoradas: [String] { d.stringArray(forKey: "velo.ignoradas") ?? Self.ignoradasDeFabrica }

    func poner(_ clave: String, _ valor: Any?) {
        if let valor { d.set(valor, forKey: clave) } else { d.removeObject(forKey: clave) }
    }

    var paraDecision: AjustesVelo {
        AjustesVelo(todaLaApp: todaLaApp, grupos: grupos, ignoradas: Set(ignoradas), ocultarEnPantallaCompleta: ocultarEnSistema)
    }

    /// Modo + ajustes → lo que se pinta.
    func aspecto(modo: ModoVelo) -> AspectoVelo {
        let profundo = modo == .profundo
        let fuerza = desenfoque ?? (profundo ? 1.0 : 0.5)
        return AspectoVelo(material: profundo ? .hudWindow : .underWindowBackground, oscuro: profundo,
                           fuerzaDesenfoque: CGFloat(0.35 + 0.65 * fuerza), tinte: Self.color(hex: tinteHex),
                           opacidadTinte: CGFloat(opacidadTinte ?? (profundo ? 0.35 : 0.12)), grano: CGFloat(grano ?? (profundo ? 0.08 : 0)))
    }

    static func color(hex: String) -> NSColor {
        let limpio = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).prefix(6)
        guard limpio.count == 6, let v = UInt32(limpio, radix: 16) else { return .black }
        return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

@MainActor
final class Velo: NSObject, NSMenuDelegate {
    static let shared = Velo()

    // MARK: API para el resto de la app

    static var estado: EstadoVelo { shared.estado }
    static func encender(modo: ModoVelo? = nil) { shared.encender(modo: modo) }
    static func apagar() { shared.apagar() }
    static func alternar() { shared.alternar() }

    /// La línea de `App.instalarModulos()`: guarda el contexto y deja el módulo vivo.
    static func instalar(_ contexto: ContextoModulos) -> Velo {
        shared.contexto = contexto
        shared.arrancar()
        return shared
    }

    /// El elemento del menú de la barra (con su submenú).
    static var itemMenu: NSMenuItem { shared.item }

    private(set) var estado: EstadoVelo = .apagado
    private var contexto: ContextoModulos?
    private var opciones = OpcionesVelo()
    private var arrancado = false
    private var paneles: [CGDirectDisplayID: PanelVelo] = [:]
    /// Pantallas donde el velo debe verse ahora (el resto se desvanece).
    private var visibles: Set<CGDirectDisplayID> = []
    private var espiando = false
    private var encendidoPorFoco = false
    private var pendiente: DispatchWorkItem?

    // Observadores
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var observadorAX: AXObserver?
    private var pidObservado: pid_t = 0
    private var monitorRaton: Any?
    private var monitorModificadores: Any?
    private var detector = DetectorSacudida()
    private var atajosPuestos = false

    private enum Atajo: UInt32, CaseIterable { case alternar = 60, modo = 61, espiar = 62 }

    private let menu = NSMenu()
    private lazy var item: NSMenuItem = {
        let i = NSMenuItem(title: "Velo (desenfocar lo demás)", action: nil, keyEquivalent: "")
        menu.delegate = self
        i.submenu = menu
        return i
    }()

    // MARK: Ciclo de vida del módulo

    private func arrancar() {
        guard !arrancado else { return }
        arrancado = true
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.velo.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        NotificationCenter.default.addObserver(forName: .focoCambio, object: nil, queue: .main) { [weak self] nota in
            let activo = nota.userInfo?["activo"] as? Bool ?? false
            MainActor.assumeIsolated { self?.alCambiarFoco(activo) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apagar(animado: false) }
        }
        sincronizar()
        // Si la app se reinició con un bloque de foco en curso, el velo vuelve.
        if Funcion.velo.activa, opciones.duranteFoco, UserDefaults.dictado.data(forKey: "foco.activo") != nil { alCambiarFoco(true) }
    }

    private func sincronizar() {
        if Funcion.velo.activa {
            registrarAtajos()
            actualizarMonitorRaton()
        } else {
            apagar()
            quitarAtajos()
            quitarMonitorRaton()
        }
    }

    // MARK: Encender y apagar

    func alternar() {
        if case .encendido = estado { apagar() } else { encender() }
    }

    func encender(modo: ModoVelo? = nil) {
        guard Funcion.velo.activa else {
            contexto?.avisar("El velo está apagado en Funciones", "circle.lefthalf.filled", nil)
            return
        }
        if let modo { opciones.guardar(modo: modo) }
        opciones = OpcionesVelo()
        let m = opciones.modo
        let yaEncendido = estado != .apagado
        estado = .encendido(m)
        crearPaneles()
        aplicarAspecto()
        if !yaEncendido { instalarObservadores() }
        espiando = false
        revisar(animado: true)
    }

    func apagar() { apagar(animado: true) }

    private func apagar(animado: Bool) {
        guard estado != .apagado else { return }
        estado = .apagado
        encendidoPorFoco = false
        pendiente?.cancel()
        quitarObservadores()
        quitarMonitorModificadores()
        espiando = false
        desvanecer(Set(paneles.keys), animado: animado)
    }

    private func cambiarModo() {
        let nuevo = (estado == .apagado ? opciones.modo : opciones.modo.siguiente)
        encender(modo: nuevo)
        contexto?.avisar("Velo · \(nuevo == .ambiente ? "Ambiente" : "Profundo")", "circle.lefthalf.filled", nil)
    }

    // MARK: Ventanas del velo

    private func crearPaneles() {
        let pantallas = NSScreen.screens
        let ids = Set(pantallas.map(\.numeroDeVista))
        for (id, p) in paneles where !ids.contains(id) {
            p.orderOut(nil)
            paneles[id] = nil
        }
        for s in pantallas {
            let id = s.numeroDeVista
            if let p = paneles[id] {
                if p.frame != s.frame { p.setFrame(s.frame, display: false) }
            } else {
                paneles[id] = PanelVelo(pantalla: s)
            }
        }
    }

    private func aplicarAspecto() {
        guard case .encendido(let modo) = estado else { return }
        let a = opciones.aspecto(modo: modo)
        paneles.values.forEach { $0.aplicar(a) }
    }

    /// Se llama desde el menú tras cambiar un ajuste.
    private func ajusteCambio() {
        opciones = OpcionesVelo()
        if case .encendido = estado {
            if case .encendido(let m) = estado, m != opciones.modo { estado = .encendido(opciones.modo) }
            aplicarAspecto()
            revisar(animado: false)
        }
        actualizarMonitorRaton()
    }

    // MARK: Decidir y colocar

    /// Mira el orden de ventanas, decide y pone el velo (o lo oculta). Barato: una lista de ventanas y una lectura de AX.
    private func revisar(animado: Bool) {
        guard estado != .apagado, !espiando else { return }
        let propias = Set(paneles.values.map { UInt32($0.windowNumber) })
        let ventanas = Self.listarVentanas(excluyendo: propias)
        let app = NSWorkspace.shared.frontmostApplication
        var enfocado: CGRect?
        var completa = false
        if let app, AXIsProcessTrusted() {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.2)
            if let v = AX.elemento(ax, kAXFocusedWindowAttribute) ?? AX.elemento(ax, kAXMainWindowAttribute) {
                enfocado = AX.marco(v)
                completa = AX.bool(v, "AXFullScreen") == true
            }
        }
        let bundle = app?.bundleIdentifier
        let enMision = opciones.ocultarEnSistema && ["com.apple.dock", "com.apple.exposelauncher", "com.apple.launchpad.launcher"].contains(bundle ?? "")
        let situacion = SituacionVelo(bundleAlFrente: bundle, marcoEnfocado: enfocado, pantallaCompleta: completa, misionControl: enMision)
        switch DecisionVelo.plan(ventanas: ventanas, situacion: situacion, ajustes: opciones.paraDecision) {
        case .ocultar:
            desvanecer(Set(paneles.keys), animado: animado)
        case .debajoDe(let id, let marco):
            colocar(debajoDe: id, marco: marco, animado: animado)
        }
    }

    private func colocar(debajoDe id: UInt32, marco: CGRect, animado: Bool) {
        var destino = Set(paneles.keys)
        if opciones.soloPantallaActiva {
            let mejor = NSScreen.screens.max { $0.marcoCG.intersection(marco).area < $1.marcoCG.intersection(marco).area }
            if let mejor, mejor.marcoCG.intersection(marco).area > 0 { destino = [mejor.numeroDeVista] }
        }
        for (pantalla, panel) in paneles {
            guard destino.contains(pantalla) else { continue }
            let eraVisible = visibles.contains(pantalla) && panel.isVisible
            panel.order(.below, relativeTo: Int(id))
            if !eraVisible { aparecer(panel, animado: animado) }
        }
        desvanecer(Set(paneles.keys).subtracting(destino), animado: animado)
        visibles = destino
    }

    private func aparecer(_ panel: PanelVelo, animado: Bool) {
        animarAlfa(panel, a: 1, animado: animado, entrada: true)
    }

    private func desvanecer(_ pantallas: Set<CGDirectDisplayID>, animado: Bool) {
        visibles.subtract(pantallas)
        for id in pantallas {
            guard let panel = paneles[id], panel.isVisible else { continue }
            animarAlfa(panel, a: 0, animado: animado, entrada: false) { [weak self] in
                // Si mientras tanto volvió a pedirse, no se esconde.
                guard let self, !self.visibles.contains(id) else { return }
                panel.orderOut(nil)
            }
        }
    }

    /// Cuánto dura y con qué curva: 0,25 s con suavizado; con Reducir movimiento, un fundido corto y lineal.
    private func animarAlfa(_ panel: PanelVelo, a alfa: CGFloat, animado: Bool, entrada: Bool, alTerminar: (@MainActor () -> Void)? = nil) {
        guard animado else {
            panel.alphaValue = alfa
            alTerminar?()
            return
        }
        let reducir = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reducir ? 0.12 : (espiando ? (entrada ? 0.3 : 0.18) : 0.25)
            ctx.timingFunction = CAMediaTimingFunction(name: reducir ? .linear : .easeInEaseOut)
            panel.animator().alphaValue = alfa
        }, completionHandler: { MainActor.assumeIsolated { alTerminar?() } })
    }

    /// Lista de ventanas en pantalla, de adelante hacia atrás. Sin permiso de Grabación de pantalla macOS entrega
    /// igualmente dueño, capa, marco y número, que es todo lo que hace falta.
    static func listarVentanas(excluyendo propias: Set<UInt32>) -> [VentanaMundo] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var bundles: [pid_t: String?] = [:]
        var lista: [VentanaMundo] = []
        for w in info {
            guard let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value, !propias.contains(id),
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let caja = w[kCGWindowBounds as String] as? NSDictionary,
                  let marco = CGRect(dictionaryRepresentation: caja) else { continue }
            if bundles[pid] == nil { bundles[pid] = .some(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) }
            lista.append(VentanaMundo(id: id, pid: pid, bundle: bundles[pid] ?? nil, capa: (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                      marco: marco, alfa: (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1))
        }
        return lista
    }

    // MARK: Observadores (solo mientras el velo está encendido)

    private func instalarObservadores() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        func escuchar(_ centro: NotificationCenter, _ nombre: Notification.Name, retraso: Double = 0.03, alActivar: Bool = false) {
            let t = centro.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if alActivar { self?.observarAppAlFrente() }
                    self?.programar(en: retraso)
                }
            }
            tokens.append((centro, t))
        }
        escuchar(ws, NSWorkspace.didActivateApplicationNotification, alActivar: true)
        escuchar(ws, NSWorkspace.didHideApplicationNotification)
        escuchar(ws, NSWorkspace.didUnhideApplicationNotification)
        escuchar(ws, NSWorkspace.didTerminateApplicationNotification)
        escuchar(ws, NSWorkspace.activeSpaceDidChangeNotification, retraso: 0.15)
        let t = nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.crearPaneles()
                self?.aplicarAspecto()
                self?.programar(en: 0.2)
            }
        }
        tokens.append((nc, t))
        observarAppAlFrente()
    }

    private func quitarObservadores() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens = []
        soltarObservadorAX()
    }

    /// Junta varios avisos seguidos en una sola revisión.
    private func programar(en segundos: Double = 0.03) {
        guard estado != .apagado else { return }
        pendiente?.cancel()
        let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.revisar(animado: true) } }
        pendiente = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: tarea)
    }

    /// Observa la app al frente por Accesibilidad: cambio de ventana enfocada, ventana nueva, ventana minimizada.
    private func observarAppAlFrente() {
        soltarObservadorAX()
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return }
        var obs: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let yo = Unmanaged<Velo>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { yo.programar() }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &obs) == .success, let obs else { return }
        let elemento = AXUIElementCreateApplication(app.processIdentifier)
        for n in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXApplicationHiddenNotification,
                  kAXApplicationShownNotification] {
            AXObserverAddNotification(obs, elemento, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observadorAX = obs
        pidObservado = app.processIdentifier
    }

    private func soltarObservadorAX() {
        if let obs = observadorAX { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes) }
        observadorAX = nil
        pidObservado = 0
    }

    // MARK: Sacudida del ratón

    /// El monitor global de movimiento solo existe mientras la función y la opción de sacudir estén encendidas.
    private func actualizarMonitorRaton() {
        guard Funcion.velo.activa, opciones.sacudir else { return quitarMonitorRaton() }
        detector = DetectorSacudida(config: .sensibilidad(opciones.sensibilidad))
        guard monitorRaton == nil else { return }
        monitorRaton = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] evento in
            let punto = NSEvent.mouseLocation
            let t = evento.timestamp
            MainActor.assumeIsolated { self?.alMoverRaton(x: punto.x, y: punto.y, t: t) }
        }
    }

    private func quitarMonitorRaton() {
        if let m = monitorRaton { NSEvent.removeMonitor(m) }
        monitorRaton = nil
    }

    private func alMoverRaton(x: Double, y: Double, t: Double) {
        guard detector.alimentar(x: x, y: y, t: t) else { return }
        if estado != .apagado, NSEvent.modifierFlags.contains(.shift) {
            empezarEspiar(soltandoConShift: true)
        } else {
            alternar()
        }
    }

    // MARK: Espiar (levantar el velo mientras lo mantienes)

    private func empezarEspiar(soltandoConShift: Bool) {
        guard estado != .apagado, !espiando else { return }
        espiando = true
        pendiente?.cancel()
        desvanecer(Set(paneles.keys), animado: true)
        if soltandoConShift {
            monitorModificadores = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in
                MainActor.assumeIsolated {
                    if !NSEvent.modifierFlags.contains(.shift) { self?.terminarEspiar() }
                }
            }
        }
    }

    private func terminarEspiar() {
        quitarMonitorModificadores()
        guard espiando else { return }
        // Los paneles vuelven con la misma animación pero ya sin el modo "espiando" para la duración de salida.
        espiando = false
        revisar(animado: true)
    }

    private func quitarMonitorModificadores() {
        if let m = monitorModificadores { NSEvent.removeMonitor(m) }
        monitorModificadores = nil
    }

    // MARK: Bloque de foco

    private func alCambiarFoco(_ activo: Bool) {
        guard Funcion.velo.activa, opciones.duranteFoco else { return }
        if activo {
            if estado == .apagado {
                encender()
                encendidoPorFoco = estado != .apagado
            }
        } else if encendidoPorFoco {
            apagar()
        }
    }

    // MARK: Atajos (Hyper + B / G / J)

    private func registrarAtajos() {
        guard !atajosPuestos else { return }
        atajosPuestos = true
        let hyper = cmdKey | optionKey | controlKey | shiftKey
        var ocupados: [String] = []
        if !Atajos.shared.registrar(id: Atajo.alternar.rawValue, tecla: kVK_ANSI_B, modificadores: hyper, alPresionar: { [weak self] in self?.alternar() }) {
            ocupados.append("B")
        }
        if !Atajos.shared.registrar(id: Atajo.modo.rawValue, tecla: kVK_ANSI_G, modificadores: hyper, alPresionar: { [weak self] in self?.cambiarModo() }) {
            ocupados.append("G")
        }
        if !Atajos.shared.registrar(id: Atajo.espiar.rawValue, tecla: kVK_ANSI_J, modificadores: hyper,
                                    alPresionar: { [weak self] in self?.empezarEspiar(soltandoConShift: false) },
                                    alSoltar: { [weak self] in self?.terminarEspiar() }) {
            ocupados.append("J")
        }
        if !ocupados.isEmpty { contexto?.avisar("Hyper + \(ocupados.joined(separator: ", ")) lo usa otra app", "keyboard.badge.exclamationmark", nil) }
    }

    private func quitarAtajos() {
        guard atajosPuestos else { return }
        atajosPuestos = false
        Atajo.allCases.forEach { Atajos.shared.quitar(id: $0.rawValue) }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        opciones = OpcionesVelo()
        menu.removeAllItems()
        guard Funcion.velo.activa else {
            let i = NSMenuItem(title: "Apagado: enciéndelo en Funciones → Velo", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
            return
        }
        func agregar(_ titulo: String, marcado: Bool = false, sangria: Int = 0, _ accion: @escaping () -> Void) {
            let i = NSMenuItem(title: titulo, action: #selector(ejecutarItem(_:)), keyEquivalent: "")
            i.target = self
            i.state = marcado ? .on : .off
            i.indentationLevel = sangria
            i.representedObject = AccionVelo(accion)
            menu.addItem(i)
        }
        func titulo(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        agregar(estado == .apagado ? "Encender el velo  (Hyper + B)" : "Apagar el velo  (Hyper + B)") { [weak self] in self?.alternar() }
        titulo("Modo  (Hyper + G)")
        for m in ModoVelo.allCases {
            agregar(m.nombre, marcado: opciones.modo == m, sangria: 1) { [weak self] in self?.elegirModo(m) }
        }
        titulo("Desenfoque")
        for (t, v) in [("Según el modo", Double?.none), ("Suave", 0.25), ("Medio", 0.6), ("Fuerte", 1.0)] {
            agregar(t, marcado: opciones.desenfoque == v, sangria: 1) { [weak self] in self?.fijar("velo.desenfoque", v) }
        }
        titulo("Oscuridad")
        for (t, v) in [("Según el modo", Double?.none), ("Ninguna", 0.0), ("Poca", 0.15), ("Media", 0.3), ("Mucha", 0.5)] {
            agregar(t, marcado: opciones.opacidadTinte == v, sangria: 1) { [weak self] in self?.fijar("velo.opacidadTinte", v) }
        }
        titulo("Grano")
        for (t, v) in [("Según el modo", Double?.none), ("Sin grano", 0.0), ("Poco", 0.06), ("Mucho", 0.16)] {
            agregar(t, marcado: opciones.grano == v, sangria: 1) { [weak self] in self?.fijar("velo.grano", v) }
        }
        titulo("Color del tinte")
        for (t, hex) in [("Negro", "000000"), ("Azul noche", "10203A"), ("Gris cálido", "2B2622"), ("Verde profundo", "0F2A22")] {
            agregar(t, marcado: opciones.tinteHex.uppercased() == hex, sangria: 1) { [weak self] in self?.fijar("velo.tinte", hex) }
        }
        menu.addItem(.separator())
        agregar("Mantener nítida toda la app activa", marcado: opciones.todaLaApp) { [weak self] in
            guard let self else { return }
            self.fijar("velo.todaLaApp", !self.opciones.todaLaApp)
        }
        agregar("Solo en la pantalla de la ventana activa", marcado: opciones.soloPantallaActiva) { [weak self] in
            guard let self else { return }
            self.fijar("velo.pantallas", self.opciones.soloPantallaActiva ? "todas" : "activa")
        }
        agregar("Ocultar en Mission Control y pantalla completa", marcado: opciones.ocultarEnSistema) { [weak self] in
            guard let self else { return }
            self.fijar("velo.ocultarEnSistema", !self.opciones.ocultarEnSistema)
        }
        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, app.processIdentifier != getpid() {
            let ignorada = opciones.ignoradas.contains(id)
            agregar("Sin velo con \(app.localizedName ?? id) al frente", marcado: ignorada) { [weak self] in
                guard let self else { return }
                var lista = self.opciones.ignoradas
                if ignorada { lista.removeAll { $0 == id } } else { lista.append(id) }
                self.fijar("velo.ignoradas", lista)
            }
        }
        menu.addItem(.separator())
        agregar("Encender con la sacudida del ratón", marcado: opciones.sacudir) { [weak self] in
            guard let self else { return }
            self.fijar("velo.sacudir", !self.opciones.sacudir)
        }
        titulo("Sensibilidad de la sacudida")
        for (t, v) in [("Baja", 0.2), ("Media", 0.5), ("Alta", 0.85)] {
            agregar(t, marcado: abs(opciones.sensibilidad - v) < 0.1, sangria: 1) { [weak self] in self?.fijar("velo.sensibilidad", v) }
        }
        agregar("Encender durante un bloque de foco", marcado: opciones.duranteFoco) { [weak self] in
            guard let self else { return }
            self.fijar("velo.duranteFoco", !self.opciones.duranteFoco)
        }
    }

    private final class AccionVelo: NSObject {
        let accion: () -> Void
        init(_ a: @escaping () -> Void) { accion = a }
    }

    @objc private func ejecutarItem(_ i: NSMenuItem) { (i.representedObject as? AccionVelo)?.accion() }

    private func elegirModo(_ m: ModoVelo) {
        opciones.guardar(modo: m)
        if estado != .apagado { encender(modo: m) } else { ajusteCambio() }
    }

    private func fijar(_ clave: String, _ valor: Any?) {
        opciones.poner(clave, valor)
        ajusteCambio()
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
