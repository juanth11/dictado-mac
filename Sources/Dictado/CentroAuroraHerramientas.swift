import AppKit
import DictadoKit
import SwiftUI

// Sección Herramientas del Centro: los MCP, las skills y los plugins de Claude Code (y los MCP de Hermes) con cuántas veces se usó cada
// uno en 7 y 30 días. Lo activo que nunca se usa se destaca en ámbar: es lo que sobra o se olvidó. Solo lectura de la configuración y de
// los registros de sesión; de los MCP nunca llegan argumentos, entorno ni cabeceras.
// Fuente: `python3 -m centro herramientas --json`.

struct HerramientasAurora: View {
    let lectura: LecturaCentro<Herramientas>
    @Bindable var nav: NavegacionAurora
    let ahora: Date
    let simulado: Bool

    private static let alto: CGFloat = 690

    var body: some View {
        if let h = lectura.valor {
            DesplazableAurora(simulado: simulado) {
                VStack(spacing: AuroraCentro.separacion) {
                    tira(h)
                    HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                        mcp(h).frame(width: 430)
                        skills(h).frame(maxWidth: .infinity)
                        VStack(spacing: AuroraCentro.separacion) {
                            plugins(h)
                            hermes(h.hermes)
                        }
                        .frame(width: 320)
                    }
                    pie(h)
                }
            }
        } else {
            TarjetaVidrioGrande(alto: 200, relleno: EdgeInsets(top: 26, leading: 30, bottom: 26, trailing: 30)) {
                EstadoVacioAurora(icono: "wrench.and.screwdriver",
                                  titulo: lectura.cargando ? "Leyendo tus herramientas…" : (lectura.disponible ? "No se pudo leer el inventario" : "Las herramientas llegan con el centro"),
                                  detalle: lectura.cargando ? "Recorre tu configuración y el uso registrado en tus sesiones."
                                      : (lectura.fallo ?? "Cuando el centro esté configurado, aquí se ven tus MCP, skills y plugins con su uso."))
            }
        }
    }

    // MARK: Tira

    private func tira(_ h: Herramientas) -> some View {
        ResumenAurora(segmentos: ResumenCentro.herramientas(
            mcpActivos: h.servidores.filter(\.activo).count, mcpSinUso: HerramientasCentro.sinUso(h.servidores).count,
            skillsActivas: h.skills.filter(\.activa).count, skillsSinUso: HerramientasCentro.sinUso(h.skills).count,
            enReserva: h.skillsEnReserva, pluginsActivos: h.plugins.filter(\.activo).count, pluginsInstalados: h.plugins.count))
    }

    // MARK: MCP

    private func mcp(_ h: Herramientas) -> some View {
        let usados = h.servidores.filter { $0.activo && $0.uso.usos30 > 0 }
        let olvidados = HerramientasCentro.sinUso(h.servidores)
        let apagados = h.servidores.filter { !$0.activo }
        let mayor = usados.map(\.uso.usos30).max() ?? 0
        return TarjetaVidrioGrande(alto: Self.alto, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "MCP", cuenta: h.servidores.count)
                DesplazableAurora(simulado: simulado) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(usados) { s in FilaUsoAurora(titulo: s.nombre, sub: sub(s), usos30: s.uso.usos30, usos7: s.uso.usos7,
                                                             ultimo: HerramientasCentro.ultimoUso(s.uso, ahora: ahora), fraccion: HerramientasCentro.fraccionUso(s.uso.usos30, mayor: mayor),
                                                             detalle: s.uso.herramientas.prefix(3).map { "\($0.nombre) \($0.usos)" }.joined(separator: " · ")) }
                        if !olvidados.isEmpty {
                            grupo("Activos sin uso en 30 días", color: Color(hex: 0xFFC24A))
                            ForEach(olvidados) { s in FilaUsoAurora(titulo: s.nombre, sub: sub(s), usos30: 0, usos7: 0, ultimo: "sin uso", fraccion: 0, atenuada: false, aviso: true) }
                        }
                        if !apagados.isEmpty {
                            grupo("Apagados", color: AuroraCentro.sutil)
                            ForEach(apagados) { s in FilaUsoAurora(titulo: s.nombre, sub: sub(s), usos30: s.uso.usos30, usos7: s.uso.usos7, ultimo: "apagado", fraccion: 0, atenuada: true) }
                        }
                        if !h.integrados.isEmpty {
                            grupo("Integrados de la app", color: AuroraCentro.sutil)
                            ForEach(h.integrados.prefix(6)) { s in
                                FilaUsoAurora(titulo: s.nombre, sub: "no está en tu configuración", usos30: s.uso.usos30, usos7: s.uso.usos7,
                                              ultimo: HerramientasCentro.ultimoUso(s.uso, ahora: ahora), fraccion: HerramientasCentro.fraccionUso(s.uso.usos30, mayor: mayor), atenuada: true)
                            }
                            if h.integrados.count > 6 {
                                Text("y \(h.integrados.count - 6) más").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).padding(.top, 8)
                            }
                        }
                    }
                }
                .desvanecerAbajo()
            }
        }
    }

    private func sub(_ s: ServidorMCP) -> String {
        [HerramientasCentro.conexion(s), s.alcance == "usuario" ? "" : s.alcance, s.pideAutorizar ? "pide autorizar" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func grupo(_ titulo: String, color: Color) -> some View {
        RotuloPieza(titulo, color: color, grande: true).padding(.top, 16).padding(.bottom, 4)
    }

    // MARK: Skills

    private func skills(_ h: Herramientas) -> some View {
        let lista = HerramientasCentro.filtrar(h.skills, nav.filtroSkills)
        let mayor = h.skills.map(\.uso.usos30).max() ?? 0
        return TarjetaVidrioGrande(alto: Self.alto, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Skills", cuenta: lista.count) {
                    SelectorAurora(opciones: HerramientasCentro.Filtro.allCases, titulo: { $0.titulo }, elegida: $nav.filtroSkills)
                }
                if lista.isEmpty {
                    Text(nav.filtroSkills == .sinUso ? "Todas las skills activas se usaron en los últimos 30 días." : "Ninguna skill usada en los últimos 30 días.")
                        .font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).padding(.top, 8)
                }
                DesplazableAurora(simulado: simulado) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lista.prefix(120)) { s in
                            FilaUsoAurora(titulo: s.nombre, sub: s.descripcion.isEmpty ? s.origen : s.descripcion, usos30: s.uso.usos30, usos7: s.uso.usos7,
                                          ultimo: s.activa ? HerramientasCentro.ultimoUso(s.uso, ahora: ahora) : "apagada",
                                          fraccion: HerramientasCentro.fraccionUso(s.uso.usos30, mayor: mayor), atenuada: !s.activa,
                                          aviso: s.activa && s.uso.usos30 == 0 && nav.filtroSkills == .sinUso)
                        }
                        if lista.count > 120 {
                            Text("y \(lista.count - 120) más").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).padding(.top, 8)
                        }
                    }
                }
                .desvanecerAbajo()
            }
        }
    }

    // MARK: Plugins y Hermes

    private func plugins(_ h: Herramientas) -> some View {
        TarjetaVidrioGrande(alto: 330, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Plugins", cuenta: h.plugins.count)
                if h.plugins.isEmpty { Text("Sin plugins instalados.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave) }
                DesplazableAurora(simulado: simulado) {
                    VStack(spacing: 0) {
                        ForEach(h.plugins) { p in
                            HStack(spacing: 12) {
                                Text(p.nombre).font(AuroraCentro.cuerpo).lineLimit(1)
                                if let v = p.version { Text(v).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil) }
                                Spacer(minLength: 6)
                                Text(p.activo ? "activo" : "apagado").font(AuroraCentro.minimo).foregroundStyle(p.activo ? AuroraCentro.verdeClaro : AuroraCentro.sutil)
                            }
                            .frame(height: 30)
                            .opacity(p.activo ? 1 : 0.6)
                        }
                    }
                }
            }
        }
    }

    private func hermes(_ h: HerramientasHermes?) -> some View {
        TarjetaVidrioGrande(alto: Self.alto - 330 - AuroraCentro.separacion, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Hermes")
                if let h {
                    ForEach(Array(h.mcp.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 8) {
                            Text(m.nombre).font(AuroraCentro.cuerpo).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(!m.activo ? "apagado" : (m.usos30 == 0 ? "sin uso" : "\(m.usos30) en 30 d")).font(AuroraCentro.minimo)
                                .foregroundStyle(!m.activo ? AuroraCentro.sutil : (m.usos30 == 0 ? Color(hex: 0xFFC24A) : AuroraCentro.suave))
                        }
                        .frame(height: 28)
                        .opacity(m.activo ? 1 : 0.6)
                    }
                    Text("\(h.skillsTotal) skills instaladas").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).padding(.top, 4)
                    if let t = h.herramientas.first {
                        Text("Lo que más usa: \(t.nombre) (\(t.usos))").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text("Sin lectura del servidor: cuando responda, aparecen sus MCP y skills.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func pie(_ h: Herramientas) -> some View {
        let desde = h.usoDesde.flatMap(LecturaDia.fecha).map { TextoTiempo.diaCorto($0) }
        return Text("El uso se cuenta con las sesiones de Claude Code\(desde.map { " desde el \($0)" } ?? ""); «sin uso» es en 30 días. Solo lectura: nada se enciende ni se apaga desde aquí.")
            .font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }
}

/// Una fila de herramienta: nombre y una línea de detalle a la izquierda; a la derecha el uso de 30 días y el último uso; y una barra fina
/// debajo con su parte del más usado. `aviso` la pinta en ámbar (activa y nunca usada); `atenuada`, en gris (apagada o ajena).
struct FilaUsoAurora: View {
    let titulo: String
    let sub: String
    let usos30: Int
    let usos7: Int
    let ultimo: String
    let fraccion: Double
    var detalle = ""
    var atenuada = false
    var aviso = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(.system(size: 16, weight: .semibold)).tracking(-0.1).lineLimit(1).truncationMode(.middle)
                    Text(sub).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
                    if !detalle.isEmpty { Text(detalle).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave).lineLimit(1) }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(usos30 > 0 ? "\(usos30)" : "—").font(.system(size: 19, weight: .medium)).monospacedDigit()
                        .foregroundStyle(aviso ? Color(hex: 0xFFC24A) : (atenuada ? AuroraCentro.suave : .white))
                    Text(usos30 > 0 ? "7 d: \(usos7) · \(ultimo)" : ultimo).font(AuroraCentro.minimo).foregroundStyle(aviso ? Color(hex: 0xFFC24A) : AuroraCentro.sutil).lineLimit(1)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(aviso ? Color(hex: 0xFFC24A).opacity(0.5) : AuroraCentro.azulBloque.opacity(atenuada ? 0.4 : 0.9)).frame(width: g.size.width * fraccion)
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 8)
        .opacity(atenuada ? 0.75 : 1)
        .overlay(alignment: .bottom) { FiloAurora().opacity(0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titulo), \(sub). \(usos30 > 0 ? "\(usos30) usos en 30 días, \(usos7) en 7" : ultimo)")
    }
}
