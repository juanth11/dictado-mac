import AppKit
import DictadoKit
import EventKit
import SwiftUI

// El widget Fecha del lanzador (Hyper + L): el calendario completo del mes. Título del mes, iniciales de los días (lunes primero), la
// cuadrícula con hoy en el círculo rojo de Aurora y un punto bajo los días con algo en la agenda. Un clic en un día abre Calendario ahí
// (`calshow:`, que no pide permisos). Lo que se decide (las semanas, qué día cuenta como ocupado) está en DictadoKit (`CuadriculaMes`).

extension Agenda {
    /// Los días del mes de `fecha` que tienen algo en la agenda (con los calendarios elegidos, sin cancelados ni rechazados). No toca el mes
    /// que mira la isla ni su caché: es una consulta aparte y corta.
    func diasConEventos(delMes fecha: Date) -> Set<Date> {
        let cal = Calendar.current
        let primero = MesCalendario.primero(de: fecha)
        let v = MesCalendario.ventana(de: primero)
        var intervalos: [Intervalo] = []
        if vivo, permitido {
            let lista = almacen.events(matching: almacen.predicateForEvents(withStart: v.start, end: v.end, calendars: calendariosElegidos()))
            for e in lista where e.status != .canceled && !Self.rechazado(e) {
                // Un evento de todo el día acaba a las 23:59 del último día; no hay que recortarlo.
                intervalos.append(Intervalo(inicio: e.startDate, fin: e.endDate))
            }
        } else {
            for e in eventosMes + eventos + todoElDia { intervalos.append(Intervalo(inicio: e.inicio, fin: e.fin)) }
        }
        return CuadriculaMes.dias(de: intervalos, calendario: cal)
    }
}

extension AbrirCalendario {
    /// Abre Calendario en ese día.
    static func enApp(_ dia: Date) {
        if let url = CuadriculaMes.enlaceCalendario(dia), NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Fecha: sólida (mosaico) con el mes entero.
struct WidgetFecha: View {
    let ahora: Date
    var agenda: Agenda?
    /// En un render no hay tareas ni consultas: los días con eventos se leen al momento.
    var simulado = false

    @Environment(\.auroraTema) private var tema
    @State private var marcados: Set<Date> = []

    private static let relleno = EdgeInsets(top: 15, leading: 14, bottom: 12, trailing: 14)

    var body: some View {
        let dias = simulado ? (agenda?.diasConEventos(delMes: ahora) ?? []) : marcados
        let mes = CuadriculaMes.armar(ahora, diasConEventos: dias, ahora: ahora)
        let primero = MesCalendario.primero(de: ahora)
        VStack(spacing: 0) {
            encabezado(mes)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(CuadriculaMes.iniciales[i]).font(.system(size: 9.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(i >= 5 ? tema.textoSuave.opacity(0.7) : tema.textoSuave)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8).padding(.bottom, 3)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(mes.semanas.enumerated()), id: \.offset) { _, semana in
                    HStack(spacing: 0) {
                        ForEach(semana) { celda in
                            if celda.delMes { dia(celda) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(Self.relleno)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .superficieWidget(solido: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendario de \(mes.mes) de \(mes.anio)")
        .task(id: primero) { if !simulado { marcados = agenda?.diasConEventos(delMes: primero) ?? [] } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            if !simulado { marcados = agenda?.diasConEventos(delMes: primero) ?? [] }
        }
    }

    private func encabezado(_ mes: CuadriculaMes) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mes.mes).font(.system(size: 20, weight: .bold)).tracking(-0.3).foregroundStyle(tema.textoPleno)
            Text(String(mes.anio)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tema.textoSuave)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func dia(_ c: CeldaMes) -> some View {
        let color: Color = c.esHoy ? .white : (c.finDeSemana ? tema.textoSuave : tema.textoPleno)
        return Button { AbrirCalendario.enApp(c.dia) } label: {
            ZStack {
                if c.esHoy { Circle().fill(AuroraAcento.hoy).frame(width: 24, height: 24).offset(y: -2) }
                Text("\(c.numero)").font(.system(size: 12.5, weight: c.esHoy ? .bold : .semibold)).monospacedDigit().foregroundStyle(color)
                    .offset(y: -2)
                if c.conEventos {
                    Circle().fill(tema.textoSuave).frame(width: 3.5, height: 3.5).offset(y: 11.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .help("Abrir el \(c.numero) en Calendario")
        .accessibilityLabel("\(c.numero) de \(NombresFecha.meses[Calendar.current.component(.month, from: c.dia) - 1])"
                            + (c.esHoy ? ", hoy" : "") + (c.conEventos ? ", con eventos" : ""))
    }
}
