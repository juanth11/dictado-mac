import AppKit
import DictadoKit
import SwiftUI

// Sección Mac del Centro: la pestaña Mac de la isla a tamaño completo. El diagnóstico en una frase, los cinco orbes (en calma van en
// blanco; el que pide atención toma color según los umbrales de Salud), quién consume memoria y procesador, y lo que se puede recuperar
// sin riesgo. Nada se borra desde aquí: los botones abren Salud del Mac en Limpieza, donde cada cosa se confirma.

struct MacCentroAurora: View {
    let salud: EstadoSalud
    let abrirSalud: (_ explicar: Bool) -> Void
    let simulado: Bool

    var body: some View {
        VStack(spacing: AuroraCentro.separacion) {
            diagnostico
            HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                consumidores
                recuperable.frame(width: 430)
            }
        }
    }

    private func orbe(_ g: Gravedad) -> TonoOrbe { g == .bien ? .calma : (g == .atento ? .atento : .mal) }

    private func gigas(_ bytes: Double) -> String {
        let g = bytes / 1e9
        return g < 10 ? String(format: "%.1f", g).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f", g)
    }

    /// El estado térmico no da grados (macOS no los expone sin permisos): se dice con palabras y el destello marca el nivel.
    private var termica: (texto: String, valor: Double) {
        switch salud.termico {
        case .nominal: return ("Normal", 0.12)
        case .fair: return ("Tibia", 0.45)
        case .serious: return ("Alta", 0.75)
        case .critical: return ("Crítica", 1)
        @unknown default: return ("Normal", 0.12)
        }
    }

    // MARK: Diagnóstico y orbes

    private var diagnostico: some View {
        let d = salud.diagnostico
        let color: Color = d.gravedad == .bien ? AuroraCentro.verdeClaro : Tono.gravedad(d.gravedad).claro
        let lado = AuroraCentro.orbe
        return TarjetaVidrioGrande(alto: 392, relleno: EdgeInsets(top: 22, leading: 28, bottom: 22, trailing: 28)) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza(d.titulo, color: color, grande: true)
                Text(d.frase.hasSuffix(".") ? String(d.frase.dropLast()) : d.frase).font(AuroraCentro.titulo).tracking(-0.3).foregroundStyle(Color.white.opacity(0.94)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    OrbeAurora(titulo: "Procesador", numero: String(format: "%.0f%%", salud.cpu * 100), valor: salud.cpu, tono: orbe(salud.gravedadCPU), cifra: 44, lado: lado)
                        .frame(maxWidth: .infinity)
                    OrbeAurora(titulo: "Memoria", numero: String(format: "%.0f", salud.memoriaUsada / 1e9),
                               unidad: String(format: "de %.0f GB", salud.memoriaTotal / 1.073741824e9),
                               valor: salud.memoriaUsada / max(1, salud.memoriaTotal), tono: orbe(salud.gravedadMemoria), cifra: 44, lado: lado)
                        .frame(maxWidth: .infinity)
                    OrbeAurora(titulo: "Gráficos", numero: String(format: "%.0f%%", salud.gpu * 100), valor: salud.gpu, tono: orbe(salud.gravedadGPU), cifra: 44, lado: lado)
                        .frame(maxWidth: .infinity)
                    OrbeAurora(titulo: "Libres", numero: gigas(salud.discoLibre), unidad: "GB", valor: salud.discoLibre / max(1, salud.discoTotal),
                               tono: orbe(salud.gravedadDisco), cifra: 44, lado: lado)
                        .frame(maxWidth: .infinity)
                    OrbeAurora(titulo: "Temp.", numero: termica.texto, valor: termica.valor, tono: orbe(salud.gravedadTermica), cifra: 28, lado: lado)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Quién consume

    private var consumidores: some View {
        let porMemoria = salud.consumidores.sorted { $0.memoria > $1.memoria }.prefix(5)
        let porCPU = salud.consumidores.sorted { $0.cpu > $1.cpu }.prefix(5)
        return TarjetaVidrioGrande(alto: 340) {
            HStack(alignment: .top, spacing: 28) {
                lista("Memoria", Array(porMemoria), valor: { Medida.bytes($0.memoria) }, fraccion: { $0.memoria / max(1, salud.memoriaTotal) * 2.5 })
                lista("Procesador", Array(porCPU), valor: { Medida.porcentaje($0.cpu) }, fraccion: { $0.cpu * 2.5 })
            }
        }
    }

    private func lista(_ titulo: String, _ filas: [Consumidor], valor: @escaping (Consumidor) -> String, fraccion: @escaping (Consumidor) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RotuloPieza("Quién usa más · " + titulo, color: AuroraCentro.suave, grande: true)
            if filas.isEmpty { Text("Midiendo…").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave) }
            ForEach(filas) { c in
                HStack(spacing: 12) {
                    Group {
                        if let icono = c.icono {
                            Image(nsImage: icono).resizable().scaledToFit()
                        } else {
                            Image(systemName: c.simbolo).font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.nombre).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(valor(c)).font(AuroraCentro.cuerpo).monospacedDigit().foregroundStyle(AuroraCentro.resumen)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, g.size.width * min(1, max(0, fraccion(c)))))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(c.nombre): \(valor(c))")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Recuperable

    private var recuperable: some View {
        let calculando = salud.analizando && salud.limpiables.isEmpty
        let seguras = salud.limpiables.filter(\.segura).sorted { $0.bytes > $1.bytes }
        let detalle = seguras.prefix(3).map { "\($0.titulo) \(Medida.bytes(Double($0.bytes)))" }.joined(separator: ", ")
        return TarjetaAuraGrande(tono: .verde, alto: 340) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Puedes recuperar sin riesgo", color: TonoAura.verde.rotulo, grande: true)
                if calculando {
                    Text("Calculando…").font(.system(size: 34, weight: .ultraLight)).padding(.top, 12)
                } else {
                    Cifra(numero: gigas(Double(salud.recuperable)), unidad: "GB", tamano: 76, peso: .ultraLight).padding(.top, 4)
                }
                Spacer(minLength: 6)
                Text(calculando ? "Buscando cachés y cosas que se pueden volver a crear."
                                : (detalle.isEmpty ? "Nada que limpiar con seguridad por ahora." : detalle))
                    .font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    BotonAura("Liberar", estilo: .lleno, grande: true, ayuda: "Abrir la limpieza de Salud del Mac: ahí eliges y confirmas") { abrirSalud(false) }
                    BotonAura("Ver qué es", grande: true, ayuda: "Abrir Salud del Mac y ver qué se puede limpiar") { abrirSalud(true) }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
    }
}
