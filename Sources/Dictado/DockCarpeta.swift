import AppKit
import DictadoKit
import ImageIO
import Observation
import SwiftUI

// La carpeta del Dock: vidrio esmerilado de verdad. Una placa trasera oscura (o la miniatura de lo más reciente), hojas blancas que
// asoman por arriba y, delante, un frente translúcido con la pestaña en diagonal que deja ver desenfocado lo de atrás. Tiene el
// nombre escrito sobre el frente y, debajo, una línea en mono (el número de elementos o la fecha).
//
// Todo se dibuja en un lienzo de 406 × 312 (la proporción de las referencias) y se escala al tamaño pedido.

/// El frente de la carpeta: borde superior recto que sube a la izquierda, baja en diagonal hacia la derecha, lados que se cierran un poco
/// hacia abajo y esquinas redondeadas. Se dibuja en su propio rectángulo de 406 × 247.
struct FrenteCarpeta: Shape {
    func path(in rect: CGRect) -> Path {
        let kx = rect.width / 406, ky = rect.height / 247
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * kx, y: rect.minY + y * ky) } // grid: ok dibujo de la carpeta (su propia escala)
        // Vértices y radio de cada esquina, en el sentido de las agujas del reloj desde arriba a la izquierda.
        let v: [(CGPoint, CGFloat)] = [
            (p(0, 0), 22 * kx), (p(188, 0), 15 * kx), (p(247, 54), 17 * kx), (p(407.5, 54), 24 * kx),
            (p(389, 247), 26 * kx), (p(17.5, 247), 26 * kx),
        ]
        var r = Path()
        let inicio = CGPoint(x: (v[v.count - 1].0.x + v[0].0.x) / 2, y: (v[v.count - 1].0.y + v[0].0.y) / 2)
        r.move(to: inicio)
        for i in 0..<v.count {
            r.addArc(tangent1End: v[i].0, tangent2End: v[(i + 1) % v.count].0, radius: v[i].1)
        }
        r.closeSubpath()
        return r
    }
}

struct CarpetaVidrio: View {
    let nombre: String
    /// La línea en mono de abajo ("12 elementos", "Wed 19 Aug"). Vacía, no se escribe.
    var detalle = ""
    /// La miniatura de lo más reciente: va en la placa de atrás. Sin ella, la placa es oscura.
    var foto: CGImage?
    /// El tamaño del texto relativo al ancho de la carpeta; en los iconos chicos se agranda para que se lea.
    var texto: CGFloat = 0.115

    private let ancho: CGFloat = 406
    private let alto: CGFloat = 312

    /// Placa y hojas: lo que queda detrás del frente. Se dibuja dos veces: nítido arriba y desenfocado dentro del frente.
    private var fondo: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.085)], startPoint: .top, endPoint: .bottom))
                .frame(width: 368, height: 310)
                .overlay {
                    if let foto {
                        Image(decorative: foto, scale: 1).resizable().scaledToFill().frame(width: 368, height: 310).clipped()
                            .overlay(LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1.5) }
                .offset(x: 20, y: 2)
            hoja(x: 224, y: 20, w: 78, h: 270, giro: -1.5, tono: 0.92, rayas: [20, 98, 112, 126, 140])
            hoja(x: 294, y: 40, w: 70, h: 250, giro: 12, tono: 0.88, rayas: [30, 62])
            hoja(x: 46, y: 24, w: 186, h: 270, giro: -10.5, tono: 0.975, rayas: [], titulo: true)
        }
        .frame(width: ancho, height: alto, alignment: .topLeading)
    }

    private func hoja(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, giro: Double, tono: Double, rayas: [CGFloat], titulo: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: tono), Color(white: tono - 0.05)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 13) {
                    if titulo {
                        Capsule().fill(Color(white: 0.80)).frame(width: w - 44, height: 11)
                        ForEach(0..<12, id: \.self) { i in
                            Capsule().fill(Color(white: 0.84)).frame(width: (w - 44) * [0.95, 0.8, 0.9, 0.55, 0.85, 0.7, 0.6, 0.9, 0.75, 0.85, 0.6, 0.8][i], height: 7)
                        }
                    } else {
                        ForEach(Array(rayas.enumerated()), id: \.offset) { i, ancho in
                            Capsule().fill(Color(white: 0.80)).frame(width: w * (i == 0 ? 0.5 : 0.62), height: 6).padding(.top, i == 0 ? ancho : 0)
                        }
                    }
                }
                .padding(.leading, 18).padding(.top, 20)
            }
            .frame(width: w, height: h)
            .rotationEffect(.degrees(giro), anchor: .topLeading)
            .offset(x: x, y: y)
    }

    var body: some View {
        let frente = FrenteCarpeta()
        ZStack(alignment: .topLeading) {
            fondo
                .shadow(color: .black.opacity(0.30), radius: 8, y: 6)
            // El frente: lo de atrás desenfocado, una base de humo, el velo de luz y el filo.
            ZStack(alignment: .topLeading) {
                Color(white: 0.09).opacity(0.62)
                fondo.blur(radius: 9).offset(x: 0, y: -65)
                LinearGradient(stops: [.init(color: .white.opacity(0.30), location: 0), .init(color: .white.opacity(0.12), location: 0.55),
                                       .init(color: .black.opacity(0.30), location: 1)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.black.opacity(0.28), .clear, .clear, .black.opacity(0.26)], startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: 406, height: 247, alignment: .topLeading)
            .clipShape(frente)
            .overlay { frente.stroke(LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.18), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1.8) }
            .overlay { frente.stroke(.black.opacity(0.18), lineWidth: 1).padding(1.6) }
            .shadow(color: .black.opacity(0.38), radius: 12, y: 10)
            .offset(y: 65)
            // El nombre y la línea en mono, sobre el frente.
            VStack(alignment: .leading, spacing: 4) {
                Text(nombre)
                    .font(.system(size: ancho * texto, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(.white.opacity(0.95))
                if !detalle.isEmpty {
                    Text(detalle).font(.system(size: ancho * texto * 0.62, weight: .regular, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(width: 190, alignment: .leading)
            .offset(x: 30, y: 65 + 16)
        }
        .frame(width: ancho, height: alto, alignment: .topLeading)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

/// La carpeta a un tamaño dado (el lienzo de 406 × 312 escalado). Un solo sitio donde se decide la proporción.
struct CarpetaVidrioEscalada: View {
    let nombre: String
    var detalle = ""
    var foto: CGImage?
    var ancho: CGFloat
    var texto: CGFloat = 0.115

    var body: some View {
        let k = ancho / 406
        CarpetaVidrio(nombre: nombre, detalle: detalle, foto: foto, texto: texto)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: ancho, height: 312 * k, alignment: .topLeading)
    }
}

// MARK: - Lo más reciente de la carpeta

/// Lo que la carpeta del Dock enseña de su contenido: cuántos elementos tiene y la miniatura de la imagen más reciente. Se lee una sola vez
/// por carpeta (fuera del hilo principal) y se guarda; el Dock lo pide al mostrarse.
@MainActor @Observable
final class ContenidoCarpetas {
    struct Datos { var elementos: Int; var foto: CGImage? }
    static let compartido = ContenidoCarpetas()
    private(set) var datos: [String: Datos] = [:]
    @ObservationIgnored private var pidiendo = Set<String>()
    @ObservationIgnored private var cargados: [String: Date] = [:]

    func pedir(_ ruta: String) {
        if let t = cargados[ruta], Date().timeIntervalSince(t) < 60 { return }
        guard !pidiendo.contains(ruta) else { return }
        pidiendo.insert(ruta)
        Task.detached(priority: .utility) {
            let lista = ModeloCarpeta.listar(ruta) ?? []
            let foto = lista.first { !$0.esCarpeta && Self.esImagen($0.nombre) }.flatMap { Self.miniatura($0.ruta) }
            await MainActor.run {
                let d = Datos(elementos: lista.count, foto: foto)
                self.datos[ruta] = d
                self.cargados[ruta] = Date()
                self.pidiendo.remove(ruta)
            }
        }
    }

    func soltar() { datos = [:]; cargados = [:] }

    nonisolated static func esImagen(_ nombre: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"].contains((nombre as NSString).pathExtension.lowercased())
    }

    /// Una miniatura de 240 px de lado mayor (ImageIO no carga la imagen entera).
    nonisolated static func miniatura(_ ruta: String) -> CGImage? {
        guard let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: 240]
        return CGImageSourceCreateThumbnailAtIndex(fuente, 0, o as CFDictionary)
    }

    static func textoElementos(_ n: Int) -> String { n >= CarpetaDock.maximo ? "\(CarpetaDock.maximo)+ elementos" : (n == 1 ? "1 elemento" : "\(n) elementos") }
}
