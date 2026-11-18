import AppKit
import CoreGraphics

/// Una versión diminuta de una imagen: al estirarla con interpolación suave queda desenfocada sin pagar un desenfoque en cada cuadro.
/// Sirve para el fondo de la tarjeta de música (la carátula o el fondo de pantalla) y se puede animar (deriva, escala) casi gratis.
enum MiniaturaDeFondo {
    static func de(_ imagen: CGImage, ancho: Int = 56) -> CGImage? {
        let alto = max(1, Int((Double(ancho) * Double(imagen.height) / Double(max(imagen.width, 1))).rounded()))
        guard let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
        return ctx.makeImage()
    }

    static func de(_ imagen: NSImage, ancho: Int = 56) -> CGImage? {
        var caja = CGRect(origin: .zero, size: imagen.size)
        return imagen.cgImage(forProposedRect: &caja, context: nil, hints: nil).flatMap { de($0, ancho: ancho) }
    }
}
