import AppKit
import DictadoKit
import SwiftUI

// La pila de sesiones de la pestaña Agentes: debajo de la sesión que trabaja (tarjeta grande), las demás como filas apiladas, la
// más importante delante y las de atrás un poco más hundidas, como las alertas apiladas bajo el notch. Cada fila lleva: estado (el
// único lugar donde hay color de acento), nombre, último paso o resumen, tiempo, barra de contexto y la acción de abrir.
// Solo LEE lo que ya leyó `SesionesClaude` (~/.claude en solo lectura); abrir usa el enlace `claude://` de siempre.

enum MedidasPila {
    static let ancho: CGFloat = 300
    static let altoFila: CGFloat = 48
    static let separacion: CGFloat = 6
    static let radio: CGFloat = 14
    /// Cada fila de atrás se mete esto a cada lado (profundidad de la pila).
    static let hundimiento: CGFloat = 5
}

struct PilaSesionesAura: View {
    let sesiones: [SesionesClaude.Sesion]
    var ahora = Date()

    private var visibles: [SesionesClaude.Sesion] { Array(sesiones.prefix(PilaAgentes.filasVisibles)) }
    private var ocultas: Int { PilaAgentes.ocultas(total: sesiones.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: MedidasPila.separacion) {
            HStack(spacing: 4) {
                RotuloPieza("Más sesiones")
                Text("\(sesiones.count)").font(AuroraNotch.rotuloFuente).monospacedDigit().foregroundStyle(AuroraNotch.sutil)
                Spacer(minLength: 0)
                if ocultas > 0 { Text("+\(ocultas) más").font(AuroraNotch.rotuloFuente).foregroundStyle(AuroraNotch.sutil) }
            }
            .padding(.horizontal, 4)
            ForEach(Array(visibles.enumerated()), id: \.element.id) { i, s in
                FilaSesionAura(sesion: s, ahora: ahora, profundidad: i)
                    .padding(.horizontal, CGFloat(i) * MedidasPila.hundimiento)
            }
            Spacer(minLength: 0)
        }
        .frame(width: MedidasPila.ancho, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Una fila de la pila. Toda la fila abre la sesión; la acción visible es "Revisar" si terminó.
struct FilaSesionAura: View {
    let sesion: SesionesClaude.Sesion
    var ahora = Date()
    var profundidad = 0

    @State private var encima = false

    private var trabaja: Bool { sesion.estado == .trabajando }
    private var acento: Color { trabaja ? AuroraAcento.seleccion : AuroraAcento.bien }
    private var progreso: Double { PilaAgentes.progreso(contexto: sesion.contexto) }
    private var detalle: String {
        if trabaja { return sesion.actividad.isEmpty ? "Trabajando…" : sesion.actividad }
        return sesion.resumen.isEmpty ? "Terminada" : sesion.resumen
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: MedidasPila.radio, style: .continuous)
        Button { SesionesClaude.abrir(sesion) } label: {
            HStack(spacing: 10) {
                estado
                VStack(alignment: .leading, spacing: 1) {
                    Text(sesion.nombre).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).help(sesion.nombre)
                    Text(detalle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(AuroraNotch.suave).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    tiempo
                    if trabaja && sesion.contexto > 0 {
                        Text("ctx " + PilaAgentes.porcentaje(contexto: sesion.contexto)).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(AuroraNotch.sutil)
                    } else if !trabaja {
                        Text("Revisar").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(encima ? 1 : 0.75))
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: MedidasPila.altoFila)
            .background {
                forma.fill(Color.white.opacity(max(0.05, 0.10 - 0.03 * Double(profundidad))))
            }
            .overlay(alignment: .bottom) { if trabaja && sesion.contexto > 0 { barra } }
            .overlay { forma.strokeBorder(.white.opacity(encima ? 0.16 : 0.07), lineWidth: 1) }
            .clipShape(forma)
            .contentShape(forma)
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .help("Abrir la sesión «\(sesion.nombre)»")
        .accessibilityLabel("\(sesion.nombre), " + (trabaja ? "trabajando, \(detalle)" : "terminada, \(detalle)") + ". Abrir")
    }

    /// El círculo de estado: azul que trabaja, verde que terminó.
    private var estado: some View {
        ZStack {
            Circle().fill(acento.opacity(0.16))
            if trabaja {
                ChispaViva(modo: .trabaja, lado: 14, color: acento)
            } else {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(acento)
            }
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder private var tiempo: some View {
        if trabaja {
            Text(sesion.desde, style: .timer).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(AuroraNotch.resumen)
        } else {
            Text(Tiempo.hace(sesion.desde)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(AuroraNotch.suave)
        }
    }

    /// Progreso de contexto: un hilo de 2 pt al pie de la fila (no es el avance de la tarea, que no se conoce: es lo medido).
    private var barra: some View {
        GeometryReader { g in
            Capsule().fill(acento).frame(width: max(4, g.size.width * progreso), height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, MedidasPila.radio / 2)
        .padding(.bottom, 0)
        .accessibilityHidden(true)
    }
}
