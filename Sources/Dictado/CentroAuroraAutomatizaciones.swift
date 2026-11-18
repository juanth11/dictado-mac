import AppKit
import DictadoKit
import SwiftUI

// Sección Automatizaciones del Centro: todo lo programado y su salud. Arriba, cuántos piden atención, cuántos van al día y cuántos están
// apagados; debajo, en tres columnas: lo que pide mirar (falló, parado, atrasado, con "parado desde…"), lo que corre con su horario y su
// última corrida, y lo apagado con las fuentes de donde sale el inventario. Solo lectura: nada se enciende, apaga ni se ejecuta desde aquí.
// Fuente: `python3 -m centro automatizaciones --json` (LaunchAgents, crontab, tareas de Claude, Hermes y el cron del VPS, feeders, Tablero).

struct AutomatizacionesAurora: View {
    let lectura: LecturaCentro<Automatizaciones>
    let ahora: Date
    let simulado: Bool

    private static let alto: CGFloat = 700

    var body: some View {
        if let a = lectura.valor {
            let g = AutomatizacionesCentro.grupos(a.items)
            DesplazableAurora(simulado: simulado) {
                VStack(spacing: AuroraCentro.separacion) {
                    tira(a)
                    HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                        atencion(g.atencion).frame(width: 430)
                        corriendo(g.activos).frame(maxWidth: .infinity)
                        VStack(spacing: AuroraCentro.separacion) {
                            apagados(g.apagados)
                            fuentes(a)
                        }
                        .frame(width: 350)
                    }
                }
            }
        } else {
            TarjetaVidrioGrande(alto: 200, relleno: EdgeInsets(top: 26, leading: 30, bottom: 26, trailing: 30)) {
                EstadoVacioAurora(icono: "clock.arrow.2.circlepath",
                                  titulo: lectura.cargando ? "Revisando lo programado…" : (lectura.disponible ? "No se pudo leer lo programado" : "Las automatizaciones llegan con el centro"),
                                  detalle: lectura.fallo ?? "Cuando el centro esté configurado, aquí se ve todo lo programado en el Mac y en el servidor, con su última corrida.")
            }
        }
    }

    // MARK: Tira

    private func tira(_ a: Automatizaciones) -> some View {
        let r = a.resumen
        return ResumenAurora(segmentos: ResumenCentro.automatizaciones(r)) {
            VStack(alignment: .trailing, spacing: 4) {
                FrescuraAurora(texto: vps(a), frescura: a.vpsError != nil || a.vpsDesactualizado ? .vieja : .vigente)
                Text("Servidor · \(r.total) en total").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
            }
            .frame(width: 300, alignment: .trailing)
        }
    }

    private func vps(_ a: Automatizaciones) -> String {
        if let e = a.vpsError { return a.vpsLeido.map { "\(e); última lectura \(TextoTiempo.hace($0, ahora))" } ?? e }
        guard let l = a.vpsLeido else { return "Sin lectura del servidor" }
        return a.vpsDesactualizado ? "Última lectura \(TextoTiempo.hace(l, ahora))" : "Leído \(TextoTiempo.hace(l, ahora))"
    }

    // MARK: Atención

    private func atencion(_ items: [ItemAutomatizacion]) -> some View {
        TarjetaVidrioGrande(alto: Self.alto, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Piden atención", cuenta: items.count, color: items.isEmpty ? AuroraCentro.suave : Color(hex: 0xFFC24A))
                if items.isEmpty {
                    EstadoVacioAurora(icono: "checkmark.circle", titulo: "Nada pide atención", detalle: "Lo programado corrió cuando debía y ninguna corrida terminó mal.").padding(.top, 8)
                }
                DesplazableAurora(simulado: simulado) {
                    VStack(spacing: 0) {
                        ForEach(items) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(i.nombre).font(.system(size: 17, weight: .semibold)).tracking(-0.15).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    EstadoPuntoAurora(estado: i.estado)
                                }
                                Text(AutomatizacionesCentro.textoParado(i, ahora: ahora) ?? (i.detalle.isEmpty ? "Última corrida: " + AutomatizacionesCentro.textoMomento(i.ultima, ahora: ahora) : i.detalle))
                                    .font(AuroraCentro.cuerpo).foregroundStyle(EstadoPuntoAurora(estado: i.estado).color).fixedSize(horizontal: false, vertical: true)
                                Text([AutomatizacionesCentro.lugar(i.origen), i.horario].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
                                if !i.queHace.isEmpty {
                                    Text(i.queHace).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) { FiloAurora().opacity(0.5) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .desvanecerAbajo()
            }
        }
    }

    // MARK: Corriendo

    private func corriendo(_ items: [ItemAutomatizacion]) -> some View {
        TarjetaVidrioGrande(alto: Self.alto, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Programado y al día", cuenta: items.count)
                DesplazableAurora(simulado: simulado) {
                    VStack(spacing: 0) {
                        ForEach(items) { i in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(EstadoPuntoAurora(estado: i.estado).color).frame(width: 7, height: 7).offset(y: -1)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(i.nombre).font(.system(size: 15.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                    Text(sub(i)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(AutomatizacionesCentro.textoMomento(i.ultima, ahora: ahora)).font(AuroraCentro.cuerpo).monospacedDigit()
                                        .foregroundStyle(i.ultima == nil ? AuroraCentro.sutil : .white)
                                    Text(i.estado == .sinDato ? "última corrida" : (i.proxima.map { "sigue: " + AutomatizacionesCentro.textoMomento($0, ahora: ahora) } ?? "última corrida"))
                                        .font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
                                }
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { FiloAurora().opacity(0.4) }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(i.nombre), \(i.horario), última corrida \(AutomatizacionesCentro.textoMomento(i.ultima, ahora: ahora)), \(i.estado.texto)")
                        }
                    }
                }
                .desvanecerAbajo()
            }
        }
    }

    private func sub(_ i: ItemAutomatizacion) -> String {
        [AutomatizacionesCentro.lugar(i.origen), i.horario, i.estado == .sinDato ? i.detalle : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Apagados y fuentes

    private func apagados(_ items: [ItemAutomatizacion]) -> some View {
        TarjetaVidrioGrande(alto: Self.alto - 250 - AuroraCentro.separacion, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 8) {
                CabezaTarjetaAurora(titulo: "Apagadas", cuenta: items.count)
                DesplazableAurora(simulado: simulado) {
                    VStack(spacing: 0) {
                        ForEach(items) { i in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.nombre).font(AuroraCentro.cuerpo).lineLimit(1).truncationMode(.middle)
                                Text(AutomatizacionesCentro.textoParado(i, ahora: ahora) ?? (i.detalle.isEmpty ? AutomatizacionesCentro.lugar(i.origen) : i.detalle))
                                    .font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .opacity(i.propio ? 0.85 : 0.5)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .desvanecerAbajo()
            }
        }
    }

    private func fuentes(_ a: Automatizaciones) -> some View {
        TarjetaVidrioGrande(alto: 250, relleno: EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22)) {
            VStack(alignment: .leading, spacing: 4) {
                CabezaTarjetaAurora(titulo: "De dónde sale")
                ForEach(a.fuentes) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(f.nombre).font(AuroraCentro.denso).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(f.total == 0 ? (f.nota.isEmpty ? "vacío" : "vacío") : "\(f.total)").font(AuroraCentro.denso).monospacedDigit().foregroundStyle(f.total == 0 ? AuroraCentro.sutil : .white)
                    }
                    .frame(height: 22)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(f.nombre): \(f.total) " + (f.total == 0 ? f.nota : ""))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
