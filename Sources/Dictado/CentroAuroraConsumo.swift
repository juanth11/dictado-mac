import AppKit
import DictadoKit
import SwiftUI

// Sección Consumo del Centro: cuánto gastan (a tarifas de API, no la factura) Claude Code y Hermes. Arriba, la tira de cifras; debajo, a la
// izquierda Claude Code con sus 30 días en barras y el reparto por modelo y por proyecto, y a la derecha Hermes (la misma lectura del
// estado de su servidor). Lo que no se pudo leer se dice con su razón; nunca se rellena con ceros.
// Fuente: `python3 -m centro consumo --json` (Claude Code: ~/.claude/projects en solo lectura; Hermes: state.db del VPS por ssh, solo lectura).

struct ConsumoAurora: View {
    let lectura: LecturaCentro<Consumo>
    @Bindable var nav: NavegacionAurora
    let ahora: Date
    let simulado: Bool

    var body: some View {
        if let c = lectura.valor {
            DesplazableAurora(simulado: simulado) {
                VStack(spacing: AuroraCentro.separacion) {
                    tira(c)
                    HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                        claude(c).frame(maxWidth: .infinity)
                        hermes(c.hermes).frame(width: 440)
                    }
                    pie(c)
                }
            }
        } else {
            TarjetaVidrioGrande(alto: 200, relleno: EdgeInsets(top: 26, leading: 30, bottom: 26, trailing: 30)) { sinLectura }
        }
    }

    private var sinLectura: some View {
        EstadoVacioAurora(icono: "chart.bar.xaxis",
                          titulo: lectura.cargando ? "Leyendo el consumo…" : (lectura.disponible ? "No se pudo leer el consumo" : "El consumo llega con el centro"),
                          detalle: lectura.cargando ? "La primera vez recorre tus sesiones de Claude Code y tarda unos segundos."
                              : (lectura.fallo ?? "Cuando el centro esté configurado, aquí se ven los tokens y el costo equivalente de Claude Code y de Hermes."))
    }

    // MARK: Tira

    private func tira(_ c: Consumo) -> some View {
        let cc = c.claudeCode
        let m = nav.medidaConsumo
        let claude = cc.disponible ? (hoy: TextoConsumo.valor(cc.hoy, m), sieteDias: TextoConsumo.valor(cc.sieteDias, m), treintaDias: TextoConsumo.valor(cc.treintaDias, m)) : nil
        let hermes = c.hermes.disponible ? TextoConsumo.valor(c.hermes.treintaDias, m) : nil
        return ResumenAurora(segmentos: ResumenCentro.consumo(claudeCode: claude, hermes30: hermes)) {
            if !cc.disponible { sinDatos("Claude Code", cc.motivo ?? "Sin sesiones en los últimos 30 días.").frame(width: 360) }
            if !c.hermes.disponible { sinDatos("Hermes", "Sin lectura del servidor.").frame(width: 280) }
        }
    }

    private func sinDatos(_ titulo: String, _ detalle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RotuloPieza(titulo, color: AuroraCentro.suave, grande: true)
            Text(detalle).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Claude Code

    private func claude(_ c: Consumo) -> some View {
        let cc = c.claudeCode
        let m = nav.medidaConsumo
        return TarjetaVidrioGrande(alto: cc.disponible ? 664 : 190, relleno: EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26)) {
            VStack(alignment: .leading, spacing: 16) {
                CabezaTarjetaAurora(titulo: "Claude Code · últimos 30 días") {
                    SelectorAurora(opciones: [ConsumoCentro.Medida.costo, .tokens], titulo: { $0 == .costo ? "Costo" : "Tokens" }, elegida: $nav.medidaConsumo)
                }
                if cc.disponible {
                    resumenLinea(cc, m)
                    BarrasDiasAurora(dias: cc.dias, medida: m, alto: 214)
                    FiloAurora().padding(.top, 2)
                    HStack(alignment: .top, spacing: 32) {
                        reparto("Por modelo", cc.modelos, m, maximo: 5, ancho: 130)
                        reparto("Por proyecto", cc.proyectos, m, maximo: 7, ancho: 140)
                    }
                    Spacer(minLength: 0)
                } else {
                    EstadoVacioAurora(icono: "tray", titulo: "Sin sesiones en los últimos 30 días",
                                      detalle: cc.motivo ?? "No hay mensajes de Claude Code con uso registrado en esa ventana.")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// La línea bajo el título: promedio, tendencia y el día más alto. Lo que no se puede calcular no se dice.
    private func resumenLinea(_ cc: FuenteConsumo, _ m: ConsumoCentro.Medida) -> some View {
        let promedio = ConsumoCentro.promedioDiario(cc.dias, ultimos: 7, por: m)
        let variacion = ConsumoCentro.variacionSemanal(cc.dias, por: m)
        let alto = ConsumoCentro.diaMasAlto(cc.dias, por: m)
        return HStack(alignment: .firstTextBaseline, spacing: 24) {
            if let promedio {
                let texto = m == .costo ? "US$ \(Int(promedio.rounded()))" : TextoConsumo.tokens(Int(promedio))
                dato("Promedio diario (7 d)", texto)
            }
            if let variacion { dato("Frente a la semana anterior", ConsumoCentro.textoVariacion(variacion)) }
            if let alto { dato("Día más alto", ConsumoCentro.etiqueta(dia: alto.dia) + " · " + TextoConsumo.valor(alto.cifras, m)) }
            Spacer(minLength: 0)
        }
    }

    private func dato(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rotulo).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
            Text(valor).font(.system(size: 19, weight: .medium)).monospacedDigit().lineLimit(1)
        }
    }

    private func reparto(_ titulo: String, _ items: [ItemConsumo], _ m: ConsumoCentro.Medida, maximo: Int, ancho: CGFloat) -> some View {
        let mostrados = ConsumoCentro.agrupar(items, maximo: maximo)
        let partes = ConsumoCentro.reparto(mostrados, por: m)
        let total = mostrados.reduce(0) { $0 + ConsumoCentro.valor($1.cifras, m) }
        let mayor = partes.map { ConsumoCentro.valor($0.item.cifras, m) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            RotuloPieza(titulo, color: AuroraCentro.suave, grande: true).padding(.bottom, 4)
            if partes.isEmpty {
                Text("Sin datos").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
            }
            ForEach(partes, id: \.item.id) { p in
                let v = ConsumoCentro.valor(p.item.cifras, m)
                FilaRepartoAurora(nombre: p.item.nombre, valor: TextoConsumo.valor(p.item.cifras, m),
                                  secundario: total > 0 ? "\(Int((v / total * 100).rounded())) %" : nil,
                                  fraccion: mayor > 0 ? v / mayor : 0, anchoNombre: ancho)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Hermes

    private func hermes(_ h: FuenteConsumo) -> some View {
        let m = nav.medidaConsumo
        return TarjetaVidrioGrande(alto: h.disponible ? 664 : 190, relleno: EdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26)) {
            VStack(alignment: .leading, spacing: 16) {
                CabezaTarjetaAurora(titulo: "Hermes · últimos 30 días")
                if h.disponible {
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        dato("Hoy", TextoConsumo.valor(h.hoy, m))
                        dato("7 días", TextoConsumo.valor(h.sieteDias, m))
                        dato("Llamadas (30 d)", "\(h.treintaDias.mensajes)")
                        Spacer(minLength: 0)
                    }
                    BarrasDiasAurora(dias: h.dias, medida: m, color: Color(hex: 0xC8D6FF), alto: 96)
                    FiloAurora()
                    reparto("Por tarea", h.proyectos, m, maximo: 6, ancho: 150)
                    reparto("Por modelo", h.modelos, m, maximo: 3, ancho: 150).padding(.top, 8)
                    Spacer(minLength: 0)
                    fuenteHermes(h)
                } else {
                    EstadoVacioAurora(icono: "server.rack", titulo: "Sin lectura de Hermes", detalle: h.motivo ?? "No se pudo leer el servidor.",
                                      falta: "El uso sale del state.db del servidor, que se lee por ssh. Cuando el servidor responda, aparece aquí.")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func fuenteHermes(_ h: FuenteConsumo) -> some View {
        let edad = h.leido.map { TextoTiempo.hace($0, ahora) }
        return VStack(alignment: .leading, spacing: 4) {
            FrescuraAurora(texto: h.desactualizado ? "El servidor no respondió: se muestra la última lectura (\(edad ?? "sin fecha"))" : "Leído \(edad ?? "ahora") del servidor",
                           frescura: h.desactualizado ? .vieja : .vigente)
            if let c = h.costoFuente {
                Text("Costo a \(c).").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Pie

    private func pie(_ c: Consumo) -> some View {
        var partes = ["Costo equivalente a tarifas oficiales de la API\(c.pricingVersion.map { " (\($0))" } ?? ""), no la factura de la suscripción."]
        if c.claudeCode.incluyeSubagentes { partes.append("Incluye subagentes; un mensaje repetido en varias sesiones cuenta una vez.") }
        if !c.completo { partes.append("Faltan \(c.pendientes) archivos por leer: se completan en la próxima lectura.") }
        return Text(partes.joined(separator: " ")).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }
}
