import AppKit
import DictadoKit
import SwiftUI

// Renders de los espacios sin abrir ninguna ventana, ni tocar el fondo de pantalla, el sonido o el micrófono:
//   Dictado --vista-espacios /tmp/espacios-mejoras
// Por cada espacio de `EspaciosIsla.sugeridos` (o del archivo que diga DICTADO_ESPACIOS) deja `dock-<espacio>.png` (la barra con su
// selector sobre el fondo de pantalla del espacio) y `lanzador-<espacio>.png` (el lanzador con su fondo, su paleta y su Dock).
// Los datos son inventados; las apps son las instaladas en este Mac.

@MainActor
private func fondoReducido(_ ruta: String, ancho: CGFloat) -> NSImage? {
    let opciones: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Int(ancho * 2),
                                     kCGImageSourceCreateThumbnailWithTransform: true]
    guard let f = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(f, 0, opciones as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
}

@MainActor
private func estadoDockDeEspacios(espacios: [EspacioIsla], actual: String, catalogo: [EntradaApp], ahora: Date) -> EstadoDock {
    let datos = datosLanzadorDeMuestra(ahora: ahora)
    let apps = AppsUsadas(vivo: false)
    func app(_ ids: [String]) -> [EntradaApp] { ids.compactMap { id in catalogo.first { $0.bundleID == id || $0.nombre == id } } }
    apps.fijar(app(["com.anthropic.claudefordesktop", "Claude", "com.spotify.client", "net.whatsapp.WhatsApp", "Safari", "com.apple.Notes"]), iconos: [:])
    apps.fijar(catalogo: catalogo, categorias: [:])
    let lanzador = LanzadorIsla(vivo: false)
    lanzador.fijar(carpetas: [], espacios: espacios, espacio: actual, atajos: [])
    let tareas = TareasIsla(pendientes: nil, vivo: false)
    tareas.fijar([TareaVista(id: "c1", rotulo: "", texto: "Enviar el poder", cita: nil, origen: .centro(1))], hechas: 2, delCentro: true)
    let foco = Foco(vivo: false)
    if actual == "Foco" { foco.empezar("Memo de IVA", minutos: 25, inicio: ahora.addingTimeInterval(-8.3 * 60)) }
    let estado = EstadoDock(agenda: datos.agenda, musica: datos.musica, claude: datos.claude, agentes: AgentesRemotos(vivo: false), foco: foco, tareas: tareas,
                            salud: EstadoSalud(), hud: EstadoHUD(), estadoIsla: EstadoIsla(), lanzador: lanzador, apps: apps, vivo: false)
    estado.ahoraFijo = ahora
    estado.clima = climaDeMuestra(ahora: ahora)
    estado.tablero = datos.tablero
    estado.fijarPapelera(llena: true)
    estado.abiertas.fijar(app(["com.apple.Safari", "com.apple.Notes", "com.apple.mail", "com.apple.MobileSMS"]))
    estado.finder.fijar([])
    PlanManana.compartido.fijar(PlanPendientes(
        hoy: [ItemPlan(texto: "Enviar el poder firmado", origen: .tarea), ItemPlan(texto: "Revisar la cláusula 7", origen: .recordatorio), ItemPlan(texto: "Llamar a Carla", origen: .recordatorio)],
        semana: [ItemPlan(texto: "Presentar la propuesta T3", origen: .hito), ItemPlan(texto: "Cerrar la base de clientes", origen: .meta), ItemPlan(texto: "Home v4 de Orbita", origen: .meta),
                 ItemPlan(texto: "Abrir el brief 5 de 7 días", origen: .meta)]))
    var iconos: [String: NSImage] = [:]
    for a in estado.appsVisibles { iconos[a.id] = CatalogoApps.icono(a.ruta) }
    estado.fijarIconos(iconos)
    return estado
}

@MainActor
func hojaEspacios(_ carpeta: URL) -> Bool {
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    let env = ProcessInfo.processInfo.environment
    let texto = env["DICTADO_ESPACIOS"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? EspaciosIsla.sugeridos
    let espacios = EspaciosIsla.leer(texto)
    let ahora = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 14, minute: 48)) ?? Date()
    let catalogo = CatalogoApps(vivo: false)
    catalogo.apps = CatalogoApps.escanear(CatalogoApps.carpetas)
    catalogo.abierto = true
    let suite = "app.dictado.prueba.espacios"
    guard let defaults = UserDefaults(suiteName: suite) else { return false }
    defer { defaults.removePersistentDomain(forName: suite) }
    let ancho: CGFloat = 1512, alto: CGFloat = 982
    var bien = true
    for e in espacios {
        let ruta = e.rutaFondoDePantalla() ?? ""
        let paleta = e.paletaAurora ?? .medianocheOro
        // Dock
        let estado = estadoDockDeEspacios(espacios: espacios, actual: e.nombre, catalogo: catalogo.apps, ahora: ahora)
        let pantalla = PantallaDock(anchoDisponible: ancho - 2 * CGFloat(MedidasDock.margenLateral))
        pantalla.simulado = true
        pantalla.aparecida = true
        pantalla.tonos = TonosDock.de(paleta: paleta)
        let barraAlto = AuroraDock.alto + AuroraDock.margenInferior + AuroraDock.margenSombra
        let selectorAlto = AuroraDock.selectorAlto + 2 * AuroraDock.margenSombra
        let altoDock = barraAlto + selectorAlto - 38
        let fondo = fondoReducido(ruta, ancho: ancho)
        let dockVista = VStack(spacing: -38) {
            VistaSelectorDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: selectorAlto)
            VistaDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: barraAlto)
        }
        .frame(width: ancho, height: altoDock, alignment: .bottom)
        let hojaDock = ZStack(alignment: .bottom) {
            if let fondo { Image(nsImage: fondo).resizable().scaledToFill().frame(width: ancho, height: 260, alignment: .bottom).clipped() }
            dockVista
        }
        .frame(width: ancho, height: 260)
        // Lanzador
        defaults.removePersistentDomain(forName: suite)
        let est = EstadoLanzador(catalogo: catalogo, defaults: defaults)
        let datos = datosLanzadorDeMuestra(ahora: ahora, catalogo: catalogo)
        datos.lanzador.fijar(carpetas: datos.lanzador.carpetas, espacios: espacios, espacio: e.nombre, atajos: [])
        datos.apps.fijar(["com.anthropic.claudefordesktop", "com.spotify.client", "net.whatsapp.WhatsApp", "com.apple.Safari", "com.valvesoftware.steam",
                          "com.nvidia.gfnpc.mall", "com.apple.Photos", "com.apple.Notes", "com.apple.iCal", "com.apple.reminders", "com.apple.mail", "com.apple.MobileSMS",
                          "com.apple.Music", "com.apple.finder"].compactMap { id in catalogo.apps.first { $0.bundleID == id } }, iconos: [:])
        est.datos = datos
        est.reservaInferior = AuroraLanzador.bandaDock
        let leida = leerFondoParaRender(ruta, ancho: ancho)
        est.fondoModelo.fijar(imagen: leida?.imagen, luminancia: leida?.luminancia)
        est.mover(.derecha)
        for el in est.elementos.prefix(60) { for a in el.apps { catalogo.iconos[a.id] = CatalogoApps.icono(a.ruta) } }
        let raiz = RaizLanzador(estado: est, catalogo: catalogo, datos: datos, acciones: AccionesLanzador(), simulado: true)
            .environment(\.vidrioSimulado, true)
            .frame(width: ancho, height: alto)
        let lanzador = ZStack(alignment: .bottom) { raiz; dockVista }.frame(width: ancho, height: alto)
        for (nombre, vista) in [("dock", AnyView(hojaDock)), ("lanzador", AnyView(lanzador))] {
            let r = ImageRenderer(content: vista)
            r.scale = 1
            guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { bien = false; continue }
            let archivo = carpeta.appendingPathComponent("\(nombre)-\(e.nombre.lowercased().replacingOccurrences(of: "ñ", with: "n")).png")
            bien = ((try? png.write(to: archivo)) != nil) && bien
            print(archivo.path)
        }
    }
    return bien
}
