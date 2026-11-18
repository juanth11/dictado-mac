import AppKit
import DictadoKit
import SwiftUI

// La isla abierta con Aurora: cinco pestañas (Inicio, Agentes, Agenda, Tareas, Mac) y debajo una fila de tarjetas de 178.
// Este archivo es la cáscara: la barra de arriba y el reparto por pestaña. Cada pestaña vive en su archivo
// (IslaAuroraInicio, IslaAuroraAgentes, IslaAuroraAgenda, IslaAuroraTareas, IslaAuroraMac). `isla.clasica` vuelve a `Expandida`.
// En reposo no anima nada: lo único vivo es `RelojMinuto` (un despertar por minuto, solo con la isla abierta) y, mientras
// suena algo o se graba, el avance de la barra y el cronómetro, como en el diseño anterior.

/// Lo que las tarjetas piden a la app. Cada una se conecta en `VistaIsla` con la isla; en los renders no hacen nada.
struct AccionesIsla {
    var unirse: (URL) -> Void = { _ in }
    /// `limpieza`: abre Salud del Mac en Limpieza (no borra nada: solo muestra); `explicar` despliega la primera categoría segura.
    var abrirSalud: (_ limpieza: Bool, _ explicar: Bool) -> Void = { _, _ in }
    var medirSalud: () -> Void = {}
    /// Calcula lo recuperable (fuera del hilo principal) si aún no se ha hecho.
    var analizarSalud: () -> Void = {}
    var preparar: (Agenda.Evento) -> Void = { _ in }
    var responderFoco: (Bool?) -> Void = { _ in }
    var extenderFoco: (Int) -> Void = { _ in }
    var alternarNotas: () -> Void = {}
    var copiarAviso: () -> Void = {}
    /// El micrófono de la barra: empieza a dictar y, al tocarlo otra vez, termina (lo mismo que mantener ⌥Espacio).
    var dictar: () -> Void = {}
    /// Dictar un encargo (desde la tarjeta Nuevo encargo): al terminar, se crea en el Tablero del centro.
    var dictarEncargo: () -> Void = {}
    /// El menú de Dictado.
    var ajustes: () -> Void = {}
}

struct ExpandidaAurora: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let privacidad: Privacidad
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let salud: EstadoSalud
    let fuentes: Fuentes?
    var foco: Foco?
    var notas: NotasReunion?
    var tareas: TareasIsla?
    var apps: AppsUsadas?
    var lanzador: LanzadorIsla?
    var tablero: TableroIsla?
    /// Render sin app: las listas se cortan en vez de desplazarse y la hora es la que se fije.
    var simulado = false
    var ahoraFijo: Date?
    var acciones = AccionesIsla()

    @State private var reloj = RelojMinuto()

    private var actual: EstadoIsla.Pestana {
        switch estado.pestana {
        case .notas: return .tareas          // Notas ya no es pestaña: lo que traía vive en Tareas
        case .some(let p): return p
        case nil: return estado.agenteAbierto != nil ? .agentes : .inicio
        }
    }

    private var ahora: Date { ahoraFijo ?? reloj.ahora }

    private func elegir(_ p: EstadoIsla.Pestana) {
        estado.pestana = p
        estado.agenteAbierto = nil
        alAbrir(p)
    }

    private func alAbrir(_ p: EstadoIsla.Pestana) {
        guard !simulado else { return }   // los renders no leen nada del Mac
        claude.vigilarActividad(p == .agentes)
        switch p {
        case .agentes:
            claude.actualizarUso()
            agentes.refrescar()
            tablero?.refrescar()
        case .mac:
            acciones.medirSalud()
            acciones.analizarSalud()
        case .agenda: agenda.refrescar()
        case .tareas: tareas?.refrescar()
        case .inicio:
            apps?.refrescar()
            lanzador?.alAbrir()
            tablero?.refrescar()
        case .notas: break
        }
    }

    // MARK: Cuentas de las pestañas

    private var cuentas: CuentasAgentes { CuentasAgentes.de(claude: claude, agentes: agentes, tablero: tablero, ahora: ahora) }
    private var esperan: Int { cuentas.esperan }
    private var reunionesRestantes: Int { agenda.eventos(del: ahora).filter { $0.esReunion && $0.fin > ahora }.count }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height + CGFloat(MedidasNotch.aireSuperior))
            barra
                .frame(height: AuroraNotch.altoPildora)
                .padding(.bottom, AuroraNotch.separacion)
                .zIndex(1)  // por encima de las tarjetas: si una se desborda hacia arriba, no le roba los clics a las pestañas
            Group {
                switch actual {
                case .inicio:
                    InicioAurora(estado: estado, musica: musica, agenda: agenda, claude: claude, agentes: agentes, fuentes: fuentes, foco: foco,
                                 apps: apps, lanzador: lanzador, tablero: tablero, ahora: ahora, acciones: acciones, simulado: simulado, ir: elegir)
                case .agentes:
                    AgentesAurora(estado: estado, claude: claude, agentes: agentes, simulado: simulado, acciones: acciones, tablero: tablero, ahora: ahora)
                case .agenda:
                    AgendaAurora(agenda: agenda, ahora: ahora, acciones: acciones, simulado: simulado)
                case .tareas, .notas:
                    TareasAurora(tareas: tareas, ahora: ahora, agenda: agenda, simulado: simulado)
                case .mac:
                    MacAurora(salud: salud, acciones: acciones)
                }
            }
            .frame(height: AuroraNotch.altoTarjeta)
            .clipped()   // nada de una pestaña se sale de su franja (ni a la vista ni al clic)
        }
        .padding(.horizontal, AuroraNotch.relleno)
        .padding(.bottom, AuroraNotch.relleno)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reloj.iniciar() }
        .task {
            // Las lecturas (uso de Claude, tareas, agenda, apps) esperan a que la forma haya crecido: publicar cambios en
            // pleno resorte re-mide el panel y es lo que hacía entrecortada la apertura.
            guard !simulado else { return alAbrir(actual) }
            try? await Task.sleep(for: AuroraApertura.esperaLecturas)
            guard !Task.isCancelled else { return }
            claude.actualizarUso()
            tareas?.refrescar()
            alAbrir(actual)
        }
        .onDisappear {
            reloj.detener()
            claude.vigilarActividad(false)
            fuentes?.mostrandoSalidas = false
        }
        .task(id: actual == .inicio) {  // qué suena y por dónde, cada 2 s: solo con Inicio a la vista
            guard actual == .inicio, let fuentes, !simulado else { return }
            try? await Task.sleep(for: AuroraApertura.esperaLecturas)
            while !Task.isCancelled {
                fuentes.refrescar()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Barra de arriba

    private var barra: some View {
        HStack(spacing: 4) {
            PildoraNotch(titulo: "Inicio", activa: actual == .inicio) { elegir(.inicio) }
            PildoraNotch(titulo: "Agentes", cuenta: esperan > 0 ? esperan : (cuentas.deTablero ? cuentas.trabajando : claude.sesiones.count + agentes.agentes.count),
                         acentoCuenta: esperan > 0 ? AuroraAcento.agentes : nil, activa: actual == .agentes) { elegir(.agentes) }
            PildoraNotch(titulo: "Agenda", cuenta: reunionesRestantes, activa: actual == .agenda) { elegir(.agenda) }
            PildoraNotch(titulo: "Tareas", cuenta: tareas?.abiertas ?? 0, activa: actual == .tareas) { elegir(.tareas) }
            PildoraNotch(titulo: "Mac", activa: actual == .mac) { elegir(.mac) }
            Spacer(minLength: 8)
            if actual == .agentes, let tablero { rotuloFuente(tablero) }
            if privacidad.activo { llamada }
            if let notas { grabar(notas) }
            IconoPildoraNotch(simbolo: "mic.fill", ayuda: "Dictar: toca para empezar y otra vez para terminar (o mantén ⌥Espacio)", accion: acciones.dictar)
            IconoPildoraNotch(simbolo: "gearshape.fill", ayuda: "Ajustes: el menú de Dictado", accion: acciones.ajustes)
        }
    }

    /// De dónde salen las tarjetas de Agentes: el Tablero del centro o las sesiones de Claude vistas directo.
    private func rotuloFuente(_ tablero: TableroIsla) -> some View {
        let del = tablero.deTablero(ahora: ahora)
        return Text(del ? "Tablero del centro" : "Sesiones de Claude")
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(AuroraNotch.sutil).lineLimit(1)
            .accessibilityLabel("Fuente: " + (del ? "Tablero del centro" : "sesiones de Claude, el Tablero no está disponible"))
    }

    /// "Revisión de contrato · Arc" si coincide con una reunión en curso; si no, la app.
    private var etiquetaLlamada: String {
        let app = privacidad.nombre.isEmpty ? (privacidad.camara ? "Cámara" : "Micrófono") : privacidad.nombre
        if let r = agenda.eventos.first(where: { $0.inicio <= ahora.addingTimeInterval(300) && $0.fin > ahora }) { return r.titulo + " · " + app }
        return "En llamada · " + app
    }

    private var llamada: some View {
        Button { privacidad.irALaApp() } label: {
            HStack(spacing: 4) {
                PuntoPrivacidad(camara: privacidad.camara)
                Text(etiquetaLlamada).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AuroraNotch.suave).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: AuroraNotch.altoPildora)
            .frame(maxWidth: 220)
            .background { Capsule().fill(AuroraNotch.pildora) }
            .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .help("Volver a la llamada")
        .accessibilityLabel("Volver a la llamada: " + etiquetaLlamada)
    }

    /// Grabar siempre está a mano (en llamada o en una reunión presencial); mientras graba, el aviso y el nombre.
    @ViewBuilder private func grabar(_ notas: NotasReunion) -> some View {
        if notas.grabando {
            IconoPildoraNotch(simbolo: notas.avisaste ? "checkmark" : "doc.on.clipboard",
                              ayuda: "Copiar el aviso de grabación para pegarlo en el chat de la reunión", accion: acciones.copiarAviso)
            IconoPildoraNotch(simbolo: notas.origen == .usuario ? "pencil.line" : "pencil",
                              ayuda: notas.origen == .usuario ? "Cambiar el nombre: «\(notas.titulo)»" : "Ponerle nombre a la grabación",
                              tinte: notas.origen == .usuario ? nil : Tono.ambar.base) { notas.pedirNombre() }
        }
        Button(action: acciones.alternarNotas) {
            HStack(spacing: 4) {
                Circle().fill(AuroraNotch.rojoHoy).frame(width: 8, height: 8)
                    .shadow(color: AuroraNotch.rojoHoy, radius: notas.grabando ? 3 : 0)
                if notas.grabando, let desde = notas.desde {
                    Text("Grabando").font(AuroraNotch.pildoraFuente)
                    Cronometro(desde: desde)
                    Text("· Terminar").font(AuroraNotch.pildoraFuente)
                } else {
                    Text(notas.pendiente.map { "Grabar · " + ($0.count > 26 ? $0.prefix(25) + "…" : $0) } ?? "Grabar")
                        .font(AuroraNotch.pildoraFuente).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: AuroraNotch.altoPildora)
            .background { Capsule().fill(notas.grabando || notas.pendiente != nil ? AuroraNotch.rojoHoy.opacity(0.28) : AuroraNotch.pildora) }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PulsadoAurora())
        .help(notas.grabando ? "Terminar: se transcribe en el Mac y el resumen va a tu inbox (Hyper + R)" : "Grabar esta reunión (Hyper + R)")
        .accessibilityLabel(notas.grabando ? "Terminar la grabación" : "Grabar la reunión")
        if !notas.grabando {
            // La última grabación a un clic: muestra su transcripción y su nota en el Finder (y deja al día ultima.md).
            IconoPildoraNotch(simbolo: "doc.text.magnifyingglass",
                              ayuda: "Mostrar en el Finder la transcripción y las notas de la última grabación") {
                let r = IrALaGrabacion.ultima(inbox: Ajustes().carpetaInbox)
                IrALaGrabacion.mostrarEnFinder([r?.transcripcion, r?.notas].map { $0.map { URL(fileURLWithPath: $0) } })
            }
        }
    }
}
