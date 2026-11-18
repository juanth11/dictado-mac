import AppKit
import DictadoKit
import IOKit.ps
import Observation
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI

// Los modelos del Dock (la barra de abajo, función opcional "Dock propio"): lo que sus vistas leen. Todo lo que toca disco,
// miniaturas o procesos corre fuera del hilo principal; nada se consulta en bucle (avisos de NSWorkspace, IOKit y del propio
// sistema de archivos). Cada modelo con recursos (la carpeta abierta, la batería, las apps abiertas) tiene `iniciar`/`detener`
// y suelta todo al ocultarse el Dock.

// MARK: - Tonos del acabado

/// Los tres tonos del acabado de la barra: la base oscura y los dos colores de la franja de luz.
struct TonosDock: Equatable {
    var hondo: Color
    var c1: Color
    var c2: Color

    static func de(_ t: TonosFondo) -> TonosDock { TonosDock(hondo: Color(hex: t.hondo), c1: Color(hex: t.c1), c2: Color(hex: t.c2)) }

    /// Sin fondo legible (un fondo en vivo, una carpeta de imágenes): la paleta del espacio.
    static func de(paleta: AuroraPaleta) -> TonosDock {
        func mezcla(_ a: UInt32, _ parte: Double, _ b: UInt32) -> Color {
            func c(_ v: UInt32, _ d: UInt32) -> Double { Double((v >> d) & 0xFF) / 255 }
            func m(_ d: UInt32) -> Double { c(a, d) * parte + c(b, d) * (1 - parte) }
            return Color(.sRGB, red: m(16), green: m(8), blue: m(0))
        }
        return TonosDock(hondo: mezcla(paleta.a, 0.30, 0x050507), c1: mezcla(paleta.a, 0.80, 0xFFFFFF), c2: Color(hex: paleta.b))
    }

    static let porOmision = de(paleta: .medianocheOro)
}

// MARK: - El fondo de pantalla

enum FondoPantalla {
    /// El archivo del fondo de esa pantalla (nil si es una carpeta, un fondo en vivo o no se puede saber).
    @MainActor static func url(de pantalla: NSScreen) -> URL? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: pantalla) else { return nil }
        var esCarpeta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta), !esCarpeta.boolValue else { return nil }
        return url
    }

    /// Una miniatura de unos 40 px y de ahí los tonos (lógica en `AnalisisFondo`). Sin hilo principal.
    nonisolated static func tonos(en url: URL) -> TonosFondo? {
        let opciones: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 40,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imagen = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else { return nil }
        return tonos(imagen: imagen)
    }

    /// Los tonos de una imagen (idealmente ya chica: se dibuja tal cual en un mapa de bits).
    nonisolated static func tonos(imagen: CGImage) -> TonosFondo? {
        let w = imagen.width, h = imagen.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let dibujado = bytes.withUnsafeMutableBytes { crudo -> Bool in
            guard let contexto = CGContext(data: crudo.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                           space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            contexto.draw(imagen, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard dibujado else { return nil }
        var muestras: [MuestraColor] = []
        muestras.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            muestras.append(MuestraColor(r: Double(bytes[i * 4]) / 255, g: Double(bytes[i * 4 + 1]) / 255, b: Double(bytes[i * 4 + 2]) / 255))
        }
        return AnalisisFondo.derivar(muestras)
    }
}

// MARK: - Apps abiertas

/// Qué apps están abiertas, por los avisos de NSWorkspace (sin consultar en bucle). Solo vive mientras el Dock se ve.
@MainActor @Observable
final class AppsAbiertasDock {
    private(set) var abiertas: Set<String> = []
    /// Las apps con ventana (activationPolicy regular) en el orden en que se abrieron, sin Dictado.
    private(set) var lista: [EntradaApp] = []
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []

    func iniciar() {
        detener()
        releer()
        let centro = NSWorkspace.shared.notificationCenter
        for nombre in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observadores.append(centro.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.releer() }
            })
        }
    }

    func detener() {
        observadores.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observadores = []
    }

    private func releer() {
        let propio = Bundle.main.bundleIdentifier
        let regulares = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        abiertas = Set(regulares.compactMap(\.bundleIdentifier))
        let nueva = regulares.filter { $0.bundleIdentifier != propio }.sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            .compactMap { a -> EntradaApp? in
                guard let url = a.bundleURL else { return nil }
                return EntradaApp(nombre: a.localizedName ?? url.deletingPathExtension().lastPathComponent, ruta: url.path, bundleID: a.bundleIdentifier)
            }
        if nueva != lista { lista = nueva }
    }

    /// Renders: una lista ya armada.
    func fijar(_ l: [EntradaApp]) {
        lista = l
        abiertas = Set(l.compactMap(\.bundleID))
    }

    /// Trae la app al frente o la abre.
    static func abrir(_ app: EntradaApp) {
        if let id = app.bundleID, let ya = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            ya.activate()
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.ruta), configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func ejecutando(_ app: EntradaApp) -> NSRunningApplication? {
        app.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
    }
}

// MARK: - Batería

/// El porcentaje y si carga, por el aviso de IOKit (sin consultar en bucle). Un Mac de escritorio no tiene batería: `existe`
/// queda en falso y la pieza no se dibuja.
@MainActor @Observable
final class BateriaDock {
    private(set) var existe = false
    private(set) var porcentaje = 0
    private(set) var cargando = false

    /// El contexto del aviso apunta a esta caja y la caja al modelo con una referencia débil: si el modelo desaparece, el aviso
    /// no toca nada.
    private final class Caja { weak var modelo: BateriaDock? }
    @ObservationIgnored private var fuente: CFRunLoopSource?
    @ObservationIgnored private var caja: Unmanaged<Caja>?

    func iniciar() {
        detener()
        leer()
        let c = Caja()
        c.modelo = self
        let puntero = Unmanaged.passRetained(c)
        caja = puntero
        fuente = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let caja = Unmanaged<Caja>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { caja.modelo?.leer() }
        }, puntero.toOpaque())?.takeRetainedValue()
        if let fuente { CFRunLoopAddSource(CFRunLoopGetMain(), fuente, .defaultMode) }
    }

    func detener() {
        if let fuente { CFRunLoopRemoveSource(CFRunLoopGetMain(), fuente, .defaultMode) }
        fuente = nil
        caja?.release()
        caja = nil
    }

    func leer() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for f in lista {
            guard let d = IOPSGetPowerSourceDescription(info, f)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let actual = d[kIOPSCurrentCapacityKey] as? Int, let maximo = d[kIOPSMaxCapacityKey] as? Int, maximo > 0 else { continue }
            existe = true
            porcentaje = actual * 100 / maximo
            cargando = (d[kIOPSIsChargingKey] as? Bool) == true || (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
        existe = false
    }

    /// Para los renders.
    func fijar(porcentaje: Int, cargando: Bool) {
        existe = true
        self.porcentaje = porcentaje
        self.cargando = cargando
    }
}

// MARK: - Una carpeta del Finder

/// Lo más reciente de una carpeta, con sus miniaturas. Existe solo mientras su panel está abierto: al cerrarse se cancelan las
/// peticiones de miniaturas, se suelta la vigilancia del directorio y se tira todo lo cargado.
@MainActor @Observable
final class ModeloCarpeta {
    let ruta: String
    private(set) var archivos: [ArchivoReciente] = []
    private(set) var miniaturas: [String: NSImage] = [:]
    private(set) var cargando = true
    private(set) var legible = true

    /// Se llama cuando cambia la lista (el Dock reajusta la altura del panel).
    @ObservationIgnored var alCambiar: (() -> Void)?
    @ObservationIgnored private var fuente: DispatchSourceFileSystemObject?
    @ObservationIgnored private var recarga: DispatchWorkItem?
    @ObservationIgnored private var peticiones: [String: QLThumbnailGenerator.Request] = [:]
    @ObservationIgnored private var generacion = 0
    @ObservationIgnored private var activo = false
    @ObservationIgnored private let escala: CGFloat

    nonisolated static let ladoMiniatura: CGFloat = 56

    init(ruta: String, escala: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) {
        self.ruta = ruta
        self.escala = escala
    }

    var url: URL { URL(fileURLWithPath: ruta, isDirectory: true) }

    func abrir() {
        guard !activo else { return }
        activo = true
        vigilar()
        recargar()
    }

    /// Todo fuera: peticiones, vigilancia, lista y miniaturas.
    func soltar() {
        activo = false
        generacion += 1
        recarga?.cancel()
        recarga = nil
        fuente?.cancel()
        fuente = nil
        for p in peticiones.values { QLThumbnailGenerator.shared.cancel(p) }
        peticiones = [:]
        miniaturas = [:]
        archivos = []
        alCambiar = nil
    }

    /// Los renders y la prueba de memoria: una lista ya armada, sin leer el disco.
    func fijar(_ lista: [ArchivoReciente], miniaturas: [String: NSImage] = [:]) {
        archivos = lista
        self.miniaturas = miniaturas
        cargando = false
    }

    /// Pide las miniaturas que faltan (y devuelve cuántas pidió).
    @discardableResult
    func pedirMiniaturas() -> Int {
        let mia = generacion
        var pedidas = 0
        for a in archivos where miniaturas[a.ruta] == nil && peticiones[a.ruta] == nil {
            let ruta = a.ruta
            let peticion = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: ruta), size: CGSize(width: Self.ladoMiniatura, height: Self.ladoMiniatura),
                                                        scale: escala, representationTypes: .all)
            peticiones[ruta] = peticion
            pedidas += 1
            QLThumbnailGenerator.shared.generateBestRepresentation(for: peticion) { representacion, _ in
                let imagen = representacion.map { NSImage(cgImage: $0.cgImage, size: NSSize(width: Self.ladoMiniatura, height: Self.ladoMiniatura)) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        guard let self, self.generacion == mia else { return }
                        self.peticiones[ruta] = nil
                        self.miniaturas[ruta] = imagen ?? NSWorkspace.shared.icon(forFile: ruta)
                    }
                }
            }
        }
        return pedidas
    }

    var pendientes: Int { peticiones.count }

    private func recargar() {
        let ruta = self.ruta
        let mia = generacion
        Task.detached(priority: .utility) {
            let lista = Self.listar(ruta)
            await MainActor.run { [weak self] in
                guard let self, self.activo, self.generacion == mia else { return }
                self.cargando = false
                self.legible = lista != nil
                let nueva = lista ?? []
                if nueva != self.archivos { self.archivos = nueva }
                // Lo que ya no está en la lista pierde su miniatura.
                let vivas = Set(nueva.map(\.ruta))
                self.miniaturas = self.miniaturas.filter { vivas.contains($0.key) }
                self.pedirMiniaturas()
                self.alCambiar?()
            }
        }
    }

    /// Lo más reciente de la carpeta (hasta 40), fuera del hilo principal. nil si no se puede leer.
    nonisolated static func listar(_ ruta: String) -> [ArchivoReciente]? {
        let claves: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: ruta, isDirectory: true),
                                                                      includingPropertiesForKeys: claves, options: [.skipsHiddenFiles]) else { return nil }
        let todos = urls.map { u -> ArchivoReciente in
            let v = try? u.resourceValues(forKeys: Set(claves))
            return ArchivoReciente(nombre: u.lastPathComponent, ruta: u.path, modificado: v?.contentModificationDate ?? .distantPast,
                                   esCarpeta: v?.isDirectory ?? false)
        }
        return CarpetaDock.masRecientes(todos)
    }

    /// Vigila el directorio con DispatchSource (sin consultas periódicas): al cambiar, recarga 0,4 s después.
    private func vigilar() {
        let fd = open(ruta, O_EVTONLY)
        guard fd >= 0 else { return }
        let f = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .global(qos: .utility))
        f.setEventHandler { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.cambioEnDisco() } }
        }
        f.setCancelHandler { close(fd) }
        f.resume()
        fuente = f
    }

    private func cambioEnDisco() {
        guard activo else { return }
        recarga?.cancel()
        let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.recargar() } }
        recarga = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: tarea)
    }
}

/// Lo que se hace con un archivo del panel (clic derecho). Nada borra de verdad: la papelera es la del sistema.
enum AccionArchivo {
    static func abrir(_ a: ArchivoReciente) { NSWorkspace.shared.open(URL(fileURLWithPath: a.ruta)) }
    static func mostrarEnFinder(_ a: ArchivoReciente) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a.ruta)]) }
    static func vistaRapida(_ a: ArchivoReciente) { VistaRapidaDock.compartida.mostrar(URL(fileURLWithPath: a.ruta)) }
    /// Vista rápida de toda la lista, empezando por `a` (con flechas se pasa al siguiente).
    static func vistaRapida(_ a: ArchivoReciente, de lista: [ArchivoReciente]) {
        VistaRapidaDock.compartida.mostrar(lista.map { URL(fileURLWithPath: $0.ruta) }, actual: lista.firstIndex(of: a) ?? 0)
    }

    static func copiarArchivo(_ a: ArchivoReciente) {
        let p = NSPasteboard.general
        p.clearContents()
        p.writeObjects([URL(fileURLWithPath: a.ruta) as NSURL])
    }

    static func copiarNombre(_ a: ArchivoReciente) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(a.nombre, forType: .string)
    }

    static func copiarRuta(_ a: ArchivoReciente) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(a.ruta, forType: .string)
    }

    /// A la Papelera del sistema (`NSWorkspace.recycle`): se puede devolver desde allí. Nunca borra para siempre.
    static func aLaPapelera(_ a: ArchivoReciente) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: a.ruta)]) { _, _ in }
    }

    /// Los textos del menú de clic derecho, en su orden (para la documentación y las pruebas).
    static let menu = ["Abrir", "Mostrar en Finder", "Vista rápida", "Copiar archivo", "Copiar nombre", "Copiar ruta", "Mover a la papelera"]
}

/// Vista rápida (la barra espaciadora del Finder) de los archivos del panel: se previsualiza el elegido y con las flechas se pasa
/// a los demás de la carpeta. Al volver a pulsar Espacio (o Esc) se cierra.
final class VistaRapidaDock: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let compartida = VistaRapidaDock()
    private var urls: [URL] = []
    /// Se llama al cerrarse con el índice en que quedó (el panel de la carpeta lo vuelve a seleccionar) y al abrirse/cerrarse.
    var alCerrar: ((Int) -> Void)?
    var visible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible && QLPreviewPanel.shared().dataSource === self }

    func mostrar(_ url: URL) { mostrar([url], actual: 0) }

    func mostrar(_ lista: [URL], actual: Int) {
        guard !lista.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        urls = lista
        panel.dataSource = self
        panel.delegate = self
        panel.level = NSWindow.Level(rawValue: Dock.nivelBaseVisible + 2)
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(actual, 0), lista.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Espacio con la vista abierta la cierra; cerrada, la abre.
    func alternar(_ lista: [URL], actual: Int) {
        if visible { cerrar() } else { mostrar(lista, actual: actual) }
    }

    func cerrar() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), visible else { return }
        let panel = QLPreviewPanel.shared()
        let i = panel?.currentPreviewItemIndex ?? 0
        panel?.orderOut(nil)
        alCerrar?(i)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }

    /// Esc, Espacio y flechas dentro de la vista rápida.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 || event.keyCode == 49 { cerrar(); return true }
        return false
    }

    /// Suelta la referencia al cerrar el Dock.
    func soltar() {
        urls = []
        alCerrar = nil
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        let panel = QLPreviewPanel.shared()
        if panel?.dataSource === self { panel?.orderOut(nil) }
        if panel?.dataSource === self { panel?.dataSource = nil }
        if panel?.delegate === self { panel?.delegate = nil }
    }
}

// MARK: - La papelera

enum PapeleraDock {
    /// ¿Hay algo en la Papelera? Con Acceso total al disco se lee la carpeta (`.trashDirectory`). Sin él macOS no deja listarla, pero
    /// sí dice cuántos elementos tiene (cuenta de entradas del directorio y, si no, los enlaces de `stat`): esa es la otra señal.
    nonisolated static func llena() -> Bool {
        let url = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/.Trash", isDirectory: true)
        let listado = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        var entradas = (try? url.resourceValues(forKeys: [.directoryEntryCountKey]))?.directoryEntryCount
        if entradas == nil {
            var st = stat()
            if stat(url.path, &st) == 0 { entradas = max(0, Int(st.st_nlink) - 2) }
        }
        return EstadoPapelera.llena(listado: listado, entradas: entradas)
    }

    @MainActor static func abrir() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash", isDirectory: true))
    }
}

// MARK: - El estado del Dock

/// Lo que el Dock puede hacer fuera de sí mismo. En los renders no hace nada.
struct AccionesDock {
    var abrirPestana: (EstadoIsla.Pestana) -> Void = { _ in }
    var dictar: () -> Void = {}
    var dictarEncargo: () -> Void = {}
    var unirse: (URL) -> Void = { _ in }
    /// Despliega la carpeta o el grupo hacia arriba, anclado a la mitad de su mosaico (coordenadas del Dock).
    var desplegar: (_ clave: String, _ ancla: CGFloat) -> Void = { _, _ in }
    /// Ventanas flotantes de una app abierta: programa el panel (o lo abre ya) y cancela cuando el puntero se va.
    var ventanasProgramar: (_ app: EntradaApp, _ ancla: CGFloat, _ ya: Bool) -> Void = { _, _, _ in }
    var ventanasCancelar: () -> Void = {}
    var elegirEspacio: (EspacioIsla) -> Void = { _ in }
    var masEspacios: () -> Void = {}
    var abrirSalud: () -> Void = {}
    var abrirLanzador: () -> Void = {}
}

/// Todo lo que leen las vistas del Dock. Los datos (agenda, música, agentes, tareas, foco, salud, espacios, apps) son los de la
/// isla: una sola fuente de verdad; el espacio actual es el del lanzador de la isla.
@MainActor @Observable
final class EstadoDock {
    let agenda: Agenda
    let musica: Musica
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let foco: Foco
    let tareas: TareasIsla?
    /// El Tablero del centro: de él salen las cuentas de la pieza de agentes (si no hay, de las sesiones de Claude).
    var tablero: TableroIsla?
    let salud: EstadoSalud
    let hud: EstadoHUD
    let estadoIsla: EstadoIsla
    let lanzador: LanzadorIsla
    let apps: AppsUsadas
    /// El clima (el mismo del lanzador): la pieza avisa cuando se ve y cuando se esconde.
    var clima = ClimaModelo.compartido

    /// El plan de Mañana (hoy y semana): el mismo para todas las pantallas.
    let plan = PlanManana.compartido
    let reloj = RelojMinuto()
    let abiertas = AppsAbiertasDock()
    let bateria = BateriaDock()
    let finder = FinderVentanasDock()
    private(set) var papeleraLlena = false
    private(set) var iconos: [String: NSImage] = [:]
    /// La clave de la carpeta o el grupo que tiene el panel abierto (resalta su mosaico).
    var desplegado: String?
    /// El centro de cada app en el Dock (para anclar su panel de ventanas desde el menú).
    @ObservationIgnored var anclasApp: [String: CGFloat] = [:]
    var acciones = AccionesDock()
    /// Renders: la hora y el vidrio simulado se fijan desde fuera.
    var ahoraFijo: Date?
    /// `iconos.txt`: un icono propio por app (Cra, por ejemplo). Se lee al mostrarse el Dock.
    @ObservationIgnored private var iconosPropios: [String: String] = [:]
    @ObservationIgnored var alCambiarFinder: (() -> Void)?
    @ObservationIgnored private var indice: [String: EntradaApp] = [:]
    @ObservationIgnored private var indiceDe = -1
    @ObservationIgnored private var pidiendo = Set<String>()
    @ObservationIgnored private let vivo: Bool

    init(agenda: Agenda, musica: Musica, claude: SesionesClaude, agentes: AgentesRemotos, foco: Foco, tareas: TareasIsla?, salud: EstadoSalud,
         hud: EstadoHUD, estadoIsla: EstadoIsla, lanzador: LanzadorIsla, apps: AppsUsadas, vivo: Bool = true) {
        self.agenda = agenda
        self.musica = musica
        self.claude = claude
        self.agentes = agentes
        self.foco = foco
        self.tareas = tareas
        self.salud = salud
        self.hud = hud
        self.estadoIsla = estadoIsla
        self.lanzador = lanzador
        self.apps = apps
        self.vivo = vivo
    }

    var ahora: Date { ahoraFijo ?? reloj.ahora }
    /// Renders: no se pide nada al centro.
    var hayTablero: Bool { vivo }

    // MARK: Ciclo de vida

    /// El Dock se ve: arranca lo que solo hace falta mientras se ve.
    func alMostrar() {
        guard vivo else { return }
        reloj.iniciar()
        abiertas.iniciar()
        bateria.iniciar()
        iconosPropios = EstadoDock.leerIconosPropios()
        finder.alCambiar = { [weak self] in self?.alCambiarFinder?() }
        finder.iniciar(fijas: { [weak self] in
            Set(self?.piezasConfiguradas.compactMap { if case .carpeta(let r) = $0 { return r } else { return nil } } ?? [])
        })
        lanzador.leerEspacios()
        apps.refrescar()
        agenda.refrescar()
        tareas?.refrescar()
        Task.detached(priority: .utility) {
            let llena = PapeleraDock.llena()
            await MainActor.run { [weak self] in self?.papeleraLlena = llena }
        }
    }

    /// El Dock se esconde: se para todo y se sueltan los íconos.
    func alOcultar() {
        reloj.detener()
        abiertas.detener()
        bateria.detener()
        finder.detener()
        iconosPropios = [:]
        iconos = [:]
        pidiendo = []
        desplegado = nil
        VistaRapidaDock.compartida.soltar()
    }

    // MARK: Espacios y piezas

    var espacios: [EspacioIsla] { lanzador.espacios }
    var espacioActual: EspacioIsla? { lanzador.espacio }

    private func reindexar() {
        guard indiceDe != apps.catalogo.count else { return }
        indiceDe = apps.catalogo.count
        var d: [String: EntradaApp] = [:]
        for a in apps.catalogo {
            if let id = a.bundleID, d[id] == nil { d[id] = a }
            let n = BusquedaApps.normalizar(a.nombre)
            if d[n] == nil { d[n] = a }
        }
        indice = d
    }

    /// Una app por nombre o identificador (nil si no está instalada).
    func app(_ clave: String) -> EntradaApp? {
        reindexar()
        return indice[clave] ?? indice[BusquedaApps.normalizar(clave)]
    }

    /// Las apps de un grupo (una carpeta de `carpetas.txt`), instaladas y en el orden del archivo.
    func appsDelGrupo(_ nombre: String) -> [EntradaApp] {
        guard let c = lanzador.carpetas.first(where: { BusquedaApps.normalizar($0.nombre) == BusquedaApps.normalizar(nombre) }) else { return [] }
        return CarpetasApps.resolver(c, instaladas: apps.catalogo)
    }

    /// Las piezas que dice el espacio actual (su línea `dock:` o las de siempre), tal cual y sin filtrar.
    var piezasConfiguradas: [PiezaDock] {
        let masUsadas = MasUsadas.conFijas(fijas: Ajustes.fijasDeLaIsla, instaladas: Set(apps.catalogo.compactMap(\.bundleID)),
                                           resto: apps.apps.map { $0.bundleID ?? $0.nombre })
        return espacioActual?.piezasDock(masUsadas: masUsadas) ?? ReglasDock.porOmision(masUsadas: masUsadas)
    }

    /// Las apps abiertas que no están fijas en el Dock (lo que muestra la pila "Abiertas").
    var abiertasNoFijas: [EntradaApp] {
        let fijas = Set(piezasConfiguradas.compactMap { p -> String? in
            if case .app(let c) = p { return app(c)?.id }
            return nil
        })
        return abiertas.lista.filter { !fijas.contains($0.id) }
    }

    /// Las piezas del espacio actual, sin las que no tienen de dónde salir (una app sin instalar, un grupo sin apps, la batería de
    /// un Mac de escritorio, la agenda sin permiso de Calendario, la pila de abiertas sin apps) y con las carpetas abiertas en el
    /// Finder en el lugar de `finder`.
    var piezas: [PiezaDock] {
        let configuradas = piezasConfiguradas
        var utiles: [PiezaDock] = []
        for p in configuradas {
            switch p {
            case .app(let c): if app(c) != nil { utiles.append(p) }
            case .grupo(let n): if !appsDelGrupo(n).isEmpty { utiles.append(p) }
            case .bateria: if bateria.existe { utiles.append(p) }
            case .agenda: if agenda.permitido || !agenda.eventos.isEmpty { utiles.append(p) }
            case .abiertas: if !abiertasNoFijas.isEmpty { utiles.append(p) }
            case .finder: utiles += finder.rutas.map { .carpeta($0) }
            default: utiles.append(p)
            }
        }
        return ReglasDock.limpiarHuecos(utiles)
    }

    /// ¿Es una carpeta abierta en el Finder (y no una fija)? Lleva su indicador hasta que se cierre la ventana.
    func esCarpetaDeFinder(_ ruta: String) -> Bool { finder.rutas.contains(ruta) }

    nonisolated static func leerIconosPropios() -> [String: String] {
        let url = Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("iconos.txt")
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return IconosPersonalizados.leer(texto)
    }

    // MARK: Fijar y quitar apps

    func estaFija(_ app: EntradaApp) -> Bool { ReglasDock.tieneApp(piezasConfiguradas, id: app.bundleID ?? app.nombre, nombre: app.nombre) }

    /// "Mantener en el Dock" / "Quitar del Dock": cambia la línea `dock:` del espacio actual en `espacios.txt` (con copia
    /// `.respaldo-<fecha>` la primera vez del día; lo demás del archivo queda igual).
    func alternarFija(_ app: EntradaApp) {
        guard let nombre = lanzador.espacioActual ?? lanzador.espacios.first?.nombre else { return }
        let nuevas = ReglasDock.alternarApp(piezasConfiguradas, id: app.bundleID ?? app.nombre, nombre: app.nombre)
        let linea = ReglasDock.serializar(nuevas)
        if let i = lanzador.espacios.firstIndex(where: { $0.nombre == nombre }) { lanzador.espacios[i].dock = linea }
        guard vivo else { return }
        Task.detached(priority: .utility) {
            let archivo = LanzadorIsla.archivoEspacios
            guard let actual = try? String(contentsOf: archivo, encoding: .utf8) else { return }
            let nuevo = ReglasDock.reemplazarLineaDock(en: actual, espacio: nombre, por: linea)
            guard nuevo != actual else { return }
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            let respaldo = archivo.deletingLastPathComponent().appendingPathComponent("espacios.txt.respaldo-" + f.string(from: Date()))
            if !FileManager.default.fileExists(atPath: respaldo.path) { try? FileManager.default.copyItem(at: archivo, to: respaldo) }
            try? nuevo.write(to: archivo, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Íconos

    /// Pide (sin bloquear) el ícono de cada app que se ve y aún no está.
    func pedirIconos(de lista: [EntradaApp]) {
        guard vivo else { return }
        let faltan = lista.filter { iconos[$0.id] == nil && !pidiendo.contains($0.id) }
        guard !faltan.isEmpty else { return }
        pidiendo.formUnion(faltan.map(\.id))
        let pares = faltan.map { ($0.id, $0.ruta, IconosPersonalizados.ruta($0, en: iconosPropios)) }
        Task.detached(priority: .userInitiated) {
            var salida: [String: NSImage] = [:]
            for (id, ruta, propio) in pares { salida[id] = propio.flatMap { Self.iconoPropio($0) } ?? CatalogoApps.icono(ruta) }
            let hecho = salida
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.iconos.merge(hecho) { $1 }
                self.pidiendo.subtract(pares.map(\.0))
            }
        }
    }

    /// Un PNG propio dibujado en un mapa de bits del tamaño del icono (a 2×).
    nonisolated static func iconoPropio(_ ruta: String) -> NSImage? {
        guard let original = NSImage(contentsOfFile: ruta) else { return nil }
        let lado = AuroraMedida.icono
        let imagen = NSImage(size: NSSize(width: lado, height: lado))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(lado * 2), pixelsHigh: Int(lado * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let contexto = NSGraphicsContext(bitmapImageRep: rep) else { return original }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexto
        contexto.imageInterpolation = .high
        original.draw(in: NSRect(x: 0, y: 0, width: lado * 2, height: lado * 2), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: lado, height: lado)
        imagen.addRepresentation(rep)
        return imagen
    }

    /// Todas las apps que las piezas actuales necesitan (sueltas, de grupos y de la pila de abiertas).
    var appsVisibles: [EntradaApp] {
        piezas.flatMap { p -> [EntradaApp] in
            switch p {
            case .app(let c): return app(c).map { [$0] } ?? []
            case .grupo(let n): return Array(appsDelGrupo(n).prefix(9))
            case .abiertas: return abiertasNoFijas
            default: return []
            }
        }
    }

    /// Renders: íconos ya armados.
    func fijarIconos(_ d: [String: NSImage]) { iconos = d }
    func fijarPapelera(llena: Bool) { papeleraLlena = llena }
}
