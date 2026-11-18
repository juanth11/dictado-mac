import AppKit
import DictadoKit
import SwiftUI

// Isla compacta: estado, Claude, eventos y avisos. Partido de VistaIsla.swift sin cambiar el comportamiento.

/// Alas a los lados del notch. Izquierda: carátula, evento, Claude o la app que escucha. Derecha: Claude
/// trabajando o esperándote, la onda de la música o los minutos para el evento; y el punto verde/naranja de
/// cámara o micrófono en el borde (como el iPhone).
struct Compacta: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let privacidad: Privacidad
    let claude: SesionesClaude
    var foco: Foco?
    var notas: NotasReunion?
    /// Hora fija para los renders.
    var ahoraFijo: Date?
    /// Con el Tablero del centro, "trabajando" y "esperan tu sí" salen de él; sin él, de las sesiones de Claude.
    var agentes: AgentesRemotos?
    var tablero: TableroIsla?

    private var cuentas: CuentasAgentes { CuentasAgentes.de(claude: claude, agentes: agentes, tablero: tablero, ahora: ahoraFijo ?? Date()) }

    var body: some View {
        let punto = privacidad.activo
        let llamada = privacidad.desde != nil
        HStack(spacing: 0) {
            izquierda
                .frame(width: 48)
                .padding(.leading, punto ? 12 : 0)
            Spacer(minLength: estado.notch.width)
            HStack(spacing: 4) {
                if llamada, let desde = privacidad.desde {
                    if notas?.grabando == true {  // tomando notas: un punto rojo junto al cronómetro
                        Circle().fill(Tono.rojo.base).frame(width: 8, height: 8).shadow(color: Tono.rojo.base, radius: 3)
                            .help("Tomando notas de la llamada")
                    }
                    Cronometro(desde: desde)  // en llamada manda el cronómetro, como en el iPhone
                } else if let notas, notas.grabando, let desde = notas.desde {  // grabando sin llamada (presencial)
                    Circle().fill(Tono.rojo.base).frame(width: 8, height: 8).shadow(color: Tono.rojo.base, radius: 3)
                    Cronometro(desde: desde)
                } else if notas?.pendiente != nil {  // la pregunta "¿grabo?" sigue abierta
                    Image(systemName: "record.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tono.rojo.claro)
                        .help("¿Grabo la reunión? Hyper + R")
                } else if let foco, foco.activo != nil {
                    MinutosFoco(foco: foco)
                } else {
                    // Aurora: el indicador solo cuando algo te espera; si no, a la derecha va la hora de tu próxima reunión.
                    if (claude.hayActividad || cuentas.esperan > 0) && (Ajustes.islaClasica || cuentas.esperan > 0) { IndicadorClaude(claude: claude, esperan: cuentas.esperan, trabajando: cuentas.trabajando) }
                    derecha
                }
            }
            .frame(width: 48)
            if punto {
                PuntoPrivacidad(camara: privacidad.camara).frame(width: 16, alignment: .leading)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, FormaIsla.hombro)
        .frame(height: estado.notch.height)
    }

    @ViewBuilder private var izquierda: some View {
        if privacidad.activo, let icono = privacidad.icono {  // la llamada manda sobre la música
            Image(nsImage: icono).resizable().frame(width: 20, height: 20).modifier(Entrada())
        } else if let foco, foco.activo != nil {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in AnilloFoco(fraccion: foco.fraccion(en: ctx.date)) }
        } else if musica.hayPista {
            Caratula(imagen: musica.caratula, lado: 20, radio: 5)
        } else if let evento = agenda.inminente {
            Circle().fill(evento.color).frame(width: 8, height: 8)
        } else if privacidad.activo {
            if let icono = privacidad.icono {
                Image(nsImage: icono).resizable().frame(width: 20, height: 20).modifier(Entrada())
            } else {
                Image(systemName: privacidad.camara ? "video.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PuntoPrivacidad.color(camara: privacidad.camara))
            }
        } else if !Ajustes.islaClasica && cuentas.trabajando > 0 {
            AgentesTrabajando(cuantos: cuentas.trabajando)
        } else if claude.hayActividad {
            EstrellaClaude().fill(Color.claude).frame(width: 16, height: 16)
        }
    }

    @ViewBuilder private var derecha: some View {
        if musica.hayPista {
            Image(systemName: "waveform")  // fija: en reposo la isla no anima nada (cero CPU)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(musica.acento)
                .opacity(musica.sonando ? 1 : 0.4)
        } else if let evento = agenda.inminente, Ajustes.islaClasica ? !claude.hayActividad : cuentas.esperan == 0 {
            Text(Tiempo.faltan(evento.inicio))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(evento.color)
                .fixedSize()
        } else if let proxima = Reposo.proximaReunion(agenda, ahora: ahoraFijo ?? Date()), cuentas.esperan == 0 {
            Text(Frase.hora(proxima.inicio))   // "3:00": la hora de tu próxima reunión de hoy
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
                .accessibilityLabel("Próxima reunión a las " + Frase.hora(proxima.inicio))
        }
    }
}

/// El reposo de Aurora (sección 9): a la izquierda de la cámara, un punto y cuántos agentes trabajan; a la derecha, la hora
/// de la próxima reunión de hoy. Cada lado se oculta si no tiene nada que decir. Es una franja quieta: no anima ni consulta.
@MainActor
enum Reposo {
    static func hay(claude: SesionesClaude, agenda: Agenda, tablero: TableroIsla? = nil, ahora: Date = Date()) -> Bool {
        guard !Ajustes.islaClasica else { return false }
        let c = CuentasAgentes.de(claude: claude, agentes: nil, tablero: tablero, ahora: ahora)
        return c.trabajando > 0 || c.esperan > 0 || proximaReunion(agenda, ahora: ahora) != nil
    }

    /// La próxima reunión de hoy que aún no empieza.
    static func proximaReunion(_ agenda: Agenda, ahora: Date = Date()) -> Agenda.Evento? {
        return agenda.eventos.first { $0.esReunion && $0.inicio > ahora && Calendar.current.isDate($0.inicio, inSameDayAs: ahora) }
    }
}

/// El punto del color de agentes y el número de los que trabajan.
struct AgentesTrabajando: View {
    let cuantos: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(AuroraAcento.agentes).frame(width: 8, height: 8).shadow(color: AuroraAcento.agentes, radius: 4)
            Text("\(cuantos)").font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cuantos) agentes trabajando")
    }
}

/// Tiempo en llamada (micrófono o cámara en uso), verde como en el iPhone. Se redibuja 1 vez por segundo
/// solo mientras dura la llamada.
struct Cronometro: View {
    let desde: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Tiempo.reloj(ctx.date.timeIntervalSince(desde)))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PuntoPrivacidad.color(camara: true))
                .fixedSize()
        }
    }
}

/// Aviso de Salud del Mac (disco casi lleno, memoria al límite, calor, una app al máximo), como el diagnóstico de la pestaña
/// Mac: el rótulo teñido dice qué pasa y una frase lo explica. "Ver" abre Salud del Mac.
struct SaludIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let detalle: String
    let grave: Bool
    let ver: () -> Void

    var body: some View {
        AlertaAura(notch: estado.notch, tono: grave ? .espera : .alerta, rotulo: titulo, frase: detalle) {
            BotonAura("Ver", estilo: .lleno, ayuda: "Abrir Salud del Mac", accion: ver)
        }
    }
}

/// Aviso de un agente de fuera del Mac: una tarea falló o el servidor no responde. "Ver" abre su detalle en la pestaña Agentes.
struct AgenteIsla: View {
    let estado: EstadoIsla
    let nombre: String
    let alerta: String
    let caido: Bool
    let ver: () -> Void

    var body: some View {
        // "informe-diario falló: sin conexión" → rótulo con el nombre, frase "informe-diario falló", apoyo "sin conexión".
        let partes = alerta.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        AlertaAura(notch: estado.notch, tono: caido ? .espera : .alerta, rotulo: (caido ? "Sin respuesta · " : "Alerta · ") + nombre,
                   frase: partes.first ?? alerta, apoyo: partes.count > 1 ? partes[1] : nil) {
            BotonAura("Ver", estilo: .lleno, ayuda: "Ver el detalle de \(nombre)", accion: ver)
        }
    }
}

/// Botón en píldora de los avisos ("Ver", "Responder").
struct BotonAviso: View {
    let titulo: String
    var fondo: Color = .white
    var texto: Color = .black
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(texto)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(fondo))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(PulsadoAurora())
    }
}

/// Claude en el ala, sin animaciones continuas (cero CPU en reposo): estrella naranja con cuántas sesiones
/// trabajan; si alguna te espera, punto naranja con brillo.
struct IndicadorClaude: View {
    let claude: SesionesClaude
    var esperan = 0
    var trabajando = 0

    var body: some View {
        HStack(spacing: 4) {
            if esperan > 0 {
                Circle().fill(Color.claude).frame(width: 8, height: 8).shadow(color: Color.claude, radius: 4)
            } else {
                EstrellaClaude().fill(Color.claude).frame(width: 12, height: 12)
            }
            let n = esperan > 0 ? esperan : trabajando
            if n > 1 {
                Text("\(n)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Color.claude)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Estrella de Claude (doce rayos de largo alterno).
struct EstrellaClaude: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radio = min(r.width, r.height) / 2
        let ancho = radio * 0.2
        for i in 0..<12 {
            let largo = radio * (i.isMultiple(of: 2) ? 1.0 : 0.74)
            let rayo = CGRect(x: -ancho / 2, y: radio * 0.1, width: ancho, height: largo - radio * 0.1)
            let giro = CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: Double(i) / 12 * 2 * .pi)
            p.addPath(Path(roundedRect: rayo, cornerRadius: ancho / 2).applying(giro))
        }
        return p
    }
}

extension Color {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

/// Una sesión de Claude te necesita (qué permiso o qué pregunta) o terminó (con qué frase y cuánto tardó, en un orbe). El botón
/// abre justo esa sesión.
struct ClaudeIsla: View {
    let estado: EstadoIsla
    let sesion: SesionesClaude.Sesion
    let necesita: Bool
    let duracion: TimeInterval
    let abrir: () -> Void

    var body: some View {
        let detalle = necesita ? sesion.actividad : sesion.resumen
        let minutos = max(1, Int((duracion / 60).rounded()))
        AlertaAura(notch: estado.notch, tono: necesita ? .claude : .verde, rotulo: necesita ? sesion.espera : "Claude terminó",
                   frase: sesion.nombre, apoyo: detalle.isEmpty ? nil : detalle) {
            if !necesita {
                OrbeAurora(titulo: "Tardó", numero: "\(minutos)", unidad: "min", valor: min(1, duracion / 3600), cifra: 17, lado: AuroraNotch.orbeAlerta)
                    .modifier(Entrada())
            }
        } acciones: {
            BotonAura(necesita ? "Responder" : "Ver", estilo: .lleno, ayuda: necesita ? "Responder en la sesión «\(sesion.nombre)»" : "Abrir la sesión «\(sesion.nombre)»", accion: abrir)
        }
    }
}

/// Reunión en 5 minutos: la cuenta regresiva en números de puntos (como la tarjeta de la próxima reunión), el título y Unirse
/// (se redibuja 1 vez por segundo solo mientras el aviso está a la vista).
struct EventoIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let inicio: Date
    let color: Color
    let enlace: URL?
    var preparar: (() -> Void)?
    let unirse: (URL) -> Void

    var body: some View {
        let tono = TonoAura.de(color)
        AlertaAura(notch: estado.notch, tono: tono, rotulo: enlace == nil ? "Reunión · empieza en" : "Videollamada · empieza en", frase: titulo) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if inicio.timeIntervalSince(ctx.date) > 0 {
                    NumeroPuntos(texto: Tiempo.cuentaRegresiva(hasta: inicio, desde: ctx.date))
                } else {
                    Text("Ahora").font(.system(size: 24, weight: .ultraLight))
                }
            }
            .frame(minWidth: 84, alignment: .leading)
            .accessibilityLabel("Empieza " + Tiempo.faltan(inicio))
        } acciones: {
            if let preparar {
                BotonAura(icono: "text.magnifyingglass", redondo: true, ayuda: "Prepárame: lo que sabe tu cerebro de esta reunión", accion: preparar)
            }
            if let enlace {
                BotonAura("Unirse", icono: "video.fill", estilo: .lleno, ayuda: "Unirse a la videollamada: \(titulo)") { unirse(enlace) }
            }
        }
    }
}

/// Terminó un bloque de foco: la pregunta, con el aura ámbar del foco.
struct FocoAvisoIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let responder: (Bool?) -> Void
    let extender: (Int) -> Void

    var body: some View {
        AlertaAura(notch: estado.notch, tono: .alerta, rotulo: "Terminó el bloque de foco · ¿quedó hecha?", frase: titulo) {
            BotonAura("Hecha", icono: "checkmark", estilo: .lleno, ayuda: "Marcarla como hecha") { responder(true) }
            BotonAura("Aún no", ayuda: "Todavía no está hecha") { responder(false) }
            BotonAura("+10", ayuda: "Diez minutos más") { extender(10) }
        }
    }
}

/// Empezó una reunión o una llamada: ¿grabo? Nunca graba sin tu sí (y conviene avisarles a los demás). La pregunta se
/// queda hasta que respondes; "En 3 min" la vuelve a hacer una vez.
struct NotasOfertaIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let responder: (NotasReunion.Respuesta) -> Void

    var body: some View {
        AlertaAura(notch: estado.notch, tono: .espera, rotulo: "¿Grabo la reunión?", frase: titulo, apoyo: "Avísales que grabas · Hyper + R") {
            BotonAura("Grabar", icono: "record.circle", estilo: .lleno, ayuda: "Grabar la reunión") { responder(.grabar) }
            BotonAura("En 3 min", ayuda: "Preguntar otra vez en 3 minutos") { responder(.luego) }
            BotonAura("No", ayuda: "No grabar") { responder(.no) }
        }
    }
}

/// Cargador conectado: el porcentaje en un orbe (en calma, blanco) y una frase, con aura verde.
struct CargaIsla: View {
    let estado: EstadoIsla
    let porcentaje: Int

    var body: some View {
        AlertaAura(notch: estado.notch, tono: .verde, rotulo: "Cargando", frase: porcentaje >= 100 ? "La batería está completa" : "Batería al \(porcentaje) %") {
            OrbeAurora(titulo: "Batería", numero: "\(porcentaje)", unidad: "%", valor: Double(porcentaje) / 100, cifra: 17, lado: AuroraNotch.orbeAlerta)
                .modifier(Entrada())
        } acciones: {
            EmptyView()
        }
    }
}

/// Unirse a la videollamada: círculo verde (como contestar una llamada) o píldora con el texto "Unirse".
struct BotonUnirse: View {
    var redondo = false
    var conTexto = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Group {
                if conTexto {
                    Label("Unirse", systemImage: "video.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(LinearGradient(colors: Tono.verde.gradiente.reversed(), startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Tono.verde.base.opacity(0.45), radius: 6)
                        .fixedSize()
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: redondo ? 13 : 11, weight: .semibold))
                        .frame(width: redondo ? 36 : 28, height: redondo ? 36 : 28)
                        .background(Circle().fill(LinearGradient(colors: Tono.verde.gradiente.reversed(), startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Tono.verde.base.opacity(0.45), radius: 6)
                }
            }
            .foregroundStyle(conTexto ? .black : .white)
            .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .help("Unirse a la reunión")
    }
}

/// Nueva canción: carátula, rótulo, título y artista y el ecualizador; de fondo, el aura de los colores de la carátula.
struct AhoraSuena: View {
    let estado: EstadoIsla
    let musica: Musica

    var body: some View {
        AlertaAura(notch: estado.notch, tono: TonoAura.de(musica.acento), rotulo: musica.sonando ? "Ahora suena" : "En pausa",
                   frase: musica.titulo, apoyo: musica.artista) {
            Caratula(imagen: musica.caratula, lado: 46, radio: 11, resplandor: true)
                .modifier(Entrada())
        } acciones: {
            Ecualizador(color: Tono.de(musica.acento).claro, activo: musica.sonando)
        }
    }
}

/// Fondo con los colores de la carátula: la imagen muy desenfocada, más fuerte a la izquierda y que se
/// funde en negro hacia la derecha (como las tarjetas de Live Activities).
struct FondoArte<Forma: Shape>: View {
    let imagen: NSImage?
    let forma: Forma
    var alcance: CGFloat = 0.75

    var body: some View {
        if let imagen {
            GeometryReader { geo in
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: geo.size.width * 0.7, height: geo.size.height * 1.4)
                    .blur(radius: 34)
                    .saturation(1.5)
                    .opacity(0.7)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: alcance)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(forma)
            .allowsHitTesting(false)
        }
    }
}
