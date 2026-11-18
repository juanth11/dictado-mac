import AppKit
import SwiftUI

// Piezas sueltas de la isla. Partido de VistaIsla.swift sin cambiar el comportamiento.

/// Botón redondo de vidrio oscuro con relieve (como los de un termostato); con tinte, el vidrio brilla de ese color.
struct BotonVidrioIsla: View {
    let simbolo: String
    var valor: Double = 1
    var tinte: Color?

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [(tinte ?? Color(white: 0.32)).opacity(tinte == nil ? 0.9 : 0.75),
                                                  (tinte ?? Color(white: 0.12)).opacity(tinte == nil ? 1 : 0.35)],
                                         center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 22))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.5)
            Image(systemName: simbolo, variableValue: max(valor, 0.01))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        .shadow(color: (tinte ?? .clear).opacity(0.55), radius: 8)
    }
}

/// El arco del termostato: medio círculo por arriba, con un tubo de volumen (sombra debajo, brillo arriba) que se
/// enciende hasta el nivel con el degradado azul → violeta → naranja → rojo; después del nivel queda tenue; los
/// extremos se desvanecen; la perilla es una esfera blanca que brilla.
struct ArcoTubo: View {
    let valor: Double
    var apagada = false

    private static let colores = [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.55, green: 0.78, blue: 1.0),
                                  Color(red: 0.7, green: 0.55, blue: 1.0), Color(red: 1.0, green: 0.6, blue: 0.3),
                                  Color(red: 1.0, green: 0.3, blue: 0.25)]

    var body: some View {
        let v = max(0, min(1, valor))
        GeometryReader { g in
            let grosor: CGFloat = 8.5
            let radio: CGFloat = 40  // el resto del cuadro es aire para que el brillo se desvanezca sin bordes
            let centro = CGPoint(x: g.size.width / 2, y: g.size.height - 1)
            let arco = { (hasta: Double) -> Path in
                Path { p in
                    p.addArc(center: centro, radius: radio, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * hasta),
                             clockwise: false)
                }
            }
            let degradado = LinearGradient(colors: apagada ? [Color(white: 0.4), Color(white: 0.3)] : Self.colores,
                                           startPoint: .leading, endPoint: .trailing)
            let angulo = (180 + 180 * v) * .pi / 180
            let perilla = CGPoint(x: centro.x + radio * cos(angulo), y: centro.y + radio * sin(angulo))
            ZStack {
                // hendidura: el tubo va encajado (sombra arriba, filo de luz abajo)
                arco(1).stroke(Color.black.opacity(0.8), style: StrokeStyle(lineWidth: grosor + 3, lineCap: .round))
                    .blur(radius: 1.5).offset(y: -0.5)
                arco(1).stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: grosor + 2, lineCap: .round)).offset(y: 0.8)
                // el tubo completo, tenue
                arco(1).stroke(degradado, style: StrokeStyle(lineWidth: grosor, lineCap: .round)).opacity(apagada ? 0.25 : 0.22)
                if !apagada && v > 0.001 {
                    // resplandor del tramo encendido
                    arco(v).stroke(degradado, style: StrokeStyle(lineWidth: grosor + 6, lineCap: .round)).blur(radius: 7).opacity(0.75)
                    // el tubo encendido
                    arco(v).stroke(degradado, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                    // sombra interior abajo y brillo arriba: volumen de tubo
                    arco(v).stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: grosor * 0.4, lineCap: .round))
                        .blur(radius: 1.2).offset(y: grosor * 0.22)
                    arco(v).stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: grosor * 0.28, lineCap: .round))
                        .blur(radius: 0.8).offset(y: -grosor * 0.2)
                }
                // la perilla: esfera blanca que brilla
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: apagada ? 0.55 : 0.88)], center: UnitPoint(x: 0.4, y: 0.35),
                                         startRadius: 0, endRadius: 7))
                    .frame(width: 12, height: 12)
                    .shadow(color: apagada ? .clear : .white.opacity(0.95), radius: 4)
                    .shadow(color: apagada ? .black.opacity(0.5) : Color(red: 1, green: 0.9, blue: 0.75).opacity(0.7), radius: 9)
                    .position(perilla)
            }
            // los extremos se desvanecen hacia la base, como en el termostato
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                         .init(color: .black.opacity(0.12), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Ícono y texto juntos, con el ícono pequeño (para "AirPods Pro", "Pantalla").
struct EtiquetaJunta: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10.5, weight: .medium)).opacity(0.8)
            configuration.title
        }
    }
}

/// Cuatro barras que bailan con la música (solo mientras el aviso está a la vista).
struct Ecualizador: View {
    let color: Color
    let activo: Bool

    private func alto(_ i: Int, _ t: Double) -> CGFloat {
        guard activo else { return 4 }
        let n = Double(i)
        let onda: Double = abs(sin(t * (2.6 + n * 0.7) + n * 1.9))
        return CGFloat(5 + 13 * onda)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !activo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color).frame(width: 4, height: alto(i, t)).shadow(color: color.opacity(0.8), radius: 2.5)
                }
            }
            .frame(width: 24, height: 20)
        }
    }
}
