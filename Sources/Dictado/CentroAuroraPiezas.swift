import AppKit
import DictadoKit
import SwiftUI

// Piezas compartidas de las secciones nuevas del Centro (Consumo, Herramientas, Finanzas, Noticias, Automatizaciones): el estado vacío
// honesto, el aviso de fuente vieja, las barras de 30 días, las filas con barra de reparto y el selector de pastillas. Sin tarjetas
// dentro de tarjetas: todo lo de dentro son filas con filo fino.

/// Lo que se ve cuando no hay datos: un título corto, la razón en una línea y, si ayuda, qué falta.
struct EstadoVacioAurora: View {
    let icono: String
    let titulo: String
    let detalle: String
    var falta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icono).font(.system(size: 22, weight: .light)).foregroundStyle(AuroraCentro.suave)
            Text(titulo).font(AuroraCentro.tituloTarjeta).foregroundStyle(.white.opacity(0.92))
            Text(detalle).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
            if let falta {
                Text(falta).font(AuroraCentro.denso).foregroundStyle(AuroraCentro.sutil).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// La línea de resumen con que abre una sección: las cifras dichas en una frase, con su contexto (el dato pleno, las palabras de enlace al 55 %),
/// en una tarjeta baja de vidrio; a la derecha, si hace falta, lo que no es cifra (la frescura de la fuente, un aviso).
struct ResumenAurora<Extra: View>: View {
    let segmentos: [SegmentoFrase]
    var acento = AuroraAcento.foco
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        TarjetaVidrioGrande(alto: AuroraCentro.altoResumen, relleno: EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)) {
            HStack(spacing: 24) {
                if !segmentos.isEmpty { FraseAurora(segmentos: segmentos, tam: AuroraCentro.fraseResumen, acento: acento, lineas: 2) }
                extra()
            }
            .frame(maxHeight: .infinity)
        }
    }
}

extension ResumenAurora where Extra == EmptyView {
    init(segmentos: [SegmentoFrase], acento: Color = AuroraAcento.foco) { self.init(segmentos: segmentos, acento: acento) { EmptyView() } }
}

/// Una línea que dice de dónde sale lo que se ve y qué tan fresco es. Callada si es de hoy; ámbar si es vieja; coral si es muy vieja.
struct FrescuraAurora: View {
    let texto: String
    var frescura = Frescura.vigente

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: frescura == .vigente ? "checkmark.circle" : "clock.badge.exclamationmark").font(.system(size: 12, weight: .semibold))
            Text(texto).font(AuroraCentro.minimo).lineLimit(1)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch frescura {
        case .vigente: return AuroraCentro.suave
        case .vieja: return Color(hex: 0xFFC24A)
        case .muyVieja: return Color(hex: 0xFF8F70)
        }
    }
}

/// El selector de pastillas (Costo | Tokens, Todo | Usadas | Sin uso): la elegida en blanco.
struct SelectorAurora<Opcion: Hashable>: View {
    let opciones: [Opcion]
    let titulo: (Opcion) -> String
    @Binding var elegida: Opcion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opciones, id: \.self) { o in
                Button { elegida = o } label: {
                    Text(titulo(o)).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(o == elegida ? Color.black : Color.white.opacity(0.78))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background { Capsule().fill(o == elegida ? Color.white : Color.clear) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PulsadoAurora())
                .accessibilityAddTraits(o == elegida ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background { Capsule().fill(Color.white.opacity(0.08)) }
        .fixedSize()
    }
}

/// El filo fino entre filas.
struct FiloAurora: View {
    var body: some View { Rectangle().fill(AuroraCentro.linea).frame(height: 1) }
}

/// El texto de una medida: costo ("US$ 1.257", con centavos si es chico) o tokens ("9.759 M").
enum TextoConsumo {
    static func valor(_ c: CifrasConsumo, _ m: ConsumoCentro.Medida) -> String {
        switch m {
        case .costo:
            let k = HistorialCentro.costo(c.costoUSD)
            let entero = c.costoUSD >= 100 ? k.numero.split(separator: ",").first.map(String.init) ?? k.numero : k.numero
            return "US$ " + entero + (c.costoIncompleto ? "+" : "")
        case .tokens: return tokens(c.tokens)
        }
    }

    /// "812", "340 k", "1,2 M", "9.759 M" (los miles de millones se dicen en millones con punto de miles).
    static func tokens(_ n: Int) -> String {
        if n < 1_000_000 { return TableroCentro.tokens(n) }
        let m = Double(n) / 1_000_000
        if m < 10 { return String(format: "%.1f M", m).replacingOccurrences(of: ".", with: ",") }
        var g = ""
        for (i, c) in String(Int(m.rounded())).reversed().enumerated() {
            if i > 0, i % 3 == 0 { g.append(".") }
            g.append(c)
        }
        return String(g.reversed()) + " M"
    }

    /// Una cifra de la tira: (número, unidad) del costo o de los tokens.
    static func cifra(_ c: CifrasConsumo, _ m: ConsumoCentro.Medida) -> (numero: String, unidad: String) {
        switch m {
        case .costo:
            let k = HistorialCentro.costo(c.costoUSD)
            let entero = c.costoUSD >= 1000 ? k.numero.split(separator: ",").first.map(String.init) ?? k.numero : k.numero
            return (entero, "US$" + (c.costoIncompleto ? " +" : ""))
        case .tokens:
            let t = tokens(c.tokens).split(separator: " ", maxSplits: 1).map(String.init)
            return (t[0], t.count > 1 ? t[1] + " tokens" : "tokens")
        }
    }
}

/// 30 días de barras sobrias: una por día, hoy en el azul pleno y los demás más suaves, con tres guías y la etiqueta de la escala. Un día
/// sin datos es una marca mínima (no una barra de cero que parezca un dato).
struct BarrasDiasAurora: View {
    let dias: [DiaConsumo]
    let medida: ConsumoCentro.Medida
    var color = AuroraCentro.azulBloque
    var alto: CGFloat = 170
    var etiquetaDias = true

    var body: some View {
        let fr = ConsumoCentro.fracciones(dias, por: medida)
        let mayor = dias.map { ConsumoCentro.valor($0.cifras, medida) }.max() ?? 0
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .bottomLeading) {
                    ForEach([0.0, 0.5, 1.0], id: \.self) { t in
                        Rectangle().fill(Color.white.opacity(t == 0 ? 0.16 : 0.06)).frame(height: 1).offset(y: -g.size.height * t)
                    }
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(dias.enumerated()), id: \.offset) { i, d in
                            let ultimo = i == dias.count - 1
                            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3, style: .continuous)
                                .fill(fr[i] == 0 ? Color.white.opacity(0.14) : (ultimo ? color : color.opacity(0.58)))
                                .frame(height: fr[i] == 0 ? 2 : max(3, (g.size.height - 2) * fr[i]))
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    if mayor > 0 {
                        // La escala va en la esquina de la guía de arriba, del lado de hoy: no se confunde con una cifra de la línea de al lado.
                        Text(escala(mayor)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil)
                            .frame(width: g.size.width, alignment: .trailing)
                            .offset(y: -g.size.height - 16)
                    }
                }
            }
            .frame(height: alto)
            .padding(.top, 20)
            if etiquetaDias { ejeX }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barras de los últimos \(dias.count) días")
        .accessibilityValue(ConsumoCentro.diaMasAlto(dias, por: medida).map { "El día más alto fue \(ConsumoCentro.etiqueta(dia: $0.dia))" } ?? "Sin datos")
    }

    private func escala(_ v: Double) -> String {
        switch medida {
        case .costo: return "US$ " + (v >= 10 ? HistorialCentro.costo(v).numero.split(separator: ",").first.map(String.init) ?? "" : HistorialCentro.costo(v).numero)
        case .tokens: return TextoConsumo.tokens(Int(v))
        }
    }

    /// Las etiquetas del eje: cada siete días hacia atrás desde hoy.
    private var ejeX: some View {
        GeometryReader { g in
            let n = max(1, dias.count)
            let paso = g.size.width / CGFloat(n)
            ForEach(Array(stride(from: n - 1, through: 0, by: -7)), id: \.self) { i in
                Text(etiqueta(i)).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).fixedSize()
                    .position(x: min(max(paso * (CGFloat(i) + 0.5), 22), g.size.width - 22), y: 8)
            }
        }
        .frame(height: 16)
    }

    private func etiqueta(_ i: Int) -> String {
        guard dias.indices.contains(i), let f = LecturaDia.fecha(dias[i].dia) else { return "" }
        return TextoTiempo.diaCorto(f)
    }
}

enum LecturaDia {
    static func fecha(_ dia: String) -> Date? {
        let p = dia.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// Una fila de reparto: el nombre, una barra fina con su parte y el valor. Sin caja: solo texto y barra.
struct FilaRepartoAurora: View {
    let nombre: String
    let valor: String
    var secundario: String?
    let fraccion: Double
    var color = AuroraCentro.azulBloque
    var anchoNombre: CGFloat = 150

    var body: some View {
        HStack(spacing: 12) {
            Text(nombre).font(AuroraCentro.cuerpo).lineLimit(1).truncationMode(.middle).frame(width: anchoNombre, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color).frame(width: max(fraccion > 0 ? 4 : 0, g.size.width * min(1, fraccion)))
                }
            }
            .frame(height: 6)
            Text(valor).font(AuroraCentro.cuerpo).monospacedDigit().frame(width: 96, alignment: .trailing).lineLimit(1)
            if let secundario {
                Text(secundario).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).monospacedDigit().frame(width: 52, alignment: .trailing).lineLimit(1)
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nombre): \(valor)" + (secundario.map { ", \($0)" } ?? ""))
    }
}

/// El punto de un estado con su palabra (nunca solo color).
struct EstadoPuntoAurora: View {
    let estado: EstadoAutomatizacion

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(estado.texto).font(AuroraCentro.minimo).foregroundStyle(estado == .alDia ? AuroraCentro.suave : color)
        }
        .accessibilityElement(children: .combine)
    }

    var color: Color {
        switch estado {
        case .fallo: return Color(hex: 0xFF6A4A)
        case .parado: return Color(hex: 0xFFC24A)
        case .atrasado: return Color(hex: 0xFFD88A)
        case .alDia: return AuroraCentro.verdeClaro
        case .sinDato: return Color.white.opacity(0.5)
        case .apagado: return Color.white.opacity(0.32)
        }
    }
}

/// El encabezado de una tarjeta: rótulo en versalitas, cuenta opcional y algo a la derecha.
struct CabezaTarjetaAurora<Derecha: View>: View {
    let titulo: String
    var cuenta: Int?
    var color = AuroraCentro.suave
    @ViewBuilder var derecha: () -> Derecha

    var body: some View {
        HStack(spacing: 8) {
            RotuloPieza(titulo, color: color, grande: true)
            if let cuenta, cuenta > 0 { Text("\(cuenta)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85)) }
            Spacer(minLength: 8)
            derecha()
        }
        .frame(minHeight: 28)
    }
}

extension CabezaTarjetaAurora where Derecha == EmptyView {
    init(titulo: String, cuenta: Int? = nil, color: Color = AuroraCentro.suave) {
        self.init(titulo: titulo, cuenta: cuenta, color: color) { EmptyView() }
    }
}

extension View {
    /// Difumina el borde de abajo de una lista que se desplaza dentro de una tarjeta: dice que sigue y no corta una fila a la mitad.
    func desvanecerAbajo(_ alto: CGFloat = 36) -> some View {
        mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: alto)
            }
        }
    }
}
