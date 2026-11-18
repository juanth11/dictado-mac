import AppKit
import DictadoKit
import SwiftUI

// Sección Finanzas del Centro: el resumen del ledger (la única contabilidad) en filas finas, sin cifra gigante: patrimonio, liquidez y neto
// del mes; el colchón como regla con su piso; los últimos meses con ingresos y egresos; y los próximos pagos. Dos fuentes viejas
// (proyección de caja y MRR de Orbita) se muestran con su edad bien visible, o como "sin datos desde…" si nunca tuvieron cifras.
// Fuente: `python3 -m centro finanzas --json` (lee el dashboard del módulo de finanzas y `_sistema/status`; no escribe nada).

struct FinanzasAurora: View {
    let lectura: LecturaCentro<Finanzas>
    let abrir: (String) -> Void
    let simulado: Bool

    var body: some View {
        if let f = lectura.valor, f.disponible {
            DesplazableAurora(simulado: simulado) {
                HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                    resumen(f).frame(maxWidth: .infinity)
                    VStack(spacing: AuroraCentro.separacion) {
                        pagos(f)
                        fuentes(f)
                    }
                    .frame(width: 480)
                }
            }
        } else {
            TarjetaVidrioGrande(alto: 200, relleno: EdgeInsets(top: 26, leading: 30, bottom: 26, trailing: 30)) {
                EstadoVacioAurora(icono: "banknote",
                                  titulo: lectura.cargando ? "Leyendo finanzas…" : (lectura.valor != nil ? "No se encontró el ledger" : (lectura.disponible ? "No se pudo leer finanzas" : "Finanzas llega con el centro")),
                                  detalle: lectura.valor != nil ? "El módulo de finanzas no dejó su dashboard (data.json) en el cerebro."
                                      : (lectura.fallo ?? "Cuando el centro esté configurado, aquí se ven el patrimonio, el colchón y los próximos pagos."))
            }
        }
    }

    // MARK: Resumen

    private func resumen(_ f: Finanzas) -> some View {
        TarjetaVidrioGrande(alto: 690, relleno: EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    RotuloPieza("Ledger de finanzas", color: AuroraCentro.suave, grande: true)
                    Spacer(minLength: 8)
                    if let dias = f.diasSinActualizar {
                        FrescuraAurora(texto: "Actualizado " + FinanzasCentro.edad(FuenteFechada(fecha: f.actualizado, dias: dias)), frescura: Frescura.de(dias: dias))
                    }
                }
                .padding(.bottom, 8)
                fila("Patrimonio neto", f.patrimonio, nota: f.delta.map { "\($0 >= 0 ? "+" : "")\(FinanzasCentro.pesos($0)) frente al corte anterior" })
                FiloAurora()
                fila("Liquidez", f.liquidez, nota: nil)
                FiloAurora()
                fila("Neto del mes", f.netoMes, nota: [f.ingresoMes.map { "ingresos \(FinanzasCentro.pesos($0))" }, f.egresoMes.map { "egresos \(FinanzasCentro.pesos($0))" }].compactMap { $0 }.joined(separator: " · "),
                     color: f.netoMes.map { $0 >= 0 ? AuroraCentro.verdeClaro : Color(hex: 0xFF8F70) })
                FiloAurora()
                colchon(f).padding(.vertical, 16)
                FiloAurora()
                meses(f).padding(.top, 16)
                Spacer(minLength: 0)
                if !f.alertas.isEmpty {
                    ForEach(f.alertas, id: \.self) { a in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold))
                            Text(a).font(AuroraCentro.detalle).lineLimit(2)
                        }
                        .foregroundStyle(Color(hex: 0xFFC24A))
                    }
                }
            }
        }
    }

    private func fila(_ rotulo: String, _ valor: Double?, nota: String?, color: Color? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rotulo).font(AuroraCentro.tituloTarjeta)
                if let nota, !nota.isEmpty { Text(nota).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let valor {
                Text(FinanzasCentro.pesos(valor)).font(.system(size: 28, weight: .light)).monospacedDigit().foregroundStyle(color ?? .white)
            } else {
                Text("sin dato").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.sutil)
            }
        }
        .frame(height: 62)
        .accessibilityElement(children: .combine)
    }

    /// El colchón como una regla: lo acumulado, el piso (marca) y la meta (el fin de la regla).
    private func colchon(_ f: Finanzas) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colchón de emergencia").font(AuroraCentro.tituloTarjeta)
                Spacer(minLength: 8)
                if let c = f.colchon { Text(FinanzasCentro.pesos(c)).font(.system(size: 22, weight: .light)).monospacedDigit() }
            }
            if let r = FinanzasCentro.regla(actual: f.colchon, piso: f.colchonPiso, meta: f.colchonMeta) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                        Capsule().fill(AuroraCentro.azulBloque).frame(width: g.size.width * r.actual, height: 8)
                        if let piso = r.piso {
                            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2, height: 18).offset(x: g.size.width * piso - 1)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 18)
                HStack {
                    Text("0").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
                    Spacer()
                    if let piso = f.colchonPiso { Text("piso \(FinanzasCentro.pesos(piso))").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave) }
                    Spacer()
                    if let meta = f.colchonMeta { Text("meta \(FinanzasCentro.pesos(meta))").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Ingresos y egresos de los últimos meses con datos: dos barras finas por mes. Un mes sin datos no se dibuja.
    private func meses(_ f: Finanzas) -> some View {
        let escala = FinanzasCentro.escalaMeses(f.historico)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                RotuloPieza("Últimos meses con datos", color: AuroraCentro.suave, grande: true)
                Spacer()
                leyenda(AuroraCentro.azulBloque, "ingresos")
                leyenda(Color.white.opacity(0.42), "egresos")
            }
            if f.historico.isEmpty {
                Text("El ledger no trae meses cerrados.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
            } else {
                if let ultimo = f.historico.last, mesesSinDatos(ultimo.mes) >= 2 {
                    Text("El ledger no trae ingresos ni egresos de \(mesesSinDatos(ultimo.mes) == 1 ? "un mes" : "\(mesesSinDatos(ultimo.mes) - 1) meses") posteriores a \(FinanzasCentro.nombreMes(ultimo.mes)).")
                        .font(AuroraCentro.minimo).foregroundStyle(Color(hex: 0xFFC24A))
                }
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach(f.historico) { m in
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 4) {
                                barra(m.ingreso / escala, AuroraCentro.azulBloque)
                                barra(m.egreso / escala, Color.white.opacity(0.42))
                            }
                            .frame(height: 150, alignment: .bottom)
                            Text(FinanzasCentro.nombreMes(m.mes)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave)
                            Text(FinanzasCentro.pesos(m.neto)).font(AuroraCentro.minimo).monospacedDigit().foregroundStyle(m.neto >= 0 ? AuroraCentro.verdeClaro : Color(hex: 0xFF8F70))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(FinanzasCentro.nombreMes(m.mes)): ingresos \(FinanzasCentro.pesos(m.ingreso)), egresos \(FinanzasCentro.pesos(m.egreso))")
                    }
                }
            }
        }
    }

    /// Cuántos meses pasaron desde el último mes con datos hasta el actual (0 si es el actual).
    private func mesesSinDatos(_ mes: String) -> Int {
        let p = mes.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return 0 }
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return ((c.year ?? p[0]) - p[0]) * 12 + ((c.month ?? p[1]) - p[1])
    }

    private func barra(_ f: Double, _ color: Color) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3, style: .continuous)
            .fill(color).frame(width: 20, height: max(3, 150 * f))
    }

    private func leyenda(_ color: Color, _ texto: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(texto).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
        }
    }

    // MARK: Pagos y fuentes

    private func pagos(_ f: Finanzas) -> some View {
        TarjetaVidrioGrande(alto: 404, relleno: EdgeInsets(top: 20, leading: 26, bottom: 14, trailing: 26)) {
            VStack(alignment: .leading, spacing: 4) {
                CabezaTarjetaAurora(titulo: "Próximos pagos", cuenta: f.pagos.count) {
                    if let enlace = f.enlace {
                        BotonAura("Abrir el tablero", icono: "arrow.up.forward.app", estilo: .oscuro, grande: false, ayuda: "Abre el tablero de finanzas del cerebro") { abrir(enlace) }
                    }
                }
                if f.pagos.isEmpty { Text("Sin pagos a la vista.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).padding(.top, 8) }
                ForEach(f.pagos.prefix(6)) { p in
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.concepto).font(.system(size: 15.5, weight: .medium)).lineLimit(1)
                                Text(cuando(p)).font(AuroraCentro.minimo).foregroundStyle(p.critico ? Color(hex: 0xFFC24A) : AuroraCentro.sutil)
                            }
                            Spacer(minLength: 6)
                            Text(FinanzasCentro.pesosCompletos(p.monto)).font(AuroraCentro.cuerpo).monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        FiloAurora().opacity(0.5)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cuando(_ p: PagoProximo) -> String {
        let dia = p.vence.map { TextoTiempo.diaCorto($0) } ?? ""
        let faltan = p.dias.map { $0 == 0 ? "hoy" : ($0 == 1 ? "mañana" : "en \($0) d") } ?? ""
        return [dia, faltan, p.critico ? "crítico" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func fuentes(_ f: Finanzas) -> some View {
        TarjetaVidrioGrande(alto: 270, relleno: EdgeInsets(top: 20, leading: 26, bottom: 16, trailing: 26)) {
            VStack(alignment: .leading, spacing: 12) {
                CabezaTarjetaAurora(titulo: "Fuentes aparte")
                fuente("Proyección de caja, burn y runway", disponible: f.proyeccionDisponible, fuente: f.proyeccionFuente,
                       valores: [f.caja.map { "caja \(FinanzasCentro.pesos($0))" }, f.burn.map { "burn \(FinanzasCentro.pesos($0))/mes" },
                                 f.runwayMeses.map { "runway \(String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",")) meses" }].compactMap { $0 },
                       vacio: "Sin datos: la proyección nunca llegó a tener cifras.")
                FiloAurora()
                fuente("Orbita · ingresos recurrentes", disponible: f.orbitaDisponible, fuente: f.orbitaFuente,
                       valores: [f.mrr.map { "MRR \(FinanzasCentro.pesos($0))" }].compactMap { $0 }, vacio: "Sin datos de Orbita.")
                Spacer(minLength: 0)
                Text("En pesos colombianos. Aquí solo se lee: el ledger es la única contabilidad.").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fuente(_ titulo: String, disponible: Bool, fuente: FuenteFechada?, valores: [String], vacio: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.system(size: 16, weight: .semibold))
            if disponible, !valores.isEmpty {
                Text(valores.joined(separator: " · ")).font(.system(size: 19, weight: .light)).monospacedDigit()
            } else {
                Text(vacio).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
            }
            if let fuente {
                FrescuraAurora(texto: (disponible && !valores.isEmpty ? "Dato " : "Sin datos desde ") + (disponible && !valores.isEmpty ? FinanzasCentro.edad(fuente) : (fuente.fecha.map { "el " + TextoTiempo.diaCorto($0) } ?? "antes")) +
                               (fuente.dias > 2 ? " · el feeder dejó de correr" : ""), frescura: Frescura.de(dias: fuente.dias))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
