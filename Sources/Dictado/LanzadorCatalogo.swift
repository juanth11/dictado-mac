import AppKit
import CoreServices
import DictadoKit
import Observation

/// Las apps instaladas para el lanzador. Se lee en un hilo aparte: /Applications, /System/Applications (y su carpeta
/// Utilities), ~/Applications, una carpeta de profundidad dentro de las subcarpetas; sin repetir (por identificador de
/// paquete) y por nombre. Los íconos salen de NSWorkspace, también fuera del hilo principal, y solo se piden los de lo que
/// se ve. FSEvents avisa cuando cambia alguna carpeta: no hay consultas en bucle.
@MainActor @Observable
final class CatalogoApps {
    var apps: [EntradaApp] = []
    var iconos: [String: NSImage] = [:]
    /// Identificadores de las apps que están abiertas (para la píldora bajo el ícono).
    var abiertas: Set<String> = []

    @ObservationIgnored private var sucio = true
    @ObservationIgnored private var flujo: FSEventStreamRef?
    @ObservationIgnored private var generacion = 0
    @ObservationIgnored private var pidiendo = Set<String>()
    @ObservationIgnored private var recarga: DispatchWorkItem?
    /// Mientras el lanzador está abierto, un cambio en las carpetas lo recarga solo.
    @ObservationIgnored var abierto = false

    /// En orden de prioridad: si una app está en dos lugares, gana la primera.
    nonisolated static var carpetas: [String] {
        ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications", "/System/Applications/Utilities"]
    }

    init(vivo: Bool = true) {
        if vivo { vigilar() }
    }

    /// Lo que hace falta al abrir: recargar si las carpetas cambiaron (o es la primera vez) y ver qué apps están abiertas.
    func alAbrir() {
        abierto = true
        actualizarAbiertas()
        if sucio || apps.isEmpty { cargar() }
    }

    func alCerrar() {
        abierto = false
        recarga?.cancel()
        iconos = [:]
        pidiendo = []
    }

    func actualizarAbiertas() {
        abiertas = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
    }

    func cargar() {
        sucio = false
        generacion += 1
        let mia = generacion
        Task.detached(priority: .userInitiated) {
            let lista = Self.escanear(Self.carpetas)
            await MainActor.run { [weak self] in
                guard let self, self.generacion == mia else { return }
                if lista != self.apps { self.apps = lista }
            }
        }
    }

    /// Lee las carpetas (sin tocar el hilo principal). Una carpeta que no es `.app` se mira un nivel adentro.
    nonisolated static func escanear(_ carpetas: [String]) -> [EntradaApp] {
        let fm = FileManager.default
        var encontradas: [EntradaApp] = []
        func agregar(_ url: URL) {
            let nombre = fm.displayName(atPath: url.path)
            let limpio = nombre.hasSuffix(".app") ? String(nombre.dropLast(4)) : nombre
            encontradas.append(EntradaApp(nombre: limpio, ruta: url.path, bundleID: Bundle(url: url)?.bundleIdentifier))
        }
        for carpeta in carpetas {
            let raiz = URL(fileURLWithPath: carpeta)
            guard let contenido = try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { continue }
            for url in contenido {
                if url.pathExtension == "app" {
                    agregar(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let dentro = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for hijo in dentro where hijo.pathExtension == "app" { agregar(hijo) }
                }
            }
        }
        return BusquedaApps.depurar(encontradas)
    }

    // MARK: Íconos

    /// Pide (sin bloquear) los íconos que aún no están. Se llama con lo que se ve: la página actual o los resultados.
    func pedirIconos(_ lista: [EntradaApp]) {
        let faltan = lista.filter { iconos[$0.id] == nil && !pidiendo.contains($0.id) }
        guard !faltan.isEmpty else { return }
        let pares = faltan.map { ($0.id, $0.ruta) }
        pidiendo.formUnion(pares.map(\.0))
        Task.detached(priority: .userInitiated) {
            var salida: [String: NSImage] = [:]
            for (id, ruta) in pares { salida[id] = Self.icono(ruta) }
            let hecho = salida
            await MainActor.run { [weak self] in
                guard let self, self.abierto else { return }
                self.iconos.merge(hecho) { $1 }
                self.pidiendo.subtract(pares.map(\.0))
            }
        }
    }

    /// El ícono dibujado en un mapa de bits del tamaño justo (70 pt a 2×): liviano y sin sorpresas al dibujarlo.
    nonisolated static func icono(_ ruta: String) -> NSImage {
        // Un icono propio de iconos.txt (Cra con su logo nuevo, por ejemplo) manda aquí también: lanzador, Inicio y Dock iguales.
        if let propio = iconoPropio(deApp: ruta) { return propio }
        let lado = AuroraMedida.icono
        let pixeles = Int(lado * 2)
        let imagen = NSImage(size: NSSize(width: lado, height: lado))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixeles, pixelsHigh: pixeles, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let contexto = NSGraphicsContext(bitmapImageRep: rep) else { return NSWorkspace.shared.icon(forFile: ruta) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexto
        NSWorkspace.shared.icon(forFile: ruta).draw(in: NSRect(x: 0, y: 0, width: pixeles, height: pixeles), from: .zero,
                                                    operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: lado, height: lado)
        imagen.addRepresentation(rep)
        return imagen
    }

    /// `iconos.txt`, leído una vez (cambiarlo pide reabrir Dictado).
    nonisolated private static let iconosPropios: [String: String] = EstadoDock.leerIconosPropios()

    nonisolated private static func iconoPropio(deApp ruta: String) -> NSImage? {
        guard !iconosPropios.isEmpty, ruta.hasSuffix(".app") else { return nil }
        let nombre = URL(fileURLWithPath: ruta).deletingPathExtension().lastPathComponent
        let entrada = EntradaApp(nombre: nombre, ruta: ruta, bundleID: Bundle(path: ruta)?.bundleIdentifier)
        return IconosPersonalizados.ruta(entrada, en: iconosPropios).flatMap { EstadoDock.iconoPropio($0) }
    }

    // MARK: Vigilancia de carpetas

    private func vigilar() {
        let existentes = Self.carpetas.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existentes.isEmpty else { return }
        var contexto = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let nuevo = FSEventStreamCreate(nil, { _, info, cuantos, rutas, _, _ in
            guard let info else { return }
            let lista = (Unmanaged<CFArray>.fromOpaque(rutas).takeUnretainedValue() as? [String]) ?? []
            // Lo que pasa dentro de un .app (actualizaciones, cachés) no cambia la lista.
            guard lista.prefix(cuantos).contains(where: { !$0.contains(".app/") }) else { return }
            let yo = Unmanaged<CatalogoApps>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { yo.cambioEnCarpetas() }
        }, &contexto, existentes as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
           FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(nuevo, .main)
        FSEventStreamStart(nuevo)
        flujo = nuevo
    }

    private func cambioEnCarpetas() {
        sucio = true
        guard abierto else { return }
        recarga?.cancel()
        let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.cargar() } }
        recarga = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: tarea)
    }
}
