import AppKit

// El velo: una ventana por pantalla, sin bordes, que no toma el foco ni deja pasar el ratón por ella (lo ignora),
// con tres capas estáticas: el desenfoque del sistema, un tinte y un grano. Nada se redibuja mientras está quieta:
// solo cuesta lo que le cueste a macOS componer el desenfoque.

/// Ventana del velo de una pantalla.
final class PanelVelo: NSPanel {
    let efecto = NSVisualEffectView()
    let tinte = NSView()
    let grano = NSView()
    let idPantalla: CGDirectDisplayID

    init(pantalla: NSScreen) {
        idPantalla = pantalla.numeroDeVista
        super.init(contentRect: pantalla.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Nivel normal: solo así entra en el orden de las ventanas de las apps (debajo de la activa). Por encima quedan
        // la barra de menús, el Dock y los avisos, que tienen niveles más altos.
        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        // Visible en todos los Spaces; fuera de Mission Control y del ciclo de ventanas (⌘`); también en Spaces de
        // pantalla completa (si no se oculta antes).
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        // Ni en capturas ni en grabaciones ni al compartir pantalla.
        sharingType = .none
        alphaValue = 0

        let raiz = NSView(frame: NSRect(origin: .zero, size: pantalla.frame.size))
        raiz.wantsLayer = true
        contentView = raiz
        for v: NSView in [efecto, tinte, grano] {
            v.frame = raiz.bounds
            v.autoresizingMask = [.width, .height]
            raiz.addSubview(v)
        }
        efecto.blendingMode = .behindWindow
        efecto.state = .active
        tinte.wantsLayer = true
        grano.wantsLayer = true
        grano.layer?.backgroundColor = Self.colorGrano.cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Sin esto, AppKit encoge una ventana sin bordes para que no pise la barra de menús.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Ruido fino, hecho una sola vez: una baldosa de 128×128 con alfa al azar que se repite.
    private static let colorGrano: NSColor = {
        let lado = 128
        var bytes = [UInt8](repeating: 0, count: lado * lado * 4)
        var g = SystemRandomNumberGenerator()
        for i in 0..<(lado * lado) {
            let a = UInt8.random(in: 0...255, using: &g)
            // Premultiplicado: gris medio con ese alfa.
            bytes[i * 4] = UInt8(UInt16(a) * 128 / 255); bytes[i * 4 + 1] = bytes[i * 4]; bytes[i * 4 + 2] = bytes[i * 4]; bytes[i * 4 + 3] = a
        }
        let datos = Data(bytes) as CFData
        guard let proveedor = CGDataProvider(data: datos),
              let imagen = CGImage(width: lado, height: lado, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: lado * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: proveedor, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return .clear }
        return NSColor(patternImage: NSImage(cgImage: imagen, size: NSSize(width: lado, height: lado)))
    }()

    /// Pone el aspecto: material y fuerza del desenfoque, tinte y grano. Se llama al encender y al cambiar un ajuste.
    func aplicar(_ a: AspectoVelo) {
        efecto.material = a.material
        efecto.appearance = a.oscuro ? NSAppearance(named: .darkAqua) : nil
        efecto.alphaValue = a.fuerzaDesenfoque
        tinte.layer?.backgroundColor = a.tinte.withAlphaComponent(a.opacidadTinte).cgColor
        grano.alphaValue = a.grano
    }
}

/// Lo que se ve del velo, ya resuelto (modo + ajustes).
struct AspectoVelo: Equatable {
    var material: NSVisualEffectView.Material
    var oscuro: Bool
    /// 0...1: cuánto del desenfoque se mezcla con lo de atrás.
    var fuerzaDesenfoque: CGFloat
    var tinte: NSColor
    var opacidadTinte: CGFloat
    var grano: CGFloat
}

extension NSScreen {
    /// Número de pantalla de CoreGraphics (el mismo que usa `CGDisplay`).
    var numeroDeVista: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Su marco en las coordenadas de CoreGraphics y Accesibilidad (origen arriba a la izquierda de la principal).
    var marcoCG: CGRect {
        let altoPrincipal = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: altoPrincipal - frame.maxY, width: frame.width, height: frame.height)
    }
}
