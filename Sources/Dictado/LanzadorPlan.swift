import AppKit
import DictadoKit
import SwiftUI

// La tarjeta del plan de Mañana en el lanzador (Hyper + L): lo de hoy y lo de la semana, con casilla donde la fuente lo permite
// (Recordatorios, por EventKit) y un botón que abre la lista de agentes de la isla. No lanza nada por su cuenta.
// Aparece en el bloque del clima cuando el espacio activo lleva la pieza `plan` en su `dock:` (o es Mañana).

extension EspacioIsla {
    /// ¿El lanzador muestra el plan en este espacio? Con la pieza `plan` en su Dock, o el espacio llamado Mañana.
    var muestraPlan: Bool { piezasDockUsaPlan || BusquedaApps.normalizar(nombre) == "manana" }
}

struct TarjetaPlanLanzador: View {
    let plan: PlanManana
    let ahora: Date
    let abrirAgentes: () -> Void
    var simulado = false

    private static let relleno = EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)
    private static let tono = TonoAura.verde

    var body: some View {
        let t = TarjetaPlan.armar(plan.plan, hechas: plan.hechas, ahora: ahora, maxHoy: 3, maxSemana: 2)
        TarjetaAura(tono: Self.tono, radio: AuroraMedida.widgetRadio, relleno: Self.relleno) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    RotuloPieza("Plan", color: Self.tono.rotulo)
                    Spacer(minLength: 4)
                    Text(resumen(t)).font(AuroraNotch.fila).foregroundStyle(AuroraNotch.suave)
                }
                if t.vacio {
                    Spacer(minLength: 0)
                    Text("Nada pendiente").font(AuroraNotch.titulo).tracking(-0.16)
                    Text("Ni hoy ni esta semana.").font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).padding(.top, 1)
                    Spacer(minLength: 0)
                } else {
                    seccion(t.hoy).padding(.top, 8)
                    if !t.semana.filas.isEmpty || t.semana.ocultas > 0 { seccion(t.semana).padding(.top, 7) }
                    Spacer(minLength: 4)
                }
                BotonAura("Dejar trabajando a los agentes", icono: "sparkles", estilo: .lleno, compacto: true,
                          ayuda: "Abre la lista de agentes y tus sesiones para dejarlos trabajando (no lanza nada por su cuenta)", accion: abrirAgentes)
            }
        }
    }

    private func resumen(_ t: TarjetaPlan) -> String {
        let n = t.hoy.pendientes
        return n == 0 ? "Hoy, libre" : (n == 1 ? "1 hoy" : "\(n) hoy")
    }

    private func seccion(_ s: SeccionPlan) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(s.titulo.uppercased()).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5).foregroundStyle(AuroraNotch.sutil)
                if s.ocultas > 0 { Text("+\(s.ocultas)").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(AuroraNotch.suave) }
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)
            if s.filas.isEmpty {
                Text(s.titulo == "Hoy" ? "Nada para hoy" : "Nada esta semana").font(AuroraNotch.fila).foregroundStyle(AuroraNotch.suave).padding(.vertical, 3)
            }
            ForEach(s.filas) { f in fila(f) }
        }
    }

    private func fila(_ f: FilaPlan) -> some View {
        HStack(spacing: 6) {
            casilla(f)
            Text(f.texto).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                .strikethrough(f.hecha)
                .foregroundStyle(f.hecha ? AuroraNotch.sutil : .white)
                .frame(maxWidth: .infinity, alignment: .leading).help(f.texto)
            if let c = f.cuando {
                Text(c).font(.system(size: 9.5, weight: .semibold)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(f.vencida ? AuroraAcento.hoy : AuroraNotch.suave)
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(f.etiqueta): \(f.texto)" + (f.cuando.map { ", \($0)" } ?? "") + (f.hecha ? ", hecha" : ""))
    }

    /// Recordatorios: casilla que se marca; tareas, metas e hitos: solo un icono de su origen (solo lectura).
    @ViewBuilder private func casilla(_ f: FilaPlan) -> some View {
        if f.puedeMarcar {
            Button { plan.marcarHecho(f) } label: {
                Image(systemName: f.hecha ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(f.hecha ? AuroraAcento.bien : AuroraNotch.suave)
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PulsadoAurora())
            .help("Marcar como hecho en Recordatorios")
            .accessibilityLabel("Marcar como hecho: \(f.texto)")
        } else {
            Image(systemName: Self.simbolo(f.origen)).font(.system(size: 9, weight: .semibold)).foregroundStyle(AuroraNotch.sutil)
                .frame(width: 16, height: 20).help(f.etiqueta + " (solo lectura)")
        }
    }

    private static func simbolo(_ o: ItemPlan.Origen) -> String {
        switch o {
        case .tarea: return "checklist"
        case .recordatorio: return "bell"
        case .meta: return "flag.fill"
        case .hito: return "calendar"
        }
    }
}
