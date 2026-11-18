import AppKit
import DictadoKit
import EventKit
import SwiftUI

// Calendario ampliado: la vista Mes (isla y Centro), los festivos y la reunión nueva.
//
// - Mes: la cuadrícula (lunes primero) con la ocupación de cada día, hoy marcado y los festivos; al tocar un día salen sus eventos y
//   sus huecos libres. Los eventos se piden a Calendario al abrir cada mes (un predicado por mes, guardado en memoria y borrado
//   cuando Calendario avisa un cambio); no hay consultas en bucle.
// - Festivos: primero cualquier calendario de festivos que ya tenga el Mac (su título lo delata, o el ajuste
//   `agenda.calendarioFestivos` lo nombra); si no hay, la lista de DictadoKit (Colombia por ahora; el país es el ajuste
//   `agenda.pais`, «CO» por omisión). No cuentan como huecos libres ni en «Copiar disponibilidad», salvo que
//   `agenda.huecosEnFestivos` sea verdadero.
// - Nueva reunión: un formulario corto. Sin invitados ni Meet se crea en Calendario (EventKit) en el calendario elegido; con ellos
//   se abre Google Calendar con todo puesto. Nada se crea sin tocar Guardar, y el formulario dice por cuál camino irá.

extension Agenda {
    static let claveFestivosPais = "agenda.pais"
    static let claveFestivosCalendario = "agenda.calendarioFestivos"
    static let claveHuecosEnFestivos = "agenda.huecosEnFestivos"

    var paisFestivos: String { UserDefaults.dictado.string(forKey: Self.claveFestivosPais) ?? "CO" }
    var huecosEnFestivos: Bool { UserDefaults.dictado.bool(forKey: Self.claveHuecosEnFestivos) }

    /// Los días que no se ofrecen al buscar huecos (festivos), salvo que el ajuste los permita.
    var diasNoLaborables: Set<Date> { huecosEnFestivos ? [] : Set(festivosProximos.keys) }

    /// Festivos entre dos fechas: el calendario de festivos del Mac si hay, y si no la lista incorporada del país.
    func festivos(desde: Date, hasta: Date) -> [Date: String] {
        let propios = DiasFestivos.entre(desde, hasta, pais: paisFestivos)
        guard vivo, permitido else { return propios }
        let nombre = UserDefaults.dictado.string(forKey: Self.claveFestivosCalendario)
        let cals = almacen.calendars(for: .event).filter { DiasFestivos.pareceDeFestivos($0.title, nombreExplicito: nombre) }
        guard !cals.isEmpty else { return propios }
        let cal = Calendar.current
        var delMac: [Date: String] = [:]
        for e in almacen.events(matching: almacen.predicateForEvents(withStart: desde, end: hasta, calendars: cals)) where e.isAllDay {
            delMac[cal.startOfDay(for: e.startDate)] = e.title ?? "Festivo"
        }
        return DiasFestivos.combinar(delCalendario: delMac, incorporados: propios)
    }

    /// Carga los eventos del mes visible (la cuadrícula entera, con las semanas de los bordes). Si ya se pidió, sale de la memoria.
    func cargarMes(_ m: Date) {
        let primero = MesCalendario.primero(de: m)
        if let c = cacheMeses[primero] {
            eventosMes = c.eventos
            festivosMes = c.festivos
            return
        }
        let v = MesCalendario.ventana(de: primero)
        let festivos = festivos(desde: v.start, hasta: v.end)
        guard vivo, permitido else {
            festivosMes = festivos
            return
        }
        let elegidos = calendariosElegidos()
        var vistos = Set<String>()
        let lista = almacen.events(matching: almacen.predicateForEvents(withStart: v.start, end: v.end, calendars: elegidos))
            .sorted { $0.startDate < $1.startDate }
            .filter { e in
                guard e.status != .canceled, !Self.rechazado(e) else { return false }
                return vistos.insert((e.title ?? "").lowercased() + "|" + String(Int(e.startDate.timeIntervalSince1970)) + (e.isAllDay ? "|d" : "")).inserted
            }
            .prefix(600).map(Self.evento)
        eventosMes = Array(lista)
        festivosMes = festivos
        cacheMeses[primero] = (eventosMes, festivosMes)
    }

    func irAlMes(_ n: Int) {
        mes = MesCalendario.desplazar(mes, por: n)
        diaMes = nil
        cargarMes(mes)
    }

    func irAHoy(_ ahora: Date) {
        mes = MesCalendario.primero(de: ahora)
        diaMes = Calendar.current.startOfDay(for: ahora)
        cargarMes(mes)
    }

    // MARK: Nueva reunión

    struct CalendarioNuevo: Identifiable, Equatable {
        let id: String
        let titulo: String
        let cuenta: String
        let esGoogle: Bool
    }

    /// Los calendarios donde se puede escribir (sin cumpleaños ni suscripciones), los elegidos para la agenda primero.
    func calendariosParaCrear() -> [CalendarioNuevo] {
        if !vivo { return calendariosDeMuestra }
        guard permitido else { return [] }
        let elegidos = Set(calendariosElegidos().map(\.calendarIdentifier))
        return almacen.calendars(for: .event)
            .filter { $0.allowsContentModifications && $0.type != .birthday && $0.type != .subscription }
            .sorted { (elegidos.contains($0.calendarIdentifier) ? 0 : 1, $0.title) < (elegidos.contains($1.calendarIdentifier) ? 0 : 1, $1.title) }
            .map { c in
                let fuente = (c.source?.title ?? "").lowercased()
                let google = c.source?.sourceType == .calDAV && (fuente.contains("google") || c.title.contains("@"))
                return CalendarioNuevo(id: c.calendarIdentifier, titulo: c.title, cuenta: c.source?.title ?? "", esGoogle: google)
            }
    }

    /// ¿Tenemos acceso completo para escribir? (Si no, el formulario cae a Google sin pedir nada.)
    var accesoCompleto: Bool { !vivo || EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Abre el formulario con esa hora (y, si ya hay un borrador, lo reemplaza). No crea nada.
    func nuevaReunion(en inicio: Date, titulo: String = "") {
        let c = calendariosParaCrear().first
        borrador = NuevaReunion(titulo: titulo, inicio: inicio, duracionMin: 30, calendarioID: c?.id, calendarioEsGoogle: c?.esGoogle ?? true,
                                puedeCrearLocal: accesoCompleto && c != nil)
        errorGuardado = nil
    }

    /// Guarda el borrador por el camino que el formulario mostró. Devuelve false (y deja `errorGuardado`) si falla.
    @discardableResult
    func guardarBorrador() -> Bool {
        guard let r = borrador, r.valida, vivo else { return false }
        switch r.camino {
        case .google:
            let cuenta = calendariosParaCrear().first { $0.id == r.calendarioID }.flatMap { $0.titulo.contains("@") ? $0.titulo : nil }
            guard let url = r.enlaceGoogle(cuenta: cuenta) else { errorGuardado = "No pude armar el enlace."; return false }
            NSWorkspace.shared.open(url)
        case .local, .localSinInvitados:
            guard let id = r.calendarioID, let cal = almacen.calendar(withIdentifier: id), cal.allowsContentModifications else {
                errorGuardado = "Ese calendario no deja crear eventos."
                return false
            }
            let e = EKEvent(eventStore: almacen)
            e.calendar = cal
            e.title = r.tituloFinal
            e.startDate = r.inicio
            e.endDate = r.fin
            do { try almacen.save(e, span: .thisEvent) } catch {
                errorGuardado = "No se pudo guardar: \(error.localizedDescription)"
                return false
            }
            cacheMeses.removeAll()
            refrescar()
        }
        borrador = nil
        errorGuardado = nil
        return true
    }
}

// MARK: - La cuadrícula

/// Las medidas de la vista Mes: la de la isla (compacta) y la del Centro (a pantalla completa).
struct EscalaMes {
    var celdaAncho: CGFloat
    var celdaAlto: CGFloat
    var numero: CGFloat
    var rotulo: CGFloat
    var radio: CGFloat

    static let isla = EscalaMes(celdaAncho: 30, celdaAlto: 15.5, numero: 9.5, rotulo: 7.5, radio: 5)
    static let centro = EscalaMes(celdaAncho: 92, celdaAlto: 78, numero: 20, rotulo: 11.5, radio: 14)
}

struct RejillaMes: View {
    let vista: VistaMes
    let elegido: Date?
    let escala: EscalaMes
    let alElegir: (Date) -> Void

    private var hueco: CGFloat { escala.celdaAlto > 40 ? 6 : 1.5 }

    var body: some View {
        VStack(spacing: hueco) {
            HStack(spacing: hueco) {
                ForEach(0..<7, id: \.self) { i in
                    Text(MesCalendario.inicialesDias[i]).font(.system(size: escala.rotulo, weight: .semibold)).foregroundStyle(AuroraNotch.sutil)
                        .frame(width: escala.celdaAncho)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(vista.semanas.enumerated()), id: \.offset) { _, semana in
                HStack(spacing: hueco) {
                    ForEach(semana) { d in celda(d) }
                }
            }
        }
    }

    private func celda(_ d: DiaMes) -> some View {
        let sel: Bool = elegido.map { Calendar.current.isDate($0, inSameDayAs: d.dia) } ?? false
        let forma = RoundedRectangle(cornerRadius: escala.radio, style: .continuous)
        let tinte: Double = d.eventos > 0 ? 0.10 + 0.55 * d.densidad : 0.04
        let colorNumero: Color = d.esHoy ? .white : (d.festivo != nil ? Color(hex: 0xFFD98A) : Color.white.opacity(d.finDeSemana ? 0.55 : 0.92))
        let relleno: CGFloat = d.esHoy ? max(3, escala.numero * 0.4) : 0
        let etiqueta = etiquetaAccesible(d)
        return Button { alElegir(d.dia) } label: {
            ZStack {
                forma.fill(Color(hex: 0x6F97FF).opacity(tinte))
                if d.festivo != nil { forma.fill(Color(hex: 0xFFC24A).opacity(0.20)) }
                if sel { forma.strokeBorder(Color.white.opacity(0.85), lineWidth: 1) }
                Text("\(d.numero)").font(.system(size: escala.numero, weight: d.esHoy ? .bold : .semibold)).monospacedDigit()
                    .foregroundStyle(colorNumero)
                    .padding(.horizontal, relleno)
                    .background { if d.esHoy { Capsule().fill(AuroraNotch.rojoHoy) } }
            }
            .opacity(d.delMes ? 1 : 0.32)
            .frame(width: escala.celdaAncho, height: escala.celdaAlto)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(etiqueta)
    }

    private func etiquetaAccesible(_ d: DiaMes) -> String {
        var t = "\(d.numero)"
        if let f = d.festivo { t += ", festivo: " + f }
        t += d.eventos > 0 ? ", \(d.eventos) eventos" : ", libre"
        if d.esHoy { t += ", hoy" }
        return t
    }
}

// MARK: - La vista Mes

/// El detalle de un día del mes: su festivo, sus eventos y los huecos libres (cada uno con su «Agendar»).
struct DetalleDiaMes: View {
    let agenda: Agenda
    let dia: Date
    let ahora: Date
    var grande = false
    var maxEventos = 3
    var maxHuecos = 2

    var body: some View {
        let cal = Calendar.current
        let inicioDia = cal.startOfDay(for: dia)
        let finDia = cal.date(byAdding: .day, value: 1, to: inicioDia) ?? dia
        let eventos = agenda.eventosMes.filter { !$0.todoElDia && $0.inicio < finDia && $0.fin > inicioDia }
        let todoDia = agenda.eventosMes.filter { $0.todoElDia && cal.isDate($0.inicio, inSameDayAs: dia) }
        let festivo = agenda.festivosMes[inicioDia]
        let ocupados = agenda.eventosMes.filter { !$0.todoElDia && $0.ocupado }.map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let noLaborables: Set<Date> = agenda.huecosEnFestivos ? [] : Set(agenda.festivosMes.keys)
        let huecos = MesCalendario.huecosDelDia(dia, ocupados: ocupados, config: Ajustes().huecos, ahora: ahora, festivos: noLaborables)
        let f = grande ? AuroraCentro.denso : AuroraNotch.fila
        VStack(alignment: .leading, spacing: grande ? 8 : 4) {
            HStack(spacing: 8) {
                Text(FormatoHuecos.dia(dia)).font(.system(size: grande ? 18 : 11, weight: .bold))
                if let festivo {
                    Text(festivo).font(.system(size: grande ? 12 : 8.5, weight: .semibold)).foregroundStyle(Color(hex: 0xFFD98A)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 1).background { Capsule().fill(Color(hex: 0xFFC24A).opacity(0.18)) }
                }
            }
            ForEach(todoDia.prefix(1), id: \.id) { e in Text(e.titulo).font(f).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            ForEach(eventos.prefix(maxEventos), id: \.id) { e in
                HStack(spacing: 8) {
                    Text(Frase.hora(e.inicio)).font(f).monospacedDigit().frame(width: grande ? 64 : 36, alignment: .leading).foregroundStyle(.white.opacity(0.7))
                    Text(e.titulo).font(f).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { AbrirCalendario.evento(e) }
            }
            if eventos.count > maxEventos { Text("y \(eventos.count - maxEventos) más").font(f).foregroundStyle(.white.opacity(0.5)) }
            if eventos.isEmpty && todoDia.isEmpty && festivo == nil { Text("Sin eventos").font(f).foregroundStyle(.white.opacity(0.5)) }
            if festivo != nil && huecos.isEmpty && !agenda.huecosEnFestivos {
                Text("Festivo: sin huecos para agendar").font(f).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(Array(huecos.prefix(maxHuecos).enumerated()), id: \.offset) { _, h in
                HStack(spacing: 8) {
                    Text("Libre " + FormatoHuecos.rango(h)).font(f).foregroundStyle(AuroraCentro.verdeClaro).lineLimit(1)
                    Spacer(minLength: 0)
                    BotonAura("Agendar", estilo: .oscuro, grande: grande, compacto: !grande, ayuda: "Nueva reunión en este hueco") { agenda.nuevaReunion(en: h.inicio) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// La vista Mes de la isla: la cuadrícula a la izquierda y el día elegido a la derecha.
struct MesIsla: View {
    let agenda: Agenda
    let ahora: Date

    var body: some View {
        let config = Ajustes().huecos
        let ocupados: [Intervalo] = agenda.eventosMes.filter { !$0.todoElDia && $0.ocupado }.map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let vista = MesCalendario.armar(mes: agenda.mes, eventos: ocupados, festivos: agenda.festivosMes, ahora: ahora, config: config)
        let elegido = agenda.diaMes ?? Calendar.current.startOfDay(for: ahora)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    flecha("chevron.left", "Mes anterior") { agenda.irAlMes(-1) }
                    Text(vista.titulo.capitalizedFirst).font(.system(size: 10.5, weight: .bold)).frame(minWidth: 96, alignment: .center)
                    flecha("chevron.right", "Mes siguiente") { agenda.irAlMes(1) }
                    Button { agenda.irAHoy(ahora) } label: { Text("Hoy").font(.system(size: 9, weight: .bold)).padding(.horizontal, 8).frame(height: 16).background(Capsule().fill(AuroraNotch.botonOscuro)) }
                        .buttonStyle(PulsadoAurora()).accessibilityLabel("Ir a hoy")
                }
                RejillaMes(vista: vista, elegido: elegido, escala: .isla) { d in agenda.diaMes = d }
            }
            .frame(width: 7 * 30 + 6 * 1.5) // grid: ok cuadrícula de 7 días de 30 más el hueco de 1,5
            DetalleDiaMes(agenda: agenda, dia: elegido, ahora: ahora)
        }
        .task(id: agenda.mes) { agenda.cargarMes(agenda.mes) }
    }

    private func flecha(_ simbolo: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 9, weight: .bold)).frame(width: 20, height: 16)
                .background(Capsule().fill(AuroraNotch.botonOscuro)).contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(ayuda)
    }
}

/// La vista Mes del Centro: la cuadrícula grande y, a la derecha, el día elegido.
struct MesCentro: View {
    let agenda: Agenda
    let ahora: Date
    let config: ConfigHuecos

    var body: some View {
        let ocupados: [Intervalo] = agenda.eventosMes.filter { !$0.todoElDia && $0.ocupado }.map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        let vista = MesCalendario.armar(mes: agenda.mes, eventos: ocupados, festivos: agenda.festivosMes, ahora: ahora, config: config)
        let elegido = agenda.diaMes ?? Calendar.current.startOfDay(for: ahora)
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BotonAura(icono: "chevron.left", estilo: .oscuro, redondo: true, grande: true, ayuda: "Mes anterior") { agenda.irAlMes(-1) }
                    Text(vista.titulo.capitalizedFirst).font(AuroraCentro.titulo).tracking(-0.3).frame(minWidth: 232, alignment: .leading)
                    BotonAura(icono: "chevron.right", estilo: .oscuro, redondo: true, grande: true, ayuda: "Mes siguiente") { agenda.irAlMes(1) }
                    BotonAura("Hoy", estilo: .oscuro, grande: true, ayuda: "Ir al mes de hoy") { agenda.irAHoy(ahora) }
                }
                RejillaMes(vista: vista, elegido: elegido, escala: .centro) { d in agenda.diaMes = d }
                HStack(spacing: 16) {
                    leyenda(Color(hex: 0x6F97FF), "Ocupado (más fuerte = más lleno)")
                    leyenda(Color(hex: 0xFFC24A), "Festivo")
                }
                .font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave)
            }
            TarjetaVidrioGrande(alto: 520) {
                DetalleDiaMes(agenda: agenda, dia: elegido, ahora: ahora, grande: true, maxEventos: 6, maxHuecos: 4)
            }
            .frame(width: 380)
        }
        .task(id: agenda.mes) { agenda.cargarMes(agenda.mes) }
    }

    private func leyenda(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 8) { RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.7)).frame(width: 12, height: 12); Text(t) }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Nueva reunión

/// El formulario compacto: título, día, hora, duración, calendario, invitados y Meet; dice por cuál camino se guardará.
struct FormularioReunion: View {
    let agenda: Agenda
    var grande = false

    var body: some View {
        if let r = agenda.borrador { contenido(r) }
    }

    private func poner(_ cambio: (inout NuevaReunion) -> Void) {
        guard var r = agenda.borrador else { return }
        cambio(&r)
        // El calendario puede cambiar el camino (Google o no) y si se puede crear local.
        if let c = agenda.calendariosParaCrear().first(where: { $0.id == r.calendarioID }) {
            r.calendarioEsGoogle = c.esGoogle
            r.puedeCrearLocal = agenda.accesoCompleto
        }
        agenda.borrador = r
    }

    private func contenido(_ r: NuevaReunion) -> some View {
        let cals = agenda.calendariosParaCrear()
        let cal = Calendar.current
        let f: CGFloat = grande ? 15 : 11
        return HStack(alignment: .top, spacing: grande ? 28 : 12) {
            VStack(alignment: .leading, spacing: grande ? 12 : 4) {
                RotuloPieza("Nueva reunión", grande: grande)
                campoTexto("Título", texto: Binding(get: { r.titulo }, set: { t in poner { $0.titulo = t } }), f: f)
                HStack(spacing: 8) {
                    paso("chevron.left", "Un día antes") { poner { $0.inicio = cal.date(byAdding: .day, value: -1, to: $0.inicio) ?? $0.inicio } }
                    Text(FormatoHuecos.dia(r.inicio)).font(.system(size: f, weight: .semibold)).frame(minWidth: grande ? 152 : 92)
                    paso("chevron.right", "Un día después") { poner { $0.inicio = cal.date(byAdding: .day, value: 1, to: $0.inicio) ?? $0.inicio } }
                    Spacer(minLength: 6)
                    paso("minus", "15 minutos antes") { poner { $0.inicio = $0.inicio.addingTimeInterval(-900) } }
                    let h = FormatoHuecos.hora(r.inicio)
                    Text(h.texto + " " + h.periodo).font(.system(size: f, weight: .semibold)).monospacedDigit()
                    paso("plus", "15 minutos después") { poner { $0.inicio = $0.inicio.addingTimeInterval(900) } }
                }
                HStack(spacing: 4) {
                    Text("Dura").font(.system(size: f - 1, weight: .medium)).foregroundStyle(AuroraNotch.suave)
                    ForEach(NuevaReunion.duraciones, id: \.self) { m in
                        chip(m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "1,5 h"), activo: r.duracionMin == m, f: f - 1) { poner { $0.duracionMin = m } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: grande ? 12 : 4) {
                HStack(spacing: 4) {
                    Text("En").font(.system(size: f - 1, weight: .medium)).foregroundStyle(AuroraNotch.suave)
                    ForEach(cals.prefix(3)) { c in
                        chip(c.titulo.count > 18 ? String(c.titulo.prefix(17)) + "…" : c.titulo, activo: r.calendarioID == c.id, f: f - 1) { poner { $0.calendarioID = c.id } }
                    }
                }
                campoTexto("Invitados (correos)", texto: Binding(get: { r.invitadosTexto }, set: { t in poner { $0.invitadosTexto = t } }), f: f)
                Button { poner { $0.conMeet.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: r.conMeet ? "checkmark.square.fill" : "square").font(.system(size: f))
                        Text("Con Meet").font(.system(size: f, weight: .medium))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PulsadoAurora())
                .accessibilityLabel("Con Meet").accessibilityAddTraits(r.conMeet ? .isSelected : [])
                Text(agenda.errorGuardado ?? r.problemas.first ?? r.avisoDelCamino)
                    .font(.system(size: f - 1, weight: .medium)).foregroundStyle(agenda.errorGuardado != nil || !r.valida ? Color(hex: 0xFF8A80) : AuroraCentro.verdeClaro)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    BotonAura("Cancelar", estilo: .oscuro, grande: grande, ayuda: "Cerrar sin crear nada") { agenda.borrador = nil; agenda.errorGuardado = nil }
                    BotonAura(r.botonGuardar, icono: r.camino == .google ? "arrow.up.forward" : "checkmark", estilo: .lleno, grande: grande,
                              ayuda: r.camino == .google ? "Abrir Google Calendar con todo puesto" : "Crear la reunión en tu Calendario") { agenda.guardarBorrador() }
                        .opacity(r.valida ? 1 : 0.4).disabled(!r.valida)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func campoTexto(_ ph: String, texto: Binding<String>, f: CGFloat) -> some View {
        Group {
            if agenda.vivo {
                TextField(ph, text: texto).textFieldStyle(.plain)
            } else {
                // ImageRenderer no dibuja los campos de AppKit: en los renders se pone el texto a secas.
                Text(texto.wrappedValue.isEmpty ? ph : texto.wrappedValue).foregroundStyle(texto.wrappedValue.isEmpty ? AuroraNotch.sutil : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: f, weight: .medium))
            .padding(.horizontal, 8).frame(height: grande ? 36 : 24)
            .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.09)) }
            .accessibilityLabel(ph)
    }

    private func paso(_ simbolo: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: grande ? 12 : 9, weight: .bold)).frame(width: grande ? 28 : 20, height: grande ? 28 : 20)
                .background(Circle().fill(AuroraNotch.botonOscuro)).contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(ayuda)
    }

    private func chip(_ t: String, activo: Bool, f: CGFloat, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(t).font(.system(size: f, weight: .semibold)).lineLimit(1)
                .foregroundStyle(activo ? Color(hex: 0x111111) : .white)
                .padding(.horizontal, 8).frame(height: grande ? 28 : 20)
                .background { Capsule().fill(activo ? Color.white : AuroraNotch.botonOscuro) }
                .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}
