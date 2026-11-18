import AppKit
import DictadoKit
import SwiftUI

// Aurora: el sistema de diseño del lanzador (y, más adelante, del Dock, los widgets y el Centro). Espejo de
// `tokens/aurora.json` del sistema de diseño Halo; la muestra visual es `galeria/aurora.plantilla.html`.
// La idea: el fondo es el protagonista y todo lo demás es vidrio encima, con dos tonos de texto, un acento por pieza y
// nada que se mueva en reposo. La isla del notch sigue en Halo (negro); Aurora solo rige lo que vive en este archivo.
// Ninguna cifra de diseño va fuera de aquí.

// MARK: - Color

extension Color {
    /// Un color desde un entero 0xRRGGBB.
    init(hex: UInt32, opacidad: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacidad)
    }
}

/// Mezcla de dos colores 0xRRGGBB: `parte` de `a` y el resto de `b` (como `color-mix(in srgb)` del CSS).
private func mezclar(_ a: UInt32, _ parte: Double, con b: UInt32 = 0xFFFFFF, opacidad: Double = 1) -> Color {
    func canal(_ v: UInt32, _ desplazo: UInt32) -> Double { Double((v >> desplazo) & 0xFF) / 255 }
    func m(_ desplazo: UInt32) -> Double { canal(a, desplazo) * parte + canal(b, desplazo) * (1 - parte) }
    return Color(.sRGB, red: m(16), green: m(8), blue: m(0), opacity: opacidad)
}

// MARK: - Temas (texto y superficies)

enum AuroraTema: String, CaseIterable {
    case oscuro, claro

    var esOscuro: Bool { self == .oscuro }
    var esquema: ColorScheme { esOscuro ? .dark : .light }
    var otro: AuroraTema { esOscuro ? .claro : .oscuro }

    var textoPleno: Color { esOscuro ? Color(white: 1) : Color(white: 0, opacity: 0.92) }
    /// Texto secundario: 0,62 sobre oscuro y 0,60 sobre claro dan 4,5:1 o más incluso sobre el amarillo claro de macOS (medido).
    var textoSuave: Color { esOscuro ? Color(white: 1, opacity: 0.62) : Color(white: 0, opacity: 0.60) }
    var textoTenue: Color { esOscuro ? Color(white: 1, opacity: 0.32) : Color(white: 0, opacity: 0.30) }
    var vidrio: Color { esOscuro ? Color(white: 0, opacity: 0.38) : Color(white: 1, opacity: 0.55) }
    var vidrioFuerte: Color { esOscuro ? Color(white: 0, opacity: 0.62) : Color(white: 1, opacity: 0.82) }
    /// El texto sobre un relleno de `textoPleno` (el chip del espacio activo).
    /// El texto de un chip que no está activo: más firme que `textoSuave` para pasar AA sobre el vidrio.
    var textoChip: Color { esOscuro ? Color(white: 1, opacity: 0.74) : Color(white: 0, opacity: 0.66) }
    var fondoChipActivo: Color { esOscuro ? .black : .white }
    var mosaico: Color { esOscuro ? Color(hex: 0x0B0B0D) : Color(hex: 0xFFFFFF) }
    var bordeArriba: Color { esOscuro ? Color(white: 1, opacity: 0.14) : Color(white: 1, opacity: 0.80) }
    var bordeAbajo: Color { esOscuro ? Color(white: 1, opacity: 0.04) : Color(white: 0, opacity: 0.06) }
    var fila: Color { esOscuro ? Color(white: 1, opacity: 0.07) : Color(white: 0, opacity: 0.05) }
    var filaActiva: Color { esOscuro ? Color(white: 1, opacity: 0.14) : Color(white: 1) }
    var filaActivaBorde: Color { esOscuro ? Color(white: 1, opacity: 0.30) : Color(white: 0, opacity: 0.20) }
}

enum AuroraAcento {
    static let hoy = Color(hex: 0xFF3B30)
    static let foco = Color(hex: 0xFF9F0A)
    static let bien = Color(hex: 0x30D158)
    static let seleccion = Color(hex: 0x4A8DFF)
    static let agentes = Color(hex: 0xF2784A)
}

// MARK: - Paletas de espacio

/// Dos tonos por espacio. Tiñen el brillo del fondo y lo activo; nada más.
enum AuroraPaleta: String, CaseIterable {
    case lagunaDurazno, medianocheOro, ciruelaCoral, bosqueLima, tintaLavanda, terracota

    var a: UInt32 {
        switch self {
        case .lagunaDurazno: return 0x0E6E8C
        case .medianocheOro: return 0x101A3A
        case .ciruelaCoral: return 0x5B1E8C
        case .bosqueLima: return 0x0F3D2E
        case .tintaLavanda: return 0x16163A
        case .terracota: return 0xA9441F
        }
    }
    var b: UInt32 {
        switch self {
        case .lagunaDurazno: return 0xF58A4B
        case .medianocheOro: return 0xE0B04A
        case .ciruelaCoral: return 0xFF5E7A
        case .bosqueLima: return 0xB6E04A
        case .tintaLavanda: return 0xA79BFF
        case .terracota: return 0xF2A65A
        }
    }
    var tonoA: Color { Color(hex: a) }
    var tonoB: Color { Color(hex: b) }

    var nombre: String {
        switch self {
        case .lagunaDurazno: return "Laguna y durazno"
        case .medianocheOro: return "Medianoche y oro"
        case .ciruelaCoral: return "Ciruela y coral"
        case .bosqueLima: return "Bosque y lima"
        case .tintaLavanda: return "Tinta y lavanda"
        case .terracota: return "Terracota"
        }
    }

    var siguiente: AuroraPaleta {
        let todas = Self.allCases
        return todas[((todas.firstIndex(of: self) ?? 0) + 1) % todas.count]
    }
}

// MARK: - Tipografía

enum AuroraTipo {
    /// El día del mes (96-140, heavy, −3 %). El widget Fecha de la maqueta usa 128 en negrita con −4,5 %.
    static func cifraGigante(_ tam: CGFloat = AuroraMedida.fechaCifra) -> Font { .system(size: tam, weight: .bold) }
    static let cifraGiganteInterletra: CGFloat = -0.045
    static let cifraGiganteInterlinea: CGFloat = 0.95

    /// Frase de widget (28-34, semibold, interlínea 1,12; en la maqueta, 31 y −1,8 %).
    static func frase(_ tam: CGFloat = 31) -> Font { .system(size: tam, weight: .semibold) }
    static let fraseInterletra: CGFloat = -0.018
    static let fraseInterlinea: CGFloat = 1.13

    static let cifraDock = Font.system(size: 30, weight: .heavy, design: .rounded)
    static let titulo = Font.system(size: 17, weight: .semibold)
    static let tituloInterletra: CGFloat = -0.01
    static let cuerpo = Font.system(size: 13, weight: .medium)
    static let busqueda = Font.system(size: 14, weight: .regular)
    static let etiquetaApp = Font.system(size: 11.5, weight: .medium)
    static let fila = Font.system(size: 12, weight: .medium)
    static let filaDato = Font.system(size: 12, weight: .semibold)
    static let fechaSemana = Font.system(size: 26, weight: .bold)
    static let artista = Font.system(size: 11, weight: .regular)
    static let rotulo = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let rotuloInterletra: CGFloat = 0.04
    static let tiempos = Font.system(size: 9, weight: .medium, design: .monospaced)
}

// MARK: - Medidas

enum AuroraMedida {
    static let base: CGFloat = 4
    // Lienzo del lanzador: 10 columnas de 96 × 4 filas de 110.
    static let celda: CGFloat = 96
    static let filaAlto: CGFloat = 110
    static let separacionColumnas: CGFloat = 30
    static let separacionFilas: CGFloat = 26
    static let lienzoTop: CGFloat = 122
    /// En pantallas más altas que la maqueta (900), el lienzo baja una parte de lo que sobra.
    static let alturaMaqueta: CGFloat = 900
    static let anchoMaqueta: CGFloat = 1440
    static let lienzoBajaPorExceso: CGFloat = 0.3
    // Iconos
    static let icono: CGFloat = 70
    static let iconoMin: CGFloat = 48
    static let iconoMax: CGFloat = 96
    static let iconoRadioProporcion: CGFloat = 0.225
    static let iconoEspacioEtiqueta: CGFloat = 9
    /// El aire sobre el ícono dentro de su celda: así los íconos de una fila quedan alineados aunque un nombre ocupe dos líneas.
    static let celdaArriba: CGFloat = 4
    static let indicadorAbierta = CGSize(width: 10, height: 3)   // grid: ok píldora de la maqueta (10 × 3), deliberada
    // Widgets
    static let widgetRadio: CGFloat = 30
    static let widgetRelleno: CGFloat = 20
    static let widgetSombra = (radio: CGFloat(20), y: CGFloat(18), opacidad: 0.22)
    static let filaListaAlto: CGFloat = 32
    static let filaListaRadio: CGFloat = 11
    static let filaListaRelleno: CGFloat = 11
    static let filaListaSeparacion: CGFloat = 6
    // Barra superior
    static let botonCircular: CGFloat = 44
    static let botonIcono: CGFloat = 17
    static let botonesSeparacion: CGFloat = 10
    static let botonesTop: CGFloat = 31
    static let botonesDerecha: CGFloat = 34
    static let busquedaAncho: CGFloat = 340
    static let busquedaAlto: CGFloat = 38
    static let busquedaTop: CGFloat = 34
    static let busquedaRelleno: CGFloat = 15
    static let busquedaSeparacion: CGFloat = 9
    static let busquedaLupa: CGFloat = 14
    // Fecha
    static let fechaCifra: CGFloat = 128
    // Música
    static let discoDiametro: CGFloat = 212
    static let discoTop: CGFloat = -86
    static let discoEtiquetaProporcion: CGFloat = 0.26
    static let discoSurco: CGFloat = 2.6
    static let barraProgreso: CGFloat = 3
    static let transporteSeparacion: CGFloat = 20
    // Paginación
    static let puntoPagina: CGFloat = 7
    static let paginasSeparacion: CGFloat = 10
    static let paginasAlto: CGFloat = 40

    static func ancho(columnas n: Int) -> CGFloat { CGFloat(n) * celda + CGFloat(max(n - 1, 0)) * separacionColumnas }
    static func alto(filas n: Int) -> CGFloat { CGFloat(n) * filaAlto + CGFloat(max(n - 1, 0)) * separacionFilas }
    static var lienzoAncho: CGFloat { ancho(columnas: RejillaLanzador.columnas) }
    static var lienzoAlto: CGFloat { alto(filas: RejillaLanzador.filas) }
}

enum AuroraEfecto {
    static let desenfoque: CGFloat = 40
    static let sombra = (y: CGFloat(12), radio: CGFloat(20), opacidad: 0.25)
    static let grano = 0.09
    static let bordeGrosor: CGFloat = 1
    static let sombraIcono = (radio: CGFloat(5), y: CGFloat(6), opacidad: 0.28)
    static let sombraTextoOscuro = (radio: CGFloat(3), y: CGFloat(1), opacidad: 0.35)
}

enum AuroraMovimiento {
    static let escalaInicial: CGFloat = 1.06
    static let punteroEscala: CGFloat = 1.06
    static let punteroDuracion = 0.12
    static let datoDuracion = 0.2
    static let espacioDuracion = 0.3
    static let fundidoCierre = 0.14
    static let fundidoSinMovimiento = 0.2

    /// Abrir el lanzador: resorte de respuesta 0,42 y amortiguación 0,82; sin movimiento, solo un fundido.
    static func abrir(sinMovimiento: Bool) -> Animation {
        sinMovimiento ? .easeOut(duration: fundidoSinMovimiento) : .spring(response: 0.42, dampingFraction: 0.82)
    }
    static let pulsadoEscala: CGFloat = 0.97
    static let pulsadoOpacidad = 0.78
    static let pulsado = Animation.easeOut(duration: 0.15)
    static let puntero = Animation.easeOut(duration: punteroDuracion)
    static let dato = Animation.easeInOut(duration: datoDuracion)
    static let espacio = Animation.easeInOut(duration: espacioDuracion)
}

// MARK: - Entorno

private struct ClaveAuroraTema: EnvironmentKey { static let defaultValue = AuroraTema.oscuro }
private struct ClaveAuroraPaleta: EnvironmentKey { static let defaultValue = AuroraPaleta.lagunaDurazno }
/// El alto de las tarjetas de aura y oscuras: 178 en la isla; nil = flexible (el lanzador a pantalla completa las estira al bloque).
private struct ClaveAltoTarjeta: EnvironmentKey { static let defaultValue: CGFloat? = AuroraNotch.altoTarjeta }

extension EnvironmentValues {
    var altoTarjetaAura: CGFloat? {
        get { self[ClaveAltoTarjeta.self] }
        set { self[ClaveAltoTarjeta.self] = newValue }
    }
    var auroraTema: AuroraTema {
        get { self[ClaveAuroraTema.self] }
        set { self[ClaveAuroraTema.self] = newValue }
    }
    var auroraPaleta: AuroraPaleta {
        get { self[ClaveAuroraPaleta.self] }
        set { self[ClaveAuroraPaleta.self] = newValue }
    }
}

// MARK: - Vidrio

/// Un contenedor de vidrio por grupo: los elementos de adentro comparten la composición del sistema y no llevan
/// vidrio propio sobre vidrio. En los renders (sin vidrio real) no hace nada.
struct ContenedorVidrio<Contenido: View>: View {
    var separacion: CGFloat = 0
    @ViewBuilder var contenido: () -> Contenido
    @Environment(\.vidrioSimulado) private var simulado

    var body: some View {
        if simulado {
            contenido()
        } else {
            GlassEffectContainer(spacing: separacion) { contenido() }
        }
    }
}

/// Vidrio de Aurora: el nativo (`glassEffect`) teñido con el vidrio del tema; con "Reducir transparencia", un material
/// opaco; en los renders, un relleno plano (el sistema no compone vidrio fuera de la pantalla).
struct VidrioAurora<Forma: InsettableShape>: ViewModifier {
    let forma: Forma
    var fuerte = false
    var sombra = false
    @Environment(\.auroraTema) private var tema
    @Environment(\.vidrioSimulado) private var simulado
    @Environment(\.accessibilityReduceTransparency) private var sinTransparencia

    func body(content: Content) -> some View {
        let tinte = fuerte ? tema.vidrioFuerte : tema.vidrio
        Group {
            if sinTransparencia {
                content.background(forma.fill(.regularMaterial)).background(forma.fill(tema.mosaico.opacity(0.6)))
            } else if simulado {
                content.background(forma.fill(tinte))
            } else {
                content.glassEffect(.regular.tint(tinte), in: forma)
            }
        }
        .overlay(forma.strokeBorder(LinearGradient(colors: [tema.bordeArriba, tema.bordeAbajo], startPoint: .top, endPoint: .bottom),
                                    lineWidth: AuroraEfecto.bordeGrosor))
        .shadow(color: .black.opacity(sombra ? AuroraEfecto.sombra.opacidad : 0), radius: sombra ? AuroraEfecto.sombra.radio : 0,
                y: sombra ? AuroraEfecto.sombra.y : 0)
    }
}

/// La superficie de un widget: vidrio fuerte con borde de luz y una sombra suave.
struct SuperficieWidget<Forma: InsettableShape>: ViewModifier {
    let forma: Forma
    var solido = false
    @Environment(\.auroraTema) private var tema
    @Environment(\.vidrioSimulado) private var simulado

    func body(content: Content) -> some View {
        Group {
            if solido {   // Fecha: mosaico sólido
                content.background(forma.fill(tema.mosaico))
                    .overlay(forma.strokeBorder(LinearGradient(colors: [tema.bordeArriba, tema.bordeAbajo], startPoint: .top, endPoint: .bottom),
                                                lineWidth: AuroraEfecto.bordeGrosor))
            } else {
                content.modifier(VidrioAurora(forma: forma, fuerte: true))
            }
        }
        .shadow(color: .black.opacity(AuroraMedida.widgetSombra.opacidad), radius: AuroraMedida.widgetSombra.radio,
                y: AuroraMedida.widgetSombra.y)
    }
}

extension View {
    func vidrioAurora(radio: CGFloat, fuerte: Bool = false, sombra: Bool = false) -> some View {
        modifier(VidrioAurora(forma: RoundedRectangle(cornerRadius: radio, style: .continuous), fuerte: fuerte, sombra: sombra))
    }
    func vidrioAuroraCapsula(sombra: Bool = true) -> some View {
        modifier(VidrioAurora(forma: Capsule(), sombra: sombra))
    }
    func vidrioAuroraCirculo(sombra: Bool = true) -> some View {
        modifier(VidrioAurora(forma: Circle(), sombra: sombra))
    }
    func superficieWidget(solido: Bool = false) -> some View {
        modifier(SuperficieWidget(forma: RoundedRectangle(cornerRadius: AuroraMedida.widgetRadio, style: .continuous), solido: solido))
    }
}

// MARK: - Frase de dos tonos

/// Una frase en un solo `Text`: el dato pleno y las palabras de enlace al 55 %; el acento toma el color de la pieza.
struct FraseAurora: View {
    let segmentos: [SegmentoFrase]
    var tam: CGFloat = 31
    var acento: Color = AuroraAcento.agentes
    var lineas = 4
    @Environment(\.auroraTema) private var tema

    private var texto: AttributedString {
        var salida = AttributedString()
        for s in segmentos {
            var parte = AttributedString(s.texto)
            switch s.tono {
            case .dato: parte.foregroundColor = tema.textoPleno
            case .enlace: parte.foregroundColor = tema.textoSuave
            case .acento: parte.foregroundColor = acento
            }
            salida.append(parte)
        }
        return salida
    }

    var body: some View {
        Text(texto)
            .font(AuroraTipo.frase(tam))
            .tracking(tam * AuroraTipo.fraseInterletra)
            .lineSpacing(tam * (AuroraTipo.fraseInterlinea - 1.19))
            .lineLimit(lineas)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(AuroraMovimiento.dato, value: segmentos)
            .accessibilityElement()
            .accessibilityLabel(Frase.texto(segmentos).replacingOccurrences(of: "\n", with: ", "))
    }
}

/// Rótulo pequeño en mono, en mayúsculas.
struct RotuloAurora: View {
    let texto: String
    @Environment(\.auroraTema) private var tema

    var body: some View {
        Text(texto.uppercased())
            .font(AuroraTipo.rotulo)
            .tracking(10 * AuroraTipo.rotuloInterletra)
            .foregroundStyle(tema.textoSuave)
            .lineLimit(1)
    }
}

// MARK: - Fondo

/// El fondo del lanzador: casi negro (o casi blanco) con tres esferas grandes de luz suave, el brillo de las dos tonalidades
/// de la paleta en las esquinas de abajo y grano encima. Estático: se dibuja una vez y no se anima.
struct FondoAurora: View {
    let paleta: AuroraPaleta
    let tema: AuroraTema

    private struct Esfera {
        let x: CGFloat, y: CGFloat, d: CGFloat
        let centro: CGPoint           // fracción del cuadrado de la esfera
        let paradas: [Gradient.Stop]
        let sombra: (x: CGFloat, y: CGFloat, radio: CGFloat, color: Color)?
    }

    private var esferas: [Esfera] {
        if tema.esOscuro {
            return [
                Esfera(x: 120, y: 130, d: 1100, centro: CGPoint(x: 0.32, y: 0.16),
                       paradas: [.init(color: .white.opacity(0.20), location: 0), .init(color: .white.opacity(0.05), location: 0.34),
                                 .init(color: Color(hex: 0x0A0A0D), location: 0.62)],
                       sombra: (-40, -30, 60, .black.opacity(0.55))),
                Esfera(x: 620, y: 300, d: 900, centro: CGPoint(x: 0.30, y: 0.14),
                       paradas: [.init(color: .white.opacity(0.17), location: 0), .init(color: .white.opacity(0.04), location: 0.36),
                                 .init(color: Color(hex: 0x08080B), location: 0.64)],
                       sombra: (-50, -30, 60, .black.opacity(0.6))),
                Esfera(x: -330, y: 420, d: 760, centro: CGPoint(x: 0.60, y: 0.12),
                       paradas: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0.03), location: 0.36),
                                 .init(color: Color(hex: 0x070709), location: 0.62)], sombra: nil),
            ]
        }
        let niebla = Color(.sRGB, red: 120 / 255, green: 130 / 255, blue: 160 / 255)
        return [
            Esfera(x: 120, y: 130, d: 1100, centro: CGPoint(x: 0.34, y: 0.18),
                   paradas: [.init(color: .white, location: 0), .init(color: .white.opacity(0.55), location: 0.40),
                             .init(color: Color(.sRGB, red: 214 / 255, green: 220 / 255, blue: 232 / 255, opacity: 0.75), location: 0.70)],
                   sombra: (-30, -20, 45, niebla.opacity(0.22))),
            Esfera(x: 620, y: 300, d: 900, centro: CGPoint(x: 0.30, y: 0.16),
                   paradas: [.init(color: .white, location: 0), .init(color: .white.opacity(0.5), location: 0.42),
                             .init(color: Color(.sRGB, red: 206 / 255, green: 213 / 255, blue: 228 / 255, opacity: 0.8), location: 0.70)],
                   sombra: (-30, -20, 45, niebla.opacity(0.25))),
            Esfera(x: -330, y: 420, d: 760, centro: CGPoint(x: 0.62, y: 0.14),
                   paradas: [.init(color: .white, location: 0), .init(color: .white.opacity(0.5), location: 0.40),
                             .init(color: Color(.sRGB, red: 212 / 255, green: 218 / 255, blue: 230 / 255, opacity: 0.7), location: 0.70)],
                   sombra: nil),
        ]
    }

    var body: some View {
        Canvas { ctx, size in
            let s = max(size.width / AuroraMedida.anchoMaqueta, size.height / AuroraMedida.alturaMaqueta)
            let ancho = AuroraMedida.anchoMaqueta * s, alto = AuroraMedida.alturaMaqueta * s
            let origen = CGPoint(x: (size.width - ancho) / 2, y: (size.height - alto) / 2)
            // Base
            if tema.esOscuro {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x050507)))
            } else {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xF6F7FA), Color(hex: 0xE7EAF1)]), startPoint: .zero,
                    endPoint: CGPoint(x: size.width * 0.35, y: size.height)))
            }
            var d = ctx
            d.translateBy(x: origen.x, y: origen.y)
            d.scaleBy(x: s, y: s)
            for e in esferas {
                let caja = CGRect(x: e.x, y: e.y, width: e.d, height: e.d)
                let disco = Path(ellipseIn: caja)
                if let sombra = e.sombra {
                    d.drawLayer { capa in
                        capa.addFilter(.shadow(color: sombra.color, radius: sombra.radio, x: sombra.x, y: sombra.y, options: [.shadowOnly]))
                        capa.fill(disco, with: .color(.black))
                    }
                }
                let centro = CGPoint(x: e.x + e.centro.x * e.d, y: e.y + e.centro.y * e.d)
                let lejos = hypot(max(e.centro.x, 1 - e.centro.x) * e.d, max(e.centro.y, 1 - e.centro.y) * e.d)
                d.fill(disco, with: .radialGradient(Gradient(stops: e.paradas), center: centro, startRadius: 0, endRadius: lejos))
                if !tema.esOscuro { d.stroke(disco, with: .color(.white.opacity(0.9)), lineWidth: 1) }
            }
            // Luz de la paleta en las esquinas de abajo (pantalla en oscuro, multiplicada en claro).
            var luz = d
            luz.blendMode = tema.esOscuro ? .screen : .multiply
            luz.opacity = tema.esOscuro ? 0.85 : 0.55
            let b = tema.esOscuro ? paleta.tonoB.opacity(0.60) : mezclar(paleta.b, 0.55)
            let a = tema.esOscuro ? paleta.tonoA.opacity(0.75) : mezclar(paleta.a, 0.30)
            luz.drawLayer { capa in
                let w = AuroraMedida.anchoMaqueta, h = AuroraMedida.alturaMaqueta
                for (color, rx, ry, cx, cy) in [(b, 0.48, 0.55, 0.88, 0.96), (a, 0.45, 0.55, 0.06, 1.0)] {
                    var l = capa
                    l.translateBy(x: cx * w, y: cy * h)
                    l.scaleBy(x: rx * w, y: ry * h)
                    l.fill(Path(CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                        Gradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: 0.70)]),
                        center: .zero, startRadius: 0, endRadius: 1))
                }
            }
        }
        .overlay { GranoAurora() }
        .accessibilityHidden(true)
    }
}

/// Grano fino: una baldosa de ruido en gris, con mezcla "overlay" y opacidad de la ficha.
struct GranoAurora: View {
    static let baldosa: CGImage? = {
        let lado = 256
        var datos = [UInt8](repeating: 255, count: lado * lado * 4)
        var semilla: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<(lado * lado) {
            semilla = semilla &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: semilla >> 56)
            datos[i * 4] = v; datos[i * 4 + 1] = v; datos[i * 4 + 2] = v
        }
        return datos.withUnsafeMutableBytes { crudo in
            CGContext(data: crudo.baseAddress, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }()

    var body: some View {
        if let baldosa = Self.baldosa {
            Image(decorative: baldosa, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(AuroraEfecto.grano)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Estados de un botón

/// El estado pulsado, el deshabilitado y el foco de teclado de todo botón de Aurora: al pulsar baja a 0,97 y 78 % de opacidad (150 ms,
/// sin rebote; con "Reducir movimiento", solo la opacidad); deshabilitado, al 40 %; con el foco del teclado, un anillo de 2 pt en el azul
/// de selección, 2 pt por fuera del control (el radio del control se pasa en `radio`; el anillo es concéntrico).
struct PulsadoAurora: ButtonStyle {
    var radio: CGFloat = AuroraFoco.radioPorDefecto
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.isEnabled) private var activo
    @Environment(\.isFocused) private var enfocado

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(activo ? (configuration.isPressed ? AuroraMovimiento.pulsadoOpacidad : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !sinMovimiento ? AuroraMovimiento.pulsadoEscala : 1)
            .animation(AuroraMovimiento.pulsado, value: configuration.isPressed)
            .anilloDeFoco(enfocado && activo, radio: radio)
    }
}

/// El anillo de foco de teclado de Aurora: 2 pt, azul de selección, separado 2 pt del control y concéntrico con su radio.
enum AuroraFoco {
    static let grosor: CGFloat = 2
    static let separacion: CGFloat = 2
    static let radioPorDefecto: CGFloat = 12
    static let color = AuroraAcento.seleccion
}

extension View {
    /// Dibuja el anillo de foco cuando `activo`; no cambia la medida ni el orden del diseño.
    func anilloDeFoco(_ activo: Bool, radio: CGFloat = AuroraFoco.radioPorDefecto) -> some View {
        overlay {
            if activo {
                RoundedRectangle(cornerRadius: radio + AuroraFoco.separacion, style: .continuous)
                    .strokeBorder(AuroraFoco.color, lineWidth: AuroraFoco.grosor)
                    .padding(-(AuroraFoco.grosor + AuroraFoco.separacion))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Botón circular

struct BotonCircularAurora: View {
    let simbolo: String
    let ayuda: String
    let accion: () -> Void
    @Environment(\.auroraTema) private var tema
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: AuroraMedida.botonIcono, weight: .regular))
                .foregroundStyle(tema.textoPleno)
                .frame(width: AuroraMedida.botonCircular, height: AuroraMedida.botonCircular)
                .vidrioAuroraCirculo()
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora(radio: AuroraMedida.botonCircular / 2))
        .scaleEffect(encima && !sinMovimiento ? AuroraMovimiento.punteroEscala : 1)
        .animation(AuroraMovimiento.puntero, value: encima)
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

// MARK: - Icono de app

enum TratamientoIcono: String, CaseIterable { case oscuro, cristal, tenido }

/// El mosaico de Aurora con sus tres tratamientos: oscuro (negro, glifo a color), cristal (vidrio claro, glifo a color)
/// y teñido (vidrio, glifo en un tono de la paleta). Sin vidrio nativo por icono: el cristal es un relleno translúcido.
/// Los iconos reales de las apps NO llevan mosaico (van a 70 con sombra suave); el mosaico es para carpetas y glifos propios.
struct MosaicoIcono<Glifo: View>: View {
    var lado: CGFloat = AuroraMedida.icono
    var tratamiento: TratamientoIcono = .oscuro
    @ViewBuilder var glifo: () -> Glifo
    @Environment(\.auroraTema) private var tema
    @Environment(\.auroraPaleta) private var paleta

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: lado * AuroraMedida.iconoRadioProporcion, style: .continuous)
        glifo()
            .foregroundStyle(tratamiento == .tenido ? paleta.tonoB : tema.textoPleno)
            .frame(width: lado, height: lado)
            .background(forma.fill(tratamiento == .oscuro ? tema.mosaico : tema.vidrioFuerte))
            .overlay(forma.strokeBorder(LinearGradient(colors: [tema.bordeArriba, tema.bordeAbajo], startPoint: .top, endPoint: .bottom),
                                        lineWidth: AuroraEfecto.bordeGrosor))
    }
}

/// La píldora de "app abierta": 10 × 3, texto pleno al 60 %.
struct IndicadorAbierta: View {
    @Environment(\.auroraTema) private var tema

    var body: some View {
        Capsule().fill(tema.textoPleno.opacity(0.6))
            .frame(width: AuroraMedida.indicadorAbierta.width, height: AuroraMedida.indicadorAbierta.height)
    }
}

// MARK: - El notch abierto: tokens

/// Medidas, colores y letra del panel abierto de la isla (sección 9 de AURORA.md; el CSS de la galería es la fuente).
/// Las medidas que también fijan el tamaño de la ventana viven en `MedidasNotch` (DictadoKit).
enum AuroraNotch {
    static let ancho = CGFloat(MedidasNotch.anchoIdeal)
    static let relleno = CGFloat(MedidasNotch.relleno)
    static let radioPanel = CGFloat(MedidasNotch.radioInferior)
    static let altoTarjeta = CGFloat(MedidasNotch.alturaTarjetas)
    static let separacion = CGFloat(MedidasNotch.separacion)
    static let altoPildora = CGFloat(MedidasNotch.alturaPestanas)
    static let radioTarjeta: CGFloat = 18
    static let radioPieza: CGFloat = 16
    static let radioIcono: CGFloat = 13
    static let rellenoTarjeta = EdgeInsets(top: 12, leading: 13, bottom: 11, trailing: 13)
    static let rellenoPieza = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    static let altoBoton: CGFloat = 28
    static let altoBotonCompacto: CGFloat = 24
    static let botonCompactoFuente = Font.system(size: 10.5, weight: .bold)
    static let anchoReunion: CGFloat = 236
    static let anchoTarea: CGFloat = 246
    static let anchoAgente: CGFloat = 232
    static let anchoResumen: CGFloat = 190
    static let anchoMusica: CGFloat = 300
    /// La música sin nada sonando: solo la acción de Spotify. El ancho que sobra pasa al lanzador de apps.
    static let anchoMusicaCompacta: CGFloat = 96
    /// La reunión en Inicio (algo más angosta que en las otras pestañas para dar espacio a las apps).
    static let anchoReunionInicio: CGFloat = 200
    /// El lanzador de Inicio (espacios, apps, carpetas y atajos).
    static let anchoApps: CGFloat = 330
    static let separacionApps: CGFloat = 6
    static let columnasLanzador = 4
    static let filasLanzador = 2
    static let altoChip: CGFloat = 20
    static let radioChip: CGFloat = 10
    static let iconoMosaico: CGFloat = 34
    /// Una carpeta muestra hasta cuatro iconos (2 × 2) de este tamaño.
    static let iconoMini: CGFloat = 20
    static let separacionMini: CGFloat = 4
    /// Con el lanzador ancho (la música compacta) caben cinco columnas.
    static let columnasLanzadorAncho = 5
    static let anchoLanzadorAncho: CGFloat = 400
    static let etiquetaApp = Font.system(size: 9.5, weight: .medium)
    static let rotuloMosaico = Font.system(size: 8.5, weight: .semibold)
    static let chipFuente = Font.system(size: 9.5, weight: .semibold)

    // Colores
    static let superficie = Color(hex: 0x111114)
    static let filo = Color.white.opacity(0.07)
    static let suave = Color.white.opacity(0.58)
    static let sutil = Color.white.opacity(0.5)
    static let resumen = Color.white.opacity(0.82)
    static let pildora = Color.white.opacity(0.12)
    static let botonVidrio = Color.white.opacity(0.2)
    static let botonOscuro = Color.white.opacity(0.14)
    static let rojoHoy = Color(hex: 0xFF3B30)

    // Letra
    static let pildoraFuente = Font.system(size: 11, weight: .bold)
    static let titulo = Font.system(size: 16, weight: .semibold)
    static let tituloTarea = Font.system(size: 14, weight: .semibold)
    static let resumenFuente = Font.system(size: 11, weight: .medium)
    static let cita = Font.system(size: 10.5, weight: .medium).italic()
    static let botonFuente = Font.system(size: 11.5, weight: .bold)
    static let rotuloFuente = Font.system(size: 7.5, weight: .semibold)
    static let rotuloInterletra: CGFloat = 7.5 * 0.11
    static let fila = Font.system(size: 10.5, weight: .medium)
    static let cifraGrande = Font.system(size: 36, weight: .ultraLight)
    static let cifraMediana = Font.system(size: 30, weight: .ultraLight)

    // Luz de la tarjeta de aura
    static let auraDesenfoque: CGFloat = 20
    static let auraExceso: CGFloat = 1.36   // el CSS la dibuja con inset −18 %
    static let orbeLado: CGFloat = 84
    static let orbeDesenfoque: CGFloat = 9

    // Avisos de la isla (las actividades que salen debajo del notch): mismo idioma que la pestaña Mac
    static let orbeAlerta: CGFloat = 62
    static let rellenoAlerta: CGFloat = 26
    static let separacionAlerta: CGFloat = 14
    static let alertaFuente = Font.system(size: 12.5, weight: .semibold)
    static let alertaApoyo = Font.system(size: 10.5, weight: .medium)
    static let auraAlertaOpacidad = 0.85
    /// Cuánto sube el aura de un aviso desde el borde de abajo (fracción del alto).
    static let auraAlertaAlto: CGFloat = 0.95
}

// MARK: - El Dock: tokens

/// Medidas, colores y letra del Dock (sección 6 de AURORA.md y el CSS `.dock` / `.pz` de la galería). Las medidas que también
/// fijan el reparto del ancho viven en `MedidasDock` (DictadoKit).
enum AuroraDock {
    static let alto = CGFloat(MedidasDock.alto)
    static let radio = CGFloat(MedidasDock.radio)
    static let margenInferior = CGFloat(MedidasDock.margenInferior)
    static let relleno = CGFloat(MedidasDock.relleno)
    static let rellenoInferior: CGFloat = 11
    static let piezaAlto = CGFloat(MedidasDock.alturaPieza)
    static let piezaRadio: CGFloat = 16
    static let separacion = CGFloat(MedidasDock.separacion)
    /// Aire transparente a cada lado de la barra para la sombra (la ventana no pasa de aquí).
    static let margenSombra: CGFloat = 24
    static let sombra = (radio: CGFloat(18), y: CGFloat(10), opacidad: 0.40)

    // Acabado de la barra
    static let desenfoque: CGFloat = 36
    static let hondoOpacidad = 0.84
    static let filo = Color.white.opacity(0.10)
    static let polvoOpacidad = 0.55
    static let rayaArriba: CGFloat = 13
    static let rayaAbajo: CGFloat = 11

    // Pieza
    static let piezaArriba = Color(hex: 0x101013)
    static let piezaAbajo = Color(hex: 0x050506)
    static let piezaFilo = Color.white.opacity(0.05)
    static let piezaLuzArriba = Color.white.opacity(0.10)
    static let piezaSombra = (radio: CGFloat(3), y: CGFloat(2), opacidad: 0.40)
    static let luzExceso: CGFloat = 8
    static let luzDesenfoque: CGFloat = 7
    /// El Dock es una barra oscura al 84 % sea cual sea el fondo: con estas opacidades el texto chico pasa 4,5:1 (calculado sobre el peor fondo: la barra encima de blanco).
    static let textoSuave = Color.white.opacity(0.62)
    static let textoTenue = Color.white.opacity(0.54)

    // Selector de espacios
    static let selectorAlto = CGFloat(MedidasDock.selectorAlto)
    static let selectorChip = CGFloat(MedidasDock.selectorChip)
    static let selectorSeparacion = CGFloat(MedidasDock.selectorSeparacion)
    static let chipFuente = Font.system(size: 12, weight: .bold)
    static let chipActivo = Color.white.opacity(0.30)
    static let chipReposo = Color.black.opacity(0.42)

    // Letra
    static let rotulo = Font.system(size: 7.5, weight: .semibold)
    static let rotuloInterletra: CGFloat = 7.5 * 0.11
    static let cifraGrande = Font.system(size: 36, weight: .ultraLight)
    static let cifraMedia = Font.system(size: 30, weight: .ultraLight)
    static let cifraPequena = Font.system(size: 9, weight: .semibold)
    static let titulo = Font.system(size: 13, weight: .semibold)
    static let detalle = Font.system(size: 10.5, weight: .medium)
    static let tecla = Font.system(size: 7.5, weight: .semibold)
    static let tiempos = Font.system(size: 8.5, weight: .semibold)

    // Iconos y botones
    static let icono: CGFloat = 56
    static let indicador = CGSize(width: 12, height: 3)   // grid: ok píldora del Dock de la maqueta (12 × 3), deliberada
    static let indicadorBajo: CGFloat = 8
    static let insignia: CGFloat = 40
    static let insigniaChica: CGFloat = 32
    static let botonVidrio: CGFloat = 27
    static let miniGrupo: CGFloat = 13
    static let miniGrupoSeparacion: CGFloat = 4
    static let orbeMac: CGFloat = 52
    static let orbeBateria: CGFloat = 54
    static let verde = AuroraAcento.bien

    // Carpeta del Finder (vidrio esmerilado, la proporción de las referencias: 406 × 312)
    static let carpeta = CGSize(width: 70, height: 70 * 312 / 406)

    // Panel desplegable (carpeta o grupo)
    static let panelRadio: CGFloat = 30
    static let panelRelleno: CGFloat = 14
    static let panelColumnas = CarpetaDock.columnas
    static let celdaAncho: CGFloat = 88
    static let celdaAlto: CGFloat = 98
    static let miniatura: CGFloat = 56
    static let miniaturaRadio: CGFloat = 10
    static let nombreArchivo = Font.system(size: 10.5, weight: .medium)
    static let panelSeparacion: CGFloat = 8
    static let panelSombra = (radio: CGFloat(20), y: CGFloat(12), opacidad: 0.40)
    static let panelMargen: CGFloat = 28

    // Borde de pantalla que despierta al Dock
    static let bordeAlto: CGFloat = 3
    static let bordeAnchoMax: CGFloat = 720

    static func anchoPanel() -> CGFloat {
        CGFloat(CarpetaDock.columnas) * celdaAncho + 2 * panelRelleno
    }
}

/// Los dos colores de una tarjeta de aura (`--t` y `--t2` del CSS).
struct TonoAura: Equatable {
    let t: UInt32
    let t2: UInt32

    /// Rojo: espera tu respuesta.
    static let espera = TonoAura(t: 0xB3261E, t2: 0xFF6A4A)
    /// Azul: trabaja, o la próxima reunión.
    static let trabaja = TonoAura(t: 0x3A3FB8, t2: 0x8FA6FF)
    static let reunion = TonoAura(t: 0x1F3FA8, t2: 0x86A8FF)
    /// Rojo con violeta: la tarjeta de agentes de Inicio cuando hay algo que decidir.
    static let agentes = TonoAura(t: 0xA8321E, t2: 0xC05CFF)
    /// Ámbar: un agente remoto con alerta.
    static let alerta = TonoAura(t: 0xA85A12, t2: 0xFFC24A)
    static let verde = TonoAura(t: 0x0F5A3A, t2: 0x5FE0A0)
    /// Naranja de Claude.
    static let claude = TonoAura(t: 0xB4491F, t2: 0xFF9A6B)

    /// El tono de una carátula o de un color de calendario: el color y su versión aclarada.
    static func de(_ color: Color) -> TonoAura {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        func hex(_ c: NSColor) -> UInt32 {
            let r = UInt32((c.redComponent * 255).rounded()), g = UInt32((c.greenComponent * 255).rounded()), bl = UInt32((c.blueComponent * 255).rounded())
            return (r << 16) | (g << 8) | bl
        }
        let base = NSColor(hue: h, saturation: min(1, max(0.5, s * 1.1)), brightness: max(0.55, min(0.75, b)), alpha: 1).usingColorSpace(.deviceRGB) ?? ns
        let claro = NSColor(hue: h, saturation: min(1, max(0.35, s * 0.7)), brightness: 1, alpha: 1).usingColorSpace(.deviceRGB) ?? ns
        return TonoAura(t: hex(base), t2: hex(claro))
    }

    var base: Color { mezclar(t, 0.30, con: 0x09090C) }
    var luz: Color { Color(hex: t) }
    var luz2: Color { Color(hex: t2) }
    /// El rótulo toma el segundo color aclarado (`color-mix(t2 45%, white)`).
    var rotulo: Color { mezclar(t2, 0.45) }
    /// Texto secundario de las filas: `color-mix(t2 40%, white)`.
    var dato: Color { mezclar(t2, 0.40) }
}

// MARK: - El notch abierto: superficies

/// Tarjeta de aura: fondo del color del estado con tres manchas de luz difusa detrás, filo de luz y el contenido encima.
/// Estática: se dibuja una vez y no se anima (ni siquiera mientras la isla está abierta).
struct TarjetaAura<Contenido: View>: View {
    let tono: TonoAura
    var ancho: CGFloat?
    var radio = AuroraNotch.radioTarjeta
    var relleno = AuroraNotch.rellenoTarjeta
    @ViewBuilder var contenido: () -> Contenido

    @Environment(\.altoTarjetaAura) private var alto

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        contenido()
            .padding(relleno)
            .frame(width: ancho, height: alto, alignment: .topLeading)
            .frame(maxHeight: alto == nil ? .infinity : nil)
            .frame(maxWidth: ancho == nil ? .infinity : nil)
            .background { ZStack { forma.fill(tono.base); LuzAura(tono: tono).clipShape(forma) } }
            .overlay { forma.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
            .overlay { forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)), lineWidth: 1) }
            .clipShape(forma)
            .foregroundStyle(.white)
    }
}

/// Las tres manchas del aura (CSS `.aura::before`): elipses con degradado radial, desenfocadas.
struct LuzAura: View {
    let tono: TonoAura

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * AuroraNotch.auraExceso, h = g.size.height * AuroraNotch.auraExceso
            Canvas { ctx, tam in
                let manchas: [(rx: Double, ry: Double, cx: Double, cy: Double, color: Color)] = [
                    (0.34, 0.44, 0.62, 0.42, mezclar(tono.t2, 0.80)),
                    (0.46, 0.62, 0.38, 0.74, tono.luz),
                    (0.40, 0.55, 0.92, 0.96, mezclar(tono.t2, 0.70, con: 0x000000)),
                ]
                for m in manchas {
                    var c = ctx
                    c.translateBy(x: tam.width * m.cx, y: tam.height * m.cy)
                    c.scaleBy(x: tam.width * m.rx, y: tam.height * m.ry)
                    c.fill(Path(CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                        Gradient(stops: [.init(color: m.color, location: 0), .init(color: m.color.opacity(0), location: 0.72)]),
                        center: .zero, startRadius: 0, endRadius: 1))
                }
            }
            .frame(width: w, height: h)
            .blur(radius: AuroraNotch.auraDesenfoque)
            .opacity(0.95)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tarjeta oscura (`.ag.oscura`): gris casi negro con filo. Sin aura: para tareas, la agenda y lo que no tiene estado.
struct TarjetaOscura<Contenido: View>: View {
    var ancho: CGFloat?
    var radio = AuroraNotch.radioTarjeta
    var relleno = AuroraNotch.rellenoTarjeta
    @ViewBuilder var contenido: () -> Contenido

    @Environment(\.altoTarjetaAura) private var alto

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        contenido()
            .padding(relleno)
            .frame(width: ancho, height: alto, alignment: .topLeading)
            .frame(maxHeight: alto == nil ? .infinity : nil)
            .frame(maxWidth: ancho == nil ? .infinity : nil)
            .background { forma.fill(LinearGradient(colors: [Color(hex: 0x131316), Color(hex: 0x070708)], startPoint: .top, endPoint: .bottom)) }
            .overlay { forma.strokeBorder(.white.opacity(0.06), lineWidth: 1) }
            .overlay { forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)), lineWidth: 1) }
            .clipShape(forma)
            .foregroundStyle(.white)
    }
}

/// Pieza plana del notch (`.lz`): #111114 con filo al 7 %. Para la música (con la carátula detrás) y las apps.
struct PiezaNotch: ViewModifier {
    var radio = AuroraNotch.radioPieza

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        content
            .background { forma.fill(AuroraNotch.superficie) }
            .overlay { forma.strokeBorder(AuroraNotch.filo, lineWidth: 1) }
            .clipShape(forma)
    }
}

extension View {
    func piezaNotch(radio: CGFloat = AuroraNotch.radioPieza) -> some View { modifier(PiezaNotch(radio: radio)) }
}

// MARK: - El notch abierto: rótulo, botones, pestañas, segmentado

/// Rótulo de pieza: mayúsculas muy pequeñas con espaciado, en el tono de la pieza.
struct RotuloPieza: View {
    let texto: String
    var color = AuroraNotch.sutil
    /// El rótulo a la medida del Centro a pantalla completa (12 en vez de 7,5).
    var grande = false

    init(_ texto: String, color: Color = AuroraNotch.sutil, grande: Bool = false) {
        self.texto = texto
        self.color = color
        self.grande = grande
    }

    var body: some View {
        Text(texto.uppercased())
            .font(grande ? AuroraCentro.rotulo : AuroraNotch.rotuloFuente)
            .tracking(grande ? AuroraCentro.rotuloInterletra : AuroraNotch.rotuloInterletra)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Botón en píldora de las tarjetas: `lleno` (blanco con texto oscuro, la acción principal), `vidrio` (sobre un aura),
/// `oscuro` (sobre una tarjeta oscura) y `verde`. `redondo` lo deja en círculo con solo el ícono.
struct BotonAura: View {
    enum Estilo { case lleno, vidrio, oscuro, verde }
    var titulo: String?
    var icono: String?
    var estilo = Estilo.vidrio
    var redondo = false
    var color: Color?
    /// El botón a la medida del Centro a pantalla completa (38 de alto, letra de 14,5).
    var grande = false
    /// Más angosto (relleno de 8, letra de 10,5, 24 de alto): para las tarjetas de 150 puntos.
    var compacto = false
    let ayuda: String
    let accion: () -> Void
    @State private var encima = false

    init(_ titulo: String? = nil, icono: String? = nil, estilo: Estilo = .vidrio, redondo: Bool = false, color: Color? = nil,
         grande: Bool = false, compacto: Bool = false, ayuda: String? = nil, accion: @escaping () -> Void) {
        self.compacto = compacto
        self.titulo = titulo
        self.icono = icono
        self.estilo = estilo
        self.redondo = redondo
        self.color = color
        self.grande = grande
        self.ayuda = ayuda ?? titulo ?? ""
        self.accion = accion
    }

    var body: some View {
        let alto = grande ? AuroraCentro.altoBoton : (compacto ? AuroraNotch.altoBotonCompacto : AuroraNotch.altoBoton)
        Button(action: accion) {
            HStack(spacing: grande ? 8 : (compacto ? 4 : 4)) {
                if let icono { Image(systemName: icono).font(.system(size: grande ? 14 : (redondo ? 11 : (compacto ? 10 : 12)), weight: .bold)) }
                if let titulo {
                    Text(titulo).font(grande ? AuroraCentro.botonFuente : (compacto ? AuroraNotch.botonCompactoFuente : AuroraNotch.botonFuente)).lineLimit(1)
                }
            }
            .foregroundStyle(primerPlano)
            .padding(.horizontal, redondo ? 0 : (grande ? 16 : (compacto ? 8 : 12)))
            .frame(width: redondo ? alto : nil, height: alto)
            .background { Capsule().fill(fondo) }
            .overlay { if encima { Capsule().fill(estilo == .lleno ? Color.black.opacity(0.06) : Color.white.opacity(0.10)) } }
            .overlay { if estilo == .vidrio || estilo == .oscuro { Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center), lineWidth: 1) } }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }

    private var primerPlano: Color {
        switch estilo {
        case .lleno: return Color(hex: 0x111111)
        case .verde: return Color(hex: 0x04210F)
        default: return color ?? .white
        }
    }

    private var fondo: Color {
        switch estilo {
        case .lleno: return .white
        case .verde: return AuroraAcento.bien
        case .vidrio: return AuroraNotch.botonVidrio
        case .oscuro: return AuroraNotch.botonOscuro
        }
    }
}

/// Pestaña en píldora de 26: la activa blanca con texto negro; las demás, blanco al 12 %.
struct PildoraNotch: View {
    let titulo: String
    var cuenta = 0
    var acentoCuenta: Color?
    let activa: Bool
    let accion: () -> Void

    @State private var encima = false
    @State private var apretada = false

    var body: some View {
        HStack(spacing: 4) {
            Text(titulo)
            if cuenta > 0 { Text("\(cuenta)").foregroundStyle(activa ? Color.black.opacity(0.55) : (acentoCuenta ?? AuroraNotch.suave)) }
        }
        .font(AuroraNotch.pildoraFuente)
        .foregroundStyle(activa ? Color.black : (encima ? Color.white : AuroraNotch.suave))
        .padding(.horizontal, 8)
        .frame(minWidth: AuroraNotch.altoPildora, minHeight: AuroraNotch.altoPildora, maxHeight: AuroraNotch.altoPildora)
        .background { Capsule().fill(activa ? Color.white : AuroraNotch.pildora.opacity(encima ? 1.9 : 1)) }
        .overlay { Capsule().strokeBorder(Color.white.opacity(activa ? 0 : (encima ? 0.22 : 0.06)), lineWidth: 0.5) }
        .scaleEffect(apretada ? 0.96 : 1)
        .fixedSize()
        // El blanco del clic es más alto que la píldora (llega al borde de la isla y a las tarjetas): es fácil de acertar.
        .padding(.vertical, 4).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .padding(.vertical, -4).padding(.horizontal, -4)
        .onHover { encima = $0 }
        // Cambia al apretar, no al soltar: responde al instante y no depende de que nada se redibuje entre medias.
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !apretada else { return }
                apretada = true
                accion()
            }
            .onEnded { _ in apretada = false })
        .animation(.easeOut(duration: 0.12), value: encima)
        .animation(.easeOut(duration: 0.1), value: apretada)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titulo + (cuenta > 0 ? ", \(cuenta)" : ""))
        .accessibilityAddTraits(activa ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { accion() }
    }
}

/// Botón de la barra de arriba (micrófono, ajustes): píldora de 26 con un ícono.
struct IconoPildoraNotch: View {
    let simbolo: String
    let ayuda: String
    var tinte: Color?
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tinte ?? AuroraNotch.suave)
                .frame(width: AuroraNotch.altoPildora, height: AuroraNotch.altoPildora)
                .background { Circle().fill(AuroraNotch.pildora) }
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora(radio: AuroraNotch.altoPildora / 2))
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }
}

/// Control segmentado (Hoy · Semana · Próxima): el elegido en blanco al 20 %.
struct SegmentadoAurora: View {
    let opciones: [String]
    let elegida: Int
    var grande = false
    let elegir: (Int) -> Void

    init(opciones: [String], elegida: Int, grande: Bool = false, elegir: @escaping (Int) -> Void) {
        self.opciones = opciones
        self.elegida = elegida
        self.grande = grande
        self.elegir = elegir
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(opciones.enumerated()), id: \.offset) { i, titulo in
                Button { elegir(i) } label: {
                    Text(titulo)
                        .font(.system(size: grande ? 14.5 : 9.5, weight: .semibold))
                        .foregroundStyle(i == elegida ? Color.white : Color.white.opacity(grande ? 0.62 : 0.55))
                        .padding(.horizontal, grande ? 16 : 8).padding(.vertical, grande ? 8 : 4)
                        .background { RoundedRectangle(cornerRadius: grande ? 12 : 8, style: .continuous).fill(i == elegida ? Color.white.opacity(0.2) : .clear) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PulsadoAurora(radio: grande ? 12 : 8))
                .accessibilityLabel(titulo)
                .accessibilityAddTraits(i == elegida ? .isSelected : [])
            }
        }
        .padding(2)
        .background { RoundedRectangle(cornerRadius: grande ? 16 : 12, style: .continuous).fill(Color.white.opacity(0.08)) }
    }
}

// MARK: - El notch abierto: luces desenfocadas y orbe

/// Las luces desenfocadas de un encargo que está pensando (CSS `.bokeh`): puntos blancos de varios tamaños. Estáticas.
struct BokehAurora: View {
    private static let puntos: [(x: Double, y: Double, r: Double, o: Double)] = [
        (0.06, 0.55, 4, 1), (0.15, 0.30, 3, 0.8), (0.27, 0.62, 5, 1), (0.36, 0.38, 3, 0.85), (0.47, 0.58, 4, 1),
        (0.58, 0.30, 3, 0.7), (0.70, 0.66, 4.5, 0.9), (0.82, 0.40, 3, 0.6), (0.94, 0.60, 3.5, 0.5),
    ]

    var body: some View {
        Canvas { ctx, tam in
            for p in Self.puntos {
                let c = CGPoint(x: tam.width * p.x, y: tam.height * p.y)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - p.r, y: c.y - p.r, width: 2 * p.r, height: 2 * p.r)), with: .color(.white.opacity(p.o)))
            }
        }
        .frame(height: 20)
        .blur(radius: 1.3)
        .opacity(0.95)
        .accessibilityHidden(true)
    }
}

/// Qué tono toma un orbe: calma (aura blanca) o atención (de color, según la gravedad de Salud).
enum TonoOrbe: Equatable {
    case calma, atento, mal

    var colores: (t: Color, t2: Color)? {
        switch self {
        case .calma: return nil
        case .atento: return (Color(hex: 0xFFB02E), Color(hex: 0xFF5A3C))
        case .mal: return (Color(hex: 0xFF3B30), Color(hex: 0xFF2D6F))
        }
    }
}

/// Orbe (sección 9): disco negro con cifra fina sobre un aura difusa, una órbita fina y un destello en el valor.
struct OrbeAurora: View {
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
                .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
            VStack(spacing: 1) {
                Text(titulo).font(.system(size: 6.5 * escala, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.8)
                Text(numero).font(.system(size: cifra, weight: .ultraLight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                if let unidad { Text(unidad).font(.system(size: 6.5 * escala, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1) }
            }
            .frame(width: lado * 0.5)
            Destello().fill(.white).frame(width: 9 * escala, height: 9 * escala) // grid: ok destello proporcional
                .shadow(color: .white, radius: 3)
                .offset(x: (lado / 2 - 5 * escala) * CGFloat(cos((giro - 90) * .pi / 180)), y: (lado / 2 - 5 * escala) * CGFloat(sin((giro - 90) * .pi / 180)))
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

// MARK: - Avisos de la isla

/// El aura de un aviso: dos manchas difusas del tono (el color y su claro) que suben desde el borde de abajo, en vez de la luz
/// plana de antes. Estática.
struct AuraBorde: View {
    let tono: TonoAura
    var alto = AuroraNotch.auraAlertaAlto

    var body: some View {
        Canvas { ctx, tam in
            let manchas: [(rx: Double, ry: Double, cx: Double, cy: Double, color: Color)] = [
                (0.40, alto, 0.24, 1.02, tono.luz),
                (0.34, alto * 0.85, 0.78, 1.06, mezclar(tono.t2, 0.85)),
                (0.46, alto * 0.5, 0.52, 1.10, tono.luz2),
            ]
            for m in manchas {
                var c = ctx
                c.translateBy(x: tam.width * m.cx, y: tam.height * m.cy)
                c.scaleBy(x: tam.width * m.rx, y: tam.height * m.ry)
                c.fill(Path(CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                    Gradient(stops: [.init(color: m.color, location: 0), .init(color: m.color.opacity(0), location: 0.72)]),
                    center: .zero, startRadius: 0, endRadius: 1))
            }
        }
        .blur(radius: AuroraNotch.auraDesenfoque)
        .opacity(AuroraNotch.auraAlertaOpacidad)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Un aviso de la isla en el idioma de la pestaña Mac: el rótulo en mayúsculas teñido que dice qué es, una frase, a la
/// izquierda lo que importa en grande (un orbe o una cuenta de puntos) y a la derecha las acciones en píldora, sobre un aura
/// del color del estado. Debajo del notch; el alto lo fija `EstadoIsla.tamano`.
struct AlertaAura<Medio: View, Acciones: View>: View {
    let notch: CGSize
    let tono: TonoAura
    let rotulo: String
    let frase: String
    var apoyo: String?
    @ViewBuilder var medio: () -> Medio
    @ViewBuilder var acciones: () -> Acciones

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: AuroraNotch.separacionAlerta) {
                medio()
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza(rotulo, color: tono.rotulo)
                    Text(frase).font(AuroraNotch.alertaFuente).foregroundStyle(.white).lineLimit(apoyo == nil ? 2 : 1)
                    if let apoyo {
                        Text(apoyo).font(AuroraNotch.alertaApoyo).foregroundStyle(AuroraNotch.resumen).lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                HStack(spacing: 4) { acciones() }
            }
            .padding(.horizontal, AuroraNotch.rellenoAlerta)
            .frame(maxHeight: .infinity)
        }
        .background { AuraBorde(tono: tono) }
        .foregroundStyle(.white)
    }
}

extension AlertaAura where Medio == EmptyView {
    init(notch: CGSize, tono: TonoAura, rotulo: String, frase: String, apoyo: String? = nil, @ViewBuilder acciones: @escaping () -> Acciones) {
        self.init(notch: notch, tono: tono, rotulo: rotulo, frase: frase, apoyo: apoyo, medio: { EmptyView() }, acciones: acciones)
    }
}

/// El minuto: se actualiza una vez al minuto (justo en el cambio de minuto) y solo mientras la isla está abierta. De
/// ahí salen las cuentas regresivas y la marca de "ahora" de la agenda; sin consultas en bucle.
@MainActor @Observable
final class RelojMinuto {
    var ahora = Date()
    @ObservationIgnored private var tarea: Task<Void, Never>?

    func iniciar() {
        detener()
        ahora = Date()
        tarea = Task { [weak self] in
            while !Task.isCancelled {
                let falta = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(falta + 0.05))
                guard !Task.isCancelled else { return }
                self?.ahora = Date()
            }
        }
    }

    func detener() {
        tarea?.cancel()
        tarea = nil
    }
}

// MARK: - El Centro a pantalla completa: medidas y piezas

/// Medidas, colores y letra del Centro a pantalla completa, para leerlo a un brazo de distancia (cuerpo de 15 o más, títulos de 26 y
/// cifras de 60; nada por debajo de 11,5). Las tarjetas son las mismas de la isla (`TarjetaAura`, `TarjetaOscura`), más grandes.
enum AuroraCentro {
    static let riel: CGFloat = 248
    static let margen: CGFloat = 24
    static let separacion: CGFloat = 16
    static let radio: CGFloat = 26
    static let relleno = EdgeInsets(top: 17, leading: 20, bottom: 17, trailing: 20)
    static let altoBoton: CGFloat = 38
    static let altoTarjeta: CGFloat = 164
    static let altoCabecera: CGFloat = 52
    static let cifra: CGFloat = 60
    /// La línea de resumen de arriba de cada sección: frase de 24 en una tarjeta baja.
    static let fraseResumen: CGFloat = 24
    static let altoResumen: CGFloat = 88
    static let orbe: CGFloat = 196

    static let titulo = Font.system(size: 26, weight: .semibold)
    static let tituloTarjeta = Font.system(size: 19, weight: .semibold)
    static let cuerpo = Font.system(size: 15, weight: .medium)
    static let detalle = Font.system(size: 15, weight: .regular)
    /// Las columnas de la Semana, que son angostas: 13 y nada menos de 11,5.
    static let denso = Font.system(size: 13, weight: .medium)
    static let minimo = Font.system(size: 11.5, weight: .medium)
    static let rotulo = Font.system(size: 12, weight: .semibold)
    static let rotuloInterletra: CGFloat = 12 * 0.11
    static let botonFuente = Font.system(size: 14.5, weight: .bold)

    static let resumen = Color.white.opacity(0.84)
    static let suave = Color.white.opacity(0.64)
    static let sutil = Color.white.opacity(0.52)
    static let linea = Color.white.opacity(0.10)
    static let verdeClaro = Color(.sRGB, red: 0.57, green: 0.92, blue: 0.64)
    static let azulBloque = Color(hex: 0x6F97FF)
}

/// Una tarjeta de aura a la medida del Centro. `alto` nil = flexible.
struct TarjetaAuraGrande<Contenido: View>: View {
    let tono: TonoAura
    var alto: CGFloat? = AuroraCentro.altoTarjeta
    @ViewBuilder var contenido: () -> Contenido

    var body: some View {
        TarjetaAura(tono: tono, radio: AuroraCentro.radio, relleno: AuroraCentro.relleno) { contenido().frame(maxWidth: .infinity, alignment: .topLeading) }
            .environment(\.altoTarjetaAura, alto)
    }
}

/// Una tarjeta de vidrio a la medida del Centro: deja ver el fondo de pantalla y lo tiñe lo justo para que el texto blanco pase AA (el vidrio
/// fuerte del tema oscuro más el velo del fondo). Con "Reducir transparencia", una superficie sólida tintada. `alto` nil = flexible.
struct TarjetaVidrioGrande<Contenido: View>: View {
    var alto: CGFloat? = AuroraCentro.altoTarjeta
    var relleno = AuroraCentro.relleno
    @ViewBuilder var contenido: () -> Contenido

    var body: some View {
        contenido()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(relleno)
            .frame(height: alto, alignment: .topLeading)
            .frame(maxHeight: alto == nil ? .infinity : nil)
            .vidrioAurora(radio: AuroraCentro.radio, fuerte: true)
            .environment(\.altoTarjetaAura, alto)
    }
}

/// Una cifra fina con su unidad en versalitas y su rótulo, al estilo de la pestaña Mac pero a 60. Si el dato no existe, no se dibuja:
/// quien la usa decide (`if let`), así no hay ceros inventados.
struct CifraAurora: View {
    let rotulo: String
    let numero: String
    var unidad = ""
    var tamano = AuroraCentro.cifra

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RotuloPieza(rotulo, color: AuroraCentro.suave, grande: true)
            HStack(alignment: .firstTextBaseline, spacing: tamano * 0.1) {
                Text(numero).font(.system(size: tamano, weight: .thin)).monospacedDigit().kerning(-tamano * 0.025)
                if !unidad.isEmpty {
                    Text(unidad.uppercased()).font(.system(size: max(12, tamano * 0.27), weight: .semibold)).opacity(0.58)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rotulo): \(numero)" + (unidad.isEmpty ? "" : " " + unidad))
    }
}

/// Una pastilla de texto (el espacio actual, una fuente, una cuenta): cápsula de vidrio claro con letra de 13.
struct ChipAurora: View {
    let texto: String
    var icono: String?
    var color: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let icono { Image(systemName: icono).font(.system(size: 12, weight: .semibold)) }
            Text(texto).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).frame(height: 28)
        .background { Capsule().fill(Color.white.opacity(0.12)) }
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }
        .fixedSize()
    }
}

/// Un elemento del riel de la izquierda: ícono, nombre y el atajo; el activo en blanco.
struct ItemRielAurora: View {
    let titulo: String
    let simbolo: String
    let atajo: String
    let activo: Bool
    var aviso = 0
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Image(systemName: simbolo).font(.system(size: 17, weight: .medium)).frame(width: 24)
                Text(titulo).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                if aviso > 0 {
                    Text("\(aviso)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(activo ? Color.white : Color.black)
                        .frame(minWidth: 24, minHeight: 24)
                        .background { Capsule().fill(activo ? Color.black.opacity(0.35) : Color.white) }
                } else {
                    Text(atajo).font(.system(size: 12, weight: .medium, design: .monospaced)).opacity(0.5)
                }
            }
            .foregroundStyle(activo ? Color.black : Color.white.opacity(encima ? 1 : 0.78))
            .padding(.horizontal, 12).frame(height: 48)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(activo ? Color.white : Color.white.opacity(encima ? 0.10 : 0)) }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .accessibilityLabel(titulo + (aviso > 0 ? ", \(aviso) pendientes" : ""))
        .accessibilityHint("Atajo \(atajo)")
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }
}

/// Una fila de lista que se puede elegir con el puntero o las flechas: resaltada si es la elegida.
struct FilaElegibleAurora<Contenido: View>: View {
    let elegida: Bool
    let accion: () -> Void
    var radio: CGFloat = 16
    var vertical: CGFloat = 12
    @ViewBuilder var contenido: () -> Contenido
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            contenido()
                .padding(.horizontal, 16).padding(.vertical, vertical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: radio, style: .continuous).fill(Color.white.opacity(elegida ? 0.16 : (encima ? 0.08 : 0))) }
                .overlay { RoundedRectangle(cornerRadius: radio, style: .continuous).strokeBorder(Color.white.opacity(elegida ? 0.30 : 0), lineWidth: 1) }
                .contentShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .accessibilityAddTraits(elegida ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Vida: la chispa de Claude, el pulso y la barra de avance

/// La chispa de Claude con vida: gira despacio mientras una sesión trabaja y late cuando una te espera. Solo se mueve mientras
/// está a la vista (la isla abierta) y en uno de esos dos estados; en cualquier otro, o con "Reducir movimiento", se dibuja una
/// vez y se queda quieta (sin consumo). La usan las tarjetas de agentes de Inicio y de la pestaña Agentes.
struct ChispaViva: View {
    enum Modo { case quieta, trabaja, espera }
    let modo: Modo
    var lado: CGFloat = 20
    var color = TonoAura.claude.luz2

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let anima = modo != .quieta && !sinMovimiento
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !anima)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let giro = anima && modo == .trabaja ? (t.truncatingRemainder(dividingBy: 7) / 7) * 360 : 0
            let latido = anima && modo == .espera ? 0.5 + 0.5 * sin(t * 2.4) : 0
            EstrellaClaude().fill(color)
                .rotationEffect(.degrees(giro))
                .scaleEffect(1 + 0.14 * latido)
                .shadow(color: color.opacity(modo == .quieta ? 0 : 0.30 + 0.45 * latido), radius: lado * 0.28)
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }
}

/// Un anillo que respira (opacidad y tamaño) alrededor de lo que te espera. Quieto, y sin gastar nada, cuando `activo` es falso o
/// con "Reducir movimiento".
struct AnilloLatido: View {
    let activo: Bool
    var lado: CGFloat
    var color = TonoAura.espera.luz2

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let anima = activo && !sinMovimiento
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !anima)) { ctx in
            let f = anima ? 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2.4) : 0.5
            Circle().strokeBorder(color.opacity(activo ? 0.15 + 0.4 * f : 0), lineWidth: 1.5)
                .frame(width: lado * (1 + 0.16 * f), height: lado * (1 + 0.16 * f))
        }
        .frame(width: lado * 1.16, height: lado * 1.16)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// La barra de avance punteada con perilla: lo escuchado en línea llena (con el color de la carátula), la perilla y lo que falta
/// en puntos. Tocar o arrastrar sobre ella busca ese punto: `alMover` con la fracción mientras arrastras y `alSoltar` al terminar.
struct BarraAvance: View {
    let fraccion: Double
    var color: Color = .white
    var puedeBuscar = true
    var alMover: (Double) -> Void = { _ in }
    var alSoltar: (Double) -> Void = { _ in }
    /// VoiceOver: ajustar ±10 s.
    var alAjustar: ((Int) -> Void)?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, x = w * max(0, min(1, fraccion)), medio = g.size.height / 2
            ZStack(alignment: .leading) {
                Path { p in
                    p.move(to: CGPoint(x: min(w, x + 6), y: medio))
                    p.addLine(to: CGPoint(x: w, y: medio))
                }
                .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.01, 4.2])) // grid: ok trazo punteado
                Capsule().fill(color).frame(width: max(2, x), height: 4).shadow(color: color.opacity(0.7), radius: 3)
                Circle().fill(.white).frame(width: 8, height: 8).shadow(color: color, radius: 4).offset(x: x - 4)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle().inset(by: -7))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in if puedeBuscar, w > 0 { alMover(max(0, min(1, v.location.x / w))) } }
                .onEnded { v in if puedeBuscar, w > 0 { alSoltar(max(0, min(1, v.location.x / w))) } })
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avance de la canción")
        .accessibilityValue("\(Int((max(0, min(1, fraccion)) * 100).rounded())) por ciento")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: alAjustar?(10)
            case .decrement: alAjustar?(-10)
            @unknown default: break
            }
        }
    }
}

// MARK: - El lanzador a pantalla completa: fondo, rejilla y esquina

/// El fondo con la imagen del Mac (`.pantalla .fondo` y `.velo` de la maqueta), la escala de la rejilla según la pantalla y la
/// esquina que lo abre. Las cifras de la maqueta (1440 × 900) son la medida de referencia.
enum AuroraLanzador {
    /// Desenfoque, saturación y exceso de la imagen (la maqueta: blur 5, saturate 1.1, inset −30).
    static let desenfoqueFondo: CGFloat = 5
    static let saturacionFondo = 1.1
    static let excesoFondo: CGFloat = 1.04
    /// El velo: oscuro de 0,50 a 0,20 (a 55 %) y 0,42; claro de 0,34 a 0,12.
    static let veloOscuro: [Gradient.Stop] = [.init(color: Color(.sRGB, red: 3 / 255, green: 6 / 255, blue: 16 / 255, opacity: 0.50), location: 0),
                                              .init(color: Color(.sRGB, red: 3 / 255, green: 6 / 255, blue: 16 / 255, opacity: 0.20), location: 0.55),
                                              .init(color: Color(.sRGB, red: 3 / 255, green: 6 / 255, blue: 16 / 255, opacity: 0.42), location: 1)]
    static let veloClaro: [Gradient.Stop] = [.init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0.12), location: 1)]
    /// El velo del tema con `refuerzo` más de opacidad en cada parada (0 = el del lanzador tal cual).
    static func velo(tema: AuroraTema, refuerzo: Double = 0) -> [Gradient.Stop] {
        let base = tema.esOscuro ? veloOscuro : veloClaro
        guard refuerzo > 0 else { return base }
        return base.map { parada in
            let c = NSColor(parada.color).usingColorSpace(.sRGB) ?? .black
            return Gradient.Stop(color: Color(.sRGB, red: c.redComponent, green: c.greenComponent, blue: c.blueComponent,
                                              opacity: min(1, c.alphaComponent + refuerzo)), location: parada.location)
        }
    }
    /// Mientras la imagen se lee (en otro hilo): un plano liso del tono del tema, sin parpadeo.
    static let planoOscuro = Color(hex: 0x0B0C10)
    static let planoClaro = Color(hex: 0xE9ECF2)

    /// La rejilla crece con la pantalla hasta que el ícono llegue a su máximo (96) y se encoge hasta el mínimo (48).
    static var escalaMin: CGFloat { AuroraMedida.iconoMin / AuroraMedida.icono }
    static var escalaMax: CGFloat { AuroraMedida.iconoMax / AuroraMedida.icono }
    /// Aire a los lados del lienzo y debajo de las páginas.
    static let margenLateral: CGFloat = 24
    /// Debajo de la rejilla: sin el Dock propio, un poco de aire; con él, su altura (barra, selector y separación) más aire.
    static let margenInferior: CGFloat = 36
    static var bandaDock: CGFloat { AuroraDock.alto + AuroraDock.margenInferior + AuroraDock.selectorSeparacion + AuroraDock.selectorAlto + 24 }
    /// Lo que ocupa arriba la barra del buscador y los espacios.
    static var altoBarra: CGFloat { AuroraMedida.busquedaTop + AuroraMedida.busquedaAlto + 10 + chipAlto + 22 }

    /// La ventana del lanzador, y los niveles de lo que debe verse por encima: la barra del Dock propio (para quedar a la vista) y la
    /// esquina que lo cierra.
    static let nivelVentana = NSWindow.Level.popUpMenu.rawValue
    static let nivelDock = nivelVentana + 1
    static let nivelEsquina = nivelVentana + 3
    /// El cuadrito de la esquina y cuánto debe quedarse el puntero.
    static let ladoEsquina: Double = 4

    /// Los chips de segmentos, espacios y ámbitos del lanzador: a pantalla completa se leen a 12, no a los 9,5 de la isla.
    static let chipFuente = Font.system(size: 12, weight: .semibold)
    static let chipAlto: CGFloat = 28

    // Selector del fondo
    static let selectorAncho: CGFloat = 288
    static let selectorRadio: CGFloat = 22
    static let selectorFila: CGFloat = 32
}

// MARK: Apertura del notch (mejoras-notch)

/// Un solo resorte continuo para que el notch se transforme en la isla abierta (y al revés): sin rebote perceptible
/// (amortiguación 0,92 → sobrepaso de 0,07 %), y el contenido entra después de que la forma ya creció.
enum AuroraApertura {
    /// La forma: crece del notch al panel y vuelve.
    static let forma = Animation.spring(response: 0.46, dampingFraction: 0.92)
    /// El contenido espera a que la forma haya recorrido una parte del camino y entra con un ease-out largo.
    static let retardoContenido = 0.14
    static let entradaContenido = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.34).delay(retardoContenido)
    /// Al cerrar, el contenido se va rápido para no quedar colgado fuera de la forma que se encoge.
    static let salidaContenido = Animation.easeOut(duration: 0.10)
    /// Con "reducir movimiento": solo un fundido, sin escala, sin desenfoque.
    static let sinMovimiento = Animation.easeOut(duration: 0.18)
    /// El desenfoque de entrada (pt) y el desplazamiento vertical (pt). Cortos: el desenfoque de una vista grande es caro.
    static let desenfoque: CGFloat = 6
    static let desplazamiento: CGFloat = 8
    /// Lo que se espera tras abrir para leer disco, agenda y uso: nada de eso compite con el primer segundo de la animación.
    static let esperaLecturas: Duration = .milliseconds(380)
}

/// Entrada del contenido de la isla abierta: fundido con un poco de desenfoque y 8 pt de subida; con `reducir`, solo fundido.
struct EntradaContenidoIsla: ViewModifier {
    let activo: Bool
    var reducir = false

    func body(content: Content) -> some View {
        content
            .opacity(activo ? 0 : 1)
            .blur(radius: activo && !reducir ? AuroraApertura.desenfoque : 0)
            .offset(y: activo && !reducir ? -AuroraApertura.desplazamiento : 0)
    }
}

// MARK: - Dock: mejoras de noviembre (fondo, reloj de tarjetas, pila de carpeta)

/// Tokens nuevos del Dock: el fondo sin ruido (vidrio con un degradado de la paleta y un filo de luz), el reloj de tarjetas y la
/// pila (abanico o cuadrícula) de una carpeta.
enum AuroraDockPila {
    // Fondo: vidrio + base + degradado de la paleta + filo de luz
    static let baseOpacidad = 0.62
    static let degradadoOpacidad = 0.20
    static let filoArriba = Color.white.opacity(0.34)
    static let filoAbajo = Color.white.opacity(0.07)
    static let luzInterior = Color.white.opacity(0.06)

    // Reloj de tarjetas
    static let tarjetaAncho: CGFloat = 58
    static let tarjetaAlto: CGFloat = 52
    static let tarjetaRadio: CGFloat = 8
    static let tarjetaSeparacion: CGFloat = 4
    static let tarjetaCifra = Font.system(size: 38, weight: .bold).width(.condensed)
    static let tarjetaPeriodo = Font.system(size: 7.5, weight: .bold)
    static let volteoIda = 0.16
    static let volteoVuelta = 0.20

    // Pila
    static let abanicoPaso: CGFloat = 56
    static let abanicoMiniatura: CGFloat = 48
    static let abanicoEtiquetaMax: CGFloat = 190
    static let abanicoAncho: CGFloat = 480
    static let abanicoCabecera: CGFloat = 40
    static let abanicoMargen: CGFloat = 20
    static let seleccion = Color.white.opacity(0.14)
    static let seleccionFilo = Color.white.opacity(0.45)

    static func altoAbanico(_ n: Int) -> CGFloat { abanicoCabecera + CGFloat(max(1, n)) * abanicoPaso + 2 * abanicoMargen }
}

// MARK: - Dock: lupa

/// Las medidas del efecto lupa del Dock (la curva y el 1,5 × están en `LupaDock`, DictadoKit).
enum AuroraDockLupa {
    /// Aire extra de la ventana de la barra: arriba, para lo que crece (1,5 × sobre piezas de 72 sobresale 36), y a los lados, para lo que se ensancha.
    static let aireArriba: CGFloat = 30
    static let aireLado: CGFloat = 48
    /// El puntero entra y sale con un suavizado; al moverse, un resorte corto lo sigue sin retraso apreciable.
    static let entrada = Animation.smooth(duration: 0.16)
    static let salida = Animation.smooth(duration: 0.22)
    static let seguir = Animation.interactiveSpring(response: 0.10, dampingFraction: 0.88)
}

// MARK: - Dock: ventanas por app

enum AuroraDockVentanas {
    static let ancho: CGFloat = 360
    static let relleno: CGFloat = 14
    static let cabecera: CGFloat = 30
    static let fila: CGFloat = 64
    static let filaPestana: CGFloat = 24
    static let separacion: CGFloat = 8
    static let miniatura = CGSize(width: 96, height: 60)
    static let altoMaximo: CGFloat = 520
}
