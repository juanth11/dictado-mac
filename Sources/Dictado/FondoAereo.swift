import AppKit
import AVFoundation
import DictadoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Los fondos de macOS que un espacio puede pedir con `fondo:`: los de sistema por nombre (`fondo: Sonoma`) y los aéreos animados
// (`fondo: aereo:Patagonia`). Aquí vive lo que toca el disco y el video; la lógica pura (leer el catálogo, elegir por nombre) está en
// `DictadoKit/CatalogoFondos.swift`.
//
// De dónde sale cada cosa (todo solo lectura, nada se descarga):
//   · Fondos estáticos: `/System/Library/Desktop Pictures/*.heic` y `.wallpapers/*/*.heic` (vienen con macOS) y
//     `~/Library/Application Support/com.apple.mobileAssetDesktop/*.heic` (los que macOS bajó al elegirlos en Ajustes del Sistema).
//     Los `.madesktop` de /System son solo marcadores: sin su archivo real en la segunda carpeta no hay nada que poner.
//   · Aéreos: el catálogo es `/Library/Application Support/com.apple.idleassetsd/Customer/entries.json` (137 entradas) y el video, si
//     está bajado, `Customer/4KSDR240FPS/<id>.mov` (o `2KSDR`, `2KHDR`). Se baja una vez en Ajustes del Sistema → Salvapantallas o Fondo
//     de pantalla.
//
// Cómo se aplica un aéreo:
//   · Lanzador y Centro: el `.mov` se reproduce en bucle, mudo, pausado si la ventana no se ve y quieto con "Reducir movimiento"
//     (`FondoAereoVista`).
//   · Escritorio: macOS NO ofrece una API para poner un aéreo como fondo de escritorio (`NSWorkspace.setDesktopImageURL` solo acepta
//     imágenes). Se pone un cuadro fijo del mismo aéreo, sacado con `AVAssetImageGenerator` y guardado en
//     `~/Library/Application Support/Dictado/fondos/<nombre>.heic`.
//
// Poner el aéreo de verdad en el escritorio (APAGADO, `AereoEnEscritorio`): exigiría escribir
// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` (en `Displays/<id>/Desktop/Content/Choices` un elemento con
// `Provider = com.apple.wallpaper.choice.aerials` y `Configuration` = plist binario `{assetID: <id>}`; el de Salvapantallas, que ya trae
// Patagonia, está en `Idle`) y reiniciar `WallpaperAgent`. Es un formato privado que cambia entre versiones de macOS; un error deja el
// fondo roto o repetido en todos los Spaces. Por eso no se escribe: el ajuste existe, pero apagado y sin efecto.

// MARK: - Dónde están

enum FondosMac {
    /// Las carpetas con fondos estáticos, de las más a las menos "de fábrica".
    static var carpetasSistema: [String] {
        ["/System/Library/Desktop Pictures", "/System/Library/Desktop Pictures/.wallpapers", "/Library/Desktop Pictures",
         NSHomeDirectory() + "/Library/Application Support/com.apple.mobileAssetDesktop"]
    }

    static let catalogos = ["/Library/Application Support/com.apple.idleassetsd/Customer/entries.json",
                            NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"]
    static let carpetasVideo = ["/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS",
                                "/Library/Application Support/com.apple.idleassetsd/Customer/2KSDR",
                                "/Library/Application Support/com.apple.idleassetsd/Customer/2KHDR",
                                NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/aerials/videos"]
    static let carpetaMiniaturas = NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/aerials/thumbnails"

    /// Donde se guardan los cuadros fijos de los aéreos.
    static var carpetaCuadros: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictado/fondos", isDirectory: true)
    }

    // MARK: Fondos de sistema

    /// Todos los archivos de imagen de las carpetas de fondos (uno o dos niveles adentro: `.wallpapers/Sonoma Horizon/…`).
    static func archivosSistema(carpetas: [String] = carpetasSistema) -> [String] {
        let fm = FileManager.default
        var salida: [String] = []
        for c in carpetas {
            guard let nombres = try? fm.contentsOfDirectory(atPath: c) else { continue }
            for n in nombres {
                let ruta = c + "/" + n
                var esCarpeta: ObjCBool = false
                guard fm.fileExists(atPath: ruta, isDirectory: &esCarpeta) else { continue }
                if esCarpeta.boolValue {
                    if n == ".thumbnails" || n == "Solid Colors" { continue }
                    for dentro in (try? fm.contentsOfDirectory(atPath: ruta)) ?? [] { salida.append(ruta + "/" + dentro) }
                } else {
                    salida.append(ruta)
                }
            }
        }
        return salida
    }

    static func archivoSistema(_ nombre: String, carpetas: [String] = carpetasSistema) -> URL? {
        CatalogoFondos.elegirSistema(nombre, entre: archivosSistema(carpetas: carpetas)).map { URL(fileURLWithPath: $0) }
    }

    // MARK: Aéreos

    static func catalogoAereos() -> [AereoMac] {
        for ruta in catalogos {
            if let texto = try? String(contentsOfFile: ruta, encoding: .utf8) {
                let a = CatalogoFondos.aereos(json: texto)
                if !a.isEmpty { return a }
            }
        }
        return []
    }

    /// El video de un aéreo si ya está en el Mac (`<id>.mov` en alguna de las carpetas de video).
    static func videoLocal(id: String, carpetas: [String] = carpetasVideo) -> URL? {
        for c in carpetas {
            for ext in ["mov", "m4v", "mp4"] {
                let ruta = c + "/" + id + "." + ext
                if FileManager.default.isReadableFile(atPath: ruta) { return URL(fileURLWithPath: ruta) }
            }
        }
        return nil
    }

    struct AereoLocal {
        let aereo: AereoMac
        /// nil si todavía no se descargó en Ajustes del Sistema.
        let video: URL?
    }

    /// Resuelve `aereo:<consulta>` con lo que hay en el Mac: el catálogo y cuáles ya tienen video.
    static func resolverAereo(_ consulta: String, catalogo: [AereoMac]? = nil, carpetas: [String] = carpetasVideo) -> AereoLocal? {
        let todos = catalogo ?? catalogoAereos()
        let bajados = Set(todos.filter { videoLocal(id: $0.id, carpetas: carpetas) != nil }.map(\.id))
        guard let a = CatalogoFondos.elegirAereo(consulta, entre: todos, descargados: bajados) else { return nil }
        return AereoLocal(aereo: a, video: bajados.contains(a.id) ? videoLocal(id: a.id, carpetas: carpetas) : nil)
    }

    static func miniatura(de a: AereoMac) -> URL? {
        let u = URL(fileURLWithPath: carpetaMiniaturas + "/" + a.id + ".png")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: El cuadro fijo

    static func cuadroGuardado(de a: AereoMac) -> URL? {
        for ext in ["heic", "png"] {
            let u = carpetaCuadros.appendingPathComponent(CatalogoFondos.nombreDeCuadro(a) + "." + ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Lo que va como imagen fija: el cuadro guardado; si no, un cuadro del video; si no, la miniatura del catálogo.
    static func imagenFija(de r: AereoLocal) -> URL? { cuadroGuardado(de: r.aereo) ?? r.video ?? miniatura(de: r.aereo) }

    /// El archivo que va al escritorio para un fondo del espacio, sin esperar: una imagen, un fondo de sistema o el cuadro ya guardado de
    /// un aéreo. nil: no hay (el aéreo sin cuadro todavía necesita `prepararEscritorio`).
    static func archivoEscritorio(_ f: FondoLanzador) -> URL? {
        switch f {
        case .imagen(let ruta): return FileManager.default.fileExists(atPath: ruta) ? URL(fileURLWithPath: ruta) : nil
        case .sistema(let n): return archivoSistema(n)
        case .aereo(let n): return resolverAereo(n).flatMap { cuadroGuardado(de: $0.aereo) }
        case .mac, .paleta: return nil
        }
    }

    /// Como `archivoEscritorio`, pero si es un aéreo con video y sin cuadro, lo saca ahora (unos segundos: el video es 4K a 240 cuadros).
    static func prepararEscritorio(_ f: FondoLanzador) async -> URL? {
        guard case .aereo(let n) = f else { return archivoEscritorio(f) }
        guard let r = resolverAereo(n) else { return nil }
        if let hay = cuadroGuardado(de: r.aereo) { return hay }
        guard let video = r.video else { return nil }
        return await extraerCuadro(de: video, aereo: r.aereo)
    }

    /// Mira 8 cuadros repartidos en el video (sin los extremos), elige el más bonito (detalle y luz media) y lo guarda como HEIC (o PNG).
    nonisolated static func extraerCuadro(de video: URL, aereo: AereoMac, lado: CGFloat = 3024) async -> URL? {
        let activo = AVURLAsset(url: video)
        guard let duracion = try? await activo.load(.duration), duracion.seconds > 1 else { return nil }
        let g = AVAssetImageGenerator(asset: activo)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: lado, height: lado)
        g.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        g.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        var cuadros: [CGImage] = []
        for i in 1...8 {
            let t = CMTime(seconds: min(duracion.seconds, 120) * Double(i) / 9, preferredTimescale: 600)
            if let c = try? await g.image(at: t).image { cuadros.append(c) }
        }
        let medidas = cuadros.map { LectorFondo.luminanciaYContraste($0) }
        guard let mejor = CatalogoFondos.cuadroBonito(luminancias: medidas.map(\.0), contrastes: medidas.map(\.1)) else { return nil }
        let carpeta = carpetaCuadros
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let nombre = CatalogoFondos.nombreDeCuadro(aereo)
        for (ext, tipo) in [("heic", UTType.heic), ("png", UTType.png)] {
            let destino = carpeta.appendingPathComponent(nombre + "." + ext)
            guard let d = CGImageDestinationCreateWithURL(destino as CFURL, tipo.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(d, cuadros[mejor], [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            if CGImageDestinationFinalize(d) { return destino }
        }
        return nil
    }
}

extension LectorFondo {
    /// La luminancia media y el contraste (desviación de la luminancia, 0 a 1) de una imagen dibujada en 24 × 24.
    nonisolated static func luminanciaYContraste(_ imagen: CGImage) -> (Double, Double) {
        let n = 24
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let ok = bytes.withUnsafeMutableBytes { crudo -> Bool in
            guard let c = CGContext(data: crudo.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.interpolationQuality = .medium
            c.draw(imagen, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return (0, 0) }
        let ls = (0..<(n * n)).map { LuminanciaFondo.luminancia(r: Double(bytes[$0 * 4]) / 255, g: Double(bytes[$0 * 4 + 1]) / 255, b: Double(bytes[$0 * 4 + 2]) / 255) }
        let media = ls.reduce(0, +) / Double(ls.count)
        let varianza = ls.reduce(0) { $0 + ($1 - media) * ($1 - media) } / Double(ls.count)
        return (media, varianza.squareRoot())
    }
}

// MARK: - Aéreo en el escritorio (apagado)

/// Poner el aéreo mismo en el escritorio exige escribir el `Store/Index.plist` de com.apple.wallpaper (ver el comentario de arriba).
/// Está apagado y esta función no escribe nada: aunque el ajuste `fondos.aereoEnEscritorio` se active, solo avisa que no hay vía
/// soportada. El escritorio lleva siempre el cuadro fijo.
enum AereoEnEscritorio {
    static let clave = "fondos.aereoEnEscritorio"
    static var activado: Bool { UserDefaults.dictado.bool(forKey: clave) }
    /// Siempre false: no hay API pública y no se toca el plist del sistema.
    @discardableResult
    static func poner(_ aereo: AereoMac) -> Bool { false }
}

// MARK: - El aéreo vivo (lanzador y Centro)

/// El `.mov` en bucle detrás del lanzador o del Centro: mudo, sin controles, pausado si la ventana no se ve (cubierta u oculta) o si el
/// Mac pide "Reducir movimiento" (entonces solo queda la imagen fija de abajo). Repite sus primeros 45 s: un video de 9 minutos y 240
/// cuadros por segundo no necesita más para un fondo.
struct FondoAereoVista: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> ReproductorAereo { ReproductorAereo(url: url) }

    func updateNSView(_ vista: ReproductorAereo, context: Context) {
        if vista.url != url { vista.cambiar(a: url) }
    }

    static func dismantleNSView(_ vista: ReproductorAereo, coordinator: ()) { vista.detener() }
}

final class ReproductorAereo: NSView {
    private(set) var url: URL
    private let capa = AVPlayerLayer()
    private var jugador: AVQueuePlayer?
    private var bucle: AVPlayerLooper?
    private var observaciones: [NSObjectProtocol] = []
    private var listo: NSKeyValueObservation?
    static let segundosDeBucle = 45.0

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        capa.videoGravity = .resizeAspectFill
        capa.opacity = 0
        layer?.addSublayer(capa)
        let nc = NotificationCenter.default
        observaciones.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizar() }
        })
        observaciones.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizar() }
        })
        observaciones.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizar() }
        })
        observaciones.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizar() }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capa.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        actualizar()
    }

    func cambiar(a nuevo: URL) {
        url = nuevo
        detener()
        actualizar()
    }

    /// ¿Debe moverse ahora? Con ventana visible, pantalla despierta y sin "Reducir movimiento".
    private var debeJugar: Bool {
        guard let w = window, w.occlusionState.contains(.visible), w.isVisible else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func actualizar() {
        if debeJugar {
            arrancar()
            jugador?.play()
        } else {
            jugador?.pause()
        }
    }

    private func arrancar() {
        guard jugador == nil else { return }
        let item = AVPlayerItem(url: url)
        item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.volume = 0
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.actionAtItemEnd = .none
        let rango = CMTimeRange(start: .zero, duration: CMTime(seconds: Self.segundosDeBucle, preferredTimescale: 600))
        bucle = AVPlayerLooper(player: p, templateItem: item, timeRange: rango)
        capa.player = p
        jugador = p
        listo = capa.observe(\.isReadyForDisplay, options: [.new]) { [weak self] c, _ in
            guard c.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.6)
                self?.capa.opacity = 1
                CATransaction.commit()
            }
        }
    }

    /// Para el video y suelta todo (cierra la memoria del decodificador).
    func detener() {
        jugador?.pause()
        bucle?.disableLooping()
        bucle = nil
        capa.player = nil
        capa.opacity = 0
        listo = nil
        jugador = nil
    }

    deinit {
        for o in observaciones { NotificationCenter.default.removeObserver(o); NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}

// MARK: - Prueba (sin ventanas ni cambiar el fondo del Mac)

/// `Dictado --probar-fondos [sacar]`: dice qué fondos de sistema y aéreos hay en el Mac y a qué resuelve cada línea `fondo:` de
/// `espacios.txt`. Con `sacar`, también saca (si falta) el cuadro fijo de cada aéreo pedido. No pone ningún fondo.
@MainActor
func probarFondos(sacar: Bool) -> Bool {
    let archivos = FondosMac.archivosSistema()
    print("Fondos estáticos en el Mac: \(archivos.count)")
    let catalogo = FondosMac.catalogoAereos()
    let bajados = catalogo.filter { FondosMac.videoLocal(id: $0.id) != nil }
    print("Aéreos en el catálogo: \(catalogo.count); con video descargado: \(bajados.count)")
    for a in bajados { print("  · \(a.nombre) (\(a.categoria)) \(a.id) → \(FondosMac.videoLocal(id: a.id)?.path ?? "")") }
    let archivo = LanzadorIsla.archivoEspacios
    let espacios = EspaciosIsla.leer((try? String(contentsOf: archivo, encoding: .utf8)) ?? "")
    var bien = true
    for e in espacios {
        guard let texto = e.fondo, let f = FondoLanzador(texto: texto) else { print("[\(e.nombre)] sin fondo"); continue }
        var detalle: String
        switch f {
        case .mac, .paleta: detalle = "no cambia el escritorio"
        case .imagen, .sistema:
            let u = FondosMac.archivoEscritorio(f)
            detalle = u?.path ?? "NO ESTÁ en el Mac"
            if u == nil { bien = false }
        case .aereo(let n):
            guard let r = FondosMac.resolverAereo(n) else { detalle = "aéreo desconocido"; bien = false; break }
            detalle = "\(r.aereo.nombre) \(r.aereo.id): video " + (r.video?.lastPathComponent ?? "SIN DESCARGAR")
            if let cuadro = FondosMac.cuadroGuardado(de: r.aereo) {
                detalle += "; cuadro \(cuadro.path)"
            } else if sacar, let v = r.video {
                let semaforo = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var sacado: URL?
                Task.detached { sacado = await FondosMac.extraerCuadro(de: v, aereo: r.aereo); semaforo.signal() }
                semaforo.wait()
                detalle += sacado.map { "; cuadro sacado: \($0.path)" } ?? "; NO se pudo sacar el cuadro"
                if sacado == nil { bien = false }
            } else {
                detalle += "; cuadro: falta (se saca al entrar al espacio)"
            }
        }
        print("[\(e.nombre)] \(texto) → \(detalle)")
    }
    return bien
}
