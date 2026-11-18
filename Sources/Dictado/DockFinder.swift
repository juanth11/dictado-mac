import AppKit
import ApplicationServices
import DictadoKit
import Observation

// Las carpetas que tienes abiertas en el Finder, para que aparezcan en el Dock y se queden hasta que cierres su ventana.
// Se lee por Accesibilidad (la app ya la tiene para los atajos de ventanas): cada ventana del Finder dice su carpeta en
// `AXDocument`. Nada se consulta en bucle: un AXObserver avisa cuando se abre, se cierra o cambia de carpeta una ventana, y solo
// vive mientras el Dock se ve. Sin permiso de Accesibilidad no hace nada (el Dock sigue igual, sin estas carpetas).

@MainActor @Observable
final class FinderVentanasDock {
    private(set) var rutas: [String] = []
    /// Cuántas carpetas abiertas se muestran como mucho.
    static let maximo = 4
    @ObservationIgnored var alCambiar: (() -> Void)?
    @ObservationIgnored private var observador: AXObserver?
    @ObservationIgnored private var app: AXUIElement?
    @ObservationIgnored private var observadas: [AXUIElement] = []
    @ObservationIgnored private var pendiente: DispatchWorkItem?
    @ObservationIgnored private var avisos: [NSObjectProtocol] = []
    @ObservationIgnored private var caja: Unmanaged<Caja>?
    @ObservationIgnored private var fijas: () -> Set<String> = { [] }
    @ObservationIgnored private var generacion = 0

    private final class Caja { weak var modelo: FinderVentanasDock? }

    func iniciar(fijas: @escaping () -> Set<String>) {
        detener()
        self.fijas = fijas
        guard AXIsProcessTrusted() else { return }
        conectar()
        let centro = NSWorkspace.shared.notificationCenter
        for nombre in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            avisos.append(centro.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] aviso in
                let id = (aviso.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { if id == "com.apple.finder" { self?.conectar() } }
            })
        }
    }

    func detener() {
        generacion += 1
        pendiente?.cancel()
        pendiente = nil
        avisos.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        avisos = []
        desconectar()
        rutas = []
    }

    private func desconectar() {
        if let o = observador { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observador = nil
        app = nil
        observadas = []
        caja?.release()
        caja = nil
    }

    private func conectar() {
        desconectar()
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            rutas = []
            return
        }
        let c = Caja()
        c.modelo = self
        let puntero = Unmanaged.passRetained(c)
        var o: AXObserver?
        let callback: AXObserverCallback = { _, _, _, ctx in
            guard let ctx else { return }
            let caja = Unmanaged<Caja>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { caja.modelo?.programarLectura() }
        }
        guard AXObserverCreate(finder.processIdentifier, callback, &o) == .success, let o else {
            puntero.release()
            return
        }
        caja = puntero
        observador = o
        let elemento = AXUIElementCreateApplication(finder.processIdentifier)
        app = elemento
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(o, elemento, n as CFString, puntero.toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        programarLectura()
    }

    /// Junta varios avisos seguidos en una sola lectura (0,25 s después).
    private func programarLectura() {
        pendiente?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.leer() } }
        pendiente = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: t)
    }

    private func leer() {
        guard let app, let o = observador, let puntero = caja else { return }
        let mia = generacion
        var ventanas: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ventanas) == .success, let lista = ventanas as? [AXUIElement] else {
            aplicar([])
            return
        }
        // Cada ventana nueva avisa cuando se cierra o cambia de carpeta.
        for v in lista where !observadas.contains(where: { CFEqual($0, v) }) {
            observadas.append(v)
            for n in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(o, v, n as CFString, puntero.toOpaque())
            }
        }
        observadas.removeAll { v in !lista.contains(where: { CFEqual($0, v) }) }
        var documentos: [String] = []
        for v in lista {
            var doc: CFTypeRef?
            if AXUIElementCopyAttributeValue(v, kAXDocumentAttribute as CFString, &doc) == .success, let d = doc as? String { documentos.append(d) }
        }
        guard generacion == mia else { return }
        let fijadas = fijas()
        let nuevas = FinderAbiertas.rutas(documentos: documentos, fijas: fijadas) { r in
            var esCarpeta: ObjCBool = false
            return FileManager.default.fileExists(atPath: r, isDirectory: &esCarpeta) && esCarpeta.boolValue
        }
        aplicar(Array(nuevas.prefix(Self.maximo)))
    }

    private func aplicar(_ nuevas: [String]) {
        guard nuevas != rutas else { return }
        rutas = nuevas
        alCambiar?()
    }

    /// Renders y pruebas: carpetas ya dadas.
    func fijar(_ r: [String]) { rutas = r }
}
