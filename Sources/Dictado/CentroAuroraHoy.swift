import AppKit
import DictadoKit
import SwiftUI

// Sección Hoy del Centro: la vista de la mañana. Arriba el clima y la semana en una línea; después el foco del día con sus tres prioridades; en
// el medio, a la izquierda la agenda de hoy y a la derecha los correos que esperan respuesta; abajo, cuántas capturas hay por clasificar y el radar.
// Fuentes: el brief y `manana.json` (solo si son de HOY: si no, se dice que aún no llegan), la agenda en vivo de Dictado (la de `manana.json`
// solo si Calendario no está disponible) y el estado del centro (inbox y noticias). Nada se inventa: lo que falta se dice en su sitio.

struct HoyAurora: View {
    let datos: DatosCentro
    let simulado: Bool
    var abrir: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var abrirRuta: (String) -> Void = { _ in }
    var unirse: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private static let altoFoco: CGFloat = 200
    private static let altoAbajo: CGFloat = 188
    private static let maxCorreos = 5

    var body: some View {
        let ahora = datos.reloj.ahora
        let estado = datos.hoy.estado
        let brief = estado?.brief.flatMap { HoyCentro.esDeHoy($0.fechaIso, ahora: ahora) ? $0 : nil }
        let manana = estado?.manana.flatMap { HoyCentro.esDeHoy($0.fechaIso, ahora: ahora) ? $0 : nil }
        VStack(alignment: .leading, spacing: AuroraCentro.separacion) {
            if let c = brief?.clima { lineaClima(c, semana: brief?.semana) }
            foco(brief: brief, manana: manana, estado: estado, ahora: ahora)
            HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                agenda(manana: manana, ahora: ahora)
                correos(manana: manana, ahora: ahora)
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                inbox(estado: estado, manana: manana)
                radar(estado?.noticias, ahora: ahora)
            }
            .frame(height: Self.altoAbajo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Clima

    private func lineaClima(_ c: EstadoCentro.Brief.Clima, semana: Int?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: c.simbolo).font(.system(size: 16, weight: .medium)).symbolRenderingMode(.hierarchical).frame(width: 22)
            Text("\(c.ciudad) · \(c.temp)° · \(c.cielo)").font(AuroraCentro.cuerpo)
            Text("máx \(c.max)° · mín \(c.min)°").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
            Spacer(minLength: 12)
            if let semana { Text("Semana \(semana)").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave) }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.ciudad), \(c.temp) grados, \(c.cielo). Máxima \(c.max), mínima \(c.min)." + (semana.map { " Semana \($0)." } ?? ""))
    }

    // MARK: Foco

    private func foco(brief: EstadoCentro.Brief?, manana: EstadoCentro.Manana?, estado: EstadoCentro?, ahora: Date) -> some View {
        let titulo = brief?.foco.titulo ?? manana?.foco?.titulo
        let porque = brief?.foco.porque ?? manana?.foco?.porque
        let hechas = datos.focoHechas()
        return TarjetaVidrioGrande(alto: Self.altoFoco, relleno: EdgeInsets(top: 22, leading: 30, bottom: 22, trailing: 30)) {
            if let titulo {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Foco de hoy").font(AuroraCentro.cuerpo).foregroundStyle(AuroraAcento.foco)
                        Text(titulo).font(.system(size: 30, weight: .semibold)).tracking(-0.4).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if let porque, !porque.isEmpty {
                            Text(porque).font(.system(size: 16, weight: .regular)).foregroundStyle(AuroraCentro.resumen)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let prioridades = brief?.prioridades, !prioridades.isEmpty {
                        Rectangle().fill(AuroraCentro.linea).frame(width: 1)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Prioridades").font(AuroraCentro.cuerpo).foregroundStyle(AuroraCentro.suave).padding(.bottom, 6)
                            ForEach(Array(prioridades.prefix(3).enumerated()), id: \.offset) { _, p in prioridad(p, hecha: p.hecha || hechas.contains(p.texto)) }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 520, alignment: .leading)
                    }
                }
            } else {
                EstadoVacioAurora(icono: "sun.horizon", titulo: tituloSinBrief(estado), detalle: detalleSinBrief(estado, ahora: ahora))
            }
        }
    }

    private func prioridad(_ p: EstadoCentro.Brief.Prioridad, hecha: Bool) -> some View {
        let notas = [p.vertical, p.meta, p.minutos.map { "\($0) min" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: hecha ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(hecha ? AuroraCentro.verdeClaro : Color.white.opacity(0.42))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.texto).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(hecha ? AuroraCentro.suave : .white)
                if !notas.isEmpty { Text(notas).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 44, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.texto)\(hecha ? ", hecha" : "")")
    }

    private func tituloSinBrief(_ e: EstadoCentro?) -> String {
        if e == nil, datos.hoy.cargando { return "Leyendo el estado del día…" }
        return "El brief de hoy aún no llega"
    }

    private func detalleSinBrief(_ e: EstadoCentro?, ahora: Date) -> String {
        if !datos.hoy.configurado { return "El centro no está configurado en este Mac, así que no hay foco ni prioridades que mostrar." }
        if let b = e?.brief, let f = HoyCentro.frescura(dia: LecturaDia.fecha(b.fechaIso ?? ""), ahora: ahora) {
            return "El último brief es \(f). Cuando llegue el de hoy, aquí verás el foco y las tres prioridades."
        }
        return datos.hoy.error ?? "Cuando llegue, aquí verás el foco y las tres prioridades del día."
    }

    // MARK: Agenda

    /// Una cita con lo que hace falta para abrirla o unirse a ella.
    private struct FilaAgenda: Identifiable {
        let id: String
        let cita: HoyCentro.Cita
        var enlace: URL?
        var evento: Agenda.Evento?
    }

    private enum Agendado {
        case citas(horas: [FilaAgenda], todoElDia: [FilaAgenda])
        case sin(titulo: String, detalle: String)
    }

    private func agendado(manana: EstadoCentro.Manana?, ahora: Date) -> Agendado {
        let cal = Calendar.current
        if datos.agenda.permitido {
            let vivos = datos.agenda.pasadosDeLaSemana + datos.agenda.eventos + datos.agenda.todoElDia
            let filas = vivos.map { e in
                FilaAgenda(id: e.id, cita: HoyCentro.Cita(titulo: e.titulo, inicio: e.inicio, fin: e.fin, todoElDia: e.todoElDia, lugar: e.lugar,
                                                          videollamada: e.enlace != nil, invitados: e.invitados.count), enlace: e.enlace, evento: e)
            }
            return ordenar(filas, ahora: ahora, cal: cal)
        }
        if let a = manana?.agenda, a.leida == true {
            let filas = (a.eventos ?? []).enumerated().compactMap { i, e -> FilaAgenda? in
                guard let ini = EstadoCentro.fecha(e.inicio) else { return nil }
                let fin = EstadoCentro.fecha(e.fin) ?? ini
                return FilaAgenda(id: "m\(i)", cita: HoyCentro.Cita(titulo: e.titulo, inicio: ini, fin: fin, todoElDia: e.todoElDia ?? false, lugar: e.lugar,
                                                                     videollamada: e.videollamada ?? false, invitados: e.invitados ?? 0))
            }
            return ordenar(filas, ahora: ahora, cal: cal)
        }
        if let motivo = manana?.agenda?.motivo, !motivo.isEmpty {
            return .sin(titulo: "La agenda de hoy no se pudo leer", detalle: motivo.prefix(1).uppercased() + motivo.dropFirst() + ".")
        }
        return .sin(titulo: "Sin acceso a Calendario", detalle: "Dictado no puede leer tu agenda ahora. Cuando tenga el permiso de Calendario, aquí verás lo de hoy.")
    }

    private func ordenar(_ filas: [FilaAgenda], ahora: Date, cal: Calendar) -> Agendado {
        let dia = HoyCentro.delDia(filas.map(\.cita), ahora: ahora, calendario: cal)
        func fila(_ c: HoyCentro.Cita) -> FilaAgenda { filas.first { $0.cita == c } ?? FilaAgenda(id: c.titulo, cita: c) }
        return .citas(horas: dia.conHora.map(fila), todoElDia: dia.todoElDia.map(fila))
    }

    private func agenda(manana: EstadoCentro.Manana?, ahora: Date) -> some View {
        let r = agendado(manana: manana, ahora: ahora)
        var cuenta: Int?
        if case let .citas(h, t) = r { cuenta = h.count + t.count }
        return TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 20, leading: 26, bottom: 14, trailing: 26)) {
            VStack(alignment: .leading, spacing: 0) {
                cabeza("Agenda de hoy", cuenta: cuenta)
                switch r {
                case let .citas(horas, todo):
                    if horas.isEmpty && todo.isEmpty {
                        EstadoVacioAurora(icono: "calendar", titulo: "Sin eventos hoy", detalle: "Tu calendario no tiene nada para hoy.").padding(.top, 14)
                    } else {
                        DesplazableAurora(simulado: simulado) {
                            VStack(alignment: .leading, spacing: 0) {
                                if !todo.isEmpty {
                                    Text("Todo el día · " + todo.map(\.cita.titulo).joined(separator: ", ")).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                                        .lineLimit(1).padding(.vertical, 8)
                                    FiloAurora()
                                }
                                ForEach(Array(horas.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { FiloAurora().opacity(0.6) }
                                    filaAgenda(f, ahora: ahora)
                                }
                            }
                        }
                    }
                case let .sin(titulo, detalle):
                    EstadoVacioAurora(icono: "calendar.badge.exclamationmark", titulo: titulo, detalle: detalle).padding(.top, 14)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func filaAgenda(_ f: FilaAgenda, ahora: Date) -> some View {
        let momento = HoyCentro.momento(f.cita, ahora: ahora)
        let detalle = HoyCentro.detalle(f.cita)
        let unir = HoyCentro.puedeUnirse(inicio: f.cita.inicio, fin: f.cita.fin, conEnlace: f.enlace != nil, ahora: ahora)
        let contenido = HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Tiempo.horaDelDia(f.cita.inicio)).font(AuroraCentro.cuerpo).monospacedDigit()
                Text(momento == .enCurso ? "Ahora" : "hasta " + Tiempo.horaDelDia(f.cita.fin, conPeriodo: false))
                    .font(AuroraCentro.minimo).foregroundStyle(momento == .enCurso ? AuroraCentro.verdeClaro : AuroraCentro.sutil)
            }
            .frame(width: 84, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.cita.titulo).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if !detalle.isEmpty { Text(detalle).font(AuroraCentro.denso).foregroundStyle(AuroraCentro.suave).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if unir, let enlace = f.enlace {
                BotonAura("Unirse", icono: "video.fill", estilo: .lleno, ayuda: "Unirse a la videollamada: \(f.cita.titulo)") { unirse(enlace) }
            } else if f.cita.videollamada {
                Image(systemName: "video").font(.system(size: 14, weight: .medium)).foregroundStyle(AuroraCentro.sutil).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .opacity(momento == .paso ? 0.5 : 1)
        .contentShape(Rectangle())
        return Group {
            if let e = f.evento {
                contenido.onTapGesture { AbrirCalendario.evento(e) }.accessibilityAddTraits(.isButton).accessibilityHint("Abre el evento en Calendario")
            } else {
                contenido
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Tiempo.horaDelDia(f.cita.inicio)), \(f.cita.titulo)\(detalle.isEmpty ? "" : ", " + detalle)\(momento == .paso ? ", ya pasó" : "")")
    }

    // MARK: Correos

    private enum Correado {
        case lista([HoyCentro.Correo], faltan: Int)
        case sin(icono: String, titulo: String, detalle: String)
    }

    private func correado(_ manana: EstadoCentro.Manana?) -> Correado {
        guard let c = manana?.correos else {
            return .sin(icono: "envelope", titulo: "Los correos de hoy aún no llegan", detalle: "Se leen junto con el brief de la mañana.")
        }
        guard c.leidos == true else {
            let motivo = c.motivo.flatMap { $0.isEmpty ? nil : $0.prefix(1).uppercased() + $0.dropFirst() + "." }
            return .sin(icono: "envelope.badge", titulo: "No se pudieron leer los correos", detalle: motivo ?? "Gmail no respondió.")
        }
        let lista = (c.lista ?? []).map {
            HoyCentro.Correo(de: $0.de, asunto: $0.asunto, fecha: EstadoCentro.fecha($0.fecha), sinLeer: $0.sinLeer ?? false, enlace: $0.enlace)
        }
        if lista.isEmpty && (c.total ?? 0) == 0 { return .sin(icono: "envelope.open", titulo: "Nada espera tu respuesta", detalle: "No hay correos recientes por contestar.") }
        let r = HoyCentro.correosAMostrar(lista, total: c.total, maximo: Self.maxCorreos)
        return .lista(r.visibles, faltan: r.faltan)
    }

    private func correos(manana: EstadoCentro.Manana?, ahora: Date) -> some View {
        let r = correado(manana)
        var total: Int?
        if case let .lista(v, faltan) = r { total = v.count + faltan }
        let bandeja = URL(string: HoyCentro.enlaceBandeja((manana?.correos?.lista ?? []).map(\.enlace)))
        return TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 20, leading: 26, bottom: 14, trailing: 26)) {
            VStack(alignment: .leading, spacing: 0) {
                cabeza("Correos que esperan respuesta", cuenta: total) {
                    if let bandeja {
                        BotonAura("Abrir Gmail", icono: "arrow.up.right", estilo: .vidrio, ayuda: "Abrir Gmail en el navegador") { abrir(bandeja) }
                    }
                }
                switch r {
                case let .lista(visibles, faltan):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibles.enumerated()), id: \.offset) { i, c in
                            if i > 0 { FiloAurora().opacity(0.6) }
                            filaCorreo(c, ahora: ahora)
                        }
                        if faltan > 0 {
                            Text("y \(faltan) más").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).padding(.top, 10).padding(.leading, 22)
                        }
                    }
                case let .sin(icono, titulo, detalle):
                    EstadoVacioAurora(icono: icono, titulo: titulo, detalle: detalle).padding(.top, 14)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func filaCorreo(_ c: HoyCentro.Correo, ahora: Date) -> some View {
        let url = c.enlace.flatMap(URL.init(string:))
        let fila = HStack(alignment: .center, spacing: 12) {
            Circle().fill(c.sinLeer ? AuroraAcento.seleccion : Color.clear).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.de).font(.system(size: 16, weight: c.sinLeer ? .bold : .semibold)).lineLimit(1)
                Text(c.asunto).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let f = c.fecha { Text(HoyCentro.hace(f, ahora: ahora)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1) }
        }
        .padding(.vertical, 9)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        return Group {
            if let url {
                Button { abrir(url) } label: { fila }.buttonStyle(PulsadoAurora()).accessibilityHint("Abre el correo en Gmail")
            } else {
                fila
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.de), \(c.asunto)\(c.sinLeer ? ", sin leer" : "")")
    }

    // MARK: Inbox

    private func inbox(estado: EstadoCentro?, manana: EstadoCentro.Manana?) -> some View {
        let cuenta = estado?.local?.inbox ?? manana?.inbox ?? estado?.inbox?.items.count
        return TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 20, leading: 26, bottom: 18, trailing: 26)) {
            VStack(alignment: .leading, spacing: 0) {
                cabeza("Inbox", cuenta: nil)
                Spacer(minLength: 0)
                if let n = cuenta {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(n)").font(.system(size: 44, weight: .light)).monospacedDigit()
                        Text(n == 0 ? "Todo clasificado" : (n == 1 ? "captura por clasificar" : "capturas por clasificar")).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Sin lectura del inbox").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                }
                Spacer(minLength: 0)
                BotonAura("Abrir el inbox", icono: "tray", estilo: .vidrio, ayuda: "Abrir la carpeta del inbox en el Finder") { abrirRuta("_inbox") }
            }
        }
        .frame(width: 330)
    }

    // MARK: Radar

    private func radar(_ n: EstadoCentro.Noticias?, ahora: Date) -> some View {
        let items = Array((n?.items ?? []).prefix(3))
        let dia = HoyCentro.frescura(dia: EstadoCentro.fecha(n?.generado), ahora: ahora)
        return TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 20, leading: 26, bottom: 16, trailing: 26)) {
            VStack(alignment: .leading, spacing: 0) {
                cabeza("Radar") {
                    if let dia, !items.isEmpty { Text(dia).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil) }
                }
                if items.isEmpty {
                    EstadoVacioAurora(icono: "newspaper", titulo: "Sin noticias del radar", detalle: "Cuando el radar encuentre algo, las tres principales salen aquí.").padding(.top, 10)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, noticia in
                            if i > 0 { Rectangle().fill(AuroraCentro.linea).frame(width: 1).padding(.vertical, 2) }
                            noticiaRadar(noticia).padding(.leading, i > 0 ? 20 : 0).padding(.trailing, i < items.count - 1 ? 20 : 0)
                        }
                    }
                    .padding(.top, 12)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func noticiaRadar(_ n: EstadoCentro.Noticia) -> some View {
        let url = n.url.flatMap(URL.init(string:))
        let contenido = VStack(alignment: .leading, spacing: 6) {
            Text(n.vertical).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.azulBloque.opacity(0.95)).lineLimit(1)
            Text(n.titulo).font(.system(size: 15, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            Text(n.fuente.isEmpty ? "Fuente sin nombre" : n.fuente).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        return Group {
            if let url {
                Button { abrir(url) } label: { contenido }.buttonStyle(PulsadoAurora()).accessibilityHint("Abre la noticia en el navegador")
            } else {
                contenido
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Cabeza de tarjeta

    private func cabeza<D: View>(_ titulo: String, cuenta: Int? = nil, @ViewBuilder derecha: () -> D) -> some View {
        HStack(spacing: 8) {
            Text(titulo).font(.system(size: 17, weight: .semibold))
            if let cuenta, cuenta > 0 { Text("\(cuenta)").font(.system(size: 15, weight: .medium)).foregroundStyle(AuroraCentro.suave) }
            Spacer(minLength: 8)
            derecha()
        }
        .frame(height: 30)
        .padding(.bottom, 4)
    }

    private func cabeza(_ titulo: String, cuenta: Int?) -> some View { cabeza(titulo, cuenta: cuenta) { EmptyView() } }
}
