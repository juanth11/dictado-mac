import AppKit
import SwiftUI

// Volumen: los cinco estilos. Partido de VistaIsla.swift sin cambiar el comportamiento.

/// Volumen como un termostato: un arco de tubo con volumen que va de azul (bajo) a naranja y rojo (alto), encendido
/// hasta el nivel y tenue después, con una perilla blanca que brilla en el nivel y la cifra grande con relieve en el
/// centro. A la izquierda, un botón de vidrio con el parlante (rojo en silencio, como el de encendido); a la derecha,
/// a dónde va el sonido. En silencio el arco se apaga y la perilla queda gris en el volumen guardado.
struct VolumenIsla: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let rojo = Color(red: 1.0, green: 0.33, blue: 0.27)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 0) {
                BotonVidrioIsla(simbolo: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", valor: valor,
                            tinte: silencio ? Self.rojo : nil)
                Spacer(minLength: 8)
                ZStack(alignment: .bottom) {
                    ArcoTubo(valor: valor, apagada: silencio)
                        .frame(width: 140, height: 60)
                    Text("\(Int((valor * 100).rounded()))")
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(silencio ? Color(white: 0.6) : Color.white)
                        .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1.5)
                        .contentTransition(.numericText(value: valor))
                        .offset(y: 1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Rotulo(silencio ? "Silencio" : "Volumen", color: silencio ? Self.rojo : Halo.texto3)
                    if let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .labelStyle(EtiquetaJunta()).lineLimit(1)
                    }
                }
                .frame(width: 112, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)  // el arco y la cifra no tocan el borde; la perilla nunca queda bajo el notch
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Cómo se ve el volumen en la isla. Se elige con `defaults write app.dictado estiloVolumen niebla` (bruma, que es
/// el de siempre, termostato, niebla, calor o espectro); en los renders, con la variable DICTADO_VOLUMEN.
enum EstiloVolumen: String {
    case bruma, termostato, niebla, calor, espectro

    static var actual: EstiloVolumen {
        let valor = ProcessInfo.processInfo.environment["DICTADO_VOLUMEN"]
            ?? UserDefaults.dictado.string(forKey: "estiloVolumen")
        return valor.flatMap(EstiloVolumen.init(rawValue:)) ?? .bruma
    }
}

/// Alturas fijas de una onda de sonido (siempre las mismas: nada se anima solo), entre 0,25 y 1.
let ondaVolumen: [Double] = (0..<48).map { i in
    let x = Double(i)
    return 0.25 + 0.75 * abs(sin(x * 0.61) * 0.55 + sin(x * 1.37 + 1.1) * 0.3 + sin(x * 0.23 + 0.4) * 0.15)
}

/// Volumen "bruma" (el de siempre): el botón de vidrio del parlante a la izquierda (rojo en silencio); en el centro,
/// una línea muy fina con topes y un parlante pequeño en cada punta (bajar a la izquierda, subir a la derecha, como el
/// control de volumen de macOS), sobre la que una bruma de luz azul y violeta llega hasta el nivel; en el nivel, un
/// punto blanco con su brillo y, encima, la cifra con una línea punteada. Al subir o bajar, el parlante de esa punta se
/// enciende un instante. A la derecha, a dónde va el sonido.
struct VolumenBruma: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    /// Hacia dónde fue el último cambio (−1 bajó, 1 subió); se apaga solo. En los renders, DICTADO_DIRECCION.
    @State private var direccion = Int(ProcessInfo.processInfo.environment["DICTADO_DIRECCION"] ?? "") ?? 0
    @State private var apagar: DispatchWorkItem?

    private static let rojo = Color(red: 1.0, green: 0.33, blue: 0.27)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 16) {
                BotonVidrioIsla(simbolo: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", valor: valor,
                            tinte: silencio ? Self.rojo : nil)
                GeometryReader { g in
                    let w = g.size.width
                    let linea: CGFloat = g.size.height - 9   // la altura de la línea
                    let x0: CGFloat = 16, x1 = w - 16         // entre los dos parlantes
                    let x = x0 + (x1 - x0) * v
                    ZStack(alignment: .topLeading) {
                        if !silencio && v > 0 {  // la bruma hasta el nivel
                            Path { p in
                                let n = 12
                                p.move(to: CGPoint(x: x0, y: linea + 3))
                                for k in 0...n {
                                    let xx = x0 + (x - x0) * CGFloat(k) / CGFloat(n)
                                    let alto = 5 + 7 * CGFloat(ondaVolumen[(k * 3) % ondaVolumen.count]) * CGFloat(0.4 + 0.6 * Double(k) / Double(n))
                                    p.addLine(to: CGPoint(x: xx, y: linea - alto))
                                }
                                p.addLine(to: CGPoint(x: x, y: linea + 3))
                                p.closeSubpath()
                            }
                            .fill(LinearGradient(colors: [Tono.volumen.base.opacity(0.15), Tono.volumen.base, Tono.volumen.claro],
                                                 startPoint: .leading, endPoint: .trailing))
                            .blur(radius: 4.5)
                            .opacity(0.85)
                        }
                        Path { p in  // la línea con sus topes
                            p.move(to: CGPoint(x: x0, y: linea)); p.addLine(to: CGPoint(x: x1, y: linea))
                            p.move(to: CGPoint(x: x0, y: linea - 3)); p.addLine(to: CGPoint(x: x0, y: linea + 3))
                            p.move(to: CGPoint(x: x1, y: linea - 3)); p.addLine(to: CGPoint(x: x1, y: linea + 3))
                        }
                        .stroke(.white.opacity(0.28), lineWidth: 0.5)
                        if !silencio {
                            Capsule().fill(.white.opacity(0.85)).frame(width: max(0, x - x0), height: 4)
                                .position(x: x0 + (x - x0) / 2, y: linea)
                        }
                        Path { p in p.move(to: CGPoint(x: x, y: 15)); p.addLine(to: CGPoint(x: x, y: linea - 3)) }  // la marca punteada
                            .stroke(.white.opacity(silencio ? 0.25 : 0.5), style: StrokeStyle(lineWidth: 0.75, dash: [1.2, 2])) // grid: ok trazo punteado
                        Circle().fill(.white.opacity(silencio ? 0.45 : 1)).frame(width: 8, height: 8)  // el nivel
                            .shadow(color: .white.opacity(silencio ? 0 : 0.9), radius: 3)
                            .shadow(color: Tono.volumen.claro.opacity(silencio ? 0 : 0.8), radius: 7)
                            .position(x: x, y: linea)
                        Text(silencio ? "Mudo" : "\(Int((v * 100).rounded()))")
                            .font(.system(size: 13, weight: .light)).monospacedDigit()
                            .foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .contentTransition(.numericText(value: v))
                            .fixedSize()
                            .position(x: min(max(x, 14), w - 14), y: 7)
                        punta("speaker.fill", activa: direccion < 0).position(x: 5, y: linea)
                        punta("speaker.wave.3.fill", activa: direccion > 0).position(x: w - 4, y: linea)
                    }
                }
                .frame(height: 40)
                VStack(alignment: .trailing, spacing: 2) {
                    Rotulo(silencio ? "Silencio" : "Volumen", color: silencio ? Self.rojo : Halo.texto3)
                    if let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .labelStyle(EtiquetaJunta()).lineLimit(1)
                    }
                }
                .frame(width: 104, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
        .onChange(of: valor) { viejo, nuevo in
            guard nuevo != viejo else { return }
            withAnimation(.easeOut(duration: 0.15)) { direccion = nuevo > viejo ? 1 : -1 }
            apagar?.cancel()
            let tarea = DispatchWorkItem { withAnimation(.easeOut(duration: 0.6)) { direccion = 0 } }
            apagar = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: tarea)
        }
    }

    /// El parlante de una punta: gris; encendido (blanco con brillo) si el volumen acaba de ir hacia ese lado.
    private func punta(_ simbolo: String, activa: Bool) -> some View {
        Image(systemName: simbolo)
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundStyle(activa ? Color.white : Halo.texto3)
            .shadow(color: activa ? Tono.volumen.claro : .clear, radius: 4)
            .scaleEffect(activa ? 1.15 : 1)
    }
}

/// Volumen como niebla de luz: hasta el nivel, la onda del sonido es una masa difuminada de azul a violeta y rosa;
/// una línea punteada con un punto marca el nivel y encima va la cifra; después, rayitas finas y tenues con la misma
/// onda (lo que falta). A la izquierda, qué es y a dónde va el sonido.
struct VolumenNiebla: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let colores = [Color(red: 0.35, green: 0.62, blue: 1.0), Color(red: 0.62, green: 0.48, blue: 1.0),
                                  Color(red: 1.0, green: 0.45, blue: 0.62)]
    private static let marca = Color(red: 1.0, green: 0.62, blue: 0.45)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo(silencio ? "Silencio" : "Volumen", color: silencio ? Color(red: 1, green: 0.46, blue: 0.44) : Halo.texto3)
                    if let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .labelStyle(EtiquetaJunta()).lineLimit(1)
                    }
                }
                .frame(width: 104, alignment: .leading)
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    let base = h - 2, techo: CGFloat = 20  // arriba queda la cifra
                    let n = ondaVolumen.count
                    let paso = w / CGFloat(n - 1)
                    let x = w * v
                    ZStack(alignment: .topLeading) {
                        if !silencio && v > 0 {
                            Path { p in  // la masa de la onda hasta el nivel: colinas suaves (una cada 4 muestras)
                                let puntos = stride(from: 0, to: n, by: 4).map { i in
                                    CGPoint(x: CGFloat(i) * paso, y: base - (base - techo) * CGFloat(0.3 + 0.7 * ondaVolumen[i]))
                                } + [CGPoint(x: w, y: base - (base - techo) * 0.5)]
                                p.move(to: CGPoint(x: 0, y: base))
                                p.addLine(to: puntos[0])
                                for k in 1..<puntos.count {
                                    let a = puntos[k - 1], b = puntos[k]
                                    let medio = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                    p.addQuadCurve(to: medio, control: a)
                                    if k == puntos.count - 1 { p.addQuadCurve(to: b, control: medio) }
                                }
                                p.addLine(to: CGPoint(x: w, y: base))
                                p.closeSubpath()
                            }
                            .fill(LinearGradient(colors: Self.colores, startPoint: .leading, endPoint: .trailing))
                            .mask(alignment: .leading) { Rectangle().frame(width: x) }
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                         .init(color: .black.opacity(0.25), location: 1)], startPoint: .top, endPoint: .bottom))
                            .blur(radius: 5)
                        }
                        ForEach(0..<n, id: \.self) { i in  // lo que falta: rayitas finas
                            let xi = CGFloat(i) * paso
                            if xi > x + 3 || silencio {
                                let alto = (base - techo) * CGFloat(ondaVolumen[i])
                                Rectangle().fill((silencio ? Color.white : Self.colores[2]).opacity(silencio ? 0.18 : 0.45))
                                    .frame(width: 4, height: alto)
                                    .position(x: xi, y: base - alto / 2)
                            }
                        }
                        Path { p in p.move(to: CGPoint(x: x, y: techo - 4)); p.addLine(to: CGPoint(x: x, y: base)) }
                            .stroke(silencio ? Color.white.opacity(0.35) : Self.marca, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                        Circle().fill(silencio ? Color.white.opacity(0.4) : Self.marca).frame(width: 4, height: 4)
                            .shadow(color: silencio ? .clear : Self.marca, radius: 3)
                            .position(x: x, y: techo - 4)
                        Text(silencio ? "Mudo" : "\(Int((v * 100).rounded()))%")
                            .font(.system(size: 14, weight: .light)).monospacedDigit()
                            .foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .contentTransition(.numericText(value: v))
                            .fixedSize()
                            .position(x: min(max(x, 18), w - 18), y: 6)
                    }
                }
                .frame(height: 52)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Volumen como calor y frío: una línea fina con topes en los extremos; desde la izquierda hasta el nivel, un brillo
/// cálido (naranja a amarillo, con el centro blanco en el nivel) y después un brillo frío azul que se apaga. Arriba,
/// "VOLUMEN 62" con la cifra en amarillo y el parlante; abajo, los extremos de la escala.
struct VolumenCalor: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let amarillo = Color(red: 1.0, green: 0.82, blue: 0.25)
    private static let naranja = Color(red: 1.0, green: 0.45, blue: 0.12)
    private static let azul = Color(red: 0.35, green: 0.72, blue: 1.0)
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(silencio ? "SILENCIO" : "VOLUMEN").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(silencio ? Self.rojoMudo : .white)
                        if !silencio {
                            Text("\(Int((v * 100).rounded()))").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(Self.amarillo)
                                .contentTransition(.numericText(value: v))
                        }
                    }
                    Spacer()
                    if let salida {
                        Text(salida.nombre).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Halo.texto3).lineLimit(1)
                    }
                    Image(systemName: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: max(v, 0.01))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(silencio ? Self.rojoMudo : Self.amarillo)
                }
                GeometryReader { g in
                    let w = g.size.width, medio = g.size.height / 2
                    let x = w * v
                    ZStack(alignment: .topLeading) {
                        if !silencio {
                            Ellipse()  // frío: lo que falta
                                .fill(LinearGradient(colors: [Self.azul, Self.azul.opacity(0.0)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(30, (w - x) * 1.1), height: 18) // grid: ok proporcional
                                .position(x: x + (w - x) / 2, y: medio)
                                .blur(radius: 7).opacity(0.85)
                            Ellipse()  // calor: hasta el nivel
                                .fill(LinearGradient(colors: [Self.naranja.opacity(0.0), Self.naranja, Self.amarillo],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(30, x * 1.1), height: 20)
                                .position(x: x / 2, y: medio)
                                .blur(radius: 6)
                            Ellipse().fill(.white)  // el centro blanco en el nivel
                                .frame(width: 24, height: 12)
                                .position(x: x, y: medio)
                                .blur(radius: 4.5)
                        }
                        Path { p in  // la línea con sus topes
                            p.move(to: CGPoint(x: 0, y: medio)); p.addLine(to: CGPoint(x: w, y: medio))
                            p.move(to: CGPoint(x: 0, y: medio - 4)); p.addLine(to: CGPoint(x: 0, y: medio + 4))
                            p.move(to: CGPoint(x: w, y: medio - 4)); p.addLine(to: CGPoint(x: w, y: medio + 4))
                        }
                        .stroke(.white.opacity(silencio ? 0.25 : 0.55), lineWidth: 0.5)
                        if silencio {
                            Capsule().fill(.white.opacity(0.35)).frame(width: 4, height: 8).position(x: x, y: medio)
                        }
                    }
                }
                .frame(height: 20)
                HStack {
                    Text("0"); Spacer(); Text("100")
                }
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Halo.texto3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Volumen como espectro (como un reproductor con barras): arriba "Volumen" y a dónde va el sonido, la cifra y el
/// parlante en un círculo; una línea fina con su perilla marca el nivel; abajo, rayitas blancas a todo lo ancho,
/// sumergidas en una luz azul y violeta que sube desde el borde, encendidas hasta el nivel y tenues después.
struct VolumenEspectro: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let azul = Color(red: 0.25, green: 0.4, blue: 1.0)
    private static let violeta = Color(red: 0.55, green: 0.45, blue: 1.0)
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            VStack(spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(silencio ? "Silencio" : "Volumen").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(silencio ? Self.rojoMudo : Halo.texto)
                        if let salida { Text(salida.nombre).font(.system(size: 10.5)).foregroundStyle(Halo.texto3).lineLimit(1) }
                    }
                    Spacer()
                    Text(silencio ? "—" : "\(Int((v * 100).rounded()))")
                        .font(.system(size: 20, weight: .light)).monospacedDigit().foregroundStyle(Halo.texto)
                        .contentTransition(.numericText(value: v))
                    Image(systemName: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: max(v, 0.01))
                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(silencio ? Self.rojoMudo : .white.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .padding(.horizontal, 24)
                GeometryReader { g in  // la línea del nivel con su perilla
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                        Capsule().fill(.white.opacity(silencio ? 0.3 : 0.9)).frame(width: w * v, height: 1.2) // grid: ok hilo proporcional
                        Circle().fill(.white.opacity(silencio ? 0.4 : 1)).frame(width: 8, height: 8)
                            .shadow(color: .white.opacity(silencio ? 0 : 0.8), radius: 3)
                            .offset(x: w * v - 3)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 8)
                .padding(.horizontal, 24)
                GeometryReader { g in  // el espectro a todo lo ancho, con la luz desde abajo
                    let w = g.size.width, h = g.size.height
                    let n = 72
                    let paso = w / CGFloat(n)
                    let x = w * v
                    ZStack(alignment: .bottomLeading) {
                        if !silencio && v > 0 {
                            Ellipse().fill(Self.azul)  // la luz que se derrama más allá de las barras
                                .frame(width: x * 1.1, height: h * 2.2)
                                .offset(x: -x * 0.03, y: h * 0.45)
                                .blur(radius: 12)
                            Rectangle()  // la luz que sube desde el borde e inunda la base de las barras
                                .fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Self.azul.opacity(0.9), location: 0.3),
                                                             .init(color: Self.violeta, location: 0.65), .init(color: .white, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: x, height: h + 20)
                                .blur(radius: 5)
                        }
                        ForEach(0..<n, id: \.self) { i in
                            let xi = paso * (CGFloat(i) + 0.5)
                            let alto = h * CGFloat(0.35 + 0.65 * ondaVolumen[i % ondaVolumen.count])
                            let prendida = !silencio && xi <= x
                            Rectangle()
                                .fill(LinearGradient(colors: prendida ? [.white.opacity(0.95), .white.opacity(0.35)] : [.white.opacity(0.14), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 4, height: alto)
                                .position(x: xi, y: h - alto / 2)
                        }
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, FormaIsla.hombro + 6)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}
