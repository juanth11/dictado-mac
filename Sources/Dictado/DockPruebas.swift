import AppKit
import DictadoKit
import SwiftUI

// Renders y prueba de memoria del Dock, sin abrir ninguna ventana a la vista:
//   DICTADO_ESCENA=dockTrabajo Dictado --vista-dock /tmp/dock.png
// Escenas: dockManana, dockTrabajo, dockFoco, dockDescanso, dockCarpeta (panel de carpeta abierto), dockGrupo (grupo de apps
// abierto), dockTodas (la hoja con todo). Usa ImageRenderer, datos inventados, una hora fija (lunes 16 de noviembre de 2026,
// 2:48 p. m.) y carpetas de muestra en /tmp.
//   Dictado --probar-dock-memoria   arma y suelta la jerarquía de vistas del Dock 30 veces y mide la memoria.

enum EscenaDock: String {
    case dockManana, dockTrabajo, dockFoco, dockDescanso, dockCarpeta, dockGrupo, dockTodas, dockLanzador, dockLargos, dockCarpetaLarga, dockAbanico, dockAbiertas, dockSeleccion, dockCarpeta512, dockLupa, dockVentanas
    var espacio: String {
        switch self {
        case .dockManana: return "Mañana"
        case .dockFoco: return "Foco"
        case .dockDescanso: return "Descanso"
        case .dockLanzador: return "Inicio"
        case .dockLargos, .dockCarpetaLarga: return "Largos"
        default: return "Trabajo"
        }
    }
}

private let ahoraDock: Date = {
    let c = Calendar.current
    let lunes = c.date(from: DateComponents(year: 2026, month: 11, day: 16)) ?? Date()
    return c.date(bySettingHour: 14, minute: 48, second: 0, of: lunes) ?? lunes
}()

/// Fondos de muestra (uno por espacio): cuatro degradados de tonos distintos.
@MainActor
private func fondoDock(_ espacio: String) -> NSImage {
    let colores: [NSColor]
    switch espacio {
    case "Mañana": colores = [NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.62, green: 0.72, blue: 0.90, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.97, alpha: 1)]
    case "Foco": colores = [NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1), NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.20, alpha: 1), NSColor(calibratedRed: 0.45, green: 0.10, blue: 0.55, alpha: 1)]
    case "Descanso": colores = [NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.50, alpha: 1), NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1), NSColor(calibratedRed: 0.80, green: 0.93, blue: 0.95, alpha: 1)]
    default: colores = [NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.40, alpha: 1), NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.65, alpha: 1), NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.90, alpha: 1)]
    }
    let imagen = NSImage(size: NSSize(width: 1440, height: 400))
    imagen.lockFocus()
    NSGradient(colors: colores)?.draw(in: NSRect(x: 0, y: 0, width: 1440, height: 400), angle: -20)
    imagen.unlockFocus()
    return imagen
}

/// Carpetas de muestra con archivos inventados (texto e imágenes dibujadas) y fechas de modificación escalonadas.
@MainActor
private func carpetaDeMuestra(_ nombre: String, base: String, archivos: Int, ahora: Date, largos: Bool = false) -> String {
    let fm = FileManager.default
    let ruta = base + "/" + nombre
    try? fm.removeItem(atPath: ruta)
    try? fm.createDirectory(atPath: ruta, withIntermediateDirectories: true)
    let nombres = ["Contrato marco.txt", "Memo de IVA.md", "captura 1.png", "Acta comité.txt", "Poder firmado.txt", "diagrama.png", "Notas reunión.md",
                   "Propuesta.txt", "captura 2.png", "Balance.txt", "Borrador.md", "Cronograma.txt", "logo.png", "Resumen.txt", "foto.png"]
    for i in 0..<archivos {
        let base = nombres[i % nombres.count]
        let (stem, ext) = (((base as NSString).deletingPathExtension), (base as NSString).pathExtension)
        let n = largos ? "Informe trimestral de resultados financieros consolidados del grupo \(i + 1).\(ext)" : i < nombres.count ? base : "\(stem) \(i / nombres.count + 1).\(ext)"
        let url = URL(fileURLWithPath: ruta + "/" + n)
        if ext == "png" {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 90, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGradient(colors: [NSColor(calibratedHue: CGFloat(i % 7) / 7, saturation: 0.6, brightness: 0.9, alpha: 1), NSColor(calibratedHue: CGFloat((i + 3) % 7) / 7, saturation: 0.7, brightness: 0.5, alpha: 1)])?
                .draw(in: NSRect(x: 0, y: 0, width: 120, height: 90), angle: 30)
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        } else {
            try? "Texto de muestra \(i)".write(to: url, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.modificationDate: ahora.addingTimeInterval(-Double(i * i) * 1500 - 600)], ofItemAtPath: url.path)
    }
    return ruta
}

/// El clima inventado de las pruebas (sin red): 18° ahora en Bogotá, se siente 17°, despejado, de noche.
@MainActor
func climaDeMuestra(ahora: Date = Date()) -> ClimaModelo {
    let c = ClimaModelo(vivo: false)
    c.fijar(ClimaActual(temperatura: 18, sensacion: 17, codigo: 0, esDia: false, maxima: 19, minima: 9), lugar: "Bogotá", ahora: ahora)
    return c
}

/// La barra del Dock y su selector de espacios como se ven con el lanzador abierto (para el render del lanzador): sin fondo propio.
@MainActor
func vistaDockDeMuestra(ancho: CGFloat, tonos: TonosDock? = nil) -> (vista: AnyView, alto: CGFloat) {
    let (estado, _) = estadoDeMuestra(.dockLanzador, base: "/tmp/aurora7/demo")
    let pantalla = PantallaDock(anchoDisponible: ancho - 2 * CGFloat(MedidasDock.margenLateral))
    pantalla.simulado = true
    pantalla.aparecida = true
    if let tonos { pantalla.tonos = tonos }
    let barraAlto = AuroraDock.alto + AuroraDock.margenInferior + AuroraDock.margenSombra
    let selectorAlto = AuroraDock.selectorAlto + 2 * AuroraDock.margenSombra
    let alto = barraAlto + selectorAlto - 38
    let vista = AnyView(VStack(spacing: -38) {
        VistaSelectorDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: selectorAlto)
        VistaDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: barraAlto)
    }
    .frame(width: ancho, height: alto, alignment: .bottom))
    return (vista, alto)
}

/// Todo lo que el Dock lee, inventado (las apps son las que trae macOS).
@MainActor
private func estadoDeMuestra(_ escena: EscenaDock, base: String) -> (estado: EstadoDock, carpetas: [String: String]) {
    let cal = Calendar.current
    let lunes = cal.startOfDay(for: ahoraDock)
    func a(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: lunes) ?? lunes }
    let agenda = Agenda(vivo: false)
    agenda.permitido = true
    var e1 = Agenda.Evento(id: "1", titulo: escena == .dockLargos ? "Revisión integral del contrato marco de prestación de servicios con el cliente" : "Revisión de contrato", inicio: a(15), fin: a(16), color: .blue, enlace: URL(string: "https://meet.google.com/abc-defg-hij"),
                           personas: ["Carla Díaz", "Pedro León", "Marta Ruiz", "Luis Prado"])
    e1.invitados = ["Carla Díaz", "Pedro León", "Marta Ruiz", "Luis Prado"]
    let e2 = Agenda.Evento(id: "2", titulo: "Cliente nuevo", inicio: a(17, 30), fin: a(18), color: .purple)
    agenda.eventos = [e1, e2]

    let musica = Musica(vivo: false)
    let fondo = fondoDock("Descanso")
    let caratula = NSImage(size: NSSize(width: 300, height: 300))
    caratula.lockFocus()
    fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 300, y: 0, width: 400, height: 400), operation: .copy, fraction: 1)
    caratula.unlockFocus()
    musica.titulo = escena == .dockLargos ? "Weightless (versión extendida para trabajar con concentración profunda)" : "Weightless"
    musica.artista = escena == .dockLargos ? "Marconi Union con la Orquesta Sinfónica del Estudio Sur" : "Marconi Union"
    musica.duracion = 480
    musica.posicion = 96
    musica.sonando = true
    musica.caratula = caratula
    musica.acento = Musica.colorMedio(caratula)
    musica.origen = Musica.spotify
    musica.nombreOrigen = "Spotify"
    musica.puedeSaltar = true

    let claude = SesionesClaude(vivo: false)
    claude.sesiones = [
        .init(id: "a", pid: 1, nombre: escena == .dockLargos ? "Contrato marco de prestación de servicios con anexos y cláusulas de exclusividad" : "Contrato marco", carpeta: "proyectos", estado: .esperando, espera: "Necesita tu permiso", desde: Date(), contexto: 1, actividad: ""),
        .init(id: "b", pid: 2, nombre: "Memo de IVA", carpeta: "proyectos", estado: .trabajando, espera: "", desde: Date(), contexto: 1, actividad: ""),
        .init(id: "c", pid: 3, nombre: "Correos", carpeta: "notas", estado: .trabajando, espera: "", desde: Date(), contexto: 1, actividad: ""),
        .init(id: "d", pid: 4, nombre: "Informe", carpeta: "x", estado: .esperando, espera: "Necesita tu permiso", desde: Date(), contexto: 1, actividad: ""),
    ]
    let foco = Foco(vivo: false)
    if escena == .dockFoco { foco.empezar("Memo de IVA", minutos: 25, inicio: Date().addingTimeInterval(-8.3 * 60)) }
    let tareas = TareasIsla(pendientes: nil, vivo: false)
    tareas.fijar([TareaVista(id: "c1", rotulo: "", texto: escena == .dockLargos ? "Enviar el poder firmado y autenticado a Carla Díaz y a todo el equipo jurídico del cliente" : "Enviar el poder", cita: nil, origen: .centro(1)), TareaVista(id: "c2", rotulo: "", texto: "Revisar cláusula", cita: nil, origen: .centro(2)),
                  TareaVista(id: "c3", rotulo: "", texto: "Agendar demo", cita: nil, origen: .centro(3)), TareaVista(id: "c4", rotulo: "", texto: "Pagar", cita: nil, origen: .centro(4)),
                  TareaVista(id: "c5", rotulo: "", texto: "Llamar", cita: nil, origen: .centro(5))], hechas: 2, delCentro: true)
    let salud = EstadoSalud()
    salud.cpu = 0.23
    salud.memoriaTotal = 24 * 1.073741824e9
    salud.memoriaUsada = 14e9
    salud.presion = 1
    salud.discoLibre = 704e9
    salud.discoTotal = 994e9
    let estadoIsla = EstadoIsla()

    // Apps de macOS y carpetas.
    var catalogo: [EntradaApp] = []
    var iconos: [String: NSImage] = [:]
    func instalada(_ id: String) -> EntradaApp? {
        if let e = catalogo.first(where: { $0.bundleID == id }) { return e }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let e = EntradaApp(nombre: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), ruta: url.path, bundleID: id)
        catalogo.append(e)
        iconos[e.id] = CatalogoApps.icono(url.path)
        return e
    }
    let ids = ["com.apple.Safari", "com.apple.Notes", "com.apple.iCal", "com.apple.Terminal", "com.apple.Chess", "com.apple.Photos", "com.apple.Maps",
               "com.apple.mail", "com.apple.MobileSMS", "com.apple.reminders", "com.apple.Preview", "com.apple.TextEdit", "com.apple.systempreferences", "com.apple.calculator"]
    ids.forEach { _ = instalada($0) }
    let apps = AppsUsadas(vivo: false)
    apps.fijar(Array(catalogo.prefix(6)), iconos: iconos)
    apps.fijar(catalogo: catalogo, categorias: [:])

    let proyectos = carpetaDeMuestra("Proyectos", base: base, archivos: 14, ahora: ahoraDock)
    let descargas = carpetaDeMuestra("Descargas", base: base, archivos: 9, ahora: ahoraDock)
    let salidas = carpetaDeMuestra("Salidas", base: base, archivos: 6, ahora: ahoraDock)
    let recientes = carpetaDeMuestra("Recientes", base: base, archivos: 6, ahora: ahoraDock)
    let largas = carpetaDeMuestra("Proyectos y entregables del cliente nuevo", base: base, archivos: 9, ahora: ahoraDock, largos: true)
    let texto = """
    [Mañana]
    dock: reloj, fecha, tareas, dictar, | com.apple.Safari, com.apple.Notes, com.apple.iCal, | carpeta:\(descargas), papelera
    [Trabajo]
    dock: reloj, agenda, agentes, dictar, | com.apple.Terminal, com.apple.Safari, com.apple.Notes, abiertas, | grupo:Trabajo, carpeta:\(proyectos), carpeta:\(recientes), finder, papelera
    [Foco]
    dock: reloj, foco, musica, | com.apple.Notes, com.apple.Terminal, | carpeta:\(proyectos), papelera
    [Descanso]
    dock: reloj, musica, mac, bateria, | com.apple.Chess, com.apple.Photos, com.apple.Maps, | papelera
    [Largos]
    dock: reloj, agenda, tareas, musica, agentes, | com.apple.Terminal, com.apple.Notes, | carpeta:\(largas), papelera
    [Inicio]
    dock: lanzador, reloj, clima, agenda, | com.apple.Safari, com.apple.Notes, com.apple.Terminal, com.apple.Photos, | carpeta:\(descargas), papelera
    """
    let grupos = [CarpetaApps(nombre: "Trabajo", apps: ["com.apple.mail", "com.apple.MobileSMS", "com.apple.reminders", "com.apple.Preview", "com.apple.TextEdit", "com.apple.systempreferences",
                                                         "com.apple.calculator", "com.apple.Notes", "com.apple.iCal"])]
    let lanzador = LanzadorIsla(vivo: false)
    lanzador.fijar(carpetas: grupos, espacios: EspaciosIsla.leer(texto), espacio: escena.espacio, atajos: [])

    let estado = EstadoDock(agenda: agenda, musica: musica, claude: claude, agentes: AgentesRemotos(vivo: false), foco: foco, tareas: tareas, salud: salud,
                            hud: EstadoHUD(), estadoIsla: estadoIsla, lanzador: lanzador, apps: apps, vivo: false)
    estado.ahoraFijo = ahoraDock
    estado.clima = climaDeMuestra(ahora: ahoraDock)
    let tablero = TableroIsla(vivo: false)
    tablero.fijar(tableroDeMuestra(ahora: ahoraDock, sesionViva: "b"), leido: ahoraDock)
    estado.tablero = tablero
    estado.fijarIconos(iconos)
    estado.bateria.fijar(porcentaje: 83, cargando: false)
    estado.fijarPapelera(llena: true)
    estado.abiertas.fijar(["com.apple.Safari", "com.apple.Photos", "com.apple.Maps", "com.apple.mail", "com.apple.Preview", "com.apple.MobileSMS", "com.apple.Chess"]
        .compactMap { id in catalogo.first { $0.bundleID == id } })
    estado.finder.fijar([descargas])
    return (estado, ["recientes": recientes, "proyectos": proyectos, "descargas": descargas, "salidas": salidas, "largas": largas])
}

/// La posición (en x, desde el borde izquierdo de la pantalla) del centro de una pieza de la barra.
private func centroDe(_ pieza: PiezaDock, en d: DisposicionDock, ancho: CGFloat) -> CGFloat {
    var x = (ancho - CGFloat(d.ancho)) / 2 + AuroraDock.relleno
    for c in d.piezas {
        if c.pieza == pieza { return x + CGFloat(c.ancho) / 2 }
        x += CGFloat(c.ancho) + AuroraDock.separacion
    }
    return ancho / 2
}

@MainActor
private func esperarMiniaturas(_ m: ModeloCarpeta, segundos: Double = 8) {
    let limite = Date().addingTimeInterval(segundos)
    while m.pendientes > 0, Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

@MainActor
private func escenaDock(_ tipo: EscenaDock, base: String) -> AnyView {
    let (estado, carpetas) = estadoDeMuestra(tipo, base: base)
    let ancho: CGFloat = 1440
    let pantalla = PantallaDock(anchoDisponible: ancho - 2 * CGFloat(MedidasDock.margenLateral))
    pantalla.simulado = true
    pantalla.aparecida = true
    let fondo = fondoDock(tipo.espacio)
    if let cg = fondo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let chico = NSImage(size: NSSize(width: 40, height: 14))
        chico.lockFocus()
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: 0, y: 0, width: 40, height: 14))
        chico.unlockFocus()
        if let c = chico.cgImage(forProposedRect: nil, context: nil, hints: nil), let t = FondoPantalla.tonos(imagen: c) { pantalla.tonos = TonosDock.de(t) }
    }
    let disposicion = ReglasDock.colocar(estado.piezas, anchoDisponible: pantalla.anchoDisponible)
    if tipo == .dockLupa {
        // La lupa simulada: los marcos en reposo salen del reparto (centrado en la ventana) y el puntero queda sobre una app.
        var x = (ancho - CGFloat(disposicion.piezas.map(\.ancho).reduce(0, +)) - CGFloat(max(0, disposicion.piezas.count - 1)) * AuroraDock.separacion) / 2
        var marcos: [(CGRect, Bool)] = []
        var objetivo: CGFloat = ancho / 2
        var apps = 0
        for c in disposicion.piezas {
            let w = CGFloat(c.ancho)
            marcos.append((CGRect(x: x, y: 0, width: w, height: AuroraDock.piezaAlto), piezaCreceConLupa(c.pieza)))
            if case .app = c.pieza { apps += 1; if apps == 3 { objetivo = x + w / 2 + 14 } }
            x += w + AuroraDock.separacion
        }
        pantalla.lupa.simular(marcos: marcos, puntero: objetivo)
    }
    var panel: AnyView?
    var altoPanel: CGFloat = 0
    if tipo == .dockCarpeta || tipo == .dockCarpetaLarga || tipo == .dockAbanico || tipo == .dockSeleccion {
        let ruta = carpetas[tipo == .dockCarpeta || tipo == .dockSeleccion ? "proyectos" : tipo == .dockAbanico ? "recientes" : "largas"] ?? ""
        let seleccion = SeleccionPila()
        if tipo == .dockSeleccion || tipo == .dockAbanico { seleccion.indice = 1 }
        let m = ModeloCarpeta(ruta: ruta, escala: 2)
        m.fijar(ModeloCarpeta.listar(ruta) ?? [])
        m.pedirMiniaturas()
        esperarMiniaturas(m)
        let medidas = AuroraDock.medidasPanel(modo: AuroraDock.modoPila(m.archivos.count), cuantos: m.archivos.count)
        altoPanel = medidas.height + 2 * AuroraDock.panelMargen
        let x = centroDe(.carpeta(ruta), en: disposicion, ancho: ancho)
        panel = AnyView(PanelCarpetaVista(modelo: m, tonos: pantalla.tonos, seleccion: seleccion, simulado: true, ahoraFijo: ahoraDock)
            .frame(width: medidas.width + 2 * AuroraDock.panelMargen, height: altoPanel)
            .position(x: x, y: altoPanel / 2))
    } else if tipo == .dockAbiertas {
        let apps = estado.abiertasNoFijas
        altoPanel = AuroraDock.altoPanel(filas: CarpetaDock.filas(apps.count)) + 2 * AuroraDock.panelMargen
        let x = centroDe(.abiertas, en: disposicion, ancho: ancho)
        let sel = SeleccionPila()
        sel.indice = 1
        panel = AnyView(PanelGrupoVista(nombre: "Abiertas", apps: apps, estado: estado, tonos: pantalla.tonos, seleccion: sel, simulado: true,
                                        subtitulo: "\(apps.count) abiertas · toca una para traerla al frente")
            .frame(width: AuroraDock.anchoPanel() + 2 * AuroraDock.panelMargen, height: altoPanel)
            .position(x: x, y: altoPanel / 2))
    } else if tipo == .dockVentanas, let app = estado.appsVisibles.dropFirst(2).first {
        let m = ModeloVentanasApp(app: app)
        let hojas = (0..<2).map { i -> NSImage in
            NSImage(size: NSSize(width: 192, height: 120), flipped: false) { r in
                NSColor(calibratedHue: 0.58 + 0.1 * CGFloat(i), saturation: 0.25, brightness: 0.9, alpha: 1).setFill(); r.fill()
                NSColor(white: 1, alpha: 0.8).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 96, width: r.width, height: 24)).fill()
                return true
            }
        }
        let pestanas = ["Bandeja de entrada (12)", "Plan de pendientes - Notion", "Revisión de contrato marco", "Tablero de Lumina", "Calendario - semana 47", "Finanzas personales"]
            .enumerated().map { PestanaApp(id: "\($0.offset)", titulo: $0.element, indice: $0.offset + 1, activa: $0.offset == 2) }
        m.fijar([ModeloVentanasApp.Item(id: 0, titulo: "Revisión de contrato marco", miniatura: hojas[0], pestanas: pestanas),
                 ModeloVentanasApp.Item(id: 1, titulo: "Notas de la reunión", miniatura: hojas[1]),
                 ModeloVentanasApp.Item(id: 2, titulo: "Documento sin título", miniatura: nil, minimizada: true)], miniaturas: true)
        altoPanel = m.medidas.height + 2 * AuroraDock.panelMargen
        let x = centroDe(.app(app.id), en: disposicion, ancho: ancho)
        panel = AnyView(PanelVentanasVista(modelo: m, estado: estado, tonos: pantalla.tonos, simulado: true)
            .frame(width: m.medidas.width + 2 * AuroraDock.panelMargen, height: altoPanel)
            .position(x: x, y: altoPanel / 2))
    } else if tipo == .dockGrupo {
        let apps = estado.appsDelGrupo("Trabajo")
        altoPanel = AuroraDock.altoPanel(filas: CarpetaDock.filas(apps.count)) + 2 * AuroraDock.panelMargen
        let x = centroDe(.grupo("Trabajo"), en: disposicion, ancho: ancho)
        panel = AnyView(PanelGrupoVista(nombre: "Trabajo", apps: apps, estado: estado, tonos: pantalla.tonos, simulado: true)
            .frame(width: AuroraDock.anchoPanel() + 2 * AuroraDock.panelMargen, height: altoPanel)
            .position(x: x, y: altoPanel / 2))
    }
    let barraAlto = AuroraDock.alto + AuroraDock.margenInferior + AuroraDock.margenSombra + (tipo == .dockLupa ? AuroraDockLupa.aireArriba : 0)
    let selectorAlto = AuroraDock.selectorAlto + 2 * AuroraDock.margenSombra
    let alto = max(barraAlto + selectorAlto - 38, 190) + (altoPanel > 0 ? altoPanel - 38 + 8 : 0)
    return AnyView(ZStack(alignment: .bottom) {
        Image(nsImage: fondo).resizable().scaledToFill().frame(width: ancho, height: alto, alignment: .bottom).clipped()
        VStack(spacing: 0) {
            if let panel { panel.frame(width: ancho, height: altoPanel).padding(.bottom, -38 + 8) }
            VStack(spacing: -38) {
                VistaSelectorDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: selectorAlto)
                VistaDock(estado: estado, pantalla: pantalla).frame(width: ancho, height: barraAlto)
            }
        }
        .frame(width: ancho, height: alto, alignment: .bottom)
    }
    .frame(width: ancho, height: alto)
    .clipShape(RoundedRectangle(cornerRadius: 14)))
}

/// `DICTADO_ESCENA=dockTrabajo Dictado --vista-dock salida.png`
@MainActor
func hojaDock(_ destino: URL) -> Bool {
    let nombre = ProcessInfo.processInfo.environment["DICTADO_ESCENA"] ?? "dockTrabajo"
    guard let tipo = EscenaDock(rawValue: nombre) else { print("escena desconocida: \(nombre)"); return false }
    let base = "/tmp/aurora3/demo"
    try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    let hoja: AnyView
    if tipo == .dockCarpeta512 {
        // Una sola carpeta a 512 px, con y sin miniatura, sobre el gris claro de las referencias.
        let foto = fotoDeMuestra()
        hoja = AnyView(HStack(spacing: 40) {
            CarpetaVidrioEscalada(nombre: "Archives", detalle: "Wed 19 Aug", foto: nil, ancho: 512, texto: 0.06)
            CarpetaVidrioEscalada(nombre: "My Files", detalle: "Wed 19 Aug", foto: foto, ancho: 512, texto: 0.06)
        }
        .padding(60).background(Color(white: 0.965)))
    } else if tipo == .dockTodas {
        hoja = AnyView(VStack(spacing: 14) {
            ForEach([EscenaDock.dockManana, .dockTrabajo, .dockFoco, .dockDescanso, .dockCarpeta, .dockGrupo], id: \.rawValue) { t in escenaDock(t, base: base) }
        }
        .padding(14).background(Color(white: 0.08)))
    } else {
        hoja = escenaDock(tipo, base: base)
    }
    let r = ImageRenderer(content: hoja)
    r.scale = tipo == .dockTodas || tipo == .dockCarpeta512 ? 1 : 2
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

// MARK: - Memoria

private func huellaMB() -> (huella: Double, residente: Double) {
    var info = task_vm_info_data_t()
    var cuenta = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &cuenta) }
    }
    guard r == KERN_SUCCESS else { return (0, 0) }
    return (Double(info.phys_footprint) / 1_048_576, Double(info.resident_size) / 1_048_576)
}

/// Arma y suelta 30 veces la jerarquía de vistas del Dock (barra, selector y el panel de una carpeta con 40 miniaturas) fuera de
/// pantalla: ninguna ventana se muestra. Imprime la memoria antes, tras el calentamiento y al final.
@MainActor
func probarDockMemoria() -> Bool {
    let base = "/tmp/dictado-dock-memoria"
    try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    let (estado, carpetas) = estadoDeMuestra(.dockTrabajo, base: base)
    let ruta = carpetaDeMuestra("Cuarenta", base: base, archivos: 40, ahora: ahoraDock)
    _ = carpetas
    var miniaturasTotales = 0
    var pixeles = 0

    func ciclo() {
        autoreleasepool {
            let pantalla = PantallaDock(anchoDisponible: 1392)
            pantalla.simulado = true
            pantalla.aparecida = true
            let barra = VistaPrimerClic(rootView: AnyView(VistaDock(estado: estado, pantalla: pantalla)))
            let selector = VistaPrimerClic(rootView: AnyView(VistaSelectorDock(estado: estado, pantalla: pantalla)))
            let modelo = ModeloCarpeta(ruta: ruta, escala: 2)
            modelo.fijar(ModeloCarpeta.listar(ruta) ?? [])
            miniaturasTotales += modelo.pedirMiniaturas()
            esperarMiniaturas(modelo)
            let panel = VistaPrimerClic(rootView: AnyView(PanelCarpetaVista(modelo: modelo, tonos: pantalla.tonos, simulado: true, ahoraFijo: ahoraDock)))
            // Una ventana que nunca se muestra: solo para que las vistas tengan dónde colgar y dibujarse.
            let ventana = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            ventana.isReleasedWhenClosed = false
            for (v, tam) in [(barra as NSView, NSSize(width: 1440, height: 130)), (selector, NSSize(width: 400, height: 90)), (panel, NSSize(width: 520, height: 420))] {
                ventana.contentView = v
                v.frame = NSRect(origin: .zero, size: tam)
                v.layoutSubtreeIfNeeded()
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    pixeles += rep.pixelsWide * rep.pixelsHigh
                }
            }
            // Desmontaje, igual que el del Dock al esconderse.
            modelo.soltar()
            for v in [barra, selector, panel] { v.rootView = AnyView(EmptyView()); v.removeFromSuperview() }
            ventana.contentView = nil
        }
    }

    let frio = huellaMB()
    for _ in 0..<3 { ciclo() }
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    let antes = huellaMB()
    for _ in 0..<30 { ciclo() }
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    let despues = huellaMB()
    print(String(format: "memoria (MB)   huella  residente"))
    print(String(format: "en frío        %6.1f  %6.1f", frio.huella, frio.residente))
    print(String(format: "tras 3 ciclos  %6.1f  %6.1f", antes.huella, antes.residente))
    print(String(format: "tras 30 más    %6.1f  %6.1f", despues.huella, despues.residente))
    print(String(format: "diferencia     %+6.1f  %+6.1f  (%.2f MB por ciclo de huella)", despues.huella - antes.huella, despues.residente - antes.residente, (despues.huella - antes.huella) / 30))
    print("miniaturas pedidas: \(miniaturasTotales), píxeles dibujados: \(pixeles)")
    try? FileManager.default.removeItem(atPath: base)
    return pixeles > 0 && despues.huella - antes.huella < 15
}


/// Una imagen de muestra (olas rojas y azules) para la placa de la carpeta.
@MainActor
func fotoDeMuestra() -> CGImage? {
    let r = ImageRenderer(content: ZStack {
        LinearGradient(colors: [Color(hex: 0x1F4E6B), Color(hex: 0x0E2230)], startPoint: .topLeading, endPoint: .bottomTrailing)
        Ellipse().fill(Color(hex: 0xE0442F)).frame(width: 220, height: 90).rotationEffect(.degrees(-24)).offset(x: 20, y: 40).blur(radius: 14)
        Ellipse().fill(Color(hex: 0xF2784A)).frame(width: 120, height: 60).rotationEffect(.degrees(20)).offset(x: -70, y: -30).blur(radius: 12)
    }.frame(width: 240, height: 200))
    r.scale = 1
    return r.cgImage
}
