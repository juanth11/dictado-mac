import AppKit
import DictadoKit
import SwiftUI

// Renders de la isla de Aurora sin abrir ninguna ventana: `DICTADO_ESCENA=auroraInicio Dictado --vista-isla /tmp/inicio.png`.
// Escenas: auroraReposo, auroraInicio, auroraAgentes, auroraAgentesRemoto, auroraAgenda, auroraAgendaSemana, auroraAgendaMes, auroraAgendaNuevaLocal, auroraAgendaNuevaGoogle, auroraTareas,
// auroraTareasNotas, auroraMac y auroraTodas; auroraLargosInicio/Agentes/Agenda/Tareas son las mismas con textos larguísimos (nombres de apps, reuniones, canciones, tareas, agentes) para comprobar el truncado; (las cinco pestañas y el reposo, una sobre otra). De Inicio hay además:
// auroraAgentesTablero (dos decisiones, dos en marcha y tres terminadas, con un JSON inventado del Tablero), auroraAgentesSinTablero (el
// centro no responde: las sesiones de Claude vistas directo), auroraInicioTablero, auroraInicioCarpeta, auroraInicioSinMusica, auroraInicioAtajos, auroraInicioTrabajo, auroraInicioFoco, auroraInicioManana, auroraInicioDescanso y
// auroraInicioTodas (todas las de Inicio en una hoja). Usa ImageRenderer (nada se muestra en pantalla), datos inventados y una
// hora fija (lunes 16 de noviembre de 2026, 2:48 p. m.).

enum EscenaAurora: String, CaseIterable {
    case auroraReposo, auroraInicio, auroraAgentes, auroraAgentesTablero, auroraAgentesSinTablero, auroraAgentesPila, auroraInicioTablero, auroraAgentesRemoto, auroraAgenda, auroraAgendaSemana, auroraAgendaMes, auroraAgendaNuevaLocal, auroraAgendaNuevaGoogle, auroraTareas,
         auroraTareasNotas, auroraMac, auroraTodas,
         auroraInicioCarpeta, auroraInicioSinMusica, auroraInicioAtajos, auroraInicioTrabajo, auroraInicioFoco, auroraInicioManana, auroraInicioDescanso, auroraInicioEnFoco, auroraInicioEnFocoSinMusica, auroraInicioSalidas, auroraInicioTodas,
         auroraLargosInicio, auroraLargosAgentes, auroraLargosAgenda, auroraLargosTareas

    var pestana: EstadoIsla.Pestana? {
        switch self {
        case .auroraInicio, .auroraLargosInicio, .auroraInicioTablero, .auroraInicioCarpeta, .auroraInicioSinMusica, .auroraInicioAtajos, .auroraInicioTrabajo, .auroraInicioFoco, .auroraInicioManana,
             .auroraInicioDescanso, .auroraInicioEnFoco, .auroraInicioEnFocoSinMusica, .auroraInicioSalidas: return .inicio
        case .auroraAgentes, .auroraAgentesPila, .auroraLargosAgentes, .auroraAgentesTablero, .auroraAgentesSinTablero, .auroraAgentesRemoto: return .agentes
        case .auroraAgenda, .auroraLargosAgenda, .auroraAgendaSemana, .auroraAgendaMes, .auroraAgendaNuevaLocal, .auroraAgendaNuevaGoogle: return .agenda
        case .auroraTareas, .auroraLargosTareas, .auroraTareasNotas: return .tareas
        case .auroraMac: return .mac
        default: return nil
        }
    }
}

/// Un JSON inventado del Tablero (como lo imprime `python3 -m centro tablero --json`), con las horas relativas a `ahora`.
func tableroDeMuestra(ahora: Date, sesionViva: String) -> Tablero? {
    let iso = ISO8601DateFormatter()
    func hace(_ minutos: Double) -> String { iso.string(from: ahora.addingTimeInterval(-minutos * 60)) }
    let json = """
    {"version": 1, "generado": "\(hace(0))", "estado": "ok", "campo_futuro": {"x": 1},
     "conteos": {"trabajando": 2, "esperan_tu_si": 2, "terminaron_hoy": 1, "terminaron_anoche": 2},
     "decisiones": [
      {"id": 41, "encargo_id": 12, "corrida_id": 201, "pregunta": "¿Publico el memo de IVA a los clientes hoy?", "opciones": ["Publicar", "Esperar"],
       "respuesta": null, "creada": "\(hace(20))", "resuelta": null, "encargo_titulo": "Memo de IVA 2027"},
      {"id": 42, "encargo_id": 13, "corrida_id": null, "pregunta": "¿Uso la plantilla nueva del contrato marco?", "opciones": [],
       "respuesta": null, "creada": "\(hace(6))", "resuelta": null, "encargo_titulo": "Contrato marco con Nimbo"}],
     "en_curso": [
      {"id": 205, "encargo_id": null, "agente": "claude-code", "sesion": "\(sesionViva)", "proyecto": "Mi Proyecto", "titulo": "Sistema de finanzas asistido",
       "inicio": "\(hace(42))", "fin": null, "estado": "trabajando", "resumen": null, "enlace": null, "tokens_entrada": 4305136, "tokens_salida": 80261,
       "modelo": "claude-opus-5-5", "costo_usd": 0.4132, "clave": "claude-code:\(sesionViva)"},
      {"id": 211, "encargo_id": null, "agente": "claude-code", "sesion": "sin-sesion-viva", "proyecto": "dictado", "titulo": "Mejoras de la aplicación de dictado",
       "inicio": "\(hace(125))", "fin": null, "estado": "trabajando", "resumen": null, "enlace": null, "tokens_entrada": 101908476, "tokens_salida": 361481,
       "modelo": "modelo-nuevo", "costo_usd": null, "clave": "claude-code:sin-sesion-viva"}],
     "ultimas": [
      {"id": 191, "agente": "claude-code", "sesion": "x1", "proyecto": "Mi Proyecto", "titulo": "Compatibilidad del juego en PC", "inicio": "\(hace(400))", "fin": "\(hace(190))",
       "estado": "termino", "resumen": "Dejé la guía de ajustes y el perfil de gráficos listos para probar.", "enlace": "https://ejemplo.co/informe", "tokens_entrada": 60654368,
       "tokens_salida": 112825, "modelo": "claude-opus-5-5", "costo_usd": 20.0077},
      {"id": 192, "agente": "claude-code", "sesion": "x2", "proyecto": "g3", "titulo": "Prueba del servidor MCP en Orbita", "inicio": "\(hace(520))", "fin": "\(hace(500))",
       "estado": "fallo", "resumen": "El servidor no respondió a la tercera llamada.", "enlace": null, "costo_usd": 0.5},
      {"id": 193, "agente": "claude-code", "sesion": "x3", "proyecto": "Mi Proyecto", "titulo": "Sincronización del MacBook y Alexa", "inicio": "\(hace(640))", "fin": "\(hace(560))",
       "estado": "termino", "resumen": null, "enlace": null, "costo_usd": 9.3262}],
     "tareas": []}
    """
    return TableroCentro.decodificar(Data(json.utf8))
}

@MainActor
private func escenaAurora(_ tipo: EscenaAurora, notch: CGSize, fondo: NSImage) -> some View {
    FondoMusicaVacia.muestra = fondo.cgImage(forProposedRect: nil, context: nil, hints: nil)
    let cal = Calendar.current
    let lunes = cal.date(from: DateComponents(year: 2026, month: 11, day: 16)) ?? Date()
    func a(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: lunes) ?? lunes }
    let ahora = a(14, 48)
    let largos = [EscenaAurora.auroraLargosInicio, .auroraLargosAgentes, .auroraLargosAgenda, .auroraLargosTareas].contains(tipo)

    let estado = EstadoIsla()
    estado.notch = notch
    estado.pantallaAncho = 1440
    if let p = tipo.pestana {
        estado.expandida = true
        estado.pestana = p
    }

    // Música: la carátula es un recorte del fondo de muestra.
    let caratula = NSImage(size: NSSize(width: 300, height: 300))
    caratula.lockFocus()
    fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 600, y: 300, width: 900, height: 900), operation: .copy, fraction: 1)
    caratula.unlockFocus()
    let musica = Musica(vivo: false)
    if tipo != .auroraReposo && tipo != .auroraInicioSinMusica && tipo != .auroraInicioEnFocoSinMusica {
        musica.titulo = largos ? "Weightless (versión extendida para trabajar con concentración profunda)" : "Weightless"
        musica.artista = largos ? "Marconi Union con la Orquesta Sinfónica del Estudio Sur" : "Marconi Union"
        musica.duracion = 480
        musica.posicion = 96
        musica.sonando = false
        musica.caratula = caratula
        musica.acento = Musica.colorMedio(caratula)
        musica.origen = Musica.spotify
        musica.nombreOrigen = "Spotify"
        musica.puedeSaltar = true
    } else {
        musica.ultima = Musica.UltimaPista(titulo: "Weightless", artista: "Marconi Union", origen: Musica.spotify, nombreOrigen: "Spotify")
    }

    // Salidas de sonido de muestra (los renders no leen CoreAudio) y, en una escena, la lista abierta.
    let fuentes = Fuentes(vivo: false)
    fuentes.salidas = [.init(id: 1, nombre: "MacBook Pro Speakers", simbolo: "laptopcomputer"), .init(id: 2, nombre: largos ? "AirPods Pro de la oficina principal del piso doce" : "AirPods de Ana", simbolo: "airpodspro"),
                       .init(id: 3, nombre: "Pantalla LG UltraFine", simbolo: "display"), .init(id: 4, nombre: "HomePod de la sala", simbolo: "homepod.fill"),
                       .init(id: 5, nombre: "MacBook + Echo", simbolo: "hifispeaker.2.fill", multiple: true)]
    fuentes.salidaActual = 2
    fuentes.mostrandoSalidas = tipo == .auroraInicioSalidas
    // Un bloque de foco que va por la mitad (9 de 25 minutos), con la hora fija de la escena.
    let foco = Foco(vivo: false)
    if tipo == .auroraInicioEnFoco || tipo == .auroraInicioEnFocoSinMusica {
        foco.empezar("Memo de IVA 2027 para los clientes", minutos: 25, inicio: ahora.addingTimeInterval(-9.5 * 60))
    }

    // Agenda: la próxima reunión en 12 min, otra a las 5:30 y el hueco libre entre las dos.
    let agenda = Agenda(vivo: false)
    agenda.permitido = true
    let azul = Color(red: 0.35, green: 0.6, blue: 1.0), naranja = Color(red: 1.0, green: 0.55, blue: 0.3)
    let verde = Color(red: 0.45, green: 0.85, blue: 0.5), violeta = Color(red: 0.75, green: 0.45, blue: 1.0)
    var lista: [Agenda.Evento] = []
    func poner(_ id: String, _ titulo: String, _ inicio: Date, _ minutos: Int, _ color: Color, gente: [String] = [], meet: Bool = false) {
        var e = Agenda.Evento(id: id, titulo: titulo, inicio: inicio, fin: inicio.addingTimeInterval(Double(minutos) * 60), color: color,
                              enlace: meet ? URL(string: "https://meet.google.com/abc-defg-hij") : nil, personas: gente)
        e.invitados = gente
        if id == "1" { e.lugar = "Calle 10 #20-30, Bogotá" }
        lista.append(e)
    }
    poner("1", largos ? "Revisión integral del contrato marco de prestación de servicios con el cliente" : "Revisión de contrato", a(15), 60, azul, gente: ["Carla Díaz", "Pedro León", "Marta Ruiz", "Luis Prado"], meet: true)
    poner("2", largos ? "Cliente nuevo: alcance, cronograma, honorarios y condiciones de pago" : "Cliente nuevo", a(17, 30), 30, violeta, gente: ["Sofía Vega"], meet: true)
    poner("0", largos ? "Comité semanal de seguimiento de proyectos y decisiones pendientes" : "Comité semanal", a(9), 60, naranja, gente: ["Ana Gómez", "Diego Mora"])
    // El resto de la semana, para las barras.
    let patron: [[(Int, Int, String)]] = [[(10, 90, "Taller")], [(9, 60, "Auditoría"), (13, 60, "Seguimiento"), (16, 30, "Demo")],
                                        [(11, 120, "Planeación"), (15, 45, "Retro")], [(10, 60, "Cliente")]]
    for (i, dia) in patron.enumerated() {
        guard let base = cal.date(byAdding: .day, value: i + 1, to: lunes) else { continue }
        for (n, (h, m, t)) in dia.enumerated() {
            poner("d\(i)-\(n)", t, cal.date(bySettingHour: h, minute: 0, second: 0, of: base) ?? base, m, verde)
        }
    }
    agenda.eventos = lista.sorted { $0.inicio < $1.inicio }
    if tipo == .auroraAgendaSemana { agenda.vista = .semana }
    // Mes con festivos (los de Colombia, de la lista incorporada) y la reunión nueva por sus dos caminos.
    agenda.calendariosDeMuestra = [.init(id: "c1", titulo: "ana@ejemplo.co", cuenta: "Google", esGoogle: true),
                                   .init(id: "c2", titulo: "Personal", cuenta: "iCloud", esGoogle: false)]
    if tipo == .auroraAgendaMes {
        agenda.vista = .mes
        agenda.eventosMes = agenda.eventos
        agenda.mes = MesCalendario.primero(de: ahora)
        agenda.diaMes = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: lunes) ?? lunes)
        agenda.cargarMes(agenda.mes)
    }
    if tipo == .auroraAgendaNuevaLocal {
        agenda.borrador = NuevaReunion(titulo: "Revisión del acta", inicio: a(16, 30), duracionMin: 45, calendarioID: "c2", calendarioEsGoogle: false)
    }
    if tipo == .auroraAgendaNuevaGoogle {
        agenda.borrador = NuevaReunion(titulo: "Cliente nuevo: alcance", inicio: a(16, 30), duracionMin: 60, calendarioID: "c1", calendarioEsGoogle: true,
                                       invitadosTexto: "carla@ejemplo.co, pedro@ejemplo.co", conMeet: true)
    }

    // Sesiones de Claude y un agente remoto.
    let claude = SesionesClaude(vivo: false)
    var sesiones: [SesionesClaude.Sesion] = [
        .init(id: "a", pid: 1, nombre: largos ? "Contrato marco de prestación de servicios con anexos y cláusulas de exclusividad" : "Contrato marco", carpeta: "proyectos", estado: .esperando, espera: "Necesita tu permiso",
              desde: Date().addingTimeInterval(-8 * 60), contexto: 318_000, actividad: largos ? "Terminal · swift build -c release --product Dictado --configuration release --verbose" : "Terminal · swift build -c release"),
        .init(id: "b", pid: 2, nombre: "Memo de IVA", carpeta: "proyectos", estado: .trabajando, espera: "", desde: Date().addingTimeInterval(-12 * 60),
              contexto: 412_000, actividad: "Editando memo-iva.md"),
        .init(id: "c", pid: 3, nombre: "Correos pendientes", carpeta: "notas", estado: .lista, espera: "", desde: Date().addingTimeInterval(-25 * 60),
              contexto: 31_000, resumen: "Clasifiqué los 14 correos pendientes y dejé 3 borradores."),
    ]
    if tipo == .auroraAgentesRemoto { sesiones.removeLast() }
    if tipo == .auroraAgentesPila {
        sesiones.append(contentsOf: [
            .init(id: "d", pid: 4, nombre: "Revisión de cláusulas", carpeta: "proyectos", estado: .trabajando, espera: "", desde: Date().addingTimeInterval(-3 * 60 - 20),
                  contexto: 96_000, actividad: "Leyendo anexo-2.docx"),
            .init(id: "e", pid: 5, nombre: "Resumen semanal", carpeta: "notas", estado: .lista, espera: "", desde: Date().addingTimeInterval(-52 * 60),
                  contexto: 54_000, resumen: "Armé el resumen de la semana con 6 pendientes."),
            .init(id: "f", pid: 6, nombre: "Plantilla de propuesta", carpeta: "notas", estado: .lista, espera: "", desde: Date().addingTimeInterval(-3 * 3600),
                  contexto: 22_000, resumen: "Dejé la plantilla lista para revisar."),
        ])
    }
    if tipo == .auroraReposo { sesiones = [sesiones[1], .init(id: "d", pid: 4, nombre: "Informe", carpeta: "x", estado: .trabajando, espera: "", desde: Date())] }
    claude.sesiones = sesiones
    let agentes = tipo == .auroraAgentesRemoto ? ejemploAgentes(alerta: true) : AgentesRemotos(vivo: false)
    // El Tablero: con datos inventados en sus escenas; en `auroraAgentesSinTablero` el centro no responde (cae a las sesiones).
    let tablero: TableroIsla?
    switch tipo {
    case .auroraAgentesTablero, .auroraInicioTablero:
        tablero = TableroIsla(vivo: false)
        tablero?.fijar(tableroDeMuestra(ahora: ahora, sesionViva: "b"),
                       encargos: tipo == .auroraAgentesTablero ? [EncargoTablero(id: 50, titulo: "Preparar el borrador del acta del comité de noviembre")] : [], leido: ahora)
    case .auroraAgentesSinTablero:
        tablero = TableroIsla(vivo: false)
        tablero?.fijar(nil)
    default:
        tablero = nil
    }

    // Mac: calma salvo la temperatura.
    let salud = EstadoSalud()
    salud.cpu = 0.23
    salud.gpu = 0.35
    salud.memoriaTotal = 24 * 1.073741824e9
    salud.memoriaUsada = 14e9
    salud.presion = 1
    salud.discoLibre = 704e9
    salud.discoTotal = 994e9
    salud.termico = .fair
    func item(_ nombre: String, _ bytes: Int64) -> ItemLimpieza { ItemLimpieza(url: URL(fileURLWithPath: "/tmp/" + nombre), nombre: nombre, detalle: "", bytes: bytes) }
    salud.consumidores = [.init(id: "c", nombre: "Claude", explicacion: "", icono: nil, simbolo: "app", cpu: 0.19, memoria: 3.6e9, pid: 1, esApp: true)]
    salud.limpiables = [
        Limpiable(id: "uv", titulo: "Caché de uv", detalle: "", simbolo: "hammer", items: [item("uv", 23_000_000_000)], accion: .papelera, boton: "A la Papelera"),
        Limpiable(id: "modelos", titulo: "modelos sin uso", detalle: "", simbolo: "cube", items: [item("modelos", 11_000_000_000)], accion: .papelera, boton: "A la Papelera"),
        Limpiable(id: "deps", titulo: "dependencias dormidas", detalle: "", simbolo: "cube.box", items: [item("deps", 4_000_000_000)], accion: .papelera, boton: "A la Papelera"),
    ]

    // Tareas.
    let tareas = TareasIsla(pendientes: nil, vivo: false)
    let delCentro = tipo != .auroraTareasNotas
    tareas.fijar([
        TareaVista(id: "c1", rotulo: delCentro ? "Revisión de contrato · vence mañana" : "Revisión de contrato · viernes",
                   texto: largos ? "Enviar el poder firmado y autenticado a Carla Díaz y a todo el equipo jurídico del cliente antes del martes" : "Enviar el poder firmado a Carla", cita: delCentro ? "Quedas tú de mandarle el poder a Carla antes del martes." : "al terminar la llamada con Carla",
                   origen: .centro(1)),
        TareaVista(id: "c2", rotulo: largos ? "Cliente nuevo: alcance, cronograma y honorarios · ayer" : "Cliente nuevo · ayer", texto: "Revisar la cláusula de exclusividad",
                   cita: delCentro ? "Eso lo revisa Ana y nos dice el jueves si se puede." : nil, origen: .centro(2)),
        TareaVista(id: "c3", rotulo: "Seguimiento · viernes", texto: "Agendar la demo con el equipo", cita: delCentro ? "Agéndala tú para la semana que viene." : nil,
                   origen: .centro(3)),
    ], hechas: 2, delCentro: delCentro)

    // Apps y lanzador: las de macOS que siempre están, repartidas en carpetas inventadas.
    let apps = AppsUsadas(vivo: false)
    var catalogo: [EntradaApp] = []
    var iconos: [String: NSImage] = [:]
    func instalada(_ id: String) -> EntradaApp? {
        if let e = catalogo.first(where: { $0.bundleID == id }) { return e }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let e = EntradaApp(nombre: largos ? url.deletingPathExtension().lastPathComponent + " para documentos y presentaciones" : url.deletingPathExtension().lastPathComponent, ruta: url.path, bundleID: id)
        catalogo.append(e)
        iconos[e.id] = CatalogoApps.icono(url.path)
        return e
    }
    let masUsadas = ["com.apple.finder", "com.apple.Safari", "com.apple.Photos", "com.apple.Maps", "com.apple.podcasts"].compactMap(instalada)
    let ids = [
        ("Trabajo", ["com.apple.Notes", "com.apple.iCal", "com.apple.reminders", "com.apple.Preview", "com.apple.TextEdit", "com.apple.iBooksX"]),
        (largos ? "Comunicación con clientes y colegas" : "Comunicación", ["com.apple.mail", "com.apple.MobileSMS", "com.apple.FaceTime"]),
        ("Desarrollo", ["com.apple.Terminal", "com.apple.ScriptEditor2", "com.apple.dt.Xcode"]),
        ("Juegos", ["com.apple.Chess", "com.apple.Stocks"]),
        ("Sistema", ["com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.DiskUtility", "com.apple.calculator", "com.apple.Console", "com.apple.AppStore"]),
    ]
    let carpetas = ids.map { CarpetaApps(nombre: $0.0, apps: $0.1.compactMap(instalada).compactMap(\.bundleID)) }
    apps.fijar(masUsadas, iconos: iconos)
    apps.fijar(catalogo: catalogo, categorias: [:])
    let lanzador = LanzadorIsla(vivo: false)
    let atajos = ["Modo concentración", "Escribir a casa", "Reunión en 5", "Apagar las luces", "Música para trabajar", "Resumen del día", "Guardar pantalla"]
    let espacioPorEscena: [EscenaAurora: String] = [.auroraInicioTrabajo: "Trabajo", .auroraInicioFoco: "Foco", .auroraInicioManana: "Mañana",
                                                    .auroraInicioDescanso: "Descanso"]
    lanzador.fijar(carpetas: carpetas, espacios: EspaciosIsla.leer(EspaciosIsla.inicial), espacio: espacioPorEscena[tipo],
                   atajos: atajos,
                   estados: tipo == .auroraInicioAtajos ? ["Escribir a casa": .listo, "Reunión en 5": .fallo("No se encontró la app «Zoom»"),
                                                           "Apagar las luces": .corriendo] : [:],
                   seccion: tipo == .auroraInicioAtajos ? .atajos : .apps, carpetaAbierta: tipo == .auroraInicioCarpeta ? "Trabajo" : nil)

    let privacidad = Privacidad(vivo: false)
    let hud = EstadoHUD()
    let alto: CGFloat = tipo == .auroraReposo ? 70 : 300
    let ancho: CGFloat = 1100
    return ZStack(alignment: .top) {
        Image(nsImage: fondo).resizable().scaledToFill().frame(width: ancho, height: alto, alignment: .top).clipped()
        Rectangle().fill(.white.opacity(0.18)).frame(height: 32)
        if tipo == .auroraReposo { UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: notch.width, height: notch.height) }
        VistaIsla(estado: estado, musica: musica, agenda: agenda, hud: hud, privacidad: privacidad, claude: claude, agentes: agentes, salud: salud,
                  control: nil, fuentes: fuentes, foco: foco,
                  notas: NotasReunion(agenda: agenda, privacidad: privacidad, vivo: false), pendientes: nil, tareas: tareas, apps: apps, lanzador: lanzador,
                  tablero: tablero, ahoraFijo: ahora)
            .frame(width: ancho)
            .frame(height: alto, alignment: .top)
    }
    .frame(width: ancho, height: alto)
    .clipShape(RoundedRectangle(cornerRadius: 14))
}

/// `DICTADO_ESCENA=auroraInicio Dictado --vista-isla salida.png`. Devuelve nil si la escena no es de Aurora.
@MainActor
func hojaIslaAurora(_ destino: URL, escena nombre: String) -> Bool? {
    guard let tipo = EscenaAurora(rawValue: nombre) else { return nil }
    let entorno = ProcessInfo.processInfo.environment
    let medidas = (entorno["DICTADO_NOTCH"] ?? "").split(separator: "x").compactMap { Double($0) }
    let notch = medidas.count == 2 ? CGSize(width: medidas[0], height: medidas[1]) : CGSize(width: 186, height: 32)
    let fondo = fondoDeMuestra()
    let hoja: AnyView
    if tipo == .auroraTodas {
        hoja = AnyView(VStack(spacing: 14) {
            ForEach([EscenaAurora.auroraReposo, .auroraInicio, .auroraAgentes, .auroraAgenda, .auroraTareas, .auroraMac], id: \.rawValue) { t in
                escenaAurora(t, notch: notch, fondo: fondo)
            }
        }
        .padding(14)
        .background(Color(white: 0.08)))
    } else if tipo == .auroraInicioTodas {
        hoja = AnyView(VStack(spacing: 14) {
            ForEach([EscenaAurora.auroraInicio, .auroraInicioSinMusica, .auroraInicioSalidas, .auroraInicioEnFoco, .auroraInicioEnFocoSinMusica, .auroraInicioCarpeta,
                     .auroraInicioAtajos, .auroraInicioTrabajo, .auroraInicioFoco, .auroraInicioManana, .auroraInicioDescanso], id: \.rawValue) { t in escenaAurora(t, notch: notch, fondo: fondo) }
        }
        .padding(14)
        .background(Color(white: 0.08)))
    } else {
        hoja = AnyView(escenaAurora(tipo, notch: notch, fondo: fondo))
    }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = tipo == .auroraInicioTodas || tipo == .auroraTodas ? 1 : 2
    guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
