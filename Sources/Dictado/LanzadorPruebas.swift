import AppKit
import DictadoKit
import SwiftUI

// Renders y prueba del lanzador. Ninguno toca tus ajustes, tu portapapeles ni tu agenda: usan datos inventados y un
// dominio de defaults desechable.
//   Dictado --vista-lanzador salida.png [oscuro|claro|todas|carpeta|buscar|cuenta|selector|dock]   render sin abrir la app (sin escena: las
//       siete principales, en salida-<escena>.png). 1512 × 982 sobre un fondo de verdad: DICTADO_FONDO=/ruta (oscuro) y DICTADO_FONDO_CLARO=/ruta;
//       sin ellas, el fondo de pantalla actual y una imagen clara de /System/Library/Desktop Pictures.
//   Dictado --probar-lanzador-memoria [N]   abre y cierra N veces la ventana real SIN mostrarla (con el fondo del Mac leyéndose) y mide la
//       memoria y el tiempo hasta el primer cuadro

/// Datos de ejemplo: una agenda con dos reuniones, una canción a punto de acabar, cinco sesiones de Claude, el Tablero inventado, las
/// carpetas de apps, los espacios y los atajos de Inicio. Las apps son las que trae macOS.
@MainActor
func datosLanzadorDeMuestra(ahora: Date, catalogo: CatalogoApps? = nil) -> DatosLanzador {
    let cal = Calendar.current
    func hoy(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: ahora) ?? ahora }
    let agenda = Agenda(vivo: false)
    agenda.permitido = true
    var daily = Agenda.Evento(id: "1", titulo: "Daily de producto", inicio: hoy(14, 30), fin: hoy(15, 15), color: .blue,
                              enlace: URL(string: "https://meet.google.com/abc-defg-hij"), personas: ["Lucía", "Marcos", "Elena"])
    daily.invitados = ["Lucía Pérez", "Marcos Díaz", "Elena Ruiz"]
    var contrato = Agenda.Evento(id: "2", titulo: "Revisión de contrato", inicio: hoy(16), fin: hoy(16, 45), color: .green,
                                 enlace: URL(string: "https://zoom.us/j/123456789"), personas: ["Marcos"])
    contrato.invitados = ["Marcos Díaz"]
    var almuerzo = Agenda.Evento(id: "3", titulo: "Almuerzo", inicio: hoy(12), fin: hoy(13), color: .orange)
    almuerzo.invitados = []
    var cliente = Agenda.Evento(id: "4", titulo: "Visita al cliente", inicio: hoy(17, 30), fin: hoy(18, 30), color: .purple, personas: ["Elena"])
    cliente.invitados = ["Elena Ruiz"]
    cliente.lugar = "Calle 10 #20-30, Bogotá"
    contrato.lugar = "Oficina Lumina"
    agenda.eventos = [almuerzo, daily, contrato, cliente]
    // Otros días del mes con algo en la agenda, para que el calendario del widget Fecha muestre sus puntos.
    agenda.eventosMes = [3, 5, 9, 12, 18, 19, 24, 27].compactMap { d in
        guard let dia = cal.date(bySetting: .day, value: d, of: ahora) else { return nil }
        let ini = cal.date(bySettingHour: 10, minute: 0, second: 0, of: dia) ?? dia
        return Agenda.Evento(id: "m\(d)", titulo: "Evento \(d)", inicio: ini, fin: ini.addingTimeInterval(3600), color: .blue)
    }

    let musica = Musica(vivo: false)
    musica.titulo = "Noche en calma"
    musica.artista = "Estudio Sur"
    musica.duracion = 204
    musica.posicion = 62
    musica.sonando = false
    musica.puedeSaltar = true
    musica.origen = Musica.spotify
    musica.nombreOrigen = "Spotify"

    let claude = SesionesClaude(vivo: false)
    let hace = ahora.addingTimeInterval(-120)
    claude.sesiones = [
        .init(id: "a", pid: 1, nombre: "Contrato marco", carpeta: "", estado: .esperando, espera: "Plan listo para revisar", desde: ahora.addingTimeInterval(-7 * 60)),
        .init(id: "c", pid: 3, nombre: "Informe trimestral", carpeta: "", estado: .trabajando, espera: "", desde: hace, actividad: "Editando informe.md"),
        .init(id: "d", pid: 4, nombre: "Conciliación de pagos", carpeta: "", estado: .trabajando, espera: "", desde: ahora.addingTimeInterval(-38 * 60), actividad: "Bash · swift test"),
        .init(id: "e", pid: 5, nombre: "Revisión de notas", carpeta: "", estado: .lista, espera: "", desde: ahora.addingTimeInterval(-95 * 60), resumen: "Resumen listo"),
        .init(id: "f", pid: 6, nombre: "Propuesta de honorarios", carpeta: "", estado: .lista, espera: "", desde: ahora.addingTimeInterval(-130 * 60), resumen: "Borrador guardado"),
    ]
    let tablero = TableroIsla(vivo: false)
    tablero.fijar(tableroDeMuestra(ahora: ahora, sesionViva: "c"), leido: ahora)

    // Apps y carpetas: las de macOS que siempre están.
    let instaladas = catalogo?.apps ?? CatalogoApps.escanear(CatalogoApps.carpetas)
    func buscar(_ id: String) -> EntradaApp? { instaladas.first { $0.bundleID == id } }
    let grupos = [
        ("Trabajo", ["com.apple.Notes", "com.apple.iCal", "com.apple.reminders", "com.apple.Preview", "com.apple.TextEdit"]),
        ("Comunicación", ["com.apple.mail", "com.apple.MobileSMS", "com.apple.FaceTime"]),
        ("Desarrollo", ["com.apple.Terminal", "com.apple.ScriptEditor2"]),
        ("Sistema", ["com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.DiskUtility", "com.apple.calculator"]),
    ].map { CarpetaApps(nombre: $0.0, apps: $0.1.filter { buscar($0) != nil }) }
    let apps = AppsUsadas(vivo: false)
    apps.fijar(["com.apple.finder", "com.apple.Safari", "com.apple.Photos", "com.apple.Maps", "com.apple.podcasts", "com.apple.Music", "com.apple.TV",
                "com.apple.AppStore", "com.apple.Preview", "com.apple.Passwords", "com.apple.shortcuts", "com.apple.Stocks", "com.apple.news",
                "com.apple.freeform", "com.apple.VoiceMemos", "com.apple.Chess"].compactMap(buscar), iconos: [:])
    let lanzador = LanzadorIsla(vivo: false)
    lanzador.fijar(carpetas: grupos, espacios: EspaciosIsla.leer(EspaciosIsla.inicial), espacio: "Trabajo",
                   atajos: ["Modo concentración", "Escribir a casa", "Reunión en 5", "Apagar las luces", "Música para trabajar", "Resumen del día"])
    return DatosLanzador(agenda: agenda, musica: musica, claude: claude, agentes: AgentesRemotos(vivo: false), tablero: tablero, lanzador: lanzador,
                         apps: apps, clima: climaDeMuestra(ahora: ahora), foco: nil, config: ConfigHuecos(dias: Set(1...7)), ahora: { ahora })
}

/// Una carátula inventada (un degradado con círculos) para los renders: sin imágenes de nadie.
@MainActor
func caratulaDeMuestra(lado: CGFloat = 300) -> NSImage {
    NSImage(size: NSSize(width: lado, height: lado), flipped: false) { r in
        NSGradient(colors: [NSColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1), NSColor(red: 0.55, green: 0.18, blue: 0.55, alpha: 1),
                            NSColor(red: 0.12, green: 0.20, blue: 0.55, alpha: 1)])?.draw(in: r, angle: -50)
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.width * 0.55, y: r.height * 0.55, width: r.width * 0.28, height: r.width * 0.28)).fill()
        NSColor(white: 0, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.width * 0.1, y: r.height * 0.1, width: r.width * 0.5, height: r.width * 0.5)).fill()
        return true
    }
}

/// Lo que cambia cada escena de muestra sobre los datos base: `musica` suena con carátula; `calma` no tiene reuniones, agentes ni música.
@MainActor
func ajustarEscenaLanzador(_ nombre: String, _ datos: DatosLanzador, ahora: Date) {
    switch nombre {
    case "pausa":
        datos.musica.caratula = caratulaDeMuestra()
    case "musica", "musica-claro":
        datos.musica.sonando = true
        datos.musica.caratula = caratulaDeMuestra()
        datos.musica.posicion = 62
        datos.musica.actualizada = Date()
    case "manana", "manana-vacio", "manana-hecho":
        // El espacio Mañana activo: el plan del día y la semana ocupa el lugar del clima.
        datos.lanzador.fijar(carpetas: datos.lanzador.carpetas, espacios: EspaciosIsla.leer(EspaciosIsla.sugeridos), espacio: "Mañana", atajos: [])
        let cal = Calendar.current
        func a(_ dias: Int, _ h: Int = 0, _ m: Int = 0) -> Date? {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: dias, to: ahora) ?? ahora)
        }
        PlanManana.compartido.fijar(nombre == "manana-vacio" ? .vacio : PlanPendientes(
            hoy: [ItemPlan(texto: "Enviar el poder firmado", vence: a(-1), origen: .recordatorio, id: "R1"),
                  ItemPlan(texto: "Revisar la cláusula 7", vence: a(0, 16, 30), origen: .recordatorio, id: "R2"),
                  ItemPlan(texto: "Declaración de renta Nimbo", origen: .tarea, delDia: true),
                  ItemPlan(texto: "Llamar a Carla", vence: a(0, 18), origen: .recordatorio, id: "R3"),
                  ItemPlan(texto: "Pagar la cuota", origen: .tarea, delDia: true)],
            semana: [ItemPlan(texto: "Presentar la propuesta T3", vence: a(2), origen: .hito),
                     ItemPlan(texto: "Cerrar la base de clientes", origen: .meta),
                     ItemPlan(texto: "Home v4 de Orbita", origen: .meta)]))
        if nombre == "manana-hecho" { PlanManana.compartido.simularHecha("id:R2") }
    case "calma":
        datos.agenda.eventos = []
        datos.claude.sesiones = []
        datos.musica.titulo = ""
        datos.musica.artista = ""
        datos.musica.ultima = Musica.UltimaPista(titulo: "Noche en calma", artista: "Estudio Sur", origen: Musica.spotify, nombreOrigen: "Spotify")
    default: break
    }
}

/// Lee una imagen de fondo como lo hace el lanzador (en otro hilo), esperando el resultado: solo para los renders.
@MainActor
func leerFondoParaRender(_ ruta: String, ancho: CGFloat) -> LectorFondo.Leida? {
    let url = URL(fileURLWithPath: ruta)
    let caja = SyncBox<LectorFondo.Leida>()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        caja.valor = await LectorFondo.leer(url, lado: ancho, oscuro: true, hora: 12)
        sem.signal()
    }
    sem.wait()
    return caja.valor
}

final class SyncBox<T>: @unchecked Sendable { var valor: T? }

/// `Dictado --vista-lanzador salida.png [escena]`. Las apps son las del Mac (sus nombres e íconos), el resto es inventado.
@MainActor
func hojaLanzador(_ destino: URL, escena: String?) -> Bool {
    _ = NSApplication.shared
    let escena = escena ?? ProcessInfo.processInfo.environment["DICTADO_ESCENA"]
    let escenas = escena.map { [$0] } ?? ["oscuro", "claro", "todas", "carpeta", "buscar", "selector", "dock", "musica", "calma"]
    let ahora = Calendar.current.date(bySettingHour: 14, minute: 20, second: 0, of: Date()) ?? Date()
    let catalogo = CatalogoApps(vivo: false)
    catalogo.apps = CatalogoApps.escanear(CatalogoApps.carpetas)
    catalogo.abierto = true
    catalogo.abiertas = Set(catalogo.apps.prefix(24).compactMap(\.bundleID).filter { $0.contains("com.apple") }.prefix(3))
    let suite = "app.dictado.prueba.lanzador"
    guard let defaults = UserDefaults(suiteName: suite) else { return false }
    defer { defaults.removePersistentDomain(forName: suite) }
    let env = ProcessInfo.processInfo.environment
    let actual = NSScreen.screens.first.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path }
    let rutaOscura = env["DICTADO_FONDO"] ?? actual ?? "/System/Library/Desktop Pictures/.thumbnails/Big Sur Graphic.heic"
    let rutaClara = env["DICTADO_FONDO_CLARO"] ?? "/System/Library/Desktop Pictures/.thumbnails/Hello Metallic Silver.heic"
    let ancho: CGFloat = 1512, alto: CGFloat = 982
    var todoBien = true
    for nombre in escenas {
        defaults.removePersistentDomain(forName: suite)
        let estado = EstadoLanzador(catalogo: catalogo, defaults: defaults)
        let ruta = nombre.hasSuffix("claro") ? rutaClara : rutaOscura
        let leida = leerFondoParaRender(ruta, ancho: ancho)
        estado.fondoModelo.fijar(imagen: leida?.imagen, luminancia: leida?.luminancia)
        estado.fondoGlobal = FondoLanzador.imagen(ruta).texto
        let datos = datosLanzadorDeMuestra(ahora: ahora, catalogo: catalogo)
        estado.datos = datos
        ajustarEscenaLanzador(nombre, datos, ahora: ahora)
        estado.reservaInferior = nombre == "dock" ? AuroraLanzador.bandaDock : AuroraLanzador.margenInferior
        switch nombre {
        case "buscar": estado.consulta = "re"; estado.consultaCambio(); estado.mover(.derecha)
        case "cuenta": estado.consulta = "1200 + 15%"; estado.consultaCambio()
        case "carpeta": estado.abrirCarpeta("Trabajo"); estado.mover(.derecha)
        case "todas": estado.elegirSegmento(.todas); estado.mover(.derecha)
        case "selector": estado.selectorAbierto = true; estado.mover(.derecha)
        default: estado.mover(.derecha)
        }
        for e in estado.elementos.prefix(60) { for a in e.apps { catalogo.iconos[a.id] = CatalogoApps.icono(a.ruta) } }
        let raiz = RaizLanzador(estado: estado, catalogo: catalogo, datos: datos, acciones: AccionesLanzador(), simulado: true)
            .environment(\.vidrioSimulado, true)
            .frame(width: ancho, height: alto)
        let contenido: AnyView
        if nombre == "dock" {
            var tonos: TonosDock?
            if let i = leida?.imagen { tonos = FondoPantalla.tonos(imagen: i).map(TonosDock.de) }
            let d = vistaDockDeMuestra(ancho: ancho, tonos: tonos)
            contenido = AnyView(ZStack(alignment: .bottom) { raiz; d.vista.frame(width: ancho, height: d.alto) }.frame(width: ancho, height: alto))
        } else {
            contenido = AnyView(raiz)
        }
        let renderer = ImageRenderer(content: contenido)
        renderer.scale = 2
        guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            todoBien = false
            continue
        }
        let archivo = escena == nil ? URL(fileURLWithPath: destino.deletingPathExtension().path + "-\(nombre).png") : destino
        todoBien = ((try? png.write(to: archivo)) != nil) && todoBien
        print(archivo.path)
    }
    return todoBien
}

private final class WeakBox<T: AnyObject> {
    weak var valor: T?
    init(_ valor: T) { self.valor = valor }
}

// MARK: - Prueba de memoria (sin ventana a la vista)

private func huellaLanzadorMB() -> Double {
    var info = task_vm_info_data_t()
    var cuenta = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &cuenta) }
    }
    return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// `Dictado --probar-lanzador-memoria [N]`: abre y cierra N veces (30 por omisión) la ventana REAL del lanzador, con la lista de
/// apps instaladas, sus íconos, los widgets y el campo de búsqueda, sin ordenarla nunca al frente ni activar la app: no hay
/// nada en pantalla ni sonido. Imprime la huella de memoria en frío, tras el calentamiento y al final.
@MainActor
func probarLanzadorMemoria(ciclos: Int = 30) -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    func esperar(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    let lanzador = Lanzador(isla: { nil }, datosDePrueba: { datosLanzadorDeMuestra(ahora: Date()) })
    var dibujados = 0
    // Tiempos (ms): abrir (hilo principal), primer cuadro (diseño + dibujo) y hasta que llega la imagen del fondo.
    var tAbrir: [Double] = [], tCuadro: [Double] = [], tImagen: [Double] = []
    func ms(_ desde: CFAbsoluteTime) -> Double { (CFAbsoluteTimeGetCurrent() - desde) * 1000 }
    // Quién sigue vivo tras cerrar: la ventana y su vista de SwiftUI. Una ventana que sobrevive guarda su memoria gráfica
    // (en pantalla, un lienzo del tamaño del monitor), que es lo que se veía crecer al abrir y cerrar de verdad.
    var ventanas: [WeakBox<NSWindow>] = []
    var anfitriones: [WeakBox<NSView>] = []
    func ciclo(buscando: Bool) {
        autoreleasepool {
            let t0 = CFAbsoluteTimeGetCurrent()
            lanzador.abrirSinMostrar()
            tAbrir.append(ms(t0))
            while lanzador.estado.fondoModelo.imagen == nil, ms(t0) < 3000 { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            tImagen.append(lanzador.estado.fondoModelo.imagen == nil ? -1 : ms(t0))
            if let v = lanzador.ventanaActual { ventanas.append(WeakBox(v)); if let c = v.contentView { anfitriones.append(WeakBox(c)) } }
            esperar(0.35)   // la lista de apps, los íconos y la primera pasada de SwiftUI
            if buscando { lanzador.estado.consulta = "a"; lanzador.estado.consultaCambio(); esperar(0.1) }
            if let v = lanzador.vistaDelContenido {
                let t1 = CFAbsoluteTimeGetCurrent()
                v.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
                v.layoutSubtreeIfNeeded()
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    dibujados += rep.pixelsWide * rep.pixelsHigh
                }
                tCuadro.append(ms(t1))
            }
            lanzador.cerrar(devolver: false)
            esperar(0.45)
        }
    }

    let frio = huellaLanzadorMB()
    // Con DICTADO_PAUSA=<segundos> el proceso espera al final (para mirarlo con `heap <pid>`).
    defer { if let p = ProcessInfo.processInfo.environment["DICTADO_PAUSA"].flatMap(Double.init) { print("pid \(getpid())"); fflush(stdout); esperar(p) } }
    for i in 0..<3 { ciclo(buscando: i == 1) }
    esperar(1)
    let antes = huellaLanzadorMB()
    for i in 0..<ciclos { ciclo(buscando: i % 3 == 1) }
    esperar(1)
    let despues = huellaLanzadorMB()
    let porCiclo = (despues - antes) / Double(max(1, ciclos))
    print(String(format: "memoria (MB)          huella"))
    print(String(format: "en frío               %6.1f", frio))
    print(String(format: "tras 3 ciclos         %6.1f", antes))
    print(String(format: "tras %d más           %6.1f", ciclos, despues))
    print(String(format: "diferencia            %+6.1f  (%.2f MB por ciclo)", despues - antes, porCiclo))
    let vivasV = ventanas.filter { $0.valor != nil }.count, vivasA = anfitriones.filter { $0.valor != nil }.count
    func mediana(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.sorted()[a.count / 2] }
    print(String(format: "abrir en el hilo principal: 1.ª vez %.1f ms · mediana %.1f ms", tAbrir.first ?? 0, mediana(tAbrir)))
    print(String(format: "primer cuadro (diseño + dibujo): 1.ª vez %.1f ms · mediana %.1f ms", tCuadro.first ?? 0, mediana(tCuadro)))
    print(String(format: "imagen del fondo lista: 1.ª vez %.0f ms · mediana %.0f ms (lecturas: %d)", tImagen.first ?? 0, mediana(tImagen), lanzador.estado.fondoModelo.lecturas))
    print("ventanas creadas: \(ventanas.count) · siguen vivas: \(vivasV) · vistas de SwiftUI vivas: \(vivasA)")
    print("apps en el catálogo: \(lanzador.catalogo.apps.count) · píxeles dibujados: \(dibujados) · ventana suelta: \(!lanzador.ventanaViva)")
    return dibujados > 0 && !lanzador.ventanaViva && porCiclo < 1 && vivasV == 0 && vivasA == 0
}
