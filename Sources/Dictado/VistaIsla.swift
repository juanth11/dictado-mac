import AppKit
import SwiftUI

/// Forma del notch: arriba plana con hombros cóncavos que se funden con la barra de menú, abajo redondeada.
struct FormaIsla: Shape {
    static let hombro: CGFloat = 8
    var radio: CGFloat

    var animatableData: CGFloat {
        get { radio }
        set { radio = newValue }
    }

    func path(in r: CGRect) -> Path {
        let h = Self.hombro
        let ri = min(radio, (r.height - h) / 2, (r.width - 2 * h) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + h, y: r.minY + h), control: CGPoint(x: r.minX + h, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + h, y: r.maxY - ri))
        p.addQuadCurve(to: CGPoint(x: r.minX + h + ri, y: r.maxY), control: CGPoint(x: r.minX + h, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - h - ri, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - h, y: r.maxY - ri), control: CGPoint(x: r.maxX - h, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - h, y: r.minY + h))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - h, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct VistaIsla: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let hud: EstadoHUD
    let privacidad: Privacidad
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let salud: EstadoSalud
    let control: Isla?
    /// Qué suena y por dónde (el reproductor de la isla abierta); sin ellas, solo Spotify.
    var fuentes: Fuentes?
    /// El bloque de foco y las notas de reunión (nil en los renders que no los usan).
    var foco: Foco?
    var notas: NotasReunion?
    /// Los pendientes de la pestaña Notas (en la app los da la isla; en los renders, uno de ejemplo).
    var pendientes: Pendientes?
    /// Las tareas y las apps de Inicio (en la app las da la isla; en los renders, de ejemplo).
    var tareas: TareasIsla?
    var apps: AppsUsadas?
    var lanzador: LanzadorIsla?
    /// El Tablero del centro (en la app lo da la isla; en los renders, de ejemplo o ausente).
    var tablero: TableroIsla?
    /// Hora fija para los renders de Aurora (la cuenta regresiva y la línea del día no dependen del reloj).
    var ahoraFijo: Date?

    private var alas: Bool {
        musica.hayPista || agenda.inminente != nil || privacidad.activo || claude.hayActividad
            || foco?.activo != nil || notas?.grabando == true || notas?.pendiente != nil
            || Reposo.hay(claude: claude, agenda: agenda, tablero: control?.tablero ?? tablero, ahora: ahoraFijo ?? Date())
    }

    var body: some View {
        let tam = estado.tamano(alas: alas, punto: privacidad.activo)
        let radio: CGFloat = estado.expandida ? (Ajustes.islaClasica ? 34 : AuroraNotch.radioPanel) : (estado.actividad != nil ? 24 : 10)
        ZStack(alignment: .top) {
            FormaIsla(radio: radio)
                .fill(.black)
                .shadow(color: .black.opacity(estado.expandida || estado.actividad != nil ? 0.35 : 0), radius: 18, y: 8)
            ZStack(alignment: .top) {
                contenido
                    .id(estado.expandida ? UUID(uuidString: "00000000-0000-0000-0000-000000000001")! : estado.idActividad)
                    .transition(.asymmetric(  // crece desde el notch y se enfoca
                        insertion: .modifier(active: Enfoque(activo: true), identity: Enfoque(activo: false)),
                        removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(FormaIsla(radio: radio))  // los resplandores no se salen de la isla
        }
        .frame(width: tam.width, height: tam.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Halo.morfosis, value: estado.expandida)
        .animation(Halo.entrada, value: estado.idActividad)
        .animation(Halo.cambio, value: alas)
        .animation(Halo.cambio, value: privacidad.activo)
        .environment(\.colorScheme, .dark)
        .onChange(of: alas) { control?.refrescarCompacta() }
        .onChange(of: privacidad.activo) { control?.refrescarCompacta() }
    }

    /// Lo que las tarjetas de Aurora piden a la isla (sin isla, en los renders, no hacen nada).
    private var accionesIsla: AccionesIsla {
        guard let c = control else { return AccionesIsla() }
        return AccionesIsla(unirse: { c.unirse($0) }, abrirSalud: { c.abrirSalud(limpieza: $0, explicar: $1) }, medirSalud: { c.medirSalud() },
                            analizarSalud: { c.analizarSalud() }, preparar: { c.preparar($0) }, responderFoco: { c.responderFoco($0) },
                            extenderFoco: { c.extenderFoco($0) }, alternarNotas: { c.alternarNotas() }, copiarAviso: { c.copiarAvisoNotas() },
                            dictar: { c.alDictar?() }, dictarEncargo: { c.alDictarEncargo?() }, ajustes: { c.alAbrirAjustes?() })
    }

    @ViewBuilder private var contenido: some View {
        if estado.expandida && !Ajustes.islaClasica {
            ExpandidaAurora(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude, agentes: agentes,
                            salud: salud, fuentes: fuentes, foco: foco, notas: notas, tareas: control?.tareas ?? tareas,
                            apps: control?.appsUsadas ?? apps, lanzador: control?.lanzador ?? lanzador, tablero: control?.tablero ?? tablero, simulado: control == nil, ahoraFijo: ahoraFijo, acciones: accionesIsla)
        } else if estado.expandida {
            Expandida(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude, agentes: agentes,
                      salud: salud, fuentes: fuentes, foco: foco, notas: notas, pendientes: control?.pendientes ?? pendientes,
                      simulado: control == nil,
                      unirse: { control?.unirse($0) }, abrirSalud: { control?.abrirSalud() }, medirSalud: { control?.medirSalud() },
                      preparar: { control?.preparar($0) }, responderFoco: { control?.responderFoco($0) },
                      extenderFoco: { control?.extenderFoco($0) }, alternarNotas: { control?.alternarNotas() },
                      copiarAviso: { control?.copiarAvisoNotas() })
        } else if let actividad = estado.actividad {
            switch actividad {
            case .dictado:
                DictadoIsla(estado: estado, hud: hud)
            case .aviso(let icono, let texto):
                let alerta = icono == "exclamationmark.triangle"
                AlertaAura(notch: estado.notch, tono: alerta ? .alerta : .verde, rotulo: alerta ? "Atención" : "Aviso", frase: texto) {
                    IconoSaltarin(simbolo: icono, color: (alerta ? TonoAura.alerta : TonoAura.verde).rotulo)
                } acciones: {
                    EmptyView()
                }
            case .cancion:
                AhoraSuena(estado: estado, musica: musica)
            case .evento(let titulo, let inicio, let color, let enlace):
                EventoIsla(estado: estado, titulo: titulo, inicio: inicio, color: color, enlace: enlace,
                           preparar: { control?.preparar(titulo: titulo, inicio: inicio) }) { control?.unirse($0) }
            case .carga(let porcentaje):
                CargaIsla(estado: estado, porcentaje: porcentaje)
            case .nivel(let tipo, let valor, let silencio, let salida):
                BarraNivel(estado: estado, tipo: tipo, valor: valor, silencio: silencio, salida: salida)
            case .salud(let titulo, let detalle, let grave):
                SaludIsla(estado: estado, titulo: titulo, detalle: detalle, grave: grave) { control?.abrirSalud() }
            case .claude(let sesion, let necesita, let duracion):
                ClaudeIsla(estado: estado, sesion: sesion, necesita: necesita, duracion: duracion) { control?.abrirClaude(sesion) }
            case .agente(let nombre, let alerta, let caido):
                AgenteIsla(estado: estado, nombre: nombre, alerta: alerta, caido: caido) { control?.verAgente(nombre) }
            case .foco(let titulo):
                FocoAvisoIsla(estado: estado, titulo: titulo,
                              responder: { control?.responderFoco($0) }, extender: { control?.extenderFoco($0) })
            case .notas(let titulo):
                NotasOfertaIsla(estado: estado, titulo: titulo) { control?.responderNotas($0) }
            case .cierre(let quedan):
                CierreIsla(estado: estado, quedan: quedan) { control?.responderCierre($0) }
            }
        } else if alas {
            Compacta(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude, foco: foco, notas: notas,
                     ahoraFijo: ahoraFijo, agentes: agentes, tablero: control?.tablero ?? tablero)
        }
    }
}

/// Una fila de contenido debajo del notch (para los avisos cortos), con la luz de su tono subiendo desde el borde.
struct FilaIsla<Contenido: View>: View {
    let notch: CGSize
    var tono: Tono?
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 11) { contenido() }
                .padding(.horizontal, 26)
                .frame(maxHeight: .infinity)
        }
        .background { if let tono { LuzBorde(tono: tono, fuerza: 0.4, alto: 0.95) } }
    }
}

/// Entrada de la isla: crece desde el notch, se enfoca y aparece (con `Halo.entrada`).
struct Enfoque: ViewModifier {
    let activo: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(activo ? 0.88 : 1, anchor: .top)
            .blur(radius: activo ? 10 : 0)
            .opacity(activo ? 0 : 1)
    }
}

/// Ícono que entra con un salto.
struct IconoSaltarin: View {
    let simbolo: String
    let color: Color
    @State private var salto = false

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .symbolEffect(.bounce, options: .nonRepeating, value: salto)
            .onAppear { salto = true }
    }
}

/// Entrada con rebote para imágenes (carátula, ícono de app).
struct Entrada: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(visible ? 1 : 0.4)
            .rotationEffect(.degrees(visible ? 0 : -12))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.06)) { visible = true }
            }
    }
}
