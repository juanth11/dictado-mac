import AppKit
import DictadoKit
import SwiftUI

// Pestaña Agenda: la próxima reunión, el día en una línea de tiempo (con el hueco libre punteado en verde y "Agendar ahí")
// y la semana en cinco barras. Semana y Próxima cambian la tarjeta del centro a las filas por día de siempre.

struct AgendaAurora: View {
    let agenda: Agenda
    let ahora: Date
    let acciones: AccionesIsla
    let simulado: Bool

    @State private var copiado = false

    private static let anchoReunion: CGFloat = 226
    private static let anchoSemana: CGFloat = 216

    var body: some View {
        if !agenda.permitido {
            TarjetaOscura {
                Text("Permite el acceso al Calendario en Ajustes → Privacidad y seguridad → Calendarios.")
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.suave)
            }
        } else if agenda.borrador != nil {
            TarjetaOscura { FormularioReunion(agenda: agenda) }
        } else {
            let config = Ajustes().huecos
            let huecos = agenda.huecos(desde: ahora, config: config)
            HStack(spacing: AuroraNotch.separacion) {
                TarjetaReunion(agenda: agenda, ahora: ahora, ancho: Self.anchoReunion, acciones: acciones)
                centro(config: config, huecos: huecos)
                semana(config: config, huecos: huecos)
            }
        }
    }

    // MARK: Centro: el día

    private var titulo: String {
        let dia = FormatoHuecos.dia(ahora)
        let corto = dia.components(separatedBy: " de ").first ?? dia
        switch agenda.vista {
        case .hoy: return "Hoy · " + corto
        case .semana: return "Esta semana"
        case .proxima: return "Semana que viene"
        case .mes: return "Mes"
        }
    }

    private func centro(config: ConfigHuecos, huecos: [Intervalo]) -> some View {
        let opciones: [Agenda.Vista] = [.hoy, .semana, .proxima, .mes]
        return TarjetaOscura {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    RotuloPieza(titulo)
                    Spacer()
                    BotonAura(icono: "plus", estilo: .oscuro, redondo: true, compacto: true, ayuda: "Nueva reunión") { agenda.nuevaReunion(en: huecos.first?.inicio ?? ListaAgenda.proximaMedia(ahora)) }
                    SegmentadoAurora(opciones: ["Hoy", "Semana", "Próxima", "Mes"], elegida: opciones.firstIndex(of: agenda.vista) ?? 0) { i in
                        guard agenda.vista != opciones[i] else { return }
                        withAnimation(Halo.cambio) {
                            agenda.vista = opciones[i]
                            agenda.diaAbierto = nil
                        }
                    }
                }
                if agenda.vista == .hoy {
                    hoy(config: config, huecos: huecos)
                } else if agenda.vista == .mes {
                    MesIsla(agenda: agenda, ahora: ahora)
                } else {
                    VistaSemanas(agenda: agenda, vista: agenda.vista, ahora: ahora, huecos: huecos, unirse: acciones.unirse, simulado: simulado)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func hoy(config: ConfigHuecos, huecos: [Intervalo]) -> some View {
        let ocupados = agenda.eventos(del: ahora).filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let hueco = huecos.first
        let linea = LineaDelDia.armar(dia: ahora, eventos: ocupados, libre: hueco, ahora: ahora, inicioHora: config.inicioMin / 60,
                                      finHora: (config.finMin + 59) / 60)
        let proximos = agenda.eventos(del: ahora).filter { $0.fin > ahora }.prefix(2)
        return VStack(alignment: .leading, spacing: 4) {
            LineaDelDiaVista(linea: linea, horas: max(1, (config.finMin + 59) / 60 - config.inicioMin / 60))
                .frame(height: 40)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(proximos), id: \.id) { e in
                    HStack(spacing: 8) {
                        Text(Frase.hora(e.inicio)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit().frame(width: 36, alignment: .leading)
                        Text(e.titulo).lineLimit(1).help(e.titulo)
                        Spacer(minLength: 6)
                        if let lugar = e.lugar { EtiquetaLugar(lugar: lugar, fuente: AuroraNotch.fila, color: .white.opacity(0.55), soloIcono: !detalle(e).isEmpty) }
                        Text(detalle(e)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    .font(AuroraNotch.fila)
                    .contentShape(Rectangle())
                    .onTapGesture { AbrirCalendario.evento(e) }
                }
                if proximos.isEmpty { Text("Nada más hoy").font(AuroraNotch.fila).foregroundStyle(.white.opacity(0.55)) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let hueco {
                    Text("Libre " + FormatoHuecos.corto(hueco, ahora: ahora).replacingOccurrences(of: "hoy ", with: ""))
                        .font(AuroraNotch.botonFuente)
                        .foregroundStyle(mezclarVerde)
                        .padding(.horizontal, 12).frame(height: AuroraNotch.altoBoton)
                        .background { Capsule().fill(AuroraNotch.botonOscuro) }
                        .accessibilityLabel("Hueco libre: " + FormatoHuecos.corto(hueco, ahora: ahora))
                    BotonAura("Agendar ahí", estilo: .lleno, ayuda: "Abre el formulario de nueva reunión en este hueco") {
                        agenda.nuevaReunion(en: hueco.inicio)
                    }
                } else {
                    Text("Sin huecos en los próximos días").font(AuroraNotch.fila).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var mezclarVerde: Color { Color(.sRGB, red: 0.57, green: 0.92, blue: 0.64) }

    /// "4 personas · Meet".
    private func detalle(_ e: Agenda.Evento) -> String {
        var partes: [String] = []
        if !e.invitados.isEmpty { partes.append("\(e.invitados.count + 1) personas") }
        if let enlace = e.enlace { partes.append(Tiempo.servicio(enlace.host ?? "")) }
        return partes.joined(separator: " · ")
    }

    // MARK: Derecha: la semana

    private func semana(config: ConfigHuecos, huecos: [Intervalo]) -> some View {
        let barras = SemanaBarras.armar(eventos: agenda.eventos.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) },
                                        ahora: ahora, config: config)
        return TarjetaOscura(ancho: Self.anchoSemana) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Esta semana")
                VStack(spacing: 4) {
                    ForEach(barras, id: \.dia) { b in
                        HStack(spacing: 8) {
                            Text(b.etiqueta).frame(width: 36, alignment: .leading)
                                .foregroundStyle(b.esHoy ? Color.white : Color.white.opacity(0.6))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.1))
                                    ForEach(Array(b.ocupado.enumerated()), id: \.offset) { _, t in
                                        Rectangle().fill(Color(hex: 0x6F97FF))
                                            .frame(width: max(2, g.size.width * t.ancho))
                                            .offset(x: g.size.width * t.inicio)
                                    }
                                }
                                .clipShape(Capsule())
                            }
                            .frame(height: 8)
                            Text("\(b.eventos)").frame(width: 16, alignment: .trailing).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(b.etiqueta): \(b.eventos) eventos")
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
                HStack {
                    BotonAura(copiado ? "Copiado" : "Copiar disponibilidad", icono: copiado ? "checkmark" : nil, estilo: .oscuro,
                                 ayuda: "Copiar los próximos huecos, listos para pegar") {
                        AbrirCalendario.copiar(FormatoHuecos.disponibilidad(huecos))
                        copiado = true
                        Task { try? await Task.sleep(for: .seconds(1.6)); copiado = false }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// La línea de tiempo del día laboral: marcas de hora, bloques de eventos, el hueco libre punteado en verde y la marca roja
/// de ahora. Todo en fracciones del ancho (las calcula `LineaDelDia`).
struct LineaDelDiaVista: View {
    let linea: LineaDelDia
    let horas: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Canvas { ctx, tam in
                    var p = Path()
                    for h in 0...horas {
                        let x = tam.width * CGFloat(h) / CGFloat(horas)
                        p.move(to: CGPoint(x: min(x, tam.width - 0.5), y: 16))
                        p.addLine(to: CGPoint(x: min(x, tam.width - 0.5), y: 24))
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.28)), lineWidth: 1)
                }
                ForEach(Array(linea.eventos.enumerated()), id: \.offset) { _, t in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x8FB2FF), Color(hex: 0x4D7DFF)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(4, w * t.ancho), height: 14) // grid: ok ancho proporcional, alto de la barra
                        .shadow(color: Color(hex: 0x4D7DFF), radius: 5)
                        .offset(x: w * t.inicio, y: 13)
                }
                if let l = linea.libre {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AuroraAcento.bien.opacity(0.16))
                        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(.sRGB, red: 0.57, green: 0.92, blue: 0.64), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
                        .frame(width: max(4, w * l.ancho), height: 14) // grid: ok ancho proporcional, alto de la barra
                        .offset(x: w * l.inicio, y: 13)
                }
                if let a = linea.ahora {
                    Rectangle().fill(AuroraNotch.rojoHoy).frame(width: 4, height: 32)
                        .shadow(color: AuroraNotch.rojoHoy, radius: 3)
                        .offset(x: w * a - 0.75, y: 5)
                }
                ForEach(Array(linea.marcas.enumerated()), id: \.offset) { _, m in
                    Text(m.etiqueta).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                        .position(x: min(max(w * m.fraccion, 4), w - 4), y: 37)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tu día: \(linea.eventos.count) bloques ocupados" + (linea.libre != nil ? " y un hueco libre" : ""))
    }
}
