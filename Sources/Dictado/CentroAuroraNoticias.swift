import AppKit
import DictadoKit
import SwiftUI

// Sección Noticias del Centro: el radar por vertical. Cada noticia lleva su titular, la fuente, cuándo salió, por qué te importa y un botón
// para abrir el enlace (solo http o https). Arriba, las pastillas de los verticales; debajo, las noticias en dos columnas de filas, sin cajas.
// Fuente: `python3 -m centro noticias --json` (el último radar del brief del servidor; si no responde, el archivo local).

struct NoticiasAurora: View {
    let lectura: LecturaCentro<Noticias>
    @Bindable var nav: NavegacionAurora
    let ahora: Date
    let simulado: Bool
    var abrir: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var body: some View {
        if let n = lectura.valor, n.disponible {
            VStack(spacing: AuroraCentro.separacion) {
                cabecera(n)
                let elegidos = n.verticales.filter { $0.vertical == nav.verticalNoticias }
                let visibles = elegidos.isEmpty ? n.verticales : elegidos
                DesplazableAurora(simulado: simulado) {
                    HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                        ForEach(Array(columnas(visibles).enumerated()), id: \.offset) { _, col in
                            VStack(spacing: AuroraCentro.separacion) {
                                ForEach(col) { v in vertical(v) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        } else {
            TarjetaVidrioGrande(alto: 200, relleno: EdgeInsets(top: 26, leading: 30, bottom: 26, trailing: 30)) {
                EstadoVacioAurora(icono: "newspaper",
                                  titulo: lectura.cargando ? "Leyendo el radar…" : (lectura.valor != nil ? "Sin noticias por ahora" : (lectura.disponible ? "No se pudo leer el radar" : "Las noticias llegan con el centro")),
                                  detalle: lectura.valor?.motivo ?? lectura.fallo ?? "Cuando el centro esté configurado, aquí se ve lo que el radar encuentra por cada frente tuyo.")
            }
        }
    }

    // MARK: Cabecera

    private func cabecera(_ n: Noticias) -> some View {
        HStack(spacing: 12) {
            SelectorAurora(opciones: [String?.none] + n.verticales.map { Optional($0.vertical) },
                           titulo: { $0 ?? "Todas (\(n.total))" }, elegida: $nav.verticalNoticias)
            Spacer(minLength: 12)
            if let g = n.generado {
                let dias = n.diasSinActualizar ?? 0
                FrescuraAurora(texto: "Radar \(dias == 0 ? "de hoy" : (dias == 1 ? "de ayer" : "de hace \(dias) días")) · \(TextoTiempo.hace(g, ahora)) · \(n.origen ?? "")",
                               frescura: Frescura.de(dias: dias))
            }
        }
        .frame(height: 32)
    }

    /// Reparte los verticales en dos columnas, equilibrando por cantidad de noticias (el más grande primero).
    private func columnas(_ v: [VerticalNoticias]) -> [[VerticalNoticias]] {
        guard v.count > 1 else { return [v] }
        var cols: [[VerticalNoticias]] = [[], []]
        var pesos = [0, 0]
        for x in v.sorted(by: { $0.items.count > $1.items.count }) {
            let i = pesos[0] <= pesos[1] ? 0 : 1
            cols[i].append(x)
            pesos[i] += x.items.count + 1
        }
        return cols
    }

    // MARK: Un vertical

    private func vertical(_ v: VerticalNoticias) -> some View {
        TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 18, leading: 24, bottom: 8, trailing: 24)) {
            VStack(alignment: .leading, spacing: 0) {
                CabezaTarjetaAurora(titulo: v.vertical, cuenta: v.items.count, color: AuroraCentro.azulBloque.opacity(0.95)).padding(.bottom, 4)
                ForEach(Array(v.items.enumerated()), id: \.element.id) { i, noticia in
                    if i > 0 { FiloAurora().opacity(0.6) }
                    fila(noticia)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // la tarjeta mide lo que mide su contenido, no se estira
    }

    private func fila(_ n: NoticiaCentro) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(n.titulo).font(.system(size: 17.5, weight: .semibold)).tracking(-0.15).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(n.fuente.isEmpty ? "Fuente sin nombre" : n.fuente).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave).lineLimit(1)
                    Text("·").foregroundStyle(AuroraCentro.sutil)
                    Text(NoticiasCentro.cuando(n)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).lineLimit(1)
                }
                if !n.porQue.isEmpty {
                    Text(n.porQue).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let url = n.url {
                BotonAura(icono: "arrow.up.right", estilo: .oscuro, redondo: true, ayuda: "Abrir la noticia en el navegador") { abrir(url) }
                    .accessibilityLabel("Abrir: \(n.titulo)")
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}
