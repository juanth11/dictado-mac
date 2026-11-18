import AppKit
import DictadoKit
import SwiftUI

// Las piezas del Dock. Cada una lee un dato real de los modelos de la isla; ninguna tiene reloj propio salvo la cuenta del bloque
// de foco (una vez por segundo y solo si está corriendo). Todo lo que dibujan sale de Aurora (tokens, `OrbeAurora`, `Dial`,
// `Regla`, `NumeroPuntos`, `Prisma`).

// MARK: - Superficie de una pieza

/// La luz del borde: un resplandor del tono de la pieza que sube desde abajo (`.pz > .luz` del CSS). Estática.
struct LuzPieza: View {
    let tono: TonoAura

    var body: some View {
        Canvas { ctx, tam in
            let manchas: [(rx: Double, ry: Double, cx: Double, cy: Double, color: Color)] = [
                (0.58, 0.82, 0.24, 1.18, tono.luz.opacity(0.78)),
                (0.52, 0.78, 0.80, 1.12, tono.luz2.opacity(0.66)),
                (0.30, 0.40, 0.55, 1.00, .white.opacity(0.22)),
            ]
            for m in manchas {
                var c = ctx
                c.translateBy(x: tam.width * m.cx, y: tam.height * m.cy)
                c.scaleBy(x: tam.width * m.rx, y: tam.height * m.ry)
                c.fill(Path(CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                    Gradient(stops: [.init(color: m.color, location: 0), .init(color: m.color.opacity(0), location: 0.70)]),
                    center: .zero, startRadius: 0, endRadius: 1))
            }
        }
        .padding(-AuroraDock.luzExceso)
        .blur(radius: AuroraDock.luzDesenfoque)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// El bloque negro de 72 de alto: degradado de gris muy oscuro a negro, filo de luz arriba y una sombra corta. Con `accion`,
/// el clic en cualquier parte que no sea un botón de adentro la dispara y el puntero la agranda un poco (1,03).
struct PiezaDockMarco<Contenido: View>: View {
    let ancho: CGFloat
    var tono: TonoAura?
    let etiqueta: String
    var accion: (() -> Void)?
    var resaltada = false
    @ViewBuilder var contenido: () -> Contenido
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.lupaActiva) private var lupaActiva
    @State private var encima = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: AuroraDock.piezaRadio, style: .continuous)
        ZStack(alignment: .leading) {
            if let tono { LuzPieza(tono: tono) }
            contenido()
        }
        .frame(width: ancho, height: AuroraDock.piezaAlto, alignment: .leading)
        .background { forma.fill(LinearGradient(colors: [AuroraDock.piezaArriba, AuroraDock.piezaAbajo], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))) }
        .overlay { forma.strokeBorder(resaltada ? Color.white.opacity(0.25) : AuroraDock.piezaFilo, lineWidth: 1) }
        .overlay { forma.strokeBorder(LinearGradient(colors: [AuroraDock.piezaLuzArriba, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1) }
        .clipShape(forma)
        .shadow(color: .black.opacity(AuroraDock.piezaSombra.opacidad), radius: AuroraDock.piezaSombra.radio, y: AuroraDock.piezaSombra.y)
        .foregroundStyle(.white)
        .contentShape(forma)
        .onTapGesture { accion?() }
        .scaleEffect(encima && accion != nil && !sinMovimiento && !lupaActiva ? 1.03 : 1)
        .animation(AuroraMovimiento.puntero, value: encima)
        .onHover { encima = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(etiqueta)
        .accessibilityAddTraits(accion != nil ? .isButton : [])
        .accessibilityAction(.default) { accion?() }
    }
}

/// Insignia: círculo oscuro con aro del tono; `lleno` es la acción principal (relleno del tono, glifo oscuro).
struct InsigniaDock: View {
    let simbolo: String
    let tono: TonoAura
    var lleno = false
    var lado = AuroraDock.insignia
    let ayuda: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: lado * 0.42, weight: .bold))
                .foregroundStyle(lleno ? Color(hex: 0x04210F) : tono.rotulo)
                .frame(width: lado, height: lado)
                .background {
                    if lleno {
                        Circle().fill(LinearGradient(colors: [tono.luz2.mix(with: .white, by: 0.35), tono.luz2], startPoint: .top, endPoint: .bottom))
                            .shadow(color: tono.luz2.opacity(0.55), radius: 8)
                    } else {
                        Circle().fill(RadialGradient(colors: [tono.luz.opacity(0.34).mix(with: Color(hex: 0x16161A), by: 0.4), Color(hex: 0x0A0A0C)],
                                                     center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: lado * 0.75))
                            .overlay { Circle().strokeBorder(tono.luz2.opacity(0.55), lineWidth: 1) }
                            .shadow(color: tono.luz2.opacity(0.35), radius: 7)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

/// Botón redondo de vidrio de 27 (los cuatro de la música).
struct BotonVidrioDock: View {
    let simbolo: String
    let ayuda: String
    var lado = AuroraDock.botonVidrio
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: lado, height: lado)
                .background { Circle().fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.09)], startPoint: .top, endPoint: .bottom)) }
                .overlay { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

enum TonosPieza {
    static let agenda = TonoAura(t: 0x1F3FA8, t2: 0x5B93FF)
    static let agentes = TonoAura(t: 0xF2784A, t2: 0xC05CFF)
    static let trabaja = TonoAura(t: 0x3A3FB8, t2: 0x8FA6FF)
    static let dictar = TonoAura(t: 0x4D6BFF, t2: 0xFF7A45)
    static let foco = TonoAura(t: 0xFF9F0A, t2: 0xFF4D3A)
    static let musica = TonoAura(t: 0x0F5A3A, t2: 0x2FE07A)
    static let reglaBlanca = Tono(base: .white.opacity(0.9), claro: .white)
    static let ambar = Color(hex: 0xFFB02E)
    static let clima = TonoAura(t: 0xFFB347, t2: 0xFF5A3C)
}

// MARK: - Qué pieza va

struct PiezaDockVista: View {
    let colocada: PiezaColocada
    let estado: EstadoDock
    let tonos: TonosDock

    var body: some View {
        let ancho = CGFloat(colocada.ancho)
        switch colocada.pieza {
        case .reloj: RelojPieza(estado: estado, ancho: ancho)
        case .agenda: AgendaPieza(estado: estado, ancho: ancho, compacta: colocada.modo == .compacta)
        case .agentes: AgentesPieza(estado: estado, ancho: ancho, compacta: colocada.modo == .compacta)
        case .tareas: TareasPieza(estado: estado, ancho: ancho)
        case .plan: PlanPieza(estado: estado, ancho: ancho)
        case .dictar: DictarPieza(estado: estado, ancho: ancho)
        case .foco: FocoPieza(estado: estado, ancho: ancho, compacta: colocada.modo == .compacta)
        case .musica: MusicaPieza(estado: estado, ancho: ancho, compacta: colocada.modo == .compacta)
        case .mac: MacPieza(estado: estado, ancho: ancho)
        case .bateria: BateriaPieza(estado: estado, ancho: ancho)
        case .fecha: FechaPieza(estado: estado, ancho: ancho)
        case .papelera: PapeleraPieza(estado: estado, ancho: ancho)
        case .clima: ClimaPieza(estado: estado, ancho: ancho)
        case .lanzador: LanzadorPieza(estado: estado, ancho: ancho)
        case .abiertas: AbiertasMosaico(estado: estado)
        case .finder: EmptyView()
        case .app(let clave): if let a = estado.app(clave) { AppMosaico(app: a, estado: estado) }
        case .grupo(let nombre): GrupoMosaico(nombre: nombre, estado: estado)
        case .carpeta(let ruta): CarpetaMosaico(ruta: ruta, estado: estado, tonos: tonos)
        case .hueco: Color.clear.frame(width: ancho, height: AuroraDock.piezaAlto)
        }
    }
}

// MARK: - Reloj y fecha

struct RelojPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let ahora = estado.ahora
        let c = Calendar.current
        let t = RelojTarjetas.partes(hora24: c.component(.hour, from: ahora), minuto: c.component(.minute, from: ahora))
        PiezaDockMarco(ancho: ancho, etiqueta: "Reloj, \(t.hora):\(t.minuto) \(t.periodo). Abre la agenda", accion: { estado.acciones.abrirPestana(.agenda) }) {
            HStack(spacing: AuroraDockPila.tarjetaSeparacion) {
                TarjetaFlip(texto: t.hora, rotulo: t.periodo)
                TarjetaFlip(texto: t.minuto)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tarjetas que se voltean

/// Una tarjeta del reloj: la cara de arriba cae y deja ver la de abajo (el reloj de tarjetas de los aeropuertos). Con "Reducir
/// movimiento" el cambio es directo. En reposo no hay nada animado: solo se anima en el instante en que cambia el texto.
struct TarjetaFlip: View {
    let texto: String
    var rotulo: String?
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var anterior: String?
    @State private var fase = Fase.reposo
    @State private var angulo = 0.0

    enum Fase { case reposo, cae, sube }

    private var ancho: CGFloat { AuroraDockPila.tarjetaAncho }
    private var alto: CGFloat { AuroraDockPila.tarjetaAlto }

    var body: some View {
        let viejo = anterior ?? texto
        ZStack {
            // Debajo: lo que se ve quieto. Arriba, siempre lo nuevo; abajo, lo viejo hasta que la hoja nueva lo tapa.
            VStack(spacing: 0) {
                mitad(texto, arriba: true)
                mitad(fase == .reposo ? texto : viejo, arriba: false)
            }
            if fase == .cae {
                mitad(viejo, arriba: true)
                    .overlay { Rectangle().fill(.black.opacity(0.45 * abs(angulo) / 90)) }
                    .rotation3DEffect(.degrees(angulo), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.45)
                    .frame(width: ancho, height: alto, alignment: .top)
            }
            if fase == .sube {
                mitad(texto, arriba: false)
                    .overlay { Rectangle().fill(.black.opacity(0.45 * abs(angulo) / 90)) }
                    .rotation3DEffect(.degrees(angulo), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.45)
                    .frame(width: ancho, height: alto, alignment: .bottom)
            }
            // La bisagra: una línea oscura y un filo de luz debajo.
            VStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.7)).frame(height: 1)
                Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            }
            .frame(width: ancho, height: 2)
        }
        .frame(width: ancho, height: alto)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        .onChange(of: texto) { viejo, nuevo in volteo(de: viejo, a: nuevo) }
        .accessibilityHidden(true)
    }

    private func volteo(de viejo: String, a nuevo: String) {
        guard !sinMovimiento else { anterior = nil; fase = .reposo; return }
        anterior = viejo
        fase = .cae
        angulo = 0
        withAnimation(.easeIn(duration: AuroraDockPila.volteoIda)) { angulo = -90 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(AuroraDockPila.volteoIda))
            fase = .sube
            angulo = 90
            withAnimation(.easeOut(duration: AuroraDockPila.volteoVuelta)) { angulo = 0 }
            try? await Task.sleep(for: .seconds(AuroraDockPila.volteoVuelta))
            fase = .reposo
            anterior = nil
        }
    }

    /// La mitad de arriba o de abajo de la tarjeta con ese texto.
    private func mitad(_ t: String, arriba: Bool) -> some View {
        TarjetaCara(texto: t, rotulo: rotulo)
            .frame(width: ancho, height: alto)
            .frame(height: alto / 2, alignment: arriba ? .top : .bottom)
            .clipped()
    }
}

/// La tarjeta entera: fondo gris oscuro en dos tonos (arriba un poco más claro), la cifra condensada con degradado y, si lo trae,
/// el rótulo (AM/PM) abajo a la izquierda. Se dibuja estática y `TarjetaFlip` la corta en mitades.
struct TarjetaCara: View {
    let texto: String
    var rotulo: String?

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: AuroraDockPila.tarjetaRadio, style: .continuous)
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(hex: 0x303034), Color(hex: 0x262629)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color(hex: 0x1E1E21), Color(hex: 0x19191B)], startPoint: .top, endPoint: .bottom)
            }
            Text(texto)
                .font(AuroraDockPila.tarjetaCifra).monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.64)], startPoint: .top, endPoint: .bottom))
                .lineLimit(1).minimumScaleFactor(0.8)
                .offset(y: -1)
            if let rotulo {
                Text(rotulo).font(AuroraDockPila.tarjetaPeriodo).tracking(0.6).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 5).padding(.bottom, 4)
            }
        }
        .clipShape(forma)
        .overlay { forma.strokeBorder(.white.opacity(0.07), lineWidth: 1) }
    }
}

struct FechaPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        return f
    }()

    private func texto(_ patron: String, _ fecha: Date) -> String {
        Self.formato.dateFormat = patron
        return Self.formato.string(from: fecha).replacingOccurrences(of: ".", with: "").capitalized
    }

    var body: some View {
        let ahora = estado.ahora
        let dia = Calendar.current.component(.day, from: ahora)
        let semana = texto("EEE", ahora), mes = texto("MMM", ahora)
        PiezaDockMarco(ancho: ancho, etiqueta: "Hoy es \(semana) \(dia) de \(mes)", accion: { AbrirCalendario.dia(ahora) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(semana.uppercased()).foregroundColor(AuroraNotch.rojoHoy))\(Text(" · " + mes.uppercased()).foregroundColor(.white.opacity(0.5)))")
                    .font(AuroraDock.rotulo).tracking(AuroraDock.rotuloInterletra).lineLimit(1)
                Text("\(dia)").font(AuroraDock.cifraMedia).monospacedDigit()
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Agenda

struct AgendaPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    let compacta: Bool

    var body: some View {
        let ahora = estado.ahora
        if let e = estado.agenda.proximaReunion(ahora: ahora) {
            reunion(e, ahora)
        } else {
            hueco(ahora)
        }
    }

    private func quienes(_ e: Agenda.Evento) -> String {
        let nombres = e.invitados.map { String($0.split(separator: " ").first ?? "") }.filter { !$0.isEmpty }
        guard let primero = nombres.first else { return e.enlace.map { Tiempo.servicio($0.host ?? "") } ?? "" }
        return nombres.count > 1 ? "\(primero) y \(nombres.count - 1) más" : primero
    }

    private func reunion(_ e: Agenda.Evento, _ ahora: Date) -> some View {
        let enCurso = e.inicio <= ahora
        let cuenta = CuentaRegresiva.texto(hasta: enCurso ? e.fin : e.inicio, desde: ahora)
        let tono = TonosPieza.agenda
        let etiqueta = (enCurso ? "Termina en " : "Empieza en ") + (cuenta.map { $0.texto + " " + $0.unidad } ?? "0 min") + ": " + e.titulo
        return PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: etiqueta, accion: { AbrirCalendario.evento(e) }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza(enCurso ? "Termina en" : "Empieza en", color: tono.rotulo)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        NumeroPuntos(texto: cuenta?.texto ?? "0", color: Color(hex: 0xCFE0FF))
                        Text(cuenta?.unidad ?? "min").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue)
                    }
                }
                if !compacta {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.titulo).font(AuroraDock.titulo).lineLimit(1)
                        Text([Frase.hora(e.inicio) + " – " + Frase.hora(e.fin), quienes(e)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).lineLimit(1)
                        LineaDiaDock(estado: estado, ahora: ahora, tono: tono).frame(width: 132, height: 8).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(e.titulo).font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let enlace = e.enlace {
                    InsigniaDock(simbolo: "video.fill", tono: TonoAura.verde, lleno: true, ayuda: "Unirse a la videollamada: \(e.titulo)") { estado.acciones.unirse(enlace) }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
    }

    /// Sin reunión por delante hoy: el próximo hueco libre de la agenda (los mismos huecos que ofrece la isla).
    private func hueco(_ ahora: Date) -> some View {
        let ocupados = estado.agenda.eventos.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let libre = Huecos.libres(ocupados: ocupados, desde: ahora, config: Ajustes().huecos).first
        let tono = TonosPieza.agenda
        let titulo: String, detalle: String
        if let h = libre {
            let m = Int(h.minutos.rounded())
            titulo = "Libre " + (m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min")
            detalle = FormatoHuecos.corto(h, ahora: ahora)
        } else {
            titulo = "Agenda libre"
            detalle = "Sin huecos en los próximos días"
        }
        return PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: "Próximo hueco libre: \(titulo), \(detalle)", accion: { AbrirCalendario.dia(ahora) }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza("Próximo hueco", color: tono.rotulo)
                    Text(titulo).font(AuroraDock.titulo).lineLimit(1)
                    if !compacta { Text(detalle).font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InsigniaDock(simbolo: "calendar", tono: tono, ayuda: "Abrir el día en el calendario") { AbrirCalendario.dia(ahora) }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
    }
}

/// El día laboral como línea: las reuniones en el tono de la pieza y la marca roja de "ahora" (`.linea-t` del CSS).
struct LineaDiaDock: View {
    let estado: EstadoDock
    let ahora: Date
    let tono: TonoAura

    var body: some View {
        let config = Ajustes().huecos
        let ocupados = estado.agenda.eventos(del: ahora).filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let linea = LineaDelDia.armar(dia: ahora, eventos: ocupados, libre: nil, ahora: ahora, inicioHora: config.inicioMin / 60, finHora: config.finMin / 60)
        Canvas { ctx, tam in
            var x: CGFloat = 0
            while x < tam.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: tam.height)), with: .color(.white.opacity(0.2)))
                x += 11
            }
            for t in linea.eventos {
                let r = CGRect(x: tam.width * t.inicio, y: 2, width: max(3, tam.width * t.ancho), height: tam.height - 4)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(tono.luz2)) // grid: ok dibujo del lienzo
            }
            if let a = linea.ahora {
                ctx.fill(Path(CGRect(x: tam.width * a, y: -2, width: 1.5, height: tam.height + 4)), with: .color(AuroraNotch.rojoHoy)) // grid: ok dibujo del lienzo
            }
        }
        .shadow(color: tono.luz2.opacity(0.5), radius: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Agentes y tareas

struct AgentesPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    let compacta: Bool

    var body: some View {
        let claude = estado.claude
        let cuentas = CuentasAgentes.de(claude: claude, agentes: estado.agentes, tablero: estado.tablero, ahora: estado.ahora)
        let espera = cuentas.esperan
        let trabajando = cuentas.trabajando
        let total = estado.tablero?.vigente(ahora: estado.ahora).map { max(1, $0.enCurso.count) } ?? max(1, claude.sesiones.count)
        let tono = espera > 0 ? TonosPieza.agentes : TonosPieza.trabaja
        let titulo = espera == 0 ? (trabajando > 0 ? "\(trabajando) trabajando" : "Todo en calma") : (espera == 1 ? "1 espera tu sí" : "\(espera) esperan tu sí")
        PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: "Agentes: \(trabajando) trabajando, \(espera) esperan tu sí", accion: { estado.acciones.abrirPestana(.agentes) }) {
            HStack(spacing: 12) {
                Dial(lado: 54, valor: Double(trabajando) / Double(total),
                     colores: espera > 0 ? [Color(hex: 0xF2784A), Color(hex: 0xC05CFF)] : [.white.opacity(0.8), .white], marcas: 36, anillo: 5, brillo: 0.25) {
                    NumeroFino(texto: "\(trabajando)", tamano: 21, peso: .thin)
                }
                if !compacta {
                    VStack(alignment: .leading, spacing: 4) {
                        RotuloPieza("Agentes", color: tono.rotulo)
                        if espera > 0 {
                            Text("\(Text("\(espera)").foregroundColor(tono.rotulo))\(espera == 1 ? " espera tu sí" : " esperan tu sí")").font(AuroraDock.titulo).lineLimit(1)
                        } else {
                            Text(titulo).font(AuroraDock.titulo).lineLimit(1)
                        }
                        Liquido(valor: Double(trabajando) / Double(total), tono: Tono(base: tono.luz, claro: tono.luz2), alto: 5)
                            .frame(width: 104)
                    }
                }
            }
            // Angosta, el círculo va en el centro de la pieza (antes quedaba corrido a la izquierda por el relleno de 8 y 12).
            .padding(.leading, compacta ? 0 : 8)
            .padding(.trailing, compacta ? 0 : 12)
            .frame(maxWidth: compacta ? .infinity : nil, alignment: .center)
        }
        // La pieza se ve: pide el Tablero (como mucho una vez por minuto) y ya no pide nada cuando el Dock se esconde.
        .onAppear { if estado.hayTablero { estado.tablero?.refrescar() } }
    }
}

struct TareasPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let t = estado.tareas
        let abiertas = t?.abiertas ?? 0, hechas = t?.hechasHoy ?? 0, total = t?.total ?? 0
        PiezaDockMarco(ancho: ancho, etiqueta: "Tareas de hoy: \(abiertas) abiertas, \(hechas) hechas", accion: { estado.acciones.abrirPestana(.tareas) }) {
            VStack(alignment: .leading, spacing: 4) {
                RotuloPieza("Tareas hoy")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(abiertas)").font(AuroraDock.cifraMedia).monospacedDigit()
                    Text("\(hechas) hechas").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue)
                }
                Regla(valor: total > 0 ? Double(hechas) / Double(total) : 0, tono: TonosPieza.reglaBlanca, cuantas: 16, alto: 7).frame(width: 68)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Dictar y foco

struct DictarPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    /// La onda en reposo: una forma fija, sin tiempo (no anima nada).
    @State private var reposo: EstadoHUD = {
        let h = EstadoHUD()
        h.fase = .escuchando
        h.nivel = 0.35
        return h
    }()

    var body: some View {
        let dictando = estado.estadoIsla.dictando
        PiezaDockMarco(ancho: ancho, tono: TonosPieza.dictar, etiqueta: dictando ? "Dictando. Toca para terminar" : "Dictar. Toca para empezar", accion: estado.acciones.dictar) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RotuloPieza(dictando ? "Escuchando" : "Dictar", color: dictando ? TonosPieza.dictar.rotulo : AuroraNotch.sutil)
                    Spacer(minLength: 4)
                    Text("⌥ ESPACIO").font(AuroraDock.tecla).tracking(0.3).foregroundStyle(.white.opacity(0.45))
                }
                Prisma(estado: dictando ? estado.hud : reposo, t: 0.7, conHalo: false)
                    .frame(width: ancho, height: 40)
                    .padding(.horizontal, -12)
            }
            .padding(.horizontal, 12)
        }
    }
}

struct FocoPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    let compacta: Bool

    var body: some View {
        let tono = TonosPieza.foco
        if let b = estado.foco.activo {
            if estado.foco.pausado {
                cuenta(b, ahora: Date())
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in cuenta(b, ahora: ctx.date) }   // solo mientras corre y se ve
            }
        } else {
            PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: "Foco: empezar un bloque de 25 minutos", accion: { estado.foco.empezar("", minutos: 25) }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        RotuloPieza("Foco", color: tono.rotulo)
                        if !compacta {
                            Text("Empezar").font(AuroraDock.titulo)
                            Text("25 min").font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave)
                        } else {
                            Text("25 min").font(AuroraDock.titulo)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    InsigniaDock(simbolo: "play.fill", tono: tono, lado: AuroraDock.insigniaChica, ayuda: "Empezar un bloque de foco de 25 minutos") { estado.foco.empezar("", minutos: 25) }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
            }
        }
    }

    private func cuenta(_ b: Foco.Bloque, ahora: Date) -> some View {
        let tono = TonosPieza.foco
        let falta = estado.foco.restante(en: ahora)
        let pausado = estado.foco.pausado
        return PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: "Foco: \(b.titulo), quedan \(Tiempo.reloj(falta))" + (pausado ? ", en pausa" : "")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza((pausado ? "En pausa · " : "Foco · ") + b.titulo, color: tono.rotulo)
                    NumeroPuntos(texto: Tiempo.reloj(falta), color: TonosPieza.ambar)
                    if !compacta { Regla(valor: estado.foco.fraccion(en: ahora), tono: .ambar, cuantas: 24, alto: 8).frame(width: 96) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InsigniaDock(simbolo: pausado ? "play.fill" : "pause.fill", tono: tono, lado: AuroraDock.insigniaChica,
                             ayuda: pausado ? "Reanudar el bloque de foco" : "Pausar el bloque de foco") {
                    if pausado { estado.foco.reanudar() } else { estado.foco.pausar() }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
    }
}

// MARK: - Música

struct MusicaPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    let compacta: Bool

    var body: some View {
        let m = estado.musica
        let tono = m.hayPista ? TonoAura.de(m.acento) : TonosPieza.musica
        let ladoCaratula = AuroraDock.piezaAlto
        PiezaDockMarco(ancho: ancho, tono: tono, etiqueta: m.hayPista ? "Suena \(m.titulo), \(m.artista)" : "No suena nada") {
            HStack(spacing: 12) {
                caratula(m, lado: ladoCaratula)
                if compacta {
                    Spacer(minLength: 0)
                    BotonVidrioDock(simbolo: m.sonando ? "pause.fill" : "play.fill", ayuda: m.sonando ? "Pausar" : "Reproducir") { m.alternar() }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        if m.hayPista {
                            Text(m.titulo).font(AuroraDock.titulo).lineLimit(1)
                            Text(m.artista.isEmpty ? m.nombreOrigen : m.artista).font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).lineLimit(1)
                            ProgresoAurora(musica: m).padding(.top, 4)
                        } else {
                            RotuloPieza("Música", color: tono.rotulo)
                            Text("Nada sonando").font(AuroraDock.titulo).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    controles(m)
                }
            }
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder private func caratula(_ m: Musica, lado: CGFloat) -> some View {
        Group {
            if m.hayPista, let imagen = m.caratula {
                Image(nsImage: imagen).resizable().scaledToFill().frame(width: lado, height: lado).clipped()
            } else {
                Image(systemName: "music.note").font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.4)).frame(width: lado, height: lado)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }

    private func controles(_ m: Musica) -> some View {
        let saltos = !(m.tieneSiguiente || !m.puedeSaltar)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                BotonVidrioDock(simbolo: saltos ? "gobackward.10" : "backward.fill", ayuda: saltos ? "Atrasar 10 segundos" : "Anterior") { saltos ? m.avanzar(-10) : m.anterior() }
                BotonVidrioDock(simbolo: m.sonando ? "pause.fill" : "play.fill", ayuda: m.sonando ? "Pausar" : "Reproducir") { m.alternar() }
            }
            HStack(spacing: 4) {
                BotonVidrioDock(simbolo: saltos ? "goforward.10" : "forward.fill", ayuda: saltos ? "Adelantar 10 segundos" : "Siguiente") { saltos ? m.avanzar(10) : m.siguiente() }
                BotonVidrioDock(simbolo: "arrow.up.forward.app", ayuda: "Ir a la app que suena") { m.irAOrigen() }
            }
        }
    }
}

// MARK: - Mac y batería

struct MacPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    private func orbe(_ g: Gravedad) -> TonoOrbe { g == .bien ? .calma : (g == .atento ? .atento : .mal) }
    private func gigas(_ bytes: Double) -> String {
        let g = bytes / 1e9
        return g < 10 ? String(format: "%.1f", g).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f", g)
    }

    var body: some View {
        let s = estado.salud
        PiezaDockMarco(ancho: ancho, etiqueta: "Mac: procesador \(Int(s.cpu * 100)) %, memoria \(gigas(s.memoriaUsada)) GB, \(gigas(s.discoLibre)) GB libres. Abre Mac",
                       accion: { estado.acciones.abrirPestana(.mac) }) {
            HStack(spacing: 4) {
                OrbeAurora(titulo: "CPU", numero: String(format: "%.0f", s.cpu * 100), unidad: "%", valor: s.cpu, tono: orbe(s.gravedadCPU), cifra: 14, lado: AuroraDock.orbeMac)
                OrbeAurora(titulo: "RAM", numero: gigas(s.memoriaUsada), unidad: "GB", valor: s.memoriaUsada / max(1, s.memoriaTotal), tono: orbe(s.gravedadMemoria),
                           cifra: 14, lado: AuroraDock.orbeMac)
                OrbeAurora(titulo: "Libres", numero: gigas(s.discoLibre), unidad: "GB", valor: s.discoLibre / max(1, s.discoTotal), tono: orbe(s.gravedadDisco),
                           cifra: 14, lado: AuroraDock.orbeMac)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct BateriaPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let b = estado.bateria
        let tono: TonoOrbe = b.porcentaje <= 10 ? .mal : (b.porcentaje <= 20 ? .atento : .calma)
        PiezaDockMarco(ancho: ancho, etiqueta: "Batería al \(b.porcentaje) %" + (b.cargando ? ", cargando" : "")) {
            OrbeAurora(titulo: b.cargando ? "Carga" : "Batería", numero: "\(b.porcentaje)", unidad: "%", valor: Double(b.porcentaje) / 100, tono: tono, cifra: 15,
                       lado: AuroraDock.orbeBateria)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Apps

struct AppMosaico: View {
    let app: EntradaApp
    let estado: EstadoDock
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    @State private var ancla: CGFloat = 0
    private var abierta: Bool { app.bundleID.map { estado.abiertas.abiertas.contains($0) } ?? false }

    var body: some View {
        PiezaDockMarco(ancho: 72, etiqueta: app.nombre + (abierta ? ", abierta" : ""), accion: { AppsAbiertasDock.abrir(app) }) {
            Group {
                if let icono = estado.iconos[app.id] {
                    Image(nsImage: icono).resizable().interpolation(.high).frame(width: AuroraDock.icono, height: AuroraDock.icono)
                } else {
                    RoundedRectangle(cornerRadius: AuroraDock.icono * AuroraMedida.iconoRadioProporcion, style: .continuous)
                        .fill(.white.opacity(0.06)).frame(width: AuroraDock.icono, height: AuroraDock.icono)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if abierta {
                Capsule().fill(.white.opacity(0.8)).frame(width: AuroraDock.indicador.width, height: AuroraDock.indicador.height)
                    .offset(y: AuroraDock.indicadorBajo).accessibilityHidden(true)
            }
        }
        .onHover { dentro in
            if !abierta { return }
            if dentro { estado.acciones.ventanasProgramar(app, ancla, false) } else { estado.acciones.ventanasCancelar() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("dock")).midX } action: { ancla = $0; estado.anclasApp[app.id] = $0 }
        .help(app.nombre)
        .menuAppDock(app, estado: estado)
    }
}

/// Las apps abiertas que no están fijas: una pila de 2 × 2 iconos que al tocarla se despliega con todas (como las que el Dock
/// original dejaba a la derecha).
struct AbiertasMosaico: View {
    let estado: EstadoDock
    @State private var ancla: CGFloat = 0

    var body: some View {
        let apps = estado.abiertasNoFijas
        let lado: CGFloat = 24
        PiezaDockMarco(ancho: 72, etiqueta: "Abiertas, \(apps.count) apps", accion: { estado.acciones.desplegar("abiertas", ancla) }, resaltada: estado.desplegado == "abiertas") {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(lado), spacing: 4), count: 2), spacing: 4) {
                ForEach(Array(apps.prefix(4))) { a in
                    if let i = estado.iconos[a.id] {
                        Image(nsImage: i).resizable().interpolation(.high).frame(width: lado, height: lado)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)).frame(width: lado, height: lado)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.8)).frame(width: AuroraDock.indicador.width, height: AuroraDock.indicador.height)
                .offset(y: AuroraDock.indicadorBajo).accessibilityHidden(true)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("dock")).midX } action: { ancla = $0 }
        .help("Apps abiertas")
    }
}

/// Un grupo de apps: rejilla de 3 × 3 iconos pequeños que, al tocarla, se despliega hacia arriba.
struct GrupoMosaico: View {
    let nombre: String
    let estado: EstadoDock
    @State private var ancla: CGFloat = 0

    var body: some View {
        let apps = Array(estado.appsDelGrupo(nombre).prefix(9))
        let clave = "grupo:" + nombre
        let lado = AuroraDock.miniGrupo
        PiezaDockMarco(ancho: 72, etiqueta: "Grupo \(nombre), \(apps.count) apps", accion: { estado.acciones.desplegar(clave, ancla) }, resaltada: estado.desplegado == clave) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(lado), spacing: AuroraDock.miniGrupoSeparacion), count: 3), spacing: AuroraDock.miniGrupoSeparacion) {
                ForEach(apps) { a in
                    if let i = estado.iconos[a.id] {
                        Image(nsImage: i).resizable().interpolation(.high).frame(width: lado, height: lado)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.08)).frame(width: lado, height: lado)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("dock")).midX } action: { ancla = $0 }
        .help(nombre)
    }
}

// MARK: - Carpetas del Finder

struct CarpetaMosaico: View {
    let ruta: String
    let estado: EstadoDock
    let tonos: TonosDock
    @State private var ancla: CGFloat = 0
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.lupaActiva) private var lupaActiva

    var body: some View {
        let clave = "carpeta:" + ruta
        let deFinder = estado.esCarpetaDeFinder(ruta)
        let contenido = ContenidoCarpetas.compartido.datos[ruta]
        CarpetaVidrioEscalada(nombre: (ruta as NSString).lastPathComponent, detalle: contenido.map { ContenidoCarpetas.textoElementos($0.elementos) } ?? "",
                              foto: contenido?.foto, ancho: AuroraDock.carpeta.width, texto: 0.125)
            .frame(width: AuroraDock.carpeta.width, height: AuroraDock.carpeta.height)
            .frame(width: 72, height: AuroraDock.piezaAlto)
            .task { ContenidoCarpetas.compartido.pedir(ruta) }
            .overlay(alignment: .bottom) {
                if deFinder {
                    Capsule().fill(.white.opacity(0.8)).frame(width: AuroraDock.indicador.width, height: AuroraDock.indicador.height)
                        .offset(y: AuroraDock.indicadorBajo).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { estado.acciones.desplegar(clave, ancla) }
            .scaleEffect((encima || estado.desplegado == clave) && !sinMovimiento && !lupaActiva ? 1.06 : 1)
            .animation(AuroraMovimiento.puntero, value: encima)
            .onHover { encima = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("dock")).midX } action: { ancla = $0 }
            .help((ruta as NSString).lastPathComponent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Carpeta \((ruta as NSString).lastPathComponent)" + (deFinder ? ", abierta en el Finder" : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { estado.acciones.desplegar(clave, ancla) }
            .contextMenu {
                Button("Abrir en Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: ruta, isDirectory: true)) }
            }
    }
}

// MARK: - Papelera

struct PapeleraPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.lupaActiva) private var lupaActiva

    var body: some View {
        let icono = NSImage(named: estado.papeleraLlena ? NSImage.trashFullName : NSImage.trashEmptyName)
        Group {
            if let icono { Image(nsImage: icono).resizable().interpolation(.high).scaledToFit() } else { Image(systemName: "trash").font(.system(size: 28)) }
        }
        .frame(width: 60, height: 60)
        .frame(width: ancho, height: AuroraDock.piezaAlto)
        .contentShape(Rectangle())
        .onTapGesture { PapeleraDock.abrir() }
        .scaleEffect(encima && !sinMovimiento && !lupaActiva ? 1.06 : 1)
        .animation(AuroraMovimiento.puntero, value: encima)
        .onHover { encima = $0 }
        .help("Papelera")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Papelera" + (estado.papeleraLlena ? ", con elementos" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { PapeleraDock.abrir() }
    }
}

// MARK: - Clima

/// El clima de ahora: lugar y estado en el rótulo, la temperatura grande y la máxima de hoy, y el símbolo del estado. Sin datos (sin red,
/// sin lugar) muestra la fecha. Lee el mismo modelo que el lanzador (`ClimaModelo`) y avisa cuando se ve y cuando se esconde.
struct ClimaPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let ahora = estado.ahora
        let v = estado.clima.vigente(ahora: ahora)
        PiezaDockMarco(ancho: ancho, tono: TonosPieza.clima, etiqueta: "Clima: " + estado.clima.texto(ahora: ahora)) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((v.map { $0.lugar + " · " + ClimaPuro.descripcion(codigo: $0.clima.codigo) } ?? "Hoy").uppercased())
                        .font(AuroraDock.rotulo).tracking(AuroraDock.rotuloInterletra).foregroundStyle(AuroraDock.textoSuave)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(v.map { "\($0.clima.temperatura)°" } ?? "\(Calendar.current.component(.day, from: ahora))")
                            .font(AuroraDock.cifraMedia).monospacedDigit().lineLimit(1)
                        if let max = v?.clima.maxima {
                            Text("máx \(max)").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let v {
                    Image(systemName: ClimaPuro.simbolo(codigo: v.clima.codigo, esDia: v.clima.esDia))
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(TonosPieza.ambar)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 12).padding(.trailing, 12)
        }
        .onAppear { estado.clima.alMostrar() }
        .onDisappear { estado.clima.alOcultar() }
    }
}

// MARK: - Lanzador

/// Abre (o cierra) el lanzador a pantalla completa: el icono de Aplicaciones (3 × 3 minis; los iconos reales de las apps más usadas, si ya se leyeron).
struct LanzadorPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let reales: [NSImage?] = estado.apps.usadas.prefix(9).map { estado.apps.iconos[$0.id] }
        PiezaDockMarco(ancho: ancho, etiqueta: "Lanzador de apps", accion: { estado.acciones.abrirLanzador() }) {
            IconoAplicaciones(lado: AuroraDock.piezaAlto - 6, reales: reales, placa: false)
                .frame(maxWidth: .infinity)
        }
        .help("Lanzador de apps")
    }
}
