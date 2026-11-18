import AppKit
import ApplicationServices
import DictadoKit
import SwiftUI

// Renders del selector de apps con datos de muestra: sin ventanas, sin teclado, sin AppleScript, sin permisos.
//   Dictado --vista-selector /tmp/cmdtab/selector.png
// escribe selector-apps.png (la app elegida sin datos todavía: lo primero que se ve), selector-ventanas.png (una app con tres ventanas
// y miniaturas) y selector-cra.png (Cra con 2 ventanas y 8 pestañas, una elegida).

@MainActor
private func iconoDeMuestra(_ bundleID: String, respaldo: String? = nil) -> NSImage? {
    var url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    if url == nil, let respaldo { url = URL(fileURLWithPath: (respaldo as NSString).expandingTildeInPath) }
    guard let url else { return nil }
    return SelectorApps.mapaDeBits(NSWorkspace.shared.icon(forFile: url.path), lado: 128)
}

@MainActor
private func appsDeMuestra() -> [AppSel] {
    let datos: [(Int32, String, String, String?)] = [
        (101, "Notas", "com.apple.Notes", nil), (102, "Cra", "dk.kildahl.cra", "~/Applications/Cra.app"),
        (103, "Safari", "com.apple.Safari", nil), (104, "Mail", "com.apple.mail", nil), (105, "Calendario", "com.apple.iCal", nil),
        (106, "Terminal", "com.apple.Terminal", nil), (107, "Mensajes", "com.apple.MobileSMS", nil), (108, "Finder", "com.apple.finder", nil),
        (109, "Preferencias", "com.apple.systempreferences", nil)]
    return datos.map { AppSel(id: $0.0, nombre: $0.1, bundleID: $0.2, icono: iconoDeMuestra($0.2, respaldo: $0.3)) }
}

private func miniaturaDeMuestra(_ matiz: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: 176, height: 112), flipped: false) { r in
        NSColor(calibratedHue: matiz, saturation: 0.22, brightness: 0.93, alpha: 1).setFill(); r.fill()
        NSColor(white: 1, alpha: 0.85).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 92, width: r.width, height: 20)).fill()
        NSColor(white: 0, alpha: 0.12).setFill()
        for k in 0..<4 { NSBezierPath(roundedRect: NSRect(x: 12, y: 74 - CGFloat(k) * 16, width: r.width - CGFloat(24 + k * 20), height: 7), xRadius: 3, yRadius: 3).fill() }
        return true
    }
}

@MainActor
private func estadoDeMuestra(_ escena: String, anchoPantalla: Double = 1440, altoPantalla: Double = 1000) -> EstadoSelector {
    let e = EstadoSelector()
    e.simulado = true
    e.anchoPantalla = anchoPantalla
    e.altoPantalla = altoPantalla
    e.apps = appsDeMuestra()
    e.maquina.iniciar(atras: false, totalApps: e.apps.count)   // la app 1 (la anterior)
    e.maquina.mostrar()
    switch escena {
    case "apps":
        var d = DetalleApp()
        d.cargandoVentanas = true
        e.detalles[102] = d
    case "ventanas":
        e.maquina.tecla(.tab(atras: false))   // Safari
        var d = DetalleApp()
        d.cargandoVentanas = false
        d.ventanas = [VentanaSel(id: 0, titulo: "Reunión con el cliente - Calendario de la semana", miniatura: miniaturaDeMuestra(0.58)),
                      VentanaSel(id: 1, titulo: "Notas de la audiencia", miniatura: miniaturaDeMuestra(0.1)),
                      VentanaSel(id: 2, titulo: "Documento sin título", minimizada: true)]
        e.detalles[103] = d
        e.maquina.ajustarElementos(total: d.elementos.count, inicial: ListaDetalle.inicial(d.resumen))
    default:   // cra
        let w1 = ["Bandeja de entrada (12) - ana@lumina.example", "Plan de pendientes - Notion", "Revisión del contrato marco - Google Docs",
                  "Tablero de Lumina", "Calendario - semana 47", "Finanzas personales - Hoja de cálculo"]
        let urls = ["https://mail.google.com/mail/u/0/#inbox", "https://www.notion.so/plan", "https://docs.google.com/document/d/1x",
                    "https://lumina.example/tablero", "https://calendar.google.com/calendar/u/0/r/week", "https://docs.google.com/spreadsheets/d/2y"]
        let p1 = w1.enumerated().map { PestanaApp(id: "a\($0.offset)", titulo: $0.element, indice: $0.offset + 1, activa: $0.offset == 2, url: urls[$0.offset]) }
        let p2 = [PestanaApp(id: "b0", titulo: "Dian - Normograma", indice: 1, activa: true, url: "https://normograma.dian.gov.co/"),
                  PestanaApp(id: "b1", titulo: "Estatuto Tributario art. 882", indice: 2, activa: false, url: "https://www.suin-juriscol.gov.co/x")]
        var d = DetalleApp()
        d.cargandoVentanas = false
        d.pestanas = .listo
        d.ventanas = [VentanaSel(id: 0, titulo: p1[2].titulo, miniatura: miniaturaDeMuestra(0.58), pestanas: p1),
                      VentanaSel(id: 1, titulo: p2[0].titulo, miniatura: miniaturaDeMuestra(0.08), pestanas: p2)]
        e.detalles[102] = d
        e.maquina.ajustarElementos(total: d.elementos.count, inicial: ListaDetalle.inicial(d.resumen))
        e.maquina.tecla(.abajo)    // baja a la pestaña activa
        e.maquina.tecla(.abajo)    // y una más
    }
    return e
}

@MainActor
func hojaSelector(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let base = destino.deletingPathExtension()
    try? FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
    for escena in ["apps", "ventanas", "cra"] {
        let estado = estadoDeMuestra(escena)
        let m = estado.medidas
        let marco = CGSize(width: m.width + 2 * AuroraSelector.margen, height: m.height + 2 * AuroraSelector.margen)
        let lienzo = CGSize(width: max(1100, marco.width + 160), height: marco.height + 140)
        let hoja = lienzoConVidrio(fondo, lienzo: lienzo, panel: m, radio: AuroraSelector.radio) {
            VistaSelectorApps(estado: estado).frame(width: marco.width, height: marco.height)
        }
        let r = ImageRenderer(content: hoja)
        r.scale = 2
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        let salida = URL(fileURLWithPath: base.path + "-" + escena + ".png")
        guard (try? png.write(to: salida)) != nil else { return false }
        print("escribí \(salida.path)")
    }
    return true
}
