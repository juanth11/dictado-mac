import AppKit
import DictadoKit
import SwiftUI

// Renders y prueba de memoria del Centro nuevo, sin abrir ninguna ventana a la vista ni tocar tus datos:
//   DICTADO_ESCENA=centroTablero Dictado --vista-centro /tmp/aurora5/tablero.png
//   Dictado --vista-centro /tmp/aurora5/centro.png        (sin escena: las cinco, en /tmp/aurora5/centro-<escena>.png)
//   Dictado --probar-centro-memoria [N]                   arma y suelta la ventana real SIN mostrarla N veces y mide la memoria
// Escenas: centroHoy, centroHoySin, centroTablero, centroSemana, centroSemanaProxima, centroReuniones, centroMac, centroTableroSin, centroConsumo, centroHerramientas,
// centroFinanzas, centroNoticias, centroAutomatizaciones, centroConsumoSin y centroNoticiasSin (con DICTADO_CENTRO_DATOS=<carpeta>, las nuevas usan tus datos reales) (el Tablero no está
// configurado: se ven las sesiones de Claude vistas directo). Usa ImageRenderer a 1512 × 982, datos inventados y una hora fija
// (lunes 16 de noviembre de 2026, 2:48 p. m.).

enum EscenaCentroAurora: String, CaseIterable {
    case centroTablero, centroSemana, centroSemanaProxima, centroMes, centroReuniones, centroMac, centroTableroSin
    case centroConsumo, centroHerramientas, centroFinanzas, centroNoticias, centroAutomatizaciones, centroConsumoSin, centroNoticiasSin
    case centroHoy, centroHoySin

    var seccion: SeccionAurora {
        switch self {
        case .centroHoy, .centroHoySin: return .hoy
        case .centroTablero, .centroTableroSin: return .tablero
        case .centroSemana, .centroSemanaProxima, .centroMes: return .semana
        case .centroReuniones: return .reuniones
        case .centroMac: return .mac
        case .centroConsumo, .centroConsumoSin: return .consumo
        case .centroHerramientas: return .herramientas
        case .centroFinanzas: return .finanzas
        case .centroNoticias, .centroNoticiasSin: return .noticias
        case .centroAutomatizaciones: return .automatizaciones
        }
    }
}

/// La mañana de la muestra de Hoy: lunes 16 de noviembre de 2026, 8:52 a. m.
let ahoraHoyDeMuestra: Date = {
    let c = Calendar.current
    let lunes = c.date(from: DateComponents(year: 2026, month: 11, day: 16)) ?? Date()
    return c.date(bySettingHour: 8, minute: 52, second: 0, of: lunes) ?? lunes
}()

let ahoraCentroDeMuestra: Date = {
    let c = Calendar.current
    let lunes = c.date(from: DateComponents(year: 2026, month: 11, day: 16)) ?? Date()
    return c.date(bySettingHour: 14, minute: 48, second: 0, of: lunes) ?? lunes
}()

// MARK: - Notas inventadas

private let notaComite = """
---
date: 2026-11-16T11:30-05:00
source: dictado-notas
tipo: reunion
reunion: Comité de revisión del contrato marco
inicio: 2026-11-16T10:30
modelo: modelo-de-prueba
transcripcion: /tmp/inventada-1.txt
---

# Notas · Comité de revisión del contrato marco

El comité aprobó la nueva cláusula de confidencialidad y fijó el viernes como fecha límite para el anexo técnico. Falta que el cliente confirme las fechas de entrega y que el área financiera valide el presupuesto.

Quedó pendiente decidir si la plantilla nueva reemplaza a la anterior en los contratos que ya están firmados.

## Decisiones

- Se usa la plantilla nueva en todos los contratos desde diciembre
- El anexo técnico sale el viernes con la firma de ambas partes

## Pendientes

- [ ] Tú · enviar el anexo técnico firmado a Carla · viernes · si: al terminar la revisión de la cláusula · (Contrato marco)
  > «yo envío el anexo técnico firmado el viernes a primera hora»
- [ ] Tú · confirmar las fechas de entrega con el cliente · jueves
  > «las fechas de entrega las confirmo yo con el cliente antes del jueves»
- [ ] Tú · revisar el presupuesto con finanzas
  > «el presupuesto lo reviso con finanzas esta semana»
- [ ] Marta · preparar el acta del comité · martes

## Descartado

- Pedro · mandar la presentación del comité
- Tú · mirar lo de la plantilla (vago)
- Tú · llamar a la notaría (sin cita verificable en la transcripción)

## Correo de seguimiento (borrador)

```text
Estimado/a Carla,

Gracias por la reunión de hoy. Quedamos en que el anexo técnico firmado llega el viernes a primera hora.
Para cerrar las fechas de entrega necesito su confirmación antes del jueves.
Quedo atento a sus comentarios sobre la plantilla nueva.
```

## Para la bitácora (wiki/reuniones.md)

- 2026-11-16 · Carla · Contrato marco · cláusula aprobada, anexo el viernes

## Transcripción

Completa en el Mac, fuera del cerebro.
"""

private let notaMeet = """
---
date: 2026-11-13T16:00-05:00
source: meet-notas
tipo: reunion
reunion: Planeación del trimestre con el equipo de producto
inicio: 2026-11-13T15:00
modelo: modelo-de-prueba
---

# Notas · Planeación del trimestre con el equipo de producto

Se repasaron las tres apuestas del trimestre y se acordó empezar por el flujo de incorporación. El equipo propone medir la activación semanal como indicador principal.

## Decisiones

- La activación semanal es el indicador principal del trimestre

## Pendientes

- [ ] Tú · definir el criterio de éxito de la primera apuesta · lunes
  > «el criterio de éxito de la primera apuesta lo defino yo el lunes»

## Descartado

- Lucía · armar el tablero de métricas
"""

private let notaSimple = """
---
date: 2026-11-12T09:15-05:00
source: dictado-notas
tipo: reunion
reunion: Llamada rápida con el proveedor de hosting
inicio: 2026-11-12T09:00
modelo: modelo-de-prueba
---

# Notas · Llamada rápida con el proveedor de hosting

El proveedor confirmó la ventana de mantenimiento del sábado y ofreció un descuento si se contrata el plan anual.
"""

private let notaCierre = """
---
date: 2026-11-10T17:20-05:00
source: meet-notas
tipo: reunion
reunion: Revisión del informe tributario con el cliente
inicio: 2026-11-10T16:00
modelo: modelo-de-prueba
---

# Notas · Revisión del informe tributario con el cliente

Se revisó el informe borrador. El cliente pidió ampliar la sección de riesgos y adjuntar el soporte de las cifras de octubre.

## Pendientes

- [ ] Tú · ampliar la sección de riesgos del informe · miércoles
  > «amplío la sección de riesgos y se la mando el miércoles»
- [ ] Tú · adjuntar el soporte de las cifras de octubre · miércoles · si: al recibir los extractos
  > «adjunto el soporte en cuanto lleguen los extractos»

## Correo de seguimiento (borrador)

```text
Estimado/a cliente,

Quedo atento a los extractos para adjuntar el soporte de octubre. El informe con la sección de riesgos ampliada llega el miércoles.
```
"""

func actasDeMuestra() -> [ActaReunion] {
    [("reunion-comite-contrato-marco-202611161130.md", notaComite), ("reunion-planeacion-trimestre-202611131600.md", notaMeet),
     ("reunion-llamada-hosting-202611120915.md", notaSimple), ("reunion-informe-tributario-202611101720.md", notaCierre)]
        .compactMap { LectorActa.interpretar($0.1, archivo: $0.0) }
}

// MARK: - Corridas del historial

/// Unas treinta corridas en siete días, con las del Tablero de muestra de hoy (`tableroDeMuestra`).
@MainActor
func corridasDeMuestra(ahora: Date, tablero: Tablero?) -> [CorridaTablero] {
    let cal = Calendar.current
    func dia(_ atras: Int, _ h: Int, _ m: Int = 0) -> Date {
        let base = cal.date(byAdding: .day, value: -atras, to: cal.startOfDay(for: ahora)) ?? ahora
        return cal.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
    }
    var lista: [CorridaTablero] = []
    var id = 300
    func nueva(_ titulo: String, _ proyecto: String, _ atras: Int, _ h1: Int, _ m1: Int, _ minutos: Int, tokens: Int?, costo: Double?, estado: CorridaTablero.Estado = .termino,
               resumen: String? = nil) {
        id += 1
        let inicio = dia(atras, h1, m1)
        lista.append(CorridaTablero(id: id, proyecto: proyecto, titulo: titulo, inicio: inicio, fin: inicio.addingTimeInterval(Double(minutos) * 60), estado: estado,
                                    resumen: resumen, tokensEntrada: tokens, tokensSalida: tokens.map { $0 / 400 }, costoUSD: costo))
    }
    // Hoy: las de la muestra del Tablero (en curso y terminadas) más dos del día.
    if let t = tablero { lista += t.enCurso + t.ultimas }
    nueva("Resumen de la jurisprudencia del trimestre", "Investigación", 0, 8, 5, 34, tokens: 8_400_000, costo: 3.12)
    nueva("Borrador del memo de IVA", "Mi Proyecto", 0, 9, 20, 55, tokens: 14_200_000, costo: 5.8)
    // Ayer.
    nueva("Sincronización de las notas de reunión", "Mi Proyecto", 1, 8, 10, 25, tokens: 5_100_000, costo: 1.9)
    nueva("Revisión de la plantilla de contratos", "Lumina", 1, 10, 0, 85, tokens: 31_000_000, costo: 11.4)
    nueva("Corrección del calendario de pagos", "Finanzas", 1, 13, 30, 40, tokens: 9_700_000, costo: 3.6)
    nueva("Prueba del servidor de datos", "g3", 1, 16, 0, 12, tokens: 900_000, costo: 0.35, estado: .fallo, resumen: "El servidor no respondió a la tercera llamada.")
    nueva("Informe de métricas semanales", "Mi Proyecto", 1, 17, 10, 48, tokens: 12_600_000, costo: 4.7)
    // Hace dos a siete días.
    nueva("Migración de la base de tareas", "Mi Proyecto", 2, 9, 0, 120, tokens: 52_000_000, costo: 19.2)
    nueva("Auditoría de los permisos de las carpetas", "Mi Proyecto", 2, 14, 0, 30, tokens: 6_000_000, costo: 2.2)
    nueva("Guía de instalación del Dock", "dictado", 3, 10, 30, 95, tokens: 27_000_000, costo: 9.9)
    nueva("Ajustes del lanzador de apps", "dictado", 3, 15, 0, 70, tokens: 20_000_000, costo: 7.3)
    nueva("Investigación de tarifas de la API", "Investigación", 4, 11, 0, 50, tokens: 11_000_000, costo: 4.1)
    nueva("Plan de la semana", "Mi Proyecto", 5, 8, 30, 20, tokens: 3_000_000, costo: 1.1)
    nueva("Revisión de correos pendientes", "Lumina", 5, 12, 0, 45, tokens: 8_000_000, costo: 3.0)
    nueva("Depuración del indexador de sesiones", "Mi Proyecto", 6, 10, 0, 140, tokens: 61_000_000, costo: 22.6)
    nueva("Notas del curso de derecho tributario", "Tesis", 6, 16, 0, 60, tokens: 14_500_000, costo: 5.4)
    return lista
}

// MARK: - Datos de muestra

/// Todo lo que el Centro lee, inventado: nada se consulta ni se escribe.
@MainActor
func datosCentroDeMuestra(_ escena: EscenaCentroAurora = .centroTablero, ahora ahoraBase: Date = ahoraCentroDeMuestra) -> DatosCentro {
    // Hoy es la vista de la mañana: ese día, a las 8:52 (la reunión de las 9:00 ya deja unirse).
    let esHoy = escena == .centroHoy || escena == .centroHoySin
    let ahora = esHoy ? ahoraHoyDeMuestra : ahoraBase
    let cal = Calendar.current
    func en(_ dia: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(from: DateComponents(year: 2026, month: 11, day: dia)) ?? ahora) ?? ahora
    }
    // Agenda: la semana del 16 y la que viene (con dos eventos que se encimen el martes y uno que ya pasó el lunes).
    let agenda = Agenda(vivo: false)
    agenda.permitido = escena != .centroHoySin
    var n = 0
    func ev(_ titulo: String, _ dia: Int, _ h1: Int, _ m1: Int = 0, _ h2: Int, _ m2: Int = 0, enlace: Bool = false, personas: [String] = []) -> Agenda.Evento {
        n += 1
        var e = Agenda.Evento(id: "e\(n)", titulo: titulo, inicio: en(dia, h1, m1), fin: en(dia, h2, m2), color: .blue,
                              enlace: enlace ? URL(string: "https://meet.google.com/abc-defg-hij") : nil, personas: personas)
        e.invitados = personas
        return e
    }
    agenda.pasadosDeLaSemana = [ev("Seguimiento diario", 16, 8, 30, 9), ev("Mentoría", 16, 10, 0, 11, 15, personas: ["Elena"])]
    agenda.eventos = [
        ev("Revisión de contrato", 16, 15, 0, 16, 0, enlace: true, personas: ["Carla", "Pedro", "Marta"]), ev("Cliente nuevo", 16, 17, 30, 18),
        ev("Comité semanal", 17, 9, 0, 10, 30, enlace: true, personas: ["Lucía", "Marcos"]), ev("Llamada con proveedor", 17, 10, 0, 11), ev("Almuerzo", 17, 12, 30, 13, 30),
        ev("Taller de producto", 18, 9, 0, 12, 0, personas: ["Elena", "Marcos", "Lucía", "Pedro"]), ev("Cierre de mes", 18, 15, 0, 16, 30),
        ev("Entrevista", 19, 8, 30, 9, 30, enlace: true, personas: ["Ana"]), ev("Demostración", 19, 14, 0, 15, 0, enlace: true, personas: ["Carla", "Marta"]),
        ev("Planeación", 20, 10, 0, 11, 30), ev("Revisión final", 20, 16, 0, 17, 0),
        ev("Reunión trimestral", 23, 9, 0, 11, 0, enlace: true, personas: ["Elena", "Marcos", "Pedro"]), ev("Seguimiento con el cliente", 23, 14, 0, 15, 0),
        ev("Comité semanal", 24, 9, 0, 10, 30, enlace: true, personas: ["Lucía", "Marcos"]), ev("Taller de tributaria", 25, 10, 0, 12, 30),
        ev("Revisión de pagos", 26, 11, 0, 12), ev("Cena de equipo", 26, 19, 0, 21),
    ]
    var festivo = Agenda.Evento(id: "f1", titulo: "Festivo", inicio: en(19, 0), fin: en(20, 0), color: .red)
    festivo.todoElDia = true
    agenda.todoElDia = [festivo]
    if esHoy {
        agenda.eventos.append(ev("Llamada de equipo", 16, 9, 0, 9, 30, enlace: true, personas: ["Carla", "Pedro", "Marta"]))
        agenda.eventos.append(ev("Almuerzo con proveedor", 16, 12, 30, 13, 30, personas: ["Elena"]))
        agenda.eventos[agenda.eventos.count - 1].lugar = "Restaurante Central"
        agenda.eventos.sort { $0.inicio < $1.inicio }
        if escena == .centroHoySin { agenda.eventos = []; agenda.pasadosDeLaSemana = []; agenda.todoElDia = [] }
    }

    // Tablero, sesiones y tareas.
    let tablero = TableroIsla(vivo: false)
    let tableroMuestra = escena == .centroTableroSin ? nil : tableroDeMuestra(ahora: ahora, sesionViva: "b")
    tablero.fijar(tableroMuestra, leido: ahora)
    let claude = SesionesClaude(vivo: false)
    let hace = ahora.addingTimeInterval(-6 * 60)
    claude.sesiones = escena == .centroTableroSin
        ? [.init(id: "a", pid: 1, nombre: "Contrato marco", carpeta: "proyectos", estado: .esperando, espera: "Necesita tu permiso", desde: hace, actividad: "Bash · swift build"),
           .init(id: "b", pid: 2, nombre: "Memo de IVA 2027", carpeta: "proyectos", estado: .trabajando, espera: "", desde: ahora.addingTimeInterval(-42 * 60), actividad: "Editando memo.md"),
           .init(id: "c", pid: 3, nombre: "Sistema de finanzas asistido", carpeta: "notas", estado: .trabajando, espera: "", desde: ahora.addingTimeInterval(-125 * 60), actividad: "Leyendo recibos.py"),
           .init(id: "d", pid: 4, nombre: "Informe trimestral", carpeta: "x", estado: .lista, espera: "", desde: ahora.addingTimeInterval(-200 * 60), resumen: "Dejé el informe listo para revisión y el resumen en la carpeta de salidas.")]
        : [.init(id: "a", pid: 1, nombre: "Contrato marco con el cliente", carpeta: "proyectos", estado: .esperando, espera: "Necesita tu permiso", desde: hace, actividad: "Bash · swift build")]
    claude.tokensHoy = 412_000
    let tareas = TareasIsla(pendientes: nil, vivo: false)
    tareas.fijar([
        TareaVista(id: "c1", rotulo: "", texto: "Enviar el poder firmado", cita: nil, origen: .centro(1)),
        TareaVista(id: "c2", rotulo: "", texto: "Pagar la renovación del dominio", cita: nil, origen: .centro(2)),
        TareaVista(id: "c3", rotulo: "", texto: "Revisar la cláusula de exclusividad", cita: nil, origen: .centro(3)),
        TareaVista(id: "c4", rotulo: "", texto: "Agendar la demostración con el equipo", cita: nil, origen: .centro(4)),
        TareaVista(id: "c5", rotulo: "", texto: "Preparar el informe del comité", cita: nil, origen: .centro(5)),
        TareaVista(id: "c6", rotulo: "", texto: "Llamar al contador", cita: nil, origen: .centro(6)),
        TareaVista(id: "c7", rotulo: "", texto: "Ordenar los recibos de octubre", cita: nil, origen: .centro(7)),
        TareaVista(id: "c8", rotulo: "", texto: "Leer el borrador de la tesis", cita: nil, origen: .centro(8)),
    ], hechas: 2, delCentro: true,
    vencimientos: ["c1": "2026-11-16", "c2": "2026-11-12", "c3": "2026-11-17", "c4": "2026-11-19", "c5": "2026-11-19", "c6": "2026-11-23"])

    // Salud.
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
    salud.consumidores = [
        .init(id: "1", nombre: "Claude", explicacion: "", icono: nil, simbolo: "sparkle", cpu: 0.19, memoria: 3.6e9, pid: 1, esApp: true),
        .init(id: "2", nombre: "Navegador", explicacion: "", icono: nil, simbolo: "safari", cpu: 0.08, memoria: 3.1e9, pid: 2, esApp: true),
        .init(id: "3", nombre: "Xcode", explicacion: "", icono: nil, simbolo: "hammer", cpu: 0.04, memoria: 2.4e9, pid: 3, esApp: true),
        .init(id: "4", nombre: "Calendario", explicacion: "", icono: nil, simbolo: "calendar", cpu: 0.01, memoria: 0.9e9, pid: 4, esApp: true),
        .init(id: "5", nombre: "Servicios del sistema", explicacion: "", icono: nil, simbolo: "gearshape", cpu: 0.06, memoria: 0.8e9, pid: 5, esApp: false),
        .init(id: "6", nombre: "Dictado", explicacion: "", icono: nil, simbolo: "mic", cpu: 0.02, memoria: 0.3e9, pid: 6, esApp: true),
    ]
    salud.limpiables = [
        Limpiable(id: "uv", titulo: "Caché de uv", detalle: "", simbolo: "hammer", items: [item("uv", 23_000_000_000)], accion: .papelera, boton: "A la Papelera"),
        Limpiable(id: "modelos", titulo: "modelos sin uso", detalle: "", simbolo: "cube", items: [item("modelos", 11_000_000_000)], accion: .papelera, boton: "A la Papelera"),
        Limpiable(id: "deps", titulo: "dependencias dormidas", detalle: "", simbolo: "cube.box", items: [item("deps", 4_000_000_000)], accion: .papelera, boton: "A la Papelera"),
    ]

    let historial = HistorialTableroModelo(vivo: false)
    historial.fijar(escena == .centroTableroSin ? nil : corridasDeMuestra(ahora: ahora, tablero: tableroMuestra), leido: ahora)
    let reuniones = ReunionesModelo(carpeta: nil, vivo: false)
    reuniones.fijar(actasDeMuestra())
    // Las secciones nuevas: datos inventados, o los reales de `DICTADO_CENTRO_DATOS`.
    let lecturas = LecturasCentro(vivo: false)
    lecturas.consumo.fijar(escena == .centroConsumoSin ? DatosNuevasDeMuestra.consumoSin() : DatosNuevasDeMuestra.consumo(ahora: ahora), leido: ahora)
    lecturas.herramientas.fijar(DatosNuevasDeMuestra.herramientas(ahora: ahora), leido: ahora)
    lecturas.finanzas.fijar(DatosNuevasDeMuestra.finanzas(ahora: ahora), leido: ahora)
    lecturas.noticias.fijar(escena == .centroNoticiasSin ? DatosNuevasDeMuestra.noticiasSin() : DatosNuevasDeMuestra.noticias(ahora: ahora), leido: ahora)
    lecturas.automatizaciones.fijar(DatosNuevasDeMuestra.automatizaciones(ahora: ahora), leido: ahora)
    let datos = DatosCentro(agenda: agenda, claude: claude, tablero: tablero, tareas: tareas, salud: salud, historial: historial, reuniones: reuniones,
                            lecturas: lecturas, hoy: CentroStore(cargarCache: false), config: ConfigHuecos(), espacio: { "Trabajo" })
    datos.reloj.ahora = ahora
    datos.hoy.estado = DatosHoyDeMuestra.estado(escena == .centroHoySin ? .sin : .completo)
    datos.focoHechas = { ["Enviar el poder firmado"] }
    return datos
}

// MARK: - Renders

/// El fondo de los renders del Centro: la imagen de `DICTADO_FONDO` (ruta) o, si falta, el fondo de pantalla actual del Mac; nunca los ajustes
/// del dueño. Sin imagen legible queda el plano del tema, como en la app.
@MainActor
func escritorioDeRender(ancho: CGFloat = 1512) -> FondoEscritorio {
    let suite = "app.dictado.prueba.centro"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    let e = FondoEscritorio(defaults: defaults)
    let actual = NSScreen.screens.first.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path }
    if let ruta = ProcessInfo.processInfo.environment["DICTADO_FONDO"] ?? actual, let leida = leerFondoParaRender(ruta, ancho: ancho) {
        e.modelo.fijar(imagen: leida.imagen, luminancia: leida.luminancia)
    }
    return e
}

@MainActor
private func vistaDeEscena(_ escena: EscenaCentroAurora) -> some View {
    let datos = datosCentroDeMuestra(escena)
    let nav = NavegacionAurora()
    nav.seccion = escena.seccion
    if escena == .centroSemanaProxima { nav.semana = 1 }
    if escena == .centroMes {
        nav.semana = 2
        let a = datos.agenda
        a.eventosMes = a.pasadosDeLaSemana + a.eventos
        a.mes = MesCalendario.primero(de: datos.reloj.ahora)
        a.diaMes = Calendar.current.startOfDay(for: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17)) ?? datos.reloj.ahora)
        a.cargarMes(a.mes)
    }
    return RaizCentroAurora(datos: datos, nav: nav, escritorio: escritorioDeRender(), paleta: .lagunaDurazno, simulado: true, margenes: EdgeInsets(), acciones: AccionesCentroAurora())
        .frame(width: 1512, height: 982)
        .environment(\.vidrioSimulado, true)
}

/// `Dictado --vista-centro salida.png [escena]` (o `DICTADO_ESCENA=centroSemana`). Sin escena, las cinco, una por archivo.
@MainActor
func hojaCentro(_ destino: URL, escena: String?) -> Bool {
    _ = NSApplication.shared
    let nombre = escena ?? ProcessInfo.processInfo.environment["DICTADO_ESCENA"]
    let escenas: [EscenaCentroAurora]
    if let nombre {
        guard let e = EscenaCentroAurora(rawValue: nombre) else { print("escena desconocida: \(nombre)"); return false }
        escenas = [e]
    } else {
        escenas = [.centroHoy, .centroHoySin, .centroTablero, .centroSemana, .centroReuniones, .centroMac, .centroTableroSin, .centroConsumo, .centroHerramientas, .centroFinanzas, .centroNoticias,
                   .centroAutomatizaciones, .centroConsumoSin, .centroNoticiasSin]
    }
    try? FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
    var todoBien = true
    for e in escenas {
        let r = ImageRenderer(content: vistaDeEscena(e))
        r.scale = 1
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            todoBien = false
            continue
        }
        let archivo = nombre == nil ? URL(fileURLWithPath: destino.deletingPathExtension().path + "-\(e.rawValue.replacingOccurrences(of: "centro", with: "").lowercased()).png") : destino
        todoBien = ((try? png.write(to: archivo)) != nil) && todoBien
        print(archivo.path)
    }
    return todoBien
}

// MARK: - Prueba de memoria (sin ventana a la vista)

private final class CajaDebil<T: AnyObject> {
    weak var valor: T?
    init(_ valor: T) { self.valor = valor }
}

private func huellaCentroMB() -> Double {
    var info = task_vm_info_data_t()
    var cuenta = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &cuenta) }
    }
    return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// `Dictado --probar-centro-memoria [N]`: arma y suelta N veces (30 por omisión) la ventana REAL del Centro con sus cuatro secciones, sin
/// ordenarla nunca al frente ni activar la app: no hay nada en pantalla ni sonido. Dibuja cada sección y cierra con la misma ruta de
/// `cerrar`. Imprime la huella de memoria en frío, tras el calentamiento y al final, y quién sigue vivo.
@MainActor
func probarCentroMemoria(ciclos: Int = 30) -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    func esperar(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    let centro = Centro(claude: nil, vidrioSimulado: true, datosDePrueba: { datosCentroDeMuestra() })
    var dibujados = 0
    var ventanas: [CajaDebil<NSWindow>] = []
    var anfitriones: [CajaDebil<NSView>] = []
    var datosVivos: [CajaDebil<DatosCentro>] = []
    func ciclo() {
        autoreleasepool {
            centro.abrirSinMostrar()
            if let v = centro.ventanaActual { ventanas.append(CajaDebil(v)); if let c = v.contentView { anfitriones.append(CajaDebil(c)) } }
            if let d = centro.datosActuales { datosVivos.append(CajaDebil(d)) }
            for s in SeccionAurora.allCases {
                centro.navegacionDePrueba?.seccion = s
                esperar(0.05)
                if let v = centro.vistaDelContenido {
                    v.frame = NSRect(x: 0, y: 0, width: 1512, height: 982)
                    v.layoutSubtreeIfNeeded()
                    if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        dibujados += rep.pixelsWide * rep.pixelsHigh
                    }
                }
            }
            centro.cerrar(devolver: false)
            esperar(0.05)
        }
    }

    let frio = huellaCentroMB()
    for _ in 0..<3 { ciclo() }
    esperar(1)
    let antes = huellaCentroMB()
    for _ in 0..<ciclos { ciclo() }
    esperar(1)
    let despues = huellaCentroMB()
    let porCiclo = (despues - antes) / Double(max(1, ciclos))
    print("memoria (MB)          huella")
    print(String(format: "en frío               %6.1f", frio))
    print(String(format: "tras 3 ciclos         %6.1f", antes))
    print(String(format: "tras %d más           %6.1f", ciclos, despues))
    print(String(format: "diferencia            %+6.1f  (%.2f MB por ciclo)", despues - antes, porCiclo))
    let vivasV = ventanas.filter { $0.valor != nil }.count, vivasA = anfitriones.filter { $0.valor != nil }.count, vivosD = datosVivos.filter { $0.valor != nil }.count
    print("ventanas creadas: \(ventanas.count) · siguen vivas: \(vivasV) · vistas de SwiftUI vivas: \(vivasA) · datos vivos: \(vivosD)")
    print("píxeles dibujados: \(dibujados) · ventana suelta: \(!centro.ventanaViva)")
    return dibujados > 0 && !centro.ventanaViva && porCiclo < 1 && vivasV == 0 && vivasA == 0 && vivosD == 0
}
