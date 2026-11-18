import AppKit
import AVFoundation
import DictadoKit
import Observation
import SwiftUI

// El fondo de escritorio que comparten el lanzador y el Centro: por omisión, el fondo de pantalla del Mac (de esa pantalla), o el que
// el dueño elija en el selector del lanzador (paleta o imagen, global o por espacio). Una sola pieza lee, guarda, dibuja y decide el tema. Se lee en otro hilo, en un solo cuadro y
// reducido al tamaño de la pantalla; se guarda mientras el lanzador está abierto (clave: ruta + fecha del archivo + tamaño) y se suelta
// al cerrarlo. La luminancia (una cifra) sí se recuerda, para que el tema salga bien desde el primer cuadro de la próxima vez.
//
// Fondos en vivo y dinámicos:
//   · un HEIC dinámico trae varios cuadros: con dos (claro y oscuro) se usa el que va con la apariencia del Mac; con más, el de la
//     hora del día (los cuadros siguen el orden del día);
//   · un video (fondos animados .mov/.mp4): su primer segundo, como imagen fija;
//   · una carpeta de imágenes (el Mac rota entre ellas): la primera, por nombre;
//   · un fondo "de la nube" de Apple (.madesktop): su miniatura;
//   · un fondo de macOS por nombre (`fondo: Sonoma`) o un aéreo (`fondo: aereo:Patagonia`): ver `FondoAereo.swift`; del aéreo se lee un
//     cuadro como imagen fija y, si el `.mov` está en el Mac, la vista lo reproduce encima;
//   · si nada se puede leer, queda el plano del tema (sin esferas) hasta que el dueño elija otra cosa.
// Quien lo usa: `EstadoLanzador` (fondo y tema del lanzador) y `RaizCentroAurora` (el fondo del Centro, con más velo).

extension FondoPantalla {
    /// El archivo de imagen o video que usa esa pantalla de fondo; si el Mac apunta a una carpeta, su primera imagen.
    @MainActor static func archivoParaLanzador(de pantalla: NSScreen) -> URL? {
        guard var url = NSWorkspace.shared.desktopImageURL(for: pantalla) else { return nil }
        var esCarpeta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta) else { return nil }
        // Los fondos de Apple "de la nube" (.madesktop) son una ficha con la ruta de su miniatura: se usa esa imagen.
        if !esCarpeta.boolValue, url.pathExtension.lowercased() == "madesktop" {
            guard let ficha = NSDictionary(contentsOf: url), let ruta = ficha["thumbnailPath"] as? String,
                  FileManager.default.fileExists(atPath: ruta) else { return nil }
            url = URL(fileURLWithPath: ruta)
        }
        guard esCarpeta.boolValue else { return url }
        let dentro = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return dentro.filter { ["heic", "jpg", "jpeg", "png", "tiff", "tif", "webp", "mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .min { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

enum LectorFondo {
    /// Una imagen ya reducida y su luminancia media (0 a 1).
    struct Leida: @unchecked Sendable {
        let imagen: CGImage
        let luminancia: Double
    }

    /// Lee un cuadro de la imagen o el video, reducido a `lado` píxeles en su lado mayor. Sin hilo principal.
    nonisolated static func leer(_ url: URL, lado: CGFloat, oscuro: Bool, hora: Int) async -> Leida? {
        var imagen = cuadro(url, lado: lado, oscuro: oscuro, hora: hora)
        if imagen == nil { imagen = await cuadroDeVideo(url, lado: lado) }
        guard let imagen else { return nil }
        return Leida(imagen: imagen, luminancia: luminanciaMedia(imagen))
    }

    nonisolated private static func cuadro(_ url: URL, lado: CGFloat, oscuro: Bool, hora: Int) -> CGImage? {
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let cuantos = CGImageSourceGetCount(fuente)
        guard cuantos > 0 else { return nil }
        var indice = max(CGImageSourceGetPrimaryImageIndex(fuente), 0)
        if cuantos == 2 { indice = oscuro ? 1 : 0 } else if cuantos > 2 { indice = min(cuantos - 1, hora * cuantos / 24) }
        let opciones: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Int(lado),
                                         kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(fuente, indice, opciones as CFDictionary)
    }

    nonisolated private static func cuadroDeVideo(_ url: URL, lado: CGFloat) async -> CGImage? {
        let activo = AVURLAsset(url: url)
        guard (try? await activo.load(.isPlayable)) == true else { return nil }
        let g = AVAssetImageGenerator(asset: activo)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: lado, height: lado)
        return try? await g.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    }

    /// La luminancia media de la imagen, dibujada en 24 × 24.
    nonisolated static func luminanciaMedia(_ imagen: CGImage) -> Double {
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
        guard ok else { return 0 }
        var suma = 0.0
        for i in 0..<(n * n) {
            suma += LuminanciaFondo.luminancia(r: Double(bytes[i * 4]) / 255, g: Double(bytes[i * 4 + 1]) / 255, b: Double(bytes[i * 4 + 2]) / 255)
        }
        return suma / Double(n * n)
    }
}

/// Lo que se muestra detrás: la imagen ya leída (o nada mientras se lee), su luminancia y si pide tema claro.
@MainActor @Observable
final class FondoEscritorioModelo {
    private(set) var imagen: CGImage?
    /// La luminancia media (0 a 1) si se conoce; de ella salen `claro` y el velo extra del Centro.
    private(set) var luminancia: Double?
    /// El video del aéreo si el fondo es uno y ya está descargado (la vista lo reproduce encima de la imagen fija); si no, nil.
    private(set) var video: URL?
    /// Con la luminancia conocida: ¿pide tema claro? (nil: aún no se sabe)
    var claro: Bool? { luminancia.map(LuminanciaFondo.esClaro) }

    @ObservationIgnored private var clave: String?
    @ObservationIgnored private var tarea: Task<Void, Never>?
    /// Una cifra por imagen (ruta + fecha): sobrevive al cierre porque pesa nada.
    @ObservationIgnored private static var luminancias: [String: Double] = [:]
    /// Cuántas lecturas se hicieron (para las pruebas y la medición).
    @ObservationIgnored private(set) var lecturas = 0

    /// Pide el fondo para esa pantalla. `.paleta` no lee nada. Si ya está leído (misma ruta y fecha), no hace nada.
    func cargar(_ fondo: FondoLanzador, pantalla: NSScreen?) {
        let url: URL?
        var vivo: URL?
        switch fondo {
        case .paleta: soltarImagen(); luminancia = nil; return
        case .mac: url = pantalla.flatMap { FondoPantalla.archivoParaLanzador(de: $0) }
        case .imagen(let ruta): url = URL(fileURLWithPath: ruta)
        case .sistema(let nombre): url = FondosMac.archivoSistema(nombre)
        case .aereo(let nombre):
            let r = FondosMac.resolverAereo(nombre)
            url = r.flatMap { FondosMac.imagenFija(de: $0) }
            vivo = r?.video
        }
        video = vivo
        guard let url, let pantalla else { soltarImagen(); luminancia = nil; return }
        let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let nueva = url.path + "|\(fecha)"
        if nueva == clave, imagen != nil { return }
        tarea?.cancel()
        clave = nueva
        if let l = Self.luminancias[nueva] { luminancia = l }
        let lado = max(pantalla.frame.width, pantalla.frame.height)
        let oscuro = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
        let hora = Calendar.current.component(.hour, from: Date())
        lecturas += 1
        tarea = Task.detached(priority: .userInitiated) {
            let leida = await LectorFondo.leer(url, lado: lado, oscuro: oscuro, hora: hora)
            await MainActor.run { [weak self] in
                guard let self, self.clave == nueva, !Task.isCancelled else { return }
                if let leida {
                    Self.luminancias[nueva] = leida.luminancia
                    self.imagen = leida.imagen
                    self.luminancia = leida.luminancia
                } else {
                    self.imagen = nil
                    self.luminancia = nil
                }
            }
        }
    }

    private func soltarImagen() {
        tarea?.cancel()
        tarea = nil
        clave = nil
        imagen = nil
        video = nil
    }

    /// Al cerrar el lanzador o el Centro: la imagen se suelta (es la parte que pesa) y la lectura en curso se cancela.
    func soltar() {
        soltarImagen()
        luminancia = nil
    }

    /// Renders: la imagen ya leída.
    func fijar(imagen: CGImage?, luminancia: Double?) {
        self.imagen = imagen
        self.luminancia = luminancia
    }
}

/// Todo lo que el lanzador y el Centro necesitan para pintar el mismo fondo: la pantalla donde están, la elección del dueño (global, y la del
/// espacio activo que traen ellos), la preferencia de tema y la imagen ya leída. Cada uno crea su propia al abrir y la suelta al cerrar.
@MainActor @Observable
final class FondoEscritorio {
    let modelo = FondoEscritorioModelo()
    /// La pantalla donde está abierto (nil en los renders, que traen su imagen).
    var pantalla: NSScreen?
    var preferencia: PreferenciaTema
    /// El fondo global (texto de `lanzador.fondo`); nil = el fondo del Mac.
    var fondoGlobal: String?
    /// Si el Mac está en oscuro al abrir (para la preferencia "sistema").
    var sistemaOscuro = true

    init(defaults: UserDefaults = .dictado) {
        preferencia = PreferenciaTema(rawValue: defaults.string(forKey: EstadoLanzador.claveTema) ?? "") ?? .automatico
        fondoGlobal = defaults.string(forKey: EstadoLanzador.claveFondo)
    }

    /// Vuelve a leer los ajustes (el Centro los lee cada vez que se abre).
    func leerAjustes(defaults: UserDefaults = .dictado) {
        preferencia = PreferenciaTema(rawValue: defaults.string(forKey: EstadoLanzador.claveTema) ?? "") ?? .automatico
        fondoGlobal = defaults.string(forKey: EstadoLanzador.claveFondo)
        sistemaOscuro = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
    }

    /// El fondo que vale: el del espacio activo (`espacio`: su línea `fondo:`), si tiene uno; si no, el global; si no, el del Mac.
    func fondo(espacio: String?) -> FondoLanzador { FondoLanzador.resolver(espacio: espacio, global: fondoGlobal) }

    func tema(espacio: String?) -> AuroraTema {
        TemaDelFondo.esClaro(preferencia: preferencia, fondo: fondo(espacio: espacio), luminanciaClara: modelo.claro, sistemaOscuro: sistemaOscuro) ? .claro : .oscuro
    }

    /// Lee (en otro hilo) el fondo que vale para esta pantalla. Sin pantalla (renders) no hace nada.
    func sincronizar(espacio: String?) {
        guard pantalla != nil else { return }
        modelo.cargar(fondo(espacio: espacio), pantalla: pantalla)
    }

    func soltar() {
        modelo.soltar()
        pantalla = nil
    }
}

// MARK: - Vista

/// El fondo: la imagen del Mac desenfocada 5 pt y algo más saturada, con el velo del tema encima (para que lo de encima se lea); o
/// las esferas de una paleta propia si el dueño la eligió. `refuerzo` suma opacidad al velo (el Centro lo pide según la luminancia).
struct FondoEscritorioVista: View {
    let fondo: FondoLanzador
    let paleta: AuroraPaleta
    let tema: AuroraTema
    let imagen: CGImage?
    /// El video de un aéreo descargado: se reproduce en bucle encima de la imagen fija (que queda mientras carga y con "Reducir movimiento").
    var video: URL? = nil
    var refuerzo = 0.0

    var body: some View {
        ZStack {
            if case .paleta = fondo {
                FondoAurora(paleta: paleta, tema: tema)
            } else {
                (tema.esOscuro ? AuroraLanzador.planoOscuro : AuroraLanzador.planoClaro)
                if let imagen {
                    Color.clear
                        .overlay {
                            Image(decorative: imagen, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(AuroraLanzador.excesoFondo)
                                .saturation(AuroraLanzador.saturacionFondo)
                                .blur(radius: AuroraLanzador.desenfoqueFondo)
                        }
                        .clipped()
                        .transition(.opacity)
                }
                if let video {
                    FondoAereoVista(url: video)
                        .scaleEffect(AuroraLanzador.excesoFondo)
                        .saturation(AuroraLanzador.saturacionFondo)
                        .blur(radius: AuroraLanzador.desenfoqueFondo)
                        .clipped()
                }
                LinearGradient(stops: AuroraLanzador.velo(tema: tema, refuerzo: refuerzo), startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeOut(duration: 0.25), value: imagen != nil)
        .accessibilityHidden(true)
    }
}

