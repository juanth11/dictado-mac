import AppKit
import DictadoKit
import SwiftUI

// Sección Semana del Centro: esta semana y la que viene en siete columnas (lunes a domingo). Los eventos son bloques sobre la línea de
// tiempo del día, los huecos libres (de `Huecos`) van punteados en verde y la marca roja es ahora. Las tareas abiertas del centro van
// bajo el día en que vencen, y las que no tienen fecha, en su columna. "Copiar disponibilidad" y "Agendar ahí" son los mismos de la isla.

struct SemanaAurora: View {
    let datos: DatosCentro
    let nav: NavegacionAurora
    let simulado: Bool

    @State private var copiado = false

    private static let altoLinea: CGFloat = 480
    private static let altoTareas: CGFloat = 176
    private static let ancho: CGFloat = 38
    private static let anchoSinFecha: CGFloat = 176

    /// Lo que se dibuja: los eventos (los que ya pasaron esta semana y los que vienen), los huecos y las tareas, ya repartidos por día.
    private struct Armado {
        var vista: VistaSemanal
        var corta: [Intervalo]
        var porID: [String: Agenda.Evento]
    }

    private func armar(ahora: Date) -> Armado {
        let agenda = datos.agenda
        let todos = agenda.pasadosDeLaSemana + agenda.eventos
        var porID: [String: Agenda.Evento] = [:]
        for e in todos { porID[e.id] = e }
        var amplia = datos.config
        amplia.diasHorizonte = max(amplia.diasHorizonte, 10)
        let vista = SemanaCentro.armar(desplazamiento: min(1, nav.semana), eventos: todos.map { Self.evento($0) }, todoElDia: Self.dias(agenda.todoElDia),
                                       huecos: agenda.huecos(desde: ahora, config: amplia), tareas: datos.tareasSemana(), ahora: ahora, config: datos.config)
        return Armado(vista: vista, corta: agenda.huecos(desde: ahora, config: datos.config), porID: porID)
    }

    var body: some View {
        let ahora = datos.reloj.ahora
        let a = armar(ahora: ahora)
        VStack(alignment: .leading, spacing: 16) {
            cabecera(vista: a.vista, corta: a.corta, ahora: ahora)
            if !datos.agenda.permitido {
                TarjetaVidrioGrande(alto: 120) {
                    Text("Permite el acceso al Calendario en Ajustes → Privacidad y seguridad → Calendarios para ver tu semana.")
                        .font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                }
            } else if datos.agenda.borrador != nil {
                TarjetaVidrioGrande(alto: 300) { FormularioReunion(agenda: datos.agenda, grande: true) }
            } else if nav.semana == 2 {
                MesCentro(agenda: datos.agenda, ahora: ahora, config: datos.config)
            } else {
                cuadricula(vista: a.vista, porID: a.porID, ahora: ahora)
            }
        }
    }

    private static func evento(_ e: Agenda.Evento) -> EventoSemana {
        var partes: [String] = []
        if !e.invitados.isEmpty { partes.append("\(e.invitados.count + 1) personas") }
        if let enlace = e.enlace { partes.append(Tiempo.servicio(enlace.host ?? "")) }
        return EventoSemana(id: e.id, titulo: e.titulo, inicio: e.inicio, fin: e.fin, detalle: partes.isEmpty ? nil : partes.joined(separator: " · "))
    }

    /// Un evento de todo el día cuenta en cada día que cubre.
    private static func dias(_ lista: [Agenda.Evento]) -> [(dia: Date, titulo: String)] {
        let cal = Calendar.current
        var salida: [(Date, String)] = []
        for e in lista {
            var d = cal.startOfDay(for: e.inicio)
            var n = 0
            while d < e.fin && n < 14 {
                salida.append((d, e.titulo))
                d = cal.date(byAdding: .day, value: 1, to: d) ?? e.fin
                n += 1
            }
        }
        return salida
    }

    // MARK: Cabecera

    private func cabecera(vista: VistaSemanal, corta: [Intervalo], ahora: Date) -> some View {
        HStack(spacing: 16) {
            SegmentadoAurora(opciones: ["Esta semana", "Próxima", "Mes"], elegida: nav.semana, grande: true) { nav.semana = $0 }
            if nav.semana < 2 { Text(vista.titulo).font(AuroraCentro.titulo).tracking(-0.3) }
            Spacer(minLength: 0)
            BotonAura(copiado ? "Copiado" : "Copiar disponibilidad", icono: copiado ? "checkmark" : "doc.on.doc", estilo: .oscuro, grande: true,
                      ayuda: "Copiar los próximos huecos, listos para pegar") {
                AbrirCalendario.copiar(FormatoHuecos.disponibilidad(corta))
                copiado = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copiado = false }
            }
            BotonAura(icono: "plus", estilo: .oscuro, redondo: true, grande: true, ayuda: "Nueva reunión") {
                datos.agenda.nuevaReunion(en: corta.first?.inicio ?? ListaAgenda.proximaMedia(ahora))
            }
            if let hueco = corta.first {
                BotonAura("Agendar ahí", icono: "calendar.badge.plus", estilo: .lleno, grande: true,
                          ayuda: "Abre el formulario de nueva reunión en el primer hueco (" + FormatoHuecos.corto(hueco, ahora: ahora) + ")") {
                    datos.agenda.nuevaReunion(en: hueco.inicio)
                }
            }
        }
        .frame(height: AuroraCentro.altoBoton + 4)
    }

    // MARK: Cuadrícula

    private func cuadricula(vista: VistaSemanal, porID: [String: Agenda.Evento], ahora: Date) -> some View {
        HStack(alignment: .top, spacing: 8) {
            regla(vista)
            ForEach(vista.dias) { d in
                ColumnaDia(dia: d, vista: vista, porID: porID, ahora: ahora, altoLinea: Self.altoLinea, altoTareas: Self.altoTareas) { datos.agenda.nuevaReunion(en: $0) }
            }
            ColumnaSinFecha(tareas: vista.sinFecha, alto: Self.altoLinea + Self.altoTareas + 58)
                .frame(width: Self.anchoSinFecha)
        }
    }

    /// Las horas, a la izquierda, alineadas con la línea de tiempo de cada columna.
    private func regla(_ vista: VistaSemanal) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 58)
            ZStack(alignment: .topTrailing) {
                Color.clear
                ForEach(vista.marcas, id: \.hora) { m in
                    Text("\(m.hora % 12 == 0 ? 12 : m.hora % 12)").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
                        .position(x: Self.ancho - 14, y: Self.altoLinea * m.fraccion)
                }
            }
            .frame(width: Self.ancho, height: Self.altoLinea)
        }
        .frame(width: Self.ancho)
        .accessibilityHidden(true)
    }
}

/// Una columna: el día arriba, su línea de tiempo y, debajo, las tareas que vencen ese día.
private struct ColumnaDia: View {
    let dia: DiaSemana
    let vista: VistaSemanal
    let porID: [String: Agenda.Evento]
    let ahora: Date
    let altoLinea: CGFloat
    let altoTareas: CGFloat
    let agendar: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            cabecera
            linea
            tareas
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .vidrioAurora(radio: 20)
        .overlay { if dia.esHoy { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.42), lineWidth: 1.5) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(dia.etiqueta) \(dia.numero): \(dia.bloques.count) eventos, \(dia.tareas.count) tareas")
    }

    private var cabecera: some View {
        VStack(spacing: 1) {
            HStack(spacing: 8) {
                Text(dia.etiqueta.uppercased()).font(AuroraCentro.rotulo).tracking(AuroraCentro.rotuloInterletra)
                    .foregroundStyle(dia.esHoy ? Color.white : AuroraCentro.suave)
                Text("\(dia.numero)").font(.system(size: 22, weight: dia.esHoy ? .bold : .semibold)).monospacedDigit()
                    .foregroundStyle(dia.esHoy ? Color.white : Color.white.opacity(0.9))
                    .padding(.horizontal, dia.esHoy ? 8 : 0)
                    .background { if dia.esHoy { Capsule().fill(AuroraNotch.rojoHoy) } }
            }
            Text(dia.todoElDia.first ?? " ").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave).lineLimit(1)
        }
        .frame(height: 58)
        .frame(maxWidth: .infinity)
    }

    private var linea: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                reglaDeHoras
                ForEach(Array(dia.huecos.enumerated()), id: \.offset) { _, t in hueco(t, g.size) }
                ForEach(dia.bloques) { b in bloque(b, g.size) }
                if let a = dia.ahora { marcaAhora(a, g.size) }
            }
        }
        .frame(height: altoLinea)
    }

    private var reglaDeHoras: some View {
        Canvas { ctx, tam in
            var p = Path()
            for m in vista.marcas {
                let y = (tam.height * m.fraccion).rounded() + 0.5
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: tam.width, y: y))
            }
            ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 1)
        }
    }

    private func hueco(_ t: TramoVertical, _ tam: CGSize) -> some View {
        let forma = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button { agendar(t.inicio) } label: {
            forma.fill(AuroraAcento.bien.opacity(0.11))
                .overlay { forma.strokeBorder(AuroraCentro.verdeClaro, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])) }
                .overlay(alignment: .topLeading) {
                    if t.alto * tam.height > 34 { Text("Libre").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.verdeClaro).padding(8) }
                }
        }
        .buttonStyle(PulsadoAurora())
        .frame(width: tam.width - 8, height: max(8, t.alto * tam.height))
        .offset(x: 4, y: t.arriba * tam.height)
        .help("Agendar ahí: abre el formulario de nueva reunión en este hueco")
        .accessibilityLabel("Hueco libre, agendar ahí")
    }

    private func bloque(_ b: BloqueSemana, _ tam: CGSize) -> some View {
        let ancho = (tam.width - 8) / CGFloat(b.carriles)
        let alto = b.alto * tam.height
        let forma = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let relleno = LinearGradient(colors: [Color(hex: 0x6F97FF), Color(hex: 0x3F63D9)], startPoint: .top, endPoint: .bottom)
        return Button { if let e = porID[b.id] { AbrirCalendario.evento(e) } } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(b.titulo).font(AuroraCentro.denso).fontWeight(.semibold).lineLimit(alto > 52 ? 3 : (alto > 30 ? 2 : 1))
                if alto > 44 { Text(horaCorta(b)).font(AuroraCentro.minimo).opacity(0.78).lineLimit(1) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { forma.fill(relleno) }
            .overlay { forma.strokeBorder(.white.opacity(0.22), lineWidth: 1) }
        }
        .buttonStyle(PulsadoAurora())
        .opacity(b.fin <= ahora ? 0.42 : 1)
        .frame(width: ancho - 2, height: max(14, alto - 2))
        .offset(x: 4 + ancho * CGFloat(b.carril), y: b.arriba * tam.height + 1)
        .help(b.titulo + (b.detalle.map { " · " + $0 } ?? ""))
        .accessibilityLabel("\(b.titulo), \(horaCorta(b))" + (b.detalle.map { ", " + $0 } ?? ""))
    }

    private func marcaAhora(_ a: Double, _ tam: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(AuroraNotch.rojoHoy).frame(height: 2).shadow(color: AuroraNotch.rojoHoy, radius: 3)
            Circle().fill(AuroraNotch.rojoHoy).frame(width: 9, height: 9).offset(x: -2)
        }
        .frame(width: tam.width, height: 9)
        .offset(y: a * tam.height - 4.5)
        .accessibilityHidden(true)
    }

    private func horaCorta(_ b: BloqueSemana) -> String {
        let a = FormatoHuecos.hora(b.inicio), z = FormatoHuecos.hora(b.fin)
        return a.periodo == z.periodo ? "\(a.texto)-\(z.texto) \(z.periodo)" : "\(a.texto) \(a.periodo)-\(z.texto) \(z.periodo)"
    }

    private var tareas: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(AuroraCentro.linea).frame(height: 1)
            ForEach(dia.tareas.prefix(4)) { t in FilaTareaSemana(tarea: t) }
            if dia.tareas.count > 4 { Text("y \(dia.tareas.count - 4) más").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
        .frame(height: altoTareas, alignment: .top)
    }
}

private struct FilaTareaSemana: View {
    let tarea: TareaSemana

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().strokeBorder(tarea.vencida ? AuroraNotch.rojoHoy : Color.white.opacity(0.55), lineWidth: 1.4).frame(width: 9, height: 9)
            Text(tarea.texto).font(AuroraCentro.denso).foregroundStyle(tarea.vencida ? Color(hex: 0xFF8A80) : Color.white.opacity(0.9)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((tarea.vencida ? "Vencida: " : "Tarea: ") + tarea.texto)
    }
}

/// La columna de las tareas que no tienen fecha.
private struct ColumnaSinFecha: View {
    let tareas: [TareaSemana]
    let alto: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SIN FECHA").font(AuroraCentro.rotulo).tracking(AuroraCentro.rotuloInterletra).foregroundStyle(AuroraCentro.suave)
                Text(tareas.isEmpty ? "Nada pendiente" : (tareas.count == 1 ? "1 tarea" : "\(tareas.count) tareas")).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
            }
            .frame(height: 42, alignment: .leading)
            ForEach(tareas.prefix(12)) { t in FilaTareaSemana(tarea: t) }
            if tareas.count > 12 { Text("y \(tareas.count - 12) más").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: alto, maxHeight: alto, alignment: .topLeading)
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)) }
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tareas sin fecha, \(tareas.count)")
    }
}
