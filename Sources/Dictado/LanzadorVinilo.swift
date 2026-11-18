import AppKit
import DictadoKit
import SwiftUI

// La tarjeta de Música del lanzador: un disco de vinilo con la carátula de la canción como etiqueta. Gira a 33⅓ rpm mientras suena y se queda
// quieto al pausar; el brazo se apoya en el disco al sonar. Detrás, la carátula desenfocada con una deriva lenta; parado, el fondo de pantalla
// desenfocado. El desenfoque sale de una miniatura estirada (ver `Miniatura`), así que animarla cuesta casi nada. Con "reducir movimiento"
// todo queda quieto.

/// El disco: surcos finos, etiqueta con la carátula y agujero. Se dibuja una vez (`drawingGroup`) y solo se le aplica el giro.
struct DiscoVinilo: View {
    let caratula: NSImage?
    let lado: CGFloat

    /// Un número fijo entre 0 y 1 por surco: el mismo disco siempre, sin azar.
    private static func ruido(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 4.1414) * 43758.5453
        return x - x.rounded(.down)
    }

    var body: some View {
        ZStack {
            Canvas { ctx, tam in
                let c = CGPoint(x: tam.width / 2, y: tam.height / 2), radio = min(tam.width, tam.height) / 2
                func circulo(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
                ctx.fill(circulo(radio), with: .radialGradient(Gradient(colors: [Color(hex: 0x1B1B20), Color(hex: 0x0B0B0E), Color(hex: 0x040405)]),
                                                                center: c, startRadius: radio * 0.3, endRadius: radio))
                // Los surcos: muy finos (cada 0,8 pt) y de brillo irregular, como el corte real; entre pistas, bandas lisas.
                var r = radio * 0.40, i = 0
                while r < radio * 0.965 {
                    ctx.stroke(circulo(r), with: .color(.white.opacity(0.018 + 0.05 * Self.ruido(i))), lineWidth: 0.5)
                    r += 0.8
                    i += 1
                }
                for f in [0.54, 0.69, 0.83] {
                    ctx.stroke(circulo(radio * f), with: .color(.black.opacity(0.7)), lineWidth: max(1.2, radio * 0.024))
                    ctx.stroke(circulo(radio * f + radio * 0.02), with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
                // Cera muerta junto a la etiqueta y borde biselado.
                ctx.stroke(circulo(radio * 0.385), with: .color(.white.opacity(0.07)), lineWidth: 1)
                ctx.stroke(circulo(radio * 0.975), with: .color(.black.opacity(0.6)), lineWidth: 1.2)
                ctx.stroke(circulo(radio - 0.4), with: .color(.white.opacity(0.2)), lineWidth: 0.8)
                // Un par de marcas leves que giran con el disco: sin ellas no se ve que gira.
                var raya = Path()
                raya.addArc(center: c, radius: radio * 0.76, startAngle: .degrees(205), endAngle: .degrees(238), clockwise: false)
                ctx.stroke(raya, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
            }
            etiqueta
        }
        .frame(width: lado, height: lado)
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private var etiqueta: some View {
        let d = lado * 0.36
        return ZStack {
            Group {
                if let caratula {
                    Image(nsImage: caratula).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0x2B2B33), Color(hex: 0x111116)], startPoint: .top, endPoint: .bottom)
                        IconoSpotify().frame(width: d * 1.18, height: d * 1.18)
                    }
                }
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            // El papel de la etiqueta: un aro interior y un velo para que la carátula no brille más que el disco.
            if caratula != nil { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1).frame(width: d * 0.72, height: d * 0.72) }
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8).frame(width: d, height: d)
            Circle().fill(RadialGradient(colors: [Color(hex: 0x1A1A1F), Color(hex: 0x050506)], center: .center, startRadius: 0, endRadius: lado * 0.03))
                .frame(width: lado * (caratula == nil ? 0.035 : 0.06), height: lado * (caratula == nil ? 0.035 : 0.06))
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.7) }
        }
    }
}

/// El brillo del plástico: lóbulos de luz cónicos sobre los surcos (anisotrópicos). No giran con el disco: la luz no se mueve.
struct BrilloVinilo: View {
    let lado: CGFloat

    var body: some View {
        func lobulo(_ centro: Double, _ fuerza: Double, _ ancho: Double) -> [Gradient.Stop] {
            [.init(color: .clear, location: max(0, centro - ancho)),
             .init(color: .white.opacity(fuerza * 0.35), location: max(0, centro - ancho * 0.45)),
             .init(color: .white.opacity(fuerza), location: centro),
             .init(color: .white.opacity(fuerza * 0.35), location: min(1, centro + ancho * 0.45)),
             .init(color: .clear, location: min(1, centro + ancho))]
        }
        let paradas = lobulo(0.125, 0.30, 0.07) + lobulo(0.375, 0.10, 0.06) + lobulo(0.625, 0.30, 0.07) + lobulo(0.875, 0.10, 0.06)
        return Circle()
            .fill(AngularGradient(stops: [.init(color: .clear, location: 0)] + paradas + [.init(color: .clear, location: 1)], center: .center, angle: .degrees(-18)))
            .blendMode(.plusLighter)
            .mask { Circle().strokeBorder(.black, lineWidth: lado * 0.31) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// El brazo del tocadiscos: sombra sobre el disco, tubo con codo, cabezal y la aguja. Apoyado al sonar; al pausar se retira hacia fuera.
struct BrazoVinilo: View {
    let lado: CGFloat
    let apoyado: Bool
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let ancla = UnitPoint(x: 0.92, y: 0.08)
        Canvas { ctx, tam in
            let pivote = CGPoint(x: tam.width * 0.92, y: tam.height * 0.08)
            let codo = CGPoint(x: tam.width * 0.88, y: tam.height * 0.34)
            let aguja = CGPoint(x: tam.width * 0.77, y: tam.height * 0.50)
            var brazo = Path()
            brazo.move(to: pivote)
            brazo.addLine(to: codo)
            brazo.addQuadCurve(to: aguja, control: CGPoint(x: tam.width * 0.87, y: tam.height * 0.45))
            // Base del pivote: plato y eje.
            let rb = lado * 0.075
            ctx.fill(Path(ellipseIn: CGRect(x: pivote.x - rb, y: pivote.y - rb, width: rb * 2, height: rb * 2)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x4A4A54), Color(hex: 0x1C1C22)]), startPoint: CGPoint(x: pivote.x, y: pivote.y - rb), endPoint: CGPoint(x: pivote.x, y: pivote.y + rb)))
            ctx.stroke(Path(ellipseIn: CGRect(x: pivote.x - rb, y: pivote.y - rb, width: rb * 2, height: rb * 2)), with: .color(.white.opacity(0.25)), lineWidth: 0.8)
            // Tubo: borde oscuro, cuerpo claro y un filo de luz.
            ctx.stroke(brazo, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: lado * 0.032, lineCap: .round, lineJoin: .round))
            ctx.stroke(brazo, with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.7)]), startPoint: pivote, endPoint: aguja),
                       style: StrokeStyle(lineWidth: lado * 0.02, lineCap: .round, lineJoin: .round))
            ctx.stroke(brazo, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            let ra = lado * 0.012
            ctx.fill(Path(ellipseIn: CGRect(x: pivote.x - ra * 2, y: pivote.y - ra * 2, width: ra * 4, height: ra * 4)), with: .color(Color(hex: 0x0E0E12)))
            // Cabezal con la aguja.
            let cab = CGRect(x: aguja.x - lado * 0.032, y: aguja.y - lado * 0.012, width: lado * 0.064, height: lado * 0.082)
            ctx.fill(Path(roundedRect: cab, cornerRadius: 2.5), with: .linearGradient(Gradient(colors: [Color(white: 0.96), Color(white: 0.66)]), startPoint: CGPoint(x: cab.minX, y: cab.minY), endPoint: CGPoint(x: cab.maxX, y: cab.maxY)))
            ctx.stroke(Path(roundedRect: cab, cornerRadius: 2.5), with: .color(.black.opacity(0.4)), lineWidth: 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: aguja.x - 1, y: cab.maxY - 1, width: 2, height: 2.4)), with: .color(Color(hex: 0xE8E8EC)))
        }
        .frame(width: lado, height: lado)
        // La sombra cae sobre el disco: pegada y nítida si está apoyado, lejana y suave si está levantado.
        .shadow(color: .black.opacity(apoyado ? 0.55 : 0.32), radius: apoyado ? 2.5 : 8, x: apoyado ? -2 : -9, y: apoyado ? 3 : 12)
        .rotationEffect(.degrees(apoyado ? 0 : -24), anchor: ancla)
        .animation(sinMovimiento ? nil : .timingCurve(0.45, 0, 0.2, 1, duration: 0.95), value: apoyado)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TarjetaMusicaLanzador: View {
    let musica: Musica
    /// El fondo de pantalla (el que ya lee el lanzador): se ve desenfocado cuando no suena nada.
    let fondo: CGImage?
    /// En un render (sin tareas ni animación) las miniaturas se arman al momento.
    var simulado = false

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var giro = GiroDisco()
    @State private var deriva = false
    @State private var miniCaratula: CGImage?
    @State private var miniFondo: CGImage?

    private static let lado: CGFloat = 124
    private var sonando: Bool { musica.sonando && musica.hayPista }
    private var gira: Bool { sonando && !sinMovimiento }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: AuroraMedida.widgetRadio, style: .continuous)
        ZStack {
            fondoTarjeta
            contenido
        }
        .clipShape(forma)
        .overlay { forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
        .shadow(color: .black.opacity(AuroraMedida.widgetSombra.opacidad), radius: AuroraMedida.widgetSombra.radio, y: AuroraMedida.widgetSombra.y)
        .foregroundStyle(.white)
        .task(id: musica.caratula.map { ObjectIdentifier($0) }) {
            guard !simulado else { return }
            let c = musica.caratula
            miniCaratula = await Task.detached(priority: .utility) { c.flatMap { MiniaturaDeFondo.de($0) } }.value
        }
        .task(id: fondo.map { ObjectIdentifier($0) }) {
            guard !simulado else { return }
            let f = fondo
            miniFondo = await Task.detached(priority: .utility) { f.flatMap { MiniaturaDeFondo.de($0) } }.value
        }
        .onAppear {
            giro.cambiar(girando: gira, ahora: Date())
            ajustarDeriva(gira)
        }
        .onChange(of: gira) { _, ahora in
            giro.cambiar(girando: ahora, ahora: Date())
            ajustarDeriva(ahora)
        }
    }

    // MARK: Fondo

    private func ajustarDeriva(_ activa: Bool) {
        if activa {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { deriva = true }
        } else {
            withAnimation(.easeOut(duration: 1.2)) { deriva = false }
        }
    }

    private func estirada(_ cg: CGImage) -> some View {
        // Sobre un color transparente: la imagen no puede agrandar la tarjeta, solo llenarla.
        Color.clear.overlay { Image(decorative: cg, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill) }
    }

    /// Sonando: la carátula, con una deriva lenta. Parado: el fondo de pantalla. Siempre un velo oscuro para que se lea el texto.
    private var fondoTarjeta: some View {
        let mc = simulado ? musica.caratula.flatMap { MiniaturaDeFondo.de($0) } : miniCaratula
        let mf = simulado ? fondo.flatMap { MiniaturaDeFondo.de($0) } : miniFondo
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x1D2540), Color(hex: 0x0B0E1A)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let mf { estirada(mf).scaleEffect(1.15).saturation(1.2) }
            if sonando, let mc {
                estirada(mc)
                    .scaleEffect(deriva ? 1.6 : 1.35)
                    .offset(x: deriva ? 16 : -16, y: deriva ? -9 : 9)
                    .rotationEffect(.degrees(deriva ? 4 : -4))
                    .saturation(1.35)
                    .transition(.opacity)
            }
            Color.black.opacity(sonando ? 0.30 : 0.34)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.6), value: sonando)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: Contenido

    private var contenido: some View {
        VStack(spacing: 0) {
            Button { musica.irAOrigen() } label: {
                ZStack {
                    disco
                    BrazoVinilo(lado: Self.lado, apoyado: sonando)
                    // El icono real de Spotify (el de la app, no un dibujo) como sello de la fuente.
                    if musica.esSpotify {
                        IconoSpotify().frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1.5)
                            .frame(width: Self.lado, height: Self.lado, alignment: .bottomLeading)
                    }
                }
                .frame(width: Self.lado, height: Self.lado)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsadoAurora())
            .help("Ir a \(musica.nombreOrigen.isEmpty ? "Spotify" : musica.nombreOrigen)")
            .accessibilityLabel(musica.hayPista ? "\(musica.titulo), \(musica.artista)" : "Música")
            .accessibilityHint("Abre la app que suena")
            Spacer(minLength: 6)
            titulos
            Spacer(minLength: 6)
            if musica.hayPista { progreso }
            Spacer(minLength: 8)
            controles
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var disco: some View {
        let d = DiscoVinilo(caratula: musica.caratula, lado: Self.lado)
        ZStack {
            if gira {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in d.rotationEffect(.degrees(giro.angulo(en: ctx.date))) }
            } else {
                d.rotationEffect(.degrees(giro.angulo(en: Date())))
            }
            BrilloVinilo(lado: Self.lado)
        }
    }

    private var titulos: some View {
        let hay = musica.hayPista
        let sub: String = {
            if hay { return [musica.artista, musica.nombreOrigen].filter { !$0.isEmpty }.joined(separator: " · ") }
            if let u = musica.ultima { return "Última: " + u.titulo }
            return "Nada sonando"
        }()
        return VStack(spacing: 1) {
            Text(hay ? musica.titulo : "Spotify").font(.system(size: 13.5, weight: .bold)).tracking(-0.1).lineLimit(1).minimumScaleFactor(0.8).help(musica.titulo)
            Text(sub).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AuroraNotch.resumen).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var progreso: some View {
        if musica.sonando {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in barra(ctx.date) }
        } else {
            barra(Date())
        }
    }

    private func barra(_ ahora: Date) -> some View {
        let pos = musica.posicion(en: ahora)
        let f = musica.duracion > 0 ? min(1, max(0, pos / musica.duracion)) : 0
        func t(_ s: String) -> some View { Text(s).font(.system(size: 8.5, weight: .bold)).monospacedDigit().foregroundStyle(AuroraNotch.suave).fixedSize() }
        return HStack(spacing: 6) {
            t(Tiempo.reloj(pos))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: max(3, g.size.width * f))
                }
            }
            .frame(height: 3)
            t(musica.duracion > 0 ? "-" + Tiempo.reloj(max(0, musica.duracion - pos)) : "")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avance: \(Tiempo.reloj(pos)) de \(Tiempo.reloj(musica.duracion))")
    }

    private var controles: some View {
        let hay = musica.hayPista
        return HStack(spacing: 10) {
            ControlMusica(simbolo: "backward.fill", ayuda: "Anterior") { musica.anterior() }.disabled(!hay)
            Button { hay ? musica.alternar() : musica.abrirYReanudarSpotify() } label: {
                Image(systemName: sonando ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x111111))
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(.white) }
                    .contentShape(Circle())
            }
            .buttonStyle(PulsadoAurora())
            .help(hay ? (sonando ? "Pausar" : "Reproducir") : "Abrir Spotify y reanudar la música")
            .accessibilityLabel(hay ? (sonando ? "Pausar" : "Reproducir") : "Abrir Spotify y reproducir")
            ControlMusica(simbolo: "forward.fill", ayuda: "Siguiente") { musica.siguiente() }.disabled(!hay)
        }
        .frame(maxWidth: .infinity)
    }
}
