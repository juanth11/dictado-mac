import AppKit
import DictadoKit
import Observation
import SwiftUI

/// El centro de mando como un espacio (CentroEspacio.swift): una ventana sin marco que cubre la pantalla con tu fondo
/// de pantalla y, encima, las ventanas de vidrio de cada sección: Hoy, Metas, Orquesta e Inbox.
/// Lee el estado con el comando configurado (CentroDatos.swift) al abrirse y cada 5 minutos mientras está abierto.
/// Se crea al abrirlo y se suelta al cerrarlo: cerrado no ocupa memoria ni corre nada. Se cierra con esc, ⌘W, la ×
/// o al irte a otra app (como Launchpad), y entonces vuelve la app que estaba al frente.
/// Atajos: ⌘1 Hoy · ⌘2 Metas · ⌘3 Orquesta · ⌘4 Inbox · ⌘R actualizar · esc o ⌘W cerrar.
///
/// Por omisión abre el Centro nuevo (CentroAurora.swift): Tablero, Semana, Reuniones y Mac en el lenguaje de la isla, con ⌘1 a ⌘4, ⌘R,
/// las flechas en las listas, esc o ⌘W. Se lee solo una vez por minuto mientras está a la vista y, al cerrar, suelta ventana, vistas y datos
/// propios (como el lanzador y el Dock). `defaults write app.dictado centro.clasico -bool true` trae de vuelta el de arriba, sin cambios.
@MainActor
final class Centro: NSObject, NSWindowDelegate {
    @MainActor @Observable
    final class Navegacion {
        var seccion = SeccionCentro.hoy
    }

    private let store = CentroStore()
    private let navegacion = Navegacion()
    /// Las sesiones de Claude Code: las de la isla si está encendida; si no, unas propias mientras la ventana vive.
    private let claudeIsla: SesionesClaude?
    private var claudePropio: SesionesClaude?
    private var ventana: NSWindow?
    private var reloj: Timer?
    private var monitor: Any?
    /// Qué Centro abrió esta ventana (el ajuste se lee al abrir; cambiarlo con la ventana abierta vale desde la siguiente).
    private var clasico = false
    // El Centro nuevo: sus datos, su navegación y la vista de SwiftUI de la ventana (se guarda para vaciarla al cerrar).
    private let isla: (() -> Isla?)?
    private let salud: Salud?
    private var datos: DatosCentro?
    private var propios: DatosCentro?
    private var navegacionAurora: NavegacionAurora?
    private var anfitrion: NSHostingView<AnyView>?
    /// El fondo de pantalla que pinta el Centro (el mismo del lanzador): se lee al abrir y se suelta al cerrar.
    private var escritorio: FondoEscritorio?
    private var observadorPantallas: NSObjectProtocol?
    private var cierre: DispatchWorkItem?
    /// Datos de otra procedencia (las pruebas): sin ellos, los de la isla o unos propios.
    private let datosDePrueba: (() -> DatosCentro)?
    /// La app que estaba al frente al abrir: a ella se vuelve al cerrar con esc, ⌘W o la ×.
    private var anterior: NSRunningApplication?
    private var cerrando = false

    /// Solo para la prueba de humo: vidrio simulado, porque el real lo compone el sistema y no sale en una foto.
    private let vidrioSimulado: Bool

    /// El bloque de foco de la app: el Centro empieza bloques desde las prioridades y marca lo que quedó hecho.
    private let foco: Foco?

    init(claude: SesionesClaude?, foco: Foco? = nil, vidrioSimulado: Bool = false, isla: (() -> Isla?)? = nil, salud: Salud? = nil,
         datosDePrueba: (() -> DatosCentro)? = nil) {
        claudeIsla = claude
        self.foco = foco
        self.vidrioSimulado = vidrioSimulado
        self.isla = isla
        self.salud = salud
        self.datosDePrueba = datosDePrueba
    }

    var abierta: Bool { ventana?.isVisible == true }
    var cargando: Bool { store.cargando }

    func abrir(_ seccion: SeccionCentro? = nil) {
        if ventana == nil { clasico = UserDefaults.dictado.bool(forKey: "centro.clasico") }
        if clasico { abrirClasico(seccion) } else { abrirAurora() }
    }

    private func abrirClasico(_ seccion: SeccionCentro?) {
        if let seccion { navegacion.seccion = seccion }
        if claudeIsla == nil && claudePropio == nil { claudePropio = SesionesClaude() }
        let nueva = ventana == nil
        if nueva, let frontal = NSWorkspace.shared.frontmostApplication, frontal != NSRunningApplication.current { anterior = frontal }
        let v = ventana ?? crearVentana()
        ventana = v
        NSApp.activate(ignoringOtherApps: true)
        if nueva && !vidrioSimulado {
            v.alphaValue = 0
            v.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.22
                v.animator().alphaValue = 1
            }
        } else {
            v.makeKeyAndOrderFront(nil)
        }
        store.actualizar()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.actualizar() }
        }
        instalarAtajos()
    }

    /// Cierra el espacio. `devolver`: vuelve a la app que estaba al frente (no al irte tú a otra app).
    func cerrar(devolver: Bool = true) {
        guard let v = ventana, !cerrando else { return }
        cerrando = true
        let app = devolver ? anterior : nil
        if !clasico {
            // Un fundido corto hecho por SwiftUI (sin animador de la ventana, que se queda con ella) y, pasado, se suelta todo.
            navegacionAurora?.saliendo = true
            let tarea = DispatchWorkItem { [weak self, weak v] in
                MainActor.assumeIsolated {
                    if let v { self?.soltar(v) }
                    app?.activate()
                }
            }
            cierre = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + (vidrioSimulado ? 0 : AuroraMovimiento.fundidoCierre), execute: tarea)
            return
        }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = vidrioSimulado ? 0 : 0.14
            v.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                v.close()
                app?.activate()
            }
        })
    }

    /// Una ventana sin marco del tamaño de la pantalla donde está el puntero. La barra de menús y el Dock quedan por
    /// encima (son de otro nivel): lo que tapan se le pasa a la vista como margen.
    private func crearVentana() -> NSWindow {
        let pantalla = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let marco = pantalla.frame, util = pantalla.visibleFrame
        let v = VentanaDelEspacio(contentRect: marco, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        v.setFrame(marco, display: false)
        v.title = "Centro de mando"
        v.backgroundColor = .clear
        v.isOpaque = false
        v.hasShadow = false
        v.level = .normal
        v.appearance = NSAppearance(named: .darkAqua)
        v.isReleasedWhenClosed = false
        v.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        v.delegate = self
        let margenes = EdgeInsets(top: marco.maxY - util.maxY, leading: util.minX - marco.minX,
                                  bottom: util.minY - marco.minY, trailing: marco.maxX - util.maxX)
        let raiz = RaizCentro(store: store, navegacion: navegacion, claude: claudeIsla ?? claudePropio, foco: foco, simulado: vidrioSimulado,
                              fondo: vidrioSimulado ? fondoDeMuestra() : FondoEspacio.deEscritorio(pantalla), margenes: margenes,
                              abrir: { [weak self] destino in self?.abrir(destino: destino) },
                              cerrar: { [weak self] in self?.cerrar() })
        let anfitrion = NSHostingView(rootView: raiz)
        anfitrion.sizingOptions = []   // el tamaño lo decide la ventana (la pantalla), no el ideal de SwiftUI
        v.contentView = anfitrion
        return v
    }

    /// Ruta relativa al cerebro (el tablero de finanzas, el archivo de metas…) o un enlace web (una noticia).
    /// Solo http(s): los enlaces de las noticias son de terceros y no deben poder abrir otros esquemas.
    private func abrir(destino: String) {
        if destino.contains("://") {
            if let u = URL(string: destino), ["http", "https"].contains(u.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(u) }
            return
        }
        guard let raiz = store.estado?.local?.cerebro, !destino.contains("..") else { return }
        let url = URL(fileURLWithPath: raiz).appendingPathComponent(destino)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    private func instalarAtajos() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            nonisolated(unsafe) let e = evento
            return MainActor.assumeIsolated {
                guard let self, let v = self.ventana, v.isKeyWindow else { return e }
                if !self.clasico { return self.tecla(e) ? nil : e }
                if e.keyCode == 53 { self.cerrar(); return nil }   // esc
                guard e.modifierFlags.contains(.command) else { return e }
                switch e.charactersIgnoringModifiers {
                case "1": self.navegacion.seccion = .hoy
                case "2": self.navegacion.seccion = .metas
                case "3": self.navegacion.seccion = .orquesta
                case "4": self.navegacion.seccion = .inbox
                case "r": self.store.actualizar()
                case "w": self.cerrar()
                default: return e
                }
                return nil
            }
        }
    }

    // MARK: - El Centro nuevo (CentroAurora.swift)

    private func abrirAurora() {
        let nueva = ventana == nil
        if nueva, let frontal = NSWorkspace.shared.frontmostApplication, frontal != NSRunningApplication.current { anterior = frontal }
        if nueva { prepararAurora() }
        let v = ventana ?? crearVentanaAurora()
        ventana = v
        NSApp.activate(ignoringOtherApps: true)
        v.alphaValue = 1
        v.makeKeyAndOrderFront(nil)
        arrancarAurora()
    }

    /// Para la prueba de memoria: arma la ventana y toda su jerarquía de vistas igual que `abrir`, pero sin ordenarla al frente, sin activar
    /// la app y sin monitores ni reloj. Nada llega a la pantalla.
    func abrirSinMostrar() {
        guard ventana == nil else { return }
        clasico = false
        prepararAurora()
        ventana = crearVentanaAurora()
    }

    /// Los datos del Centro: los de la isla si está encendida; si no, unos propios que se crean UNA vez y se conservan (cada `Agenda()` o
    /// `SesionesClaude()` vivos abren el almacén de Calendario, observadores y un flujo de FSEvents que nadie cierra: uno por apertura sería
    /// una fuga). Las piezas propias del Centro (historial y reuniones) sí se crean y se sueltan en cada apertura.
    private func prepararAurora() {
        cerrando = false
        let nav = NavegacionAurora()
        navegacionAurora = nav
        if let datosDePrueba {
            datos = datosDePrueba()
            datos?.seccionVisible = nav.seccion
            return
        }
        let d: DatosCentro
        if let i = isla?() {
            d = DatosCentro(agenda: i.agenda, claude: i.claude, tablero: i.tablero, tareas: i.tareas, salud: i.salud.estado)
        } else {
            if propios == nil {
                propios = DatosCentro(agenda: Agenda(), claude: claudeIsla ?? SesionesClaude(), tablero: TableroIsla(), tareas: TareasIsla(pendientes: nil),
                                      salud: salud?.estado ?? EstadoSalud())
            }
            guard let p = propios else { return }
            d = DatosCentro(agenda: p.agenda, claude: p.claude, tablero: p.tablero, tareas: p.tareas, salud: p.salud)
        }
        if let s = salud ?? isla?()?.salud {
            d.medirSalud = { s.medirAhora() }
            d.analizarSalud = { if s.estado.limpiables.isEmpty && !s.estado.analizando { s.analizar() } }
        }
        d.seccionVisible = nav.seccion
        d.focoHechas = { [weak self] in self?.foco?.hechas ?? [] }
        d.espacio = { [weak self] in self?.isla?()?.lanzador.espacioActual ?? Ajustes.espacioDeLaIsla }
        d.fondoEspacio = { [weak self] in
            if let e = self?.isla?()?.lanzador.espacio { return e.fondo }
            guard let nombre = Ajustes.espacioDeLaIsla, let texto = try? String(contentsOf: LanzadorIsla.archivoEspacios, encoding: .utf8) else { return nil }
            return EspaciosIsla.leer(texto).first { $0.nombre == nombre }?.fondo
        }
        datos = d
    }

    /// Lo que pasa al ponerse a la vista: leer todo, el reloj de una vez por minuto (el único) y el vigilante de pantallas.
    private func arrancarAurora() {
        datos?.abrir()
        reloj?.invalidate()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.datos?.minuto() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        reloj = t
        instalarAtajos()
        if observadorPantallas == nil {
            // Si cambian las pantallas con el Centro abierto (se desconectó el monitor donde estaba), se cierra: es lo que no da sorpresas.
            observadorPantallas = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cerrar(devolver: false) }
            }
        }
    }

    private func crearVentanaAurora() -> NSWindow {
        let pantalla = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let marco = pantalla.frame, util = pantalla.visibleFrame
        let v = VentanaDelEspacio(contentRect: marco, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        v.setFrame(marco, display: false)
        v.title = "Centro"
        v.backgroundColor = .black
        v.isOpaque = true
        v.hasShadow = false
        v.level = .normal
        v.appearance = NSAppearance(named: .darkAqua)
        v.isReleasedWhenClosed = false
        v.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        v.delegate = self
        let margenes = EdgeInsets(top: marco.maxY - util.maxY, leading: util.minX - marco.minX,
                                  bottom: util.minY - marco.minY, trailing: marco.maxX - util.maxX)
        let paleta = AuroraPaleta(rawValue: UserDefaults.dictado.string(forKey: EstadoLanzador.clavePaleta) ?? "") ?? .lagunaDurazno
        guard let datos, let nav = navegacionAurora else { return v }
        let fondo = FondoEscritorio()
        fondo.leerAjustes()
        fondo.pantalla = pantalla
        fondo.sincronizar(espacio: datos.fondoEspacio())
        escritorio = fondo
        let acciones = AccionesCentroAurora(
            cerrar: { [weak self] in self?.cerrar() },
            abrirSalud: { [weak self] explicar in self?.abrirSalud(explicar: explicar) },
            abrirEnlace: { url in
                // Las noticias son de terceros: solo se abre web.
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            },
            unirse: { enlace in
                // Una videollamada de la agenda: Zoom directo en su app si está instalada.
                if ["http", "https"].contains(enlace.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(Reunion.abrible(enlace)) }
            },
            abrirRuta: { ruta in
                // Una ruta relativa al cerebro (el tablero de finanzas): dentro de él y que exista.
                guard let centro = TareasIsla.carpetaCentro, !ruta.contains("..") else { return }
                let url = centro.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(ruta)
                if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
            })
        let raiz = RaizCentroAurora(datos: datos, nav: nav, escritorio: fondo, paleta: paleta, simulado: vidrioSimulado, margenes: margenes, acciones: acciones)
        let host = NSHostingView(rootView: AnyView(raiz))
        host.sizingOptions = []   // el tamaño lo decide la ventana (la pantalla), no el ideal de SwiftUI
        anfitrion = host
        v.contentView = host
        return v
    }

    /// Desde la sección Mac: abre Salud del Mac en Limpieza (nada se borra aquí: cada cosa se confirma allá).
    private func abrirSalud(explicar: Bool) {
        guard let s = salud ?? isla?()?.salud else { return }
        s.estado.pestana = 1
        if explicar, let primera = s.estado.limpiables.first(where: \.segura) { s.estado.abiertos = [primera.id] }
        cerrar(devolver: false)
        s.abrir()
    }

    /// Suelta la ventana y todo lo que cuelga de ella, en orden: el foco, el contenido de SwiftUI (vaciado, como el Dock y el lanzador: así el
    /// grafo de vistas se libera aunque AppKit tarde en soltar la ventana), la vista, el delegado y, al final, la ventana y los datos propios.
    private func soltar(_ v: NSWindow) {
        cierre = nil
        reloj?.invalidate()
        reloj = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let o = observadorPantallas { NotificationCenter.default.removeObserver(o) }
        observadorPantallas = nil
        v.makeFirstResponder(nil)
        anfitrion?.rootView = AnyView(EmptyView())
        anfitrion = nil
        v.contentView = nil
        v.delegate = nil
        v.orderOut(nil)
        v.close()
        datos?.soltar()
        datos = nil
        escritorio?.soltar()
        escritorio = nil
        navegacionAurora = nil
        if ventana === v { ventana = nil }
        cerrando = false
    }

    /// El teclado del Centro nuevo: ⌘1 a ⌘9 y ⌘0 cambian de sección, ⌘R lee ya, esc o ⌘W cierran y las flechas se mueven por la lista de la
    /// sección. true si la tecla era suya.
    private func tecla(_ e: NSEvent) -> Bool {
        guard let nav = navegacionAurora, let datos else { return false }
        if e.keyCode == 53 { cerrar(); return true }   // esc
        if e.modifierFlags.contains(.command) {
            let tecla = e.charactersIgnoringModifiers
            if let s = SeccionAurora.deAtajo(tecla) { nav.seccion = s; return true }
            switch tecla {
            case "r": datos.minuto()
            case "w": cerrar()
            default: return false
            }
            return true
        }
        guard e.modifierFlags.intersection([.control, .option, .shift]).isEmpty else { return false }
        let delta: Int
        switch e.keyCode {
        case 125, 124: delta = 1    // abajo, derecha
        case 126, 123: delta = -1   // arriba, izquierda
        default: return false
        }
        let vertical = e.keyCode == 125 || e.keyCode == 126
        switch nav.seccion {
        case .tablero:
            guard vertical else { return false }
            nav.dia = ListaFlechas.mover(actual: nav.dia, delta: delta, total: HistorialCentro.diasPorOmision) ?? 0
        case .semana:
            guard !vertical else { return false }
            nav.semana = min(1, max(0, nav.semana + delta))
        case .reuniones:
            guard vertical else { return false }
            let ids = datos.reuniones.actas.map(\.id)
            let actual = ids.firstIndex(of: ReunionesAurora.elegida(datos.reuniones.actas, nav.reunion)?.id ?? "")
            if let i = ListaFlechas.mover(actual: actual, delta: delta, total: ids.count) {
                if nav.reunion != ids[i] { nav.descartadoAbierto = false; nav.correoCopiado = false }
                nav.reunion = ids[i]
            }
        case .hoy, .mac, .consumo, .herramientas, .finanzas, .noticias, .automatizaciones: return false
        }
        return true
    }

    // Para las pruebas: lo que sigue vivo tras cerrar.
    var ventanaActual: NSWindow? { ventana }
    var vistaDelContenido: NSView? { ventana?.contentView }
    var navegacionDePrueba: NavegacionAurora? { navegacionAurora }
    var datosActuales: DatosCentro? { datos }
    var ventanaViva: Bool { ventana != nil }

    /// Te fuiste a otra app (o abriste un enlace): el espacio se cierra, como Launchpad.
    func windowDidResignKey(_ notification: Notification) {
        cerrar(devolver: false)
    }

    func windowWillClose(_ notification: Notification) {
        reloj?.invalidate()
        reloj = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        claudePropio = nil
        // Se suelta la ventana con toda su jerarquía de vistas (después de que AppKit termine de cerrarla).
        DispatchQueue.main.async { [weak self] in
            self?.ventana = nil
            self?.cerrando = false
        }
    }

    /// Foto de la ventana (para la prueba de humo): sirve para ver que abre y lee el estado. Ni el vidrio ni el giro 3D de
    /// las ventanas laterales salen en ella (cacheDisplay no aplica las transformaciones); el diseño se revisa con los renders.
    func capturar() -> Data? {
        guard let vista = ventana?.contentView, let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) else { return nil }
        vista.cacheDisplay(in: vista.bounds, to: rep)
        // El vidrio lo pone el sistema y no sale en la foto: se compone sobre un fondo oscuro para verla.
        let imagen = NSImage(size: vista.bounds.size)
        imagen.lockFocus()
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(origin: .zero, size: vista.bounds.size).fill()
        rep.draw(in: NSRect(origin: .zero, size: vista.bounds.size), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)
        imagen.unlockFocus()
        guard let tiff = imagen.tiffRepresentation, let salida = NSBitmapImageRep(data: tiff) else { return nil }
        return salida.representation(using: .png, properties: [:])
    }
}

/// Una ventana sin marco que igual recibe el teclado (esc y los atajos).
private final class VentanaDelEspacio: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct RaizCentro: View {
    let store: CentroStore
    @Bindable var navegacion: Centro.Navegacion
    let claude: SesionesClaude?
    let foco: Foco?
    let simulado: Bool
    let fondo: NSImage?
    let margenes: EdgeInsets
    let abrir: (String) -> Void
    let cerrar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var visto = false

    var body: some View {
        let ctx = ContextoCentro(sesiones: claude?.sesiones ?? [], leido: store.leido, cargando: store.cargando,
                                 error: store.error, configurado: store.configurado, enVentana: true,
                                 actualizar: { store.actualizar() }, abrir: abrir,
                                 abrirSesion: { SesionesClaude.abrir($0) },
                                 aplicando: store.aplicando, fallos: store.fallos, puedeActuar: store.puedeActuar,
                                 aplicarInbox: { store.aplicarInbox($0, accion: $1, destino: $2) },
                                 copiar: { texto in
                                     NSPasteboard.general.clearContents()
                                     NSPasteboard.general.setString(texto, forType: .string)
                                 },
                                 cerrar: cerrar, tokensHoy: claude?.tokensHoy ?? 0, respuestasHoy: claude?.respuestasHoy ?? 0,
                                 focoActivo: foco?.activo?.titulo, focoHechas: foco?.hechas ?? [], focoMinutosHoy: foco?.minutosHoy ?? 0,
                                 empezarFoco: { titulo, minutos, vertical in
                                     // Empezar un bloque es ponerse a trabajar: el espacio se cierra y la isla lleva el tiempo.
                                     foco?.empezar(titulo, minutos: minutos, vertical: vertical)
                                     cerrar()
                                 })
        ZStack {
            FondoEspacio(imagen: fondo)
            // Al abrir, las ventanas llegan desde un poco más lejos (sin movimiento si así lo pides).
            VistaCentro(estado: store.estado, ctx: ctx, seccion: $navegacion.seccion)
                .padding(margenes)
                .scaleEffect(visto || sinMovimiento || simulado ? 1 : 0.965)
                .opacity(visto || simulado ? 1 : 0)
        }
        .ignoresSafeArea()
        .environment(\.vidrioSimulado, simulado)
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: sinMovimiento ? 0.2 : 0.5)) { visto = true }
        }
    }
}

/// Otra instancia (o un atajo del sistema) le pide a Dictado abierto que muestre el centro: `Dictado --abrir-centro`.
extension Notification.Name {
    static let abrirCentro = Notification.Name("app.dictado.abrirCentro")
}

func pedirAbrirCentro() {
    DistributedNotificationCenter.default().postNotificationName(.abrirCentro, object: nil, userInfo: nil, deliverImmediately: true)
}

/// Prueba de humo de la ventana real: la abre, espera el estado del comando configurado y guarda una foto.
/// `Dictado --probar-ventana-centro salida.png [hoy|metas|orquesta]`
@MainActor
func probarVentanaCentro(_ destino: URL, escena: String?) -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let centro = Centro(claude: nil, vidrioSimulado: true)
    centro.abrir(SeccionCentro(rawValue: escena ?? "hoy"))
    let limite = Date().addingTimeInterval(45)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    while centro.cargando && Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    guard let png = centro.capturar() else { return false }
    centro.cerrar()
    return (try? png.write(to: destino)) != nil
}
