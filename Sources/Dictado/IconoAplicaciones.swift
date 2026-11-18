import AppKit
import DictadoKit
import SwiftUI

// El icono de «Aplicaciones» (pieza `lanzador` del Dock): cuadrícula de 3 × 3 mini iconos, como el de Apps de macOS 26.
// Cada mini es un squircle con degradado suave y brillo de vidrio; si hay iconos reales de las apps más usadas se usan
// esos (reducidos) y los huecos se completan con el diseño genérico.

/// Un mini icono genérico: el tono y el símbolo que lo dibuja cuando no hay un icono real.
struct MiniGenerico {
    let arriba: Color
    let abajo: Color
    let simbolo: String
}

enum AuroraIconoApps {
    /// Los nueve minis genéricos (la paleta de siempre del icono, ahora con degradado).
    static let genericos: [MiniGenerico] = [
        MiniGenerico(arriba: Color(hex: 0xFF8FA3), abajo: Color(hex: 0xE5314F), simbolo: "heart.fill"),
        MiniGenerico(arriba: Color(hex: 0xFFD27A), abajo: Color(hex: 0xF08A1C), simbolo: "sun.max.fill"),
        MiniGenerico(arriba: Color(hex: 0xD3F27A), abajo: Color(hex: 0x7FB82A), simbolo: "leaf.fill"),
        MiniGenerico(arriba: Color(hex: 0x7DB2FF), abajo: Color(hex: 0x2A62E0), simbolo: "safari.fill"),
        MiniGenerico(arriba: Color(hex: 0xC9C1FF), abajo: Color(hex: 0x7B6BEA), simbolo: "sparkles"),
        MiniGenerico(arriba: Color(hex: 0x6EE59A), abajo: Color(hex: 0x1FA84A), simbolo: "message.fill"),
        MiniGenerico(arriba: Color(hex: 0xFFA27C), abajo: Color(hex: 0xDB5A2A), simbolo: "flame.fill"),
        MiniGenerico(arriba: Color(hex: 0x8ED2FF), abajo: Color(hex: 0x3597DD), simbolo: "cloud.fill"),
        MiniGenerico(arriba: Color(hex: 0xFFFFFF), abajo: Color(hex: 0xC9CDD6), simbolo: "square.grid.2x2.fill"),
    ]
    static let radioMini: CGFloat = 0.225     // proporción del lado: el squircle de las apps de macOS
    static let separacion: CGFloat = 0.075    // proporción del lado total
    static let margenPlaca: CGFloat = 0.13
    static let radioPlaca: CGFloat = 0.235
}

/// Un mini icono: un icono real reducido o el genérico, con brillo de vidrio.
struct MiniIconoApp: View {
    let lado: CGFloat
    var generico: MiniGenerico
    var real: NSImage?

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: lado * AuroraIconoApps.radioMini, style: .continuous)
        ZStack {
            if let real {
                Image(nsImage: real).resizable().interpolation(.high).scaledToFit().frame(width: lado, height: lado)
            } else {
                forma.fill(LinearGradient(colors: [generico.arriba, generico.abajo], startPoint: .top, endPoint: .bottom))
                if lado >= 18 {
                    Image(systemName: generico.simbolo)
                        .font(.system(size: lado * 0.46, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.18), radius: lado * 0.03, y: lado * 0.02)
                }
                // Brillo de vidrio: reflejo en la mitad de arriba y filo de luz.
                forma.fill(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                    .mask(forma.inset(by: lado * 0.03))
                forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, lado * 0.025))
            }
        }
        .frame(width: lado, height: lado)
        .shadow(color: .black.opacity(0.35), radius: lado * 0.07, y: lado * 0.045)
    }
}

/// La cuadrícula de 3 × 3. `placa`: dibuja también la placa de vidrio oscuro con filo de luz (el icono suelto); sin placa, solo los minis
/// (el Dock ya pone su propio vidrio detrás).
struct IconoAplicaciones: View {
    let lado: CGFloat
    var reales: [NSImage?] = []
    var placa = true

    var body: some View {
        let margen = placa ? lado * AuroraIconoApps.margenPlaca : 0
        let sep = lado * AuroraIconoApps.separacion
        let mini = (lado - 2 * margen - 2 * sep) / 3
        ZStack {
            if placa { Placa(lado: lado) }
            VStack(spacing: sep) {
                ForEach(0..<3, id: \.self) { f in
                    HStack(spacing: sep) {
                        ForEach(0..<3, id: \.self) { c in
                            let i = f * 3 + c
                            MiniIconoApp(lado: mini, generico: AuroraIconoApps.genericos[i], real: i < reales.count ? reales[i] : nil)
                        }
                    }
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }

    /// La placa: vidrio oscuro, reflejo arriba y filo de luz.
    private struct Placa: View {
        let lado: CGFloat
        var body: some View {
            let forma = RoundedRectangle(cornerRadius: lado * AuroraIconoApps.radioPlaca, style: .continuous)
            forma.fill(LinearGradient(colors: [Color(hex: 0x2B2E3A), Color(hex: 0x0E0F14)], startPoint: .top, endPoint: .bottom))
                .overlay { forma.fill(RadialGradient(colors: [.white.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: lado * 0.8)) }
                .overlay { forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.50), .white.opacity(0.05), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.75, lado * 0.012)) }
                .shadow(color: .black.opacity(0.4), radius: lado * 0.05, y: lado * 0.03)
        }
    }
}

// MARK: - Render de prueba

/// `Dictado --vista-icono-apps salida.png`: el icono a 256 (genérico y con iconos reales) y a su tamaño real (58) sobre el vidrio del Dock.
@MainActor
func hojaIconoApps(_ destino: URL) -> Bool {
    let ids = ["com.apple.Safari", "com.apple.Notes", "com.apple.iCal", "com.apple.Terminal", "com.apple.Photos", "com.apple.Maps",
               "com.apple.mail", "com.apple.MobileSMS", "com.apple.reminders"]
    let reales: [NSImage?] = ids.map { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { CatalogoApps.icono($0.path) } }
    let hoja = VStack(spacing: 28) {
        HStack(spacing: 40) {
            IconoAplicaciones(lado: 256)
            IconoAplicaciones(lado: 256, reales: reales)
        }
        HStack(spacing: 24) {
            ForEach([false, true], id: \.self) { conReales in
                let r: [NSImage?] = conReales ? reales : []
                PiezaVidrioDePrueba { IconoAplicaciones(lado: AuroraDock.piezaAlto - 6, reales: r, placa: false) }
            }
            IconoAplicaciones(lado: 58)
            IconoAplicaciones(lado: 58, reales: reales)
        }
    }
    .padding(40)
    .background(LinearGradient(colors: [Color(hex: 0x3B5A8C), Color(hex: 0x9FB6D8)], startPoint: .topLeading, endPoint: .bottomTrailing))
    let r = ImageRenderer(content: hoja)
    r.scale = 2
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// La pieza del Dock sin estado: solo su vidrio, para ver el icono a su tamaño real.
private struct PiezaVidrioDePrueba<Contenido: View>: View {
    @ViewBuilder var contenido: () -> Contenido
    var body: some View {
        let forma = RoundedRectangle(cornerRadius: AuroraDock.piezaRadio, style: .continuous)
        contenido()
            .frame(width: 72, height: AuroraDock.piezaAlto)
            .background { forma.fill(LinearGradient(colors: [AuroraDock.piezaArriba, AuroraDock.piezaAbajo], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))) }
            .overlay { forma.strokeBorder(AuroraDock.piezaFilo, lineWidth: 1) }
            .overlay { forma.strokeBorder(LinearGradient(colors: [AuroraDock.piezaLuzArriba, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1) }
    }
}
