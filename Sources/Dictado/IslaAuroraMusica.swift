import AppKit
import CoreAudio
import DictadoKit
import SwiftUI

// La música de Inicio y el bloque de foco. La música es la tarjeta principal: carátula, quién suena, avance con perilla (tocar o
// arrastrar busca ese punto; ±10 s a los lados), anterior / pausa / siguiente y "dónde suena" (las salidas de sonido del Mac, que
// salen de `Fuentes` y se cambian con CoreAudio). El foco tiene su propia tarjeta y nunca ocupa el lugar de la música.

// MARK: - Música

struct MusicaAurora: View {
    let musica: Musica
    let fuentes: Fuentes?
    var foco: Foco?
    let acciones: AccionesIsla

    private var otra: Fuentes.Fuente? {
        guard let fuentes else { return nil }
        return fuentes.sonando.first { $0.id != musica.origen }
    }

    var body: some View {
        Group {
            if let fuentes, fuentes.mostrandoSalidas {
                ListaSalidasAurora(fuentes: fuentes)
            } else if musica.hayPista {
                pista
            } else if let otra, let fuentes {
                FuenteVista(fuente: otra, fuentes: fuentes).padding(AuroraNotch.rellenoPieza)
            } else {
                vacia
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { fondo }
        .piezaNotch()
        .foregroundStyle(.white)
    }

    /// La carátula desenfocada y, encima, el color medio del álbum: la tarjeta se tiñe de lo que suena.
    @ViewBuilder private var fondo: some View {
        if !musica.hayPista && (fuentes?.mostrandoSalidas != true) && otra == nil {
            FondoMusicaVacia()
        } else if musica.hayPista, let imagen = musica.caratula {
            GeometryReader { g in
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                    .scaleEffect(1.5)
                    .blur(radius: 10)
                    .saturation(1.2)
                    .brightness(-0.2)
                    .overlay { Color.black.opacity(0.30) }
                    .overlay { LinearGradient(colors: [musica.acento.opacity(0.30), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    .clipped()
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Suena algo

    private var pista: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button { musica.irAOrigen() } label: { Caratula(imagen: musica.caratula, lado: 48, radio: 11) }
                    .buttonStyle(PulsadoAurora())
                    .help("Ir a \(musica.nombreOrigen.isEmpty ? "la app" : musica.nombreOrigen)")
                    .accessibilityLabel("Ir a \(musica.nombreOrigen.isEmpty ? "la app" : musica.nombreOrigen)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(musica.titulo).font(.system(size: 15, weight: .bold)).tracking(-0.15).help(musica.titulo)
                        .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    Text(subtitulo).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AuroraNotch.suave).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Button { musica.traerSpotify() } label: { IconoSpotify().frame(width: 24, height: 24).contentShape(Circle()) }
                        .buttonStyle(PulsadoAurora())
                        .help("Traer Spotify al frente")
                        .accessibilityLabel("Traer Spotify al frente")
                    Ecualizador(color: Tono.de(musica.acento).claro, activo: musica.sonando).frame(height: 20)
                }
            }
            Spacer(minLength: 4)
            ProgresoMusica(musica: musica)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                if let fuentes { SalidaAurora(fuentes: fuentes) }
                Spacer(minLength: 4)
                controles
            }
        }
        .padding(AuroraNotch.rellenoPieza)
    }

    /// "Marconi Union · Spotify": el artista y de dónde suena (YouTube · Arc).
    private var subtitulo: String {
        let servicio = fuentes?.sonando.first { $0.id == musica.origen }?.servicio
        let origen = [servicio, musica.nombreOrigen].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return [musica.artista, origen].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var controles: some View {
        let sinSiguiente = !musica.tieneSiguiente && musica.puedeSaltar
        return HStack(spacing: 2) {
            ControlMusica(simbolo: "backward.fill", ayuda: "Anterior") { musica.anterior() }.opacity(sinSiguiente ? 0.35 : 1)
            Button { musica.alternar() } label: {
                Image(systemName: musica.sonando ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x111111))
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(.white) }
                    .contentShape(Circle())
            }
            .buttonStyle(PulsadoAurora())
            .help(musica.sonando ? "Pausar" : "Reproducir")
            .accessibilityLabel(musica.sonando ? "Pausar" : "Reproducir")
            ControlMusica(simbolo: "forward.fill", ayuda: "Siguiente") { musica.siguiente() }.opacity(sinSiguiente ? 0.35 : 1)
        }
    }

    // MARK: Nada suena

    /// Nada suena: sobre el fondo de pantalla del Mac difuminado, el icono de Spotify, "Nada sonando" y un botón para reproducir.
    private var vacia: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconoSpotify().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    RotuloPieza("Música", color: AuroraNotch.suave)
                    Text("Nada sonando").font(.system(size: 16, weight: .bold)).tracking(-0.16)
                    Text("Spotify").font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.suave).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let u = musica.ultima {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold)).foregroundStyle(AuroraNotch.suave)
                    Text("Última: " + u.titulo + (u.artista.isEmpty ? "" : " · " + u.artista))
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(AuroraNotch.resumen).lineLimit(1)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Última canción: \(u.titulo)" + (u.artista.isEmpty ? "" : ", \(u.artista)"))
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                BotonAura("Reproducir", icono: "play.fill", estilo: .lleno, grande: true, ayuda: "Abrir Spotify y reanudar la música") { musica.abrirYReanudarSpotify() }
                IconoPildoraNotch(simbolo: "arrow.up.forward.app", ayuda: "Traer Spotify al frente") { musica.traerSpotify() }
                Spacer(minLength: 4)
                if let fuentes { SalidaAurora(fuentes: fuentes) }
            }
        }
        .padding(AuroraNotch.rellenoPieza)
    }
}

/// El fondo de la música vacía: el fondo de pantalla del Mac, muy difuminado y con un velo oscuro para que el texto se lea. Se lee al
/// aparecer (en otro hilo, ya reducido) y se suelta al desaparecer; si no hay fondo legible, queda el plano oscuro de la pieza.
struct FondoMusicaVacia: View {
    /// Renders: la imagen de muestra (no leen nada del Mac).
    @MainActor static var muestra: CGImage?

    @State private var modelo = FondoEscritorioModelo()

    var body: some View {
        let imagen = Self.muestra ?? modelo.imagen
        ZStack {
            AuroraNotch.superficie
            if let imagen {
                GeometryReader { g in
                    Image(decorative: imagen, scale: 1).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                        .scaleEffect(1.35)
                        .blur(radius: 22)
                        .saturation(1.25)
                        .clipped()
                }
                .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.38), .black.opacity(0.58)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeOut(duration: 0.25), value: imagen != nil)
        .clipped()
        .onAppear {
            guard Self.muestra == nil else { return }
            modelo.cargar(.mac, pantalla: NSScreen.main ?? NSScreen.screens.first)
        }
        .onDisappear { modelo.soltar() }
        .accessibilityHidden(true)
    }
}

/// El icono real de la app de Spotify (el del Finder), sin deformarlo ni recortarlo; si no está instalada, el glifo dibujado.
struct IconoSpotify: View {
    @MainActor private static var icono: CGImage??

    /// El icono se baja a un mapa de bits de 128 × 128 (sin copias de 1024 px de la app ni representaciones en vivo).
    @MainActor private static func cargar() -> CGImage? {
        if let c = icono { return c }
        var img: CGImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            let origen = NSWorkspace.shared.icon(forFile: url.path)
            var caja = CGRect(x: 0, y: 0, width: 128, height: 128)
            if let crudo = origen.cgImage(forProposedRect: &caja, context: nil, hints: nil),
               let ctx = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(crudo, in: caja)
                img = ctx.makeImage()
            }
        }
        icono = .some(img)
        return img
    }

    var body: some View {
        if let img = Self.cargar() {
            Image(decorative: img, scale: 2).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            GlifoSpotify()
        }
    }
}

/// El glifo de Spotify dibujado a mano (círculo verde con tres arcos): sin imágenes de marca dentro de la app.
struct GlifoSpotify: View {
    var body: some View {
        Canvas { ctx, tam in
            let l = min(tam.width, tam.height)
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: l, height: l)), with: .color(AuroraAcento.bien))
            let grosor = l * 0.075
            for (i, (ancho, alto)) in [(0.58, 0.14), (0.48, 0.11), (0.38, 0.09)].enumerated() {
                var p = Path()
                let cy = l * (0.36 + 0.15 * Double(i)), w = l * ancho
                p.move(to: CGPoint(x: (l - w) / 2, y: cy))
                p.addQuadCurve(to: CGPoint(x: (l + w) / 2, y: cy), control: CGPoint(x: l / 2, y: cy - l * alto * 2))
                ctx.stroke(p, with: .color(Color(hex: 0x04210F)), style: StrokeStyle(lineWidth: grosor, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ControlMusica: View {
    let simbolo: String
    let ayuda: String
    var grande = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: grande ? 17 : 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

// MARK: - Avance

/// El avance: ⟲10, lo escuchado, la barra con perilla, lo que falta y 10⟳. Se redibuja una vez por segundo solo mientras suena; en
/// pausa es estático. Tocar o arrastrar la barra busca ese punto (`Musica.saltar`, que usa MediaRemote) si la app lo acepta.
struct ProgresoMusica: View {
    let musica: Musica
    @State private var arrastre: Double?

    var body: some View {
        if musica.sonando {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in fila(ctx.date) }
        } else {
            fila(Date())
        }
    }

    private func fila(_ ahora: Date) -> some View {
        let pos = arrastre.map { $0 * musica.duracion } ?? musica.posicion(en: ahora)
        let fraccion = musica.duracion > 0 ? min(1, pos / musica.duracion) : 0
        let tono = Tono.de(musica.acento)
        let puede = musica.puedeSaltar && musica.duracion > 0
        let barra = BarraAvance(fraccion: fraccion, color: tono.claro, puedeBuscar: puede,
                                alMover: { arrastre = $0 },
                                alSoltar: { f in
                                    musica.saltar(a: f * musica.duracion)
                                    arrastre = nil
                                },
                                alAjustar: { musica.avanzar(Double($0)) })
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                salto("gobackward.10", -10, ayuda: "Atrasar 10 segundos")
                tiempo(Tiempo.reloj(pos), ancho: .leading)
                barra
                tiempo(musica.duracion > 0 ? "-" + Tiempo.reloj(max(0, musica.duracion - pos)) : "", ancho: .trailing)
                salto("goforward.10", 10, ayuda: "Adelantar 10 segundos")
            }
            HStack(spacing: 4) {
                tiempo(Tiempo.reloj(pos), ancho: .leading)
                barra
                tiempo(musica.duracion > 0 ? "-" + Tiempo.reloj(max(0, musica.duracion - pos)) : "", ancho: .trailing)
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Avance: \(Tiempo.reloj(pos)) de \(Tiempo.reloj(musica.duracion))")
    }

    private func tiempo(_ texto: String, ancho: Alignment) -> some View {
        Text(texto).font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(AuroraNotch.suave)
            .frame(minWidth: 28, alignment: ancho).fixedSize()
    }

    private func salto(_ simbolo: String, _ segundos: Double, ayuda: String) -> some View {
        Button { musica.avanzar(segundos) } label: {
            Image(systemName: simbolo).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(musica.puedeSaltar ? 0.85 : 0.3))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .disabled(!musica.puedeSaltar)
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

// MARK: - Dónde suena

/// La salida actual (ícono y nombre) en una píldora: al tocarla, la tarjeta muestra la lista de salidas del Mac.
struct SalidaAurora: View {
    let fuentes: Fuentes

    var body: some View {
        let actual = fuentes.salidas.first { $0.id == fuentes.salidaActual }
        Button { withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = true } } label: {
            HStack(spacing: 4) {
                Image(systemName: actual?.simbolo ?? "hifispeaker.fill").font(.system(size: 10.5, weight: .semibold))
                Text(actual?.nombre ?? "Salida").font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7.5, weight: .bold)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: 124)
            .background { Capsule().fill(AuroraNotch.botonVidrio) }
            .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .help("Dónde suena: " + (actual?.nombre ?? "elegir salida"))
        .accessibilityLabel("Dónde suena: " + (actual?.nombre ?? "elegir salida"))
    }
}

/// Las salidas de sonido (altavoces, AirPods, pantalla, AirPlay), con la actual marcada: tocar una cambia por dónde suena el Mac
/// (`Fuentes.ponerSalida`, que escribe la salida predeterminada con CoreAudio, igual que el reproductor de antes).
struct ListaSalidasAurora: View {
    let fuentes: Fuentes
    @State private var encima: AudioDeviceID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RotuloPieza("Dónde suena")
                Spacer(minLength: 0)
                Button { withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24).background(Circle().fill(AuroraNotch.botonVidrio)).contentShape(Circle())
                }
                .buttonStyle(PulsadoAurora())
                .help("Cerrar")
                .accessibilityLabel("Cerrar la lista de salidas")
            }
            VStack(spacing: 2) {
                ForEach(fuentes.salidasVisibles(4)) { s in fila(s) }
            }
            Spacer(minLength: 0)
        }
        .padding(AuroraNotch.rellenoPieza)
    }

    private func fila(_ s: Fuentes.Salida) -> some View {
        let actual = s.id == fuentes.salidaActual
        return Button {
            fuentes.ponerSalida(s)
            withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = false }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: s.simbolo).font(.system(size: 12, weight: .medium)).frame(width: 20)
                Text(s.nombre).font(.system(size: 12, weight: actual ? .bold : .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if actual { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(AuroraAcento.bien) }
            }
            .foregroundStyle(actual ? Color.white : AuroraNotch.resumen)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(actual ? 0.14 : (encima == s.id ? 0.08 : 0))) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 ? s.id : nil }
        .accessibilityLabel(s.nombre + (actual ? ", salida actual" : ""))
    }
}

// MARK: - Foco

/// Un bloque de foco en su propia tarjeta (ámbar): "En foco", la cuenta en puntos, la tarea, una regla con lo que va y los botones.
/// Cabe de 176 de ancho para arriba: si los botones con texto no entran, pasan a una versión más angosta y, al final, a íconos.
/// Terminado el tiempo, pregunta si quedó hecha. Solo se redibuja una vez por segundo mientras el bloque corre.
struct TarjetaFoco: View {
    let foco: Foco
    let acciones: AccionesIsla
    var ancho: CGFloat?
    /// En los renders, la hora fija (sin reloj corriendo).
    var ahoraFijo: Date?

    var body: some View {
        TarjetaAura(tono: .alerta, ancho: ancho) {
            if let ahoraFijo {
                contenido(ahoraFijo)
            } else if foco.pausado {
                contenido(Date())
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in contenido(ctx.date) }
            }
        }
    }

    private func contenido(_ ahora: Date) -> some View {
        let falta = foco.restante(en: ahora)
        let terminado = falta <= 0 && !foco.pausado
        return VStack(alignment: .leading, spacing: 0) {
            RotuloPieza(terminado ? "Terminó el bloque" : (foco.pausado ? "En pausa" : "En foco"), color: TonoAura.alerta.rotulo)
            NumeroPuntos(texto: terminado ? "0:00" : Tiempo.reloj(falta)).padding(.top, 8)
            Text(foco.activo?.titulo ?? "").font(AuroraNotch.tituloTarea).tracking(-0.14).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 4)
            Regla(valor: foco.fraccion(en: ahora), tono: Tono(base: .white, claro: Color(hex: 0xFFE2A8)), cuantas: 26, alto: 6, grosor: 1.2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Va \(Int((foco.fraccion(en: ahora) * 100).rounded())) por ciento del bloque")
            botones(terminado: terminado).padding(.top, 8)
        }
    }

    private func botones(terminado: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            fila(terminado: terminado, compacto: false, conTexto: true)
            fila(terminado: terminado, compacto: true, conTexto: true)
            fila(terminado: terminado, compacto: true, conTexto: false)
        }
    }

    private func fila(terminado: Bool, compacto: Bool, conTexto: Bool) -> some View {
        HStack(spacing: compacto ? 4 : 4) {
            if terminado {
                BotonAura(conTexto ? "Hecha" : nil, icono: conTexto ? nil : "checkmark", estilo: .lleno, redondo: !conTexto, compacto: compacto, ayuda: "Quedó hecha") { acciones.responderFoco(true) }
                BotonAura(conTexto ? "Aún no" : nil, icono: conTexto ? nil : "arrow.uturn.backward", redondo: !conTexto, compacto: compacto, ayuda: "Aún no la termino") { acciones.responderFoco(false) }
                BotonAura("+10", compacto: compacto, ayuda: "Diez minutos más") { acciones.extenderFoco(10) }
            } else {
                BotonAura(conTexto ? "Terminé" : nil, icono: conTexto ? nil : "checkmark", estilo: .lleno, redondo: !conTexto, compacto: compacto, ayuda: "Terminé este bloque") { acciones.responderFoco(true) }
                BotonAura("+5", compacto: compacto, ayuda: "Cinco minutos más") { acciones.extenderFoco(5) }
                BotonAura(conTexto ? "Soltar" : nil, icono: conTexto ? nil : "xmark", redondo: !conTexto, compacto: compacto, ayuda: "Soltar el bloque sin contarlo") { acciones.responderFoco(nil) }
            }
        }
    }
}
