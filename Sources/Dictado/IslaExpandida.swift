import AppKit
import SwiftUI

// Isla expandida: actividad, agentes y sesiones. Partido de VistaIsla.swift sin cambiar el comportamiento.

struct Expandida: View {
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
    var pendientes: Pendientes?
    /// Render sin app (ImageRenderer no dibuja ScrollView): las listas se cortan abajo en vez de desplazarse.
    var simulado = false
    let unirse: (URL) -> Void
    let abrirSalud: () -> Void
    let medirSalud: () -> Void
    var preparar: (Agenda.Evento) -> Void = { _ in }
    var responderFoco: (Bool?) -> Void = { _ in }
    var extenderFoco: (Int) -> Void = { _ in }
    var alternarNotas: () -> Void = {}
    var copiarAviso: () -> Void = {}

    /// Sin elegir: Agentes, salvo que haya una reunión en curso o en las próximas dos horas (entonces Agenda). Lo que
    /// pide tu respuesta (un agente abierto desde su aviso, Claude esperándote, una alerta) va primero. El Mac solo
    /// si lo eliges: sus problemas ya avisan solos y tiñen su pestaña.
    private var porDefecto: EstadoIsla.Pestana {
        if estado.agenteAbierto != nil || !claude.esperando.isEmpty || agentes.hayAlertas { return .agentes }
        if notas?.grabando == true { return .notas }
        let ahora = Date()
        if agenda.eventos.contains(where: { $0.fin > ahora && $0.inicio.timeIntervalSince(ahora) < 2 * 3600 }) { return .agenda }
        return .agentes
    }

    /// Punto de la pestaña Agentes: naranja si Claude te espera, rojo o ámbar si un agente remoto avisa.
    private var puntoAgentes: Color? {
        if !claude.esperando.isEmpty { return Tono.claude.base }
        if agentes.agentes.contains(where: { $0.estado == .caido }) { return AgentesRemotos.Estado.caido.color }
        return agentes.hayAlertas ? AgentesRemotos.Estado.alerta.color : nil
    }

    /// La luz de la derecha, solo cuando algo pide atención: Claude te espera, un agente avisa (o su detalle está
    /// abierto), hay una reunión en la próxima hora, el Mac no está bien. Si todo está en calma, no hay luz.
    private func tonoPestana(_ p: EstadoIsla.Pestana) -> Tono? {
        switch p {
        case .agentes:
            if !claude.esperando.isEmpty { return .claude }
            if let a = agentes.agentes.first(where: { $0.estado == .caido || $0.estado == .alerta }) { return Tono.agente(a.estado) }
            if let nombre = estado.agenteAbierto, let a = agentes.agentes.first(where: { $0.nombre == nombre }) { return Tono.agente(a.estado) }
            return nil
        case .agenda:
            return agenda.eventos.first { $0.fin > Date() && $0.inicio.timeIntervalSinceNow < 3600 }.map { Tono.de($0.color) }
        case .notas:
            return notas?.grabando == true || notas?.pendiente != nil ? .rojo : nil
        case .mac:
            let g = salud.diagnostico.gravedad
            return g == .bien ? nil : Tono.gravedad(g)
        case .inicio, .tareas: return nil
        }
    }

    /// Las pestañas nuevas de Aurora no existen aquí: Inicio cae en Agentes y Tareas en Notas.
    private static func clasica(_ p: EstadoIsla.Pestana) -> EstadoIsla.Pestana {
        switch p {
        case .inicio: return .agentes
        case .tareas: return .notas
        default: return p
        }
    }

    private func elegir(_ p: EstadoIsla.Pestana) {
        estado.pestana = p
        estado.agenteAbierto = nil
        switch p {
        case .agentes:
            claude.actualizarUso()
            agentes.refrescar()
        case .mac: medirSalud()
        case .agenda, .inicio: break
        case .notas, .tareas: pendientes?.refrescar()
        }
    }

    /// "Revisión de contrato · Arc" si coincide con una reunión en curso; si no, la app.
    private var etiquetaLlamada: String {
        let ahora = Date()
        let app = privacidad.nombre.isEmpty ? (privacidad.camara ? "Cámara" : "Micrófono") : privacidad.nombre
        if let reunion = agenda.eventos.first(where: { $0.inicio <= ahora.addingTimeInterval(300) && $0.fin > ahora }) {
            return reunion.titulo + " · " + app
        }
        return "En llamada · " + app
    }

    var body: some View {
        let actual = Self.clasica(estado.pestana ?? porDefecto)
        VStack(spacing: 0) {
            HStack {  // el notch físico; a la derecha, quién usa la cámara o el micrófono
                Spacer()
                if let notas {  // grabar siempre está a mano: en llamada o en una reunión presencial
                    if notas.grabando {
                        Button(action: copiarAviso) {
                            Image(systemName: notas.avisaste ? "checkmark" : "doc.on.clipboard")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Halo.texto2)
                                .frame(width: 24, height: 20)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(PulsadoAurora())
                        .help("Copiar el aviso de grabación para pegarlo en el chat de la reunión")
                        .padding(.trailing, 4)
                        Button { notas.pedirNombre() } label: {
                            Image(systemName: notas.origen == .usuario ? "pencil.line" : "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(notas.origen == .usuario ? Halo.texto2 : Tono.ambar.base)
                                .frame(width: 24, height: 20)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(PulsadoAurora())
                        .help(notas.origen == .usuario ? "Cambiar el nombre: «\(notas.titulo)»"
                              : "Ponerle nombre (si no, lo pongo según lo que se habló). Ahora: «\(notas.titulo)»")
                        .padding(.trailing, 4)
                    }
                    Button(action: alternarNotas) {
                        HStack(spacing: 4) {
                            Circle().fill(Tono.rojo.base).frame(width: 8, height: 8)
                                .shadow(color: Tono.rojo.base, radius: notas.grabando ? 3 : 0)
                            if notas.grabando, let desde = notas.desde {
                                Text("Grabando").font(.system(size: 10, weight: .semibold)).foregroundStyle(Halo.texto)
                                Cronometro(desde: desde)
                                Text("· Terminar").font(.system(size: 10, weight: .semibold)).foregroundStyle(Halo.texto)
                            } else {
                                Text(notas.pendiente.map { "Grabar · " + ($0.count > 26 ? $0.prefix(25) + "…" : $0) } ?? "Grabar")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8).frame(height: 20).fixedSize()
                        .background(Capsule().fill(Tono.rojo.base.opacity(notas.grabando || notas.pendiente != nil ? 0.2 : 0.1)))
                    }
                    .buttonStyle(PulsadoAurora())
                    .help(notas.grabando ? "Terminar: se transcribe en el Mac y el resumen va a tu inbox (Hyper + R)"
                                         : "Grabar esta reunión, en llamada o presencial (Hyper + R)")
                    .padding(.trailing, privacidad.activo ? 8 : 32)
                }
                if privacidad.activo {
                    Button { privacidad.irALaApp() } label: {
                        HStack(spacing: 4) {
                            Text(etiquetaLlamada)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Halo.texto2)
                                .lineLimit(1)
                            if let desde = privacidad.desde { Cronometro(desde: desde) }
                            PuntoPrivacidad(camara: privacidad.camara)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PulsadoAurora())
                    .help("Volver a la llamada")
                    .padding(.trailing, 32)
                }
            }
            .frame(height: estado.notch.height)
            HStack(alignment: .top, spacing: 20) {
                Group {
                    if let foco, foco.activo != nil {
                        FocoIsla(foco: foco, responder: responderFoco, extender: extenderFoco)
                    } else {
                        Reproductor(musica: musica, fuentes: fuentes)
                    }
                }
                .frame(width: 212, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .center)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        PildoraHalo(titulo: "Agentes", cuenta: claude.sesiones.count + agentes.agentes.count, punto: puntoAgentes,
                                    activa: actual == .agentes) { elegir(.agentes) }
                        PildoraHalo(titulo: "Agenda", cuenta: agenda.reunionesHoy, activa: actual == .agenda) { elegir(.agenda) }
                        if pendientes != nil {
                            PildoraHalo(titulo: "Notas", cuenta: pendientes?.abiertos ?? 0,
                                        punto: notas?.grabando == true || notas?.pendiente != nil ? Tono.rojo.base : nil,
                                        activa: actual == .notas) { elegir(.notas) }
                        }
                        PildoraHalo(titulo: "Mac", punto: Tono.gravedad(salud.diagnostico.gravedad).base, activa: actual == .mac) {
                            elegir(.mac)
                        }
                        Spacer(minLength: 4)
                        if actual == .agentes && estado.agenteAbierto == nil && claude.tokensHoy > 0 {
                            ActividadDia(porHora: claude.porHora)
                                .help("Hoy: \(claude.respuestasHoy) respuestas y \(Tiempo.tokens(claude.tokensHoy)) tokens escritos entre todas las sesiones")
                        }
                    }
                    switch actual {
                    case .agentes:
                        if let nombre = estado.agenteAbierto, let agente = agentes.agentes.first(where: { $0.nombre == nombre }) {
                            DetalleAgente(agente: agente, consultando: agentes.consultando) { estado.agenteAbierto = nil }
                        } else {
                            ListaAgentes(claude: claude, agentes: agentes, simulado: simulado) { estado.agenteAbierto = $0 }
                        }
                    case .agenda: ListaAgenda(agenda: agenda, unirse: unirse, preparar: preparar, simulado: simulado)
                    case .mac: ResumenMac(salud: salud, abrir: abrirSalud)
                    case .notas, .inicio, .tareas:
                        if let pendientes {
                            PestanaNotas(pendientes: pendientes, agenda: agenda, notas: notas, foco: foco, alternarNotas: alternarNotas)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {  // la música tiñe el borde de abajo a la izquierda; la pestaña, a la derecha
            ZStack {
                if musica.hayPista { LuzBorde(tono: Tono.de(musica.acento), fuerza: 0.5, alto: 0.6, centro: 0.2, ancho: 0.48) }
                if let tono = tonoPestana(actual) { LuzBorde(tono: tono, fuerza: 0.26, alto: 0.5, centro: 0.74, ancho: 0.5) }
            }
        }
        .onAppear {
            claude.actualizarUso()
            claude.vigilarActividad(true)
            switch Self.clasica(estado.pestana ?? porDefecto) {
            case .mac: medirSalud()
            case .agentes: agentes.refrescar()
            default: break
            }
        }
        .onDisappear {
            claude.vigilarActividad(false)
            fuentes?.mostrandoSalidas = false
        }
        .task {  // qué suena y por dónde, cada 2 s solo mientras la isla está abierta
            guard let fuentes, !simulado else { return }
            while !Task.isCancelled {
                fuentes.refrescar()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Tokens escritos por hora en las últimas 8 horas de hoy (como la gráfica de UV de las referencias);
/// la hora actual en naranja.
struct ActividadDia: View {
    let porHora: [Int]

    var body: some View {
        let ahora = Calendar.current.component(.hour, from: Date())
        let horas = Array(max(0, ahora - 7)...ahora)
        let maximo = max(1, horas.map { porHora[$0] }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(horas, id: \.self) { h in
                Capsule()
                    .fill(h == ahora ? Tono.claude.base : .white.opacity(0.3))
                    .frame(width: 2.5, height: max(2.5, 14 * CGFloat(porHora[h]) / CGFloat(maximo))) // grid: ok barra proporcional
            }
        }
        .frame(height: 16, alignment: .bottom)

    }
}

/// Lo más importante de Salud del Mac en la isla: el titular del diagnóstico y cuatro diales cuyo resplandor sube
/// con la gravedad (verde tranquilo, ámbar, rojo intenso). El titular y el ícono abren el panel completo.
struct ResumenMac: View {
    let salud: EstadoSalud
    let abrir: () -> Void

    private static func gigas(_ bytes: Double) -> String {
        let g = bytes / 1e9
        return g < 10 ? String(format: "%.1f", g).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f", g)
    }

    var body: some View {
        let d = salud.diagnostico
        VStack(alignment: .leading, spacing: 8) {
            Button(action: abrir) {
                HStack(spacing: 8) {
                    PuntoBrillante(color: Tono.gravedad(d.gravedad).base, lado: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.titulo).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        Text(d.frase).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsadoAurora())
            .help("Abrir Salud del Mac (detalle y limpieza)")
            HStack(spacing: 0) {
                DialMac(valor: salud.cpu, gravedad: salud.gravedadCPU,
                        numero: String(format: "%.0f", salud.cpu * 100), unidad: "%", titulo: "Procesador")
                DialMac(valor: salud.memoriaUsada / max(1, salud.memoriaTotal), gravedad: salud.gravedadMemoria,
                        numero: String(format: "%.0f", salud.memoriaUsada / 1e9),
                        unidad: String(format: "/%.0f", salud.memoriaTotal / 1.073741824e9), titulo: "Memoria GB")
                DialMac(valor: salud.gpu, gravedad: salud.gravedadGPU,
                        numero: String(format: "%.0f", salud.gpu * 100), unidad: "%", titulo: "Gráficos")
                DialMac(valor: 1 - salud.discoLibre / max(1, salud.discoTotal), gravedad: salud.gravedadDisco,
                        numero: Self.gigas(salud.discoLibre), unidad: "GB", titulo: "Disco libre")
            }
        }
    }
}

/// Un dial de Salud del Mac: anillo encendido hasta el uso, resplandor según la gravedad y el número en el centro.
struct DialMac: View {
    let valor: Double
    let gravedad: Gravedad
    let numero: String
    let unidad: String
    let titulo: String

    var body: some View {
        VStack(spacing: 4) {
            Dial(lado: 52, valor: valor, colores: Tono.gravedad(gravedad).gradiente, marcas: 32, anillo: 4,
                 brillo: gravedad == .mal ? 0.8 : (gravedad == .atento ? 0.55 : 0.25)) {
                NumeroFino(texto: numero, unidad: unidad, tamano: 14.5, peso: .light)
            }
            Rotulo(titulo, color: Halo.texto3)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pestaña Agentes: las sesiones de Claude Code y los agentes remotos en una sola lista, primero lo que necesita
/// atención (Claude esperándote, un agente con alerta), luego lo que trabaja y al final lo que está quieto.
/// Tocar un agente remoto abre su detalle con el día (`DetalleAgente`).
struct ListaAgentes: View {
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    var simulado = false
    let abrir: (String) -> Void

    private enum Elemento: Identifiable {
        case sesion(SesionesClaude.Sesion)
        case agente(AgentesRemotos.Agente)

        var id: String {
            switch self {
            case .sesion(let s): return "s" + s.id
            case .agente(let a): return "a" + a.id
            }
        }

        var prioridad: Int {
            switch self {
            case .sesion(let s): return s.estado == .esperando ? 0 : (s.estado == .trabajando ? 2 : 4)
            case .agente(let a): return a.estado == .alerta || a.estado == .caido || !a.alertas.isEmpty ? 1 : 3
            }
        }
    }

    private var elementos: [Elemento] {
        let todos = claude.sesiones.map(Elemento.sesion) + agentes.agentes.map(Elemento.agente)
        return todos.enumerated()
            .sorted { ($0.element.prioridad, $0.offset) < ($1.element.prioridad, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        if elementos.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sin sesiones abiertas").font(.system(size: 13)).foregroundStyle(Halo.texto2)
                Text("Aquí aparecen tus sesiones de Claude Code y los agentes remotos que configures.")
                    .font(Halo.detalle).foregroundStyle(Halo.texto3)
            }
        } else if simulado {
            Color.clear.overlay(alignment: .top) { lista }.clipped().mask(desvanecido)
        } else {
            ScrollView(.vertical, showsIndicators: false) { lista.padding(.bottom, 8) }
                .mask(desvanecido)
        }
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(elementos) { e in
                switch e {
                case .sesion(let s): FilaSesion(sesion: s)
                case .agente(let a): FilaAgente(agente: a) { abrir(a.nombre) }
                }
            }
        }
    }

    /// Lo que sigue más abajo se desvanece (pista de que se puede desplazar).
    private var desvanecido: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Una sesión de Claude Code: qué hace o qué te pide, y su contexto. El clic abre justo esa sesión. Si te espera,
/// va resaltada en naranja y con el pedido completo.
struct FilaSesion: View {
    let sesion: SesionesClaude.Sesion

    var body: some View {
        let espera = sesion.estado == .esperando
        Button { SesionesClaude.abrir(sesion) } label: {
            HStack(spacing: 8) {
                Group {
                    if espera { Insignia(icono: .estrella, tono: .claude, lado: 26) } else { EstadoSesion(estado: sesion.estado).frame(width: 16, height: 16) }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sesion.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                    Text(Tiempo.sesion(sesion))
                        .font(Halo.detalle)
                        .foregroundStyle(espera ? Tono.claude.claro : Halo.texto3)
                        .lineLimit(espera ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if espera {
                    BotonHalo(titulo: "Responder", tono: .claude, alto: 26) { SesionesClaude.abrir(sesion) }
                } else if sesion.contexto > 0 {
                    Contexto(tokens: sesion.contexto)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, espera ? 8 : 4)
            .background {
                if espera { Color.clear.tarjetaHalo(radio: 14, activa: true, tono: .claude) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .help(espera ? "Abrir la sesión para responder" : "Abrir la sesión")
    }
}

/// Contexto de una conversación: anillo pequeño (de 0 a 1 M) y la cifra; ámbar pasados ~600 k.
struct Contexto: View {
    let tokens: Int

    var body: some View {
        let alto = tokens > 600_000
        let color = alto ? Tono.ambar.base : Color.white.opacity(0.5)
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 1.5)
                Circle().trim(from: 0, to: min(1, Double(tokens) / 1_000_000))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)) // grid: ok trazo dibujado
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text(Tiempo.tokens(tokens))
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(alto ? Tono.ambar.claro : Halo.texto3)
        }
        .fixedSize()
        .help("Contexto de esta conversación. Si pasa de ~600 k conviene abrir una nueva.")
    }
}

/// Ícono del estado de una sesión: estrella que gira (trabaja), punto que late (te espera), check (lista).
struct EstadoSesion: View {
    let estado: SesionesClaude.Estado
    @State private var giro = false

    var body: some View {
        switch estado {
        case .trabajando:
            EstrellaClaude().fill(Tono.claude.base)
                .rotationEffect(.degrees(giro ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { giro = true } }
        case .esperando:
            PuntoBrillante(color: Tono.claude.base, lado: 8)
        case .lista:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
    }
}
