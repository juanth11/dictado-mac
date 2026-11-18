import AppKit
import DictadoKit
import SwiftUI

// Pestaña Mac: el diagnóstico en una frase, cinco orbes (en calma van en blanco; el que pide atención toma color según
// los umbrales de Salud) y la tarjeta verde con lo que se puede recuperar sin riesgo. Liberar no borra nada desde aquí:
// abre Salud del Mac en Limpieza, donde cada cosa se confirma.

struct MacAurora: View {
    let salud: EstadoSalud
    let acciones: AccionesIsla

    var body: some View {
        HStack(spacing: AuroraNotch.separacion) {
            diagnostico
            recuperable
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

    private var diagnostico: some View {
        let d = salud.diagnostico
        let color: Color = d.gravedad == .bien ? Color(.sRGB, red: 0.60, green: 0.93, blue: 0.69) : Tono.gravedad(d.gravedad).claro
        return TarjetaOscura {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza(d.titulo, color: color)
                Text(d.frase).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(2).padding(.top, 2)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    OrbeCentrado(titulo: "Procesador", numero: String(format: "%.0f%%", salud.cpu * 100), valor: salud.cpu, tono: orbe(salud.gravedadCPU))
                        .frame(maxWidth: .infinity)
                    OrbeCentrado(titulo: "Memoria", numero: String(format: "%.0f", salud.memoriaUsada / 1e9),
                               unidad: String(format: "de %.0f GB", salud.memoriaTotal / 1.073741824e9),
                               valor: salud.memoriaUsada / max(1, salud.memoriaTotal), tono: orbe(salud.gravedadMemoria))
                        .frame(maxWidth: .infinity)
                    OrbeCentrado(titulo: "Gráficos", numero: String(format: "%.0f%%", salud.gpu * 100), valor: salud.gpu, tono: orbe(salud.gravedadGPU))
                        .frame(maxWidth: .infinity)
                    OrbeCentrado(titulo: "Libres", numero: gigas(salud.discoLibre), unidad: "GB",
                               valor: salud.discoLibre / max(1, salud.discoTotal), tono: orbe(salud.gravedadDisco))
                        .frame(maxWidth: .infinity)
                    OrbeCentrado(titulo: "Temp.", numero: termica.texto, valor: termica.valor, tono: orbe(salud.gravedadTermica), cifra: 12)
                        .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var recuperable: some View {
        let calculando = salud.analizando && salud.limpiables.isEmpty
        let seguras = salud.limpiables.filter(\.segura).sorted { $0.bytes > $1.bytes }
        let detalle = seguras.prefix(3).map { "\($0.titulo) \(Medida.bytes(Double($0.bytes)))" }.joined(separator: ", ")
        return TarjetaAura(tono: .verde, ancho: AuroraNotch.anchoReunion) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Puedes recuperar sin riesgo", color: TonoAura.verde.rotulo)
                if calculando {
                    Text("Calculando…").font(.system(size: 24, weight: .ultraLight)).padding(.top, 4)
                } else {
                    Cifra(numero: gigas(Double(salud.recuperable)), unidad: "GB", tamano: 38, peso: .ultraLight).padding(.top, 4)
                }
                Spacer(minLength: 0)
                Text(calculando ? "Buscando cachés y cosas que se pueden volver a crear."
                                : (detalle.isEmpty ? "Nada que limpiar con seguridad por ahora." : detalle))
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    BotonAura("Liberar", estilo: .lleno, ayuda: "Abrir la limpieza de Salud del Mac: ahí eliges y confirmas") { acciones.abrirSalud(true, false) }
                    BotonAura("Ver qué es", ayuda: "Abrir Salud del Mac y ver qué se puede limpiar") { acciones.abrirSalud(true, true) }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
    }
}

/// El orbe de la pestaña Mac con la cifra en el centro óptico: el número siempre va en el centro exacto del disco, el título arriba y la
/// unidad abajo a distancias fijas (antes los tres se apilaban y, con o sin unidad, la cifra quedaba más arriba o más abajo según el orbe).
/// El destello recorre la órbita fina (no el borde del aura) y el aura se centra con su propio desenfoque, sin márgenes negativos
/// que la corrían.
struct OrbeCentrado: View {
    let titulo: String
    let numero: String
    var unidad: String?
    /// 0 a 1: dónde va el destello en la órbita, empezando arriba.
    let valor: Double
    var tono = TonoOrbe.calma
    var cifra: CGFloat = 19
    var lado = AuroraNotch.orbeLado

    var body: some View {
        let escala = lado / AuroraNotch.orbeLado
        let v = max(0, min(1, valor))
        let giro = v * 360
        let rotulo = 6.5 * escala
        let sepVertical = 19 * 0.5 + rotulo * 0.5 + 4   // fija: títulos y unidades a la misma altura en todos los orbes
        let radioOrbita = lado / 2 - 4.5   // el trazo de 1 pt va a 4 pt del borde: su línea media
        ZStack {
            Circle()
                .fill(AngularGradient(gradient: gradiente, center: .center, angle: .degrees(giro)))
                .padding(-4)
                .blur(radius: AuroraNotch.orbeDesenfoque)
                .opacity(0.95)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(4)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x232327), Color(hex: 0x050506)], center: UnitPoint(x: 0.5, y: 0.2),
                                     startRadius: 0, endRadius: lado * 0.45))
                .frame(width: lado * 0.6, height: lado * 0.6)
                .overlay { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center), lineWidth: 1) }
                .shadow(color: .black.opacity(0.6), radius: 5)   // sin desplazamiento vertical: simétrica
            Text(numero).font(.system(size: cifra, weight: .ultraLight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: lado * 0.5)
            Text(titulo).font(.system(size: rotulo, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: lado * 0.5)
                .offset(y: -sepVertical)
            if let unidad {
                Text(unidad).font(.system(size: rotulo, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    .frame(width: lado * 0.5)
                    .offset(y: sepVertical)
            }
            Destello().fill(.white).frame(width: 9 * escala, height: 9 * escala)
                .shadow(color: .white, radius: 3)
                .offset(x: radioOrbita * CGFloat(cos((giro - 90) * .pi / 180)), y: radioOrbita * CGFloat(sin((giro - 90) * .pi / 180)))
        }
        .frame(width: lado, height: lado)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titulo): \(numero)" + (unidad.map { " " + $0 } ?? ""))
    }

    private var gradiente: Gradient {
        if let c = tono.colores {
            return Gradient(stops: [.init(color: c.t2, location: 0), .init(color: c.t, location: 0.30), .init(color: c.t.opacity(0), location: 0.55),
                                    .init(color: c.t2.opacity(0.6), location: 0.85), .init(color: c.t2, location: 1)])
        }
        return Gradient(stops: [.init(color: .white.opacity(0.55), location: 0), .init(color: Color(.sRGB, red: 160 / 255, green: 175 / 255, blue: 210 / 255, opacity: 0.5), location: 0.30),
                                .init(color: .white.opacity(0), location: 0.55), .init(color: .white.opacity(0.25), location: 0.85),
                                .init(color: .white.opacity(0.55), location: 1)])
    }
}
