import AppKit
import ApplicationServices
import DictadoKit
import os
import SwiftUI

private let log = Logger(subsystem: "app.dictado", category: "selector")

// Selector de apps (⌘Tab propio). Reemplaza el selector del sistema: ⌘Tab abre un panel de vidrio con las apps abiertas (la usada
// más reciente primero) y, debajo de la elegida, sus ventanas y, en los navegadores que se controlan con AppleScript (Cra, Chrome,
// Brave, Edge, Arc, Safari…), las pestañas de cada ventana. Soltar ⌘ salta a lo elegido.
//
// Teclas (con ⌘ apretado): Tab / ⇧Tab y ←/→ cambian de app; ↓/↑ entran en la lista de ventanas y pestañas de la app y la recorren;
// ` / ⇧` cicla sus ventanas (como ⌘` del sistema); Return va ya; Esc cancela. Un toque rápido de ⌘Tab (soltar antes de ~150 ms)
// cambia a la app anterior sin mostrar el panel, como el original.
//
// Cómo escucha: un event tap de teclado (punto HID; el de sesión si no se puede), en su propio hilo, igual que la tecla hyper. Solo
// consume ⌘Tab y ⌘⇧Tab (sin ⌥ ni ⌃) y, con el selector abierto, las teclas del selector; todo lo demás pasa sin tocarse. Pide
// Accesibilidad, como hyper, ventanas y buscador. Sin ese permiso NO lo pide: el ⌘Tab del sistema queda intacto y se avisa una vez.
//
// Qué lee: apps abiertas (NSWorkspace), ventanas por Accesibilidad, miniaturas con ScreenCaptureKit SOLO si Grabación de pantalla ya
// está concedida (nunca se pide), pestañas con AppleScript SOLO si la Automatización del navegador ya está concedida (se consulta
// sin preguntar). Nada se guarda en disco; la caché de ventanas y pestañas vive en memoria y se refresca cada vez que abres el selector.
//
// Apagarlo: menú Funciones > Selector de apps, o `defaults write app.dictado selector.activo -bool false`.

/// Interruptor del módulo, panel, caché y salto a la app, ventana o pestaña elegida.
@MainActor
final class SelectorApps {
    let estado = EstadoSelector()
    private let contexto: ContextoModulos
    private let tap = TapSelector()
    private var panel: PanelSelector?
    private var encendido = false
    private var avisado = false
    private var reintento: Timer?
    private var revision: Timer?
    private var vigia: Timer?
    private var mostrarPendiente: DispatchWorkItem?
    private var observadores: [NSObjectProtocol] = []
    private var ajustes: NSObjectProtocol?
    /// pids en orden de uso, el último usado primero.
    private var uso: [pid_t] = []
    private var iconos: [pid_t: NSImage] = [:]
    private var iconosPropios: [String: String] = [:]
    private var generacionVentanas: [pid_t: Int] = [:]
    private var pestanasEnCurso: Set<pid_t> = []
    /// Cuánto vale una lectura antes de volver a pedirla al abrir el selector (segundos).
    private let frescura: TimeInterval = 2
    private var yaMostrado = false
    /// Navegadores a los que ya se les pidió la Automatización en esta sesión (macOS pregunta una sola vez).
    private var automatizacionPedida: Set<String> = []
    private var cimaPanel: CGFloat = 0

    /// `defaults write app.dictado selector.activo -bool false` lo apaga sin pasar por el menú.
    static var habilitado: Bool {
        Funcion.selector.activa && (UserDefaults.dictado.object(forKey: "selector.activo") as? Bool ?? true)
    }

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.selector.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        })
        ajustes = centro.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        estado.alElegir = { [weak self] app, elemento in self?.elegirConRaton(app, elemento) }
        estado.alAviso = { [weak self] aviso in self?.atenderAviso(aviso) }
        sincronizar()
    }

    private func sincronizar() {
        Self.habilitado ? encender() : apagar()
    }

    // MARK: Encender y apagar

    private func encender() {
        guard !encendido else { return }
        encendido = true
        uso = BuscadorVentanas.appsVisibles().map(\.pid)
        iconosPropios = EstadoDock.leerIconosPropios()
        let ws = NSWorkspace.shared.notificationCenter
        observadores.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] nota in
            let app = nota.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let bundle = app?.bundleIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.registrarUso(pid) }
                self?.pedirAutomatizacionSiFalta(bundle)
            }
        })
        observadores.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] nota in
            let pid = (nota.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.olvidar(pid) } }
        })
        observadores.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tap.reiniciarEstado() }
        })
        conectar()
        if !tap.activo {
            reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.conectar() }
            }
        }
        // Los iconos se preparan con calma, antes de que hagan falta: el primer ⌘Tab no paga por ellos.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { _ = self?.encendido == true ? self?.construirApps() : nil }
        }
    }

    private func apagar() {
        guard encendido else { return }
        encendido = false
        reintento?.invalidate(); reintento = nil
        revision?.invalidate(); revision = nil
        cerrarPanel()
        tap.detener()
        let ws = NSWorkspace.shared.notificationCenter
        for o in observadores.dropFirst() { ws.removeObserver(o) }   // el primero es el de Funciones, que sigue
        observadores = Array(observadores.prefix(1))
        estado.detalles = [:]
        estado.apps = []
        iconos = [:]
        uso = []
    }

    /// Crea el tap si hay permiso. Sin permiso no se pide nada: el ⌘Tab del sistema sigue como siempre y se avisa una sola vez.
    private func conectar() {
        guard encendido, !tap.activo else { return }
        guard TapHyper.permitido() else {
            if !avisado {
                avisado = true
                contexto.avisar("El selector de apps (⌘Tab) necesita Accesibilidad; mientras tanto sigue el del sistema", "lock", nil)
            }
            return
        }
        let listo = tap.iniciar { [weak self] entrada in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recibir(entrada) } }
        }
        guard listo else { return }
        log.info("tap del selector en \(self.tap.ubicacion == .cghidEventTap ? "HID" : "sesión", privacy: .public)")
        reintento?.invalidate(); reintento = nil
        // Si quitas el permiso con el tap vivo, macOS puede dejar el teclado trabado: se revisa cada 15 s.
        revision = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.encendido, !TapHyper.permitido() else { return }
                self.cerrarPanel()
                self.tap.detener()
                self.revision?.invalidate(); self.revision = nil
                self.reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.conectar() }
                }
            }
        }
        revision?.tolerance = 5
    }

    // MARK: Entradas del tap

    private func recibir(_ entrada: EntradaSelector) {
        guard encendido else { return }
        switch entrada {
        case .iniciar(let atras): iniciar(atras: atras)
        case .tecla(let t):
            guard estado.maquina.fase != .reposo else { return }
            let cambioApp = estado.maquina.tecla(t)
            if estado.maquina.fase == .visible { mostrar() }
            if cambioApp { alCambiarApp() }
            reajustar()
        case .cancelar:
            estado.maquina.cancelar()
            cerrarPanel()
        case .confirmar, .soltarCmd:
            terminar()
        }
    }

    private func iniciar(atras: Bool) {
        cerrarPanel()
        let apps = construirApps()
        guard !apps.isEmpty else { tap.terminarSesion(); return }
        estado.apps = apps
        let pantalla = NSScreen.main ?? NSScreen.screens.first
        estado.anchoPantalla = Double(pantalla?.visibleFrame.width ?? 1440)
        estado.altoPantalla = Double(pantalla?.visibleFrame.height ?? 900)
        estado.hayMiniaturas = CGPreflightScreenCaptureAccess()   // solo consulta: no abre ningún diálogo
        estado.maquina.iniciar(atras: atras, totalApps: apps.count)
        sincronizarElementos()
        // Un toque rápido de ⌘Tab no muestra nada: el panel sale solo si ⌘ sigue apretado pasado el retraso.
        let pendiente = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.estado.maquina.fase == .esperando else { return }
                self.estado.maquina.mostrar()
                self.mostrar()
            }
        }
        mostrarPendiente = pendiente
        DispatchQueue.main.asyncAfter(deadline: .now() + MaquinaSelector.retrasoPanel, execute: pendiente)
        vigia?.invalidate()
        // Red de seguridad: si por lo que sea no llegó el aviso de soltar ⌘, no se queda abierto.
        vigia = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.estado.maquina.fase != .reposo else { return }
                if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
                    self.tap.terminarSesion()
                    self.terminar()
                }
            }
        }
    }

    /// Soltar ⌘ (o Return): cierra y va a lo elegido.
    private func terminar() {
        let r = estado.maquina.soltar()
        cerrarPanel()
        if case .confirmar(let app, let elemento, _) = r { ir(app: app, elemento: elemento) }
    }

    /// Un clic en una tarjeta con ⌘ apretado: va ya y el soltar posterior no hace nada.
    private func elegirConRaton(_ app: Int, _ elemento: Int?) {
        guard estado.maquina.fase != .reposo else { return }
        tap.terminarSesion()
        estado.maquina.cancelar()
        cerrarPanel()
        ir(app: app, elemento: elemento)
    }

    // MARK: Permisos

    /// Cuando un navegador pasa al frente y su Automatización aún no se decidió, macOS pregunta una vez (el diálogo es del sistema).
    /// Así ⌘Tab puede mostrar sus pestañas; si dices que no, no se vuelve a preguntar.
    private func pedirAutomatizacionSiFalta(_ bundle: String?) {
        guard encendido, let bundle, NavegadoresDock.familia(bundleID: bundle) != nil,
              automatizacionPedida.insert(bundle).inserted else { return }
        DispatchQueue.global(qos: .utility).async {
            guard PermisoAutomatizacion.consultar(bundle) == .pendiente else { return }
            _ = PermisoAutomatizacion.pedir(bundle)
        }
    }

    /// Un clic en el aviso del pie: cierra el selector y pide el permiso (o abre Ajustes si ya se negó).
    private func atenderAviso(_ aviso: AvisoSelector) {
        tap.terminarSesion()
        estado.maquina.cancelar()
        cerrarPanel()
        switch aviso {
        case .automatizacion(let bundle):
            DispatchQueue.global(qos: .userInitiated).async {
                guard PermisoAutomatizacion.pedir(bundle) != .concedido else { return }
                DispatchQueue.main.async { Self.abrirAjustes("Privacy_Automation") }
            }
        case .grabacion:
            if !CGRequestScreenCaptureAccess() { Self.abrirAjustes("Privacy_ScreenCapture") }
        }
    }

    private static func abrirAjustes(_ seccion: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(seccion)") { NSWorkspace.shared.open(url) }
    }

    // MARK: Panel

    private func mostrar() {
        guard encendido, estado.maquina.fase == .visible else { return }
        refrescarTodo()
        let p = panelListo()
        guard !p.isVisible else { return }
        iconosPropios = EstadoDock.leerIconosPropios()
        let m = estado.medidas
        let total = CGSize(width: m.width + 2 * AuroraSelector.margen, height: m.height + 2 * AuroraSelector.margen)
        let z = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        cimaPanel = z.midY + total.height / 2
        p.setFrame(NSRect(x: z.midX - total.width / 2, y: cimaPanel - total.height, width: total.width, height: total.height), display: false)
        let sinMovimiento = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = sinMovimiento ? AuroraMovimiento.fundidoSinMovimiento : 0.12
            p.animator().alphaValue = 1
        }
        yaMostrado = true
    }

    private func panelListo() -> PanelSelector {
        if let panel { return panel }
        let p = PanelSelector()
        let vista = NSHostingView(rootView: VistaSelectorApps(estado: estado))
        vista.sizingOptions = []
        p.contentView = vista
        panel = p
        return p
    }

    /// El panel crece o se encoge hacia abajo cuando llegan ventanas o pestañas: la fila de apps se queda donde está.
    private func reajustar() {
        guard let p = panel, p.isVisible else { return }
        let m = estado.medidas
        let total = CGSize(width: m.width + 2 * AuroraSelector.margen, height: m.height + 2 * AuroraSelector.margen)
        let z = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let nuevo = NSRect(x: z.midX - total.width / 2, y: cimaPanel - total.height, width: total.width, height: total.height)
        if nuevo != p.frame { p.setFrame(nuevo, display: true) }
    }

    private func cerrarPanel() {
        mostrarPendiente?.cancel(); mostrarPendiente = nil
        vigia?.invalidate(); vigia = nil
        panel?.orderOut(nil)
        if yaMostrado { yaMostrado = false; recortarCache() }
    }

    /// Entre aperturas solo queda lo de las apps más usadas: ni miniaturas ni pestañas de lo que ya no importa.
    private func recortarCache() {
        let vivas = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let guardar = Set(uso.prefix(6)).intersection(vivas)
        for pid in estado.detalles.keys where !guardar.contains(pid) { estado.detalles[pid] = nil }
    }

    // MARK: Apps

    private func registrarUso(_ pid: pid_t) {
        guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
        uso = OrdenUso.registrar(pid, en: uso)
    }

    private func olvidar(_ pid: pid_t) {
        uso.removeAll { $0 == pid }
        iconos[pid] = nil
        estado.detalles[pid] = nil
    }

    private func construirApps() -> [AppSel] {
        let vivas = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        if let frente = NSWorkspace.shared.frontmostApplication, frente.activationPolicy == .regular { registrarUso(frente.processIdentifier) }
        let porPid = Dictionary(vivas.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let orden = OrdenUso.ordenar(vivos: vivas.map(\.processIdentifier), uso: uso)
        return orden.compactMap { pid in
            guard let r = porPid[pid] else { return nil }
            return AppSel(id: pid, nombre: r.localizedName ?? "App", bundleID: r.bundleIdentifier, icono: icono(de: r))
        }
    }

    private func icono(de r: NSRunningApplication) -> NSImage? {
        if let i = iconos[r.processIdentifier] { return i }
        let entrada = EntradaApp(nombre: r.localizedName ?? "", ruta: r.bundleURL?.path ?? "", bundleID: r.bundleIdentifier)
        let propio = IconosPersonalizados.ruta(entrada, en: iconosPropios).flatMap { EstadoDock.iconoPropio($0) }
        guard let original = propio ?? r.icon else { return nil }
        let i = Self.mapaDeBits(original, lado: 128)
        iconos[r.processIdentifier] = i
        return i
    }

    /// El icono en un mapa de bits de `lado` píxeles (más liviano que el multirresolución de macOS), a 2× de su tamaño en puntos.
    static func mapaDeBits(_ original: NSImage, lado: Int) -> NSImage {
        let puntos = CGFloat(lado) / 2
        let imagen = NSImage(size: NSSize(width: puntos, height: puntos))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let contexto = NSGraphicsContext(bitmapImageRep: rep) else { return original }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexto
        contexto.imageInterpolation = .high
        original.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: puntos, height: puntos)
        imagen.addRepresentation(rep)
        return imagen
    }

    // MARK: Caché de ventanas y pestañas

    private func alCambiarApp() {
        sincronizarElementos()
        if estado.maquina.fase == .visible, let app = estado.appActual { refrescar(app, completo: true) }
    }

    private func sincronizarElementos() {
        let d = estado.detalleActual
        estado.maquina.ajustarElementos(total: d?.elementos.count ?? 0, inicial: ListaDetalle.inicial(d?.resumen ?? []))
    }

    /// Al abrirse el panel: la app elegida primero y luego los navegadores, para que sus pestañas ya estén al llegar a ellos.
    private func refrescarTodo() {
        guard let actual = estado.appActual else { return }
        refrescar(actual, completo: true)
        for app in estado.apps where app.id != actual.id && NavegadoresDock.familia(bundleID: app.bundleID) != nil {
            refrescarPestanas(app)
        }
    }

    private func refrescar(_ app: AppSel, completo: Bool) {
        refrescarVentanas(app)
        refrescarPestanas(app)
    }

    private func refrescarVentanas(_ app: AppSel) {
        let pid = app.id
        var d = estado.detalles[pid] ?? DetalleApp()
        if Date().timeIntervalSince(d.ventanasInstante) < frescura && !d.ventanas.isEmpty { return }
        d.ventanasInstante = Date()
        estado.detalles[pid] = d
        generacionVentanas[pid, default: 0] += 1
        let mia = generacionVentanas[pid] ?? 0
        let visible = BuscadorVentanas.AppVisible(pid: pid, nombre: app.nombre, bundle: app.bundleID,
                                                  oculta: NSRunningApplication(processIdentifier: pid)?.isHidden ?? false)
        Task { [weak self] in
            let encontradas = await Task.detached(priority: .userInitiated) { BuscadorVentanas.ventanas(de: visible, espera: 0.25) }.value
            self?.aplicarVentanas(pid, encontradas, generacion: mia)
        }
    }

    private func aplicarVentanas(_ pid: pid_t, _ encontradas: [VentanaEncontrada], generacion: Int) {
        guard generacionVentanas[pid] == generacion, var d = estado.detalles[pid] else { return }
        let previas = d.ventanas
        d.ventanas = encontradas.enumerated().map { k, e in
            var v = VentanaSel(id: k, titulo: e.titulo, minimizada: e.minimizada, ax: e.elemento)
            if let ax = e.elemento, let vieja = previas.first(where: { $0.ax.map { CFEqual($0, ax) } ?? false }) {
                v.miniatura = vieja.miniatura
            }
            return v
        }
        d.cargandoVentanas = false
        Self.emparejar(&d)
        estado.detalles[pid] = d
        alLlegarDatos(pid)
        if estado.hayMiniaturas { cargarMiniaturas(pid, generacion: generacion) }
    }

    private func cargarMiniaturas(_ pid: pid_t, generacion: Int) {
        guard let d = estado.detalles[pid], !d.ventanas.isEmpty else { return }
        let marcos = d.ventanas.map { LecturaVentanas.marco($0.ax) }
        Task { [weak self] in
            let imagenes = await LecturaVentanas.miniaturas(pid: pid, marcos: marcos)
            guard let self, self.generacionVentanas[pid] == generacion, var d = self.estado.detalles[pid] else { return }
            for (k, img) in imagenes.enumerated() where d.ventanas.indices.contains(k) && img != nil { d.ventanas[k].miniatura = img }
            self.estado.detalles[pid] = d
        }
    }

    private func refrescarPestanas(_ app: AppSel) {
        guard let bundle = app.bundleID, let familia = NavegadoresDock.familia(bundleID: bundle) else { return }
        let pid = app.id
        var d = estado.detalles[pid] ?? DetalleApp()
        if Date().timeIntervalSince(d.pestanasInstante) < frescura || pestanasEnCurso.contains(pid) { return }
        if d.pestanas == .noAplica { d.pestanas = .cargando }
        estado.detalles[pid] = d
        pestanasEnCurso.insert(pid)
        let guion = NavegadoresDock.guionListar(bundleID: bundle, familia: familia, conURL: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Sin preguntar: si falta el permiso de Automatización del navegador no se corre nada ni se abre ningún diálogo.
            let permiso = PermisoAutomatizacion.consultar(bundle)
            let texto = permiso == .concedido ? LecturaVentanas.ejecutar(guion) : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.aplicarPestanas(pid, permiso: permiso, texto: texto) } }
        }
    }

    private func aplicarPestanas(_ pid: pid_t, permiso: PermisoAutomatizacion, texto: String?) {
        pestanasEnCurso.remove(pid)
        guard var d = estado.detalles[pid] else { return }
        switch (permiso, texto) {
        case (.concedido, let t?):
            d.nav = NavegadoresDock.leer(t)
            d.pestanas = .listo
        case (.concedido, nil): d.pestanas = .fallo
        case (.noCorre, _): d.pestanas = .noAplica
        default: d.pestanas = .sinPermiso
        }
        d.pestanasInstante = Date()
        Self.emparejar(&d)
        estado.detalles[pid] = d
        alLlegarDatos(pid)
    }

    /// Une las ventanas del sistema con las del navegador (por título y, si no, por posición). Si Accesibilidad no vio ninguna
    /// ventana pero el navegador sí, se muestran las del navegador.
    private static func emparejar(_ d: inout DetalleApp) {
        if d.ventanas.isEmpty, !d.nav.isEmpty {
            d.ventanas = d.nav.enumerated().map { k, n in VentanaSel(id: k, titulo: n.titulo, ventanaNav: n) }
        }
        for k in d.ventanas.indices {
            let n = NavegadoresDock.emparejar(titulo: d.ventanas[k].titulo, posicion: k, entre: d.nav)
            d.ventanas[k].ventanaNav = n
            d.ventanas[k].pestanas = n?.pestanas ?? []
        }
    }

    private func alLlegarDatos(_ pid: pid_t) {
        guard estado.appActual?.id == pid else { return }
        sincronizarElementos()
        reajustar()
    }

    // MARK: Ir a lo elegido

    private func ir(app indice: Int, elemento: Int?) {
        guard estado.apps.indices.contains(indice) else { return }
        let app = estado.apps[indice]
        uso = OrdenUso.registrar(app.id, en: uso)   // sin esperar al aviso del sistema: ⌘Tab seguidos alternan bien
        guard let e = elemento, let d = estado.detalles[app.id], d.elementos.indices.contains(e) else {
            activar(app.id)
            return
        }
        switch d.elementos[e] {
        case .ventana(let w):
            subir(d.ventanas[w], de: app.id)
        case .pestana(let w, let p):
            let v = d.ventanas[w]
            subir(v, de: app.id)
            guard let bundle = app.bundleID, let familia = NavegadoresDock.familia(bundleID: bundle), let nav = v.ventanaNav, v.pestanas.indices.contains(p)
            else { return }
            let guion = NavegadoresDock.guionSaltar(bundleID: bundle, familia: familia, ventana: nav, pestana: v.pestanas[p])
            DispatchQueue.global(qos: .userInitiated).async { _ = LecturaVentanas.ejecutar(guion) }
        }
    }

    /// Trae la app al frente. Desde un panel que no activa a Dictado, macOS puede ignorar `activate()`; por Accesibilidad sí obedece.
    private func activar(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// Quita el minimizado, sube la ventana y activa su app.
    private func subir(_ v: VentanaSel, de pid: pid_t) {
        if let ventana = v.ax {
            AXUIElementSetMessagingTimeout(ventana, 0.3)
            if v.minimizada { AXUIElementSetAttributeValue(ventana, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            AXUIElementPerformAction(ventana, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(ventana, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        activar(pid)
        if let ventana = v.ax { AXUIElementPerformAction(ventana, kAXRaiseAction as CFString) }
    }
}

// MARK: - Panel

/// Un panel que no se activa ni toma el teclado (las teclas las lee el tap): solo se ve y recibe clics.
final class PanelSelector: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false   // la sombra la dibuja el vidrio de Aurora
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

// MARK: - Permiso de Automatización (sin preguntar)

enum PermisoAutomatizacion {
    case concedido, pendiente, denegado, noCorre

    /// Consulta el permiso de este proceso sobre el navegador SIN abrir el diálogo de macOS.
    nonisolated static func consultar(_ bundleID: String) -> PermisoAutomatizacion {
        let objetivo = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = objetivo.aeDesc else { return .noCorre }
        let r = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch r {
        case noErr: return .concedido
        case OSStatus(errAEEventNotPermitted): return .denegado
        case OSStatus(procNotFound): return .noCorre
        default: return .pendiente   // errAEEventWouldRequireUserConsent: aún no se ha decidido
        }
    }

    /// Pide el permiso: si aún no se decidió, macOS muestra su diálogo y esto espera la respuesta (llamar fuera del hilo principal).
    nonisolated static func pedir(_ bundleID: String) -> PermisoAutomatizacion {
        let objetivo = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = objetivo.aeDesc else { return .noCorre }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true) {
        case noErr: return .concedido
        case OSStatus(errAEEventNotPermitted): return .denegado
        case OSStatus(procNotFound): return .noCorre
        default: return .pendiente
        }
    }
}

// MARK: - Event tap

/// El tap de ⌘Tab, en un hilo propio (como el de hyper): si el hilo principal se ocupa, el teclado del Mac no se traba. Con ayuda de
/// `ClasificadorSelector` decide en el acto qué se consume; los avisos al selector van al hilo principal, en orden.
final class TapSelector: @unchecked Sendable {
    typealias Aviso = @Sendable (EntradaSelector) -> Void

    private final class Sesion: @unchecked Sendable {
        var tap: CFMachPort?
        var lugar: CGEventTapLocation?
        var bucle: CFRunLoop?
        let cerrojo = NSLock()
        var clasificador = ClasificadorSelector()
        let avisar: Aviso
        init(_ avisar: @escaping Aviso) { self.avisar = avisar }

        func modificadores(_ f: CGEventFlags) -> ModsSelector {
            var m: ModsSelector = []
            if f.contains(.maskCommand) { m.insert(.cmd) }
            if f.contains(.maskShift) { m.insert(.shift) }
            if f.contains(.maskAlternate) { m.insert(.opcion) }
            if f.contains(.maskControl) { m.insert(.control) }
            return m
        }

        /// Corre en el hilo del tap: tiene que ser rápido, cada tecla del Mac pasa por aquí.
        func manejar(_ tipo: CGEventType, _ evento: CGEvent) -> Unmanaged<CGEvent>? {
            switch tipo {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                let habia = cerrojo.withLock { clasificador.reiniciar() }
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                if habia { avisar(.cancelar) }   // pudo perderse el soltar de ⌘ mientras estaba apagado
                return Unmanaged.passUnretained(evento)
            case .keyDown:
                let codigo = Int(evento.getIntegerValueField(.keyboardEventKeycode))
                let mods = modificadores(evento.flags)
                let r = cerrojo.withLock { clasificador.teclaAbajo(codigo: codigo, mods: mods) }
                if let e = r.entrada { avisar(e) }
                return r.consumir ? nil : Unmanaged.passUnretained(evento)
            case .keyUp:
                let codigo = Int(evento.getIntegerValueField(.keyboardEventKeycode))
                let consumir = cerrojo.withLock { clasificador.teclaArriba(codigo: codigo) }
                return consumir ? nil : Unmanaged.passUnretained(evento)
            case .flagsChanged:
                let mods = modificadores(evento.flags)
                if let e = cerrojo.withLock({ clasificador.modificadores(mods) }) { avisar(e) }
                return Unmanaged.passUnretained(evento)
            default:
                return Unmanaged.passUnretained(evento)
            }
        }
    }

    /// Solo en el hilo principal.
    private(set) var activo = false
    private(set) var ubicacion: CGEventTapLocation?
    private var sesion: Sesion?

    private static let mascara: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    @MainActor
    func iniciar(_ avisar: @escaping Aviso) -> Bool {
        guard !activo else { return true }
        let s = Sesion(avisar)
        let listo = DispatchSemaphore(value: 0)
        let hilo = Thread {
            let refcon = Unmanaged.passUnretained(s).toOpaque()   // la sesión vive mientras viva su hilo
            for lugar in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
                if let tap = CGEvent.tapCreate(
                    tap: lugar, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: TapSelector.mascara,
                    callback: { _, tipo, evento, refcon in
                        guard let refcon else { return Unmanaged.passUnretained(evento) }
                        return Unmanaged<Sesion>.fromOpaque(refcon).takeUnretainedValue().manejar(tipo, evento)
                    }, userInfo: refcon) {
                    s.tap = tap
                    s.lugar = lugar
                    s.bucle = CFRunLoopGetCurrent()
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
                    CGEvent.tapEnable(tap: tap, enable: true)
                    break
                }
            }
            let vivo = s.bucle != nil
            listo.signal()
            if vivo { CFRunLoopRun() }   // duerme hasta que llegue un evento: 0 % de CPU en reposo
        }
        hilo.name = "app.dictado.selector"
        hilo.qualityOfService = .userInteractive
        hilo.start()
        listo.wait()
        guard s.bucle != nil else { return false }
        sesion = s
        ubicacion = s.lugar
        activo = true
        return true
    }

    @MainActor
    func detener() {
        guard activo, let s = sesion, let bucle = s.bucle else { return }
        activo = false
        sesion = nil
        CFRunLoopPerformBlock(bucle, CFRunLoopMode.commonModes.rawValue) {
            if let tap = s.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            s.tap = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(bucle)
    }

    /// El selector cerró por su cuenta (un clic): lo que quede de ⌘Tab ya no se consume.
    @MainActor
    func terminarSesion() {
        guard let s = sesion else { return }
        s.cerrojo.withLock { s.clasificador.terminar() }
    }

    @MainActor
    func reiniciarEstado() {
        guard let s = sesion else { return }
        _ = s.cerrojo.withLock { s.clasificador.reiniciar() }
    }
}
