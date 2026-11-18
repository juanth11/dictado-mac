import AppKit
import DictadoKit
import SwiftUI

// Las tarjetas de Agenda y Agentes del lanzador (Hyper + L): más que un resumen, el día y el trabajo a la vista y con botones que hacen algo.
// Usan los mismos datos que la isla (`Agenda` y EventKit, `SesionesClaude`, `AgentesRemotos` y el Tablero); lo que se decide (qué reunión va
// primero, el orden y el tiempo de los agentes) está en DictadoKit (`PlanDelDia`, `PlanAgentes`) y se prueba allá.

// MARK: - Agenda

struct TarjetaAgendaLanzador: View {
    let agenda: Agenda
    let ahora: Date
    var config: ConfigHuecos = Ajustes().huecos
    let acciones: AccionesIsla
    /// En un render no corre el reloj: se usa `ahora` tal cual.
    var simulado = false

    private static let relleno = EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)

    var body: some View {
        Group {
            if !agenda.permitido {
                TarjetaAura(tono: .reunion, radio: AuroraMedida.widgetRadio, relleno: Self.relleno) {
                    VStack(alignment: .leading, spacing: 6) {
                        RotuloPieza("Agenda", color: TonoAura.reunion.rotulo)
                        Spacer(minLength: 0)
                        Text("Sin acceso al Calendario").font(AuroraNotch.titulo).tracking(-0.16)
                        Text("Permítelo en Ajustes → Privacidad y seguridad → Calendarios.").font(AuroraNotch.resumenFuente)
                            .foregroundStyle(AuroraNotch.resumen).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if simulado {
                contenido(ahora)
            } else {
                // Cada 30 s se recalcula la cuenta regresiva; nada más corre.
                TimelineView(.periodic(from: .now, by: 30)) { ctx in contenido(ctx.date) }
            }
        }
    }

    private func reuniones(_ ahora: Date) -> (lista: [ReunionDia], eventos: [String: Agenda.Evento]) {
        let del = agenda.eventos(del: ahora)
        let lista = del.map { e in
            ReunionDia(id: e.id, titulo: e.titulo, inicio: e.inicio, fin: e.fin, invitados: e.invitados,
                       servicio: e.enlace.map { Tiempo.servicio($0.host ?? "") }, tieneEnlace: e.enlace != nil, esReunion: e.esReunion)
        }
        return (lista, Dictionary(del.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    @ViewBuilder private func contenido(_ ahora: Date) -> some View {
        let (lista, eventos) = reuniones(ahora)
        let plan = PlanDelDia.armar(reuniones: lista, huecos: agenda.huecos(desde: ahora, config: config), ahora: ahora)
        TarjetaAura(tono: .reunion, radio: AuroraMedida.widgetRadio, relleno: Self.relleno) {
            if let foco = plan.foco, let evento = eventos[foco.id] {
                conFoco(plan, foco, evento, ahora, eventos)
            } else {
                sinNada(plan, ahora)
            }
        }
    }

    // MARK: Con reunión

    private func conFoco(_ plan: PlanDelDia, _ foco: ReunionDia, _ evento: Agenda.Evento, _ ahora: Date, _ eventos: [String: Agenda.Evento]) -> some View {
        let cuenta = CuentaRegresiva.texto(hasta: plan.enCurso ? foco.fin : foco.inicio, desde: ahora)
        let rango = Frase.hora(foco.inicio) + " – " + Frase.hora(foco.fin)
        let donde = [rango, foco.servicio].compactMap { $0 }.joined(separator: " · ")
        let quienes = PlanDelDia.quienes(foco.invitados)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                RotuloPieza(plan.enCurso ? "Termina en" : "Empieza en", color: TonoAura.reunion.rotulo)
                Spacer(minLength: 4)
                Text(plan.restantes == 1 ? "1 hoy" : "\(plan.restantes) hoy").font(AuroraNotch.fila).foregroundStyle(AuroraNotch.suave)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                NumeroPuntos(texto: cuenta?.texto ?? "0")
                Text(cuenta?.unidad ?? "min").font(.system(size: 9, weight: .semibold)).foregroundStyle(AuroraNotch.sutil)
            }
            .padding(.top, 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((plan.enCurso ? "Termina en " : "Empieza en ") + (cuenta.map { $0.texto + " " + $0.unidad } ?? "unos minutos"))
            Text(foco.titulo).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8).help(foco.titulo)
            Text(donde).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(1).padding(.top, 1)
            if !quienes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 8.5, weight: .semibold))
                    Text(quienes).lineLimit(1)
                }
                .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.suave).padding(.top, 1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Con " + quienes)
            }
            if let lugar = evento.lugar { EtiquetaLugar(lugar: lugar).padding(.top, 1) }
            HStack(spacing: 4) {
                if let enlace = evento.enlace {
                    BotonAura("Unirse", icono: "video.fill", estilo: .lleno, compacto: true, ayuda: "Unirse a la videollamada: \(foco.titulo)") { acciones.unirse(enlace) }
                }
                BotonAura("Abrir", compacto: true, ayuda: "Abrir «\(foco.titulo)» en el calendario") { AbrirCalendario.evento(evento) }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            Spacer(minLength: 6)
            siguientes(plan, eventos)
        }
    }

    /// Lo que sigue hoy y el próximo hueco libre.
    private func siguientes(_ plan: PlanDelDia, _ eventos: [String: Agenda.Evento]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.bottom, 3)
            ForEach(plan.despues) { r in
                Button { if let e = eventos[r.id] { AbrirCalendario.evento(e) } } label: {
                    HStack(spacing: 6) {
                        Text(Frase.hora(r.inicio)).monospacedDigit().foregroundStyle(AuroraNotch.suave).frame(width: 34, alignment: .leading)
                        Text(r.titulo).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if eventos[r.id]?.lugar != nil { Image(systemName: "mappin").font(.system(size: 8)).foregroundStyle(AuroraNotch.suave) }
                        if r.tieneEnlace { Image(systemName: "video.fill").font(.system(size: 8)).foregroundStyle(AuroraNotch.suave) }
                    }
                    .font(AuroraNotch.fila)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PulsadoAurora())
                .help("Abrir «\(r.titulo)» en el calendario")
                .accessibilityLabel("\(Frase.hora(r.inicio)), \(r.titulo)")
            }
            if plan.sinMostrar > 0 {
                Text("y \(plan.sinMostrar) más").font(AuroraNotch.fila).foregroundStyle(AuroraNotch.suave)
            }
            if let h = plan.huecos.first { hueco(h) }
        }
    }

    private func hueco(_ h: Intervalo) -> some View {
        let verde = Color(.sRGB, red: 0.57, green: 0.92, blue: 0.64)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(verde, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                .frame(width: 8, height: 8).accessibilityHidden(true)
            Text("Libre " + FormatoHuecos.rango(h)).font(AuroraNotch.fila).foregroundStyle(verde).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            Button { AbrirCalendario.nuevo(en: h.inicio) } label: {
                Text("Agendar").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background { Capsule().fill(AuroraNotch.botonVidrio) }
                    .contentShape(Capsule())
            }
            .buttonStyle(PulsadoAurora())
            .help("Nueva reunión en este hueco (se abre en el calendario)")
            .accessibilityLabel("Agendar en el hueco libre, " + FormatoHuecos.rango(h))
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sin reuniones

    private func sinNada(_ plan: PlanDelDia, _ ahora: Date) -> some View {
        let cambio = CambioAgenda.proximo(ocupados: agenda.eventos.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }, ahora: ahora)
        let frase: String
        if let c = cambio.cambio {
            let dia = Calendar.current.isDate(c, inSameDayAs: ahora) ? "" : " " + FormatoHuecos.dia(c)
            frase = (cambio.ocupadoAhora ? "Ocupado hasta " : "Libre hasta ") + FormatoHuecos.hora(c).texto + " " + FormatoHuecos.hora(c).periodo + dia
        } else {
            frase = "Nada más en la agenda"
        }
        return VStack(alignment: .leading, spacing: 0) {
            RotuloPieza("Reuniones", color: TonoAura.reunion.rotulo)
            Spacer(minLength: 0)
            Text("Sin reuniones hoy").font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2)
            Text(frase).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(2).padding(.top, 1)
            HStack(spacing: 4) {
                BotonAura("Abrir", compacto: true, ayuda: "Abrir el día en el calendario") { AbrirCalendario.dia(ahora) }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            if let h = plan.huecos.first { hueco(h).padding(.top, 10) }
        }
    }
}

// MARK: - Agentes

/// Una fila de la tarjeta con lo que hace al tocarla.
private struct EntradaAgente {
    let fila: FilaTarjetaAgentes
    let abrir: () -> Void
}

struct TarjetaAgentesLanzador: View {
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    var tablero: TableroIsla?
    let ahora: Date
    let acciones: AccionesIsla
    let abrirAgentes: () -> Void
    var simulado = false

    private static let relleno = EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)
    private static let maximo = 4
    /// Una sesión lista que lleva más de esto quieta ya no es noticia.
    private static let vigenciaListas: TimeInterval = 3 * 3600

    @MainActor private func entradas() -> [EntradaAgente] {
        var salida: [EntradaAgente] = []
        let t = tablero?.vigente(ahora: ahora)
        for s in claude.sesiones {
            let estado: FilaTarjetaAgentes.Estado = s.estado == .esperando ? .espera : (s.estado == .trabajando ? .trabaja : .termino)
            if estado == .termino, ahora.timeIntervalSince(s.desde) > Self.vigenciaListas { continue }
            let paso: String
            switch s.estado {
            case .esperando: paso = s.espera.isEmpty ? "Te espera" : s.espera
            case .trabajando: paso = s.actividad.isEmpty ? "Trabajando" : s.actividad
            case .lista: paso = s.resumen.isEmpty ? "Lista" : s.resumen
            }
            salida.append(EntradaAgente(fila: FilaTarjetaAgentes(id: "s" + s.id, nombre: s.nombre, estado: estado, desde: s.desde, paso: paso)) { SesionesClaude.abrir(s) })
        }
        if let t {
            let vivas = Set(claude.sesiones.map(\.id))
            for c in t.enCurso where c.sesion.map({ !vivas.contains($0) }) ?? true {
                let estado: FilaTarjetaAgentes.Estado = c.estado == .espera ? .espera : .trabaja
                let destino = DestinoCorrida.de(c, sesiones: claude.sesiones)
                salida.append(EntradaAgente(fila: FilaTarjetaAgentes(id: "c\(c.id)", nombre: c.titulo, estado: estado, desde: c.inicio,
                                                             paso: [c.proyecto, c.resumen].compactMap { $0 }.first ?? c.agente)) { destino?.abrir() ?? SesionesClaude.abrir() })
            }
            for c in TableroCentro.terminadas(t, limite: 3) {
                let fin = c.fin ?? c.inicio ?? ahora
                guard ahora.timeIntervalSince(fin) <= Self.vigenciaListas else { continue }
                let destino = DestinoCorrida.de(c, sesiones: claude.sesiones)
                salida.append(EntradaAgente(fila: FilaTarjetaAgentes(id: "t\(c.id)", nombre: c.titulo, estado: c.estado == .fallo ? .alerta : .termino, desde: fin,
                                                             paso: c.estado == .fallo ? "Falló" : (c.resumen ?? "Terminó"))) { destino?.abrir() ?? SesionesClaude.abrir() })
            }
        }
        for a in agentes.agentes {
            let alerta = a.estado == .alerta || a.estado == .caido
            let paso = a.error ?? a.alertas.first ?? (a.resumen.isEmpty ? (alerta ? "Revisa su estado" : "En calma") : a.resumen)
            salida.append(EntradaAgente(fila: FilaTarjetaAgentes(id: "a" + a.nombre, nombre: a.nombre, estado: alerta ? .alerta : .quieto, desde: a.actualizado, paso: paso)) { abrirAgentes() })
        }
        return salida
    }

    var body: some View {
        let todas = entradas()
        let (visibles, ocultas) = PlanAgentes.visibles(todas.map(\.fila), maximo: Self.maximo)
        let cab = PlanAgentes.cabecera(todas.map(\.fila))
        let espera = cab.numero > 0 && visibles.first.map { $0.estado == .espera || $0.estado == .alerta } == true
        let abrir = Dictionary(todas.map { ($0.fila.id, $0.abrir) }, uniquingKeysWith: { a, _ in a })
        TarjetaAura(tono: espera ? .agentes : .trabaja, radio: AuroraMedida.widgetRadio, relleno: Self.relleno) {
            VStack(alignment: .leading, spacing: 0) {
                cabecera(cab, espera: espera, hay: !todas.isEmpty)
                if visibles.isEmpty {
                    Spacer(minLength: 0)
                    Text("Nada en marcha").font(AuroraNotch.titulo).tracking(-0.16)
                    Text("Cuando una sesión de Claude trabaje o te espere, aparece aquí.").font(AuroraNotch.resumenFuente)
                        .foregroundStyle(AuroraNotch.resumen).fixedSize(horizontal: false, vertical: true).padding(.top, 1)
                    HStack {
                        BotonAura("Abrir Claude", compacto: true, ayuda: "Abrir Claude") { SesionesClaude.abrir() }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                            fila(f, abrir: abrir[f.id] ?? {})
                        }
                    }
                    .padding(.top, 8)
                    Spacer(minLength: 4)
                    if ocultas > 0 {
                        Button(action: abrirAgentes) {
                            HStack(spacing: 4) {
                                Text("y \(ocultas) más").font(AuroraNotch.fila)
                                Image(systemName: "arrow.up.forward").font(.system(size: 8, weight: .bold))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(AuroraNotch.suave)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PulsadoAurora())
                        .help("Ver todos los agentes en la isla")
                        .accessibilityLabel("Ver los \(ocultas) agentes restantes")
                    }
                }
            }
        }
    }

    private func cabecera(_ cab: (numero: Int, leyenda: String), espera: Bool, hay: Bool) -> some View {
        let modo: ChispaViva.Modo = espera ? .espera : (cab.numero > 0 ? .trabaja : .quieta)
        return HStack(alignment: .center, spacing: 8) {
            ChispaViva(modo: modo, lado: 22)
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Agentes", color: (espera ? TonoAura.agentes : TonoAura.trabaja).rotulo)
                Text(cab.numero > 0 ? "\(cab.numero) \(cab.leyenda)" : (hay ? "En calma" : "Sin actividad"))
                    .font(AuroraNotch.titulo).tracking(-0.16).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            BotonAura(icono: "mic.fill", estilo: .vidrio, redondo: true, compacto: true, ayuda: "Dictar un encargo para un agente", accion: acciones.dictarEncargo)
        }
        .accessibilityElement(children: .contain)
    }

    private func fila(_ f: FilaTarjetaAgentes, abrir: @escaping () -> Void) -> some View {
        let tiempo = f.desde.map { PlanAgentes.duracion(desde: $0, hasta: ahora) }
        let color: Color = {
            switch f.estado {
            case .espera: return AuroraAcento.hoy
            case .alerta: return Color(hex: 0xFFC24A)
            case .trabaja: return TonoAura.trabaja.luz2
            case .quieto: return AuroraNotch.suave
            case .termino: return AuroraAcento.bien
            }
        }()
        return HStack(spacing: 8) {
            Button(action: abrir) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.8), radius: f.estado == .quieto ? 0 : 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.nombre).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).help(f.nombre)
                        Text([f.paso, tiempo].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(AuroraNotch.suave).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsadoAurora())
            .accessibilityLabel("\(f.nombre), \(f.rotulo.lowercased())" + (tiempo.map { ", \($0)" } ?? ""))
            .accessibilityHint(f.paso)
            if f.estado == .espera {
                BotonAura(f.accion, estilo: .lleno, compacto: true, ayuda: "\(f.accion): \(f.nombre)", accion: abrir)
            } else {
                BotonAura(icono: "arrow.up.forward", estilo: .vidrio, redondo: true, compacto: true, ayuda: "\(f.accion): \(f.nombre)", accion: abrir)
            }
        }
        .padding(.vertical, 5)
    }
}
