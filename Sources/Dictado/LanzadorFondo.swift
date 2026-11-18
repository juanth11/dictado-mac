import AppKit
import DictadoKit
import SwiftUI

// El selector del fondo del lanzador (el botón de la foto). La lectura, la caché y el dibujo del fondo viven en `FondoEscritorio.swift`.

// MARK: - El selector del fondo

/// El botón de la foto abre esto: el fondo del Mac, las paletas propias de la app o una imagen tuya; si hay un espacio activo, elegir si el
/// fondo vale para todos o solo para él; el tema; y recuperar las apps ocultas.
struct SelectorFondo: View {
    @Bindable var estado: EstadoLanzador
    let acciones: AccionesLanzador
    @Environment(\.auroraTema) private var tema

    var body: some View {
        let actual = estado.fondo
        let espacio = estado.datos?.lanzador.espacio
        VStack(alignment: .leading, spacing: 2) {
            RotuloAurora(texto: "Fondo").padding(.horizontal, 8).padding(.bottom, 4)
            fila("Fondo del Mac", activo: actual == .mac, ayuda: "Usa el fondo de pantalla de esta pantalla") {
                Image(systemName: "desktopcomputer").font(.system(size: 12, weight: .medium)).foregroundStyle(tema.textoSuave).frame(width: 28)
            } accion: { acciones.elegirFondo(.mac) }
            ForEach(AuroraPaleta.allCases, id: \.rawValue) { p in
                fila(p.nombre, activo: actual == .paleta(p.rawValue), ayuda: "Paleta \(p.nombre)") {
                    HStack(spacing: -4) {
                        Circle().fill(p.tonoA).frame(width: 12, height: 12)
                        Circle().fill(p.tonoB).frame(width: 12, height: 12)
                    }
                    .frame(width: 28)
                } accion: { acciones.elegirFondo(.paleta(p.rawValue)) }
            }
            fila(esImagen(actual) ? "Otra imagen…" : "Elegir imagen…", activo: esImagen(actual), ayuda: "Abre un selector de archivos") {
                Image(systemName: "photo.on.rectangle").font(.system(size: 12, weight: .medium)).foregroundStyle(tema.textoSuave).frame(width: 28)
            } accion: { acciones.elegirImagen() }

            if let espacio {
                separador
                RotuloAurora(texto: "Vale para").padding(.horizontal, 8).padding(.bottom, 2)
                HStack(spacing: 4) {
                    ambito("Todos los espacios", activo: !estado.ambitoEspacio) { estado.ambitoEspacio = false }
                    ambito("Solo \(espacio.nombre)", activo: estado.ambitoEspacio) { estado.ambitoEspacio = true }
                }
                .padding(.horizontal, 8)
            }

            separador
            RotuloAurora(texto: "Tema").padding(.horizontal, 8).padding(.bottom, 2)
            HStack(spacing: 4) {
                ForEach([PreferenciaTema.automatico, .oscuro, .claro], id: \.rawValue) { t in
                    ambito(t.nombre, activo: estado.preferencia == t) { acciones.elegirTema(t) }
                }
            }
            .padding(.horizontal, 8)

            if !estado.ocultas.isEmpty {
                separador
                fila("Mostrar apps ocultas (\(estado.ocultas.count))", activo: false, ayuda: "Vuelve a mostrar las apps que ocultaste") {
                    Image(systemName: "eye").font(.system(size: 12, weight: .medium)).foregroundStyle(tema.textoSuave).frame(width: 28)
                } accion: { estado.mostrarOcultas() }
            }
        }
        .padding(8)
        .frame(width: AuroraLanzador.selectorAncho)
        .background { RoundedRectangle(cornerRadius: AuroraLanzador.selectorRadio, style: .continuous).fill(tema.mosaico.opacity(0.62)) }
        .vidrioAurora(radio: AuroraLanzador.selectorRadio, fuerte: true, sombra: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fondo del lanzador")
    }

    private func esImagen(_ f: FondoLanzador) -> Bool { if case .imagen = f { return true } else { return false } }

    private var separador: some View {
        Rectangle().fill(tema.fila).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4).accessibilityHidden(true)
    }

    private func fila<Icono: View>(_ titulo: String, activo: Bool, ayuda: String, @ViewBuilder icono: () -> Icono, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                icono()
                Text(titulo).font(AuroraTipo.fila).foregroundStyle(tema.textoPleno).lineLimit(1)
                Spacer(minLength: 0)
                if activo { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(tema.textoPleno) }
            }
            .padding(.horizontal, 8)
            .frame(height: AuroraLanzador.selectorFila)
            .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(activo ? tema.fila : .clear) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(titulo)
        .accessibilityHint(ayuda)
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }

    private func ambito(_ titulo: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(titulo).font(AuroraLanzador.chipFuente)
                .foregroundStyle(activo ? tema.fondoChipActivo : tema.textoChip)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 12).frame(height: AuroraLanzador.chipAlto)
                .background { Capsule().fill(activo ? tema.textoPleno : tema.fila) }
                .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel(titulo)
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }
}
