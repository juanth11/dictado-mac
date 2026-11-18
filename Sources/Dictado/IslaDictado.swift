import AppKit
import SwiftUI

// Dictado y nivel del micrófono. Partido de VistaIsla.swift sin cambiar el comportamiento.

/// Dictando: punto rojo que late, cronómetro, el Prisma en miniatura y el texto en vivo.
struct DictadoIsla: View {
    let estado: EstadoIsla
    let hud: EstadoHUD

    var body: some View {
        let escuchando = hud.fase == .escuchando
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: escuchando ? "circle.fill" : "waveform")
                        .font(.system(size: escuchando ? 8 : 11, weight: .bold))
                        .foregroundStyle(escuchando ? .red : .white)
                        .symbolEffect(.pulse, isActive: true)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Tiempo.reloj(ctx.date.timeIntervalSince(estado.inicioActividad)))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 120, alignment: .leading)
                Spacer(minLength: estado.notch.width)
                Text(escuchando ? (hud.nota == nil ? "Escuchando" : "→ _inbox") : "Transcribiendo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: estado.notch.height)
            TimelineView(.animation) { ctx in
                Visual(estado: hud, t: ctx.date.timeIntervalSinceReferenceDate)
                    .frame(width: 380, height: 120)
                    .scaleEffect(0.42)
                    .frame(width: 172, height: 48)
            }
            Text(hud.texto.isEmpty ? " " : hud.texto)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 28)
                .padding(.bottom, 4)
        }
    }
}

/// Verde: cámara (y casi siempre micrófono). Naranja: solo micrófono.
struct PuntoPrivacidad: View {
    let camara: Bool

    static func color(camara: Bool) -> Color {
        camara ? Color(red: 0.20, green: 0.84, blue: 0.35) : Color(red: 1.0, green: 0.58, blue: 0.0)
    }

    var body: some View {
        Circle()
            .fill(Self.color(camara: camara))
            .frame(width: 8, height: 8)
            .shadow(color: Self.color(camara: camara).opacity(0.8), radius: 3)
    }
}

/// Volumen o brillo (reemplaza el cuadro de macOS): a la izquierda la cifra en su tono, en el centro la cuña de nivel
/// (rayitas que suben de izquierda a derecha sobre una cuadrícula tenue, encendidas hasta el nivel, con la luz naciendo
/// debajo y un marcador blanco) y a la derecha a dónde va el sonido. En silencio la cuña se apaga y queda marcado tenue
/// el volumen guardado. Mientras mantienes la tecla, `Isla` reemplaza la actividad sin cambiar su id: la cuña se
/// enciende o apaga sin volver a entrar.
struct BarraNivel: View {
    let estado: EstadoIsla
    let tipo: Niveles.Tipo
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private var simbolo: String {
        switch tipo {
        case .brillo: return valor < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volumen: return silencio ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    private var tono: Tono { tipo == .brillo ? .brillo : .volumen }
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        contenido
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(etiquetaAccesible)
            .accessibilityValue("\(Int((valor * 100).rounded())) por ciento" + (salida.map { ", " + $0.nombre } ?? ""))
    }

    @ViewBuilder private var contenido: some View {
        if tipo == .volumen {
            switch EstiloVolumen.actual {
            case .bruma: VolumenBruma(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .niebla: VolumenNiebla(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .calor: VolumenCalor(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .espectro: VolumenEspectro(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .termostato: VolumenIsla(estado: estado, valor: valor, silencio: silencio, salida: salida)
            }
        } else {
            cuna
        }
    }

    /// VoiceOver lee el nivel como una sola cosa en vez de los trazos del dibujo.
    private var etiquetaAccesible: String { tipo == .brillo ? "Brillo" : (silencio ? "Volumen en silencio" : "Volumen") }

    /// Brillo: el dial con el sol, "BRILLO · Pantalla", la cifra grande y fina y la luz ámbar desde el borde.
    private var cuna: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 12) {
                Dial(lado: 36, valor: valor, colores: tono.gradiente, marcas: 30, anillo: 3.5, brillo: 0.45 + 0.4 * valor) {
                    Image(systemName: simbolo)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo("Brillo", color: tono.claro)
                    Label { Text("Pantalla") } icon: { Image(systemName: "display") }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Halo.texto2)
                        .labelStyle(EtiquetaJunta())
                        .lineLimit(1)
                }
                .layoutPriority(-1)
                Spacer(minLength: 6)
                NumeroFino(texto: "\(Int((valor * 100).rounded()))", unidad: "%", tamano: 30, valor: valor)
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .frame(maxHeight: .infinity)
        }
        .background {  // la isla toma el color del brillo desde el borde; más fuerte cuanto más alto
            LuzBorde(tono: tono, fuerza: 0.18 + 0.3 * valor, alto: 0.95, centro: 0.3, ancho: 0.8)
        }
        .animation(Halo.cambio, value: valor)
    }
}
