import AppKit
import DictadoKit
import SwiftUI

// Agenda, tiempo y notas. Partido de VistaIsla.swift sin cambiar el comportamiento.

/// Controles como los de iOS: glifos blancos sin fondo.
struct BotonIsla: View {
    let simbolo: String
    var grande = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: grande ? 22 : 16, weight: .semibold))
                .foregroundStyle(.white.opacity(grande ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(Self.nombres[simbolo] ?? "Control")
    }

    /// Lo que lee VoiceOver de cada símbolo de transporte.
    private static let nombres = ["backward.fill": "Canción anterior", "forward.fill": "Canción siguiente", "gobackward.10": "Retroceder 10 segundos",
                                  "goforward.10": "Adelantar 10 segundos", "pause.fill": "Pausar", "play.fill": "Reproducir", "playpause.fill": "Reproducir o pausar"]
}

// MARK: - Pestaña Agenda

extension Agenda {
    /// Eventos con hora que tocan ese día (también los que vienen de la noche anterior o siguen al día siguiente).
    func eventos(del dia: Date, calendario: Calendar = .current) -> [Evento] {
        let inicio = calendario.startOfDay(for: dia)
        let fin = calendario.date(byAdding: .day, value: 1, to: inicio) ?? inicio.addingTimeInterval(86_400)
        return eventos.filter { $0.inicio < fin && $0.fin > inicio }
    }

    func todoElDia(del dia: Date, calendario: Calendar = .current) -> [Evento] {
        let inicio = calendario.startOfDay(for: dia)
        let fin = calendario.date(byAdding: .day, value: 1, to: inicio) ?? inicio.addingTimeInterval(86_400)
        return todoElDia.filter { $0.inicio < fin && $0.fin > inicio }
    }

    /// Los huecos libres desde `ahora` según el horario de Ajustes. Los eventos de todo el día, los rechazados (ya
    /// fuera de la lista) y los marcados como "libre" no bloquean.
    func huecos(desde ahora: Date, config: ConfigHuecos = Ajustes().huecos) -> [Intervalo] {
        Huecos.libres(ocupados: eventos.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }, desde: ahora, config: config,
                      excluyendo: diasNoLaborables)
    }

    /// Reuniones que quedan hoy (para el contador de la pestaña).
    var reunionesHoy: Int {
        let ahora = Date()
        return eventos(del: ahora).filter { $0.esReunion && $0.fin > ahora }.count
    }

    /// Los días que muestra Semana (desde hoy hasta el domingo) o Próxima (de lunes a domingo). Los fines de semana
    /// solo si tienen algo; hoy siempre.
    func dias(_ vista: Vista, ahora: Date, calendario: Calendar = .current) -> [Date] {
        var cal = calendario
        cal.firstWeekday = 2
        let hoy = cal.startOfDay(for: ahora)
        let lunes = cal.dateInterval(of: .weekOfYear, for: ahora)?.start ?? hoy
        let primero = vista == .proxima ? (cal.date(byAdding: .day, value: 7, to: lunes) ?? lunes) : hoy
        let n = vista == .proxima ? 7 : max(1, (cal.dateComponents([.day], from: hoy, to: cal.date(byAdding: .day, value: 7, to: lunes) ?? hoy).day ?? 1))
        return (0..<n).compactMap { cal.date(byAdding: .day, value: $0, to: primero) }.filter { d in
            let finDeSemana = cal.isDateInWeekend(d)
            return !finDeSemana || cal.isDate(d, inSameDayAs: ahora) || !eventos(del: d).isEmpty || !todoElDia(del: d).isEmpty
        }
    }
}

/// Abrir el evento donde vive: Google Calendar en el navegador por omisión si viene de una cuenta de Google, si no
/// Calendario.app. Nada se crea ni se envía desde aquí: solo se abren páginas.
@MainActor
enum AbrirCalendario {
    static func evento(_ e: Agenda.Evento) {
        if e.deGoogle {
            if let url = e.urlGoogle ?? EnlacesCalendario.dia(e.inicio, cuenta: e.cuenta) { NSWorkspace.shared.open(url) }
        } else if let url = URL(string: "calshow:\(Int(e.inicio.timeIntervalSinceReferenceDate))"), NSWorkspace.shared.open(url) {
            return
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func dia(_ fecha: Date) {
        if let url = EnlacesCalendario.dia(fecha) { NSWorkspace.shared.open(url) }
    }

    /// La página de "nuevo evento" de Google Calendar con la hora puesta (30 minutos). No se crea nada hasta que lo guardes allá.
    static func nuevo(en inicio: Date) {
        if let url = EnlacesCalendario.nuevoEvento(inicio: inicio) { NSWorkspace.shared.open(url) }
    }

    static func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}

/// Agenda: tres vistas (Hoy, Semana, Próxima) con una botonera fina arriba. Se redibuja cada 30 segundos solo mientras
/// la isla está abierta en esta pestaña; los datos llegan por los avisos de EventKit.
struct ListaAgenda: View {
    let agenda: Agenda
    let unirse: (URL) -> Void
    var preparar: (Agenda.Evento) -> Void = { _ in }
    /// Render sin app (ImageRenderer no dibuja ScrollView): las listas se cortan abajo en vez de desplazarse.
    var simulado = false

    @State private var copiado = false

    var body: some View {
        if !agenda.permitido {
            Text("Permite el acceso al Calendario en Ajustes → Privacidad y seguridad → Calendarios.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let ahora = ctx.date
                let huecos = agenda.huecos(desde: ahora)
                VStack(alignment: .leading, spacing: 4) {
                    cabecera(ahora: ahora, huecos: huecos)
                    if agenda.vista == .hoy {
                        VistaHoy(agenda: agenda, ahora: ahora, hueco: huecos.first, unirse: unirse, preparar: preparar, simulado: simulado)
                    } else {
                        VistaSemanas(agenda: agenda, vista: agenda.vista == .mes ? .semana : agenda.vista, ahora: ahora, huecos: huecos, unirse: unirse, simulado: simulado)
                    }
                }
            }
            .onAppear { agenda.refrescar() }
        }
    }

    private func cabecera(ahora: Date, huecos: [Intervalo]) -> some View {
        HStack(spacing: 4) {
            SegmentoAgenda(titulo: "Hoy", activo: agenda.vista == .hoy) { elegir(.hoy) }
            SegmentoAgenda(titulo: "Semana", activo: agenda.vista == .semana) { elegir(.semana) }
            SegmentoAgenda(titulo: "Próxima", activo: agenda.vista == .proxima) { elegir(.proxima) }
            Spacer(minLength: 4)
            if agenda.vista == .hoy { EtiquetaTodoElDia(eventos: agenda.todoElDia(del: ahora)) }
            AccionAgenda(simbolo: copiado ? "checkmark" : "doc.on.doc", ayuda: "Copiar disponibilidad: los próximos huecos, listos para pegar") {
                AbrirCalendario.copiar(FormatoHuecos.disponibilidad(huecos))
                copiado = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copiado = false }
            }
            AccionAgenda(simbolo: "plus", ayuda: "Agendar: abre Google Calendar con un evento nuevo en el próximo hueco") {
                AbrirCalendario.nuevo(en: huecos.first?.inicio ?? Self.proximaMedia(ahora))
            }
        }
        .frame(height: 20)
    }

    private func elegir(_ v: Agenda.Vista) {
        guard agenda.vista != v else { return }
        withAnimation(Halo.cambio) {
            agenda.vista = v
            agenda.diaAbierto = nil
        }
    }

    /// La próxima media hora en punto (para "+" cuando no hay hueco).
    static func proximaMedia(_ ahora: Date) -> Date {
        let t = ahora.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.up) * 1800)
    }
}

struct SegmentoAgenda: View {
    let titulo: String
    let activo: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(activo ? 1 : 0.5))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(activo ? 0.13 : 0)))
                .overlay(Capsule().strokeBorder(.white.opacity(activo ? 0.1 : 0), lineWidth: 1))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(titulo)
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }
}

struct AccionAgenda: View {
    let simbolo: String
    let ayuda: String
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(encima ? Halo.texto : Halo.texto2)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(encima ? 0.16 : 0.09)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(ayuda)
        .onHover { encima = $0 }
    }
}

/// Los eventos de todo el día como una etiqueta: el título si es uno, la cuenta si son varios.
struct EtiquetaTodoElDia: View {
    let eventos: [Agenda.Evento]

    var body: some View {
        if let primero = eventos.first {
            HStack(spacing: 4) {
                Circle().fill(Tono.de(primero.color).claro).frame(width: 4, height: 4)
                Text(eventos.count == 1 ? primero.titulo : "\(eventos.count) todo el día")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Halo.texto2).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .frame(maxWidth: 112)
            .background(Capsule().fill(Halo.superficie))
            .help(eventos.map(\.titulo).joined(separator: "\n"))
        }
    }
}

/// Hoy: lo que queda del día, con hora, título, invitados y Unirse; abajo, el próximo hueco libre.
struct VistaHoy: View {
    let agenda: Agenda
    let ahora: Date
    let hueco: Intervalo?
    let unirse: (URL) -> Void
    let preparar: (Agenda.Evento) -> Void
    let simulado: Bool

    private var restantes: [Agenda.Evento] { agenda.eventos(del: ahora).filter { $0.fin > ahora } }

    var body: some View {
        let lista = restantes
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if lista.isEmpty {
                    Text("Nada más hoy").font(.system(size: 15, weight: .thin)).foregroundStyle(Halo.texto)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                } else {
                    ListaDesplazable(simulado: simulado) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                                FilaEventoAgenda(evento: e, ahora: ahora, principal: i == 0, unirse: unirse,
                                                 preparar: i == 0 && e.esReunion ? { preparar(e) } : nil)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            LineaHueco(hueco: hueco, ahora: ahora)
        }
    }
}

/// "Próximo hueco: mar 3:00-4:30 p. m." con Agendar.
struct LineaHueco: View {
    let hueco: Intervalo?
    let ahora: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tono.verde.claro)
            if let hueco {
                HStack(spacing: 4) {
                    Text("Próximo hueco").font(Halo.detalle).foregroundStyle(Halo.texto2)
                    Text(FormatoHuecos.corto(hueco, ahora: ahora)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Halo.texto)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                BotonHalo(titulo: "Agendar", secundario: true, alto: 22) { AbrirCalendario.nuevo(en: hueco.inicio) }
                    .help("Abre Google Calendar con un evento nuevo de 30 minutos en este hueco")
            } else {
                Text("Sin huecos en los próximos días").font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 24)
    }
}

/// Una fila de evento: hora, barra de color, título, invitados y, si se puede, Unirse. El clic lo abre donde vive.
struct FilaEventoAgenda: View {
    let evento: Agenda.Evento
    let ahora: Date
    var principal = false
    let unirse: (URL) -> Void
    var preparar: (() -> Void)?
    @State private var encima = false

    private var estado: String? {
        guard principal else { return nil }
        let s = evento.inicio.timeIntervalSince(ahora)
        if s <= 0 { return "en curso · termina en \(max(1, Int((evento.fin.timeIntervalSince(ahora) / 60).rounded(.up)))) min" }
        if s < 3600 { return "en \(Int((s / 60).rounded(.up))) min" }
        return nil
    }

    /// "Ana, Luis +3": el primer nombre de los dos primeros invitados y cuántos más.
    private var invitados: String {
        let nombres = evento.invitados.map { String($0.split(separator: " ").first ?? "") }.filter { !$0.isEmpty }
        guard !nombres.isEmpty else { return "" }
        let resto = evento.invitados.count - 2
        return nombres.prefix(2).joined(separator: ", ") + (resto > 0 ? " +\(resto)" : "")
    }

    /// Lo que VoiceOver lee tras el título: la hora, el estado y quién va.
    private var descripcionAccesible: String {
        var partes = [Tiempo.horaDelDia(evento.inicio)]
        if let estado { partes.append(estado) }
        if !invitados.isEmpty { partes.append("con " + invitados) }
        return partes.joined(separator: ", ")
    }

    var body: some View {
        let tono = Tono.de(evento.color)
        let hora = Tiempo.horaDelDia(evento.inicio, conPeriodo: false)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(hora).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(Halo.texto)
                Text(Tiempo.periodo(evento.inicio)).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Halo.texto3)
            }
            .frame(width: 40, alignment: .leading)
            Capsule()
                .fill(LinearGradient(colors: tono.gradiente, startPoint: .top, endPoint: .bottom))
                .opacity(principal ? 1 : 0.7)
                .frame(width: 4, height: 24)
                .shadow(color: tono.base.opacity(principal ? 0.8 : 0), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(evento.titulo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                HStack(spacing: 4) {
                    if let estado { Text(estado).font(Halo.detalle).foregroundStyle(tono.claro).lineLimit(1).fixedSize() }
                    let i = invitados
                    Text(i.isEmpty ? (estado == nil ? "hasta " + Tiempo.horaDelDia(evento.fin) : "") : i)
                        .font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if let preparar {
                AccionAgenda(simbolo: "text.magnifyingglass", ayuda: "Prepárame: lo que sabe tu cerebro de esta reunión", accion: preparar)
            }
            if evento.sePuedeUnir, let enlace = evento.enlace {
                BotonUnirse { unirse(enlace) }
                    .help("Unirse a la videollamada")
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(encima ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .onTapGesture { AbrirCalendario.evento(evento) }
        .help(evento.titulo)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(evento.titulo)
        .accessibilityValue(descripcionAccesible)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(evento.deGoogle ? "Abre en Google Calendar" : "Abre en Calendario")
        .accessibilityAction { AbrirCalendario.evento(evento) }
    }
}

/// ScrollView con el borde de abajo desvanecido; en el render sin app se corta en vez de desplazarse.
struct ListaDesplazable<Contenido: View>: View {
    let simulado: Bool
    @ViewBuilder let contenido: () -> Contenido

    private var desvanecido: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        if simulado {
            Color.clear.overlay(alignment: .top) { contenido() }.clipped().mask(desvanecido)
        } else {
            ScrollView(.vertical, showsIndicators: false) { contenido().padding(.bottom, 8) }.mask(desvanecido)
        }
    }
}

/// Semana y Próxima: una fila por día (día, cuántos eventos, de qué hora a qué hora y una barra con lo ocupado del
/// horario laboral); al tocarla se abre con los eventos de ese día.
struct VistaSemanas: View {
    let agenda: Agenda
    let vista: Agenda.Vista
    let ahora: Date
    let huecos: [Intervalo]
    let unirse: (URL) -> Void
    let simulado: Bool

    var body: some View {
        let config = Ajustes().huecos
        ListaDesplazable(simulado: simulado) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(agenda.dias(vista, ahora: ahora), id: \.self) { dia in
                    let abierto = agenda.diaAbierto.map { Calendar.current.isDate($0, inSameDayAs: dia) } ?? false
                    FilaDia(agenda: agenda, dia: dia, ahora: ahora, config: config, abierto: abierto) {
                        withAnimation(Halo.cambio) { agenda.diaAbierto = abierto ? nil : dia }
                    }
                    if abierto {
                        DiaAbierto(agenda: agenda, dia: dia, ahora: ahora, hueco: huecos.first { Calendar.current.isDate($0.inicio, inSameDayAs: dia) },
                                   unirse: unirse)
                    }
                }
            }
        }
    }
}

struct FilaDia: View {
    let agenda: Agenda
    let dia: Date
    let ahora: Date
    let config: ConfigHuecos
    let abierto: Bool
    let tocar: () -> Void
    @State private var encima = false

    private static let cortos = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    /// "9–3:30 p. m." / "11 a. m.–1 p. m.": sin ":00" para que quepa en la fila.
    static func compacto(_ a: Date, _ b: Date, _ cal: Calendar) -> String {
        func h(_ f: Date) -> (String, String) {
            let x = FormatoHuecos.hora(f, calendario: cal)
            return (x.texto.hasSuffix(":00") ? String(x.texto.dropLast(3)) : x.texto, x.periodo)
        }
        let (ta, pa) = h(a), (tb, pb) = h(b)
        return pa == pb ? "\(ta)–\(tb) \(pb)" : "\(ta) \(pa)–\(tb) \(pb)"
    }

    var body: some View {
        let cal = Calendar.current
        let eventos = agenda.eventos(del: dia)
        let hoy = cal.isDateInToday(dia)
        let rango: String = {
            guard let primero = eventos.first, let ultimo = eventos.max(by: { $0.fin < $1.fin }) else { return "Libre" }
            let dia0 = cal.startOfDay(for: dia)
            let fin = cal.date(byAdding: .day, value: 1, to: dia0) ?? ultimo.fin
            return Self.compacto(max(primero.inicio, dia0), min(ultimo.fin, fin), cal)
        }()
        Button(action: tocar) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(Self.cortos[cal.component(.weekday, from: dia) - 1]).font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(hoy ? Tono.azul.claro : Halo.texto2)
                    Text("\(cal.component(.day, from: dia))").font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Halo.texto)
                }
                .frame(width: 48, alignment: .leading)
                Text(eventos.isEmpty ? "–" : "\(eventos.count)").font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(eventos.isEmpty ? Halo.texto3 : Halo.texto)
                    .frame(width: 16, alignment: .trailing)
                    .help("Eventos con hora")
                Text(rango).font(Halo.detalle).foregroundStyle(eventos.isEmpty ? Halo.texto3 : Halo.texto2).lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                BarraOcupado(eventos: eventos, dia: dia, config: config)
                    .frame(height: 8)
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(abierto ? 0.09 : encima ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .accessibilityLabel(Self.cortos[cal.component(.weekday, from: dia) - 1] + " \(cal.component(.day, from: dia))")
        .accessibilityValue(eventos.isEmpty ? "libre" : "\(eventos.count) eventos, \(rango)")
        .accessibilityAddTraits(abierto ? .isSelected : [])
    }
}

/// El horario laboral del día como una barra fina: los bloques ocupados, del color de su calendario.
struct BarraOcupado: View {
    let eventos: [Agenda.Evento]
    let dia: Date
    let config: ConfigHuecos

    var body: some View {
        GeometryReader { geo in
            let cal = Calendar.current
            let inicio = cal.startOfDay(for: dia).addingTimeInterval(Double(config.inicioMin) * 60)
            let total = Double(config.finMin - config.inicioMin) * 60
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                ForEach(eventos) { e in
                    let x0 = max(0, e.inicio.timeIntervalSince(inicio) / total), x1 = min(1, e.fin.timeIntervalSince(inicio) / total)
                    if x1 > x0 {
                        Capsule().fill(Tono.de(e.color).claro).opacity(e.ocupado ? 0.9 : 0.35)
                            .frame(width: max(3, geo.size.width * (x1 - x0)))
                            .offset(x: geo.size.width * x0)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)   // decorativa: la fila del día ya dice cuántos eventos y el rango
    }
}

/// Los eventos de un día abierto, con su hueco libre y la vista del día en Google Calendar.
struct DiaAbierto: View {
    let agenda: Agenda
    let dia: Date
    let ahora: Date
    let hueco: Intervalo?
    let unirse: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(agenda.eventos(del: dia)) { e in
                FilaEventoAgenda(evento: e, ahora: ahora, unirse: unirse)
            }
            HStack(spacing: 4) {
                ForEach(agenda.todoElDia(del: dia)) { e in
                    Text(e.titulo).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Halo.texto2).lineLimit(1)
                        .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(Halo.superficie))
                }
                if let hueco {
                    Text("Hueco " + FormatoHuecos.rango(hueco)).font(Halo.detalle).foregroundStyle(Tono.verde.claro).lineLimit(1)
                    BotonHalo(titulo: "Agendar", secundario: true, alto: 20) { AbrirCalendario.nuevo(en: hueco.inicio) }
                }
                Spacer(minLength: 0)
                AccionAgenda(simbolo: "arrow.up.right", ayuda: "Abrir este día en Google Calendar") { AbrirCalendario.dia(dia) }
            }
            .padding(.leading, 4).padding(.bottom, 4)
        }
        .padding(.leading, 8)
    }
}

struct EtiquetaIsla: View {
    let titulo: String

    var body: some View {
        Rotulo(titulo, color: Halo.texto3)
    }
}

enum Tiempo {
    static func reloj(_ segundos: Double) -> String {
        let s = max(0, Int(segundos.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func faltan(_ fecha: Date) -> String {
        let minutos = Int((fecha.timeIntervalSinceNow / 60).rounded(.up))
        return minutos <= 0 ? "ahora" : "en \(minutos) min"
    }

    /// "4:59" hasta que empieza; "Ahora" cuando ya empezó.
    static func cuentaRegresiva(hasta inicio: Date, desde ahora: Date) -> String {
        let s = Int(inicio.timeIntervalSince(ahora).rounded(.up))
        return s <= 0 ? "Ahora" : reloj(Double(s))
    }

    /// "hace 3 min", "hace 2 h", "hace 4 d".
    static func hace(_ fecha: Date) -> String {
        let s = Int(-fecha.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 48 * 3600 { return "hace \(s / 3600) h" }
        return "hace \(s / 86_400) d"
    }

    private static func formato(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = patron
        return f
    }

    /// "3:00 p. m." (o "3:00" sin el periodo), sin el día.
    static func horaDelDia(_ fecha: Date, conPeriodo: Bool = true) -> String {
        formato(conPeriodo ? "h:mm a" : "h:mm").string(from: fecha)
    }

    /// "a. m." / "p. m.".
    static func periodo(_ fecha: Date) -> String { formato("a").string(from: fecha) }

    /// Número de la hora para la regla de la agenda ("9", "10", "1").
    static func horaCorta(_ fecha: Date) -> String { formato("h").string(from: fecha) }

    /// "Meet", "Zoom", "Teams"… según el enlace de la reunión.
    static func servicio(_ host: String) -> String {
        if host.contains("meet.google") { return "Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return "Videollamada"
    }

    /// "Editando Isla.swift · 3 min", "Necesita tu permiso: swift build", "Lista · hace 5 min".
    static func sesion(_ s: SesionesClaude.Sesion) -> String {
        let minutos = max(0, Int(-s.desde.timeIntervalSinceNow) / 60)
        switch s.estado {
        case .trabajando:
            return (s.actividad.isEmpty ? "Trabajando" : s.actividad) + (minutos > 0 ? " · \(minutos) min" : "")
        case .esperando:
            return s.espera + (s.actividad.isEmpty ? "" : ": " + s.actividad)
        case .lista:
            return "Lista · " + hace(s.desde) + (s.resumen.isEmpty ? "" : " · " + s.resumen)
        }
    }

    /// 76 400 → "76 k"; 1 230 000 → "1,2 M".
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 1_000 { return "\(n / 1_000) k" }
        return "\(n)"
    }

    /// "3:00 a. m." si es hoy; "mañana 3:00 a. m.", "ayer 8:03 a. m." o "lun. 8:00 a. m." si no.
    static func hora(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_CO")
        let cal = Calendar.current
        formato.dateFormat = cal.isDateInToday(fecha) || cal.isDateInTomorrow(fecha) || cal.isDateInYesterday(fecha) ? "h:mm a" : "EEE h:mm a"
        let dia = cal.isDateInTomorrow(fecha) ? "mañana " : cal.isDateInYesterday(fecha) ? "ayer " : ""
        return dia + formato.string(from: fecha)
    }

    /// "2:04 – 2:49 p. m." (formato colombiano de 12 horas).
    static func franja(_ e: Agenda.Evento, conEstado: Bool = true) -> String {
        let inicio = horaDelDia(e.inicio, conPeriodo: false)
        let fin = horaDelDia(e.fin)
        let dia = Calendar.current.isDateInToday(e.inicio) ? "" : "Mañana · "
        let ahora = Date()
        let estado = !conEstado ? "" : e.inicio <= ahora ? " · en curso"
            : (e.inicio.timeIntervalSince(ahora) < 3600 ? " · \(faltan(e.inicio))" : "")
        return dia + inicio + " – " + fin + estado
    }
}

/// Pestaña Notas: arriba "lo siguiente" (una sola cosa, con su "si… entonces" y de qué reunión salió), con Empezar
/// (un bloque de foco de 25 min), Hecha, Otra y Soltar; abajo las reuniones de hoy (con notas, grabando o sin grabar).
struct PestanaNotas: View {
    let pendientes: Pendientes
    let agenda: Agenda
    let notas: NotasReunion?
    var foco: Foco?
    let alternarNotas: () -> Void

    /// Las reuniones de hoy del calendario que ya empezaron y no tienen notas (ni se están grabando).
    private var sinGrabar: [Agenda.Evento] {
        let ahora = Date()
        return agenda.eventos.filter { e in
            e.esReunion && e.inicio <= ahora && Calendar.current.isDateInToday(e.inicio)
                && !pendientes.hoy.contains { $0.titulo == e.titulo } && notas?.titulo != e.titulo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = pendientes.siguiente {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Rotulo("Lo siguiente", color: Tono.ambar.claro)
                        if pendientes.abiertos > 1 {
                            Text("1 de \(pendientes.abiertos)").font(.system(size: 10, weight: .medium)).foregroundStyle(Halo.texto2)
                        }
                        Spacer(minLength: 4)
                        if pendientes.hechasHoy > 0 {
                            Label("\(pendientes.hechasHoy) hoy", systemImage: "checkmark")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Tono.verde.claro)
                                .help("Pendientes que cerraste hoy")
                        }
                    }
                    Text(s.texto).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detalle(s)).font(.system(size: 10.5)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
                HStack(spacing: 4) {
                    BotonHalo(titulo: "Empezar", icono: "timer", alto: 24) { foco?.empezar(s.texto, minutos: 25) }
                        .help("Un bloque de foco de 25 minutos para esto")
                    BotonHalo(titulo: "Hecha", icono: "checkmark", secundario: true, alto: 24) { pendientes.hecho(s) }
                    BotonHalo(titulo: "Otra", secundario: true, alto: 24) { pendientes.otra() }
                    BotonHalo(titulo: "Soltar", secundario: true, alto: 24) { pendientes.soltar(s) }
                        .help("No hacerlo: deja de mostrarse")
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Rotulo("Lo siguiente")
                    Text(pendientes.hechasHoy > 0 ? "Todo al día · \(pendientes.hechasHoy) hechas hoy" : "Nada pendiente de tus reuniones")
                        .font(.system(size: 15, weight: .thin)).foregroundStyle(Halo.texto)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let notas, notas.grabando {
                    fila(icono: "record.circle", color: Tono.rojo.claro, notas.titulo)
                }
                ForEach(pendientes.hoy.suffix(2)) { r in fila(icono: "checkmark.circle", color: Tono.verde.claro, r.titulo) }
                if let e = sinGrabar.last, notas?.grabando != true {
                    Button(action: alternarNotas) { fila(icono: "circle.dashed", color: Halo.texto2, e.titulo + " · Grabar") }
                        .buttonStyle(PulsadoAurora())
                        .help("Esta reunión no tiene notas: grabarla ahora")
                }
                if pendientes.hoy.isEmpty && sinGrabar.isEmpty && notas?.grabando != true {
                    Text("Hoy no hay reuniones con notas").font(.system(size: 10.5)).foregroundStyle(Halo.texto2)
                }
            }
        }
        .onAppear { pendientes.refrescar() }
    }

    private func detalle(_ s: Pendientes.Item) -> String {
        var partes: [String] = []
        if let g = s.gatillo, !g.isEmpty { partes.append("Si: " + g) } else if let c = s.cuando, !c.isEmpty { partes.append(c) }
        partes.append("de «\(s.reunion)»")
        return partes.joined(separator: " · ")
    }

    private func fila(icono: String, color: Color, _ texto: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icono).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(texto).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Halo.texto2).lineLimit(1)
        }
    }
}

/// El cierre del día: cuántos pendientes quedan (en un orbe); Mañana (siguen ahí), Soltar (dejan de mostrarse) o Ver el resumen.
struct CierreIsla: View {
    let estado: EstadoIsla
    let quedan: Int
    let responder: (Bool?) -> Void

    var body: some View {
        AlertaAura(notch: estado.notch, tono: .alerta, rotulo: "Cierre del día",
                   frase: quedan == 1 ? "Queda 1 pendiente" : "Quedan \(quedan) pendientes", apoyo: "El resumen de hoy está en tu inbox") {
            OrbeAurora(titulo: "Pendientes", numero: "\(quedan)", valor: min(1, Double(quedan) / 10), cifra: 20, lado: AuroraNotch.orbeAlerta)
                .modifier(Entrada())
        } acciones: {
            BotonAura("Mañana", estilo: .lleno, ayuda: "Que sigan para mañana") { responder(true) }
            BotonAura("Soltar", ayuda: "Dejar de mostrarlos") { responder(false) }
            BotonAura("Ver", ayuda: "Ver el resumen") { responder(nil) }
        }
    }
}
