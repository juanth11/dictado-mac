import AppKit
import DictadoKit
import SwiftUI

// El lugar de una reunión (`Agenda.Evento.lugar`): un icono de ubicación con el texto; el clic abre Mapas.

@MainActor
enum AbrirLugar {
    static func enMapas(_ lugar: String) {
        if let url = LugarEvento.urlMapas(lugar) { NSWorkspace.shared.open(url) }
    }
}

/// «📍 Calle 93 #11-27»: una línea; clic abre Mapas con ese lugar.
struct EtiquetaLugar: View {
    let lugar: String
    var fuente: Font = AuroraNotch.resumenFuente
    var color: Color = AuroraNotch.suave
    /// Solo el icono (para filas angostas); el texto va en la ayuda.
    var soloIcono = false

    var body: some View {
        Button { AbrirLugar.enMapas(lugar) } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin").font(.system(size: 9, weight: .semibold))
                if !soloIcono { Text(lugar).lineLimit(1) }
            }
            .font(fuente).foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .help("Abrir «\(lugar)» en Mapas")
        .accessibilityLabel("Lugar: \(lugar). Abrir en Mapas")
    }
}
