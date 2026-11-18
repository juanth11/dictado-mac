import AppKit
import SwiftUI

// Reproductor, salidas de audio y progreso. Partido de VistaIsla.swift sin cambiar el comportamiento.

struct Caratula: View {
    let imagen: NSImage?
    let lado: CGFloat
    let radio: CGFloat
    /// Detrás, la misma carátula desenfocada: un brillo con los colores reales del álbum (como Apple Music).
    var resplandor = false

    var body: some View {
        if resplandor, let imagen {
            portada.background {
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: lado, height: lado)
                    .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
                    .blur(radius: lado * 0.22)
                    .opacity(0.75)
                    .offset(y: lado * 0.06)
            }
        } else {
            portada
        }
    }

    private var portada: some View {
        Group {
            if let imagen {
                Image(nsImage: imagen).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: "music.note").font(.system(size: lado * 0.4)).foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}

/// Reproductor de la vista abierta: carátula, título, onda en el color del álbum, progreso y controles.
struct Reproductor: View {
    let musica: Musica
    var fuentes: Fuentes?

    /// Lo que se puede mostrar: lo que suena en "Ahora suena" (con controles completos) y las demás apps que suenan.
    private var opciones: [(id: String, nombre: String, icono: NSImage?)] {
        var lista: [(String, String, NSImage?)] = []
        if musica.hayPista {
            let icono = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musica.origen)
                .map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 26) }
            let servicio = fuentes?.sonando.first { $0.id == musica.origen }?.servicio
            lista.append((musica.origen, servicio ?? musica.nombreOrigen, icono))
        }
        for f in fuentes?.sonando ?? [] where f.id != musica.origen { lista.append((f.id, f.servicio ?? f.nombre, f.icono)) }
        return lista
    }

    /// Otra app que suena a la vez y que elegiste en las pestañas (sin "Ahora suena", solo su título y ⏯).
    private var otra: Fuentes.Fuente? {
        guard let fuentes else { return nil }
        let otras = fuentes.sonando.filter { $0.id != musica.origen }
        if let id = fuentes.elegida, id != musica.origen { return otras.first { $0.id == id } }
        return musica.hayPista ? nil : otras.first
    }

    var body: some View {
        if let fuentes, fuentes.mostrandoSalidas {
            ListaSalidas(fuentes: fuentes)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if opciones.count > 1, let fuentes { selector(fuentes) }
                if let otra, let fuentes {
                    FuenteVista(fuente: otra, fuentes: fuentes)
                } else if musica.hayPista {
                    principal
                } else {
                    vacio
                }
            }
        }
    }

    /// Pestañas pequeñas para pasar de una fuente a otra (Spotify · YouTube · …).
    private func selector(_ fuentes: Fuentes) -> some View {
        let actual = otra?.id ?? musica.origen
        return HStack(spacing: 4) {
            ForEach(opciones, id: \.id) { o in
                Button { withAnimation(Halo.cambio) { fuentes.elegida = o.id } } label: {
                    HStack(spacing: 4) {
                        if let icono = o.icono { Image(nsImage: icono).resizable().frame(width: 12, height: 12) }
                        Text(o.nombre).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(o.id == actual ? Halo.texto : Halo.texto3)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(.white.opacity(o.id == actual ? 0.13 : 0)))
                    .contentShape(Capsule())
                    .fixedSize()
                }
                .buttonStyle(PulsadoAurora())
            }
        }
    }

    /// Lo que suena (Spotify, YouTube en el navegador, Música…): carátula o ícono de la app, título, de dónde, progreso
    /// (tócalo para saltar) y controles. Sin "siguiente" (un video suelto), ⏮ ⏭ pasan a ser −10 s y +10 s.
    private var principal: some View {
        VStack(alignment: .leading, spacing: opciones.count > 1 ? 8 : 8) {
            HStack(spacing: 8) {
                Button { musica.irAOrigen() } label: { Caratula(imagen: musica.caratula, lado: 50, radio: 12, resplandor: true) }
                    .buttonStyle(PulsadoAurora())
                    .help("Ir a \(musica.nombreOrigen.isEmpty ? "la app" : musica.nombreOrigen)")
                VStack(alignment: .leading, spacing: 2) {
                    // Los títulos de video son largos: dos líneas (las canciones caben en una).
                    Text(musica.titulo).font(.system(size: musica.esSpotify ? 14 : 13, weight: .semibold)).foregroundStyle(Halo.texto)
                        .lineLimit(musica.esSpotify ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                    Text(subtitulo).font(.system(size: 11.5)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
                Spacer(minLength: 4)
                Ecualizador(color: Tono.de(musica.acento).claro, activo: musica.sonando)
                if let fuentes { BotonSalida(fuentes: fuentes) }
            }
            Progreso(musica: musica)
            HStack(spacing: 0) {
                Spacer()
                if musica.tieneSiguiente || !musica.puedeSaltar {
                    BotonIsla(simbolo: "backward.fill") { musica.anterior() }
                } else {
                    BotonIsla(simbolo: "gobackward.10") { musica.avanzar(-10) }
                }
                Spacer()
                BotonIsla(simbolo: musica.sonando ? "pause.fill" : "play.fill", grande: true) { musica.alternar() }
                Spacer()
                if musica.tieneSiguiente || !musica.puedeSaltar {
                    BotonIsla(simbolo: "forward.fill") { musica.siguiente() }
                } else {
                    BotonIsla(simbolo: "goforward.10") { musica.avanzar(10) }
                }
                Spacer()
            }
        }
    }

    /// "Canal · YouTube" o "Artista · Arc": de dónde suena (en Spotify se sobreentiende).
    private var subtitulo: String {
        var partes = [musica.artista].filter { !$0.isEmpty }
        if !musica.esSpotify && !musica.nombreOrigen.isEmpty {
            partes.append(fuentes?.sonando.first { $0.id == musica.origen }?.servicio ?? musica.nombreOrigen)
        }
        return partes.joined(separator: " · ")
    }

    private var vacio: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EtiquetaIsla(titulo: "Música")
                Spacer()
                if let fuentes { BotonSalida(fuentes: fuentes) }
            }
            Text("Nada sonando todavía").font(.system(size: 13)).foregroundStyle(Halo.texto2)
            HStack(spacing: 8) {
                BotonHalo(titulo: "Reanudar", icono: "play.fill", alto: 28) { musica.alternar() }
                BotonHalo(titulo: "Abrir Spotify", secundario: true, alto: 28) { musica.abrirSpotify() }
            }
        }
    }
}

/// Otra app que suena (un video de YouTube en el navegador, Música, un podcast…): su ícono, qué suena (del título de
/// la ventana) y dónde; reproducir o pausar con la tecla multimedia (la recibe la app que suena) e ir a la app.
struct FuenteVista: View {
    let fuente: Fuentes.Fuente
    let fuentes: Fuentes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if let icono = fuente.icono { Image(nsImage: icono).resizable().scaledToFit() } else { Image(systemName: "waveform") }
                }
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fuente.titulo.isEmpty ? "Reproduciendo audio" : fuente.titulo)
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                    Text(fuente.detalle).font(.system(size: 11.5)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
                Spacer(minLength: 4)
                BotonSalida(fuentes: fuentes)
            }
            HStack(spacing: 0) {
                Spacer()
                BotonIsla(simbolo: "playpause.fill") { Musica.teclaMedia(16) }
                Spacer()
                BotonHalo(titulo: "Ir a \(fuente.nombre)", icono: "arrow.up.forward", secundario: true, alto: 26) { fuentes.irA(fuente) }
                Spacer()
            }
        }
    }
}

/// Por dónde suena: el ícono de la salida actual en un círculo de vidrio; al tocarlo se elige otra.
struct BotonSalida: View {
    let fuentes: Fuentes

    var body: some View {
        let actual = fuentes.salidas.first { $0.id == fuentes.salidaActual }
        Button { withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = true } } label: {
            Image(systemName: actual?.simbolo ?? "hifispeaker.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Halo.texto)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .help("Por dónde suena: " + (actual?.nombre ?? "elegir salida"))
    }
}

/// Las salidas de sonido (altavoces, AirPods, pantalla, AirPlay): la actual con ✓; tocar una cambia el sonido del Mac.
struct ListaSalidas: View {
    let fuentes: Fuentes

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Rotulo("Salida de sonido", color: Halo.texto3)
                Spacer()
                Button { withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Halo.texto2)
                        .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.08))).contentShape(Circle())
                }
                .buttonStyle(PulsadoAurora())
            }
            ForEach(fuentes.salidasVisibles(4)) { s in
                let actual = s.id == fuentes.salidaActual
                Button {
                    fuentes.ponerSalida(s)
                    withAnimation(Halo.cambio) { fuentes.mostrandoSalidas = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.simbolo).font(.system(size: 12, weight: .medium)).frame(width: 20)
                        Text(s.nombre).font(.system(size: 12, weight: actual ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 4)
                        if actual { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Tono.azul.claro) }
                    }
                    .foregroundStyle(actual ? Halo.texto : Halo.texto2)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(actual ? 0.1 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PulsadoAurora())
            }
        }
    }
}

/// Progreso como un deslizador fino: lo escuchado en línea continua, un punto brillante y lo que falta punteado.
/// Solo se redibuja (1 vez por segundo) mientras la isla está abierta. Si la app que suena lo acepta, tocar o
/// arrastrar sobre la línea salta a ese punto.
struct Progreso: View {
    let musica: Musica
    @State private var arrastre: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = arrastre.map { $0 * musica.duracion } ?? musica.posicion(en: ctx.date)
            let fraccion = musica.duracion > 0 ? min(1, pos / musica.duracion) : 0
            HStack(spacing: 8) {
                Text(Tiempo.reloj(pos))
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = w * fraccion
                    let medio = geo.size.height / 2
                    ZStack(alignment: .leading) {
                        Path { p in
                            p.move(to: CGPoint(x: x + 6, y: medio))
                            p.addLine(to: CGPoint(x: w, y: medio))
                        }
                        .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.01, 4])) // grid: ok trazo punteado
                        Capsule()
                            .fill(LinearGradient(colors: [Tono.de(musica.acento).base, Tono.de(musica.acento).claro], startPoint: .leading, endPoint: .trailing))
                            .frame(width: x, height: 4)
                            .shadow(color: Tono.de(musica.acento).base.opacity(0.8), radius: 3)
                        Circle().fill(.white).frame(width: 8, height: 8)
                            .shadow(color: Tono.de(musica.acento).base, radius: 5)
                            .offset(x: x - 4.5)
                    }
                    .frame(height: geo.size.height)
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard musica.puedeSaltar, musica.duracion > 0, w > 0 else { return }
                            arrastre = max(0, min(1, v.location.x / w))
                        }
                        .onEnded { v in
                            guard musica.puedeSaltar, musica.duracion > 0, w > 0 else { return }
                            musica.saltar(a: max(0, min(1, v.location.x / w)) * musica.duracion)
                            arrastre = nil
                        })
                }
                .frame(height: 8)
                Text("-" + Tiempo.reloj(max(0, musica.duracion - pos)))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Halo.texto3)
        }
    }
}
